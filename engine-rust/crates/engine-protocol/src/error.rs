#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ImeErrorCode {
    Success = 0,
    InvalidArgument = 1001,
    InvalidHandle = 1002,
    UnsupportedOperation = 1003,
    InvalidUtf8 = 1004,
    SerializationError = 1005,
    BufferAllocationFailed = 1006,
    EngineNotInitialized = 1007,
    EngineInternalError = 1008,
    NativeBridgeError = 1009,
    AbiVersionMismatch = 1010,
    InvalidConfig = 1011,
    InvalidScheme = 1012,
    LexiconNotFound = 1013,
    LexiconLoadFailed = 1014,
    InvalidPage = 1015,
    InvalidCandidate = 1016,
    UnknownError = 1099,
}

impl ImeErrorCode {
    pub const fn as_i32(self) -> i32 {
        self as i32
    }

    pub const fn message(self) -> &'static str {
        match self {
            Self::Success => "success",
            Self::InvalidArgument => "invalid argument",
            Self::InvalidHandle => "invalid handle",
            Self::UnsupportedOperation => "unsupported operation",
            Self::InvalidUtf8 => "invalid utf-8",
            Self::SerializationError => "serialization error",
            Self::BufferAllocationFailed => "buffer allocation failed",
            Self::EngineNotInitialized => "engine not initialized",
            Self::EngineInternalError => "engine internal error",
            Self::NativeBridgeError => "native bridge error",
            Self::AbiVersionMismatch => "abi version mismatch",
            Self::InvalidConfig => "invalid config",
            Self::InvalidScheme => "invalid scheme",
            Self::LexiconNotFound => "lexicon not found",
            Self::LexiconLoadFailed => "lexicon load failed",
            Self::InvalidPage => "invalid candidate page",
            Self::InvalidCandidate => "invalid candidate",
            Self::UnknownError => "unknown error",
        }
    }
}
