use std::fmt;

use shuangpin_schema::SchemaError;

/// Errors returned by the shuangpin parser.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ParseError {
    /// A processed key is not accepted by the current schema.
    InvalidKey { key: char },
    /// A two-key code cannot produce a legal pinyin syllable.
    InvalidCode { code: String },
    /// A generated syllable is outside the maintained pinyin inventory.
    InvalidSyllable { syllable: String },
    /// Loading or switching schema failed.
    Schema(SchemaError),
    /// A segment boundary requires a complete non-empty segment before it.
    InvalidSegmentBoundary,
    /// The parser found an impossible internal state.
    InternalStateInconsistent { reason: String },
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidKey { key } => write!(f, "invalid shuangpin key: {key}"),
            Self::InvalidCode { code } => write!(f, "invalid shuangpin code: {code}"),
            Self::InvalidSyllable { syllable } => {
                write!(f, "invalid generated syllable: {syllable}")
            }
            Self::Schema(err) => write!(f, "schema error: {err}"),
            Self::InvalidSegmentBoundary => write!(f, "invalid explicit segment boundary"),
            Self::InternalStateInconsistent { reason } => {
                write!(f, "internal parser state inconsistent: {reason}")
            }
        }
    }
}

impl std::error::Error for ParseError {}

impl From<SchemaError> for ParseError {
    fn from(value: SchemaError) -> Self {
        Self::Schema(value)
    }
}
