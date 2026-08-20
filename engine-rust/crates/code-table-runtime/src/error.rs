use std::fmt;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CodeTableErrorKind {
    ResourceMissing,
    InvalidMagic,
    UnsupportedVersion,
    InvalidManifest,
    EmptyCategories,
    DuplicateCategoryId,
    MissingCategory,
    MetadataMismatch,
    ChecksumMismatch,
    TruncatedData,
    InvalidUtf8,
    InvalidIndex,
    InvalidSourceOrder,
    InvalidKey,
    CodeTooLong,
    InvalidPage,
    InvalidCandidate,
    MissingBundleFile,
    UnexpectedBundleFile,
    InvalidUserRules,
    CategoryPolicy,
    InvalidActionTable,
    InvalidCommitPolicy,
}

impl CodeTableErrorKind {
    pub const fn code(self) -> &'static str {
        match self {
            Self::ResourceMissing => "resource_missing",
            Self::InvalidMagic => "invalid_magic",
            Self::UnsupportedVersion => "unsupported_version",
            Self::InvalidManifest => "invalid_manifest",
            Self::EmptyCategories => "empty_categories",
            Self::DuplicateCategoryId => "duplicate_category_id",
            Self::MissingCategory => "missing_category",
            Self::MetadataMismatch => "metadata_mismatch",
            Self::ChecksumMismatch => "checksum_mismatch",
            Self::TruncatedData => "truncated_data",
            Self::InvalidUtf8 => "invalid_utf8",
            Self::InvalidIndex => "invalid_index",
            Self::InvalidSourceOrder => "invalid_source_order",
            Self::InvalidKey => "invalid_key",
            Self::CodeTooLong => "code_too_long",
            Self::InvalidPage => "invalid_page",
            Self::InvalidCandidate => "invalid_candidate",
            Self::MissingBundleFile => "missing_bundle_file",
            Self::UnexpectedBundleFile => "unexpected_bundle_file",
            Self::InvalidUserRules => "invalid_user_rules",
            Self::CategoryPolicy => "category_policy",
            Self::InvalidActionTable => "invalid_action_table",
            Self::InvalidCommitPolicy => "invalid_commit_policy",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CodeTableError {
    pub kind: CodeTableErrorKind,
    pub resource: &'static str,
    pub category_id: Option<String>,
    pub detail: String,
}

impl CodeTableError {
    pub fn new(kind: CodeTableErrorKind, detail: impl Into<String>) -> Self {
        Self {
            kind,
            resource: "code-table-bundle",
            category_id: None,
            detail: detail.into(),
        }
    }

    pub fn for_category(
        kind: CodeTableErrorKind,
        category_id: impl Into<String>,
        detail: impl Into<String>,
    ) -> Self {
        Self {
            kind,
            resource: "code-table-category",
            category_id: Some(category_id.into()),
            detail: detail.into(),
        }
    }

    pub const fn code(&self) -> &'static str {
        self.kind.code()
    }
}

impl fmt::Display for CodeTableError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}", self.resource, self.kind.code())?;
        if let Some(category_id) = &self.category_id {
            write!(f, ":category={category_id}")?;
        }
        write!(f, ":{}", self.detail)
    }
}

impl std::error::Error for CodeTableError {}
