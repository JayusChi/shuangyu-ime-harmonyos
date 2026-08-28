use std::fmt;
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum UserLexiconField {
    File,
    Fields,
    Word,
    DisplayText,
    Code,
    Category,
    Marker,
    Position,
    SourceOrder,
    Storage,
}

impl UserLexiconField {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::File => "file",
            Self::Fields => "fields",
            Self::Word => "word",
            Self::DisplayText => "display_text",
            Self::Code => "code",
            Self::Category => "category",
            Self::Marker => "marker",
            Self::Position => "position",
            Self::SourceOrder => "source_order",
            Self::Storage => "storage",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum UserLexiconReason {
    Io(String),
    InvalidUtf8,
    FieldCount { actual: usize },
    EmptyWord,
    WordTooLong { actual: usize, max: usize },
    UnsupportedWordCharacter { codepoint: u32 },
    InvalidDisplayText,
    InvalidCategory,
    EmptyCode,
    InvalidCode,
    UnknownMarker,
    MultipleMarkers,
    MarkerNotAtEnd,
    InvalidPosition,
    PositionOutOfRange,
    SourceOrderOutOfRange,
    InvalidPath,
    RevisionConflict,
    CorruptPrimaryAndBackup,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserLexiconError {
    pub path: PathBuf,
    pub line: usize,
    pub field: UserLexiconField,
    pub reason: UserLexiconReason,
}

impl UserLexiconError {
    pub fn new(
        path: impl Into<PathBuf>,
        line: usize,
        field: UserLexiconField,
        reason: UserLexiconReason,
    ) -> Self {
        Self {
            path: path.into(),
            line,
            field,
            reason,
        }
    }

    pub const fn code(&self) -> &'static str {
        match self.reason {
            UserLexiconReason::Io(_) => "io_error",
            UserLexiconReason::InvalidUtf8 => "invalid_utf8",
            UserLexiconReason::InvalidPath => "invalid_path",
            UserLexiconReason::RevisionConflict => "revision_conflict",
            UserLexiconReason::CorruptPrimaryAndBackup => "corrupt",
            _ => "invalid_format",
        }
    }
}

impl fmt::Display for UserLexiconError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}:{}: field={}; error={}",
            self.path.display(),
            self.line,
            self.field.as_str(),
            self.reason
        )
    }
}

impl std::error::Error for UserLexiconError {}

impl fmt::Display for UserLexiconReason {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(kind) => write!(f, "io error: {kind}"),
            Self::InvalidUtf8 => write!(f, "file is not valid UTF-8"),
            Self::FieldCount { actual } => {
                write!(f, "expected exactly 2 TAB-separated fields, got {actual}")
            }
            Self::EmptyWord => write!(f, "word must not be empty"),
            Self::WordTooLong { actual, max } => {
                write!(f, "word has {actual} characters, max is {max}")
            }
            Self::UnsupportedWordCharacter { codepoint } => {
                write!(f, "unsupported word character U+{codepoint:04X}")
            }
            Self::InvalidDisplayText => {
                write!(f, "display text must contain 1-64 non-control characters")
            }
            Self::InvalidCategory => write!(
                f,
                "category must contain 1-64 lowercase ASCII letters, digits, or hyphens"
            ),
            Self::EmptyCode => write!(f, "code must not be empty"),
            Self::InvalidCode => write!(f, "code must contain 1-64 lowercase ASCII letters"),
            Self::UnknownMarker => write!(f, "unknown marker; expected #删, #固, or #N"),
            Self::MultipleMarkers => write!(f, "only one marker is allowed"),
            Self::MarkerNotAtEnd => write!(f, "marker must appear only at the end of code"),
            Self::InvalidPosition => {
                write!(f, "position must be an unsigned integer starting at 1")
            }
            Self::PositionOutOfRange => write!(f, "position is outside the u16 range"),
            Self::SourceOrderOutOfRange => write!(f, "source order is outside the u32 range"),
            Self::InvalidPath => write!(f, "invalid user lexicon path"),
            Self::RevisionConflict => write!(f, "user lexicon changed since it was loaded"),
            Self::CorruptPrimaryAndBackup => write!(f, "primary and backup are both invalid"),
        }
    }
}
