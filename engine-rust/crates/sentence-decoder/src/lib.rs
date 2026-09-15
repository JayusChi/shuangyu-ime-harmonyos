//! Deterministic stage 8 sentence decoding for the Rust IME core.
//!
//! The crate receives already parsed pinyin syllables plus an already loaded
//! binary lexicon. It owns graph construction, bounded Viterbi search, path
//! scoring, de-duplication, and partial-commit metadata. It does not parse
//! shuangpin mappings, read TSV files, expose C ABI, or depend on HarmonyOS.

mod context;
mod decoder;
mod error;
mod graph;
mod limits;
mod path;
mod scorer;
mod t9_joint;

pub use decoder::{DecodeResult, SentenceDecoder, XiaoheSentenceQuery};
pub use error::DecodeError;
pub use graph::FixedWordConstraint;
pub use limits::DecodeLimits;
pub use path::SentenceCandidate;
pub use t9_joint::{
    t9_sentence_candidate_penalty, T9JointDecodeResult, T9JointLimits, T9JointSession, T9JointStats,
};
