use std::collections::{BTreeMap, BTreeSet};

use lexicon_core::{BinaryLexicon, LexiconEntry};

use crate::context::CharacterBigramModel;
use crate::graph::WordEdge;
use crate::path::{compare_path, deduplicate_candidates, SentenceCandidate, SentencePath};
use crate::scorer::SentenceScorer;

// Single-letter syllables are legal (for example `a`), but in an ambiguous
// digit stream they create pathological segmentations such as `a a ni zhu`
// ahead of `bang zhu`. The penalty is T9-only and therefore cannot perturb
// full-pinyin or double-pinyin ranking.
const T9_SINGLE_LETTER_SYLLABLE_PENALTY: i64 = 1_600;
const T9_SYLLABLE_AMBIGUITY_PENALTY: i64 = 220;
const T9_WORD_EDGE_PENALTY: i64 = 600;
// Cross-word character bigrams are weak evidence in a digit-collision search:
// a boundary such as `离了|解决` can accidentally recreate the frequent
// in-word pair `了解`. Keep that signal below one word-frequency magnitude
// step (70 points), so it breaks close ties without overturning lexical priors.
const T9_MAX_CROSS_WORD_CONTEXT_SCORE: i64 = 64;

/// All T9 joint-search ceilings live here so tests and diagnostics observe the
/// same limits as production code.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct T9JointLimits {
    pub max_raw_digits: usize,
    pub max_word_digits: usize,
    pub beam_width: usize,
    pub max_states_per_position: usize,
    pub max_entries_per_reading: usize,
    pub max_direct_entries_per_reading: usize,
    pub max_direct_paths: usize,
    pub max_edges_per_position: usize,
    pub max_graph_edges: usize,
    pub max_sentence_words: usize,
    pub max_output_candidates: usize,
    pub max_diagnostic_paths: usize,
    pub max_joint_public_promotions: usize,
    pub max_compatibility_decode_paths: usize,
    pub max_compatibility_decode_digits: usize,
    pub score_prune_delta: i64,
}

impl Default for T9JointLimits {
    fn default() -> Self {
        Self {
            max_raw_digits: 64,
            max_word_digits: 64,
            beam_width: 16,
            max_states_per_position: 16,
            max_entries_per_reading: 16,
            max_direct_entries_per_reading: 64,
            max_direct_paths: 256,
            max_edges_per_position: 64,
            max_graph_edges: 1_024,
            max_sentence_words: 32,
            max_output_candidates: 256,
            max_diagnostic_paths: 512,
            max_joint_public_promotions: 4,
            // The compatibility decoder uses a T9-specific Top-4 sentence
            // budget, so all public pinyin paths remain covered without the
            // historical 32 x 16 candidate fan-out.
            max_compatibility_decode_paths: 32,
            max_compatibility_decode_digits: 32,
            score_prune_delta: 12_000,
        }
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct T9JointStats {
    pub explored_pinyin_hypotheses: usize,
    pub max_beam_states: usize,
    pub lexicon_prefix_unreachable_prunes: usize,
    pub joint_score_prunes: usize,
    pub beam_capacity_prunes: usize,
    pub output_limit_prunes: usize,
    pub graph_edges: usize,
    pub peak_estimated_bytes: usize,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct T9JointDecodeResult {
    pub candidates: Vec<SentenceCandidate>,
    pub ranked_pinyin_paths: Vec<String>,
    pub lexicon_reachable_paths: Vec<String>,
    pub beam_pruned_paths: Vec<String>,
    pub stats: T9JointStats,
}

/// Prefix-owned beam cache for incremental T9 decoding. Appending a digit
/// expands only lexicon edges ending at the new position.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct T9JointSession {
    raw_digits: String,
    explicit_boundaries: Vec<usize>,
    arena: JointArena,
    beams: Vec<Vec<JointState>>,
    direct_paths: Vec<SentencePath>,
    last_pruned_paths: Vec<String>,
}

impl Default for T9JointSession {
    fn default() -> Self {
        Self {
            raw_digits: String::new(),
            explicit_boundaries: Vec::new(),
            arena: JointArena::default(),
            beams: vec![vec![JointState::default()]],
            direct_paths: Vec::new(),
            last_pruned_paths: Vec::new(),
        }
    }
}

impl T9JointSession {
    pub fn clear(&mut self) {
        *self = Self::default();
    }
}

#[derive(Clone, Debug)]
struct IndexedEntry {
    entry_index: usize,
    syllable_boundaries: Vec<usize>,
    /// Zero-based frequency rank within one canonical pinyin reading. Search
    /// edges use this to reserve room for distinct readings before adding more
    /// homophones of an already represented reading.
    reading_rank: usize,
}

#[derive(Clone, Debug, Default)]
struct IndexedSignature {
    /// Global-frequency order is used for whole-input candidate publication.
    output_entries: Vec<IndexedEntry>,
    /// Reading-diverse order is used by the bounded sentence search.
    search_entries: Vec<IndexedEntry>,
}

/// Digit signatures point at existing lexicon entries; no patch dictionary or
/// evaluation-derived data is introduced. Values use entry indexes so the
/// loaded lexicon remains the single owner of word/frequency/source data.
#[derive(Clone, Debug, Default)]
pub(crate) struct T9LexiconIndex {
    by_signature: BTreeMap<String, IndexedSignature>,
    max_signature_len: usize,
}

impl T9LexiconIndex {
    pub(crate) fn build(lexicon: &BinaryLexicon) -> Self {
        let mut grouped = BTreeMap::<String, Vec<IndexedEntry>>::new();
        let mut max_signature_len = 0usize;
        for (entry_index, entry) in lexicon.entries.iter().enumerate() {
            let Some((signature, syllable_boundaries)) = entry_signature(entry) else {
                continue;
            };
            max_signature_len = max_signature_len.max(signature.len());
            grouped.entry(signature).or_default().push(IndexedEntry {
                entry_index,
                syllable_boundaries,
                reading_rank: 0,
            });
        }
        let mut by_signature = BTreeMap::new();
        for (signature, mut entries) in grouped {
            entries.sort_by(|left, right| {
                let left_entry = &lexicon.entries[left.entry_index];
                let right_entry = &lexicon.entries[right.entry_index];
                right_entry
                    .frequency
                    .cmp(&left_entry.frequency)
                    .then_with(|| left_entry.pinyin_key.cmp(&right_entry.pinyin_key))
                    .then_with(|| left_entry.word.cmp(&right_entry.word))
                    .then_with(|| left.entry_index.cmp(&right.entry_index))
            });
            let mut ranks_by_reading = BTreeMap::<String, usize>::new();
            for indexed in &mut entries {
                let reading = lexicon.entries[indexed.entry_index].pinyin_key.clone();
                let rank = ranks_by_reading.entry(reading).or_default();
                indexed.reading_rank = *rank;
                *rank += 1;
            }
            let mut search_entries = entries.clone();
            search_entries.sort_by(|left, right| {
                let left_entry = &lexicon.entries[left.entry_index];
                let right_entry = &lexicon.entries[right.entry_index];
                left.reading_rank
                    .cmp(&right.reading_rank)
                    .then_with(|| right_entry.frequency.cmp(&left_entry.frequency))
                    .then_with(|| left_entry.pinyin_key.cmp(&right_entry.pinyin_key))
                    .then_with(|| left_entry.word.cmp(&right_entry.word))
                    .then_with(|| left.entry_index.cmp(&right.entry_index))
            });
            by_signature.insert(
                signature,
                IndexedSignature {
                    output_entries: entries,
                    search_entries,
                },
            );
        }
        Self {
            by_signature,
            max_signature_len,
        }
    }

    pub(crate) fn decode(
        &self,
        lexicon: &BinaryLexicon,
        context_model: &CharacterBigramModel,
        raw_digits: &str,
        explicit_boundaries: &[usize],
        limits: &T9JointLimits,
    ) -> T9JointDecodeResult {
        if raw_digits.is_empty()
            || raw_digits.len() > limits.max_raw_digits
            || raw_digits
                .bytes()
                .any(|digit| !(b'2'..=b'9').contains(&digit))
        {
            return T9JointDecodeResult::default();
        }

        let raw_len = raw_digits.len();
        let mut stats = T9JointStats::default();
        let mut arena = JointArena::default();
        let mut edges_by_start = vec![Vec::<usize>::new(); raw_len + 1];
        let mut reachable_paths = BTreeSet::<String>::new();

        for start in 0..raw_len {
            let max_end = start
                .saturating_add(limits.max_word_digits.min(self.max_signature_len))
                .min(raw_len);
            'ends: for end in start + 1..=max_end {
                let Some(indexed) = self.by_signature.get(&raw_digits[start..end]) else {
                    continue;
                };
                for indexed in &indexed.search_entries {
                    let entry = &lexicon.entries[indexed.entry_index];
                    if !boundaries_compatible(
                        start,
                        end,
                        &indexed.syllable_boundaries,
                        explicit_boundaries,
                    ) {
                        continue;
                    }
                    if start == 0 && end == raw_len {
                        reachable_paths.insert(reading_combination(&entry.pinyin_key));
                    }
                    if indexed.reading_rank >= limits.max_entries_per_reading {
                        continue;
                    }
                    if edges_by_start[start].len() >= limits.max_edges_per_position
                        || stats.graph_edges >= limits.max_graph_edges
                    {
                        break 'ends;
                    }
                    let edge = word_edge(lexicon, entry, start, end);
                    edges_by_start[start].push(arena.push_edge(edge));
                    stats.graph_edges += 1;
                }
            }
            edges_by_start[start].sort_by(|left, right| {
                let left = arena.edge(*left);
                let right = arena.edge(*right);
                right
                    .end
                    .cmp(&left.end)
                    .then_with(|| right.syllable_count.cmp(&left.syllable_count))
                    .then_with(|| right.frequency.cmp(&left.frequency))
                    .then_with(|| left.reading.cmp(&right.reading))
                    .then_with(|| left.text.cmp(&right.text))
                    .then_with(|| left.entry_id.cmp(&right.entry_id))
            });
        }

        let mut beams = vec![Vec::<JointState>::new(); raw_len + 1];
        beams[0].push(JointState::default());
        let mut pruned_paths = BTreeSet::<String>::new();
        for position in 0..raw_len {
            trim_states(
                &mut beams[position],
                &arena,
                limits,
                &mut stats,
                &mut pruned_paths,
            );
            stats.max_beam_states = stats.max_beam_states.max(beams[position].len());
            let states = beams[position].clone();
            if states.is_empty() {
                continue;
            }
            for state in states {
                let mut expanded = false;
                for edge in &edges_by_start[position] {
                    if state.edge_count >= limits.max_sentence_words {
                        stats.joint_score_prunes += 1;
                        continue;
                    }
                    expanded = true;
                    let edge_end = arena.edge(*edge).end;
                    let mut next = arena.extend(state, *edge, context_model);
                    if edge_end == raw_len {
                        next.score += SentenceScorer::terminal_score(next.edge_count, true, false);
                    }
                    stats.explored_pinyin_hypotheses += 1;
                    beams[edge_end].push(next);
                }
                if !expanded {
                    stats.lexicon_prefix_unreachable_prunes += 1;
                }
            }
        }
        trim_states(
            &mut beams[raw_len],
            &arena,
            limits,
            &mut stats,
            &mut pruned_paths,
        );
        stats.max_beam_states = stats.max_beam_states.max(beams[raw_len].len());

        let mut complete_paths =
            self.direct_paths_for_signature(lexicon, raw_digits, explicit_boundaries, limits);
        complete_paths.extend(beams[raw_len].iter().map(|state| arena.as_path(*state)));
        complete_paths.sort_by(compare_path);
        let mut ranked_paths = Vec::new();
        let mut seen_paths = BTreeSet::new();
        for path in &complete_paths {
            let combination = path_combination(path);
            reachable_paths.insert(combination.clone());
            if seen_paths.insert(combination.clone()) {
                ranked_paths.push(combination);
            }
        }
        for path in &reachable_paths {
            if seen_paths.insert(path.clone()) {
                ranked_paths.push(path.clone());
            }
        }
        ranked_paths.truncate(limits.max_diagnostic_paths);

        let candidates_before_limit = complete_paths.len();
        let mut candidates = deduplicate_candidates(
            complete_paths
                .iter()
                .map(|path| SentenceCandidate::from_path(path, raw_len, true)),
        );
        stats.output_limit_prunes = candidates
            .len()
            .saturating_sub(limits.max_output_candidates);
        candidates.truncate(limits.max_output_candidates);
        if candidates_before_limit > candidates.len() {
            stats.output_limit_prunes = stats
                .output_limit_prunes
                .max(candidates_before_limit.saturating_sub(candidates.len()));
        }
        stats.peak_estimated_bytes = stats
            .graph_edges
            .saturating_mul(std::mem::size_of::<WordEdge>())
            .saturating_add(
                arena
                    .nodes
                    .len()
                    .saturating_mul(std::mem::size_of::<JointNode>()),
            )
            .saturating_add(
                stats
                    .max_beam_states
                    .saturating_mul(std::mem::size_of::<JointState>())
                    .saturating_mul(raw_len.saturating_add(1)),
            );

        T9JointDecodeResult {
            candidates,
            ranked_pinyin_paths: ranked_paths,
            lexicon_reachable_paths: reachable_paths
                .into_iter()
                .take(limits.max_diagnostic_paths)
                .collect(),
            beam_pruned_paths: pruned_paths
                .into_iter()
                .take(limits.max_diagnostic_paths)
                .collect(),
            stats,
        }
    }

    pub(crate) fn update_session(
        &self,
        lexicon: &BinaryLexicon,
        context_model: &CharacterBigramModel,
        session: &mut T9JointSession,
        raw_digits: &str,
        explicit_boundaries: &[usize],
        limits: &T9JointLimits,
    ) -> T9JointDecodeResult {
        if raw_digits.is_empty() {
            session.clear();
            return T9JointDecodeResult::default();
        }
        if raw_digits.len() > limits.max_raw_digits
            || raw_digits
                .bytes()
                .any(|digit| !(b'2'..=b'9').contains(&digit))
        {
            return T9JointDecodeResult::default();
        }

        if raw_digits == session.raw_digits
            && explicit_boundaries
                .iter()
                .all(|boundary| *boundary == raw_digits.len())
        {
            session.explicit_boundaries = explicit_boundaries.to_vec();
            return incremental_result(session, T9JointStats::default(), limits);
        }

        let previous_boundaries = explicit_boundaries
            .iter()
            .copied()
            .filter(|boundary| *boundary < raw_digits.len())
            .collect::<Vec<_>>();
        let is_append = raw_digits.len() == session.raw_digits.len() + 1
            && raw_digits.starts_with(&session.raw_digits)
            && previous_boundaries == session.explicit_boundaries;
        if is_append {
            session.explicit_boundaries = explicit_boundaries.to_vec();
            let stats =
                self.append_incremental(lexicon, context_model, session, raw_digits, limits);
            return incremental_result(session, stats, limits);
        }

        session.clear();
        let mut stats = T9JointStats::default();
        for end in 1..=raw_digits.len() {
            session.explicit_boundaries = explicit_boundaries
                .iter()
                .copied()
                .filter(|boundary| *boundary <= end)
                .collect();
            stats = self.append_incremental(
                lexicon,
                context_model,
                session,
                &raw_digits[..end],
                limits,
            );
        }
        incremental_result(session, stats, limits)
    }

    fn append_incremental(
        &self,
        lexicon: &BinaryLexicon,
        context_model: &CharacterBigramModel,
        session: &mut T9JointSession,
        new_raw_digits: &str,
        limits: &T9JointLimits,
    ) -> T9JointStats {
        let end = new_raw_digits.len();
        let min_start = end.saturating_sub(limits.max_word_digits.min(self.max_signature_len));
        let mut stats = T9JointStats::default();
        let mut incoming = Vec::<JointState>::new();
        let mut direct_paths = Vec::<SentencePath>::new();
        let mut pruned_paths = BTreeSet::<String>::new();

        for start in min_start..end {
            let Some(states) = session.beams.get(start).filter(|states| !states.is_empty()) else {
                continue;
            };
            let Some(indexed_signature) = self.by_signature.get(&new_raw_digits[start..end]) else {
                stats.lexicon_prefix_unreachable_prunes += states.len();
                continue;
            };
            let mut edges = Vec::<usize>::new();
            for indexed in &indexed_signature.search_entries {
                let entry = &lexicon.entries[indexed.entry_index];
                if !boundaries_compatible(
                    start,
                    end,
                    &indexed.syllable_boundaries,
                    &session.explicit_boundaries,
                ) {
                    continue;
                }
                if indexed.reading_rank >= limits.max_entries_per_reading {
                    continue;
                }
                if edges.len() >= limits.max_edges_per_position
                    || stats.graph_edges >= limits.max_graph_edges
                {
                    break;
                }
                let edge = word_edge(lexicon, entry, start, end);
                edges.push(session.arena.push_edge(edge));
                stats.graph_edges += 1;
            }
            if edges.is_empty() {
                stats.lexicon_prefix_unreachable_prunes += states.len();
                continue;
            }
            if start == 0 {
                direct_paths = self.direct_paths_for_signature(
                    lexicon,
                    new_raw_digits,
                    &session.explicit_boundaries,
                    limits,
                );
            }
            for state in states {
                if state.edge_count >= limits.max_sentence_words {
                    stats.joint_score_prunes += edges.len();
                    continue;
                }
                incoming.extend(
                    edges
                        .iter()
                        .map(|edge| session.arena.extend(*state, *edge, context_model)),
                );
                stats.explored_pinyin_hypotheses += edges.len();
            }
            if incoming.len() > limits.max_states_per_position.saturating_mul(4) {
                trim_states(
                    &mut incoming,
                    &session.arena,
                    limits,
                    &mut stats,
                    &mut pruned_paths,
                );
            }
        }
        trim_states(
            &mut incoming,
            &session.arena,
            limits,
            &mut stats,
            &mut pruned_paths,
        );
        stats.max_beam_states = incoming.len();
        session.raw_digits = new_raw_digits.to_owned();
        session.beams.push(incoming);
        session.direct_paths = direct_paths;
        session.last_pruned_paths = pruned_paths
            .into_iter()
            .take(limits.max_diagnostic_paths)
            .collect();
        stats.peak_estimated_bytes = session
            .beams
            .iter()
            .map(Vec::len)
            .sum::<usize>()
            .saturating_mul(std::mem::size_of::<JointState>())
            .saturating_add(
                session
                    .arena
                    .edges
                    .len()
                    .saturating_mul(std::mem::size_of::<WordEdge>()),
            )
            .saturating_add(
                session
                    .arena
                    .nodes
                    .len()
                    .saturating_mul(std::mem::size_of::<JointNode>()),
            )
            .saturating_add(
                session
                    .direct_paths
                    .len()
                    .saturating_mul(std::mem::size_of::<SentencePath>()),
            );
        stats
    }

    /// Complete lexicon matches are candidate-output material, not search
    /// states. Keeping their wider, separately bounded pool prevents the
    /// narrow sentence beam from discarding homophones before publication.
    fn direct_paths_for_signature(
        &self,
        lexicon: &BinaryLexicon,
        raw_digits: &str,
        explicit_boundaries: &[usize],
        limits: &T9JointLimits,
    ) -> Vec<SentencePath> {
        let Some(indexed_signature) = self.by_signature.get(raw_digits) else {
            return Vec::new();
        };
        let mut paths = Vec::new();
        for indexed in &indexed_signature.output_entries {
            let entry = &lexicon.entries[indexed.entry_index];
            if !boundaries_compatible(
                0,
                raw_digits.len(),
                &indexed.syllable_boundaries,
                explicit_boundaries,
            ) {
                continue;
            }
            if indexed.reading_rank >= limits.max_direct_entries_per_reading {
                continue;
            }
            if paths.len() >= limits.max_direct_paths {
                break;
            }
            let edge = word_edge(lexicon, entry, 0, raw_digits.len());
            paths.push(SentencePath {
                score: t9_edge_score(&edge) + SentenceScorer::terminal_score(1, true, false),
                edges: vec![edge],
            });
        }
        paths
    }
}

fn incremental_result(
    session: &T9JointSession,
    mut stats: T9JointStats,
    limits: &T9JointLimits,
) -> T9JointDecodeResult {
    let raw_len = session.raw_digits.len();
    if raw_len == 0 {
        return T9JointDecodeResult::default();
    }
    let mut complete_paths = session.direct_paths.clone();
    complete_paths.extend(session.beams[raw_len].iter().map(|state| {
        let mut path = session.arena.as_path(*state);
        path.score += SentenceScorer::terminal_score(path.edges.len(), true, false);
        path
    }));
    complete_paths.sort_by(compare_path);
    let mut reachable_paths = BTreeSet::<String>::new();
    let mut ranked_paths = Vec::new();
    let mut seen_paths = BTreeSet::new();
    for path in &complete_paths {
        let combination = path_combination(path);
        reachable_paths.insert(combination.clone());
        if seen_paths.insert(combination.clone()) {
            ranked_paths.push(combination);
        }
    }
    ranked_paths.truncate(limits.max_diagnostic_paths);

    let candidates_before_limit = complete_paths.len();
    let mut candidates = deduplicate_candidates(
        complete_paths
            .iter()
            .map(|path| SentenceCandidate::from_path(path, raw_len, true)),
    );
    stats.output_limit_prunes = candidates
        .len()
        .saturating_sub(limits.max_output_candidates)
        .max(candidates_before_limit.saturating_sub(limits.max_output_candidates));
    candidates.truncate(limits.max_output_candidates);
    T9JointDecodeResult {
        candidates,
        ranked_pinyin_paths: ranked_paths,
        lexicon_reachable_paths: reachable_paths
            .into_iter()
            .take(limits.max_diagnostic_paths)
            .collect(),
        beam_pruned_paths: session.last_pruned_paths.clone(),
        stats,
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct JointState {
    tail: Option<usize>,
    score: i64,
    edge_count: usize,
    fallback_count: usize,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
struct JointArena {
    edges: Vec<WordEdge>,
    nodes: Vec<JointNode>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct JointNode {
    parent: Option<usize>,
    edge: usize,
}

impl JointArena {
    fn push_edge(&mut self, edge: WordEdge) -> usize {
        let index = self.edges.len();
        self.edges.push(edge);
        index
    }

    fn edge(&self, index: usize) -> &WordEdge {
        &self.edges[index]
    }

    fn extend(
        &mut self,
        state: JointState,
        edge_index: usize,
        context_model: &CharacterBigramModel,
    ) -> JointState {
        let edge = &self.edges[edge_index];
        let transition = state
            .tail
            .map(|tail| {
                let previous = &self.edges[self.nodes[tail].edge];
                context_model
                    .transition_score(&previous.text, &edge.text)
                    .min(T9_MAX_CROSS_WORD_CONTEXT_SCORE)
            })
            .unwrap_or(0);
        let score = state.score + t9_edge_score(edge) + transition;
        let fallback_count = state.fallback_count + usize::from(edge.fallback);
        let node = self.nodes.len();
        self.nodes.push(JointNode {
            parent: state.tail,
            edge: edge_index,
        });
        JointState {
            tail: Some(node),
            score,
            edge_count: state.edge_count + 1,
            fallback_count,
        }
    }

    fn edge_indexes(&self, state: JointState) -> Vec<usize> {
        let mut indexes = Vec::with_capacity(state.edge_count);
        let mut node = state.tail;
        while let Some(index) = node {
            let current = &self.nodes[index];
            indexes.push(current.edge);
            node = current.parent;
        }
        indexes.reverse();
        indexes
    }

    fn as_path(&self, state: JointState) -> SentencePath {
        SentencePath {
            edges: self
                .edge_indexes(state)
                .into_iter()
                .map(|index| self.edges[index].clone())
                .collect(),
            score: state.score,
        }
    }
}

#[derive(Debug)]
struct JointSortKey {
    text: String,
    reading: String,
    path_key: String,
    combination: String,
}

impl JointSortKey {
    fn new(state: JointState, arena: &JointArena) -> Self {
        use std::fmt::Write as _;

        let indexes = arena.edge_indexes(state);
        let mut text = String::new();
        let mut reading = String::new();
        let mut path_key = String::new();
        for (position, index) in indexes.into_iter().enumerate() {
            let edge = arena.edge(index);
            text.push_str(&edge.text);
            if position > 0 {
                reading.push(' ');
                path_key.push('>');
            }
            reading.push_str(&edge.reading);
            write!(&mut path_key, "{}:{}:", edge.start, edge.end)
                .expect("writing to String cannot fail");
            for character in edge.reading.chars() {
                path_key.push(if character == ' ' { '_' } else { character });
            }
            path_key.push(':');
            path_key.push_str(&edge.text);
        }
        let combination = reading_combination(&reading);
        Self {
            text,
            reading,
            path_key,
            combination,
        }
    }
}

#[derive(Debug)]
struct RankedJointState {
    state: JointState,
    key: JointSortKey,
}

fn trim_states(
    states: &mut Vec<JointState>,
    arena: &JointArena,
    limits: &T9JointLimits,
    stats: &mut T9JointStats,
    pruned_paths: &mut BTreeSet<String>,
) {
    if states.is_empty() {
        return;
    }
    // Materialize compact scalar/string keys once per state. The old
    // comparator cloned the complete WordEdge path, then rebuilt text,
    // reading and path-key Strings on every comparison.
    let mut ranked = std::mem::take(states)
        .into_iter()
        .map(|state| RankedJointState {
            key: JointSortKey::new(state, arena),
            state,
        })
        .collect::<Vec<_>>();
    ranked.sort_by(|left, right| {
        right
            .state
            .score
            .cmp(&left.state.score)
            .then_with(|| left.state.fallback_count.cmp(&right.state.fallback_count))
            .then_with(|| left.state.edge_count.cmp(&right.state.edge_count))
            .then_with(|| left.key.text.cmp(&right.key.text))
            .then_with(|| left.key.reading.cmp(&right.key.reading))
            .then_with(|| left.key.path_key.cmp(&right.key.path_key))
    });
    let best_score = ranked[0].state.score;
    let score_cutoff = best_score.saturating_sub(limits.score_prune_delta);
    let score_keep = ranked.partition_point(|item| item.state.score >= score_cutoff);
    for item in &ranked[score_keep..] {
        pruned_paths.insert(item.key.combination.clone());
    }
    stats.joint_score_prunes += ranked.len().saturating_sub(score_keep);
    ranked.truncate(score_keep);

    // A homophone-rich reading can otherwise consume the entire beam with
    // different text realizations of the same pinyin. Candidate alternatives
    // are retained by the separate direct-output pool and bounded
    // compatibility decoder; the joint search reserves one state per reading.
    let before_diversity = ranked.len();
    let mut seen_combinations = BTreeSet::new();
    ranked.retain(|item| seen_combinations.insert(item.key.combination.clone()));
    stats.beam_capacity_prunes += before_diversity.saturating_sub(ranked.len());
    let capacity = limits.beam_width.min(limits.max_states_per_position);
    if ranked.len() > capacity {
        for item in &ranked[capacity..] {
            pruned_paths.insert(item.key.combination.clone());
        }
        stats.beam_capacity_prunes += ranked.len() - capacity;
        ranked.truncate(capacity);
    }
    states.extend(ranked.into_iter().map(|item| item.state));
}

fn entry_signature(entry: &LexiconEntry) -> Option<(String, Vec<usize>)> {
    let mut signature = String::new();
    let mut boundaries = Vec::with_capacity(entry.syllables.len());
    for syllable in &entry.syllables {
        signature.push_str(&t9_signature(syllable)?);
        boundaries.push(signature.len());
    }
    (!signature.is_empty()).then_some((signature, boundaries))
}

fn t9_signature(pinyin: &str) -> Option<String> {
    let mut output = String::with_capacity(pinyin.len());
    for letter in pinyin.bytes() {
        output.push(match letter {
            b'a'..=b'c' => '2',
            b'd'..=b'f' => '3',
            b'g'..=b'i' => '4',
            b'j'..=b'l' => '5',
            b'm'..=b'o' => '6',
            b'p'..=b's' => '7',
            b't'..=b'v' => '8',
            b'w'..=b'z' => '9',
            _ => return None,
        });
    }
    (!output.is_empty()).then_some(output)
}

fn boundaries_compatible(
    start: usize,
    end: usize,
    syllable_boundaries: &[usize],
    explicit_boundaries: &[usize],
) -> bool {
    explicit_boundaries
        .iter()
        .copied()
        .filter(|boundary| start < *boundary && *boundary < end)
        .all(|boundary| syllable_boundaries.contains(&(boundary - start)))
}

fn word_edge(lexicon: &BinaryLexicon, entry: &LexiconEntry, start: usize, end: usize) -> WordEdge {
    WordEdge {
        entry_id: format!(
            "lex-v{}-{}-{}",
            lexicon.header.lexicon_version,
            entry.pinyin_key.replace(' ', "_"),
            entry.word
        ),
        text: entry.word.clone(),
        reading: entry.pinyin_key.clone(),
        start,
        end,
        syllable_count: entry.syllables.len(),
        frequency: entry.frequency,
        source: entry.source_key(),
        fallback: false,
    }
}

fn t9_edge_score(edge: &WordEdge) -> i64 {
    let ambiguous_short_syllables = edge
        .reading
        .split_whitespace()
        .filter(|syllable| syllable.len() == 1)
        .count() as i64;
    SentenceScorer::edge_score(edge)
        .saturating_sub(ambiguous_short_syllables.saturating_mul(T9_SINGLE_LETTER_SYLLABLE_PENALTY))
        .saturating_sub((edge.syllable_count as i64).saturating_mul(T9_SYLLABLE_AMBIGUITY_PENALTY))
        .saturating_sub(T9_WORD_EDGE_PENALTY)
}

/// Returns the T9-only ambiguity cost for a candidate produced by the generic
/// compatibility decoder. Joint candidates already pay the same costs while
/// their edges are expanded, so callers must not apply this twice.
pub fn t9_sentence_candidate_penalty(candidate: &SentenceCandidate) -> i64 {
    let syllables = candidate.reading.split_whitespace().collect::<Vec<_>>();
    let ambiguous_short_syllables = syllables
        .iter()
        .filter(|syllable| syllable.len() == 1)
        .count() as i64;
    ambiguous_short_syllables
        .saturating_mul(T9_SINGLE_LETTER_SYLLABLE_PENALTY)
        .saturating_add((syllables.len() as i64).saturating_mul(T9_SYLLABLE_AMBIGUITY_PENALTY))
        .saturating_add((candidate.words.len() as i64).saturating_mul(T9_WORD_EDGE_PENALTY))
}

fn reading_combination(reading: &str) -> String {
    reading.split_whitespace().collect::<Vec<_>>().join("'")
}

fn path_combination(path: &SentencePath) -> String {
    reading_combination(&path.reading())
}

#[cfg(test)]
mod tests {
    use lexicon_core::{build_binary_lexicon, load_binary_lexicon};

    use super::*;

    fn entry(text: &str, reading: &str, frequency: u64) -> LexiconEntry {
        LexiconEntry::new(
            text.to_owned(),
            reading.to_owned(),
            reading.split_whitespace().map(str::to_owned).collect(),
            frequency,
            vec!["t9-joint-test".to_owned()],
        )
    }

    fn decode(
        entries: Vec<LexiconEntry>,
        digits: &str,
        boundaries: &[usize],
    ) -> T9JointDecodeResult {
        let bytes = build_binary_lexicon(&entries, 1, 1).unwrap();
        let lexicon = load_binary_lexicon(&bytes).unwrap();
        let index = T9LexiconIndex::build(&lexicon);
        let context = CharacterBigramModel::from_lexicon(&lexicon);
        index.decode(
            &lexicon,
            &context,
            digits,
            boundaries,
            &T9JointLimits::default(),
        )
    }

    #[test]
    fn whole_word_frequency_and_coverage_rank_the_pinyin_path() {
        let result = decode(
            vec![
                entry("你好", "ni hao", 100_000),
                entry("米干", "mi gan", 10),
                entry("你", "ni", 20_000),
                entry("好", "hao", 20_000),
            ],
            "64426",
            &[],
        );

        assert_eq!(result.candidates[0].text, "你好");
        assert_eq!(result.ranked_pinyin_paths[0], "ni'hao");
    }

    #[test]
    fn single_letter_over_segmentation_does_not_beat_a_complete_syllable() {
        let result = decode(
            vec![entry("的", "de", 10), entry("哦", "e", 1_000_000)],
            "33",
            &[],
        );

        assert_eq!(result.candidates[0].text, "的");
        assert_eq!(result.ranked_pinyin_paths[0], "de");
        let de = result
            .candidates
            .iter()
            .find(|candidate| candidate.reading == "de")
            .unwrap();
        let fragmented = result
            .candidates
            .iter()
            .find(|candidate| candidate.reading == "e e")
            .unwrap();
        assert!(t9_sentence_candidate_penalty(de) < t9_sentence_candidate_penalty(fragmented));
    }

    #[test]
    fn lexical_syllables_outrank_a_high_frequency_fragmented_path() {
        let result = decode(
            vec![
                entry("帮", "bang", 10),
                entry("住", "zhu", 1_000_000),
                entry("啊", "a", 1_000_000),
                entry("你", "ni", 1_000_000),
            ],
            "2264948",
            &[],
        );

        assert_eq!(result.ranked_pinyin_paths[0], "bang'zhu");
    }

    #[test]
    fn cross_word_bigram_cannot_overturn_stronger_lexical_words() {
        let result = decode(
            vec![
                entry("立刻", "li ke", 4_933),
                entry("离了", "li le", 241),
                entry("解决", "jie jue", 28_554),
                // Supplies a strong `了→解` character pair. It must not be
                // mistaken for evidence that `离了|解决` is a natural phrase.
                entry("了解", "liao jie", 1_000_000),
            ],
            "5453543583",
            &[],
        );

        assert_eq!(result.candidates[0].text, "立刻解决");
    }

    #[test]
    fn explicit_boundary_must_match_a_syllable_boundary() {
        let entries = vec![
            entry("你好", "ni hao", 100_000),
            entry("另读", "mian", 200_000),
        ];
        let unconstrained = decode(entries.clone(), "6426", &[]);
        assert!(unconstrained
            .candidates
            .iter()
            .any(|item| item.text == "另读"));

        let constrained = decode(entries, "6426", &[2]);
        assert!(!constrained
            .candidates
            .iter()
            .any(|item| item.text == "另读"));
    }

    #[test]
    fn beam_capacity_output_is_deterministic() {
        let entries = vec![
            entry("你", "ni", 100),
            entry("米", "mi", 100),
            entry("好", "hao", 100),
            entry("高", "gao", 100),
        ];
        let first = decode(entries.clone(), "64426", &[]);
        for _ in 0..3 {
            assert_eq!(decode(entries.clone(), "64426", &[]), first);
        }
    }

    #[test]
    fn beam_limit_reports_capacity_pruning_separately() {
        let entries = vec![
            entry("你", "ni", 100),
            entry("米", "mi", 90),
            entry("哦", "ng", 80),
        ];
        let bytes = build_binary_lexicon(&entries, 1, 1).unwrap();
        let lexicon = load_binary_lexicon(&bytes).unwrap();
        let index = T9LexiconIndex::build(&lexicon);
        let context = CharacterBigramModel::from_lexicon(&lexicon);
        let limits = T9JointLimits {
            beam_width: 1,
            max_states_per_position: 1,
            ..T9JointLimits::default()
        };

        let result = index.decode(&lexicon, &context, "64", &[], &limits);

        assert!(!result.candidates.is_empty());
        assert!(result.stats.beam_capacity_prunes > 0);
        assert!(!result.beam_pruned_paths.is_empty());
        assert_eq!(result.stats.joint_score_prunes, 0);
    }

    #[test]
    fn incremental_append_backspace_and_boundary_match_fresh_search() {
        let entries = vec![
            entry("你", "ni", 100_000),
            entry("好", "hao", 90_000),
            entry("你好", "ni hao", 150_000),
            entry("米安", "mi an", 20_000),
        ];
        let bytes = build_binary_lexicon(&entries, 1, 1).unwrap();
        let lexicon = load_binary_lexicon(&bytes).unwrap();
        let index = T9LexiconIndex::build(&lexicon);
        let context = CharacterBigramModel::from_lexicon(&lexicon);
        let limits = T9JointLimits::default();
        let mut session = T9JointSession::default();
        for end in 1..="64426".len() {
            let prefix = &"64426"[..end];
            let incremental =
                index.update_session(&lexicon, &context, &mut session, prefix, &[], &limits);
            let fresh = index.decode(&lexicon, &context, prefix, &[], &limits);
            assert_eq!(incremental.candidates, fresh.candidates);
            assert_eq!(incremental.ranked_pinyin_paths, fresh.ranked_pinyin_paths);
        }

        let backspaced =
            index.update_session(&lexicon, &context, &mut session, "6442", &[], &limits);
        assert_eq!(
            backspaced.candidates,
            index
                .decode(&lexicon, &context, "6442", &[], &limits)
                .candidates
        );

        let bounded = index.update_session(&lexicon, &context, &mut session, "64", &[2], &limits);
        assert_eq!(
            bounded.candidates,
            index
                .decode(&lexicon, &context, "64", &[2], &limits)
                .candidates
        );
    }

    #[test]
    fn bounded_edges_reserve_distinct_readings_before_extra_homophones() {
        let noisy_readings = ["mg", "mh", "mi", "ng"];
        let mut entries = Vec::new();
        for (reading_index, reading) in noisy_readings.into_iter().enumerate() {
            for homophone in 0..20 {
                entries.push(entry(
                    &format!("噪{reading_index:01}{homophone:02}"),
                    reading,
                    1_000_000 - homophone,
                ));
            }
        }
        entries.push(entry("目标", "ni", 1));
        let bytes = build_binary_lexicon(&entries, 1, 1).unwrap();
        let lexicon = load_binary_lexicon(&bytes).unwrap();
        let index = T9LexiconIndex::build(&lexicon);
        let context = CharacterBigramModel::from_lexicon(&lexicon);
        let limits = T9JointLimits {
            max_direct_paths: 1,
            ..T9JointLimits::default()
        };

        let result = index.decode(&lexicon, &context, "64", &[], &limits);

        assert!(result
            .candidates
            .iter()
            .any(|candidate| candidate.text == "目标"));
        assert!(result
            .lexicon_reachable_paths
            .iter()
            .any(|reading| reading == "ni"));
    }
}
