use std::fmt;

/// Error returned by binary lexicon serialization and loading.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LexiconError {
    /// A binary lexicon cannot be created without entries.
    EmptyLexicon,
    /// A count, offset, or section length does not fit the on-disk format.
    ValueOutOfRange { field: &'static str },
    /// The file is too short to contain the fixed header.
    TruncatedHeader { len: usize },
    /// The magic number does not match the stage 6 lexicon format.
    InvalidMagic,
    /// The fixed header length is not supported.
    InvalidHeaderLength { actual: u32 },
    /// The binary format version is not supported by this reader.
    UnsupportedVersion { major: u16, minor: u16 },
    /// The checksum algorithm identifier is unknown.
    UnsupportedChecksumAlgorithm { algorithm: u32 },
    /// A named section points outside the file or overlaps the expected layout.
    SectionOutOfBounds { section: &'static str },
    /// A table length is not a multiple of its record size.
    InvalidTableLength { table: &'static str },
    /// A string reference points outside the string table.
    StringOutOfBounds { field: &'static str },
    /// A string table range is not valid UTF-8.
    InvalidUtf8 { field: &'static str },
    /// The payload checksum does not match the header.
    ChecksumMismatch { expected: u32, actual: u32 },
    /// An index range points outside the entry table.
    IndexOutOfBounds { key: String },
    /// Entry order is not compatible with the pinyin-key index.
    InvalidIndexOrder { key: String },
}

impl fmt::Display for LexiconError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptyLexicon => write!(f, "lexicon must contain at least one entry"),
            Self::ValueOutOfRange { field } => write!(f, "{field} exceeds binary format range"),
            Self::TruncatedHeader { len } => {
                write!(f, "file is truncated before header ends: {len} bytes")
            }
            Self::InvalidMagic => write!(f, "invalid lexicon magic"),
            Self::InvalidHeaderLength { actual } => {
                write!(f, "unsupported lexicon header length: {actual}")
            }
            Self::UnsupportedVersion { major, minor } => {
                write!(f, "unsupported lexicon format version: {major}.{minor}")
            }
            Self::UnsupportedChecksumAlgorithm { algorithm } => {
                write!(f, "unsupported checksum algorithm: {algorithm}")
            }
            Self::SectionOutOfBounds { section } => {
                write!(f, "lexicon section is out of bounds: {section}")
            }
            Self::InvalidTableLength { table } => {
                write!(f, "invalid table length for {table}")
            }
            Self::StringOutOfBounds { field } => {
                write!(f, "string reference is out of bounds: {field}")
            }
            Self::InvalidUtf8 { field } => write!(f, "invalid UTF-8 in {field}"),
            Self::ChecksumMismatch { expected, actual } => {
                write!(
                    f,
                    "checksum mismatch: expected {expected:08x}, actual {actual:08x}"
                )
            }
            Self::IndexOutOfBounds { key } => write!(f, "index range is out of bounds: {key}"),
            Self::InvalidIndexOrder { key } => {
                write!(f, "entries are not contiguous for pinyin key: {key}")
            }
        }
    }
}

impl std::error::Error for LexiconError {}
