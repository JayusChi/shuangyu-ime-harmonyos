use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::SystemTime;

use lexicon_core::{
    load_binary_lexicon_compact, BinaryLexicon, LexiconError, SOURCE_ORDER_UNSPECIFIED,
};
use user_lexicon::UserLexiconSnapshot;

use crate::error::{CodeTableError, CodeTableErrorKind};
use crate::file_bytes::FileBytes;
use crate::manifest::{BundleManifest, CategoryManifest};
use crate::sha256::sha256;

const MAGIC: [u8; 8] = *b"HSPCTF01";
const HEADER_LEN: usize = 128;
const FORMAT_MAJOR: u16 = 1;
const FORMAT_MINOR: u16 = 0;
const GENERATOR_VERSION: u32 = 1;
const MANIFEST_VERSION: u32 = 1;
const MAX_BUNDLE_BYTES: usize = 128 * 1024 * 1024;
pub const FIXTURE_SCHEME_ID: &str = "code-table-fixture";
pub const PRODUCTION_SCHEME_ID: &str = "xiaohe-yinxing";

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
struct ProductionCacheKey {
    path: PathBuf,
    len: u64,
    modified: Option<SystemTime>,
}

static PRODUCTION_BUNDLE_CACHE: OnceLock<
    Mutex<HashMap<ProductionCacheKey, Weak<CodeTableBundle>>>,
> = OnceLock::new();

#[derive(Clone, Debug)]
pub struct CodeTableCategory {
    pub id: String,
    pub display_name: String,
    pub binary_file: String,
    pub order: u32,
    pub default_enabled: bool,
    pub entry_count: usize,
    pub binary_sha256: [u8; 32],
    pub source_sha256: [u8; 32],
    pub lexicon: BinaryLexicon,
}

#[derive(Clone, Debug)]
pub struct CodeTableBundle {
    pub bundle_id: String,
    pub categories: Vec<CodeTableCategory>,
    pub guide: Option<CodeTableCategory>,
    pub build_input_sha256: [u8; 32],
    pub content_sha256: [u8; 32],
    pub user_rules: Option<UserLexiconSnapshot>,
    pub production_metadata: Option<crate::production::ProductionBundleMetadata>,
}

impl CodeTableBundle {
    pub fn load_file(path: impl AsRef<Path>) -> Result<Self, CodeTableError> {
        let bytes = FileBytes::open(path.as_ref()).map_err(map_file_error)?;
        Self::load_bytes(bytes.as_slice())
    }

    pub fn load_bytes(bytes: &[u8]) -> Result<Self, CodeTableError> {
        if bytes.len() > MAX_BUNDLE_BYTES {
            return Err(CodeTableError::new(
                CodeTableErrorKind::TruncatedData,
                "bundle exceeds runtime size limit",
            ));
        }
        if bytes.len() < HEADER_LEN {
            return Err(CodeTableError::new(
                CodeTableErrorKind::TruncatedData,
                "bundle header is truncated",
            ));
        }
        if bytes[..8] == crate::production::PRODUCTION_MAGIC {
            return crate::production::load_production_bytes(bytes, false);
        }
        if bytes[..8] != MAGIC {
            return Err(CodeTableError::new(
                CodeTableErrorKind::InvalidMagic,
                "bundle magic is not HSPCTF01",
            ));
        }
        if read_u32(bytes, 8)? as usize != HEADER_LEN {
            return Err(CodeTableError::new(
                CodeTableErrorKind::UnsupportedVersion,
                "unsupported bundle header length",
            ));
        }
        let major = read_u16(bytes, 12)?;
        let minor = read_u16(bytes, 14)?;
        if (major, minor) != (FORMAT_MAJOR, FORMAT_MINOR)
            || read_u32(bytes, 16)? != GENERATOR_VERSION
            || read_u32(bytes, 20)? != MANIFEST_VERSION
        {
            return Err(CodeTableError::new(
                CodeTableErrorKind::UnsupportedVersion,
                format!("unsupported bundle metadata {major}.{minor}"),
            ));
        }
        if bytes[112..HEADER_LEN].iter().any(|byte| *byte != 0) {
            return Err(CodeTableError::new(
                CodeTableErrorKind::MetadataMismatch,
                "reserved header bytes are not zero",
            ));
        }

        let category_count = read_u32(bytes, 24)? as usize;
        let table_count = read_u32(bytes, 28)? as usize;
        if category_count == 0 {
            return Err(CodeTableError::new(
                CodeTableErrorKind::EmptyCategories,
                "bundle has no normal categories",
            ));
        }
        if table_count != category_count.saturating_add(1) {
            return Err(CodeTableError::new(
                CodeTableErrorKind::MetadataMismatch,
                "table count must equal category count plus guide",
            ));
        }
        let manifest_len = to_usize(read_u64(bytes, 32)?, "manifest length")?;
        let payload_len = to_usize(read_u64(bytes, 40)?, "payload length")?;
        let expected_len = HEADER_LEN
            .checked_add(manifest_len)
            .and_then(|value| value.checked_add(payload_len));
        if expected_len != Some(bytes.len()) {
            return Err(CodeTableError::new(
                CodeTableErrorKind::TruncatedData,
                "bundle section lengths do not match file length",
            ));
        }
        let build_input_sha256: [u8; 32] = bytes[48..80]
            .try_into()
            .map_err(|_| truncated("build-input checksum"))?;
        let content_sha256: [u8; 32] = bytes[80..112]
            .try_into()
            .map_err(|_| truncated("content checksum"))?;
        if sha256(&bytes[HEADER_LEN..]) != content_sha256 {
            return Err(CodeTableError::new(
                CodeTableErrorKind::ChecksumMismatch,
                "bundle content SHA-256 mismatch",
            ));
        }

        let manifest_end = HEADER_LEN
            .checked_add(manifest_len)
            .ok_or_else(|| truncated("manifest end"))?;
        let manifest = BundleManifest::parse(
            bytes
                .get(HEADER_LEN..manifest_end)
                .ok_or_else(|| truncated("manifest"))?,
        )?;
        if manifest.categories.len() != category_count {
            return Err(CodeTableError::new(
                CodeTableErrorKind::MetadataMismatch,
                "manifest category count differs from header",
            ));
        }

        let mut cursor = manifest_end;
        let mut categories = Vec::with_capacity(category_count);
        let mut seen_ids = BTreeSet::new();
        for expected in &manifest.categories {
            let record = read_table_record(bytes, &mut cursor)?;
            if record.is_guide {
                return Err(CodeTableError::for_category(
                    CodeTableErrorKind::MetadataMismatch,
                    &record.id,
                    "guide record appeared inside normal category list",
                ));
            }
            validate_record(&record, expected)?;
            if !seen_ids.insert(record.id.clone()) {
                return Err(CodeTableError::for_category(
                    CodeTableErrorKind::DuplicateCategoryId,
                    &record.id,
                    "duplicate category record",
                ));
            }
            categories.push(record.into_category(&expected.display_name, &expected.source_path));
        }
        let guide_record = read_table_record(bytes, &mut cursor)?;
        if cursor != bytes.len() {
            return Err(CodeTableError::new(
                CodeTableErrorKind::MetadataMismatch,
                "trailing bytes follow table records",
            ));
        }
        if !guide_record.is_guide
            || guide_record.id != manifest.guide.id
            || guide_record.order != u32::MAX
            || guide_record.default_enabled
            || guide_record.entry_count != manifest.guide.expected_entry_count
            || guide_record.source_sha256 != manifest.guide.source_sha256
        {
            return Err(CodeTableError::for_category(
                CodeTableErrorKind::MetadataMismatch,
                &guide_record.id,
                "guide record differs from manifest",
            ));
        }
        if seen_ids.contains(&guide_record.id) {
            return Err(CodeTableError::for_category(
                CodeTableErrorKind::DuplicateCategoryId,
                &guide_record.id,
                "guide id duplicates a normal category",
            ));
        }

        Ok(Self {
            bundle_id: manifest.bundle_id,
            categories,
            guide: Some(guide_record.into_category("测试引导", "guide")),
            build_input_sha256,
            content_sha256,
            user_rules: None,
            production_metadata: None,
        })
    }

    pub fn load_frozen_production_file(path: impl AsRef<Path>) -> Result<Self, CodeTableError> {
        let bytes = FileBytes::open(path.as_ref()).map_err(map_file_error)?;
        crate::production::load_verified_frozen_production_bytes(bytes.as_slice())
    }

    /// Loads the frozen production bundle once per unchanged file and shares
    /// the immutable parsed index between engine handles in this process.
    /// Weak cache entries ensure the index is released when the last engine
    /// using it is destroyed.
    pub fn load_frozen_production_file_shared(
        path: impl AsRef<Path>,
    ) -> Result<Arc<Self>, CodeTableError> {
        let key = production_cache_key(path.as_ref())?;
        let cache = PRODUCTION_BUNDLE_CACHE.get_or_init(|| Mutex::new(HashMap::new()));
        let mut bundles = cache
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        bundles.retain(|_, bundle| bundle.strong_count() != 0);
        if let Some(bundle) = bundles.get(&key).and_then(Weak::upgrade) {
            return Ok(bundle);
        }
        let bundle = Arc::new(Self::load_frozen_production_file(&key.path)?);
        bundles.insert(key, Arc::downgrade(&bundle));
        Ok(bundle)
    }

    pub fn load_frozen_production_bytes(bytes: &[u8]) -> Result<Self, CodeTableError> {
        if bytes.len() >= 8 && bytes[..8] == crate::production::PRODUCTION_MAGIC {
            crate::production::load_production_bytes(bytes, true)
        } else {
            let bundle = Self::load_bytes(bytes)?;
            bundle.validate_scheme_identity(PRODUCTION_SCHEME_ID)?;
            Ok(bundle)
        }
    }

    pub fn default_enabled_category_ids(&self) -> Vec<String> {
        self.categories
            .iter()
            .filter(|category| category.default_enabled)
            .map(|category| category.id.clone())
            .collect()
    }

    /// Verifies that an already validated bundle is paired with the only
    /// scheme identity allowed for its container type. This deliberately uses
    /// validated magic/metadata state rather than a path or file extension.
    pub fn validate_scheme_identity(&self, scheme_id: &str) -> Result<(), CodeTableError> {
        let paired = match scheme_id {
            FIXTURE_SCHEME_ID => self.production_metadata.is_none() && self.guide.is_some(),
            PRODUCTION_SCHEME_ID => self.production_metadata.is_some() && self.guide.is_none(),
            _ => false,
        };
        if !paired {
            return Err(CodeTableError::new(
                CodeTableErrorKind::MetadataMismatch,
                "scheme and validated bundle identity do not match",
            ));
        }
        Ok(())
    }

    pub fn validate_enabled_categories(&self, ids: &[String]) -> Result<(), CodeTableError> {
        if ids.is_empty() {
            return Err(CodeTableError::new(
                CodeTableErrorKind::EmptyCategories,
                "runtime enabled-category list is empty",
            ));
        }
        let mut seen = BTreeSet::new();
        for id in ids {
            if !seen.insert(id) {
                return Err(CodeTableError::for_category(
                    CodeTableErrorKind::DuplicateCategoryId,
                    id,
                    "runtime category id is duplicated",
                ));
            }
            if !self.categories.iter().any(|category| category.id == *id) {
                return Err(CodeTableError::for_category(
                    CodeTableErrorKind::MissingCategory,
                    id,
                    "runtime configuration references an unknown category",
                ));
            }
        }
        Ok(())
    }
}

struct TableRecord {
    id: String,
    is_guide: bool,
    order: u32,
    default_enabled: bool,
    entry_count: usize,
    binary_sha256: [u8; 32],
    source_sha256: [u8; 32],
    lexicon: BinaryLexicon,
}

impl TableRecord {
    fn into_category(self, display_name: &str, binary_file: &str) -> CodeTableCategory {
        CodeTableCategory {
            id: self.id,
            display_name: display_name.to_owned(),
            binary_file: binary_file.to_owned(),
            order: self.order,
            default_enabled: self.default_enabled,
            entry_count: self.entry_count,
            binary_sha256: self.binary_sha256,
            source_sha256: self.source_sha256,
            lexicon: self.lexicon,
        }
    }
}

fn validate_record(
    record: &TableRecord,
    expected: &CategoryManifest,
) -> Result<(), CodeTableError> {
    if record.id != expected.id
        || record.order != expected.order
        || record.default_enabled != expected.default_enabled
        || record.entry_count != expected.expected_entry_count
        || record.source_sha256 != expected.source_sha256
    {
        return Err(CodeTableError::for_category(
            CodeTableErrorKind::MetadataMismatch,
            &record.id,
            "category record differs from manifest",
        ));
    }
    Ok(())
}

fn read_table_record(bytes: &[u8], cursor: &mut usize) -> Result<TableRecord, CodeTableError> {
    let id_len = take_u16(bytes, cursor)? as usize;
    let guide_flag = take_u8(bytes, cursor)?;
    let enabled_flag = take_u8(bytes, cursor)?;
    if guide_flag > 1 || enabled_flag > 1 {
        return Err(CodeTableError::new(
            CodeTableErrorKind::MetadataMismatch,
            "table flags must be zero or one",
        ));
    }
    let order = take_u32(bytes, cursor)?;
    let entry_count = take_u32(bytes, cursor)? as usize;
    let source_sha256: [u8; 32] = take(bytes, cursor, 32)?
        .try_into()
        .map_err(|_| truncated("table source checksum"))?;
    let binary_len = to_usize(take_u64(bytes, cursor)?, "nested binary length")?;
    let id = std::str::from_utf8(take(bytes, cursor, id_len)?)
        .map_err(|_| CodeTableError::new(CodeTableErrorKind::InvalidUtf8, "table id is not UTF-8"))?
        .to_owned();
    let binary = take(bytes, cursor, binary_len)?;
    let binary_sha256 = sha256(binary);
    let lexicon =
        load_binary_lexicon_compact(binary).map_err(|error| map_lexicon_error(&id, error))?;
    if lexicon.header.format_major != 1
        || lexicon.header.format_minor != 1
        || lexicon.entries.len() != entry_count
    {
        return Err(CodeTableError::for_category(
            CodeTableErrorKind::MetadataMismatch,
            &id,
            "nested lexicon version or entry count mismatch",
        ));
    }
    if !has_complete_source_order(&lexicon) {
        return Err(CodeTableError::for_category(
            CodeTableErrorKind::InvalidSourceOrder,
            &id,
            "source_order must be a complete zero-based sequence",
        ));
    }
    Ok(TableRecord {
        id,
        is_guide: guide_flag == 1,
        order,
        default_enabled: enabled_flag == 1,
        entry_count,
        binary_sha256,
        source_sha256,
        lexicon,
    })
}

fn map_lexicon_error(category_id: &str, error: LexiconError) -> CodeTableError {
    let kind = match error {
        LexiconError::InvalidUtf8 { .. } => CodeTableErrorKind::InvalidUtf8,
        LexiconError::ChecksumMismatch { .. } => CodeTableErrorKind::ChecksumMismatch,
        LexiconError::IndexOutOfBounds { .. }
        | LexiconError::InvalidIndexOrder { .. }
        | LexiconError::StringOutOfBounds { .. }
        | LexiconError::SectionOutOfBounds { .. } => CodeTableErrorKind::InvalidIndex,
        LexiconError::InvalidMagic => CodeTableErrorKind::InvalidMagic,
        LexiconError::UnsupportedVersion { .. } => CodeTableErrorKind::UnsupportedVersion,
        _ => CodeTableErrorKind::TruncatedData,
    };
    CodeTableError::for_category(
        kind,
        category_id,
        format!("nested lexicon invalid: {error}"),
    )
}

fn read_u16(bytes: &[u8], offset: usize) -> Result<u16, CodeTableError> {
    Ok(u16::from_le_bytes(
        bytes
            .get(offset..offset + 2)
            .ok_or_else(|| truncated("u16"))?
            .try_into()
            .map_err(|_| truncated("u16"))?,
    ))
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32, CodeTableError> {
    Ok(u32::from_le_bytes(
        bytes
            .get(offset..offset + 4)
            .ok_or_else(|| truncated("u32"))?
            .try_into()
            .map_err(|_| truncated("u32"))?,
    ))
}

fn read_u64(bytes: &[u8], offset: usize) -> Result<u64, CodeTableError> {
    Ok(u64::from_le_bytes(
        bytes
            .get(offset..offset + 8)
            .ok_or_else(|| truncated("u64"))?
            .try_into()
            .map_err(|_| truncated("u64"))?,
    ))
}

fn take<'a>(bytes: &'a [u8], cursor: &mut usize, count: usize) -> Result<&'a [u8], CodeTableError> {
    let end = cursor
        .checked_add(count)
        .ok_or_else(|| truncated("cursor"))?;
    let value = bytes
        .get(*cursor..end)
        .ok_or_else(|| truncated("table record"))?;
    *cursor = end;
    Ok(value)
}

fn take_u8(bytes: &[u8], cursor: &mut usize) -> Result<u8, CodeTableError> {
    Ok(take(bytes, cursor, 1)?[0])
}

fn take_u16(bytes: &[u8], cursor: &mut usize) -> Result<u16, CodeTableError> {
    Ok(u16::from_le_bytes(
        take(bytes, cursor, 2)?
            .try_into()
            .map_err(|_| truncated("table u16"))?,
    ))
}

fn take_u32(bytes: &[u8], cursor: &mut usize) -> Result<u32, CodeTableError> {
    Ok(u32::from_le_bytes(
        take(bytes, cursor, 4)?
            .try_into()
            .map_err(|_| truncated("table u32"))?,
    ))
}

fn take_u64(bytes: &[u8], cursor: &mut usize) -> Result<u64, CodeTableError> {
    Ok(u64::from_le_bytes(
        take(bytes, cursor, 8)?
            .try_into()
            .map_err(|_| truncated("table u64"))?,
    ))
}

fn to_usize(value: u64, field: &'static str) -> Result<usize, CodeTableError> {
    usize::try_from(value).map_err(|_| truncated(field))
}

fn truncated(field: &'static str) -> CodeTableError {
    CodeTableError::new(
        CodeTableErrorKind::TruncatedData,
        format!("{field} is truncated or out of range"),
    )
}

fn map_file_error(error: std::io::Error) -> CodeTableError {
    if error.kind() == ErrorKind::NotFound {
        CodeTableError::new(
            CodeTableErrorKind::ResourceMissing,
            "bundle file does not exist",
        )
    } else {
        CodeTableError::new(
            CodeTableErrorKind::ResourceMissing,
            format!("bundle read failed: {}", error.kind()),
        )
    }
}

fn production_cache_key(path: &Path) -> Result<ProductionCacheKey, CodeTableError> {
    let path = fs::canonicalize(path).map_err(map_file_error)?;
    let metadata = fs::metadata(&path).map_err(map_file_error)?;
    Ok(ProductionCacheKey {
        path,
        len: metadata.len(),
        modified: metadata.modified().ok(),
    })
}

fn has_complete_source_order(lexicon: &BinaryLexicon) -> bool {
    let mut seen = vec![false; lexicon.entries.len()];
    for entry in &lexicon.entries {
        let order = entry.source_order as usize;
        if entry.source_order == SOURCE_ORDER_UNSPECIFIED
            || order >= seen.len()
            || std::mem::replace(&mut seen[order], true)
        {
            return false;
        }
    }
    true
}
