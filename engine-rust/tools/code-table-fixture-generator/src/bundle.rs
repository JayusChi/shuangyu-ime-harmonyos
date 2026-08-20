use std::fs;
use std::path::{Path, PathBuf};

use lexicon_builder::flypy_table::FlypyTableImporter;
use lexicon_core::{build_binary_lexicon_with_source_order, load_binary_lexicon};

use crate::error::FixtureError;
use crate::manifest::FixtureManifest;
use crate::sha256::{sha256, sha256_hex};
use crate::table::{validate_table_bytes, ValidatedTable};
use crate::GENERATOR_VERSION;

const MAGIC: [u8; 8] = *b"HSPCTF01";
const HEADER_LEN: usize = 128;
const FORMAT_MAJOR: u16 = 1;
const FORMAT_MINOR: u16 = 0;
const LEXICON_VERSION: u32 = 11_620;
const MIN_NORMAL_ENTRIES: usize = 25_000;
const MIN_GUIDE_ENTRIES: usize = 2_000;

struct HeaderValues {
    manifest_version: u32,
    category_count: usize,
    table_count: usize,
    manifest_len: usize,
    payload_len: usize,
    input_hash: [u8; 32],
    content_hash: [u8; 32],
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TableBinary {
    pub id: String,
    pub is_guide: bool,
    pub order: u32,
    pub default_enabled: bool,
    pub entry_count: usize,
    pub source_sha256: String,
    pub bytes: Vec<u8>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BundleMetadata {
    pub format_version: String,
    pub bundle_id: String,
    pub normal_entry_count: usize,
    pub guide_entry_count: usize,
    pub category_order: Vec<String>,
    pub build_input_sha256: String,
    pub content_sha256: String,
    pub bundle_sha256: String,
    pub bundle_bytes: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BundleBuild {
    pub bytes: Vec<u8>,
    pub metadata: BundleMetadata,
    pub tables: Vec<TableBinary>,
}

pub fn build_bundle(manifest_path: &Path) -> Result<BundleBuild, FixtureError> {
    let manifest_bytes = fs::read(manifest_path)
        .map_err(|source| missing_or_io(manifest_path, source, "manifest"))?;
    let manifest_file = manifest_path.to_string_lossy();
    let manifest = FixtureManifest::from_bytes(&manifest_bytes, &manifest_file)?;
    let normal_expected = manifest
        .categories
        .iter()
        .map(|value| value.expected_entry_count)
        .sum::<usize>();
    if normal_expected < MIN_NORMAL_ENTRIES {
        return Err(FixtureError::diagnostic(
            "CTF_SCALE_TOO_SMALL",
            &*manifest_file,
            0,
            "categories.expectedEntryCount",
            "normal fixture must contain at least 25000 entries",
        ));
    }
    if manifest.guide_table.expected_entry_count < MIN_GUIDE_ENTRIES {
        return Err(FixtureError::diagnostic(
            "CTF_GUIDE_SCALE_TOO_SMALL",
            &*manifest_file,
            0,
            "guideTable.expectedEntryCount",
            "guide fixture must contain at least 2000 entries",
        ));
    }

    let root = manifest_path.parent().unwrap_or_else(|| Path::new("."));
    let canonical_root = root
        .canonicalize()
        .map_err(|source| FixtureError::io(root, source))?;
    let mut categories = manifest.categories.clone();
    categories.sort_by_key(|value| value.order);
    let mut tables = Vec::with_capacity(categories.len() + 1);
    let mut input_material = Vec::new();
    append_sized(&mut input_material, &manifest_bytes);

    for category in &categories {
        let path = resolve_source(&canonical_root, &category.source_path, &manifest_file)?;
        let source = fs::read(&path)
            .map_err(|error| missing_or_io(&path, error, "categories.sourcePath"))?;
        append_sized(&mut input_material, &source);
        let table = validate_source(
            &source,
            &category.source_path,
            category.expected_entry_count,
            &category.source_sha256,
        )?;
        tables.push(build_table(
            &path,
            &category.id,
            false,
            category.order,
            category.default_enabled,
            &category.source_sha256,
            &table,
        )?);
    }

    let guide_path = resolve_source(
        &canonical_root,
        &manifest.guide_table.source_path,
        &manifest_file,
    )?;
    let guide_source = fs::read(&guide_path)
        .map_err(|error| missing_or_io(&guide_path, error, "guideTable.sourcePath"))?;
    append_sized(&mut input_material, &guide_source);
    let guide_table = validate_source(
        &guide_source,
        &manifest.guide_table.source_path,
        manifest.guide_table.expected_entry_count,
        &manifest.guide_table.source_sha256,
    )?;
    tables.push(build_table(
        &guide_path,
        &manifest.guide_table.id,
        true,
        u32::MAX,
        false,
        &manifest.guide_table.source_sha256,
        &guide_table,
    )?);

    let mut payload = Vec::new();
    for table in &tables {
        write_table_record(&mut payload, table)?;
    }
    let mut content = manifest_bytes.clone();
    content.extend_from_slice(&payload);
    let input_hash = sha256(&input_material);
    let content_hash = sha256(&content);
    let mut bytes = vec![0_u8; HEADER_LEN];
    bytes.extend_from_slice(&content);
    write_header(
        &mut bytes[..HEADER_LEN],
        &HeaderValues {
            manifest_version: manifest.format_version,
            category_count: categories.len(),
            table_count: tables.len(),
            manifest_len: manifest_bytes.len(),
            payload_len: payload.len(),
            input_hash,
            content_hash,
        },
    )?;
    let bundle_hash = sha256_hex(&bytes);
    let metadata = BundleMetadata {
        format_version: format!("{FORMAT_MAJOR}.{FORMAT_MINOR}"),
        bundle_id: manifest.bundle_id,
        normal_entry_count: tables
            .iter()
            .filter(|value| !value.is_guide)
            .map(|value| value.entry_count)
            .sum(),
        guide_entry_count: tables
            .iter()
            .find(|value| value.is_guide)
            .map_or(0, |value| value.entry_count),
        category_order: tables
            .iter()
            .filter(|value| !value.is_guide)
            .map(|value| value.id.clone())
            .collect(),
        build_input_sha256: hex(input_hash),
        content_sha256: hex(content_hash),
        bundle_sha256: bundle_hash,
        bundle_bytes: bytes.len(),
    };
    Ok(BundleBuild {
        bytes,
        metadata,
        tables,
    })
}

pub fn verify_bundle(bytes: &[u8]) -> Result<BundleMetadata, FixtureError> {
    if bytes.len() < HEADER_LEN || bytes[..8] != MAGIC {
        return Err(FixtureError::Bundle(
            "invalid fixture bundle magic or length".into(),
        ));
    }
    let header_len = read_u32(bytes, 8)? as usize;
    if header_len != HEADER_LEN {
        return Err(FixtureError::Bundle("unsupported header length".into()));
    }
    let major = read_u16(bytes, 12)?;
    let minor = read_u16(bytes, 14)?;
    if (major, minor) != (FORMAT_MAJOR, FORMAT_MINOR) {
        return Err(FixtureError::Bundle(
            "unsupported bundle format version".into(),
        ));
    }
    if read_u32(bytes, 16)? != GENERATOR_VERSION {
        return Err(FixtureError::Bundle("generator version mismatch".into()));
    }
    let manifest_version = read_u32(bytes, 20)?;
    let category_count = read_u32(bytes, 24)? as usize;
    let table_count = read_u32(bytes, 28)? as usize;
    let manifest_len = read_u64(bytes, 32)? as usize;
    let payload_len = read_u64(bytes, 40)? as usize;
    if HEADER_LEN
        .checked_add(manifest_len)
        .and_then(|value| value.checked_add(payload_len))
        != Some(bytes.len())
    {
        return Err(FixtureError::Bundle(
            "section lengths do not match file length".into(),
        ));
    }
    let expected_content_hash: [u8; 32] = bytes[80..112]
        .try_into()
        .map_err(|_| FixtureError::Bundle("short content checksum".into()))?;
    if sha256(&bytes[HEADER_LEN..]) != expected_content_hash {
        return Err(FixtureError::Bundle("content SHA-256 mismatch".into()));
    }
    let manifest_end = HEADER_LEN + manifest_len;
    let manifest_bytes = &bytes[HEADER_LEN..manifest_end];
    let manifest = FixtureManifest::from_bytes(manifest_bytes, "<bundle-manifest>")?;
    if manifest.format_version != manifest_version || manifest.categories.len() != category_count {
        return Err(FixtureError::Bundle(
            "manifest/header metadata mismatch".into(),
        ));
    }
    let mut cursor = manifest_end;
    let mut tables = Vec::with_capacity(table_count);
    for _ in 0..table_count {
        tables.push(read_table_record(bytes, &mut cursor)?);
    }
    if cursor != bytes.len() || tables.len() != category_count + 1 {
        return Err(FixtureError::Bundle("table record count mismatch".into()));
    }
    let normal = tables
        .iter()
        .filter(|value| !value.is_guide)
        .collect::<Vec<_>>();
    let guide = tables
        .iter()
        .filter(|value| value.is_guide)
        .collect::<Vec<_>>();
    if guide.len() != 1 || normal.len() != manifest.categories.len() {
        return Err(FixtureError::Bundle(
            "guide/category isolation mismatch".into(),
        ));
    }
    let mut expected_categories = manifest.categories.clone();
    expected_categories.sort_by_key(|value| value.order);
    for (actual, expected) in normal.iter().zip(&expected_categories) {
        if actual.id != expected.id
            || actual.order != expected.order
            || actual.default_enabled != expected.default_enabled
            || actual.entry_count != expected.expected_entry_count
            || !actual
                .source_sha256
                .eq_ignore_ascii_case(&expected.source_sha256)
        {
            return Err(FixtureError::Bundle("category metadata mismatch".into()));
        }
    }
    let actual_guide = guide[0];
    if actual_guide.id != manifest.guide_table.id
        || actual_guide.entry_count != manifest.guide_table.expected_entry_count
        || !actual_guide
            .source_sha256
            .eq_ignore_ascii_case(&manifest.guide_table.source_sha256)
    {
        return Err(FixtureError::Bundle("guide metadata mismatch".into()));
    }
    let input_hash: [u8; 32] = bytes[48..80]
        .try_into()
        .map_err(|_| FixtureError::Bundle("short input checksum".into()))?;
    Ok(BundleMetadata {
        format_version: format!("{major}.{minor}"),
        bundle_id: manifest.bundle_id,
        normal_entry_count: normal.iter().map(|value| value.entry_count).sum(),
        guide_entry_count: actual_guide.entry_count,
        category_order: normal.iter().map(|value| value.id.clone()).collect(),
        build_input_sha256: hex(input_hash),
        content_sha256: hex(expected_content_hash),
        bundle_sha256: sha256_hex(bytes),
        bundle_bytes: bytes.len(),
    })
}

fn validate_source(
    bytes: &[u8],
    file: &str,
    expected_count: usize,
    expected_hash: &str,
) -> Result<ValidatedTable, FixtureError> {
    let actual_hash = sha256_hex(bytes);
    if !actual_hash.eq_ignore_ascii_case(expected_hash) {
        return Err(FixtureError::diagnostic(
            "CTF_SOURCE_SHA256_MISMATCH",
            file,
            0,
            "sourceSha256",
            "source SHA-256 does not match manifest",
        ));
    }
    let table = validate_table_bytes(bytes, file)?;
    if table.entry_count != expected_count {
        return Err(FixtureError::diagnostic(
            "CTF_ENTRY_COUNT_MISMATCH",
            file,
            0,
            "expectedEntryCount",
            "valid row count does not match manifest",
        ));
    }
    Ok(table)
}

fn build_table(
    source_path: &Path,
    id: &str,
    is_guide: bool,
    order: u32,
    default_enabled: bool,
    source_hash: &str,
    validated: &ValidatedTable,
) -> Result<TableBinary, FixtureError> {
    let parsed = FlypyTableImporter::new()
        .import_files(&[source_path.to_path_buf()])
        .map_err(|error| FixtureError::Builder(error.to_string()))?;
    if parsed.entries.len() != validated.entry_count {
        return Err(FixtureError::Builder(
            "importer changed the strict validated row count".into(),
        ));
    }
    let bytes =
        build_binary_lexicon_with_source_order(&parsed.entries, LEXICON_VERSION, GENERATOR_VERSION)
            .map_err(|error| FixtureError::Builder(error.to_string()))?;
    let loaded =
        load_binary_lexicon(&bytes).map_err(|error| FixtureError::Builder(error.to_string()))?;
    if loaded.header.format_major != 1 || loaded.header.format_minor != 1 {
        return Err(FixtureError::Builder("expected HSPLEX01 1.1 output".into()));
    }
    let mut ordered = loaded.entries.clone();
    ordered.sort_by_key(|entry| entry.source_order);
    if ordered.iter().zip(&validated.rows).any(|(entry, row)| {
        entry.source_order != row.source_order
            || entry.word != row.word
            || entry.pinyin_key != row.code
    }) {
        return Err(FixtureError::Builder(
            "source_order round-trip does not match physical valid-row order".into(),
        ));
    }
    Ok(TableBinary {
        id: id.to_owned(),
        is_guide,
        order,
        default_enabled,
        entry_count: validated.entry_count,
        source_sha256: source_hash.to_ascii_lowercase(),
        bytes,
    })
}

fn resolve_source(
    root: &Path,
    relative: &str,
    manifest_file: &str,
) -> Result<PathBuf, FixtureError> {
    let joined = root.join(relative);
    let canonical = joined
        .canonicalize()
        .map_err(|error| missing_or_io(&joined, error, "sourcePath"))?;
    if !canonical.starts_with(root) {
        return Err(FixtureError::diagnostic(
            "CTF_PATH_TRAVERSAL",
            manifest_file,
            0,
            "sourcePath",
            "resolved source escapes manifest root",
        ));
    }
    Ok(canonical)
}

fn missing_or_io(path: &Path, error: std::io::Error, field: &'static str) -> FixtureError {
    if error.kind() == std::io::ErrorKind::NotFound {
        FixtureError::diagnostic(
            "CTF_SOURCE_MISSING",
            path.to_string_lossy(),
            0,
            field,
            "required source file is missing",
        )
    } else {
        FixtureError::io(path, error)
    }
}

fn append_sized(output: &mut Vec<u8>, bytes: &[u8]) {
    output.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
    output.extend_from_slice(bytes);
}

fn write_header(header: &mut [u8], values: &HeaderValues) -> Result<(), FixtureError> {
    header[..8].copy_from_slice(&MAGIC);
    header[8..12].copy_from_slice(&(HEADER_LEN as u32).to_le_bytes());
    header[12..14].copy_from_slice(&FORMAT_MAJOR.to_le_bytes());
    header[14..16].copy_from_slice(&FORMAT_MINOR.to_le_bytes());
    header[16..20].copy_from_slice(&GENERATOR_VERSION.to_le_bytes());
    header[20..24].copy_from_slice(&values.manifest_version.to_le_bytes());
    header[24..28].copy_from_slice(
        &u32::try_from(values.category_count)
            .map_err(|_| FixtureError::Bundle("too many categories".into()))?
            .to_le_bytes(),
    );
    header[28..32].copy_from_slice(
        &u32::try_from(values.table_count)
            .map_err(|_| FixtureError::Bundle("too many tables".into()))?
            .to_le_bytes(),
    );
    header[32..40].copy_from_slice(&(values.manifest_len as u64).to_le_bytes());
    header[40..48].copy_from_slice(&(values.payload_len as u64).to_le_bytes());
    header[48..80].copy_from_slice(&values.input_hash);
    header[80..112].copy_from_slice(&values.content_hash);
    Ok(())
}

fn write_table_record(output: &mut Vec<u8>, table: &TableBinary) -> Result<(), FixtureError> {
    let id_len = u16::try_from(table.id.len())
        .map_err(|_| FixtureError::Bundle("table id is too long".into()))?;
    output.extend_from_slice(&id_len.to_le_bytes());
    output.push(u8::from(table.is_guide));
    output.push(u8::from(table.default_enabled));
    output.extend_from_slice(&table.order.to_le_bytes());
    output.extend_from_slice(
        &u32::try_from(table.entry_count)
            .map_err(|_| FixtureError::Bundle("table entry count exceeds u32".into()))?
            .to_le_bytes(),
    );
    output.extend_from_slice(&decode_hash(&table.source_sha256)?);
    output.extend_from_slice(&(table.bytes.len() as u64).to_le_bytes());
    output.extend_from_slice(table.id.as_bytes());
    output.extend_from_slice(&table.bytes);
    Ok(())
}

fn read_table_record(bytes: &[u8], cursor: &mut usize) -> Result<TableBinary, FixtureError> {
    let id_len = take_u16(bytes, cursor)? as usize;
    let is_guide = take_u8(bytes, cursor)? != 0;
    let default_enabled = take_u8(bytes, cursor)? != 0;
    let order = take_u32(bytes, cursor)?;
    let entry_count = take_u32(bytes, cursor)? as usize;
    let source_hash = take(bytes, cursor, 32)?;
    let binary_len = usize::try_from(take_u64(bytes, cursor)?)
        .map_err(|_| FixtureError::Bundle("binary length exceeds usize".into()))?;
    let id = std::str::from_utf8(take(bytes, cursor, id_len)?)
        .map_err(|_| FixtureError::Bundle("table id is not UTF-8".into()))?
        .to_owned();
    let binary = take(bytes, cursor, binary_len)?.to_vec();
    let loaded = load_binary_lexicon(&binary)
        .map_err(|error| FixtureError::Bundle(format!("nested HSPLEX01 invalid: {error}")))?;
    if loaded.header.format_minor != 1 || loaded.entries.len() != entry_count {
        return Err(FixtureError::Bundle(
            "nested table metadata mismatch".into(),
        ));
    }
    Ok(TableBinary {
        id,
        is_guide,
        order,
        default_enabled,
        entry_count,
        source_sha256: hex(source_hash.try_into().expect("32-byte hash")),
        bytes: binary,
    })
}

fn decode_hash(value: &str) -> Result<[u8; 32], FixtureError> {
    let mut output = [0_u8; 32];
    if value.len() != 64 {
        return Err(FixtureError::Bundle("invalid SHA-256 hex length".into()));
    }
    for (index, slot) in output.iter_mut().enumerate() {
        *slot = u8::from_str_radix(&value[index * 2..index * 2 + 2], 16)
            .map_err(|_| FixtureError::Bundle("invalid SHA-256 hex".into()))?;
    }
    Ok(output)
}

fn hex(value: [u8; 32]) -> String {
    let mut output = String::with_capacity(64);
    for byte in value {
        use std::fmt::Write;
        write!(&mut output, "{byte:02x}").expect("writing to String cannot fail");
    }
    output
}

fn read_u16(bytes: &[u8], offset: usize) -> Result<u16, FixtureError> {
    Ok(u16::from_le_bytes(
        bytes
            .get(offset..offset + 2)
            .ok_or_else(|| FixtureError::Bundle("truncated u16".into()))?
            .try_into()
            .expect("two bytes"),
    ))
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32, FixtureError> {
    Ok(u32::from_le_bytes(
        bytes
            .get(offset..offset + 4)
            .ok_or_else(|| FixtureError::Bundle("truncated u32".into()))?
            .try_into()
            .expect("four bytes"),
    ))
}

fn read_u64(bytes: &[u8], offset: usize) -> Result<u64, FixtureError> {
    Ok(u64::from_le_bytes(
        bytes
            .get(offset..offset + 8)
            .ok_or_else(|| FixtureError::Bundle("truncated u64".into()))?
            .try_into()
            .expect("eight bytes"),
    ))
}

fn take<'a>(bytes: &'a [u8], cursor: &mut usize, count: usize) -> Result<&'a [u8], FixtureError> {
    let end = cursor
        .checked_add(count)
        .ok_or_else(|| FixtureError::Bundle("cursor overflow".into()))?;
    let value = bytes
        .get(*cursor..end)
        .ok_or_else(|| FixtureError::Bundle("truncated table record".into()))?;
    *cursor = end;
    Ok(value)
}

fn take_u8(bytes: &[u8], cursor: &mut usize) -> Result<u8, FixtureError> {
    Ok(take(bytes, cursor, 1)?[0])
}

fn take_u16(bytes: &[u8], cursor: &mut usize) -> Result<u16, FixtureError> {
    Ok(u16::from_le_bytes(
        take(bytes, cursor, 2)?.try_into().expect("two bytes"),
    ))
}

fn take_u32(bytes: &[u8], cursor: &mut usize) -> Result<u32, FixtureError> {
    Ok(u32::from_le_bytes(
        take(bytes, cursor, 4)?.try_into().expect("four bytes"),
    ))
}

fn take_u64(bytes: &[u8], cursor: &mut usize) -> Result<u64, FixtureError> {
    Ok(u64::from_le_bytes(
        take(bytes, cursor, 8)?.try_into().expect("eight bytes"),
    ))
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;
    use crate::generate_fixture;

    static NEXT_TEMP: AtomicUsize = AtomicUsize::new(0);

    fn temp_root(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "code-table-bundle-{name}-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ))
    }

    #[test]
    fn bundle_round_trip_preserves_category_and_source_order() {
        let root = temp_root("roundtrip");
        let report = generate_fixture(&root).unwrap();
        let build = build_bundle(&report.manifest_path).unwrap();
        let verified = verify_bundle(&build.bytes).unwrap();
        assert_eq!(verified, build.metadata);
        assert_eq!(verified.normal_entry_count, 25_000);
        assert_eq!(verified.guide_entry_count, 2_000);
        assert_eq!(
            verified.category_order,
            ["core", "phrases", "extended", "domain", "symbols"]
        );
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn independent_bundles_are_byte_identical_and_detect_mutation() {
        let left = temp_root("left");
        let right = temp_root("right");
        let left_report = generate_fixture(&left).unwrap();
        let right_report = generate_fixture(&right).unwrap();
        let left_build = build_bundle(&left_report.manifest_path).unwrap();
        let right_build = build_bundle(&right_report.manifest_path).unwrap();
        assert_eq!(left_build.bytes, right_build.bytes);
        assert_eq!(
            left_build.metadata.bundle_sha256,
            right_build.metadata.bundle_sha256
        );
        let mut damaged = left_build.bytes.clone();
        let last = damaged.len() - 1;
        damaged[last] ^= 1;
        assert!(verify_bundle(&damaged).is_err());
        let _ = fs::remove_dir_all(left);
        let _ = fs::remove_dir_all(right);
    }

    #[test]
    fn manifest_file_failures_have_distinct_stable_codes() {
        let root = temp_root("manifest-negatives");
        let report = generate_fixture(&root).unwrap();
        let original_bytes = fs::read(&report.manifest_path).unwrap();
        let original = FixtureManifest::from_bytes(&original_bytes, "manifest.json").unwrap();

        let mut missing = original.clone();
        missing.categories[0].source_path = "source/missing.txt".into();
        fs::write(&report.manifest_path, missing.to_json_bytes()).unwrap();
        assert_diagnostic(build_bundle(&report.manifest_path), "CTF_SOURCE_MISSING");

        let mut count = original.clone();
        count.categories[0].expected_entry_count += 1;
        fs::write(&report.manifest_path, count.to_json_bytes()).unwrap();
        assert_diagnostic(
            build_bundle(&report.manifest_path),
            "CTF_ENTRY_COUNT_MISMATCH",
        );

        let mut checksum = original;
        checksum.categories[0].source_sha256 = "0".repeat(64);
        fs::write(&report.manifest_path, checksum.to_json_bytes()).unwrap();
        assert_diagnostic(
            build_bundle(&report.manifest_path),
            "CTF_SOURCE_SHA256_MISMATCH",
        );
        let _ = fs::remove_dir_all(root);
    }

    fn assert_diagnostic(result: Result<BundleBuild, FixtureError>, expected: &'static str) {
        let error = result.unwrap_err();
        let FixtureError::Diagnostic(diagnostic) = error else {
            panic!("expected diagnostic, got {error}");
        };
        assert_eq!(diagnostic.code, expected);
        assert!(!diagnostic.file.is_empty());
        assert!(!diagnostic.field.is_empty());
        assert!(!diagnostic.reason.is_empty());
    }
}
