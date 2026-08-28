use std::collections::{BTreeMap, BTreeSet};

use lexicon_core::{load_binary_lexicon_compact, SOURCE_ORDER_UNSPECIFIED};
use user_lexicon::parse_embedded_user_lexicon_bytes;

use crate::bundle::{CodeTableBundle, CodeTableCategory};
use crate::error::{CodeTableError, CodeTableErrorKind};
use crate::json::{self, JsonValue};
use crate::sha256::{sha256, Sha256};

pub const PRODUCTION_MAGIC: [u8; 8] = *b"HSPYXP01";
const HEADER_LEN: usize = 128;
const FORMAT_MAJOR: u16 = 1;
const FORMAT_MINOR: u16 = 0;
const CONVERTER_BINARY_VERSION: u32 = 1;
const MANIFEST_VERSION: u32 = 1;
const MAX_BUNDLE_BYTES: usize = 128 * 1024 * 1024;
const EXPECTED_SCHEME: &str = "xiaohe-yinxing";
const EXPECTED_BUNDLE: &str = "xiaohe-yinxing-production";
const EXPECTED_DATA_VERSION: &str = "source-receipt-1";
const EXPECTED_CONVERTER: &str = "yinxing-converter/1.0.0";
const EXPECTED_AUDIT_MANIFEST_VERSION: &str = "1.1.0";
const EXPECTED_AUDITOR: &str = "yinxing-source-auditor/1.1.0";
const EXPECTED_CONTRACT_VERSION: &str = "1.1.0";
const EXPECTED_SOURCE_MANIFEST_HASH: &str =
    "4dd2304ce2a2f7ffa48f38c7a707e11d9d2318b1bc32c8ded7dc264a2458048f";
const EXPECTED_CONTRACT_HASH: &str =
    "27894e17bed11e267504e3ddae20f82348ab89e07e3a813b6236d80d29739caa";
const EXPECTED_CONTENT_HASH: &str =
    "83fa186fb43acc045fac88ba74ea3db5d761bf8c7c901499c4b517d953eef2e3";
const EXPECTED_ARCHIVE_HASH: &str =
    "f7bbfdf4473e9317d618c9ad02a792b47ff2dab8bfd74fa23416579e01f9bdc7";
const EXPECTED_ARCHIVE_FILE_COUNT: usize = 17;
const EXPECTED_CATEGORIES: [(&str, usize, bool); 12] = [
    ("core", 68_568, true),
    ("category-secondary", 1_690, true),
    ("quick-symbol", 16, true),
    ("one-key-secondary", 26, true),
    ("two-key-secondary", 66, false),
    ("out-of-table-character", 362, true),
    ("full-code-word", 464, false),
    ("symbol", 623, true),
    ("symbol-group", 707, true),
    ("rare-character", 498, false),
    ("full-code-character", 1_654, false),
    ("ok-spelling", 88_020, true),
];
const FLAG_MANIFEST: u16 = 1;
const FLAG_CATEGORY: u16 = 2;
const FLAG_USER_RULES: u16 = 4;
const FLAG_ACTIONS: u16 = 8;
const FLAG_TRACE: u16 = 16;
const FLAG_REPORT: u16 = 32;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProductionBundleMetadata {
    pub scheme_id: String,
    pub data_version: String,
    pub converter_version: String,
    pub source_manifest_sha256: [u8; 32],
    pub conversion_contract_sha256: [u8; 32],
    pub bundle_content_sha256: [u8; 32],
    pub archive_file_count: usize,
}

struct ArchiveEntry<'a> {
    path: String,
    flags: u16,
    order: u32,
    bytes: &'a [u8],
    sha256: [u8; 32],
}

#[derive(Clone)]
struct CategoryManifest {
    id: String,
    display_name: String,
    order: u32,
    default_enabled: bool,
    file: String,
    byte_size: usize,
    sha256: [u8; 32],
    entry_count: usize,
    source_sha256: [u8; 32],
}

struct MachineFile {
    path: String,
    byte_size: usize,
    sha256: [u8; 32],
    flag: u16,
}

struct ProductionManifest {
    bundle_id: String,
    categories: Vec<CategoryManifest>,
    user_rules: MachineFile,
    actions: MachineFile,
    trace: MachineFile,
    report: MachineFile,
    metadata: ProductionBundleMetadata,
}

pub(crate) fn load_production_bytes(
    bytes: &[u8],
    strict_frozen: bool,
) -> Result<CodeTableBundle, CodeTableError> {
    load_production_bytes_with_trust(bytes, strict_frozen, false)
}

pub(crate) fn load_verified_frozen_production_bytes(
    bytes: &[u8],
) -> Result<CodeTableBundle, CodeTableError> {
    if encode(sha256(bytes)) != EXPECTED_ARCHIVE_HASH {
        // Invalid resources stay on the detailed verifier so callers retain
        // the established structured diagnostic (identity, magic, nested
        // index, and so on). Only the exact frozen production bytes take the
        // reduced-pass trusted path.
        return CodeTableBundle::load_frozen_production_bytes(bytes);
    }
    load_production_bytes_with_trust(bytes, true, true)
}

fn load_production_bytes_with_trust(
    bytes: &[u8],
    strict_frozen: bool,
    trusted_frozen_bytes: bool,
) -> Result<CodeTableBundle, CodeTableError> {
    if bytes.len() > MAX_BUNDLE_BYTES {
        return Err(error(
            CodeTableErrorKind::TruncatedData,
            "production bundle exceeds size limit",
        ));
    }
    if bytes.len() < HEADER_LEN {
        return Err(truncated("production header"));
    }
    if bytes[..8] != PRODUCTION_MAGIC {
        return Err(error(
            CodeTableErrorKind::InvalidMagic,
            "production magic mismatch",
        ));
    }
    if read_u32(bytes, 8)? as usize != HEADER_LEN {
        return Err(error(
            CodeTableErrorKind::UnsupportedVersion,
            "production header length",
        ));
    }
    let major = read_u16(bytes, 12)?;
    let minor = read_u16(bytes, 14)?;
    if (major, minor) != (FORMAT_MAJOR, FORMAT_MINOR)
        || read_u32(bytes, 16)? != CONVERTER_BINARY_VERSION
        || read_u32(bytes, 20)? != MANIFEST_VERSION
    {
        return Err(error(
            CodeTableErrorKind::UnsupportedVersion,
            format!("unsupported production metadata {major}.{minor}"),
        ));
    }
    if bytes[112..HEADER_LEN].iter().any(|byte| *byte != 0) {
        return Err(error(
            CodeTableErrorKind::MetadataMismatch,
            "production reserved bytes",
        ));
    }
    let entry_count = read_u32(bytes, 24)? as usize;
    let category_count = read_u32(bytes, 28)? as usize;
    let records_len = to_usize(read_u64(bytes, 32)?, "record length")?;
    if entry_count == 0
        || category_count == 0
        || HEADER_LEN.checked_add(records_len) != Some(bytes.len())
    {
        return Err(truncated("production record section"));
    }
    if read_u64(bytes, 40)? != 0 {
        return Err(error(
            CodeTableErrorKind::MetadataMismatch,
            "production reserved length",
        ));
    }
    let source_manifest_sha256: [u8; 32] = bytes[48..80]
        .try_into()
        .map_err(|_| truncated("source manifest hash"))?;
    let content_sha256: [u8; 32] = bytes[80..112]
        .try_into()
        .map_err(|_| truncated("content hash"))?;
    if !trusted_frozen_bytes && sha256(&bytes[HEADER_LEN..]) != content_sha256 {
        return Err(error(
            CodeTableErrorKind::ChecksumMismatch,
            "production archive checksum",
        ));
    }
    if encode(source_manifest_sha256) != EXPECTED_SOURCE_MANIFEST_HASH {
        return Err(error(
            CodeTableErrorKind::MetadataMismatch,
            "source manifest hash is not frozen value",
        ));
    }

    let mut cursor = HEADER_LEN;
    let mut entries = BTreeMap::new();
    for index in 0..entry_count {
        let entry = read_entry(bytes, &mut cursor, !trusted_frozen_bytes)?;
        if index == 0 && (entry.path != "manifest.json" || entry.flags != FLAG_MANIFEST) {
            return Err(error(
                CodeTableErrorKind::InvalidManifest,
                "manifest entry must be first",
            ));
        }
        if entries.insert(entry.path.clone(), entry).is_some() {
            return Err(error(
                CodeTableErrorKind::UnexpectedBundleFile,
                "duplicate archive path",
            ));
        }
    }
    if cursor != bytes.len() {
        return Err(error(
            CodeTableErrorKind::UnexpectedBundleFile,
            "trailing archive bytes",
        ));
    }
    let manifest_entry = entries.get("manifest.json").ok_or_else(|| {
        error(
            CodeTableErrorKind::MissingBundleFile,
            "manifest.json missing",
        )
    })?;
    let manifest = ProductionManifest::parse(manifest_entry.bytes, entry_count, strict_frozen)?;
    if manifest.categories.len() != category_count
        || manifest.metadata.source_manifest_sha256 != source_manifest_sha256
    {
        return Err(error(
            CodeTableErrorKind::MetadataMismatch,
            "production header/manifest mismatch",
        ));
    }
    validate_archive_set(&entries, &manifest, !trusted_frozen_bytes)?;
    let mut categories = Vec::with_capacity(category_count);
    for expected in &manifest.categories {
        let entry = entries.get(&expected.file).expect("validated archive path");
        if entry.flags != FLAG_CATEGORY
            || entry.order != expected.order
            || entry.bytes.len() != expected.byte_size
            || entry.sha256 != expected.sha256
        {
            return Err(CodeTableError::for_category(
                CodeTableErrorKind::MetadataMismatch,
                &expected.id,
                "production category archive metadata mismatch",
            ));
        }
        let lexicon = load_binary_lexicon_compact(entry.bytes).map_err(|source| {
            CodeTableError::for_category(
                CodeTableErrorKind::InvalidIndex,
                &expected.id,
                format!("nested production lexicon invalid: {source}"),
            )
        })?;
        if lexicon.header.format_major != 1
            || lexicon.header.format_minor != 1
            || lexicon.entries.len() != expected.entry_count
        {
            return Err(CodeTableError::for_category(
                CodeTableErrorKind::MetadataMismatch,
                &expected.id,
                "nested production lexicon metadata mismatch",
            ));
        }
        if !has_complete_source_order(&lexicon.entries) {
            return Err(CodeTableError::for_category(
                CodeTableErrorKind::InvalidSourceOrder,
                &expected.id,
                "production source_order is not zero-based and complete",
            ));
        }
        categories.push(CodeTableCategory {
            id: expected.id.clone(),
            display_name: expected.display_name.clone(),
            binary_file: expected.file.clone(),
            order: expected.order,
            default_enabled: expected.default_enabled,
            entry_count: expected.entry_count,
            binary_sha256: expected.sha256,
            source_sha256: expected.source_sha256,
            lexicon,
        });
    }
    let user_entry = entries
        .get(&manifest.user_rules.path)
        .expect("validated user rules");
    let user_rules = parse_embedded_user_lexicon_bytes("production-user-rules", user_entry.bytes)
        .map_err(|_| {
            error(
                CodeTableErrorKind::InvalidUserRules,
                "production user rules are invalid",
            )
        })?
        .into_snapshot();
    let user_stats = user_rules.stats();
    if strict_frozen
        && (user_stats.accepted != 37
            || user_stats.effective != 37
            || user_stats.added != 1
            || user_stats.deleted != 0
            || user_stats.fixed != 36
            || user_stats.positioned != 0)
    {
        return Err(error(
            CodeTableErrorKind::MetadataMismatch,
            "production user-rule counts differ from frozen profile",
        ));
    }
    validate_metadata_json(
        entries.get(&manifest.actions.path).expect("actions").bytes,
        "actions",
    )?;
    validate_metadata_json(
        entries.get(&manifest.report.path).expect("report").bytes,
        "report",
    )?;
    if !trusted_frozen_bytes {
        validate_trace(entries.get(&manifest.trace.path).expect("trace").bytes)?;
    }
    if strict_frozen && encode(manifest.metadata.bundle_content_sha256) != EXPECTED_CONTENT_HASH {
        return Err(error(
            CodeTableErrorKind::MetadataMismatch,
            "bundle_content_sha256 is not frozen value",
        ));
    }
    if strict_frozen && !trusted_frozen_bytes && encode(sha256(bytes)) != EXPECTED_ARCHIVE_HASH {
        return Err(error(
            CodeTableErrorKind::ChecksumMismatch,
            "production bundle SHA-256 differs from frozen value",
        ));
    }
    Ok(CodeTableBundle {
        bundle_id: manifest.bundle_id,
        categories,
        guide: None,
        build_input_sha256: source_manifest_sha256,
        content_sha256,
        user_rules: Some(user_rules),
        production_metadata: Some(manifest.metadata),
    })
}

impl ProductionManifest {
    fn parse(
        bytes: &[u8],
        archive_file_count: usize,
        strict_frozen: bool,
    ) -> Result<Self, CodeTableError> {
        let root = json::parse(bytes)
            .map_err(|detail| error(CodeTableErrorKind::InvalidManifest, detail))?;
        let root_object = object(&root, "manifest")?;
        expect_string(root_object, "format_version", "1.0")?;
        expect_number(root_object, "manifest_version", 1)?;
        expect_string(root_object, "scheme_id", EXPECTED_SCHEME)?;
        expect_string(root_object, "bundle_id", EXPECTED_BUNDLE)?;
        expect_string(root_object, "data_version", EXPECTED_DATA_VERSION)?;
        expect_string(root_object, "converter_version", EXPECTED_CONVERTER)?;
        if strict_frozen {
            expect_string(
                root_object,
                "audit_manifest_version",
                EXPECTED_AUDIT_MANIFEST_VERSION,
            )?;
            expect_string(root_object, "auditor_version", EXPECTED_AUDITOR)?;
            expect_string(
                root_object,
                "conversion_contract_version",
                EXPECTED_CONTRACT_VERSION,
            )?;
        }
        expect_string(
            root_object,
            "source_manifest_sha256",
            EXPECTED_SOURCE_MANIFEST_HASH,
        )?;
        expect_string(
            root_object,
            "conversion_contract_sha256",
            EXPECTED_CONTRACT_HASH,
        )?;
        expect_string(root_object, "build_timestamp_policy", "omitted")?;
        let categories_value = array(required(root_object, "category_files")?, "category_files")?;
        let order_values = array(required(root_object, "category_order")?, "category_order")?;
        let category_count =
            number(required(root_object, "category_count")?, "category_count")? as usize;
        if category_count == 0
            || categories_value.len() != category_count
            || order_values.len() != category_count
            || (strict_frozen
                && (archive_file_count != EXPECTED_ARCHIVE_FILE_COUNT
                    || category_count != EXPECTED_CATEGORIES.len()))
        {
            return Err(error(
                CodeTableErrorKind::EmptyCategories,
                "production category profile mismatch",
            ));
        }
        let mut categories = Vec::new();
        let mut ids = BTreeSet::new();
        let mut orders = BTreeSet::new();
        for (index, value) in categories_value.iter().enumerate() {
            let item = object(value, "category_files[]")?;
            let id = string(required(item, "category_id")?, "category_id")?.to_owned();
            validate_id(&id)?;
            let order =
                u32::try_from(number(required(item, "order")?, "order")?).map_err(|_| {
                    error(
                        CodeTableErrorKind::InvalidManifest,
                        "category order overflow",
                    )
                })?;
            if !ids.insert(id.clone())
                || !orders.insert(order)
                || order as usize != index
                || (strict_frozen && id != EXPECTED_CATEGORIES[index].0)
            {
                return Err(error(
                    CodeTableErrorKind::DuplicateCategoryId,
                    "category id/order invalid",
                ));
            }
            if order_values[index].as_str() != Some(&id) {
                return Err(error(
                    CodeTableErrorKind::MetadataMismatch,
                    "category_order mismatch",
                ));
            }
            let path = string(required(item, "file")?, "category file")?.to_owned();
            validate_path(&path)?;
            let default_enabled = boolean(required(item, "default_enabled")?, "default_enabled")?;
            let entry_count = usize_value(required(item, "entry_count")?, "entry_count")?;
            if strict_frozen
                && (default_enabled != EXPECTED_CATEGORIES[index].2
                    || entry_count != EXPECTED_CATEGORIES[index].1)
            {
                return Err(error(
                    CodeTableErrorKind::MetadataMismatch,
                    "category default/count differs from frozen profile",
                ));
            }
            categories.push(CategoryManifest {
                id,
                display_name: string(required(item, "display_name")?, "display_name")?.to_owned(),
                order,
                default_enabled,
                file: path,
                byte_size: usize_value(required(item, "byte_size")?, "byte_size")?,
                sha256: hash(required(item, "sha256")?, "category sha256")?,
                entry_count,
                source_sha256: hash(required(item, "source_sha256")?, "source_sha256")?,
            });
        }
        let source_manifest_sha256 = hash(
            required(root_object, "source_manifest_sha256")?,
            "source_manifest_sha256",
        )?;
        let conversion_contract_sha256 = hash(
            required(root_object, "conversion_contract_sha256")?,
            "conversion_contract_sha256",
        )?;
        let bundle_content_sha256 = hash(
            required(root_object, "bundle_content_sha256")?,
            "bundle_content_sha256",
        )?;
        Ok(Self {
            bundle_id: EXPECTED_BUNDLE.to_owned(),
            categories,
            user_rules: machine_file(root_object, "user_rule_file", FLAG_USER_RULES)?,
            actions: machine_file(root_object, "action_metadata_file", FLAG_ACTIONS)?,
            trace: machine_file(root_object, "trace_metadata_file", FLAG_TRACE)?,
            report: machine_file(root_object, "statistics_file", FLAG_REPORT)?,
            metadata: ProductionBundleMetadata {
                scheme_id: EXPECTED_SCHEME.to_owned(),
                data_version: EXPECTED_DATA_VERSION.to_owned(),
                converter_version: EXPECTED_CONVERTER.to_owned(),
                source_manifest_sha256,
                conversion_contract_sha256,
                bundle_content_sha256,
                archive_file_count,
            },
        })
    }
}

fn validate_archive_set(
    entries: &BTreeMap<String, ArchiveEntry<'_>>,
    manifest: &ProductionManifest,
    verify_content_hash: bool,
) -> Result<(), CodeTableError> {
    let mut expected = BTreeSet::from(["manifest.json".to_owned()]);
    expected.extend(
        manifest
            .categories
            .iter()
            .map(|category| category.file.clone()),
    );
    for machine in [
        &manifest.user_rules,
        &manifest.actions,
        &manifest.trace,
        &manifest.report,
    ] {
        expected.insert(machine.path.clone());
        let actual = entries.get(&machine.path).ok_or_else(|| {
            error(
                CodeTableErrorKind::MissingBundleFile,
                format!("{} missing", machine.path),
            )
        })?;
        if actual.flags != machine.flag
            || actual.order != 0
            || actual.bytes.len() != machine.byte_size
            || actual.sha256 != machine.sha256
        {
            return Err(error(
                CodeTableErrorKind::MetadataMismatch,
                "machine file metadata mismatch",
            ));
        }
    }
    let actual = entries.keys().cloned().collect::<BTreeSet<_>>();
    if let Some(missing) = expected.difference(&actual).next() {
        return Err(error(
            CodeTableErrorKind::MissingBundleFile,
            format!("{missing} missing"),
        ));
    }
    if let Some(extra) = actual.difference(&expected).next() {
        return Err(error(
            CodeTableErrorKind::UnexpectedBundleFile,
            format!("{extra} unexpected"),
        ));
    }
    if verify_content_hash {
        let mut material = Sha256::new();
        for path in expected
            .iter()
            .filter(|path| path.as_str() != "manifest.json")
        {
            let entry = entries.get(path).expect("set equality");
            update_sized(&mut material, path.as_bytes());
            update_sized(&mut material, entry.bytes);
        }
        if material.finalize() != manifest.metadata.bundle_content_sha256 {
            return Err(error(
                CodeTableErrorKind::ChecksumMismatch,
                "bundle_content_sha256 mismatch",
            ));
        }
    }
    Ok(())
}

fn read_entry<'a>(
    bytes: &'a [u8],
    cursor: &mut usize,
    verify_hash: bool,
) -> Result<ArchiveEntry<'a>, CodeTableError> {
    let path_len = take_u16(bytes, cursor)? as usize;
    let flags = take_u16(bytes, cursor)?;
    let order = take_u32(bytes, cursor)?;
    let data_len = to_usize(take_u64(bytes, cursor)?, "archive data length")?;
    let expected_hash: [u8; 32] = take(bytes, cursor, 32)?
        .try_into()
        .map_err(|_| truncated("archive entry hash"))?;
    let path = std::str::from_utf8(take(bytes, cursor, path_len)?)
        .map_err(|_| error(CodeTableErrorKind::InvalidUtf8, "archive path is not UTF-8"))?
        .to_owned();
    validate_path(&path)?;
    let data = take(bytes, cursor, data_len)?;
    if verify_hash && sha256(data) != expected_hash {
        return Err(error(
            CodeTableErrorKind::ChecksumMismatch,
            "archive entry SHA-256 mismatch",
        ));
    }
    if !matches!(
        flags,
        FLAG_MANIFEST | FLAG_CATEGORY | FLAG_USER_RULES | FLAG_ACTIONS | FLAG_TRACE | FLAG_REPORT
    ) {
        return Err(error(
            CodeTableErrorKind::MetadataMismatch,
            "unknown archive entry flags",
        ));
    }
    Ok(ArchiveEntry {
        path,
        flags,
        order,
        bytes: data,
        sha256: expected_hash,
    })
}

fn machine_file(
    values: &BTreeMap<String, JsonValue>,
    field: &'static str,
    flag: u16,
) -> Result<MachineFile, CodeTableError> {
    let item = object(required(values, field)?, field)?;
    let path = string(required(item, "path")?, field)?.to_owned();
    validate_path(&path)?;
    Ok(MachineFile {
        path,
        byte_size: usize_value(required(item, "byte_size")?, field)?,
        sha256: hash(required(item, "sha256")?, field)?,
        flag,
    })
}

fn validate_metadata_json(bytes: &[u8], name: &str) -> Result<(), CodeTableError> {
    json::parse(bytes).map(|_| ()).map_err(|_| {
        error(
            CodeTableErrorKind::InvalidManifest,
            format!("{name} JSON invalid"),
        )
    })
}

fn validate_trace(bytes: &[u8]) -> Result<(), CodeTableError> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| error(CodeTableErrorKind::InvalidUtf8, "trace index is not UTF-8"))?;
    for line in text.lines() {
        if line.is_empty() || json::parse(line.as_bytes()).is_err() {
            return Err(error(
                CodeTableErrorKind::InvalidManifest,
                "trace JSON line invalid",
            ));
        }
    }
    Ok(())
}

fn validate_path(value: &str) -> Result<(), CodeTableError> {
    if value.is_empty()
        || value.starts_with('/')
        || value.contains('\\')
        || value
            .split('/')
            .any(|part| part.is_empty() || part == "." || part == "..")
        || value.as_bytes().get(1) == Some(&b':')
    {
        return Err(error(
            CodeTableErrorKind::InvalidManifest,
            "unsafe archive path",
        ));
    }
    Ok(())
}

fn validate_id(value: &str) -> Result<(), CodeTableError> {
    if value.is_empty()
        || value.len() > 64
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
    {
        return Err(error(
            CodeTableErrorKind::InvalidManifest,
            "invalid production category id",
        ));
    }
    Ok(())
}

fn object<'a>(
    value: &'a JsonValue,
    field: &str,
) -> Result<&'a BTreeMap<String, JsonValue>, CodeTableError> {
    value.as_object().ok_or_else(|| {
        error(
            CodeTableErrorKind::InvalidManifest,
            format!("{field} is not object"),
        )
    })
}

fn array<'a>(value: &'a JsonValue, field: &str) -> Result<&'a [JsonValue], CodeTableError> {
    value.as_array().ok_or_else(|| {
        error(
            CodeTableErrorKind::InvalidManifest,
            format!("{field} is not array"),
        )
    })
}

fn required<'a>(
    object: &'a BTreeMap<String, JsonValue>,
    field: &str,
) -> Result<&'a JsonValue, CodeTableError> {
    object.get(field).ok_or_else(|| {
        error(
            CodeTableErrorKind::InvalidManifest,
            format!("missing {field}"),
        )
    })
}

fn string<'a>(value: &'a JsonValue, field: &str) -> Result<&'a str, CodeTableError> {
    value.as_str().ok_or_else(|| {
        error(
            CodeTableErrorKind::InvalidManifest,
            format!("{field} is not string"),
        )
    })
}

fn number(value: &JsonValue, field: &str) -> Result<u64, CodeTableError> {
    value.as_u64().ok_or_else(|| {
        error(
            CodeTableErrorKind::InvalidManifest,
            format!("{field} is not number"),
        )
    })
}

fn boolean(value: &JsonValue, field: &str) -> Result<bool, CodeTableError> {
    value.as_bool().ok_or_else(|| {
        error(
            CodeTableErrorKind::InvalidManifest,
            format!("{field} is not boolean"),
        )
    })
}

fn usize_value(value: &JsonValue, field: &str) -> Result<usize, CodeTableError> {
    usize::try_from(number(value, field)?).map_err(|_| {
        error(
            CodeTableErrorKind::InvalidManifest,
            format!("{field} overflow"),
        )
    })
}

fn hash(value: &JsonValue, field: &str) -> Result<[u8; 32], CodeTableError> {
    let value = string(value, field)?;
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(error(
            CodeTableErrorKind::InvalidManifest,
            format!("{field} invalid hash"),
        ));
    }
    let mut output = [0_u8; 32];
    for (index, slot) in output.iter_mut().enumerate() {
        *slot = u8::from_str_radix(&value[index * 2..index * 2 + 2], 16).map_err(|_| {
            error(
                CodeTableErrorKind::InvalidManifest,
                format!("{field} invalid hash"),
            )
        })?;
    }
    Ok(output)
}

fn expect_string(
    object: &BTreeMap<String, JsonValue>,
    field: &str,
    expected: &str,
) -> Result<(), CodeTableError> {
    let actual = string(required(object, field)?, field)?;
    if actual != expected {
        return Err(error(
            CodeTableErrorKind::MetadataMismatch,
            format!("{field} mismatch"),
        ));
    }
    Ok(())
}

fn expect_number(
    object: &BTreeMap<String, JsonValue>,
    field: &str,
    expected: u64,
) -> Result<(), CodeTableError> {
    if number(required(object, field)?, field)? != expected {
        return Err(error(
            CodeTableErrorKind::MetadataMismatch,
            format!("{field} mismatch"),
        ));
    }
    Ok(())
}

#[cfg(test)]
fn append_sized(output: &mut Vec<u8>, value: &[u8]) {
    output.extend_from_slice(&(value.len() as u64).to_le_bytes());
    output.extend_from_slice(value);
}

fn update_sized(output: &mut Sha256, value: &[u8]) {
    output.update(&(value.len() as u64).to_le_bytes());
    output.update(value);
}

fn has_complete_source_order(entries: &[lexicon_core::LexiconEntry]) -> bool {
    let mut seen = vec![false; entries.len()];
    for entry in entries {
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

fn encode(value: [u8; 32]) -> String {
    use std::fmt::Write;
    let mut output = String::with_capacity(64);
    for byte in value {
        write!(&mut output, "{byte:02x}").expect("string write");
    }
    output
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
        .ok_or_else(|| truncated("archive entry"))?;
    *cursor = end;
    Ok(value)
}

fn take_u16(bytes: &[u8], cursor: &mut usize) -> Result<u16, CodeTableError> {
    Ok(u16::from_le_bytes(
        take(bytes, cursor, 2)?
            .try_into()
            .map_err(|_| truncated("entry u16"))?,
    ))
}

fn take_u32(bytes: &[u8], cursor: &mut usize) -> Result<u32, CodeTableError> {
    Ok(u32::from_le_bytes(
        take(bytes, cursor, 4)?
            .try_into()
            .map_err(|_| truncated("entry u32"))?,
    ))
}

fn take_u64(bytes: &[u8], cursor: &mut usize) -> Result<u64, CodeTableError> {
    Ok(u64::from_le_bytes(
        take(bytes, cursor, 8)?
            .try_into()
            .map_err(|_| truncated("entry u64"))?,
    ))
}

fn to_usize(value: u64, field: &str) -> Result<usize, CodeTableError> {
    usize::try_from(value).map_err(|_| truncated(field))
}

fn truncated(field: &str) -> CodeTableError {
    error(
        CodeTableErrorKind::TruncatedData,
        format!("{field} truncated or out of range"),
    )
}

#[cfg(test)]
mod damage_tests {
    use std::collections::BTreeMap;
    use std::fs;
    use std::path::PathBuf;

    use lexicon_core::crc32_ieee;

    use super::*;

    #[derive(Clone, Debug)]
    struct Layout {
        start: usize,
        path_start: usize,
        data_start: usize,
        data_end: usize,
        path: String,
    }

    #[test]
    fn formal_damage_matrix_returns_stable_structured_errors() {
        let base = fs::read(bundle_path()).expect("frozen production bundle");
        let missing = CodeTableBundle::load_file(bundle_path().with_extension("missing"))
            .expect_err("missing file");
        assert_eq!(missing.kind, CodeTableErrorKind::ResourceMissing);

        let mut cases = Vec::<(&str, Vec<u8>, CodeTableErrorKind)>::new();
        cases.push(("empty", Vec::new(), CodeTableErrorKind::TruncatedData));

        let mut value = base.clone();
        value[0] = b'X';
        cases.push(("magic", value, CodeTableErrorKind::InvalidMagic));

        let mut value = base.clone();
        value[8..12].copy_from_slice(&127_u32.to_le_bytes());
        cases.push((
            "header_length",
            value,
            CodeTableErrorKind::UnsupportedVersion,
        ));

        for (name, offset) in [("major", 12), ("minor", 14)] {
            let mut value = base.clone();
            value[offset..offset + 2].copy_from_slice(&9_u16.to_le_bytes());
            cases.push((name, value, CodeTableErrorKind::UnsupportedVersion));
        }
        for (name, offset) in [("converter_binary", 16), ("manifest_version", 20)] {
            let mut value = base.clone();
            value[offset..offset + 4].copy_from_slice(&9_u32.to_le_bytes());
            cases.push((name, value, CodeTableErrorKind::UnsupportedVersion));
        }
        cases.push((
            "truncated_header",
            base[..127].to_vec(),
            CodeTableErrorKind::TruncatedData,
        ));
        cases.push((
            "truncated_record",
            base[..base.len() - 1].to_vec(),
            CodeTableErrorKind::TruncatedData,
        ));

        let mut value = base.clone();
        value.push(0);
        let records_len = (value.len() - HEADER_LEN) as u64;
        value[32..40].copy_from_slice(&records_len.to_le_bytes());
        refresh_header_content(&mut value);
        cases.push((
            "trailing_byte",
            value,
            CodeTableErrorKind::UnexpectedBundleFile,
        ));

        let mut value = base.clone();
        value[80] ^= 1;
        cases.push((
            "bundle_content_sha",
            value,
            CodeTableErrorKind::ChecksumMismatch,
        ));

        let mut value = base.clone();
        let core = layout(&value, "categories/core.lex");
        value[core.data_start] ^= 1;
        refresh_header_content(&mut value);
        cases.push((
            "archive_record_sha",
            value,
            CodeTableErrorKind::ChecksumMismatch,
        ));

        let mut value = base.clone();
        replace_manifest(&mut value, b"source-receipt-1", b"source-receipt-2");
        finish_manifest_only_change(&mut value);
        cases.push((
            "manifest_metadata",
            value,
            CodeTableErrorKind::MetadataMismatch,
        ));

        let mut value = base.clone();
        let core = layout(&value, "categories/core.lex");
        value[core.path_start + "categories/".len()] = b'x';
        refresh_header_content(&mut value);
        cases.push((
            "category_missing",
            value,
            CodeTableErrorKind::MissingBundleFile,
        ));

        let mut value = base.clone();
        replace_manifest(&mut value, b"rare-character", b"full-code-word");
        finish_manifest_only_change(&mut value);
        cases.push((
            "duplicate_category_id",
            value,
            CodeTableErrorKind::DuplicateCategoryId,
        ));

        let mut value = base.clone();
        let core = layout(&value, "categories/core.lex");
        value[core.start + 4..core.start + 8].copy_from_slice(&9_u32.to_le_bytes());
        refresh_header_content(&mut value);
        cases.push((
            "category_record_order",
            value,
            CodeTableErrorKind::MetadataMismatch,
        ));

        let mut value = base.clone();
        let core = layout(&value, "categories/core.lex");
        value[core.data_start] = b'X';
        finish_changed_payload(&mut value, "categories/core.lex");
        cases.push(("nested_hsplex", value, CodeTableErrorKind::InvalidIndex));

        let mut value = base.clone();
        let core = layout(&value, "categories/core.lex");
        let entry_offset = read_u64_raw(&value, core.data_start + 48) as usize;
        let source_order_offset = core.data_start + entry_offset + 36;
        value[source_order_offset..source_order_offset + 4]
            .copy_from_slice(&u32::MAX.to_le_bytes());
        let checksum = crc32_ieee(&value[core.data_start + 96..core.data_end]);
        value[core.data_start + 84..core.data_start + 88].copy_from_slice(&checksum.to_le_bytes());
        finish_changed_payload(&mut value, "categories/core.lex");
        cases.push((
            "source_order",
            value,
            CodeTableErrorKind::InvalidSourceOrder,
        ));

        let mut value = base.clone();
        let rules = layout(&value, "user-rules.txt");
        value[rules.data_start] = 0xff;
        finish_changed_payload(&mut value, "user-rules.txt");
        cases.push(("user_rules", value, CodeTableErrorKind::InvalidUserRules));

        let mut value = base.clone();
        let actions = layout(&value, "action-metadata.json");
        value[actions.path_start..actions.path_start + 3].copy_from_slice(b"../");
        refresh_header_content(&mut value);
        cases.push(("unsafe_path", value, CodeTableErrorKind::InvalidManifest));

        for (name, bytes, expected) in cases {
            let error = CodeTableBundle::load_frozen_production_bytes(&bytes).expect_err(name);
            assert_eq!(error.kind, expected, "{name}: {error}");
            assert!(!error.code().is_empty(), "{name}");
            assert!(!error.detail.is_empty(), "{name}");
        }
    }

    fn bundle_path() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
            "../../../dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
        )
    }

    fn layouts(bytes: &[u8]) -> Vec<Layout> {
        let mut cursor = HEADER_LEN;
        let mut output = Vec::new();
        for _ in 0..read_u32_raw(bytes, 24) {
            let start = cursor;
            let path_len = read_u16_raw(bytes, cursor) as usize;
            let data_len = read_u64_raw(bytes, cursor + 8) as usize;
            let path_start = cursor + 48;
            let data_start = path_start + path_len;
            let data_end = data_start + data_len;
            output.push(Layout {
                start,
                path_start,
                data_start,
                data_end,
                path: String::from_utf8(bytes[path_start..data_start].to_vec()).expect("path"),
            });
            cursor = data_end;
        }
        output
    }

    fn layout(bytes: &[u8], path: &str) -> Layout {
        layouts(bytes)
            .into_iter()
            .find(|entry| entry.path == path)
            .unwrap_or_else(|| panic!("missing layout {path}"))
    }

    fn replace_manifest(bytes: &mut [u8], old: &[u8], new: &[u8]) {
        assert_eq!(old.len(), new.len());
        let manifest = layout(bytes, "manifest.json");
        let relative = bytes[manifest.data_start..manifest.data_end]
            .windows(old.len())
            .position(|window| window == old)
            .expect("manifest value");
        let start = manifest.data_start + relative;
        bytes[start..start + new.len()].copy_from_slice(new);
    }

    fn finish_manifest_only_change(bytes: &mut [u8]) {
        refresh_entry_hash(bytes, "manifest.json");
        refresh_header_content(bytes);
    }

    fn finish_changed_payload(bytes: &mut [u8], path: &str) {
        let entry = layout(bytes, path);
        let old_hash: [u8; 32] = bytes[entry.start + 16..entry.start + 48]
            .try_into()
            .expect("old hash");
        let new_hash = sha256(&bytes[entry.data_start..entry.data_end]);
        replace_manifest(
            bytes,
            encode(old_hash).as_bytes(),
            encode(new_hash).as_bytes(),
        );
        bytes[entry.start + 16..entry.start + 48].copy_from_slice(&new_hash);

        let mut archive = BTreeMap::new();
        for item in layouts(bytes) {
            if item.path != "manifest.json" {
                archive.insert(item.path, bytes[item.data_start..item.data_end].to_vec());
            }
        }
        let mut material = Vec::new();
        for (archive_path, data) in archive {
            append_sized(&mut material, archive_path.as_bytes());
            append_sized(&mut material, &data);
        }
        let bundle_hash = encode(sha256(&material));
        replace_manifest(
            bytes,
            EXPECTED_CONTENT_HASH.as_bytes(),
            bundle_hash.as_bytes(),
        );
        refresh_entry_hash(bytes, "manifest.json");
        refresh_header_content(bytes);
    }

    fn refresh_entry_hash(bytes: &mut [u8], path: &str) {
        let entry = layout(bytes, path);
        let hash = sha256(&bytes[entry.data_start..entry.data_end]);
        bytes[entry.start + 16..entry.start + 48].copy_from_slice(&hash);
    }

    fn refresh_header_content(bytes: &mut [u8]) {
        let hash = sha256(&bytes[HEADER_LEN..]);
        bytes[80..112].copy_from_slice(&hash);
    }

    fn read_u16_raw(bytes: &[u8], offset: usize) -> u16 {
        u16::from_le_bytes(bytes[offset..offset + 2].try_into().expect("u16"))
    }

    fn read_u32_raw(bytes: &[u8], offset: usize) -> u32 {
        u32::from_le_bytes(bytes[offset..offset + 4].try_into().expect("u32"))
    }

    fn read_u64_raw(bytes: &[u8], offset: usize) -> u64 {
        u64::from_le_bytes(bytes[offset..offset + 8].try_into().expect("u64"))
    }
}

fn error(kind: CodeTableErrorKind, detail: impl Into<String>) -> CodeTableError {
    CodeTableError::new(kind, detail)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn production_path_validation_rejects_escape_absolute_and_windows_paths() {
        assert!(validate_path("categories/core.lex").is_ok());
        for path in ["../x", "/x", "C:/x", "a\\b", "a//b", "a/./b"] {
            assert!(validate_path(path).is_err(), "{path}");
        }
    }
}
