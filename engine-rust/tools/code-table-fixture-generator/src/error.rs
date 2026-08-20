use std::fmt;
use std::path::PathBuf;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Diagnostic {
    pub code: &'static str,
    pub file: String,
    pub line: usize,
    pub field: &'static str,
    pub reason: String,
}

impl Diagnostic {
    pub fn new(
        code: &'static str,
        file: impl Into<String>,
        line: usize,
        field: &'static str,
        reason: impl Into<String>,
    ) -> Self {
        Self {
            code,
            file: file.into(),
            line,
            field,
            reason: reason.into(),
        }
    }
}

#[derive(Debug)]
pub enum FixtureError {
    Diagnostic(Diagnostic),
    Io {
        path: PathBuf,
        source: std::io::Error,
    },
    Builder(String),
    Bundle(String),
}

impl FixtureError {
    pub fn diagnostic(
        code: &'static str,
        file: impl Into<String>,
        line: usize,
        field: &'static str,
        reason: impl Into<String>,
    ) -> Self {
        Self::Diagnostic(Diagnostic::new(code, file, line, field, reason))
    }

    pub fn io(path: impl Into<PathBuf>, source: std::io::Error) -> Self {
        Self::Io {
            path: path.into(),
            source,
        }
    }
}

impl fmt::Display for FixtureError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Diagnostic(value) => write!(
                f,
                "code={} file={} line={} field={} reason={}",
                value.code, value.file, value.line, value.field, value.reason
            ),
            Self::Io { path, source } => write!(f, "{}: io error: {source}", path.display()),
            Self::Builder(reason) => write!(f, "code=CTF_BUILDER_FAILED reason={reason}"),
            Self::Bundle(reason) => write!(f, "code=CTF_BUNDLE_INVALID reason={reason}"),
        }
    }
}

impl std::error::Error for FixtureError {}
