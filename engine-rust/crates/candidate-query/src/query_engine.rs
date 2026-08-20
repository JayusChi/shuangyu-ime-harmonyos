use candidate_ranking::{
    compare_candidates, rank_candidates_with_order, CandidateMatchType, CandidateOrder,
    RankingCandidate,
};
use lexicon_core::{runtime_index, BinaryLexicon, LexiconEntry};
use std::cmp::Ordering;
use std::collections::{BTreeMap, BinaryHeap};

use crate::cache::{BoundedQueryCache, CacheKey, QueryCacheStats};
use crate::error::QueryError;
use crate::model::{
    PrefixRecallStrategy, QueryConfig, QueryKind, QueryMode, QueryRequest, QueryResult,
};

/// Reusable runtime query engine for one loaded binary lexicon.
#[derive(Clone, Debug)]
pub struct CandidateQueryEngine {
    lexicon: BinaryLexicon,
    /// Compact full-pinyin lookup for long audited phrases. Keeping only
    /// entries of five or more syllables bounds memory while preventing a
    /// correct long word from depending on the parser's limited segmentation
    /// alternatives.
    quanpin_long_exact: BTreeMap<String, Vec<usize>>,
    /// Two-key lattice prefix index. Each lexicon row is indexed by every
    /// possible first two raw keys formed from full syllables or initials.
    /// This replaces the former first-letter bucket scan.
    quanpin_lattice_prefix: BTreeMap<String, Vec<usize>>,
    /// Pre-ranked, bounded one-letter pools used by full-pinyin initial input.
    /// Building these with the immutable lexicon prevents every reset/session
    /// from rescanning the complete production prefix range.
    single_letter_prefix: BTreeMap<char, Vec<RankingCandidate>>,
    config: QueryConfig,
    cache: BoundedQueryCache,
}

impl CandidateQueryEngine {
    pub fn new(lexicon: BinaryLexicon, config: QueryConfig) -> Self {
        let cache = BoundedQueryCache::new(config.cache_capacity);
        let mut quanpin_long_exact = BTreeMap::<String, Vec<usize>>::new();
        let mut quanpin_lattice_prefix = BTreeMap::<String, Vec<usize>>::new();
        let mut single_letter_pools = BTreeMap::<char, BoundedPrefixTopK>::new();
        let lexicon_version = lexicon.header.lexicon_version;
        for (index, entry) in lexicon.entries.iter().enumerate() {
            if entry.syllables.len() >= 5 {
                quanpin_long_exact
                    .entry(entry.syllables.concat())
                    .or_default()
                    .push(index);
            }
            for prefix in quanpin_lattice_prefixes(&entry.syllables) {
                quanpin_lattice_prefix
                    .entry(prefix)
                    .or_default()
                    .push(index);
            }
            if let Some(initial) = entry
                .pinyin_key
                .chars()
                .next()
                .filter(char::is_ascii_lowercase)
            {
                let initial_reading = initial.to_string();
                let match_type = if entry.pinyin_key == initial_reading {
                    CandidateMatchType::Exact
                } else {
                    CandidateMatchType::Prefix
                };
                single_letter_pools
                    .entry(initial)
                    .or_insert_with(|| BoundedPrefixTopK::new(config.prefix_recall_limit))
                    .push(
                        RankingCandidate::new(
                            stable_candidate_id(lexicon_version, &entry.pinyin_key, &entry.word),
                            entry.word.clone(),
                            entry.pinyin_key.clone(),
                            entry.source_key(),
                            entry.frequency,
                            match_type,
                        )
                        .with_source_order(entry.source_order),
                    );
            }
        }
        let single_letter_prefix = single_letter_pools
            .into_iter()
            .map(|(initial, pool)| (initial, pool.into_candidates()))
            .collect();
        Self {
            lexicon,
            quanpin_long_exact,
            quanpin_lattice_prefix,
            single_letter_prefix,
            config,
            cache,
        }
    }

    pub fn lexicon_version(&self) -> u32 {
        self.lexicon.header.lexicon_version
    }

    pub fn config(&self) -> &QueryConfig {
        &self.config
    }

    pub fn clear_cache(&mut self) {
        self.cache.clear();
    }

    pub fn cache_stats(&self) -> QueryCacheStats {
        self.cache.stats()
    }

    /// Recalls entries for the full-pinyin editable lattice. Each syllable may
    /// be represented by its full spelling or by its initial; the final
    /// syllable may also be an unfinished prefix. A bounded number of trailing
    /// syllables may remain untyped so inputs such as `gj` can offer useful
    /// continue-typing candidates without treating raw ASCII as committed
    /// text. Exact full-pinyin is intentionally excluded: the normal exact and
    /// sentence decoders remain authoritative and therefore always rank above
    /// this tolerant recall tier.
    pub fn recall_quanpin_lattice(&self, raw_input: &str, limit: usize) -> Vec<RankingCandidate> {
        let raw = raw_input
            .chars()
            .filter(|character| *character != '\'')
            .collect::<String>();
        if raw.len() < 2 || limit == 0 || !raw.bytes().all(|byte| byte.is_ascii_lowercase()) {
            return Vec::new();
        }

        let prefix = raw[..2].to_owned();
        let mut matches = self
            .quanpin_lattice_prefix
            .get(&prefix)
            .into_iter()
            .flatten()
            .filter_map(|index| self.lexicon.entries.get(*index))
            .filter_map(|entry| {
                let quality = quanpin_lattice_match(&raw, &entry.syllables)?;
                // A zero-cost path is ordinary exact full pinyin and is owned
                // by the normal decoder. Requiring at least one abbreviation
                // prevents this tolerant scan from perturbing exact ranking.
                if quality.abbreviated == 0 {
                    return None;
                }
                Some((quality, entry))
            })
            .collect::<Vec<_>>();
        matches.sort_by(|(left_quality, left), (right_quality, right)| {
            left_quality
                .cmp(right_quality)
                .then_with(|| right.frequency.cmp(&left.frequency))
                .then_with(|| left.word.cmp(&right.word))
                .then_with(|| left.pinyin_key.cmp(&right.pinyin_key))
        });

        let mut seen_text = std::collections::BTreeSet::new();
        matches
            .into_iter()
            .filter(|(_, entry)| seen_text.insert(entry.word.clone()))
            .take(limit)
            .map(|(_, entry)| self.to_candidate(entry, &raw, CandidateMatchType::Prefix))
            .collect()
    }

    /// Recalls only audited lexicon entries whose complete five-or-more
    /// syllable pinyin exactly matches the compact full-pinyin input.
    pub fn recall_quanpin_long_exact(
        &self,
        raw_input: &str,
        limit: usize,
    ) -> Vec<RankingCandidate> {
        let raw = raw_input
            .chars()
            .filter(|character| *character != '\'')
            .collect::<String>();
        if raw.is_empty() || limit == 0 || !raw.bytes().all(|byte| byte.is_ascii_lowercase()) {
            return Vec::new();
        }
        let mut candidates = self
            .quanpin_long_exact
            .get(&raw)
            .into_iter()
            .flatten()
            .filter_map(|index| self.lexicon.entries.get(*index))
            .map(|entry| self.to_candidate(entry, &raw, CandidateMatchType::Exact))
            .collect::<Vec<_>>();
        candidates.sort_by(compare_candidates);
        candidates.truncate(limit);
        candidates
    }

    pub fn query(&mut self, request: QueryRequest) -> Result<QueryResult, QueryError> {
        let page_size = self.config.normalize_page_size(request.page_size)?;
        let reading = normalize_reading(&request.reading)?;
        if reading.is_empty() {
            return Ok(QueryResult {
                kind: QueryKind::Empty,
                reading,
                candidates: Vec::new(),
                page_size,
                cache_hit: false,
            });
        }

        let key = CacheKey {
            scheme_id: request.scheme_id,
            reading: reading.clone(),
            mode: request.mode,
            candidate_order: request.candidate_order,
            page_size,
            lexicon_version: self.lexicon_version(),
        };
        if let Some(candidates) = self.cache.get(&key) {
            return Ok(QueryResult {
                kind: self.query_kind(request.mode, &reading),
                reading,
                candidates,
                page_size,
                cache_hit: true,
            });
        }

        let (candidates, candidate_limit) = match request.mode {
            QueryMode::Exact => (self.collect_exact(&reading), self.config.max_candidates),
            QueryMode::PrefixLexical => (
                self.collect_single_letter_prefix(&reading),
                self.config.prefix_recall_limit,
            ),
            QueryMode::Prefix
                if request.candidate_order == CandidateOrder::ExistingRanking
                    && self.config.prefix_recall_strategy
                        == PrefixRecallStrategy::LexicalEarlyStop =>
            {
                (
                    self.collect_lexical_prefix(&reading),
                    self.config.max_candidates,
                )
            }
            QueryMode::Prefix if request.candidate_order == CandidateOrder::ExistingRanking => (
                self.collect_ranked_prefix_top_k(&reading),
                self.config.prefix_recall_limit,
            ),
            QueryMode::Prefix => (
                self.collect_source_order_prefix(&reading),
                self.config.max_candidates,
            ),
            QueryMode::ExactOrPrefix => {
                let exact = self.collect_exact(&reading);
                if exact.is_empty() {
                    (
                        self.collect_source_order_prefix(&reading),
                        self.config.max_candidates,
                    )
                } else {
                    (exact, self.config.max_candidates)
                }
            }
        };
        let mut ranked = rank_candidates_with_order(candidates, request.candidate_order);
        ranked.truncate(candidate_limit);
        self.cache.insert(key, ranked.clone());

        Ok(QueryResult {
            kind: self.query_kind(request.mode, &reading),
            reading,
            candidates: ranked,
            page_size,
            cache_hit: false,
        })
    }

    fn collect_exact(&self, reading: &str) -> Vec<RankingCandidate> {
        let Some(index) = runtime_index::find_exact_index(&self.lexicon, reading) else {
            return Vec::new();
        };
        self.entries_for_range(index.start, index.len, reading, CandidateMatchType::Exact)
    }

    fn collect_source_order_prefix(&self, reading: &str) -> Vec<RankingCandidate> {
        let mut candidates = Vec::new();
        let indexes = runtime_index::find_prefix_indexes(&self.lexicon, reading, usize::MAX);
        for index in indexes {
            let match_type = if index.pinyin_key == reading {
                CandidateMatchType::Exact
            } else {
                CandidateMatchType::Prefix
            };
            candidates.extend(self.entries_for_range(index.start, index.len, reading, match_type));
        }
        candidates
    }

    fn collect_lexical_prefix(&self, reading: &str) -> Vec<RankingCandidate> {
        let mut candidates = Vec::new();
        for index in runtime_index::find_prefix_indexes(
            &self.lexicon,
            reading,
            self.config.max_prefix_index_records,
        ) {
            let match_type = if index.pinyin_key == reading {
                CandidateMatchType::Exact
            } else {
                CandidateMatchType::Prefix
            };
            candidates.extend(self.entries_for_range(index.start, index.len, reading, match_type));
            if candidates.len() >= self.config.max_candidates {
                break;
            }
        }
        candidates.truncate(self.config.max_candidates);
        candidates
    }

    fn collect_single_letter_prefix(&self, reading: &str) -> Vec<RankingCandidate> {
        let mut characters = reading.chars();
        let Some(initial) = characters.next() else {
            return Vec::new();
        };
        if characters.next().is_some() {
            return self.collect_lexical_prefix(reading);
        }
        self.single_letter_prefix
            .get(&initial)
            .cloned()
            .unwrap_or_default()
    }

    /// Scans every matching pinyin index while retaining only the globally
    /// best bounded set. The pool is unique by visible candidate text.
    fn collect_ranked_prefix_top_k(&self, reading: &str) -> Vec<RankingCandidate> {
        let mut top_k = BoundedPrefixTopK::new(self.config.prefix_recall_limit);
        for index in runtime_index::find_prefix_indexes(&self.lexicon, reading, usize::MAX) {
            let match_type = if index.pinyin_key == reading {
                CandidateMatchType::Exact
            } else {
                CandidateMatchType::Prefix
            };
            let start = index.start as usize;
            let end = start
                .saturating_add(index.len as usize)
                .min(self.lexicon.entries.len());
            for entry in &self.lexicon.entries[start..end] {
                top_k.push(self.to_candidate(entry, reading, match_type));
            }
        }
        top_k.into_candidates()
    }

    fn entries_for_range(
        &self,
        start: u32,
        len: u32,
        query_reading: &str,
        match_type: CandidateMatchType,
    ) -> Vec<RankingCandidate> {
        let start = start as usize;
        let end = start
            .saturating_add(len as usize)
            .min(self.lexicon.entries.len());
        self.lexicon.entries[start..end]
            .iter()
            .map(|entry| self.to_candidate(entry, query_reading, match_type))
            .collect()
    }

    fn to_candidate(
        &self,
        entry: &LexiconEntry,
        _query_reading: &str,
        match_type: CandidateMatchType,
    ) -> RankingCandidate {
        RankingCandidate::new(
            stable_candidate_id(self.lexicon_version(), &entry.pinyin_key, &entry.word),
            entry.word.clone(),
            entry.pinyin_key.clone(),
            entry.source_key(),
            entry.frequency,
            match_type,
        )
        .with_source_order(entry.source_order)
    }

    fn query_kind(&self, mode: QueryMode, reading: &str) -> QueryKind {
        match mode {
            QueryMode::Exact => QueryKind::Exact,
            QueryMode::Prefix | QueryMode::PrefixLexical => QueryKind::Prefix,
            QueryMode::ExactOrPrefix => {
                if runtime_index::find_exact_index(&self.lexicon, reading).is_some() {
                    QueryKind::Exact
                } else {
                    QueryKind::Prefix
                }
            }
        }
    }
}

fn quanpin_lattice_prefixes(syllables: &[String]) -> Vec<String> {
    fn visit(syllables: &[String], index: usize, raw: &mut String, output: &mut Vec<String>) {
        if raw.len() >= 2 {
            output.push(raw[..2].to_owned());
            return;
        }
        let Some(syllable) = syllables.get(index) else {
            return;
        };
        let initial = &syllable[..1];
        let original_len = raw.len();
        raw.push_str(syllable);
        visit(syllables, index + 1, raw, output);
        raw.truncate(original_len);
        raw.push_str(initial);
        visit(syllables, index + 1, raw, output);
        raw.truncate(original_len);
    }

    let mut output = Vec::new();
    visit(syllables, 0, &mut String::new(), &mut output);
    output.sort();
    output.dedup();
    output
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
struct QuanpinLatticeQuality {
    trailing_syllables: usize,
    incomplete_tail: usize,
    abbreviated: usize,
}

fn quanpin_lattice_match(raw: &str, syllables: &[String]) -> Option<QuanpinLatticeQuality> {
    if syllables.is_empty() {
        return None;
    }
    let mut states = vec![(0usize, 0usize, 0usize)];
    // state = (raw byte offset, abbreviation count, incomplete-tail penalty)
    for syllable in syllables {
        let mut next = Vec::new();
        for (offset, abbreviated, incomplete_tail) in states {
            if offset == raw.len() {
                continue;
            }
            let remaining = &raw[offset..];
            if remaining.starts_with(syllable) {
                next.push((offset + syllable.len(), abbreviated, incomplete_tail));
            }
            if remaining.as_bytes().first() == syllable.as_bytes().first() {
                next.push((offset + 1, abbreviated + 1, incomplete_tail));
            }
            if remaining.len() < syllable.len()
                && syllable.starts_with(remaining)
                && remaining.len() > 1
            {
                next.push((raw.len(), abbreviated, syllable.len() - remaining.len()));
            }
        }
        next.sort_unstable();
        next.dedup();
        states = next;
        if states.is_empty() {
            return quanpin_prefix_match(raw, syllables);
        }
    }

    states
        .into_iter()
        .filter(|(offset, _, _)| *offset == raw.len())
        .map(|(_, abbreviated, incomplete_tail)| QuanpinLatticeQuality {
            trailing_syllables: 0,
            incomplete_tail,
            abbreviated,
        })
        .min()
        .or_else(|| {
            // The loop retains completed-raw states while walking the
            // remaining reading. Re-evaluate the cheapest prefix explicitly
            // and allow at most two untyped syllables.
            quanpin_prefix_match(raw, syllables)
        })
}

fn quanpin_prefix_match(raw: &str, syllables: &[String]) -> Option<QuanpinLatticeQuality> {
    let mut states = vec![(0usize, 0usize)];
    for (index, syllable) in syllables.iter().enumerate() {
        let mut next = Vec::new();
        for (offset, abbreviated) in states {
            if offset == raw.len() {
                let trailing = syllables.len() - index;
                if trailing <= 2 {
                    return Some(QuanpinLatticeQuality {
                        trailing_syllables: trailing,
                        incomplete_tail: 0,
                        abbreviated,
                    });
                }
                continue;
            }
            let remaining = &raw[offset..];
            if remaining.starts_with(syllable) {
                next.push((offset + syllable.len(), abbreviated));
            }
            if remaining.as_bytes().first() == syllable.as_bytes().first() {
                next.push((offset + 1, abbreviated + 1));
            }
        }
        states = next;
    }
    None
}

/// A text-deduplicated bounded Top-K pool. Memory remains O(K) even when one
/// prefix matches thousands of lexicon rows.
struct BoundedPrefixTopK {
    limit: usize,
    candidates_by_text: BTreeMap<String, (RankingCandidate, u64)>,
    worst_first: BinaryHeap<PrefixHeapEntry>,
    next_version: u64,
}

impl BoundedPrefixTopK {
    fn new(limit: usize) -> Self {
        Self {
            limit,
            candidates_by_text: BTreeMap::new(),
            worst_first: BinaryHeap::new(),
            next_version: 0,
        }
    }

    fn push(&mut self, candidate: RankingCandidate) {
        if self.limit == 0 {
            return;
        }
        if let Some((existing, _)) = self.candidates_by_text.get(&candidate.text) {
            if compare_candidates(&candidate, existing).is_lt() {
                self.insert(candidate);
            }
            return;
        }
        if self.candidates_by_text.len() < self.limit {
            self.insert(candidate);
            return;
        }
        self.prune_stale();
        let Some(worst) = self.worst_first.peek() else {
            return;
        };
        if !compare_candidates(&candidate, &worst.candidate).is_lt() {
            return;
        }
        let worst = self.worst_first.pop().expect("peeked heap entry");
        self.candidates_by_text.remove(&worst.candidate.text);
        self.insert(candidate);
    }

    fn into_candidates(self) -> Vec<RankingCandidate> {
        self.candidates_by_text
            .into_values()
            .map(|(candidate, _)| candidate)
            .collect()
    }

    fn insert(&mut self, candidate: RankingCandidate) {
        self.next_version = self.next_version.saturating_add(1);
        let version = self.next_version;
        self.candidates_by_text
            .insert(candidate.text.clone(), (candidate.clone(), version));
        self.worst_first
            .push(PrefixHeapEntry { candidate, version });
        if self.worst_first.len() > self.limit.saturating_mul(2).max(1) {
            self.worst_first = self
                .candidates_by_text
                .values()
                .map(|(candidate, version)| PrefixHeapEntry {
                    candidate: candidate.clone(),
                    version: *version,
                })
                .collect();
        }
    }

    fn prune_stale(&mut self) {
        while let Some(entry) = self.worst_first.peek() {
            let is_current = self
                .candidates_by_text
                .get(&entry.candidate.text)
                .is_some_and(|(_, version)| *version == entry.version);
            if is_current {
                break;
            }
            self.worst_first.pop();
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct PrefixHeapEntry {
    candidate: RankingCandidate,
    version: u64,
}

impl Ord for PrefixHeapEntry {
    fn cmp(&self, other: &Self) -> Ordering {
        compare_candidates(&self.candidate, &other.candidate)
            .then_with(|| self.version.cmp(&other.version))
    }
}

impl PartialOrd for PrefixHeapEntry {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

fn normalize_reading(reading: &str) -> Result<String, QueryError> {
    let normalized = reading.split_whitespace().collect::<Vec<_>>().join(" ");
    if normalized.is_empty() {
        return Ok(normalized);
    }
    if normalized
        .chars()
        .all(|ch| ch == ' ' || ch.is_ascii_lowercase())
    {
        Ok(normalized)
    } else {
        Err(QueryError::InvalidReading)
    }
}

fn stable_candidate_id(lexicon_version: u32, reading: &str, text: &str) -> String {
    format!(
        "lex-v{}-{}-{}",
        lexicon_version,
        reading.replace(' ', "_"),
        text
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use lexicon_core::{build_binary_lexicon, load_binary_lexicon, LexiconEntry};

    fn sample_engine() -> CandidateQueryEngine {
        let entries = vec![
            LexiconEntry::new(
                "你".to_owned(),
                "ni".to_owned(),
                vec!["ni".to_owned()],
                100,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "你好".to_owned(),
                "ni hao".to_owned(),
                vec!["ni".to_owned(), "hao".to_owned()],
                90,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "输入".to_owned(),
                "shu ru".to_owned(),
                vec!["shu".to_owned(), "ru".to_owned()],
                80,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "输入法".to_owned(),
                "shu ru fa".to_owned(),
                vec!["shu".to_owned(), "ru".to_owned(), "fa".to_owned()],
                70,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "其间".to_owned(),
                "qi jian".to_owned(),
                vec!["qi".to_owned(), "jian".to_owned()],
                10,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "期间".to_owned(),
                "qi jian".to_owned(),
                vec!["qi".to_owned(), "jian".to_owned()],
                20,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "过几天".to_owned(),
                "guo ji tian".to_owned(),
                vec!["guo".to_owned(), "ji".to_owned(), "tian".to_owned()],
                30_000,
                vec!["test".to_owned()],
            ),
        ];
        let bytes = build_binary_lexicon(&entries, 42, 1).unwrap();
        CandidateQueryEngine::new(
            load_binary_lexicon(&bytes).unwrap(),
            QueryConfig {
                default_page_size: 2,
                max_page_size: 3,
                max_candidates: 4,
                prefix_recall_limit: 4,
                prefix_snapshot_limit: 3,
                prefix_recall_strategy: PrefixRecallStrategy::GlobalTopK,
                max_prefix_index_records: 4,
                cache_capacity: 2,
            },
        )
    }

    fn source_order_engine() -> CandidateQueryEngine {
        let rows = [
            ("第一词", "abz", 0),
            ("第二词", "aba", 1),
            ("第三词", "abz", 2),
            ("第四词", "abc", 3),
            ("第五词", "abd", 4),
            ("第六词", "abe", 5),
        ];
        let entries = rows
            .into_iter()
            .map(|(word, code, order)| {
                LexiconEntry::new(
                    word.to_owned(),
                    code.to_owned(),
                    vec![code.to_owned()],
                    0,
                    vec!["flypy-table".to_owned()],
                )
                .with_source_order(order)
            })
            .collect::<Vec<_>>();
        let bytes = lexicon_core::build_binary_lexicon_with_source_order(&entries, 1, 1).unwrap();
        CandidateQueryEngine::new(
            load_binary_lexicon(&bytes).unwrap(),
            QueryConfig {
                default_page_size: 2,
                max_page_size: 2,
                max_candidates: 64,
                prefix_recall_limit: 128,
                prefix_snapshot_limit: 100,
                prefix_recall_strategy: PrefixRecallStrategy::GlobalTopK,
                max_prefix_index_records: 1,
                cache_capacity: 4,
            },
        )
    }

    #[test]
    fn exact_single_syllable_query_returns_single_character() {
        let mut engine = sample_engine();
        let result = engine
            .query(QueryRequest::new("xiaohe", "ni", QueryMode::Exact, 2))
            .unwrap();

        assert_eq!(result.kind, QueryKind::Exact);
        assert_eq!(result.candidates[0].text, "你");
        assert_eq!(result.candidates[0].reading, "ni");
    }

    #[test]
    fn exact_multi_syllable_query_returns_existing_word_only() {
        let mut engine = sample_engine();
        let result = engine
            .query(QueryRequest::new(
                "xiaohe",
                "shu ru fa",
                QueryMode::Exact,
                2,
            ))
            .unwrap();

        assert_eq!(result.candidates.len(), 1);
        assert_eq!(result.candidates[0].text, "输入法");
    }

    #[test]
    fn prefix_query_is_bounded_and_uses_sorted_index() {
        let mut engine = sample_engine();
        let result = engine
            .query(QueryRequest::new("xiaohe", "shu", QueryMode::Prefix, 99))
            .unwrap();

        assert_eq!(result.page_size, 3);
        assert_eq!(result.candidates.len(), 2);
        assert_eq!(result.candidates[0].text, "输入");
        assert_eq!(result.candidates[1].text, "输入法");
    }

    #[test]
    fn empty_input_does_not_return_whole_lexicon() {
        let mut engine = sample_engine();
        let result = engine
            .query(QueryRequest::new("xiaohe", "", QueryMode::Prefix, 2))
            .unwrap();

        assert_eq!(result.kind, QueryKind::Empty);
        assert!(result.candidates.is_empty());
    }

    #[test]
    fn invalid_reading_and_zero_page_size_are_rejected() {
        let mut engine = sample_engine();
        assert_eq!(
            engine.query(QueryRequest::new("xiaohe", "Ni", QueryMode::Exact, 2)),
            Err(QueryError::InvalidReading)
        );
        assert_eq!(
            engine.query(QueryRequest::new("xiaohe", "ni", QueryMode::Exact, 0)),
            Err(QueryError::InvalidPageSize)
        );
    }

    #[test]
    fn production_default_accepts_fifty_and_clamps_oversized_requests() {
        let config = QueryConfig::default();
        assert_eq!(config.default_page_size, 50);
        assert_eq!(config.max_page_size, 500);
        assert_eq!(config.max_candidates, 500);
        assert_eq!(config.prefix_recall_limit, 512);
        assert_eq!(config.prefix_snapshot_limit, 500);
        assert_eq!(
            config.prefix_recall_strategy,
            PrefixRecallStrategy::GlobalTopK
        );
        assert_eq!(config.normalize_page_size(50), Ok(50));
        assert_eq!(config.normalize_page_size(9), Ok(9));
        assert_eq!(config.normalize_page_size(usize::MAX), Ok(500));
        assert_eq!(
            config.normalize_page_size(0),
            Err(QueryError::InvalidPageSize)
        );
    }

    #[test]
    fn duplicate_readings_are_ranked_by_frequency() {
        let mut engine = sample_engine();
        let result = engine
            .query(QueryRequest::new("xiaohe", "qi jian", QueryMode::Exact, 2))
            .unwrap();

        assert_eq!(result.candidates[0].text, "期间");
        assert_eq!(result.candidates[1].text, "其间");
    }

    #[test]
    fn repeated_query_hits_cache_and_preserves_order() {
        let mut engine = sample_engine();
        let first = engine
            .query(QueryRequest::new("xiaohe", "ni", QueryMode::Prefix, 2))
            .unwrap();
        let second = engine
            .query(QueryRequest::new("xiaohe", "ni", QueryMode::Prefix, 2))
            .unwrap();

        assert!(!first.cache_hit);
        assert!(second.cache_hit);
        assert_eq!(first.candidates, second.candidates);
        assert_eq!(engine.cache_stats().hits, 1);
    }

    #[test]
    fn quanpin_lattice_recalls_initials_and_mixed_spellings() {
        let engine = sample_engine();
        for raw in ["gj", "gjt", "guojt", "gjitian"] {
            let recalled = engine.recall_quanpin_lattice(raw, 16);
            assert!(
                recalled.iter().any(|candidate| candidate.text == "过几天"),
                "missing mixed/initial recall for {raw}"
            );
        }
        assert!(engine.recall_quanpin_lattice("guojitian", 16).is_empty());
    }

    #[test]
    fn prefix_top_k_scans_later_branches_before_truncation() {
        let entries = vec![
            LexiconEntry::new(
                "低甲".to_owned(),
                "ha".to_owned(),
                vec!["ha".to_owned()],
                1,
                vec!["test".to_owned()],
            ),
            LexiconEntry::new(
                "低乙".to_owned(),
                "hai".to_owned(),
                vec!["hai".to_owned()],
                2,
                vec!["test".to_owned()],
            ),
            LexiconEntry::new(
                "高甲".to_owned(),
                "he".to_owned(),
                vec!["he".to_owned()],
                10_000,
                vec!["test".to_owned()],
            ),
            LexiconEntry::new(
                "高乙".to_owned(),
                "huo".to_owned(),
                vec!["huo".to_owned()],
                9_000,
                vec!["test".to_owned()],
            ),
        ];
        let bytes = build_binary_lexicon(&entries, 43, 1).unwrap();
        let mut engine = CandidateQueryEngine::new(
            load_binary_lexicon(&bytes).unwrap(),
            QueryConfig {
                default_page_size: 2,
                max_page_size: 2,
                max_candidates: 2,
                prefix_recall_limit: 2,
                prefix_snapshot_limit: 2,
                prefix_recall_strategy: PrefixRecallStrategy::GlobalTopK,
                max_prefix_index_records: 1,
                cache_capacity: 2,
            },
        );

        let result = engine
            .query(QueryRequest::new("xiaohe", "h", QueryMode::Prefix, 2))
            .unwrap();

        assert_eq!(
            result
                .candidates
                .iter()
                .map(|candidate| candidate.reading.as_str())
                .collect::<Vec<_>>(),
            vec!["he", "huo"]
        );
    }

    #[test]
    fn prefix_top_k_deduplicates_visible_text_across_readings() {
        let entries = vec![
            LexiconEntry::new(
                "行".to_owned(),
                "hang".to_owned(),
                vec!["hang".to_owned()],
                10,
                vec!["test".to_owned()],
            ),
            LexiconEntry::new(
                "行".to_owned(),
                "heng".to_owned(),
                vec!["heng".to_owned()],
                20,
                vec!["test".to_owned()],
            ),
            LexiconEntry::new(
                "和".to_owned(),
                "he".to_owned(),
                vec!["he".to_owned()],
                15,
                vec!["test".to_owned()],
            ),
        ];
        let bytes = build_binary_lexicon(&entries, 44, 1).unwrap();
        let mut engine = CandidateQueryEngine::new(
            load_binary_lexicon(&bytes).unwrap(),
            QueryConfig {
                prefix_recall_limit: 8,
                prefix_snapshot_limit: 4,
                ..QueryConfig::default()
            },
        );

        let result = engine
            .query(QueryRequest::new("xiaohe", "h", QueryMode::Prefix, 8))
            .unwrap();

        assert_eq!(
            result
                .candidates
                .iter()
                .filter(|candidate| candidate.text == "行")
                .count(),
            1
        );
        assert_eq!(
            result
                .candidates
                .iter()
                .find(|candidate| candidate.text == "行")
                .unwrap()
                .reading,
            "heng"
        );
    }

    #[test]
    fn cache_capacity_evicts_old_entries() {
        let mut engine = sample_engine();
        for reading in ["ni", "shu", "qi"] {
            let _ = engine
                .query(QueryRequest::new("xiaohe", reading, QueryMode::Prefix, 2))
                .unwrap();
        }

        assert_eq!(engine.cache_stats().len, 2);
    }

    #[test]
    fn no_dynamic_sentence_assembly_is_performed() {
        let mut engine = sample_engine();
        let result = engine
            .query(QueryRequest::new("xiaohe", "ni shu", QueryMode::Exact, 2))
            .unwrap();

        assert!(result.candidates.is_empty());
    }

    #[test]
    fn source_order_mode_uses_exact_or_prefix_fallback_rules() {
        let mut engine = source_order_engine();
        let exact = engine
            .query(
                QueryRequest::new("flypy-table", "abz", QueryMode::ExactOrPrefix, 2)
                    .with_candidate_order(CandidateOrder::SourceOrder),
            )
            .unwrap();
        assert_eq!(exact.kind, QueryKind::Exact);
        assert_eq!(
            exact
                .candidates
                .iter()
                .map(|candidate| candidate.text.as_str())
                .collect::<Vec<_>>(),
            vec!["第一词", "第三词"]
        );

        let fallback = engine
            .query(
                QueryRequest::new("flypy-table", "ab", QueryMode::ExactOrPrefix, 2)
                    .with_candidate_order(CandidateOrder::SourceOrder),
            )
            .unwrap();
        assert_eq!(fallback.kind, QueryKind::Prefix);
        assert_eq!(
            fallback
                .candidates
                .iter()
                .map(|candidate| candidate.text.as_str())
                .collect::<Vec<_>>(),
            vec!["第一词", "第二词", "第三词", "第四词", "第五词", "第六词"]
        );

        let cached = engine
            .query(
                QueryRequest::new("flypy-table", "ab", QueryMode::ExactOrPrefix, 2)
                    .with_candidate_order(CandidateOrder::SourceOrder),
            )
            .unwrap();
        assert!(cached.cache_hit);
        assert_eq!(fallback.candidates, cached.candidates);
    }

    #[test]
    fn source_order_mode_sorts_before_stable_pagination() {
        let mut engine = source_order_engine();
        let result = engine
            .query(
                QueryRequest::new("flypy-table", "ab", QueryMode::ExactOrPrefix, 2)
                    .with_candidate_order(CandidateOrder::SourceOrder),
            )
            .unwrap();
        let pages = result
            .candidates
            .chunks(result.page_size)
            .collect::<Vec<_>>();
        assert_eq!(pages.len(), 3);
        assert_eq!(pages[0][0].text, "第一词");
        assert_eq!(pages[1][0].text, "第三词");
        assert_eq!(pages[2][0].text, "第五词");
        let flattened = pages
            .into_iter()
            .flat_map(|page| page.iter().map(|candidate| candidate.text.as_str()))
            .collect::<Vec<_>>();
        assert_eq!(
            flattened,
            vec!["第一词", "第二词", "第三词", "第四词", "第五词", "第六词"]
        );
    }

    #[test]
    fn source_order_mode_empty_input_does_not_enumerate_table() {
        let mut engine = source_order_engine();
        let result = engine
            .query(
                QueryRequest::new("flypy-table", "", QueryMode::ExactOrPrefix, 2)
                    .with_candidate_order(CandidateOrder::SourceOrder),
            )
            .unwrap();
        assert_eq!(result.kind, QueryKind::Empty);
        assert!(result.candidates.is_empty());
    }
}
