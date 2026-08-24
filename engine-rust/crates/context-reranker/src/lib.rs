//! Bounded, deterministic word n-gram re-ranking for already recalled IME candidates.
//!
//! This crate deliberately has no lexicon, parser, network, or persistence
//! dependency. It can only assign a positive bounded bonus to a finite list of
//! existing candidates supplied by the IME engine.

use std::collections::{BTreeMap, HashMap};
use std::fs::File;
use std::io::Read;
use std::path::Path;

pub const MODEL_FORMAT_VERSION: u16 = 1;
pub const MODEL_VERSION: u16 = 2;
pub const MAX_MODEL_FILE_BYTES: usize = 256 * 1024;
pub const MAX_MODEL_MEMORY_BYTES: usize = 512 * 1024;
pub const MAX_MODEL_LOAD_MICROS: u64 = 250_000;
pub const MAX_BIGRAM_ENTRIES: usize = 4_096;
pub const MAX_TRIGRAM_ENTRIES: usize = 2_048;
pub const MAX_WORD_BYTES: usize = 48;
pub const MAX_NGRAM_COUNT: u32 = 1_000_000;
pub const MAX_CANDIDATE_POOL: usize = 16;
pub const MAX_NGRAM_CANDIDATES: usize = 12;
pub const MAX_WORDS_PER_CANDIDATE: usize = 8;
pub const MAX_CONTEXT_WORDS: usize = 2;
pub const MAX_BIGRAM_QUERIES: usize = 96;
pub const MAX_TRIGRAM_QUERIES: usize = 12;
pub const MAX_RERANK_MICROS: u64 = 5_000;
pub const MAX_ASSOCIATION_SUGGESTIONS: usize = 3;
pub const QUERY_CACHE_CAPACITY: usize = 0;
pub const MAX_BASE_SCORE_GAP_FOR_REORDER: i64 = 350;
pub const MAX_BIGRAM_BONUS: i64 = 96;
pub const MAX_TRIGRAM_BONUS: i64 = 144;

const MAGIC: &[u8; 8] = b"QPNGRM2\0";
const HEADER_LEN: usize = 52;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ModelLoadError {
    Io,
    TooLarge,
    InvalidHash,
    HashMismatch,
    Truncated,
    InvalidHeader,
    UnsupportedVersion,
    LexiconVersionMismatch,
    ContentHashMismatch,
    InvalidEntry,
    EntryLimit,
    MemoryLimit,
}

impl ModelLoadError {
    pub const fn code(&self) -> &'static str {
        match self {
            Self::Io => "io_error",
            Self::TooLarge => "too_large",
            Self::InvalidHash => "invalid_hash",
            Self::HashMismatch => "hash_mismatch",
            Self::Truncated => "truncated",
            Self::InvalidHeader => "invalid_header",
            Self::UnsupportedVersion => "unsupported_version",
            Self::LexiconVersionMismatch => "lexicon_version_mismatch",
            Self::ContentHashMismatch => "content_hash_mismatch",
            Self::InvalidEntry => "invalid_entry",
            Self::EntryLimit => "entry_limit",
            Self::MemoryLimit => "memory_limit",
        }
    }
}

impl std::fmt::Display for ModelLoadError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(self.code())
    }
}

impl std::error::Error for ModelLoadError {}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NgramBuildInput {
    pub bigrams: Vec<(String, String, u32)>,
    pub trigrams: Vec<(String, String, String, u32)>,
}

#[derive(Clone, Debug)]
pub struct WordNgramModel {
    lexicon_version: u32,
    // Nested maps permit allocation-free `&str` lookups on every key. The
    // per-key path remains bounded and never scans the model.
    bigrams: HashMap<String, HashMap<String, u32>>,
    trigrams: HashMap<String, HashMap<String, HashMap<String, u32>>>,
    file_bytes: usize,
    memory_bytes: usize,
}

impl WordNgramModel {
    pub fn build_bytes(
        lexicon_version: u32,
        input: &NgramBuildInput,
    ) -> Result<Vec<u8>, ModelLoadError> {
        let bigrams = normalize_bigrams(&input.bigrams)?;
        let trigrams = normalize_trigrams(&input.trigrams)?;
        let mut body = Vec::new();
        write_u32(&mut body, bigrams.len() as u32);
        write_u32(&mut body, trigrams.len() as u32);
        for ((left, right), count) in bigrams {
            write_word(&mut body, &left)?;
            write_word(&mut body, &right)?;
            write_u32(&mut body, count);
        }
        for ((left, middle, right), count) in trigrams {
            write_word(&mut body, &left)?;
            write_word(&mut body, &middle)?;
            write_word(&mut body, &right)?;
            write_u32(&mut body, count);
        }
        let content_hash = sha256(&body);
        let mut output = Vec::with_capacity(HEADER_LEN + body.len());
        output.extend_from_slice(MAGIC);
        write_u16(&mut output, MODEL_FORMAT_VERSION);
        write_u16(&mut output, MODEL_VERSION);
        write_u32(&mut output, lexicon_version);
        write_u32(&mut output, body.len() as u32);
        output.extend_from_slice(&content_hash);
        output.extend_from_slice(&body);
        if output.len() > MAX_MODEL_FILE_BYTES {
            return Err(ModelLoadError::TooLarge);
        }
        Ok(output)
    }

    pub fn load_file(
        path: &Path,
        expected_sha256: &str,
        expected_lexicon_version: u32,
    ) -> Result<Self, ModelLoadError> {
        let file = File::open(path).map_err(|_| ModelLoadError::Io)?;
        let mut bytes = Vec::with_capacity(MAX_MODEL_FILE_BYTES + 1);
        file.take((MAX_MODEL_FILE_BYTES + 1) as u64)
            .read_to_end(&mut bytes)
            .map_err(|_| ModelLoadError::Io)?;
        if bytes.len() > MAX_MODEL_FILE_BYTES {
            return Err(ModelLoadError::TooLarge);
        }
        Self::load_bytes(&bytes, expected_sha256, expected_lexicon_version)
    }

    pub fn load_bytes(
        bytes: &[u8],
        expected_sha256: &str,
        expected_lexicon_version: u32,
    ) -> Result<Self, ModelLoadError> {
        if bytes.len() > MAX_MODEL_FILE_BYTES {
            return Err(ModelLoadError::TooLarge);
        }
        if !is_sha256_hex(expected_sha256) {
            return Err(ModelLoadError::InvalidHash);
        }
        if !sha256_hex(bytes).eq_ignore_ascii_case(expected_sha256) {
            return Err(ModelLoadError::HashMismatch);
        }
        if bytes.len() < HEADER_LEN {
            return Err(ModelLoadError::Truncated);
        }
        if &bytes[..8] != MAGIC {
            return Err(ModelLoadError::InvalidHeader);
        }
        let format = read_u16(bytes, 8)?;
        let model_version = read_u16(bytes, 10)?;
        if format != MODEL_FORMAT_VERSION || model_version != MODEL_VERSION {
            return Err(ModelLoadError::UnsupportedVersion);
        }
        let lexicon_version = read_u32(bytes, 12)?;
        if lexicon_version != expected_lexicon_version {
            return Err(ModelLoadError::LexiconVersionMismatch);
        }
        let body_len = read_u32(bytes, 16)? as usize;
        if HEADER_LEN.checked_add(body_len) != Some(bytes.len()) {
            return Err(ModelLoadError::Truncated);
        }
        let expected_content_hash: [u8; 32] = bytes[20..52]
            .try_into()
            .map_err(|_| ModelLoadError::Truncated)?;
        let body = &bytes[HEADER_LEN..];
        if sha256(body) != expected_content_hash {
            return Err(ModelLoadError::ContentHashMismatch);
        }
        let mut cursor = 0usize;
        let bigram_count = take_u32(body, &mut cursor)? as usize;
        let trigram_count = take_u32(body, &mut cursor)? as usize;
        if bigram_count > MAX_BIGRAM_ENTRIES || trigram_count > MAX_TRIGRAM_ENTRIES {
            return Err(ModelLoadError::EntryLimit);
        }
        let mut bigrams = HashMap::<String, HashMap<String, u32>>::new();
        for _ in 0..bigram_count {
            let left = take_word(body, &mut cursor)?;
            let right = take_word(body, &mut cursor)?;
            let count = take_u32(body, &mut cursor)?;
            if !valid_word(&left) || !valid_word(&right) || count == 0 || count > MAX_NGRAM_COUNT {
                return Err(ModelLoadError::InvalidEntry);
            }
            if bigrams
                .entry(left)
                .or_default()
                .insert(right, count)
                .is_some()
            {
                return Err(ModelLoadError::InvalidEntry);
            }
        }
        let mut trigrams = HashMap::<String, HashMap<String, HashMap<String, u32>>>::new();
        for _ in 0..trigram_count {
            let left = take_word(body, &mut cursor)?;
            let middle = take_word(body, &mut cursor)?;
            let right = take_word(body, &mut cursor)?;
            let count = take_u32(body, &mut cursor)?;
            if !valid_word(&left)
                || !valid_word(&middle)
                || !valid_word(&right)
                || count == 0
                || count > MAX_NGRAM_COUNT
            {
                return Err(ModelLoadError::InvalidEntry);
            }
            if trigrams
                .entry(left)
                .or_default()
                .entry(middle)
                .or_default()
                .insert(right, count)
                .is_some()
            {
                return Err(ModelLoadError::InvalidEntry);
            }
        }
        if cursor != body.len() {
            return Err(ModelLoadError::InvalidEntry);
        }
        let memory_bytes = estimate_memory_bytes(&bigrams, &trigrams);
        if memory_bytes > MAX_MODEL_MEMORY_BYTES {
            return Err(ModelLoadError::MemoryLimit);
        }
        Ok(Self {
            lexicon_version,
            bigrams,
            trigrams,
            file_bytes: bytes.len(),
            memory_bytes,
        })
    }

    pub const fn lexicon_version(&self) -> u32 {
        self.lexicon_version
    }

    pub const fn file_bytes(&self) -> usize {
        self.file_bytes
    }

    pub const fn memory_bytes(&self) -> usize {
        self.memory_bytes
    }

    pub fn bigram_count(&self) -> usize {
        self.bigrams.values().map(HashMap::len).sum()
    }

    pub fn trigram_count(&self) -> usize {
        self.trigrams
            .values()
            .flat_map(HashMap::values)
            .map(HashMap::len)
            .sum()
    }

    /// Returns a bounded deterministic next-word list for an already-owned,
    /// in-memory context. No new model, history, or unbounded candidate pool is
    /// introduced for association suggestions.
    pub fn suggest_next(&self, committed_context: &[String], limit: usize) -> Vec<String> {
        let limit = limit.min(MAX_ASSOCIATION_SUGGESTIONS);
        if limit == 0 {
            return Vec::new();
        }
        let context = committed_context
            .iter()
            .filter(|word| valid_word(word))
            .rev()
            .take(MAX_CONTEXT_WORDS)
            .cloned()
            .collect::<Vec<_>>();
        let context = context.into_iter().rev().collect::<Vec<_>>();
        let trigram_rights = if context.len() == MAX_CONTEXT_WORDS {
            self.trigrams
                .get(&context[0])
                .and_then(|middles| middles.get(&context[1]))
        } else {
            None
        };
        if let Some(rights) = trigram_rights.filter(|rights| !rights.is_empty()) {
            return top_associations(rights, limit);
        }
        context
            .last()
            .and_then(|previous| self.bigrams.get(previous))
            .map(|rights| top_associations(rights, limit))
            .unwrap_or_default()
    }

    fn bigram_bonus(&self, left: &str, right: &str) -> Option<i64> {
        self.bigrams
            .get(left)
            .and_then(|rights| rights.get(right))
            .copied()
            .map(bigram_bonus)
    }

    fn trigram_bonus(&self, left: &str, middle: &str, right: &str) -> Option<i64> {
        self.trigrams
            .get(left)
            .and_then(|middles| middles.get(middle))
            .and_then(|rights| rights.get(right))
            .copied()
            .map(trigram_bonus)
    }
}

fn top_associations(rights: &HashMap<String, u32>, limit: usize) -> Vec<String> {
    let mut top = Vec::<(u32, String)>::with_capacity(limit + 1);
    for (word, count) in rights {
        top.push((*count, word.clone()));
        top.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
        top.truncate(limit);
    }
    top.into_iter().map(|(_, word)| word).collect()
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RerankCandidate {
    pub base_score: i64,
    pub words: Vec<String>,
    pub complete_coverage: bool,
    pub fallback_count: usize,
    pub fixed: bool,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct RerankStats {
    pub enabled: bool,
    pub candidate_pool_size: usize,
    pub candidates_scored: usize,
    pub candidates_with_ngram_hit: usize,
    pub protected_candidates: usize,
    pub skipped_candidate_limit: usize,
    pub skipped_word_limit: usize,
    pub bigram_queries: usize,
    pub bigram_hits: usize,
    pub trigram_queries: usize,
    pub trigram_hits: usize,
    pub trigram_backoffs: usize,
    pub model_file_bytes: usize,
    pub model_memory_bytes: usize,
    pub query_cache_capacity: usize,
    pub rerank_micros: u64,
    pub timeout_fallbacks: usize,
    pub skipped_rerank_calls: usize,
}

impl RerankStats {
    pub fn add_assign(&mut self, other: &Self) {
        self.enabled |= other.enabled;
        self.candidate_pool_size = self
            .candidate_pool_size
            .saturating_add(other.candidate_pool_size);
        self.candidates_scored = self
            .candidates_scored
            .saturating_add(other.candidates_scored);
        self.candidates_with_ngram_hit = self
            .candidates_with_ngram_hit
            .saturating_add(other.candidates_with_ngram_hit);
        self.protected_candidates = self
            .protected_candidates
            .saturating_add(other.protected_candidates);
        self.skipped_candidate_limit = self
            .skipped_candidate_limit
            .saturating_add(other.skipped_candidate_limit);
        self.skipped_word_limit = self
            .skipped_word_limit
            .saturating_add(other.skipped_word_limit);
        self.bigram_queries = self.bigram_queries.saturating_add(other.bigram_queries);
        self.bigram_hits = self.bigram_hits.saturating_add(other.bigram_hits);
        self.trigram_queries = self.trigram_queries.saturating_add(other.trigram_queries);
        self.trigram_hits = self.trigram_hits.saturating_add(other.trigram_hits);
        self.trigram_backoffs = self.trigram_backoffs.saturating_add(other.trigram_backoffs);
        self.model_file_bytes = other.model_file_bytes;
        self.model_memory_bytes = other.model_memory_bytes;
        self.query_cache_capacity = QUERY_CACHE_CAPACITY;
        self.rerank_micros = self.rerank_micros.max(other.rerank_micros);
        self.timeout_fallbacks = self
            .timeout_fallbacks
            .saturating_add(other.timeout_fallbacks);
        self.skipped_rerank_calls = self
            .skipped_rerank_calls
            .saturating_add(other.skipped_rerank_calls);
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContextWindow {
    words: Vec<String>,
    allowed: bool,
}

impl Default for ContextWindow {
    fn default() -> Self {
        Self {
            words: Vec::new(),
            allowed: true,
        }
    }
}

impl ContextWindow {
    pub fn words(&self) -> &[String] {
        &self.words
    }

    pub fn set_allowed(&mut self, allowed: bool) {
        self.allowed = allowed;
        if !allowed {
            self.clear();
        }
    }

    /// Stores at most two explicitly committed, already-tokenized words in RAM.
    /// It never writes to disk and ignores malformed or overlong words.
    pub fn record_committed_words(&mut self, words: &[String]) {
        if !self.allowed {
            return;
        }
        for word in words {
            if valid_word(word) {
                self.words.push(word.clone());
            }
        }
        let keep_from = self.words.len().saturating_sub(MAX_CONTEXT_WORDS);
        self.words.drain(..keep_from);
    }

    pub fn clear(&mut self) {
        self.words.clear();
    }
}

/// Returns a stable reordering of the supplied candidate positions. The caller
/// must keep candidate identity, de-duplication, and pagination unchanged.
pub fn rerank_order(
    model: Option<&WordNgramModel>,
    candidates: &[RerankCandidate],
    committed_context: &[String],
) -> (Vec<usize>, RerankStats) {
    let mut order = (0..candidates.len()).collect::<Vec<_>>();
    let Some(model) = model else {
        return (order, RerankStats::default());
    };
    let mut stats = RerankStats {
        enabled: true,
        candidate_pool_size: candidates.len().min(MAX_CANDIDATE_POOL),
        skipped_candidate_limit: candidates.len().saturating_sub(MAX_CANDIDATE_POOL),
        model_file_bytes: model.file_bytes(),
        model_memory_bytes: model.memory_bytes(),
        query_cache_capacity: QUERY_CACHE_CAPACITY,
        ..RerankStats::default()
    };
    let context = committed_context
        .iter()
        .filter(|word| valid_word(word))
        .rev()
        .take(MAX_CONTEXT_WORDS)
        .cloned()
        .collect::<Vec<_>>();
    let context = context.into_iter().rev().collect::<Vec<_>>();
    let pool_end = candidates.len().min(MAX_CANDIDATE_POOL);
    let top_score = candidates
        .first()
        .map(|candidate| candidate.base_score)
        .unwrap_or(0);
    let mut index = 0usize;
    while index < pool_end {
        if !eligible(&candidates[index], top_score) {
            stats.protected_candidates = stats.protected_candidates.saturating_add(1);
            index += 1;
            continue;
        }
        let start = index;
        while index < pool_end && eligible(&candidates[index], top_score) {
            index += 1;
        }
        let end = index;
        let mutable_end = (start + MAX_NGRAM_CANDIDATES).min(end);
        stats.skipped_candidate_limit = stats
            .skipped_candidate_limit
            .saturating_add(end.saturating_sub(mutable_end));
        let mut scored = Vec::new();
        for (position, candidate) in candidates.iter().enumerate().take(mutable_end).skip(start) {
            if candidate.words.len() > MAX_WORDS_PER_CANDIDATE {
                stats.skipped_word_limit = stats.skipped_word_limit.saturating_add(1);
                scored.push((candidate.base_score, position));
                continue;
            }
            let bonus = candidate_bonus(model, &candidate.words, &context, &mut stats);
            stats.candidates_scored = stats.candidates_scored.saturating_add(1);
            if bonus > 0 {
                stats.candidates_with_ngram_hit = stats.candidates_with_ngram_hit.saturating_add(1);
            }
            scored.push((candidate.base_score.saturating_add(bonus), position));
        }
        scored.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
        for (slot, (_, position)) in (start..mutable_end).zip(scored) {
            order[slot] = position;
        }
    }
    (order, stats)
}

fn eligible(candidate: &RerankCandidate, top_score: i64) -> bool {
    candidate.complete_coverage
        && candidate.fallback_count == 0
        && !candidate.fixed
        && candidate.base_score >= top_score.saturating_sub(MAX_BASE_SCORE_GAP_FOR_REORDER)
}

fn candidate_bonus(
    model: &WordNgramModel,
    words: &[String],
    context: &[String],
    stats: &mut RerankStats,
) -> i64 {
    let Some(first) = words.first() else {
        return 0;
    };
    if words.iter().any(|word| !valid_word(word)) {
        return 0;
    }
    let mut bonus = 0i64;
    if context.len() == MAX_CONTEXT_WORDS && stats.trigram_queries < MAX_TRIGRAM_QUERIES {
        stats.trigram_queries += 1;
        if let Some(value) = model.trigram_bonus(&context[0], &context[1], first) {
            stats.trigram_hits += 1;
            bonus = bonus.saturating_add(value);
        } else {
            stats.trigram_backoffs += 1;
            bonus = bonus.saturating_add(lookup_bigram(model, &context[1], first, stats));
        }
    } else if let Some(previous) = context.last() {
        bonus = bonus.saturating_add(lookup_bigram(model, previous, first, stats));
    }
    for pair in words.windows(2) {
        bonus = bonus.saturating_add(lookup_bigram(model, &pair[0], &pair[1], stats));
    }
    bonus
}

fn lookup_bigram(model: &WordNgramModel, left: &str, right: &str, stats: &mut RerankStats) -> i64 {
    if stats.bigram_queries >= MAX_BIGRAM_QUERIES {
        return 0;
    }
    stats.bigram_queries += 1;
    match model.bigram_bonus(left, right) {
        Some(value) => {
            stats.bigram_hits += 1;
            value
        }
        None => 0,
    }
}

fn normalize_bigrams(
    entries: &[(String, String, u32)],
) -> Result<BTreeMap<(String, String), u32>, ModelLoadError> {
    if entries.len() > MAX_BIGRAM_ENTRIES {
        return Err(ModelLoadError::EntryLimit);
    }
    let mut output = BTreeMap::<(String, String), u32>::new();
    for (left, right, count) in entries {
        if !valid_word(left) || !valid_word(right) || *count == 0 || *count > MAX_NGRAM_COUNT {
            return Err(ModelLoadError::InvalidEntry);
        }
        output
            .entry((left.clone(), right.clone()))
            .and_modify(|existing: &mut u32| {
                *existing = existing.saturating_add(*count).min(MAX_NGRAM_COUNT)
            })
            .or_insert(*count);
    }
    Ok(output)
}

fn normalize_trigrams(
    entries: &[(String, String, String, u32)],
) -> Result<BTreeMap<(String, String, String), u32>, ModelLoadError> {
    if entries.len() > MAX_TRIGRAM_ENTRIES {
        return Err(ModelLoadError::EntryLimit);
    }
    let mut output = BTreeMap::<(String, String, String), u32>::new();
    for (left, middle, right, count) in entries {
        if !valid_word(left)
            || !valid_word(middle)
            || !valid_word(right)
            || *count == 0
            || *count > MAX_NGRAM_COUNT
        {
            return Err(ModelLoadError::InvalidEntry);
        }
        output
            .entry((left.clone(), middle.clone(), right.clone()))
            .and_modify(|existing: &mut u32| {
                *existing = existing.saturating_add(*count).min(MAX_NGRAM_COUNT)
            })
            .or_insert(*count);
    }
    Ok(output)
}

fn valid_word(word: &str) -> bool {
    !word.is_empty()
        && word.len() <= MAX_WORD_BYTES
        && word
            .chars()
            .all(|character| !character.is_control() && !character.is_whitespace())
}

fn write_word(output: &mut Vec<u8>, word: &str) -> Result<(), ModelLoadError> {
    if !valid_word(word) {
        return Err(ModelLoadError::InvalidEntry);
    }
    output.push(word.len() as u8);
    output.extend_from_slice(word.as_bytes());
    Ok(())
}

fn take_word(input: &[u8], cursor: &mut usize) -> Result<String, ModelLoadError> {
    let len = *input.get(*cursor).ok_or(ModelLoadError::Truncated)? as usize;
    *cursor += 1;
    if len == 0 || len > MAX_WORD_BYTES || input.len().saturating_sub(*cursor) < len {
        return Err(ModelLoadError::InvalidEntry);
    }
    let bytes = &input[*cursor..*cursor + len];
    *cursor += len;
    String::from_utf8(bytes.to_vec()).map_err(|_| ModelLoadError::InvalidEntry)
}

fn write_u16(output: &mut Vec<u8>, value: u16) {
    output.extend_from_slice(&value.to_le_bytes());
}

fn write_u32(output: &mut Vec<u8>, value: u32) {
    output.extend_from_slice(&value.to_le_bytes());
}

fn read_u16(input: &[u8], offset: usize) -> Result<u16, ModelLoadError> {
    input
        .get(offset..offset + 2)
        .and_then(|bytes| bytes.try_into().ok())
        .map(u16::from_le_bytes)
        .ok_or(ModelLoadError::Truncated)
}

fn read_u32(input: &[u8], offset: usize) -> Result<u32, ModelLoadError> {
    input
        .get(offset..offset + 4)
        .and_then(|bytes| bytes.try_into().ok())
        .map(u32::from_le_bytes)
        .ok_or(ModelLoadError::Truncated)
}

fn take_u32(input: &[u8], cursor: &mut usize) -> Result<u32, ModelLoadError> {
    let value = read_u32(input, *cursor)?;
    *cursor += 4;
    Ok(value)
}

fn bigram_bonus(count: u32) -> i64 {
    ((count.ilog2() as i64 + 1) * 12).min(MAX_BIGRAM_BONUS)
}

fn trigram_bonus(count: u32) -> i64 {
    ((count.ilog2() as i64 + 1) * 18).min(MAX_TRIGRAM_BONUS)
}

fn estimate_memory_bytes(
    bigrams: &HashMap<String, HashMap<String, u32>>,
    trigrams: &HashMap<String, HashMap<String, HashMap<String, u32>>>,
) -> usize {
    let strings = bigrams
        .iter()
        .map(|(left, rights)| left.len() + rights.keys().map(String::len).sum::<usize>())
        .sum::<usize>()
        + trigrams
            .iter()
            .map(|(left, middles)| {
                left.len()
                    + middles
                        .iter()
                        .map(|(middle, rights)| {
                            middle.len() + rights.keys().map(String::len).sum::<usize>()
                        })
                        .sum::<usize>()
            })
            .sum::<usize>();
    let bigram_entries = bigrams.values().map(HashMap::len).sum::<usize>();
    let trigram_entries = trigrams
        .values()
        .flat_map(HashMap::values)
        .map(HashMap::len)
        .sum::<usize>();
    strings
        .saturating_add(bigram_entries.saturating_mul(112))
        .saturating_add(trigram_entries.saturating_mul(176))
}

pub fn sha256_hex(input: &[u8]) -> String {
    let mut output = String::with_capacity(64);
    for byte in sha256(input) {
        output.push_str(&format!("{byte:02x}"));
    }
    output
}

fn is_sha256_hex(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn sha256(input: &[u8]) -> [u8; 32] {
    const INITIAL: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let bit_len = (input.len() as u64).wrapping_mul(8);
    let mut padded = input.to_vec();
    padded.push(0x80);
    while !(padded.len() + 8).is_multiple_of(64) {
        padded.push(0);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());
    let mut state = INITIAL;
    for block in padded.chunks_exact(64) {
        let mut schedule = [0u32; 64];
        for (index, item) in schedule.iter_mut().take(16).enumerate() {
            *item = u32::from_be_bytes(block[index * 4..index * 4 + 4].try_into().expect("block"));
        }
        for index in 16..64 {
            let s0 = schedule[index - 15].rotate_right(7)
                ^ schedule[index - 15].rotate_right(18)
                ^ (schedule[index - 15] >> 3);
            let s1 = schedule[index - 2].rotate_right(17)
                ^ schedule[index - 2].rotate_right(19)
                ^ (schedule[index - 2] >> 10);
            schedule[index] = schedule[index - 16]
                .wrapping_add(s0)
                .wrapping_add(schedule[index - 7])
                .wrapping_add(s1);
        }
        let mut a = state[0];
        let mut b = state[1];
        let mut c = state[2];
        let mut d = state[3];
        let mut e = state[4];
        let mut f = state[5];
        let mut g = state[6];
        let mut h = state[7];
        for index in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let choose = (e & f) ^ ((!e) & g);
            let temp1 = h
                .wrapping_add(s1)
                .wrapping_add(choose)
                .wrapping_add(K[index])
                .wrapping_add(schedule[index]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let majority = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(majority);
            h = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        state[0] = state[0].wrapping_add(a);
        state[1] = state[1].wrapping_add(b);
        state[2] = state[2].wrapping_add(c);
        state[3] = state[3].wrapping_add(d);
        state[4] = state[4].wrapping_add(e);
        state[5] = state[5].wrapping_add(f);
        state[6] = state[6].wrapping_add(g);
        state[7] = state[7].wrapping_add(h);
    }
    let mut output = [0u8; 32];
    for (index, item) in state.iter().enumerate() {
        output[index * 4..index * 4 + 4].copy_from_slice(&item.to_be_bytes());
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn model() -> WordNgramModel {
        let input = NgramBuildInput {
            bigrams: vec![
                ("今天".into(), "天气".into(), 512),
                ("天气".into(), "不错".into(), 256),
                ("天气".into(), "不佳".into(), 1),
            ],
            trigrams: vec![("昨天".into(), "今天".into(), "天气".into(), 512)],
        };
        let bytes = WordNgramModel::build_bytes(7, &input).unwrap();
        let hash = sha256_hex(&bytes);
        WordNgramModel::load_bytes(&bytes, &hash, 7).unwrap()
    }

    fn candidate(score: i64, words: &[&str]) -> RerankCandidate {
        RerankCandidate {
            base_score: score,
            words: words.iter().map(|word| (*word).to_owned()).collect(),
            complete_coverage: true,
            fallback_count: 0,
            fixed: false,
        }
    }

    #[test]
    fn bigram_hit_lifts_existing_candidate_without_creating_one() {
        let candidates = vec![
            candidate(1_000, &["天气", "不佳"]),
            candidate(990, &["天气", "不错"]),
        ];
        let (order, stats) = rerank_order(Some(&model()), &candidates, &[]);
        assert_eq!(order, vec![1, 0]);
        assert_eq!(stats.bigram_hits, 2);
    }

    #[test]
    fn trigram_hit_precedes_bigram_and_miss_backs_off() {
        let candidates = vec![candidate(1_000, &["天气"]), candidate(995, &["不佳"])];
        let (order, hit) =
            rerank_order(Some(&model()), &candidates, &["昨天".into(), "今天".into()]);
        assert_eq!(order[0], 0);
        assert_eq!(hit.trigram_hits, 1);
        let (_, miss) = rerank_order(Some(&model()), &candidates, &["前天".into(), "今天".into()]);
        assert_eq!(miss.trigram_backoffs, 2);
        assert!(miss.bigram_queries >= 2);
    }

    #[test]
    fn no_hit_keeps_base_order_and_fixed_or_low_confidence_candidates_are_protected() {
        let candidates = vec![
            candidate(1_000, &["甲"]),
            RerankCandidate {
                fixed: true,
                ..candidate(999, &["天气", "不错"])
            },
            candidate(500, &["天气", "不错"]),
        ];
        let (order, stats) = rerank_order(Some(&model()), &candidates, &[]);
        assert_eq!(order, vec![0, 1, 2]);
        assert!(stats.protected_candidates >= 2);
    }

    #[test]
    fn corrupt_wrong_hash_and_wrong_version_fail_closed() {
        let bytes = WordNgramModel::build_bytes(
            7,
            &NgramBuildInput {
                bigrams: vec![],
                trigrams: vec![],
            },
        )
        .unwrap();
        let hash = sha256_hex(&bytes);
        assert_eq!(
            WordNgramModel::load_bytes(&bytes, &"0".repeat(64), 7).unwrap_err(),
            ModelLoadError::HashMismatch
        );
        assert_eq!(
            WordNgramModel::load_bytes(&bytes, &hash, 8).unwrap_err(),
            ModelLoadError::LexiconVersionMismatch
        );
        let mut corrupt = bytes.clone();
        corrupt[0] = b'X';
        assert_eq!(
            WordNgramModel::load_bytes(&corrupt, &sha256_hex(&corrupt), 7).unwrap_err(),
            ModelLoadError::InvalidHeader
        );
    }

    #[test]
    fn repeat_build_is_byte_identical_and_order_is_deterministic() {
        let input = NgramBuildInput {
            bigrams: vec![("乙".into(), "丙".into(), 2), ("甲".into(), "乙".into(), 3)],
            trigrams: vec![],
        };
        let first = WordNgramModel::build_bytes(1, &input).unwrap();
        assert_eq!(first, WordNgramModel::build_bytes(1, &input).unwrap());
        let hash = sha256_hex(&first);
        let model = WordNgramModel::load_bytes(&first, &hash, 1).unwrap();
        let candidates = vec![candidate(100, &["甲", "乙"]), candidate(100, &["乙", "丙"])];
        let expected = rerank_order(Some(&model), &candidates, &[]).0;
        for _ in 0..3 {
            assert_eq!(expected, rerank_order(Some(&model), &candidates, &[]).0);
        }
    }

    #[test]
    fn context_window_is_ephemeral_bounded_and_clearable() {
        let mut context = ContextWindow::default();
        context.record_committed_words(&["一".into(), "二".into(), "三".into()]);
        assert_eq!(context.words(), &["二", "三"]);
        context.set_allowed(false);
        assert!(context.words().is_empty());
        context.record_committed_words(&["四".into()]);
        assert!(context.words().is_empty());
    }

    #[test]
    fn local_associations_are_bounded_deterministic_and_use_trigram_then_bigram() {
        let model = model();
        assert_eq!(
            model.suggest_next(&["天气".into()], MAX_ASSOCIATION_SUGGESTIONS),
            vec!["不错", "不佳"]
        );
        assert_eq!(
            model.suggest_next(&["昨天".into(), "今天".into()], 1),
            vec!["天气"]
        );
        let expected = model.suggest_next(&["天气".into()], MAX_ASSOCIATION_SUGGESTIONS);
        for _ in 0..8 {
            assert_eq!(expected, model.suggest_next(&["天气".into()], 99));
        }
    }

    #[test]
    fn hard_limits_are_explicit() {
        assert_eq!(std::hint::black_box(QUERY_CACHE_CAPACITY), 0);
        assert_eq!(std::hint::black_box(MAX_CANDIDATE_POOL), 16);
        assert_eq!(std::hint::black_box(MAX_NGRAM_CANDIDATES), 12);
        assert_eq!(std::hint::black_box(MAX_WORDS_PER_CANDIDATE), 8);
        assert_eq!(std::hint::black_box(MAX_CONTEXT_WORDS), 2);
        assert_eq!(std::hint::black_box(MAX_BIGRAM_QUERIES), 96);
        assert_eq!(std::hint::black_box(MAX_TRIGRAM_QUERIES), 12);
        assert_eq!(std::hint::black_box(MAX_MODEL_FILE_BYTES), 256 * 1024);
        assert_eq!(std::hint::black_box(MAX_MODEL_MEMORY_BYTES), 512 * 1024);
        assert_eq!(std::hint::black_box(MAX_MODEL_LOAD_MICROS), 250_000);
        assert_eq!(std::hint::black_box(MAX_RERANK_MICROS), 5_000);
        assert_eq!(std::hint::black_box(MAX_ASSOCIATION_SUGGESTIONS), 3);
    }

    #[test]
    fn oversized_file_read_is_bounded_and_rejected_before_parsing() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "context-reranker-oversized-{}-{nanos}.qng",
            std::process::id()
        ));
        fs::write(&path, vec![0; MAX_MODEL_FILE_BYTES + 2]).unwrap();
        assert_eq!(
            WordNgramModel::load_file(&path, &"0".repeat(64), 1).unwrap_err(),
            ModelLoadError::TooLarge
        );
    }
}
