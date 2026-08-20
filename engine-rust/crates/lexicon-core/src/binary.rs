use std::collections::BTreeMap;

use crate::checksum::crc32_ieee;
use crate::error::LexiconError;
use crate::model::{LexiconEntry, PinyinIndex, SOURCE_ORDER_UNSPECIFIED};

/// Fixed magic number for stage 6 binary lexicons.
pub const MAGIC: [u8; 8] = *b"HSPLEX01";
/// Stage 6 binary format major version.
pub const FORMAT_MAJOR_VERSION: u16 = 1;
/// Stage 6 binary format minor version.
pub const FORMAT_MINOR_VERSION: u16 = 1;
/// Checksum algorithm identifier for IEEE CRC32 over the payload.
pub const CHECKSUM_ALGORITHM_CRC32: u32 = 1;

const HEADER_LEN: usize = 96;
const ENTRY_RECORD_LEN_V1_0: usize = 36;
const ENTRY_RECORD_LEN_V1_1: usize = 40;
const INDEX_RECORD_LEN: usize = 16;

/// Header decoded from a binary lexicon.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LexiconHeader {
    /// Format major version.
    pub format_major: u16,
    /// Format minor version.
    pub format_minor: u16,
    /// Deterministic builder version written by the offline builder.
    pub builder_version: u32,
    /// User supplied lexicon data version.
    pub lexicon_version: u32,
    /// Number of entries in the entry table.
    pub entry_count: u32,
    /// Number of pinyin-key index records.
    pub pinyin_key_count: u32,
    /// Absolute string table offset from the start of the file.
    pub string_table_offset: u64,
    /// String table length in bytes.
    pub string_table_length: u64,
    /// Absolute entry table offset from the start of the file.
    pub entry_table_offset: u64,
    /// Entry table length in bytes.
    pub entry_table_length: u64,
    /// Absolute pinyin-key index table offset from the start of the file.
    pub index_offset: u64,
    /// Pinyin-key index table length in bytes.
    pub index_length: u64,
    /// Checksum algorithm identifier.
    pub checksum_algorithm: u32,
    /// CRC32 checksum over all payload bytes after the header.
    pub payload_checksum: u32,
}

/// A verified binary lexicon loaded into owned Rust values.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BinaryLexicon {
    /// Parsed and verified file header.
    pub header: LexiconHeader,
    /// Normalized entries in deterministic binary order.
    pub entries: Vec<LexiconEntry>,
    /// Pinyin-key index ranges into `entries`.
    pub index: Vec<PinyinIndex>,
}

/// Builds deterministic binary lexicon bytes from normalized entries.
pub fn build_binary_lexicon(
    entries: &[LexiconEntry],
    lexicon_version: u32,
    builder_version: u32,
) -> Result<Vec<u8>, LexiconError> {
    build_binary_lexicon_for_minor(entries, lexicon_version, builder_version, 0)
}

/// Builds format 1.1 bytes with a persisted `source_order` field.
///
/// The existing builder entry point intentionally remains on format 1.0 so
/// production pinyin lexicons keep their established byte representation.
pub fn build_binary_lexicon_with_source_order(
    entries: &[LexiconEntry],
    lexicon_version: u32,
    builder_version: u32,
) -> Result<Vec<u8>, LexiconError> {
    build_binary_lexicon_for_minor(entries, lexicon_version, builder_version, 1)
}

fn build_binary_lexicon_for_minor(
    entries: &[LexiconEntry],
    lexicon_version: u32,
    builder_version: u32,
    format_minor: u16,
) -> Result<Vec<u8>, LexiconError> {
    if entries.is_empty() {
        return Err(LexiconError::EmptyLexicon);
    }

    let mut sorted_entries = entries.to_vec();
    sort_entries(&mut sorted_entries);

    let mut strings = BTreeMap::<String, (u32, u32)>::new();
    for entry in &sorted_entries {
        intern_string(&mut strings, &entry.word)?;
        intern_string(&mut strings, &entry.pinyin_key)?;
        intern_string(&mut strings, &entry.source_key())?;
    }

    let mut string_table = Vec::new();
    for (value, slot) in &mut strings {
        let offset =
            u32::try_from(string_table.len()).map_err(|_| LexiconError::ValueOutOfRange {
                field: "string_table_offset",
            })?;
        let len = u32::try_from(value.len()).map_err(|_| LexiconError::ValueOutOfRange {
            field: "string_length",
        })?;
        string_table.extend_from_slice(value.as_bytes());
        *slot = (offset, len);
    }

    let entry_record_len = entry_record_len(format_minor)?;
    let mut entry_table = Vec::with_capacity(sorted_entries.len() * entry_record_len);
    for entry in &sorted_entries {
        let source_key = entry.source_key();
        let (word_offset, word_len) = strings[&entry.word];
        let (pinyin_offset, pinyin_len) = strings[&entry.pinyin_key];
        let (source_offset, source_len) = strings[&source_key];
        write_u32(&mut entry_table, word_offset);
        write_u32(&mut entry_table, word_len);
        write_u32(&mut entry_table, pinyin_offset);
        write_u32(&mut entry_table, pinyin_len);
        write_u32(&mut entry_table, source_offset);
        write_u32(&mut entry_table, source_len);
        write_u64(&mut entry_table, entry.frequency);
        write_u16(
            &mut entry_table,
            u16::try_from(entry.syllables.len()).map_err(|_| LexiconError::ValueOutOfRange {
                field: "syllable_count",
            })?,
        );
        write_u16(&mut entry_table, 0);
        if format_minor >= 1 {
            write_u32(&mut entry_table, entry.source_order);
        }
    }

    let index = build_index(&sorted_entries)?;
    let mut index_table = Vec::with_capacity(index.len() * INDEX_RECORD_LEN);
    for record in &index {
        let (pinyin_offset, pinyin_len) = strings[&record.pinyin_key];
        write_u32(&mut index_table, pinyin_offset);
        write_u32(&mut index_table, pinyin_len);
        write_u32(&mut index_table, record.start);
        write_u32(&mut index_table, record.len);
    }

    let string_offset = HEADER_LEN;
    let entry_offset = checked_add(string_offset, string_table.len(), "entry_table_offset")?;
    let index_offset = checked_add(entry_offset, entry_table.len(), "index_offset")?;

    let mut payload =
        Vec::with_capacity(string_table.len() + entry_table.len() + index_table.len());
    payload.extend_from_slice(&string_table);
    payload.extend_from_slice(&entry_table);
    payload.extend_from_slice(&index_table);
    let checksum = crc32_ieee(&payload);

    let header = LexiconHeader {
        format_major: FORMAT_MAJOR_VERSION,
        format_minor,
        builder_version,
        lexicon_version,
        entry_count: to_u32(sorted_entries.len(), "entry_count")?,
        pinyin_key_count: to_u32(index.len(), "pinyin_key_count")?,
        string_table_offset: to_u64(string_offset, "string_table_offset")?,
        string_table_length: to_u64(string_table.len(), "string_table_length")?,
        entry_table_offset: to_u64(entry_offset, "entry_table_offset")?,
        entry_table_length: to_u64(entry_table.len(), "entry_table_length")?,
        index_offset: to_u64(index_offset, "index_offset")?,
        index_length: to_u64(index_table.len(), "index_length")?,
        checksum_algorithm: CHECKSUM_ALGORITHM_CRC32,
        payload_checksum: checksum,
    };

    let mut bytes = encode_header(&header);
    bytes.extend_from_slice(&payload);
    Ok(bytes)
}

/// Loads and verifies binary lexicon bytes.
pub fn load_binary_lexicon(bytes: &[u8]) -> Result<BinaryLexicon, LexiconError> {
    load_binary_lexicon_with_profile(bytes, false)
}

/// Loads a binary lexicon for code-table lookup without retaining metadata
/// that the code-table runtime never reads.
///
/// The persisted source and syllable fields are still bounds/UTF-8 checked,
/// but avoiding their per-entry vectors and strings materially reduces the
/// resident size of large code-table bundles.
pub fn load_binary_lexicon_compact(bytes: &[u8]) -> Result<BinaryLexicon, LexiconError> {
    load_binary_lexicon_with_profile(bytes, true)
}

fn load_binary_lexicon_with_profile(
    bytes: &[u8],
    compact_code_table: bool,
) -> Result<BinaryLexicon, LexiconError> {
    let header = decode_header(bytes)?;
    validate_layout(bytes, &header)?;

    let payload = &bytes[HEADER_LEN..];
    let actual_checksum = crc32_ieee(payload);
    if actual_checksum != header.payload_checksum {
        return Err(LexiconError::ChecksumMismatch {
            expected: header.payload_checksum,
            actual: actual_checksum,
        });
    }

    let string_table = slice_section(
        bytes,
        header.string_table_offset,
        header.string_table_length,
        "string_table",
    )?;
    let entry_table = slice_section(
        bytes,
        header.entry_table_offset,
        header.entry_table_length,
        "entry_table",
    )?;
    let index_table = slice_section(bytes, header.index_offset, header.index_length, "index")?;

    let entry_record_len = entry_record_len(header.format_minor)?;
    let mut entries = Vec::with_capacity(header.entry_count as usize);
    for record in entry_table.chunks_exact(entry_record_len) {
        let word = read_string(
            string_table,
            read_u32(record, 0),
            read_u32(record, 4),
            "word",
        )?;
        let pinyin_key = read_string(
            string_table,
            read_u32(record, 8),
            read_u32(record, 12),
            "pinyin_key",
        )?;
        let source_key = read_str(
            string_table,
            read_u32(record, 16),
            read_u32(record, 20),
            "source",
        )?;
        let frequency = read_u64(record, 24);
        let syllable_count = usize::from(read_u16(record, 32));
        let actual_syllable_count = if pinyin_key.is_empty() {
            0
        } else {
            pinyin_key.split(' ').count()
        };
        if actual_syllable_count != syllable_count {
            return Err(LexiconError::InvalidIndexOrder { key: pinyin_key });
        }
        let syllables = if compact_code_table || pinyin_key.is_empty() {
            Vec::new()
        } else {
            pinyin_key.split(' ').map(str::to_owned).collect::<Vec<_>>()
        };
        let sources = if compact_code_table {
            Vec::new()
        } else {
            split_sources(source_key)
        };
        let source_order = if header.format_minor >= 1 {
            read_u32(record, 36)
        } else {
            SOURCE_ORDER_UNSPECIFIED
        };
        entries.push(
            LexiconEntry::new(word, pinyin_key, syllables, frequency, sources)
                .with_source_order(source_order),
        );
    }

    let mut index = Vec::with_capacity(header.pinyin_key_count as usize);
    for record in index_table.chunks_exact(INDEX_RECORD_LEN) {
        let pinyin_key = read_string(
            string_table,
            read_u32(record, 0),
            read_u32(record, 4),
            "index.pinyin_key",
        )?;
        let start = read_u32(record, 8);
        let len = read_u32(record, 12);
        let end = start
            .checked_add(len)
            .ok_or_else(|| LexiconError::IndexOutOfBounds {
                key: pinyin_key.clone(),
            })?;
        if end as usize > entries.len() {
            return Err(LexiconError::IndexOutOfBounds { key: pinyin_key });
        }
        for entry in &entries[start as usize..end as usize] {
            if entry.pinyin_key != pinyin_key {
                return Err(LexiconError::InvalidIndexOrder {
                    key: pinyin_key.clone(),
                });
            }
        }
        index.push(PinyinIndex {
            pinyin_key,
            start,
            len,
        });
    }

    Ok(BinaryLexicon {
        header,
        entries,
        index,
    })
}

fn sort_entries(entries: &mut [LexiconEntry]) {
    entries.sort_by(|left, right| {
        left.pinyin_key
            .cmp(&right.pinyin_key)
            .then_with(|| left.word.cmp(&right.word))
            .then_with(|| left.source_key().cmp(&right.source_key()))
            .then_with(|| left.frequency.cmp(&right.frequency))
    });
}

fn build_index(entries: &[LexiconEntry]) -> Result<Vec<PinyinIndex>, LexiconError> {
    let mut index = Vec::new();
    let mut cursor = 0_usize;
    while cursor < entries.len() {
        let key = entries[cursor].pinyin_key.clone();
        let start = cursor;
        while cursor < entries.len() && entries[cursor].pinyin_key == key {
            cursor += 1;
        }
        index.push(PinyinIndex {
            pinyin_key: key,
            start: to_u32(start, "index_start")?,
            len: to_u32(cursor - start, "index_len")?,
        });
    }
    Ok(index)
}

fn intern_string(
    strings: &mut BTreeMap<String, (u32, u32)>,
    value: &str,
) -> Result<(), LexiconError> {
    if !strings.contains_key(value) {
        strings.insert(value.to_owned(), (0, 0));
    }
    Ok(())
}

fn encode_header(header: &LexiconHeader) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(HEADER_LEN);
    bytes.extend_from_slice(&MAGIC);
    write_u32(&mut bytes, HEADER_LEN as u32);
    write_u16(&mut bytes, header.format_major);
    write_u16(&mut bytes, header.format_minor);
    write_u32(&mut bytes, header.builder_version);
    write_u32(&mut bytes, header.lexicon_version);
    write_u32(&mut bytes, header.entry_count);
    write_u32(&mut bytes, header.pinyin_key_count);
    write_u64(&mut bytes, header.string_table_offset);
    write_u64(&mut bytes, header.string_table_length);
    write_u64(&mut bytes, header.entry_table_offset);
    write_u64(&mut bytes, header.entry_table_length);
    write_u64(&mut bytes, header.index_offset);
    write_u64(&mut bytes, header.index_length);
    write_u32(&mut bytes, header.checksum_algorithm);
    write_u32(&mut bytes, header.payload_checksum);
    write_u32(&mut bytes, 0);
    write_u32(&mut bytes, 0);
    debug_assert_eq!(bytes.len(), HEADER_LEN);
    bytes
}

fn decode_header(bytes: &[u8]) -> Result<LexiconHeader, LexiconError> {
    if bytes.len() < HEADER_LEN {
        return Err(LexiconError::TruncatedHeader { len: bytes.len() });
    }
    if bytes[0..8] != MAGIC {
        return Err(LexiconError::InvalidMagic);
    }
    let header_len = read_u32(bytes, 8);
    if header_len != HEADER_LEN as u32 {
        return Err(LexiconError::InvalidHeaderLength { actual: header_len });
    }
    let format_major = read_u16(bytes, 12);
    let format_minor = read_u16(bytes, 14);
    if format_major != FORMAT_MAJOR_VERSION || format_minor > FORMAT_MINOR_VERSION {
        return Err(LexiconError::UnsupportedVersion {
            major: format_major,
            minor: format_minor,
        });
    }
    let checksum_algorithm = read_u32(bytes, 80);
    if checksum_algorithm != CHECKSUM_ALGORITHM_CRC32 {
        return Err(LexiconError::UnsupportedChecksumAlgorithm {
            algorithm: checksum_algorithm,
        });
    }
    Ok(LexiconHeader {
        format_major,
        format_minor,
        builder_version: read_u32(bytes, 16),
        lexicon_version: read_u32(bytes, 20),
        entry_count: read_u32(bytes, 24),
        pinyin_key_count: read_u32(bytes, 28),
        string_table_offset: read_u64(bytes, 32),
        string_table_length: read_u64(bytes, 40),
        entry_table_offset: read_u64(bytes, 48),
        entry_table_length: read_u64(bytes, 56),
        index_offset: read_u64(bytes, 64),
        index_length: read_u64(bytes, 72),
        checksum_algorithm,
        payload_checksum: read_u32(bytes, 84),
    })
}

fn validate_layout(bytes: &[u8], header: &LexiconHeader) -> Result<(), LexiconError> {
    if header.string_table_offset != HEADER_LEN as u64 {
        return Err(LexiconError::SectionOutOfBounds {
            section: "string_table",
        });
    }
    if header.entry_table_offset
        != header
            .string_table_offset
            .checked_add(header.string_table_length)
            .ok_or(LexiconError::SectionOutOfBounds {
                section: "entry_table",
            })?
    {
        return Err(LexiconError::SectionOutOfBounds {
            section: "entry_table",
        });
    }
    if header.index_offset
        != header
            .entry_table_offset
            .checked_add(header.entry_table_length)
            .ok_or(LexiconError::SectionOutOfBounds { section: "index" })?
    {
        return Err(LexiconError::SectionOutOfBounds { section: "index" });
    }
    let end = header
        .index_offset
        .checked_add(header.index_length)
        .ok_or(LexiconError::SectionOutOfBounds { section: "index" })?;
    if end != bytes.len() as u64 {
        return Err(LexiconError::SectionOutOfBounds { section: "index" });
    }
    let entry_record_len = entry_record_len(header.format_minor)?;
    if header.entry_table_length as usize != header.entry_count as usize * entry_record_len {
        return Err(LexiconError::InvalidTableLength {
            table: "entry_table",
        });
    }
    if header.index_length as usize != header.pinyin_key_count as usize * INDEX_RECORD_LEN {
        return Err(LexiconError::InvalidTableLength { table: "index" });
    }
    Ok(())
}

fn entry_record_len(format_minor: u16) -> Result<usize, LexiconError> {
    match format_minor {
        0 => Ok(ENTRY_RECORD_LEN_V1_0),
        1 => Ok(ENTRY_RECORD_LEN_V1_1),
        _ => Err(LexiconError::UnsupportedVersion {
            major: FORMAT_MAJOR_VERSION,
            minor: format_minor,
        }),
    }
}

fn slice_section<'a>(
    bytes: &'a [u8],
    offset: u64,
    len: u64,
    section: &'static str,
) -> Result<&'a [u8], LexiconError> {
    let start =
        usize::try_from(offset).map_err(|_| LexiconError::SectionOutOfBounds { section })?;
    let len = usize::try_from(len).map_err(|_| LexiconError::SectionOutOfBounds { section })?;
    let end = start
        .checked_add(len)
        .ok_or(LexiconError::SectionOutOfBounds { section })?;
    bytes
        .get(start..end)
        .ok_or(LexiconError::SectionOutOfBounds { section })
}

fn read_string(
    string_table: &[u8],
    offset: u32,
    len: u32,
    field: &'static str,
) -> Result<String, LexiconError> {
    let start = offset as usize;
    let len = len as usize;
    let end = start
        .checked_add(len)
        .ok_or(LexiconError::StringOutOfBounds { field })?;
    let bytes = string_table
        .get(start..end)
        .ok_or(LexiconError::StringOutOfBounds { field })?;
    std::str::from_utf8(bytes)
        .map(str::to_owned)
        .map_err(|_| LexiconError::InvalidUtf8 { field })
}

fn read_str<'a>(
    string_table: &'a [u8],
    offset: u32,
    len: u32,
    field: &'static str,
) -> Result<&'a str, LexiconError> {
    let start = offset as usize;
    let len = len as usize;
    let end = start
        .checked_add(len)
        .ok_or(LexiconError::StringOutOfBounds { field })?;
    let bytes = string_table
        .get(start..end)
        .ok_or(LexiconError::StringOutOfBounds { field })?;
    std::str::from_utf8(bytes).map_err(|_| LexiconError::InvalidUtf8 { field })
}

fn split_sources(source_key: &str) -> Vec<String> {
    if source_key.is_empty() {
        Vec::new()
    } else {
        source_key.split(',').map(str::to_owned).collect()
    }
}

fn write_u16(bytes: &mut Vec<u8>, value: u16) {
    bytes.extend_from_slice(&value.to_le_bytes());
}

fn write_u32(bytes: &mut Vec<u8>, value: u32) {
    bytes.extend_from_slice(&value.to_le_bytes());
}

fn write_u64(bytes: &mut Vec<u8>, value: u64) {
    bytes.extend_from_slice(&value.to_le_bytes());
}

fn read_u16(bytes: &[u8], offset: usize) -> u16 {
    u16::from_le_bytes(bytes[offset..offset + 2].try_into().unwrap())
}

fn read_u32(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap())
}

fn read_u64(bytes: &[u8], offset: usize) -> u64 {
    u64::from_le_bytes(bytes[offset..offset + 8].try_into().unwrap())
}

fn to_u32(value: usize, field: &'static str) -> Result<u32, LexiconError> {
    u32::try_from(value).map_err(|_| LexiconError::ValueOutOfRange { field })
}

fn to_u64(value: usize, field: &'static str) -> Result<u64, LexiconError> {
    u64::try_from(value).map_err(|_| LexiconError::ValueOutOfRange { field })
}

fn checked_add(left: usize, right: usize, field: &'static str) -> Result<usize, LexiconError> {
    left.checked_add(right)
        .ok_or(LexiconError::ValueOutOfRange { field })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_and_loads_binary_lexicon() {
        let bytes = sample_bytes();
        let loaded = load_binary_lexicon(&bytes).unwrap();

        assert_eq!(loaded.header.format_major, 1);
        assert_eq!(loaded.header.format_minor, 0);
        assert_eq!(loaded.header.lexicon_version, 7);
        assert_eq!(loaded.entries.len(), 3);
        assert_eq!(loaded.index.len(), 3);
        assert_eq!(loaded.entries[0].word, "好");
        assert_eq!(loaded.entries[0].pinyin_key, "hao");
        assert_eq!(loaded.entries[2].word, "你好");
        assert!(loaded
            .entries
            .iter()
            .all(|entry| entry.source_order == SOURCE_ORDER_UNSPECIFIED));
    }

    #[test]
    fn format_1_1_persists_source_order_after_key_sorting() {
        let entries = vec![
            LexiconEntry::new(
                "第一词".to_owned(),
                "abz".to_owned(),
                vec!["abz".to_owned()],
                0,
                vec!["test".to_owned()],
            )
            .with_source_order(0),
            LexiconEntry::new(
                "第二词".to_owned(),
                "aba".to_owned(),
                vec!["aba".to_owned()],
                0,
                vec!["test".to_owned()],
            )
            .with_source_order(1),
        ];

        let bytes = build_binary_lexicon_with_source_order(&entries, 7, 1).unwrap();
        let loaded = load_binary_lexicon(&bytes).unwrap();

        assert_eq!(loaded.header.format_minor, 1);
        assert_eq!(loaded.entries[0].word, "第二词");
        assert_eq!(loaded.entries[0].source_order, 1);
        assert_eq!(loaded.entries[1].word, "第一词");
        assert_eq!(loaded.entries[1].source_order, 0);
    }

    #[test]
    fn compact_code_table_profile_drops_unused_entry_metadata() {
        let loaded = load_binary_lexicon_compact(&sample_bytes()).unwrap();
        assert!(loaded
            .entries
            .iter()
            .all(|entry| entry.syllables.is_empty() && entry.sources.is_empty()));
        assert_eq!(loaded.entries[0].word, "好");
        assert_eq!(loaded.entries[0].pinyin_key, "hao");
        assert_eq!(loaded.index.len(), 3);
    }

    #[test]
    fn rejects_empty_lexicon() {
        assert_eq!(
            build_binary_lexicon(&[], 1, 1),
            Err(LexiconError::EmptyLexicon)
        );
    }

    #[test]
    fn rejects_bad_magic_and_unsupported_version() {
        let mut bad_magic = sample_bytes();
        bad_magic[0] = b'X';
        assert_eq!(
            load_binary_lexicon(&bad_magic),
            Err(LexiconError::InvalidMagic)
        );

        let mut bad_version = sample_bytes();
        bad_version[12..14].copy_from_slice(&2_u16.to_le_bytes());
        assert_eq!(
            load_binary_lexicon(&bad_version),
            Err(LexiconError::UnsupportedVersion { major: 2, minor: 0 })
        );
    }

    #[test]
    fn rejects_truncated_and_checksum_corrupted_files() {
        let bytes = sample_bytes();
        assert!(matches!(
            load_binary_lexicon(&bytes[..16]),
            Err(LexiconError::TruncatedHeader { .. })
        ));

        let mut corrupted = bytes;
        let last = corrupted.len() - 1;
        corrupted[last] ^= 0x01;
        assert!(matches!(
            load_binary_lexicon(&corrupted),
            Err(LexiconError::ChecksumMismatch { .. })
        ));
    }

    #[test]
    fn rejects_section_and_string_bounds_errors() {
        let mut section_bad = sample_bytes();
        section_bad[40..48].copy_from_slice(&u64::MAX.to_le_bytes());
        assert!(matches!(
            load_binary_lexicon(&section_bad),
            Err(LexiconError::SectionOutOfBounds { .. })
        ));

        let mut string_bad = sample_bytes();
        let entry_offset = read_u64(&string_bad, 48) as usize;
        string_bad[entry_offset + 4..entry_offset + 8].copy_from_slice(&u32::MAX.to_le_bytes());
        refresh_checksum(&mut string_bad);
        assert!(matches!(
            load_binary_lexicon(&string_bad),
            Err(LexiconError::StringOutOfBounds { .. })
        ));
    }

    #[test]
    fn rejects_index_out_of_bounds() {
        let mut bytes = sample_bytes();
        let index_offset = read_u64(&bytes, 64) as usize;
        bytes[index_offset + 8..index_offset + 12].copy_from_slice(&99_u32.to_le_bytes());
        refresh_checksum(&mut bytes);
        assert!(matches!(
            load_binary_lexicon(&bytes),
            Err(LexiconError::IndexOutOfBounds { .. })
        ));
    }

    fn sample_bytes() -> Vec<u8> {
        let entries = vec![
            LexiconEntry::new(
                "你好".to_owned(),
                "ni hao".to_owned(),
                vec!["ni".to_owned(), "hao".to_owned()],
                300,
                vec!["test".to_owned()],
            ),
            LexiconEntry::new(
                "好".to_owned(),
                "hao".to_owned(),
                vec!["hao".to_owned()],
                200,
                vec!["test".to_owned()],
            ),
            LexiconEntry::new(
                "你".to_owned(),
                "ni".to_owned(),
                vec!["ni".to_owned()],
                100,
                vec!["test".to_owned()],
            ),
        ];
        build_binary_lexicon(&entries, 7, 1).unwrap()
    }

    fn refresh_checksum(bytes: &mut [u8]) {
        let checksum = crc32_ieee(&bytes[HEADER_LEN..]);
        bytes[84..88].copy_from_slice(&checksum.to_le_bytes());
    }
}
