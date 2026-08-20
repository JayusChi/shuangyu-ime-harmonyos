use std::collections::BTreeMap;
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use crate::error::UserModelError;
use crate::key::{key_from_parts, CandidateSourceKind, UserCandidateKey};
use crate::limits::{UserModelConfig, DATA_VERSION, FILE_MAGIC, FORMAT_VERSION};
use crate::migration::ensure_supported_format;
use crate::record::UserRecord;

const HEADER_LEN: usize = 24;
#[cfg(test)]
const CHECKSUM_OFFSET: usize = 20;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ModelSnapshot {
    pub sequence: u64,
    pub records: BTreeMap<UserCandidateKey, UserRecord>,
}

impl ModelSnapshot {
    pub(crate) fn empty() -> Self {
        Self {
            sequence: 0,
            records: BTreeMap::new(),
        }
    }
}

pub(crate) fn read_snapshot(
    path: &Path,
    config: &UserModelConfig,
) -> Result<ModelSnapshot, UserModelError> {
    let metadata = fs::metadata(path)?;
    if metadata.len() > config.max_file_size {
        return Err(UserModelError::FileTooLarge {
            actual: metadata.len(),
            max: config.max_file_size,
        });
    }
    let mut file = File::open(path)?;
    let mut bytes = Vec::with_capacity(metadata.len() as usize);
    file.read_to_end(&mut bytes)?;
    decode_snapshot(&bytes, config)
}

pub(crate) fn write_snapshot_atomic(
    path: &Path,
    snapshot: &ModelSnapshot,
    config: &UserModelConfig,
) -> Result<(), UserModelError> {
    let bytes = encode_snapshot(snapshot)?;
    if bytes.len() as u64 > config.max_file_size {
        return Err(UserModelError::FileTooLarge {
            actual: bytes.len() as u64,
            max: config.max_file_size,
        });
    }

    let parent = path.parent().ok_or(UserModelError::InvalidPath)?;
    if parent.as_os_str().is_empty() {
        return Err(UserModelError::InvalidPath);
    }
    fs::create_dir_all(parent)?;
    let tmp = sibling_path(path, "tmp")?;
    let bak = sibling_path(path, "bak")?;

    {
        let mut file = File::create(&tmp)?;
        file.write_all(&bytes)?;
        file.flush()?;
        file.sync_all()?;
    }
    let _verified = read_snapshot(&tmp, config)?;

    if path.exists() {
        fs::copy(path, &bak)?;
        fs::remove_file(path)?;
    }
    fs::rename(&tmp, path)?;
    fs::copy(path, &bak)?;
    Ok(())
}

pub(crate) fn remove_model_files(path: &Path) -> Result<(), UserModelError> {
    for target in [
        path.to_path_buf(),
        sibling_path(path, "tmp")?,
        sibling_path(path, "bak")?,
    ] {
        match fs::remove_file(&target) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(())
}

pub(crate) fn sibling_path(path: &Path, extension: &str) -> Result<PathBuf, UserModelError> {
    let stem = path.file_stem().ok_or(UserModelError::InvalidPath)?;
    let parent = path.parent().ok_or(UserModelError::InvalidPath)?;
    let mut file_name = stem.to_os_string();
    file_name.push(".");
    file_name.push(extension);
    Ok(parent.join(file_name))
}

pub(crate) fn encode_snapshot(snapshot: &ModelSnapshot) -> Result<Vec<u8>, UserModelError> {
    if snapshot.records.len() > u32::MAX as usize {
        return Err(UserModelError::TooManyRecords {
            actual: u32::MAX,
            max: u32::MAX as usize,
        });
    }
    let mut body = Vec::new();
    write_u64(&mut body, snapshot.sequence);
    for (key, record) in &snapshot.records {
        write_u64(&mut body, key.candidate_hash);
        body.push(key.source_kind.as_u8());
        write_scheme(&mut body, &key.scheme_id)?;
        write_u32(&mut body, key.lexicon_version);
        write_u32(&mut body, record.selection_count);
        write_u16(&mut body, record.first_record_version);
        write_u64(&mut body, record.last_selected_seq);
        write_u64(&mut body, record.updated_seq);
    }

    let mut bytes = Vec::with_capacity(HEADER_LEN + body.len());
    bytes.extend_from_slice(FILE_MAGIC);
    write_u16(&mut bytes, FORMAT_VERSION);
    write_u16(&mut bytes, DATA_VERSION);
    write_u32(&mut bytes, snapshot.records.len() as u32);
    write_u64(&mut bytes, body.len() as u64);
    write_u32(&mut bytes, checksum32(&body));
    bytes.extend_from_slice(&body);
    Ok(bytes)
}

pub(crate) fn decode_snapshot(
    bytes: &[u8],
    config: &UserModelConfig,
) -> Result<ModelSnapshot, UserModelError> {
    if bytes.len() < HEADER_LEN {
        return Err(UserModelError::Corrupt("truncated header"));
    }
    if &bytes[0..4] != FILE_MAGIC {
        return Err(UserModelError::Corrupt("bad magic"));
    }
    let mut index = 4;
    let format_version = read_u16(bytes, &mut index)?;
    ensure_supported_format(format_version)?;
    let _data_version = read_u16(bytes, &mut index)?;
    let record_count = read_u32(bytes, &mut index)?;
    if record_count as usize > config.max_records.saturating_mul(4) {
        return Err(UserModelError::TooManyRecords {
            actual: record_count,
            max: config.max_records,
        });
    }
    let data_len = read_u64(bytes, &mut index)? as usize;
    let expected_checksum = read_u32(bytes, &mut index)?;
    if index != HEADER_LEN {
        return Err(UserModelError::Corrupt("header length mismatch"));
    }
    if bytes.len().saturating_sub(HEADER_LEN) != data_len {
        return Err(UserModelError::Corrupt("data length mismatch"));
    }
    let body = &bytes[HEADER_LEN..];
    if checksum32(body) != expected_checksum {
        return Err(UserModelError::Corrupt("checksum mismatch"));
    }

    let mut body_index = 0;
    let sequence = read_u64(body, &mut body_index)?;
    let mut records = BTreeMap::new();
    for _ in 0..record_count {
        let candidate_hash = read_u64(body, &mut body_index)?;
        let source_kind = CandidateSourceKind::from_u8(read_u8(body, &mut body_index)?)
            .ok_or(UserModelError::Corrupt("invalid source kind"))?;
        let scheme_id = read_scheme(body, &mut body_index, config.max_scheme_id_len)?;
        let lexicon_version = read_u32(body, &mut body_index)?;
        let selection_count = read_u32(body, &mut body_index)?;
        let first_record_version = read_u16(body, &mut body_index)?;
        let last_selected_seq = read_u64(body, &mut body_index)?;
        let updated_seq = read_u64(body, &mut body_index)?;
        if selection_count > crate::limits::MAX_SELECTION_COUNT {
            return Err(UserModelError::Corrupt("selection count overflow"));
        }
        if last_selected_seq > sequence || updated_seq > sequence {
            return Err(UserModelError::Corrupt("invalid logical sequence"));
        }
        let key = key_from_parts(scheme_id, lexicon_version, source_kind, candidate_hash)?;
        let record = UserRecord {
            selection_count,
            last_selected_seq,
            first_record_version,
            updated_seq,
        };
        records
            .entry(key)
            .and_modify(|existing: &mut UserRecord| existing.merge(&record))
            .or_insert(record);
    }
    if body_index != body.len() {
        return Err(UserModelError::Corrupt("trailing bytes"));
    }
    Ok(ModelSnapshot { sequence, records })
}

#[cfg(test)]
pub(crate) fn patch_format_version_for_test(bytes: &mut [u8], version: u16) {
    if bytes.len() >= 6 {
        let version_bytes = version.to_le_bytes();
        bytes[4] = version_bytes[0];
        bytes[5] = version_bytes[1];
        let body = &bytes[HEADER_LEN..];
        let checksum = checksum32(body).to_le_bytes();
        bytes[CHECKSUM_OFFSET..CHECKSUM_OFFSET + 4].copy_from_slice(&checksum);
    }
}

fn write_scheme(out: &mut Vec<u8>, value: &str) -> Result<(), UserModelError> {
    if value.is_empty() || value.len() > u8::MAX as usize {
        return Err(UserModelError::InvalidPath);
    }
    out.push(value.len() as u8);
    out.extend_from_slice(value.as_bytes());
    Ok(())
}

fn read_scheme(bytes: &[u8], index: &mut usize, max_len: usize) -> Result<String, UserModelError> {
    let len = read_u8(bytes, index)? as usize;
    if len == 0 || len > max_len || index.saturating_add(len) > bytes.len() {
        return Err(UserModelError::Corrupt("invalid scheme length"));
    }
    let raw = &bytes[*index..*index + len];
    *index += len;
    let value = std::str::from_utf8(raw).map_err(|_| UserModelError::Corrupt("scheme utf8"))?;
    if !value
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-')
    {
        return Err(UserModelError::Corrupt("invalid scheme id"));
    }
    Ok(value.to_owned())
}

fn read_u8(bytes: &[u8], index: &mut usize) -> Result<u8, UserModelError> {
    let value = *bytes
        .get(*index)
        .ok_or(UserModelError::Corrupt("truncated u8"))?;
    *index += 1;
    Ok(value)
}

fn read_u16(bytes: &[u8], index: &mut usize) -> Result<u16, UserModelError> {
    let end = index.saturating_add(2);
    let slice = bytes
        .get(*index..end)
        .ok_or(UserModelError::Corrupt("truncated u16"))?;
    *index = end;
    Ok(u16::from_le_bytes([slice[0], slice[1]]))
}

fn read_u32(bytes: &[u8], index: &mut usize) -> Result<u32, UserModelError> {
    let end = index.saturating_add(4);
    let slice = bytes
        .get(*index..end)
        .ok_or(UserModelError::Corrupt("truncated u32"))?;
    *index = end;
    Ok(u32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]]))
}

fn read_u64(bytes: &[u8], index: &mut usize) -> Result<u64, UserModelError> {
    let end = index.saturating_add(8);
    let slice = bytes
        .get(*index..end)
        .ok_or(UserModelError::Corrupt("truncated u64"))?;
    *index = end;
    Ok(u64::from_le_bytes([
        slice[0], slice[1], slice[2], slice[3], slice[4], slice[5], slice[6], slice[7],
    ]))
}

fn write_u16(out: &mut Vec<u8>, value: u16) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn write_u32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn write_u64(out: &mut Vec<u8>, value: u64) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn checksum32(bytes: &[u8]) -> u32 {
    let mut hash = 0x811c_9dc5_u32;
    for byte in bytes {
        hash ^= u32::from(*byte);
        hash = hash.wrapping_mul(0x0100_0193);
    }
    hash
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{CandidateSourceKind, UserCandidateKey};

    #[test]
    fn duplicate_records_are_merged_on_load() {
        let key =
            UserCandidateKey::from_stable_id("xiaohe", 8, CandidateSourceKind::SystemLexicon, "b")
                .expect("key");
        let mut records = BTreeMap::new();
        records.insert(
            key,
            UserRecord {
                selection_count: 2,
                last_selected_seq: 2,
                first_record_version: 1,
                updated_seq: 2,
            },
        );
        let snapshot = ModelSnapshot {
            sequence: 2,
            records,
        };
        let bytes = encode_snapshot(&snapshot).expect("encode");
        let decoded = decode_snapshot(&bytes, &UserModelConfig::default()).expect("decode");

        assert_eq!(decoded.records.len(), 1);
    }
}
