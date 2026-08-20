use std::fmt;

/// Structured failures produced before or during bounded sentence decoding.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum DecodeError {
    /// The raw key buffer is longer than the configured search limit.
    RawInputTooLong { actual: usize, max: usize },
    /// The complete syllable sequence is longer than the configured limit.
    TooManySyllables { actual: usize, max: usize },
    /// A limit field is zero where a positive value is required.
    InvalidLimit { field: &'static str },
}

impl fmt::Display for DecodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::RawInputTooLong { actual, max } => {
                write!(f, "raw input is too long: actual={actual}, max={max}")
            }
            Self::TooManySyllables { actual, max } => {
                write!(f, "too many syllables: actual={actual}, max={max}")
            }
            Self::InvalidLimit { field } => write!(f, "invalid decode limit: {field}"),
        }
    }
}

impl std::error::Error for DecodeError {}
