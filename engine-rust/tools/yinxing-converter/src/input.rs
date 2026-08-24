use std::fs;
use std::path::{Component, Path, PathBuf};

use crate::error::{ConverterError, ErrorCode, Result};
use crate::model::{CategorySpec, ValidatedContract};
use crate::sha256;
use crate::version::MAX_INPUT_BYTES;

#[derive(Clone, Debug)]
pub struct SourceInput {
    pub spec: CategorySpec,
    pub bytes: Vec<u8>,
}

pub fn preflight_all(source_root: &Path, contract: &ValidatedContract) -> Result<Vec<SourceInput>> {
    let root_metadata =
        fs::symlink_metadata(source_root).map_err(|error| missing_or_io(source_root, &error))?;
    if root_metadata.file_type().is_symlink() {
        return Err(ConverterError::new(
            ErrorCode::SymlinkRejected,
            "source root is a symbolic link",
        ));
    }
    if !root_metadata.is_dir() {
        return Err(ConverterError::new(
            ErrorCode::PathInvalid,
            "source root is not a directory",
        ));
    }
    let canonical_root = source_root
        .canonicalize()
        .map_err(|error| ConverterError::io(source_root, &error))?;

    let mut resolved = Vec::with_capacity(contract.categories.len());
    for spec in &contract.categories {
        validate_relative_path(&spec.source_path)?;
        let path = resolve_without_symlinks(&canonical_root, &spec.source_path)?;
        let metadata = fs::metadata(&path).map_err(|error| missing_or_io(&path, &error))?;
        if !metadata.is_file() {
            return Err(ConverterError::new(
                ErrorCode::SourceMissing,
                format!("source_file_id={} not_regular_file", spec.source_file_id),
            ));
        }
        if metadata.len() != spec.source_size {
            return Err(ConverterError::new(
                ErrorCode::SourceSizeMismatch,
                format!(
                    "source_file_id={} expected={} actual={}",
                    spec.source_file_id,
                    spec.source_size,
                    metadata.len()
                ),
            ));
        }
        if metadata.len() as usize > MAX_INPUT_BYTES {
            return Err(ConverterError::new(
                ErrorCode::SourceSizeMismatch,
                format!("source_file_id={} exceeds input limit", spec.source_file_id),
            ));
        }
        resolved.push((spec.clone(), path));
    }

    // Every path and size is validated before any source body is loaded.
    let mut inputs = Vec::with_capacity(resolved.len());
    for (spec, path) in resolved {
        let bytes = fs::read(&path).map_err(|error| ConverterError::io(&path, &error))?;
        let actual_hash = sha256::hex(&bytes);
        if actual_hash != spec.source_sha256 {
            return Err(ConverterError::new(
                ErrorCode::SourceHashMismatch,
                format!(
                    "source_file_id={} expected={} actual={}",
                    spec.source_file_id, spec.source_sha256, actual_hash
                ),
            ));
        }
        inputs.push(SourceInput { spec, bytes });
    }
    // Parsing starts only after every one of the twelve byte hashes has passed.
    Ok(inputs)
}

pub fn validate_relative_path(value: &str) -> Result<()> {
    if value.is_empty()
        || value.contains('\\')
        || value
            .split('/')
            .any(|part| part.is_empty() || part == "." || part == "..")
    {
        return Err(ConverterError::new(
            ErrorCode::PathInvalid,
            "source path must be a non-empty forward-slash relative path",
        ));
    }
    let path = Path::new(value);
    if path.is_absolute()
        || path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err(ConverterError::new(
            ErrorCode::PathInvalid,
            format!(
                "unsafe relative source path digest={}",
                sha256::hex(value.as_bytes())
            ),
        ));
    }
    Ok(())
}

fn resolve_without_symlinks(root: &Path, relative: &str) -> Result<PathBuf> {
    let mut current = root.to_path_buf();
    for component in Path::new(relative).components() {
        let Component::Normal(part) = component else {
            return Err(ConverterError::new(
                ErrorCode::PathInvalid,
                "source path contains a non-normal component",
            ));
        };
        current.push(part);
        let metadata =
            fs::symlink_metadata(&current).map_err(|error| missing_or_io(&current, &error))?;
        if metadata.file_type().is_symlink() {
            return Err(ConverterError::new(
                ErrorCode::SymlinkRejected,
                format!(
                    "symbolic link rejected component={}",
                    part.to_string_lossy()
                ),
            ));
        }
    }
    let canonical = current
        .canonicalize()
        .map_err(|error| missing_or_io(&current, &error))?;
    if !canonical.starts_with(root) {
        return Err(ConverterError::new(
            ErrorCode::PathInvalid,
            "resolved source escapes source root",
        ));
    }
    Ok(canonical)
}

fn missing_or_io(path: &Path, error: &std::io::Error) -> ConverterError {
    if error.kind() == std::io::ErrorKind::NotFound {
        ConverterError::new(
            ErrorCode::SourceMissing,
            format!(
                "path_component={}",
                path.file_name()
                    .map(|value| value.to_string_lossy())
                    .unwrap_or_default()
            ),
        )
    } else {
        ConverterError::io(path, error)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_only_normal_relative_forward_slash_paths() {
        assert!(validate_relative_path("小鹤音形/0.0.小鹤.txt").is_ok());
        for path in [
            "",
            "../escape.txt",
            "/absolute.txt",
            "C:/absolute.txt",
            "a\\b.txt",
            "a/./b",
        ] {
            assert!(validate_relative_path(path).is_err(), "{path}");
        }
    }
}
