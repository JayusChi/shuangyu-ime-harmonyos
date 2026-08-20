use std::fmt;

/// Recoverable errors produced by user-model validation and persistence.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum UserModelError {
    /// The caller supplied an empty, relative-only, or otherwise unusable path.
    InvalidPath,
    /// The supplied path exceeds the configured path length limit.
    PathTooLong,
    /// The on-disk file is larger than the configured maximum.
    FileTooLarge { actual: u64, max: u64 },
    /// The snapshot claims more records than this engine is willing to load.
    TooManyRecords { actual: u32, max: usize },
    /// The snapshot format version is not supported by this engine.
    UnsupportedVersion { version: u16 },
    /// The snapshot failed structural validation.
    Corrupt(&'static str),
    /// An operating-system I/O error occurred.
    Io(String),
}

impl UserModelError {
    /// Stable diagnostic code safe to expose across FFI.
    pub const fn code(&self) -> &'static str {
        match self {
            Self::InvalidPath => "invalid_path",
            Self::PathTooLong => "path_too_long",
            Self::FileTooLarge { .. } => "file_too_large",
            Self::TooManyRecords { .. } => "too_many_records",
            Self::UnsupportedVersion { .. } => "unsupported_version",
            Self::Corrupt(_) => "corrupt",
            Self::Io(_) => "io_error",
        }
    }
}

impl fmt::Display for UserModelError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPath => write!(f, "invalid user model path"),
            Self::PathTooLong => write!(f, "user model path is too long"),
            Self::FileTooLarge { actual, max } => {
                write!(f, "user model file is too large: {actual} > {max}")
            }
            Self::TooManyRecords { actual, max } => {
                write!(f, "user model record count is too large: {actual} > {max}")
            }
            Self::UnsupportedVersion { version } => {
                write!(f, "unsupported user model format version: {version}")
            }
            Self::Corrupt(reason) => write!(f, "corrupt user model: {reason}"),
            Self::Io(kind) => write!(f, "user model io error: {kind}"),
        }
    }
}

impl std::error::Error for UserModelError {}

impl From<std::io::Error> for UserModelError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value.kind().to_string())
    }
}
