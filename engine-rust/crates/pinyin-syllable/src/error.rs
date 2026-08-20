use std::fmt;

/// Error returned when a pinyin syllable cannot be normalized or validated.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SyllableError {
    /// The input was empty after trimming whitespace.
    Empty,
    /// The input contains a character that is not accepted by the ASCII pinyin
    /// convention used by the engine.
    InvalidCharacter { ch: char },
    /// The normalized spelling is not in the maintained Mandarin syllable set.
    InvalidSyllable { syllable: String },
}

impl fmt::Display for SyllableError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Empty => write!(f, "empty pinyin syllable"),
            Self::InvalidCharacter { ch } => write!(f, "invalid pinyin character: {ch}"),
            Self::InvalidSyllable { syllable } => {
                write!(f, "invalid pinyin syllable: {syllable}")
            }
        }
    }
}

impl std::error::Error for SyllableError {}
