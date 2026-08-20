use std::fmt;

/// Query-layer errors that can be mapped to engine errors without panicking.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum QueryError {
    InvalidReading,
    InvalidPageSize,
}

impl fmt::Display for QueryError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidReading => write!(f, "invalid query reading"),
            Self::InvalidPageSize => write!(f, "invalid candidate page size"),
        }
    }
}

impl std::error::Error for QueryError {}
