use std::fmt;

use engine_protocol::error::ImeErrorCode;
use lexicon_core::LexiconError;
use user_lexicon::{UserLexiconError, UserLexiconReason};
use user_model::UserModelError;

#[derive(Debug)]
pub enum EngineCreateError {
    Parser(shuangpin_parser::ParseError),
    InvalidConfig,
    LexiconNotFound,
    LexiconLoadFailed(String),
    CodeTableNotFound,
    CodeTableLoadFailed(String),
}

impl EngineCreateError {
    pub const fn code(&self) -> ImeErrorCode {
        match self {
            Self::Parser(_) => ImeErrorCode::InvalidScheme,
            Self::InvalidConfig => ImeErrorCode::InvalidConfig,
            Self::LexiconNotFound => ImeErrorCode::LexiconNotFound,
            Self::LexiconLoadFailed(_) => ImeErrorCode::LexiconLoadFailed,
            Self::CodeTableNotFound => ImeErrorCode::LexiconNotFound,
            Self::CodeTableLoadFailed(_) => ImeErrorCode::LexiconLoadFailed,
        }
    }
}

impl fmt::Display for EngineCreateError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Parser(error) => write!(f, "{error}"),
            Self::InvalidConfig => write!(f, "invalid engine config"),
            Self::LexiconNotFound => write!(f, "lexicon not found"),
            Self::LexiconLoadFailed(error) => write!(f, "lexicon load failed: {error}"),
            Self::CodeTableNotFound => write!(f, "code-table bundle not found"),
            Self::CodeTableLoadFailed(error) => write!(f, "code-table bundle load failed: {error}"),
        }
    }
}

impl std::error::Error for EngineCreateError {}

impl From<shuangpin_parser::ParseError> for EngineCreateError {
    fn from(value: shuangpin_parser::ParseError) -> Self {
        Self::Parser(value)
    }
}

impl From<LexiconError> for EngineCreateError {
    fn from(value: LexiconError) -> Self {
        Self::LexiconLoadFailed(value.to_string())
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum EngineOperationError {
    InvalidCandidate,
    InvalidPage,
    InvalidArgument,
    UnsupportedOperation,
    CategoryPolicy,
    UserLexicon(UserLexiconError),
    UserModel(UserModelError),
}

impl EngineOperationError {
    pub fn code(&self) -> ImeErrorCode {
        match self {
            Self::InvalidCandidate => ImeErrorCode::InvalidCandidate,
            Self::InvalidPage => ImeErrorCode::InvalidPage,
            Self::InvalidArgument => ImeErrorCode::InvalidArgument,
            Self::UnsupportedOperation => ImeErrorCode::UnsupportedOperation,
            Self::CategoryPolicy => ImeErrorCode::InvalidArgument,
            Self::UserLexicon(error) => match error.reason {
                UserLexiconReason::InvalidPath => ImeErrorCode::InvalidArgument,
                _ => ImeErrorCode::EngineInternalError,
            },
            Self::UserModel(error) => match error {
                UserModelError::InvalidPath | UserModelError::PathTooLong => {
                    ImeErrorCode::InvalidArgument
                }
                UserModelError::FileTooLarge { .. }
                | UserModelError::TooManyRecords { .. }
                | UserModelError::UnsupportedVersion { .. }
                | UserModelError::Corrupt(_)
                | UserModelError::Io(_) => ImeErrorCode::EngineInternalError,
            },
        }
    }
}
