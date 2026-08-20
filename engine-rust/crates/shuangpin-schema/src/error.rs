use std::fmt;

/// Structured errors returned while loading or validating a shuangpin schema.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SchemaError {
    /// The schema id is empty.
    EmptyId,
    /// The schema display name is empty.
    EmptyName,
    /// The schema version must be greater than zero.
    InvalidVersion { version: u32 },
    /// A required field is absent from the configuration.
    MissingField { field: String },
    /// A key is not a lowercase ASCII key allowed by the schema.
    InvalidKey { section: String, key: String },
    /// A mapping target is empty.
    EmptyMappingTarget { section: String, key: String },
    /// A section contains the same mapping key or value more than once.
    DuplicateMapping { section: String, key: String },
    /// A generated or explicit code points at conflicting syllables.
    ConflictingMapping {
        code: String,
        first: String,
        second: String,
    },
    /// A rule references a syllable outside the maintained pinyin inventory.
    InvalidSyllable { syllable: String },
    /// The zero-initial rules are missing or refer to unknown finals.
    InvalidZeroInitialRule { reason: String },
    /// The configuration cannot be parsed or has an unsupported shape.
    InvalidConfig { reason: String },
    /// The requested built-in schema id is unknown.
    SchemaNotFound { id: String },
}

impl fmt::Display for SchemaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptyId => write!(f, "schema id is empty"),
            Self::EmptyName => write!(f, "schema name is empty"),
            Self::InvalidVersion { version } => write!(f, "invalid schema version: {version}"),
            Self::MissingField { field } => write!(f, "missing schema field: {field}"),
            Self::InvalidKey { section, key } => {
                write!(f, "invalid key in {section}: {key}")
            }
            Self::EmptyMappingTarget { section, key } => {
                write!(f, "empty mapping target in {section}: {key}")
            }
            Self::DuplicateMapping { section, key } => {
                write!(f, "duplicate mapping in {section}: {key}")
            }
            Self::ConflictingMapping {
                code,
                first,
                second,
            } => write!(f, "conflicting mapping for {code}: {first} vs {second}"),
            Self::InvalidSyllable { syllable } => write!(f, "invalid syllable: {syllable}"),
            Self::InvalidZeroInitialRule { reason } => {
                write!(f, "invalid zero-initial rule: {reason}")
            }
            Self::InvalidConfig { reason } => write!(f, "invalid schema config: {reason}"),
            Self::SchemaNotFound { id } => write!(f, "schema not found: {id}"),
        }
    }
}

impl std::error::Error for SchemaError {}
