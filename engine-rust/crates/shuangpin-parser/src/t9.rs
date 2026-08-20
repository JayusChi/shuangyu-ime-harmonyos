use std::cmp::Ordering;
use std::collections::BTreeSet;
use std::sync::{Arc, OnceLock};

use pinyin_syllable::all_syllables;

use crate::{ParseError, ParseResult, ParseStatus, ParsedSyllable, PhoneticParser, QueryIntent};

const T9_DIGIT_COUNT: usize = 8;

/// Centralized T9 lattice limits. The public protocol still exposes at most 32
/// combinations, while the internal lattice deliberately retains a wider pool
/// for lexicon/language-model scoring in `ime-engine`.
pub const T9_MAX_RAW_DIGITS: usize = 64;
pub const T9_MAX_SYLLABLE_DIGITS: usize = 6;
pub const T9_LEGACY_PUBLIC_PATHS_PER_OFFSET: usize = 32;
pub const T9_MAX_PATHS_PER_OFFSET: usize = 64;
pub const T9_MAX_GENERATED_STATES_PER_OFFSET: usize = 1_024;
pub const T9_MAX_INTERNAL_PINYIN_HYPOTHESES: usize = 128;
pub const T9_MAX_PINYIN_COMBINATIONS: usize = 32;
pub const T9_PREFIX_CACHE_CAPACITY: usize = T9_MAX_RAW_DIGITS + 1;

/// Per-update diagnostics used by limit and performance regression tests.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct T9LatticeStats {
    pub raw_digits: usize,
    pub visited_trie_edges: usize,
    pub generated_states: usize,
    pub retained_states: usize,
    pub max_states_at_offset: usize,
    pub cache_entries: usize,
    pub input_limit_hit: bool,
    pub invalid_syllable_prunes: usize,
    pub beam_capacity_prunes: usize,
    pub internal_hypotheses: usize,
}

#[derive(Clone, Debug, Default)]
struct T9TrieNode {
    children: [Option<usize>; T9_DIGIT_COUNT],
    terminals: Vec<String>,
    prefixes: Vec<String>,
}

/// Immutable digit-signature index built once from the canonical pinyin
/// inventory. Runtime parsing walks this index and never scans the inventory.
#[derive(Clone, Debug)]
pub struct T9SyllableIndex {
    nodes: Vec<T9TrieNode>,
    syllable_count: usize,
    max_depth: usize,
    max_terminal_collision: usize,
    max_prefix_collision: usize,
}

impl T9SyllableIndex {
    pub fn build() -> Self {
        let mut index = Self {
            nodes: vec![T9TrieNode::default()],
            syllable_count: 0,
            max_depth: 0,
            max_terminal_collision: 0,
            max_prefix_collision: 0,
        };
        for syllable in all_syllables() {
            index.insert(syllable);
        }
        for node in &mut index.nodes {
            node.terminals.sort();
            node.terminals.dedup();
            node.prefixes.sort();
            node.prefixes.dedup();
            index.max_terminal_collision = index.max_terminal_collision.max(node.terminals.len());
            index.max_prefix_collision = index.max_prefix_collision.max(node.prefixes.len());
        }
        index
    }

    pub fn node_count(&self) -> usize {
        self.nodes.len()
    }

    pub fn syllable_count(&self) -> usize {
        self.syllable_count
    }

    pub fn max_depth(&self) -> usize {
        self.max_depth
    }

    pub fn max_terminal_collision(&self) -> usize {
        self.max_terminal_collision
    }

    pub fn max_prefix_collision(&self) -> usize {
        self.max_prefix_collision
    }

    pub fn exact_syllables(&self, digits: &str) -> Vec<String> {
        self.walk(digits)
            .map(|node| self.nodes[node].terminals.clone())
            .unwrap_or_default()
    }

    fn insert(&mut self, syllable: &str) {
        let Some(signature) = t9_signature(syllable) else {
            return;
        };
        self.syllable_count += 1;
        self.max_depth = self.max_depth.max(signature.len());
        let mut node_index = 0usize;
        for (offset, digit) in signature.bytes().enumerate() {
            let child_slot = usize::from(digit - b'2');
            let next = match self.nodes[node_index].children[child_slot] {
                Some(value) => value,
                None => {
                    let value = self.nodes.len();
                    self.nodes.push(T9TrieNode::default());
                    self.nodes[node_index].children[child_slot] = Some(value);
                    value
                }
            };
            node_index = next;
            self.nodes[node_index]
                .prefixes
                .push(syllable[..=offset].to_owned());
        }
        self.nodes[node_index].terminals.push(syllable.to_owned());
    }

    fn walk(&self, digits: &str) -> Option<usize> {
        let mut node_index = 0usize;
        for digit in digits.bytes() {
            let slot = digit_slot(digit)?;
            node_index = self.nodes[node_index].children[slot]?;
        }
        Some(node_index)
    }
}

fn shared_index() -> Arc<T9SyllableIndex> {
    static INDEX: OnceLock<Arc<T9SyllableIndex>> = OnceLock::new();
    Arc::clone(INDEX.get_or_init(|| Arc::new(T9SyllableIndex::build())))
}

/// Returns the standard T9 letter group for one digit.
pub const fn t9_letters(digit: char) -> Option<&'static str> {
    match digit {
        '2' => Some("abc"),
        '3' => Some("def"),
        '4' => Some("ghi"),
        '5' => Some("jkl"),
        '6' => Some("mno"),
        '7' => Some("pqrs"),
        '8' => Some("tuv"),
        '9' => Some("wxyz"),
        _ => None,
    }
}

/// Converts normalized lowercase pinyin to its T9 signature.
pub fn t9_signature(pinyin: &str) -> Option<String> {
    let mut output = String::with_capacity(pinyin.len());
    for letter in pinyin.chars() {
        output.push(match letter {
            'a'..='c' => '2',
            'd'..='f' => '3',
            'g'..='i' => '4',
            'j'..='l' => '5',
            'm'..='o' => '6',
            'p'..='s' => '7',
            't'..='v' => '8',
            'w'..='z' => '9',
            _ => return None,
        });
    }
    (!output.is_empty()).then_some(output)
}

fn digit_slot(digit: u8) -> Option<usize> {
    (b'2'..=b'9')
        .contains(&digit)
        .then_some(usize::from(digit - b'2'))
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct T9Segment {
    syllable: String,
    start: usize,
    end: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct T9Path {
    segments: Vec<T9Segment>,
}

impl T9Path {
    fn combination(&self) -> String {
        self.segments
            .iter()
            .map(|segment| segment.syllable.as_str())
            .collect::<Vec<_>>()
            .join("'")
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct T9IncompletePath {
    stable: T9Path,
    pending: String,
    pending_start: usize,
}

impl T9IncompletePath {
    fn combination(&self) -> String {
        let stable = self.stable.combination();
        if stable.is_empty() {
            self.pending.clone()
        } else {
            format!("{stable}'{}", self.pending)
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum T9Variant {
    Complete(T9Path),
    Incomplete(T9IncompletePath),
}

impl T9Variant {
    fn combination(&self) -> String {
        match self {
            Self::Complete(path) => path.combination(),
            Self::Incomplete(path) => path.combination(),
        }
    }

    fn segment_count(&self) -> usize {
        match self {
            Self::Complete(path) => path.segments.len(),
            Self::Incomplete(path) => path.stable.segments.len() + 1,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum T9InputAction {
    Digit,
    Boundary(usize),
}

/// Stateful traditional 9-key pinyin parser. It keeps only bounded legal
/// pinyin paths and recomputes from the digit history after edits, so deletion
/// and explicit-boundary removal cannot retain stale ambiguity state.
#[derive(Clone, Debug)]
pub struct T9PinyinParser {
    index: Arc<T9SyllableIndex>,
    raw_digits: String,
    boundaries: Vec<usize>,
    history: Vec<T9InputAction>,
    /// Dynamic-programming rows for every digit prefix. Appending one digit
    /// computes only the new row; backspace drops one row. A boundary inserted
    /// at the current end is a hard constraint for subsequent rows and does
    /// not invalidate already-computed prefixes.
    paths_at: Vec<Vec<T9Path>>,
    /// Separate first-stage-width lattice used to preserve the public path
    /// snapshot while `paths_at` explores a wider joint-search pool.
    public_paths_at: Vec<Vec<T9Path>>,
    variants: Vec<T9Variant>,
    public_variants: Vec<T9Variant>,
    selected_combination: Option<String>,
    selection_explicit: bool,
    current: ParseResult,
    stats: T9LatticeStats,
}

impl Default for T9PinyinParser {
    fn default() -> Self {
        Self::new()
    }
}

impl T9PinyinParser {
    pub fn new() -> Self {
        Self {
            index: shared_index(),
            raw_digits: String::new(),
            boundaries: Vec::new(),
            history: Vec::new(),
            paths_at: vec![vec![T9Path {
                segments: Vec::new(),
            }]],
            public_paths_at: vec![vec![T9Path {
                segments: Vec::new(),
            }]],
            variants: Vec::new(),
            public_variants: Vec::new(),
            selected_combination: None,
            selection_explicit: false,
            current: ParseResult::empty(),
            stats: T9LatticeStats::default(),
        }
    }

    pub fn process_str(&mut self, input: &str) -> ParseResult {
        for digit in input.chars() {
            self.process_key(digit);
        }
        self.current.clone()
    }

    pub fn lattice_stats(&self) -> T9LatticeStats {
        self.stats
    }

    pub fn index(&self) -> &T9SyllableIndex {
        &self.index
    }

    pub fn has_explicit_selection(&self) -> bool {
        self.selection_explicit
    }

    /// All internally retained legal hypotheses, before the public 32-path
    /// limit. This is intentionally T9-specific and consumed only by the joint
    /// decoder and its diagnostics.
    pub fn internal_combinations(&self) -> Vec<String> {
        self.variants
            .iter()
            .map(T9Variant::combination)
            .take(T9_MAX_INTERNAL_PINYIN_HYPOTHESES)
            .collect()
    }

    /// Publishes lexicon/language-model ranked paths. Complete paths recovered
    /// directly from the digit-indexed lexicon may not have survived the
    /// parser-only beam, so verified paths are admitted before stable reorder.
    pub fn publish_joint_order(&mut self, ranked: &[String]) -> ParseResult {
        if self.selection_explicit {
            return self.current.clone();
        }
        for combination in ranked {
            if self
                .public_variants
                .iter()
                .any(|variant| variant.combination() == *combination)
            {
                continue;
            }
            if let Some(path) =
                complete_path_for_combination(&self.raw_digits, &self.boundaries, combination)
            {
                self.public_variants.push(T9Variant::Complete(path));
            }
        }
        let rank = ranked
            .iter()
            .enumerate()
            .map(|(index, value)| (value.as_str(), index))
            .collect::<std::collections::BTreeMap<_, _>>();
        self.public_variants.sort_by(|left, right| {
            let left_value = left.combination();
            let right_value = right.combination();
            rank.get(left_value.as_str())
                .copied()
                .unwrap_or(usize::MAX)
                .cmp(
                    &rank
                        .get(right_value.as_str())
                        .copied()
                        .unwrap_or(usize::MAX),
                )
                .then_with(|| left_value.cmp(&right_value))
        });
        self.public_variants
            .dedup_by(|left, right| left.combination() == right.combination());
        self.current = render_result(
            &self.raw_digits,
            &self.boundaries,
            &self.public_variants,
            None,
        );
        self.current.clone()
    }

    /// Index zero is the displayed `currentPinyin`; following indexes address
    /// `pinyinCombinations` in their published order.
    pub fn select_pinyin_combination(&mut self, index: usize) -> Result<ParseResult, ParseError> {
        let mut published = Vec::with_capacity(1 + self.current.pinyin_combinations.len());
        if !self.current.current_pinyin.is_empty() {
            published.push(self.current.current_pinyin.clone());
        }
        published.extend(self.current.pinyin_combinations.iter().cloned());
        let Some(selected) = published.get(index).cloned() else {
            return Err(ParseError::InvalidCode {
                code: format!("pinyin-combination-{index}"),
            });
        };
        self.selected_combination = Some(selected);
        self.selection_explicit = true;
        self.current = render_result(
            &self.raw_digits,
            &self.boundaries,
            &self.public_variants,
            self.selected_combination.as_deref(),
        );
        Ok(self.current.clone())
    }

    fn append_digit(&mut self, digit: char) -> ParseResult {
        if t9_letters(digit).is_none() {
            return invalid_result(
                &self.raw_digits,
                &self.boundaries,
                ParseError::InvalidKey { key: digit },
            );
        }
        if self.raw_digits.len() >= T9_MAX_RAW_DIGITS {
            self.stats.input_limit_hit = true;
            return self.current.clone();
        }
        self.raw_digits.push(digit);
        self.history.push(T9InputAction::Digit);
        self.clear_selection();
        self.extend_prefix_cache()
    }

    fn clear_selection(&mut self) {
        self.selected_combination = None;
        self.selection_explicit = false;
    }

    fn refresh(&mut self) -> ParseResult {
        let (variants, stats) = variants_from_paths(
            &self.index,
            &self.raw_digits,
            &self.boundaries,
            &self.paths_at,
            T9LatticeStats::default(),
            T9_MAX_INTERNAL_PINYIN_HYPOTHESES,
        );
        let (public_variants, _) = variants_from_paths(
            &self.index,
            &self.raw_digits,
            &self.boundaries,
            &self.public_paths_at,
            T9LatticeStats::default(),
            T9_MAX_PINYIN_COMBINATIONS,
        );
        self.variants = variants;
        self.public_variants = public_variants;
        self.stats = stats;
        self.current = render_result(
            &self.raw_digits,
            &self.boundaries,
            &self.public_variants,
            self.selected_combination.as_deref(),
        );
        self.current.clone()
    }

    fn extend_prefix_cache(&mut self) -> ParseResult {
        let mut stats = T9LatticeStats::default();
        let row = extend_paths_for_new_end(
            &self.index,
            &self.raw_digits,
            &self.boundaries,
            &self.paths_at,
            &mut stats,
            T9_MAX_PATHS_PER_OFFSET,
            true,
        );
        self.paths_at.push(row);
        let mut public_stats = T9LatticeStats::default();
        let public_row = extend_paths_for_new_end(
            &self.index,
            &self.raw_digits,
            &self.boundaries,
            &self.public_paths_at,
            &mut public_stats,
            T9_LEGACY_PUBLIC_PATHS_PER_OFFSET,
            false,
        );
        self.public_paths_at.push(public_row);
        let (variants, stats) = variants_from_paths(
            &self.index,
            &self.raw_digits,
            &self.boundaries,
            &self.paths_at,
            stats,
            T9_MAX_INTERNAL_PINYIN_HYPOTHESES,
        );
        let (public_variants, _) = variants_from_paths(
            &self.index,
            &self.raw_digits,
            &self.boundaries,
            &self.public_paths_at,
            public_stats,
            T9_MAX_PINYIN_COMBINATIONS,
        );
        self.variants = variants;
        self.public_variants = public_variants;
        self.stats = stats;
        self.current = render_result(
            &self.raw_digits,
            &self.boundaries,
            &self.public_variants,
            self.selected_combination.as_deref(),
        );
        self.current.clone()
    }
}

impl PhoneticParser for T9PinyinParser {
    type Error = ParseError;

    fn raw_input(&self) -> &str {
        &self.raw_digits
    }

    fn process_key(&mut self, key: char) -> ParseResult {
        self.append_digit(key)
    }

    fn process_str(&mut self, input: &str) -> ParseResult {
        T9PinyinParser::process_str(self, input)
    }

    fn insert_segment_boundary(&mut self) -> Result<ParseResult, Self::Error> {
        let offset = self.raw_digits.len();
        if offset == 0
            || self.boundaries.last() == Some(&offset)
            || !matches!(
                self.current.status,
                ParseStatus::Complete | ParseStatus::Ambiguous
            )
        {
            return Err(ParseError::InvalidSegmentBoundary);
        }
        self.boundaries.push(offset);
        self.history.push(T9InputAction::Boundary(offset));
        self.clear_selection();
        Ok(self.refresh())
    }

    fn backspace(&mut self) -> ParseResult {
        match self.history.pop() {
            Some(T9InputAction::Digit) => {
                self.raw_digits.pop();
                if self.paths_at.len() > 1 {
                    self.paths_at.pop();
                }
                if self.public_paths_at.len() > 1 {
                    self.public_paths_at.pop();
                }
            }
            Some(T9InputAction::Boundary(offset)) if self.boundaries.last() == Some(&offset) => {
                self.boundaries.pop();
            }
            Some(T9InputAction::Boundary(_)) => {}
            None => {}
        }
        self.clear_selection();
        self.refresh()
    }

    fn reset(&mut self) -> ParseResult {
        self.raw_digits.clear();
        self.boundaries.clear();
        self.history.clear();
        self.paths_at.clear();
        self.paths_at.push(vec![T9Path {
            segments: Vec::new(),
        }]);
        self.public_paths_at.clear();
        self.public_paths_at.push(vec![T9Path {
            segments: Vec::new(),
        }]);
        self.variants.clear();
        self.public_variants.clear();
        self.clear_selection();
        self.current = ParseResult::empty();
        self.stats = T9LatticeStats::default();
        self.current.clone()
    }

    fn current_state(&self) -> ParseResult {
        self.current.clone()
    }
}

fn extend_paths_for_new_end(
    index: &T9SyllableIndex,
    raw_digits: &str,
    boundaries: &[usize],
    paths_at: &[Vec<T9Path>],
    stats: &mut T9LatticeStats,
    path_limit: usize,
    prefer_fewer_segments: bool,
) -> Vec<T9Path> {
    let end = raw_digits.len();
    if end == 0 {
        return Vec::new();
    }
    let last_boundary = boundaries
        .iter()
        .copied()
        .filter(|boundary| *boundary < end)
        .max()
        .unwrap_or(0);
    let min_start = end
        .saturating_sub(T9_MAX_SYLLABLE_DIGITS)
        .max(last_boundary);
    let mut row = Vec::new();
    'starts: for start in min_start..end {
        let Some(prefixes) = paths_at.get(start) else {
            continue;
        };
        if prefixes.is_empty() {
            continue;
        }
        let digits = &raw_digits[start..end];
        stats.visited_trie_edges = stats.visited_trie_edges.saturating_add(digits.len());
        let Some(node_index) = index.walk(digits) else {
            stats.invalid_syllable_prunes += 1;
            continue;
        };
        let terminals = &index.nodes[node_index].terminals;
        if terminals.is_empty() {
            stats.invalid_syllable_prunes += 1;
            continue;
        }
        for prefix in prefixes.iter().take(path_limit) {
            for syllable in terminals.iter().take(path_limit) {
                if stats.generated_states >= T9_MAX_GENERATED_STATES_PER_OFFSET {
                    break 'starts;
                }
                let mut path = prefix.clone();
                path.segments.push(T9Segment {
                    syllable: syllable.clone(),
                    start,
                    end,
                });
                row.push(path);
                stats.generated_states += 1;
            }
        }
    }
    stats.beam_capacity_prunes += normalize_paths(&mut row, path_limit, prefer_fewer_segments);
    row
}

fn variants_from_paths(
    index: &T9SyllableIndex,
    raw_digits: &str,
    boundaries: &[usize],
    paths_at: &[Vec<T9Path>],
    mut stats: T9LatticeStats,
    variant_limit: usize,
) -> (Vec<T9Variant>, T9LatticeStats) {
    if raw_digits.is_empty() {
        stats.cache_entries = 1;
        return (Vec::new(), stats);
    }
    let raw_len = raw_digits.len();
    stats.raw_digits = raw_len;
    stats.cache_entries = paths_at.len().min(T9_PREFIX_CACHE_CAPACITY);
    stats.retained_states = paths_at.iter().map(Vec::len).sum();
    stats.max_states_at_offset = paths_at.iter().map(Vec::len).max().unwrap_or(0);

    if let Some(complete) = paths_at.get(raw_len).filter(|paths| !paths.is_empty()) {
        let mut variants = complete
            .iter()
            .cloned()
            .map(T9Variant::Complete)
            .collect::<Vec<_>>();
        stats.beam_capacity_prunes += normalize_variants(&mut variants, variant_limit);
        stats.internal_hypotheses = variants.len();
        return (variants, stats);
    }

    let last_boundary = boundaries.last().copied().unwrap_or(0);
    for pending_start in (last_boundary..raw_len).rev() {
        let Some(stable_paths) = paths_at.get(pending_start) else {
            continue;
        };
        if stable_paths.is_empty() {
            continue;
        }
        let Some(node_index) = index.walk(&raw_digits[pending_start..]) else {
            stats.invalid_syllable_prunes += 1;
            continue;
        };
        if index.nodes[node_index].prefixes.is_empty() {
            stats.invalid_syllable_prunes += 1;
            continue;
        }
        let mut variants = Vec::new();
        'pending: for stable in stable_paths.iter().take(variant_limit) {
            for prefix in index.nodes[node_index].prefixes.iter().take(variant_limit) {
                if variants.len() >= variant_limit {
                    break 'pending;
                }
                variants.push(T9Variant::Incomplete(T9IncompletePath {
                    stable: stable.clone(),
                    pending: prefix.clone(),
                    pending_start,
                }));
            }
        }
        stats.beam_capacity_prunes += normalize_variants(&mut variants, variant_limit);
        stats.internal_hypotheses = variants.len();
        return (variants, stats);
    }

    (Vec::new(), stats)
}

fn normalize_paths(
    paths: &mut Vec<T9Path>,
    path_limit: usize,
    prefer_fewer_segments: bool,
) -> usize {
    if prefer_fewer_segments {
        paths.sort_by(compare_path);
    } else {
        paths.sort_by_key(T9Path::combination);
    }
    paths.dedup_by(|left, right| left.segments == right.segments);
    let pruned = paths.len().saturating_sub(path_limit);
    paths.truncate(path_limit);
    pruned
}

fn compare_path(left: &T9Path, right: &T9Path) -> Ordering {
    left.segments
        .len()
        .cmp(&right.segments.len())
        .then_with(|| left.combination().cmp(&right.combination()))
}

fn normalize_variants(variants: &mut Vec<T9Variant>, variant_limit: usize) -> usize {
    variants.sort_by(|left, right| {
        left.segment_count()
            .cmp(&right.segment_count())
            .then_with(|| left.combination().cmp(&right.combination()))
    });
    variants.dedup_by(|left, right| left.combination() == right.combination());
    let pruned = variants.len().saturating_sub(variant_limit);
    variants.truncate(variant_limit);
    pruned
}

fn complete_path_for_combination(
    raw_digits: &str,
    boundaries: &[usize],
    combination: &str,
) -> Option<T9Path> {
    let mut start = 0usize;
    let mut segments = Vec::new();
    for syllable in combination.split('\'').filter(|value| !value.is_empty()) {
        let signature = t9_signature(syllable)?;
        let end = start.checked_add(signature.len())?;
        if raw_digits.get(start..end)? != signature {
            return None;
        }
        segments.push(T9Segment {
            syllable: syllable.to_owned(),
            start,
            end,
        });
        start = end;
    }
    if start != raw_digits.len()
        || boundaries
            .iter()
            .any(|boundary| !segments.iter().any(|segment| segment.end == *boundary))
    {
        return None;
    }
    Some(T9Path { segments })
}

fn render_result(
    raw_digits: &str,
    boundaries: &[usize],
    variants: &[T9Variant],
    selected_combination: Option<&str>,
) -> ParseResult {
    if raw_digits.is_empty() {
        return ParseResult::empty();
    }
    if variants.is_empty() {
        return invalid_result(
            raw_digits,
            boundaries,
            ParseError::InvalidCode {
                code: raw_digits.to_owned(),
            },
        );
    }

    let selected_index = selected_combination
        .and_then(|selected| {
            variants
                .iter()
                .position(|variant| variant.combination() == selected)
        })
        .unwrap_or(0);
    let selected = &variants[selected_index];
    let current_pinyin = selected.combination();
    let mut seen = BTreeSet::new();
    seen.insert(current_pinyin.clone());
    let mut pinyin_combinations = Vec::new();
    for variant in variants {
        if pinyin_combinations.len() + 1 >= T9_MAX_PINYIN_COMBINATIONS {
            break;
        }
        let value = variant.combination();
        if seen.insert(value.clone()) {
            pinyin_combinations.push(value);
        }
    }

    match selected {
        T9Variant::Complete(path) => complete_result(
            raw_digits,
            boundaries,
            path,
            current_pinyin,
            pinyin_combinations,
        ),
        T9Variant::Incomplete(path) => incomplete_result(
            raw_digits,
            boundaries,
            path,
            current_pinyin,
            pinyin_combinations,
        ),
    }
}

fn complete_result(
    raw_digits: &str,
    boundaries: &[usize],
    path: &T9Path,
    current_pinyin: String,
    pinyin_combinations: Vec<String>,
) -> ParseResult {
    let syllables = parsed_syllables(raw_digits, &path.segments);
    let logical_syllable_count = syllables.len();
    ParseResult {
        raw_input: raw_digits.to_owned(),
        query_intent: if logical_syllable_count <= 1 {
            QueryIntent::CompleteSyllable
        } else {
            QueryIntent::MultiSyllable
        },
        status: if pinyin_combinations.is_empty() {
            ParseStatus::Complete
        } else {
            ParseStatus::Ambiguous
        },
        syllables,
        logical_syllable_count,
        pending_code: String::new(),
        display_segments: path
            .segments
            .iter()
            .map(|segment| raw_digits[segment.start..segment.end].to_owned())
            .collect(),
        segment_boundaries: boundaries.to_vec(),
        current_pinyin,
        pinyin_combinations,
        error: None,
    }
}

fn incomplete_result(
    raw_digits: &str,
    boundaries: &[usize],
    path: &T9IncompletePath,
    current_pinyin: String,
    pinyin_combinations: Vec<String>,
) -> ParseResult {
    let syllables = parsed_syllables(raw_digits, &path.stable.segments);
    let logical_syllable_count = syllables.len();
    let mut display_segments = path
        .stable
        .segments
        .iter()
        .map(|segment| raw_digits[segment.start..segment.end].to_owned())
        .collect::<Vec<_>>();
    display_segments.push(raw_digits[path.pending_start..].to_owned());
    ParseResult {
        raw_input: raw_digits.to_owned(),
        query_intent: if logical_syllable_count == 0 {
            QueryIntent::SingleKeyPrefix
        } else if logical_syllable_count == 1 {
            QueryIntent::IncompleteSyllable
        } else {
            QueryIntent::MultiSyllable
        },
        status: ParseStatus::Incomplete,
        syllables,
        logical_syllable_count,
        pending_code: path.pending.clone(),
        display_segments,
        segment_boundaries: boundaries.to_vec(),
        current_pinyin,
        pinyin_combinations,
        error: None,
    }
}

fn parsed_syllables(raw_digits: &str, segments: &[T9Segment]) -> Vec<ParsedSyllable> {
    segments
        .iter()
        .enumerate()
        .map(|(logical_index, segment)| {
            let (initial, final_part) = split_initial(&segment.syllable);
            ParsedSyllable {
                logical_index,
                raw_code: raw_digits[segment.start..segment.end].to_owned(),
                syllable: segment.syllable.clone(),
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

fn invalid_result(raw_digits: &str, boundaries: &[usize], error: ParseError) -> ParseResult {
    ParseResult {
        raw_input: raw_digits.to_owned(),
        query_intent: QueryIntent::Invalid,
        status: ParseStatus::Invalid,
        syllables: Vec::new(),
        logical_syllable_count: 0,
        pending_code: String::new(),
        display_segments: if raw_digits.is_empty() {
            Vec::new()
        } else {
            vec![raw_digits.to_owned()]
        },
        segment_boundaries: boundaries.to_vec(),
        current_pinyin: String::new(),
        pinyin_combinations: Vec::new(),
        error: Some(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn all_combinations(result: &ParseResult) -> Vec<String> {
        let mut values = vec![result.current_pinyin.clone()];
        values.extend(result.pinyin_combinations.clone());
        values
    }

    #[test]
    fn standard_mapping_and_inventory_index_are_complete() {
        assert_eq!(t9_letters('2'), Some("abc"));
        assert_eq!(t9_letters('3'), Some("def"));
        assert_eq!(t9_letters('4'), Some("ghi"));
        assert_eq!(t9_letters('5'), Some("jkl"));
        assert_eq!(t9_letters('6'), Some("mno"));
        assert_eq!(t9_letters('7'), Some("pqrs"));
        assert_eq!(t9_letters('8'), Some("tuv"));
        assert_eq!(t9_letters('9'), Some("wxyz"));
        assert_eq!(t9_signature("ni").as_deref(), Some("64"));
        assert_eq!(t9_signature("hao").as_deref(), Some("426"));

        let index = T9SyllableIndex::build();
        assert_eq!(index.syllable_count(), pinyin_syllable::syllable_count());
        assert!(index.exact_syllables("64").contains(&"ni".to_owned()));
        assert!(index.max_depth() <= T9_MAX_SYLLABLE_DIGITS);
        assert!(index.max_terminal_collision() <= T9_MAX_PATHS_PER_OFFSET);
        assert!(index.max_prefix_collision() <= T9_MAX_PATHS_PER_OFFSET);
    }

    #[test]
    fn parses_single_and_multi_syllable_collisions_without_letter_expansion() {
        let mut parser = T9PinyinParser::new();
        let ni = parser.process_str("64");
        assert!(all_combinations(&ni).contains(&"ni".to_owned()));
        assert!(ni.pinyin_combinations.len() < T9_MAX_PINYIN_COMBINATIONS);

        parser.reset();
        let nihao = parser.process_str("64426");
        assert!(all_combinations(&nihao).contains(&"ni'hao".to_owned()));
        assert!(parser.lattice_stats().generated_states <= 5 * T9_MAX_GENERATED_STATES_PER_OFFSET);
        assert!(parser.lattice_stats().max_states_at_offset <= T9_MAX_PATHS_PER_OFFSET);
    }

    #[test]
    fn selection_boundary_and_backspace_restore_deterministically() {
        let mut parser = T9PinyinParser::new();
        let initial = parser.process_str("64");
        let published = all_combinations(&initial);
        let ni_index = published.iter().position(|value| value == "ni").unwrap();
        let selected = parser.select_pinyin_combination(ni_index).unwrap();
        assert_eq!(selected.current_pinyin, "ni");
        assert!(parser.has_explicit_selection());

        parser.insert_segment_boundary().unwrap();
        let segmented = parser.process_str("426");
        assert!(all_combinations(&segmented).contains(&"ni'hao".to_owned()));
        assert_eq!(segmented.segment_boundaries, [2]);

        let after_digit_delete = parser.backspace();
        assert_eq!(after_digit_delete.raw_input, "6442");
        parser.backspace();
        parser.backspace();
        let after_boundary_delete = parser.backspace();
        assert_eq!(after_boundary_delete.raw_input, "64");
        assert!(after_boundary_delete.segment_boundaries.is_empty());
        assert!(all_combinations(&after_boundary_delete).contains(&"ni".to_owned()));
    }

    #[test]
    fn incomplete_and_extreme_inputs_stay_bounded() {
        let mut parser = T9PinyinParser::new();
        let incomplete = parser.process_str("946");
        assert_ne!(incomplete.status, ParseStatus::Empty);

        parser.reset();
        for _ in 0..(T9_MAX_RAW_DIGITS + 20) {
            parser.process_key('6');
        }
        assert_eq!(parser.raw_input().len(), T9_MAX_RAW_DIGITS);
        assert!(parser.lattice_stats().input_limit_hit);
        assert!(parser.lattice_stats().max_states_at_offset <= T9_MAX_PATHS_PER_OFFSET);
        assert!(
            parser.lattice_stats().generated_states
                <= T9_MAX_RAW_DIGITS * T9_MAX_GENERATED_STATES_PER_OFFSET
        );
        assert!(parser.lattice_stats().cache_entries <= T9_PREFIX_CACHE_CAPACITY);

        for _ in 0..T9_MAX_RAW_DIGITS {
            parser.backspace();
        }
        assert_eq!(parser.current_state(), ParseResult::empty());
    }

    #[test]
    fn repeated_runs_return_identical_path_order() {
        let first = T9PinyinParser::new().process_str("64426");
        for _ in 0..20 {
            assert_eq!(T9PinyinParser::new().process_str("64426"), first);
        }
    }

    #[test]
    fn incremental_prefix_cache_matches_fresh_parse_and_backspace() {
        let digits = "6442664426";
        let mut incremental = T9PinyinParser::new();
        let mut prefix = String::new();
        for digit in digits.chars() {
            prefix.push(digit);
            let current = incremental.process_key(digit);
            assert_eq!(current, T9PinyinParser::new().process_str(&prefix));
            assert_eq!(incremental.lattice_stats().cache_entries, prefix.len() + 1);
        }
        while !prefix.is_empty() {
            prefix.pop();
            let current = incremental.backspace();
            assert_eq!(current, T9PinyinParser::new().process_str(&prefix));
        }
    }

    #[test]
    fn internal_pool_exceeds_public_protocol_limit_without_leaking_paths() {
        let mut parser = T9PinyinParser::new();
        let result = parser.process_str("6442664426");

        assert!(parser.internal_combinations().len() > T9_MAX_PINYIN_COMBINATIONS);
        assert!(all_combinations(&result).len() <= T9_MAX_PINYIN_COMBINATIONS);
        assert!(parser.lattice_stats().internal_hypotheses > T9_MAX_PINYIN_COMBINATIONS);
    }
}
