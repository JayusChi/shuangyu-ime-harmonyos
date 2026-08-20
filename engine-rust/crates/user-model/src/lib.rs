//! Local user learning model for candidate selection statistics.
//!
//! The model stores privacy-preserving stable candidate keys, bounded selection
//! counts, logical recency, and a compact versioned on-disk snapshot. It does
//! not depend on HarmonyOS APIs and never stores raw input or candidate text.

mod error;
mod key;
mod limits;
mod migration;
mod model;
mod persistence;
mod record;
mod recovery;
mod scoring;

pub use error::UserModelError;
pub use key::{CandidateSourceKind, UserCandidateKey};
pub use limits::{
    UserModelConfig, DATA_VERSION, FORMAT_VERSION, MAX_SELECTION_COUNT, MAX_USER_WEIGHT,
};
pub use model::{UserModel, UserModelStatus};
pub use record::UserRecord;
pub use recovery::{LoadAction, LoadReport};
pub use scoring::score_record;
