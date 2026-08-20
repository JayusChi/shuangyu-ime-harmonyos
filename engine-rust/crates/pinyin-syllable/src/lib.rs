//! Pinyin syllable normalization and validation for the Rust input engine.
//!
//! This crate is platform independent and owns the maintained tone-less
//! Mandarin pinyin syllable inventory used by stage 4 shuangpin parsing.

pub mod error;
pub mod inventory;
pub mod normalize;

pub use error::SyllableError;
pub use inventory::{all_syllables, syllable_count};
pub use normalize::{is_valid_syllable, normalize_syllable};
