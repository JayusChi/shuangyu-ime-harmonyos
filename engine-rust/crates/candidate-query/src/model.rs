use candidate_ranking::{CandidateOrder, RankingCandidate};

use crate::error::QueryError;

/// Production page size requested by ArkTS when the caller does not override it.
pub const DEFAULT_CANDIDATE_PAGE_SIZE: usize = 50;
/// Upper bound on page size. Raised to allow a single scrollable page with all
/// candidates rather than splitting across multiple pages.
pub const MAX_CANDIDATE_PAGE_SIZE: usize = 500;

/// Stage 7 query mode.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub enum QueryMode {
    Exact,
    Prefix,
    /// Bounded lexical prefix recall for a single editable full-pinyin key.
    /// This avoids scanning the complete one-letter production range while
    /// still merging standalone readings such as `n` with common prefixes.
    PrefixLexical,
    /// Exact-only when present, otherwise longer keys sharing the prefix.
    ExactOrPrefix,
}

/// Query result kind after validation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QueryKind {
    Empty,
    Exact,
    Prefix,
}

/// Internal rollback boundary for incomplete double-pinyin prefix recall.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PrefixRecallStrategy {
    /// Stage 0 behavior: lexical index scan stops as soon as the legacy
    /// candidate limit is reached.
    LexicalEarlyStop,
    /// Stage 3 behavior: scan all matching indexes and retain a bounded global
    /// Top-K pool.
    GlobalTopK,
}

/// Centralized stage 7 query limits.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QueryConfig {
    pub default_page_size: usize,
    pub max_page_size: usize,
    /// Legacy exact-query and source-order snapshot limit.
    pub max_candidates: usize,
    /// Maximum system candidates retained from a complete double-pinyin
    /// prefix scan before user ranking.
    pub prefix_recall_limit: usize,
    /// Maximum double-pinyin prefix candidates retained after user ranking.
    pub prefix_snapshot_limit: usize,
    pub prefix_recall_strategy: PrefixRecallStrategy,
    /// Source-order prefix index limit. Existing-ranking prefix queries scan
    /// the complete matching index range instead of using this lexical cap.
    pub max_prefix_index_records: usize,
    pub cache_capacity: usize,
}

impl Default for QueryConfig {
    fn default() -> Self {
        Self {
            default_page_size: DEFAULT_CANDIDATE_PAGE_SIZE,
            max_page_size: MAX_CANDIDATE_PAGE_SIZE,
            max_candidates: 500,
            prefix_recall_limit: 512,
            prefix_snapshot_limit: 500,
            prefix_recall_strategy: PrefixRecallStrategy::GlobalTopK,
            max_prefix_index_records: 512,
            cache_capacity: 64,
        }
    }
}

impl QueryConfig {
    /// Applies the one page-size contract shared by query and engine backends.
    pub fn normalize_page_size(&self, requested: usize) -> Result<usize, QueryError> {
        if requested == 0 {
            return Err(QueryError::InvalidPageSize);
        }
        Ok(requested.min(self.max_page_size))
    }
}

/// Candidate query request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QueryRequest {
    pub scheme_id: String,
    pub reading: String,
    pub mode: QueryMode,
    pub page_size: usize,
    pub candidate_order: CandidateOrder,
}

impl QueryRequest {
    pub fn new(
        scheme_id: impl Into<String>,
        reading: impl Into<String>,
        mode: QueryMode,
        page_size: usize,
    ) -> Self {
        Self {
            scheme_id: scheme_id.into(),
            reading: reading.into(),
            mode,
            page_size,
            candidate_order: CandidateOrder::ExistingRanking,
        }
    }

    /// Selects an internal ordering policy without changing public IME APIs.
    pub fn with_candidate_order(mut self, candidate_order: CandidateOrder) -> Self {
        self.candidate_order = candidate_order;
        self
    }
}

/// Full ranked candidate query result. Pagination is owned by `ime-engine`.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QueryResult {
    pub kind: QueryKind,
    pub reading: String,
    pub candidates: Vec<RankingCandidate>,
    pub page_size: usize,
    pub cache_hit: bool,
}
