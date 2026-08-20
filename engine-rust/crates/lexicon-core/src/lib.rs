//! Shared lexicon domain models and binary format support.
//!
//! This crate is platform independent. It owns the stage 6 binary lexicon
//! layout, checksum implementation, serialization, and defensive loading
//! checks used by offline tools and future runtime code.

pub mod binary;
pub mod checksum;
pub mod error;
pub mod model;
pub mod runtime_index;
pub mod validation;

pub use binary::{
    build_binary_lexicon, build_binary_lexicon_with_source_order, load_binary_lexicon,
    load_binary_lexicon_compact, BinaryLexicon, LexiconHeader, CHECKSUM_ALGORITHM_CRC32,
    FORMAT_MAJOR_VERSION, FORMAT_MINOR_VERSION, MAGIC,
};
pub use checksum::crc32_ieee;
pub use error::LexiconError;
pub use model::{LexiconEntry, PinyinIndex, SOURCE_ORDER_UNSPECIFIED};
pub use validation::{
    validate_code, validate_system_table_word, validate_word, CodeValidationError,
    WordValidationError, MAX_CODE_LEN, MAX_WORD_CHARS,
};
