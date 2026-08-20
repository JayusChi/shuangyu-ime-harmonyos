use std::collections::BTreeSet;
use std::sync::{Arc, OnceLock};

use pinyin_syllable::all_syllables;

use crate::{ParseError, ParseResult, ParseStatus, ParsedSyllable, PhoneticParser, QueryIntent};

const ALPHABET_SIZE: usize = 26;
const MAX_PARSE_PATHS: usize = 32;

/// Per-update diagnostics for the bounded incremental lattice.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct QuanpinLatticeStats {
    pub raw_len: usize,
    pub generated_states: usize,
    pub retained_states: usize,
    pub reused_prefix_states: usize,
}

#[derive(Clone, Debug)]
struct TrieNode {
    children: [Option<usize>; ALPHABET_SIZE],
    terminal: bool,
}

impl TrieNode {
    fn new() -> Self {
        Self {
            children: [None; ALPHABET_SIZE],
            terminal: false,
        }
    }
}

/// Trie built from the maintained, normalized pinyin inventory.
#[derive(Clone, Debug)]
struct SyllableTrie {
    nodes: Vec<TrieNode>,
    max_syllable_len: usize,
}

impl SyllableTrie {
    fn from_inventory() -> Self {
        let mut trie = Self {
            nodes: vec![TrieNode::new()],
            max_syllable_len: 0,
        };
        for syllable in all_syllables() {
            trie.insert(syllable);
        }
        trie
    }

    fn insert(&mut self, syllable: &str) {
        self.max_syllable_len = self.max_syllable_len.max(syllable.len());
        let mut node_index = 0usize;
        for byte in syllable.bytes() {
            let letter_index = usize::from(byte - b'a');
            let next = match self.nodes[node_index].children[letter_index] {
                Some(index) => index,
                None => {
                    let index = self.nodes.len();
                    self.nodes.push(TrieNode::new());
                    self.nodes[node_index].children[letter_index] = Some(index);
                    index
                }
            };
            node_index = next;
        }
        self.nodes[node_index].terminal = true;
    }

    fn is_terminal(&self, input: &str) -> bool {
        if input.is_empty() {
            return false;
        }
        let mut node_index = 0usize;
        for byte in input.bytes() {
            if !byte.is_ascii_lowercase() {
                return false;
            }
            let Some(next) = self.nodes[node_index].children[usize::from(byte - b'a')] else {
                return false;
            };
            node_index = next;
        }
        self.nodes[node_index].terminal
    }

    fn is_prefix(&self, input: &str) -> bool {
        if input.is_empty() {
            return false;
        }
        let mut node_index = 0usize;
        for byte in input.bytes() {
            let letter_index = usize::from(byte - b'a');
            let Some(next) = self.nodes[node_index].children[letter_index] else {
                return false;
            };
            node_index = next;
        }
        self.nodes[node_index].children.iter().any(Option::is_some)
    }
}

fn shared_syllable_trie() -> Arc<SyllableTrie> {
    static TRIE: OnceLock<Arc<SyllableTrie>> = OnceLock::new();
    Arc::clone(TRIE.get_or_init(|| Arc::new(SyllableTrie::from_inventory())))
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct IncompletePath {
    syllables: Vec<String>,
    pending: String,
}

/// Stateful 26-key full-pinyin parser backed by a bounded incremental lattice.
/// Appends expand only the newest position and backspace restores cached prefix
/// states, so long compositions remain deterministic without full reparsing.
#[derive(Clone, Debug)]
pub struct QuanpinParser {
    trie: Arc<SyllableTrie>,
    raw_input: String,
    /// Complete-path states keyed by raw byte offset. Appending one ASCII key
    /// only expands the newest offset; backspace truncates this vector and
    /// therefore restores the exact previous lattice without reparsing.
    complete_paths: Vec<Vec<Vec<String>>>,
    current: ParseResult,
    stats: QuanpinLatticeStats,
}

impl Default for QuanpinParser {
    fn default() -> Self {
        Self::new()
    }
}

impl QuanpinParser {
    pub fn new() -> Self {
        Self {
            trie: shared_syllable_trie(),
            raw_input: String::new(),
            complete_paths: vec![vec![Vec::new()]],
            current: ParseResult::empty(),
            stats: QuanpinLatticeStats::default(),
        }
    }

    pub fn process_str(&mut self, input: &str) -> ParseResult {
        for key in input.chars() {
            self.append_key(key);
        }
        self.current.clone()
    }

    pub fn lattice_stats(&self) -> QuanpinLatticeStats {
        self.stats
    }

    fn append_key(&mut self, key: char) -> ParseResult {
        let previous_len = self.raw_input.len();
        self.raw_input.push(key);
        let end = self.raw_input.len();
        let mut generated_states = 0usize;
        let mut next_paths = Vec::new();

        if key == '\'' {
            if end == previous_len + 1 {
                next_paths = self.complete_paths[previous_len].clone();
                generated_states = next_paths.len();
            }
        } else if key.is_ascii_lowercase() && end == previous_len + 1 {
            let segment_start = self
                .raw_input
                .get(..previous_len)
                .and_then(|prefix| prefix.rfind('\''))
                .map_or(0, |index| index + 1);
            let earliest = segment_start.max(end.saturating_sub(self.trie.max_syllable_len));
            for start in earliest..end {
                let syllable = &self.raw_input[start..end];
                if !self.trie.is_terminal(syllable) {
                    continue;
                }
                for prefix in &self.complete_paths[start] {
                    let mut path = prefix.clone();
                    path.push(syllable.to_owned());
                    next_paths.push(path);
                    generated_states += 1;
                }
            }
            normalize_paths(&mut next_paths);
        }

        if end == previous_len + 1 {
            self.complete_paths.push(next_paths);
        } else {
            // Non-ASCII input is invalid, but retaining byte-offset alignment
            // lets one backspace restore the preceding valid lattice.
            self.complete_paths.resize_with(end + 1, Vec::new);
        }
        self.stats = QuanpinLatticeStats {
            raw_len: raw_letter_count(&self.raw_input),
            generated_states,
            retained_states: self.complete_paths[end].len(),
            reused_prefix_states: self.complete_paths[..end].iter().map(Vec::len).sum(),
        };
        self.refresh_current()
    }

    fn refresh_current(&mut self) -> ParseResult {
        self.current = result_from_lattice(&self.trie, &self.raw_input, &self.complete_paths);
        self.current.clone()
    }
}

impl PhoneticParser for QuanpinParser {
    type Error = ParseError;

    fn raw_input(&self) -> &str {
        &self.raw_input
    }

    fn process_key(&mut self, key: char) -> ParseResult {
        self.append_key(key)
    }

    fn process_str(&mut self, input: &str) -> ParseResult {
        QuanpinParser::process_str(self, input)
    }

    fn insert_segment_boundary(&mut self) -> Result<ParseResult, Self::Error> {
        if self.raw_input.is_empty()
            || self.raw_input.ends_with('\'')
            || !matches!(
                self.current.status,
                ParseStatus::Complete | ParseStatus::Ambiguous
            )
        {
            return Err(ParseError::InvalidSegmentBoundary);
        }
        Ok(self.append_key('\''))
    }

    fn backspace(&mut self) -> ParseResult {
        self.raw_input.pop();
        self.complete_paths.truncate(self.raw_input.len() + 1);
        self.stats = QuanpinLatticeStats {
            raw_len: raw_letter_count(&self.raw_input),
            generated_states: 0,
            retained_states: self.complete_paths.last().map_or(0, Vec::len),
            reused_prefix_states: self.complete_paths.iter().map(Vec::len).sum(),
        };
        self.refresh_current()
    }

    fn reset(&mut self) -> ParseResult {
        self.raw_input.clear();
        self.complete_paths.clear();
        self.complete_paths.push(vec![Vec::new()]);
        self.current = ParseResult::empty();
        self.stats = QuanpinLatticeStats::default();
        self.current.clone()
    }

    fn current_state(&self) -> ParseResult {
        self.current.clone()
    }
}

fn result_from_lattice(
    trie: &SyllableTrie,
    raw_input: &str,
    complete_paths: &[Vec<Vec<String>>],
) -> ParseResult {
    if raw_input.is_empty() {
        return ParseResult::empty();
    }
    if let Some(key) = raw_input
        .chars()
        .find(|key| *key != '\'' && !key.is_ascii_lowercase())
    {
        return invalid(raw_input, ParseError::InvalidKey { key }, Vec::new());
    }
    if raw_input.starts_with('\'') || raw_input.contains("''") {
        return invalid(raw_input, ParseError::InvalidSegmentBoundary, Vec::new());
    }

    let segment_boundaries = explicit_boundaries(raw_input);
    let end = raw_input.len();
    let complete = complete_paths.get(end).cloned().unwrap_or_default();
    if !complete.is_empty() {
        let terminal_prefix = !raw_input.contains('\'')
            && complete
                .first()
                .is_some_and(|path| path.len() == 1 && path[0] == raw_input)
            && trie.is_prefix(raw_input);
        return complete_result(raw_input, segment_boundaries, complete, terminal_prefix);
    }

    let segment_start = raw_input.rfind('\'').map_or(0, |index| index + 1);
    let mut partials = Vec::new();
    for start in segment_start..end {
        let pending = &raw_input[start..end];
        if !trie.is_prefix(pending) {
            continue;
        }
        for syllables in complete_paths.get(start).into_iter().flatten() {
            partials.push(IncompletePath {
                syllables: syllables.clone(),
                pending: pending.to_owned(),
            });
        }
    }

    // A suffix which is not itself a legal syllable prefix is still an
    // editable pending tail. Preserve the furthest complete boundary instead
    // of collapsing the entire composition to Invalid.
    if partials.is_empty() {
        let stable_end = (segment_start..=end)
            .rev()
            .find(|offset| {
                complete_paths
                    .get(*offset)
                    .is_some_and(|paths| !paths.is_empty())
            })
            .unwrap_or(segment_start);
        let pending = raw_input[stable_end..].to_owned();
        for syllables in complete_paths.get(stable_end).into_iter().flatten() {
            partials.push(IncompletePath {
                syllables: syllables.clone(),
                pending: pending.clone(),
            });
        }
    }

    partials.sort_by(|left, right| {
        left.pending
            .len()
            .cmp(&right.pending.len())
            .then_with(|| left.syllables.len().cmp(&right.syllables.len()))
            .then_with(|| left.syllables.cmp(&right.syllables))
    });
    partials.dedup();
    partials.truncate(MAX_PARSE_PATHS);
    if partials.is_empty() {
        return invalid(
            raw_input,
            ParseError::InvalidCode {
                code: raw_input.to_owned(),
            },
            segment_boundaries,
        );
    }
    incomplete_result(raw_input, segment_boundaries, partials)
}

fn raw_letter_count(raw_input: &str) -> usize {
    raw_input.bytes().filter(|byte| *byte != b'\'').count()
}

fn normalize_paths(paths: &mut Vec<Vec<String>>) {
    paths.sort_by(|left, right| left.len().cmp(&right.len()).then_with(|| left.cmp(right)));
    paths.dedup();
    paths.truncate(MAX_PARSE_PATHS);
}

fn complete_result(
    raw_input: &str,
    segment_boundaries: Vec<usize>,
    mut paths: Vec<Vec<String>>,
    terminal_prefix: bool,
) -> ParseResult {
    normalize_paths(&mut paths);
    let preferred = paths.first().cloned().unwrap_or_default();
    let syllables = parsed_syllables(&preferred);
    let logical_syllable_count = preferred.len();
    let current_pinyin = preferred.join("'");
    let pinyin_combinations = unique_combinations(paths.into_iter().skip(1));
    let status = if pinyin_combinations.is_empty() {
        ParseStatus::Complete
    } else {
        ParseStatus::Ambiguous
    };
    ParseResult {
        raw_input: raw_input.to_owned(),
        query_intent: if terminal_prefix {
            QueryIntent::SingleKeyPrefix
        } else if logical_syllable_count <= 1 {
            QueryIntent::CompleteSyllable
        } else {
            QueryIntent::MultiSyllable
        },
        status,
        syllables,
        logical_syllable_count,
        pending_code: String::new(),
        display_segments: preferred,
        segment_boundaries,
        current_pinyin,
        pinyin_combinations,
        error: None,
    }
}

fn incomplete_result(
    raw_input: &str,
    segment_boundaries: Vec<usize>,
    paths: Vec<IncompletePath>,
) -> ParseResult {
    let preferred = paths.first().cloned().expect("incomplete path exists");
    let logical_syllable_count = preferred.syllables.len();
    let mut display_segments = preferred.syllables.clone();
    display_segments.push(preferred.pending.clone());
    let current_pinyin = combination_with_pending(&preferred);
    let alternatives = paths
        .into_iter()
        .skip(1)
        .map(|path| combination_with_pending(&path));
    let pinyin_combinations = unique_strings(alternatives);
    ParseResult {
        raw_input: raw_input.to_owned(),
        query_intent: if logical_syllable_count == 0 {
            QueryIntent::SingleKeyPrefix
        } else if logical_syllable_count == 1 {
            QueryIntent::IncompleteSyllable
        } else {
            QueryIntent::MultiSyllable
        },
        status: ParseStatus::Incomplete,
        syllables: parsed_syllables(&preferred.syllables),
        logical_syllable_count,
        pending_code: preferred.pending,
        display_segments,
        segment_boundaries,
        current_pinyin,
        pinyin_combinations,
        error: None,
    }
}

fn parsed_syllables(values: &[String]) -> Vec<ParsedSyllable> {
    values
        .iter()
        .enumerate()
        .map(|(logical_index, syllable)| {
            let (initial, final_part) = split_initial(syllable);
            ParsedSyllable {
                logical_index,
                raw_code: syllable.clone(),
                syllable: syllable.clone(),
                initial,
                final_part,
                special_rule: false,
            }
        })
        .collect()
}

fn split_initial(syllable: &str) -> (String, String) {
    const INITIALS: [&str; 23] = [
        "zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x",
        "r", "z", "c", "s", "y", "w",
    ];
    for initial in INITIALS {
        if let Some(final_part) = syllable.strip_prefix(initial) {
            return (initial.to_owned(), final_part.to_owned());
        }
    }
    (String::new(), syllable.to_owned())
}

fn explicit_boundaries(raw_input: &str) -> Vec<usize> {
    let mut letter_offset = 0usize;
    let mut boundaries = Vec::new();
    for character in raw_input.chars() {
        if character == '\'' {
            boundaries.push(letter_offset);
        } else {
            letter_offset += 1;
        }
    }
    boundaries
}

fn unique_combinations(paths: impl Iterator<Item = Vec<String>>) -> Vec<String> {
    unique_strings(paths.map(|path| path.join("'")))
}

fn unique_strings(values: impl Iterator<Item = String>) -> Vec<String> {
    let mut seen = BTreeSet::new();
    let mut output = Vec::new();
    for value in values {
        if seen.insert(value.clone()) {
            output.push(value);
        }
    }
    output
}

fn combination_with_pending(path: &IncompletePath) -> String {
    let mut values = path.syllables.clone();
    values.push(path.pending.clone());
    values.join("'")
}

fn invalid(raw_input: &str, error: ParseError, segment_boundaries: Vec<usize>) -> ParseResult {
    ParseResult {
        raw_input: raw_input.to_owned(),
        query_intent: QueryIntent::Invalid,
        status: ParseStatus::Invalid,
        syllables: Vec::new(),
        logical_syllable_count: 0,
        pending_code: String::new(),
        display_segments: vec![raw_input.to_owned()],
        segment_boundaries,
        current_pinyin: String::new(),
        pinyin_combinations: Vec::new(),
        error: Some(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(input: &str) -> ParseResult {
        let mut parser = QuanpinParser::new();
        parser.process_str(input)
    }

    #[test]
    fn parses_common_full_pinyin_and_parser_owned_segments() {
        let nihao = parse("nihao");
        assert_eq!(nihao.current_pinyin, "ni'hao");
        assert_eq!(nihao.display_segments, ["ni", "hao"]);
        assert_eq!(nihao.query_intent, QueryIntent::MultiSyllable);

        let zhongguo = parse("zhongguo");
        assert_eq!(zhongguo.current_pinyin, "zhong'guo");
        assert_eq!(zhongguo.display_segments, ["zhong", "guo"]);
    }

    #[test]
    fn preserves_bounded_ambiguity_and_honors_explicit_boundaries() {
        let xian = parse("xian");
        assert_eq!(xian.current_pinyin, "xian");
        assert!(xian
            .pinyin_combinations
            .iter()
            .any(|value| value == "xi'an"));

        let explicit = parse("xi'an");
        assert_eq!(explicit.current_pinyin, "xi'an");
        assert_eq!(explicit.display_segments, ["xi", "an"]);
        assert_eq!(explicit.segment_boundaries, [2]);
        assert!(!explicit
            .pinyin_combinations
            .iter()
            .any(|value| value == "xian"));
    }

    #[test]
    fn returns_prefix_intent_for_incomplete_tail() {
        let result = parse("zhon");
        assert_eq!(result.status, ParseStatus::Incomplete);
        assert_eq!(result.query_intent, QueryIntent::SingleKeyPrefix);
        assert_eq!(result.pending_code, "zhon");
        assert_eq!(result.display_segments, ["zhon"]);
    }

    #[test]
    fn terminal_n_also_uses_prefix_query_semantics() {
        let result = parse("n");
        assert_eq!(result.status, ParseStatus::Complete);
        assert_eq!(result.query_intent, QueryIntent::SingleKeyPrefix);
        assert_eq!(result.current_pinyin, "n");
        assert!(result.pending_code.is_empty());
    }

    #[test]
    fn backspace_restores_each_previous_state() {
        let mut parser = QuanpinParser::new();
        parser.process_str("xi'an");
        assert_eq!(parser.backspace().current_pinyin, "xi'a");
        assert_eq!(parser.backspace().current_pinyin, "xi");
        assert_eq!(parser.backspace().current_pinyin, "xi");
        assert_eq!(parser.backspace().current_pinyin, "x");
        assert_eq!(parser.backspace(), ParseResult::empty());
    }

    #[test]
    fn invalid_key_can_be_removed_without_losing_history() {
        let mut parser = QuanpinParser::new();
        parser.process_str("ni");
        assert_eq!(parser.process_key('1').status, ParseStatus::Invalid);
        assert_eq!(parser.backspace().current_pinyin, "ni");
    }

    #[test]
    fn path_count_is_bounded_for_long_ambiguous_input() {
        let result = parse("xianxianxianxianxianxian");
        assert!(result.pinyin_combinations.len() < MAX_PARSE_PATHS);
    }

    #[test]
    fn shorthand_tails_remain_editable_parse_states() {
        for input in ["gj", "gjt", "guojt", "gjitian"] {
            let result = parse(input);
            assert_ne!(result.status, ParseStatus::Complete, "{input}");
            assert_eq!(result.raw_input, input);
        }
    }

    #[test]
    fn opaque_tail_preserves_the_furthest_stable_prefix() {
        let result = parse("nihaoqx");
        assert_eq!(result.status, ParseStatus::Incomplete);
        assert_eq!(result.raw_input, "nihaoqx");
        assert_eq!(result.pending_code, "qx");
        assert_eq!(result.current_pinyin, "ni'hao'qx");
        assert_eq!(
            result
                .syllables
                .iter()
                .map(|syllable| syllable.syllable.as_str())
                .collect::<Vec<_>>(),
            ["ni", "hao"]
        );
    }

    #[test]
    fn incremental_and_fresh_parse_are_equivalent_for_generated_inputs() {
        let inventory = all_syllables().collect::<Vec<_>>();
        let mut seed = 0x5eed_cafe_u64;
        for case in 0..256usize {
            let syllable_count = 1 + case % 24;
            let mut input = String::new();
            for _ in 0..syllable_count {
                seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
                input.push_str(inventory[(seed as usize) % inventory.len()]);
            }
            if case % 3 == 0 {
                input.push_str("qx");
            } else if case % 3 == 1 {
                let _ = input.pop();
            }

            let mut incremental = QuanpinParser::new();
            let mut prefixes = Vec::new();
            for key in input.chars() {
                let actual = incremental.process_key(key);
                prefixes.push(actual.clone());
                let mut fresh = QuanpinParser::new();
                let expected = fresh.process_str(incremental.raw_input());
                assert_eq!(
                    actual,
                    expected,
                    "case={case} raw={}",
                    incremental.raw_input()
                );
                assert!(incremental.lattice_stats().retained_states <= MAX_PARSE_PATHS);
            }
            while let Some(expected) = prefixes.pop() {
                assert_eq!(incremental.current_state(), expected);
                incremental.backspace();
            }
            assert_eq!(incremental.current_state(), ParseResult::empty());
        }
    }

    #[test]
    fn long_generated_sequences_have_no_length_cliff_or_state_explosion() {
        let inventory = all_syllables().collect::<Vec<_>>();
        let mut parser = QuanpinParser::new();
        for index in 0..128usize {
            let syllable = inventory[(index * 37 + 11) % inventory.len()];
            for key in syllable.chars() {
                let result = parser.process_key(key);
                assert_ne!(result.status, ParseStatus::Invalid, "index={index}");
                assert!(parser.lattice_stats().retained_states <= MAX_PARSE_PATHS);
            }
        }
        assert!(parser.raw_input().len() > 256);
        assert_eq!(parser.current_state().raw_input, parser.raw_input());
    }
}
