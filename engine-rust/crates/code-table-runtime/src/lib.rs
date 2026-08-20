//! Deterministic, platform-independent runtime for verified classified code-table bundles.

mod action;
mod bundle;
mod category;
mod error;
mod file_bytes;
mod json;
mod manifest;
mod production;
mod query;
mod sha256;
mod state;

pub use action::{
    ActionRecord, DateTimeFormatId, FunctionalAction, FunctionalActionTable,
    ACTION_TABLE_FORMAT_VERSION, MAX_ACTION_TEXT_BYTES, MAX_PAIR_CURSOR_OFFSET_UTF16,
};
pub use bundle::{CodeTableBundle, CodeTableCategory, FIXTURE_SCHEME_ID, PRODUCTION_SCHEME_ID};
pub use category::{
    CategoryDefinition, CategoryKind, CategorySelectionSnapshot, CATEGORY_SCHEMA_VERSION,
    MAX_CATEGORY_ID_LEN,
};
pub use error::{CodeTableError, CodeTableErrorKind};
pub use production::{ProductionBundleMetadata, PRODUCTION_MAGIC};
pub use query::{
    query_exact_or_prefix, query_exact_or_prefix_with_snapshot, query_with_strategy,
    query_with_strategy_and_snapshot, CodeTableCandidate, CodeTableMatch, CodeTableQueryStrategy,
    QuerySnapshot,
};
pub use state::{
    CodeTableCommitPolicy, CodeTableInputState, CodeTableProcessOutcome, CodeTableSelection,
    CodeTableStateMachine, ResourceState,
};
