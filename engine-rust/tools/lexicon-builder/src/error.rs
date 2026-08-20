use std::fmt;
use std::path::PathBuf;

/// Error returned by the offline lexicon builder.
#[derive(Debug)]
pub enum BuildError {
    Argument(String),
    InputIo {
        path: PathBuf,
        source: std::io::Error,
    },
    OutputIo {
        path: PathBuf,
        source: std::io::Error,
    },
    InvalidUtf8 {
        path: PathBuf,
        source: std::string::FromUtf8Error,
    },
    Line(Box<LineError>),
    EmptyInput {
        path: PathBuf,
    },
    Binary(lexicon_core::LexiconError),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LineError {
    pub path: PathBuf,
    pub line: usize,
    pub word: Option<String>,
    pub pinyin: Option<String>,
    pub field: &'static str,
    pub reason: LineErrorReason,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LineErrorReason {
    FieldCount {
        expected: usize,
        actual: usize,
    },
    EmptyWord,
    EmptyPinyin,
    EmptyCode,
    EmptySource,
    InvalidSource {
        value: String,
    },
    InvalidCode {
        value: String,
    },
    InvalidFrequency {
        value: String,
    },
    FrequencyOutOfRange {
        value: String,
    },
    ControlCharacter {
        field: &'static str,
        ch: char,
    },
    UnsupportedWordCharacter {
        ch: char,
    },
    WordTooLong {
        actual: usize,
        max: usize,
    },
    TooManySyllables {
        actual: usize,
        max: usize,
    },
    InvalidPinyinSyllable {
        syllable: String,
        index: usize,
        detail: String,
    },
    SyllableCountMismatch {
        word_chars: usize,
        syllables: usize,
    },
    SourceOrderOutOfRange,
}

impl fmt::Display for BuildError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Argument(message) => write!(f, "{message}"),
            Self::InputIo { path, source } => {
                write!(f, "{}: input io error: {source}", path.display())
            }
            Self::OutputIo { path, source } => {
                write!(f, "{}: output io error: {source}", path.display())
            }
            Self::InvalidUtf8 { path, source } => {
                write!(f, "{}: invalid UTF-8: {source}", path.display())
            }
            Self::Line(error) => write!(f, "{error}"),
            Self::EmptyInput { path } => write!(f, "{}: no accepted lexicon rows", path.display()),
            Self::Binary(error) => write!(f, "binary lexicon error: {error}"),
        }
    }
}

impl std::error::Error for BuildError {}

impl From<lexicon_core::LexiconError> for BuildError {
    fn from(value: lexicon_core::LexiconError) -> Self {
        Self::Binary(value)
    }
}

impl fmt::Display for LineError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "{}:{}:", self.path.display(), self.line)?;
        writeln!(
            f,
            "word=\"{}\"",
            self.word.as_deref().unwrap_or("<unparsed>")
        )?;
        writeln!(
            f,
            "pinyin=\"{}\"",
            self.pinyin.as_deref().unwrap_or("<unparsed>")
        )?;
        write!(f, "field={}\nerror={}", self.field, self.reason)
    }
}

impl fmt::Display for LineErrorReason {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::FieldCount { expected, actual } => {
                write!(f, "expected {expected} TAB-separated fields, got {actual}")
            }
            Self::EmptyWord => write!(f, "word must not be empty"),
            Self::EmptyPinyin => write!(f, "pinyin must not be empty"),
            Self::EmptyCode => write!(f, "code must not be empty"),
            Self::EmptySource => write!(f, "source must not be empty"),
            Self::InvalidSource { value } => write!(f, "invalid source tag: {value}"),
            Self::InvalidCode { value } => write!(
                f,
                "invalid code: {value}; expected 1-64 lowercase ASCII letters"
            ),
            Self::InvalidFrequency { value } => write!(f, "invalid frequency: {value}"),
            Self::FrequencyOutOfRange { value } => {
                write!(f, "frequency is outside the allowed u64 range: {value}")
            }
            Self::ControlCharacter { field, ch } => {
                write!(f, "control character U+{:04X} in {field}", *ch as u32)
            }
            Self::UnsupportedWordCharacter { ch } => {
                write!(
                    f,
                    "current TSV format supports only common CJK words, got {ch}"
                )
            }
            Self::WordTooLong { actual, max } => {
                write!(f, "word has {actual} characters, max is {max}")
            }
            Self::TooManySyllables { actual, max } => {
                write!(f, "pinyin has {actual} syllables, max is {max}")
            }
            Self::InvalidPinyinSyllable {
                syllable,
                index,
                detail,
            } => write!(
                f,
                "invalid pinyin syllable \"{syllable}\" at syllable index {index}: {detail}"
            ),
            Self::SyllableCountMismatch {
                word_chars,
                syllables,
            } => write!(
                f,
                "word character count {word_chars} does not match pinyin syllable count {syllables}"
            ),
            Self::SourceOrderOutOfRange => write!(f, "source order exceeds the u32 range"),
        }
    }
}
