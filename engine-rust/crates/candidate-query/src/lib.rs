//! Runtime candidate query over verified stage 6 binary lexicons.

mod cache;
mod error;
mod model;
mod query_engine;

pub use cache::{CacheKey, QueryCacheStats};
pub use candidate_ranking::CandidateOrder;
pub use error::QueryError;
pub use model::{
    PrefixRecallStrategy, QueryConfig, QueryKind, QueryMode, QueryRequest, QueryResult,
};
pub use query_engine::CandidateQueryEngine;
