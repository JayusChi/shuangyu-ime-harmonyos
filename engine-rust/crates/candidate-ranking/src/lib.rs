//! Deterministic candidate ranking and deduplication.
//!
//! This crate uses only candidate fields and caller-supplied bounded scores.
//! It does not own user history, current context, language models, I/O, or
//! HarmonyOS state.

mod deduplication;
mod model;
mod ranking_policy;

pub use deduplication::{deduplicate_candidates, deduplicate_candidates_stable};
pub use model::{CandidateMatchType, CandidateOrder, RankingCandidate};
pub use ranking_policy::{
    compare_candidates, compare_prefix_candidates, prefix_quality_score, rank_candidates,
    rank_candidates_by_source_order, rank_candidates_with_order, rank_candidates_with_user_scores,
    rank_prefix_candidates, rank_prefix_candidates_with_user_scores,
};
