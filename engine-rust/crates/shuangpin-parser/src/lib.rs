//! Stateful shuangpin parser for stage 4.
//!
//! This crate turns raw shuangpin key codes into normalized pinyin syllables.
//! It is independent of ArkTS, C++, HarmonyOS APIs, dictionaries, and candidate
//! ranking.

pub mod error;
pub mod parser;
pub mod phonetic;
pub mod quanpin;
pub mod result;
pub mod state;
pub mod t9;

pub use error::ParseError;
pub use parser::ShuangpinParser;
pub use phonetic::{PhoneticParser, PhoneticParserKind, XiaoheShuangpinParserAdapter};
pub use quanpin::{QuanpinLatticeStats, QuanpinParser};
pub use result::{ParseResult, ParseStatus, ParsedSyllable, QueryIntent};
pub use state::ParserState;
pub use t9::{
    t9_letters, t9_signature, T9LatticeStats, T9PinyinParser, T9SyllableIndex,
    T9_MAX_GENERATED_STATES_PER_OFFSET, T9_MAX_INTERNAL_PINYIN_HYPOTHESES, T9_MAX_PATHS_PER_OFFSET,
    T9_MAX_PINYIN_COMBINATIONS, T9_MAX_RAW_DIGITS, T9_MAX_SYLLABLE_DIGITS,
    T9_PREFIX_CACHE_CAPACITY,
};
