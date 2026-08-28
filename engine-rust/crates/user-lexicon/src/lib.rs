//! Deterministic user lexicon overlay for manual candidate rules.
//!
//! This crate is independent from the system binary lexicon and `user-model`.
//! It parses a small UTF-8 text file once, exposes an immutable runtime
//! snapshot, applies hard candidate ordering, and owns reliable persistence.

mod error;
mod merge;
mod model;
mod parser;
mod snapshot;
mod store;

pub use error::{UserLexiconError, UserLexiconField, UserLexiconReason};
pub use merge::{
    merge_candidates, merge_candidates_exact_or_prefix, merge_code_table_candidates,
    merge_code_table_exact_candidates, merge_code_table_hint_candidates,
    merge_code_table_progressive_candidates,
};
pub use model::{UserLexiconAction, UserLexiconEntry, UserLexiconStats};
pub use parser::{
    parse_embedded_user_lexicon_bytes, parse_user_lexicon_bytes, parse_user_lexicon_file,
    ParsedUserLexicon,
};
pub use snapshot::{merge_user_lexicon_snapshots, UserLexiconSnapshot};
pub use store::{
    load_snapshot_recovering, save_snapshot_atomic, save_snapshot_atomic_if_revision,
    UserLexiconLoadAction, UserLexiconLoadReport, UserLexiconStore,
};
