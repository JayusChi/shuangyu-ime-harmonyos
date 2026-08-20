use std::fmt;
use std::path::Path;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ErrorCode {
    Cli,
    FrozenHashMismatch,
    JsonInvalid,
    ContractInvalid,
    ContractVersion,
    IdentityMismatch,
    CategoryInvalid,
    PathInvalid,
    SymlinkRejected,
    SourceMissing,
    SourceSizeMismatch,
    SourceHashMismatch,
    InvalidUtf8,
    UnsafeControl,
    InvalidRecord,
    Serialization,
    Integrity,
    OutputUnsafe,
    Io,
}

impl ErrorCode {
    pub const fn reason(self) -> &'static str {
        match self {
            Self::Cli => "YX_CLI_INVALID",
            Self::FrozenHashMismatch => "YX_FROZEN_HASH_MISMATCH",
            Self::JsonInvalid => "YX_JSON_INVALID",
            Self::ContractInvalid => "YX_CONTRACT_INVALID",
            Self::ContractVersion => "YX_CONTRACT_VERSION_UNSUPPORTED",
            Self::IdentityMismatch => "YX_IDENTITY_MISMATCH",
            Self::CategoryInvalid => "YX_CATEGORY_INVALID",
            Self::PathInvalid => "YX_PATH_INVALID",
            Self::SymlinkRejected => "YX_SYMLINK_REJECTED",
            Self::SourceMissing => "YX_SOURCE_MISSING",
            Self::SourceSizeMismatch => "YX_SOURCE_SIZE_MISMATCH",
            Self::SourceHashMismatch => "YX_SOURCE_SHA256_MISMATCH",
            Self::InvalidUtf8 => "YX_INVALID_UTF8",
            Self::UnsafeControl => "YX_UNSAFE_CONTROL_CHARACTER",
            Self::InvalidRecord => "YX_INVALID_RECORD",
            Self::Serialization => "YX_SERIALIZATION_FAILED",
            Self::Integrity => "YX_INTEGRITY_FAILED",
            Self::OutputUnsafe => "YX_OUTPUT_PATH_UNSAFE",
            Self::Io => "YX_IO_ERROR",
        }
    }

    pub const fn exit_code(self) -> i32 {
        match self {
            Self::Cli => 2,
            Self::FrozenHashMismatch => 10,
            Self::JsonInvalid | Self::ContractInvalid | Self::ContractVersion => 11,
            Self::IdentityMismatch | Self::CategoryInvalid => 12,
            Self::PathInvalid | Self::SymlinkRejected => 13,
            Self::SourceMissing | Self::SourceSizeMismatch | Self::SourceHashMismatch => 14,
            Self::InvalidUtf8 | Self::UnsafeControl | Self::InvalidRecord => 15,
            Self::Serialization | Self::Integrity => 16,
            Self::OutputUnsafe => 17,
            Self::Io => 18,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ConverterError {
    pub code: ErrorCode,
    pub detail: String,
}

impl ConverterError {
    pub fn new(code: ErrorCode, detail: impl Into<String>) -> Self {
        Self {
            code,
            detail: detail.into(),
        }
    }

    pub fn io(path: &Path, error: &std::io::Error) -> Self {
        Self::new(
            ErrorCode::Io,
            format!("path={} kind={}", safe_path(path), error.kind()),
        )
    }
}

fn safe_path(path: &Path) -> String {
    path.file_name()
        .map(|value| value.to_string_lossy().into_owned())
        .unwrap_or_else(|| "<path>".to_owned())
}

impl fmt::Display for ConverterError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}", self.code.reason(), self.detail)
    }
}

impl std::error::Error for ConverterError {}

pub type Result<T> = std::result::Result<T, ConverterError>;
