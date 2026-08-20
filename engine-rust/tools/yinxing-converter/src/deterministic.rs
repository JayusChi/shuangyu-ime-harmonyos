use std::collections::BTreeSet;
use std::fs;
use std::path::{Component, Path, PathBuf};

use crate::error::{ConverterError, ErrorCode, Result};
use crate::model::OutputFile;
use crate::version::BUNDLE_ID;

pub fn install_output(output: &Path, source_root: &Path, files: &[OutputFile]) -> Result<()> {
    let output = absolute(output)?;
    validate_output_path(&output, source_root)?;
    let parent = output.parent().ok_or_else(|| {
        ConverterError::new(ErrorCode::OutputUnsafe, "output has no parent directory")
    })?;
    fs::create_dir_all(parent).map_err(|error| ConverterError::io(parent, &error))?;
    let name = output
        .file_name()
        .ok_or_else(|| ConverterError::new(ErrorCode::OutputUnsafe, "output has no final name"))?
        .to_string_lossy();
    let staging = parent.join(format!(".{name}.yinxing-staging"));
    if staging.exists() {
        validate_existing_controlled(&staging, true)?;
        fs::remove_dir_all(&staging).map_err(|error| ConverterError::io(&staging, &error))?;
    }
    fs::create_dir(&staging).map_err(|error| ConverterError::io(&staging, &error))?;

    for file in files {
        validate_output_relative(&file.path)?;
        let destination = staging.join(&file.path);
        if let Some(directory) = destination.parent() {
            fs::create_dir_all(directory).map_err(|error| ConverterError::io(directory, &error))?;
        }
        fs::write(&destination, &file.bytes)
            .map_err(|error| ConverterError::io(&destination, &error))?;
    }
    verify_exact(&staging, files)?;

    if output.exists() {
        validate_existing_controlled(&output, false)?;
        fs::remove_dir_all(&output).map_err(|error| ConverterError::io(&output, &error))?;
    }
    fs::rename(&staging, &output).map_err(|error| ConverterError::io(&output, &error))?;
    verify_exact(&output, files)
}

pub fn compare_directories(left: &Path, right: &Path) -> Result<Vec<(String, usize, String)>> {
    let left_files = list_files(left)?;
    let right_files = list_files(right)?;
    if left_files != right_files {
        return Err(ConverterError::new(
            ErrorCode::Integrity,
            "determinism file sets differ",
        ));
    }
    let mut output = Vec::new();
    for relative in left_files {
        let left_bytes = fs::read(left.join(&relative))
            .map_err(|error| ConverterError::io(&left.join(&relative), &error))?;
        let right_bytes = fs::read(right.join(&relative))
            .map_err(|error| ConverterError::io(&right.join(&relative), &error))?;
        if left_bytes != right_bytes {
            return Err(ConverterError::new(
                ErrorCode::Integrity,
                format!(
                    "determinism bytes differ path={}",
                    relative.to_string_lossy()
                ),
            ));
        }
        output.push((
            relative.to_string_lossy().replace('\\', "/"),
            left_bytes.len(),
            crate::sha256::hex(&left_bytes),
        ));
    }
    Ok(output)
}

fn verify_exact(root: &Path, files: &[OutputFile]) -> Result<()> {
    let expected = files
        .iter()
        .map(|file| PathBuf::from(&file.path))
        .collect::<BTreeSet<_>>();
    let actual = list_files(root)?;
    if actual != expected {
        return Err(ConverterError::new(
            ErrorCode::Integrity,
            "output file set differs from generated set",
        ));
    }
    for file in files {
        let path = root.join(&file.path);
        let bytes = fs::read(&path).map_err(|error| ConverterError::io(&path, &error))?;
        if bytes != file.bytes || crate::sha256::hex(&bytes) != file.sha256 {
            return Err(ConverterError::new(
                ErrorCode::Integrity,
                format!("output verification failed path={}", file.path),
            ));
        }
    }
    Ok(())
}

fn list_files(root: &Path) -> Result<BTreeSet<PathBuf>> {
    let mut output = BTreeSet::new();
    let mut pending = vec![root.to_path_buf()];
    while let Some(directory) = pending.pop() {
        let entries =
            fs::read_dir(&directory).map_err(|error| ConverterError::io(&directory, &error))?;
        for entry in entries {
            let entry = entry.map_err(|error| ConverterError::io(&directory, &error))?;
            let file_type = entry
                .file_type()
                .map_err(|error| ConverterError::io(&entry.path(), &error))?;
            if file_type.is_symlink() {
                return Err(ConverterError::new(
                    ErrorCode::OutputUnsafe,
                    "symbolic link found in output",
                ));
            }
            if file_type.is_dir() {
                pending.push(entry.path());
            } else if file_type.is_file() {
                let relative = entry
                    .path()
                    .strip_prefix(root)
                    .map_err(|_| ConverterError::new(ErrorCode::OutputUnsafe, "output escape"))?
                    .to_path_buf();
                output.insert(relative);
            } else {
                return Err(ConverterError::new(
                    ErrorCode::OutputUnsafe,
                    "non-regular output entry",
                ));
            }
        }
    }
    Ok(output)
}

fn validate_existing_controlled(path: &Path, staging: bool) -> Result<()> {
    let metadata = fs::symlink_metadata(path).map_err(|error| ConverterError::io(path, &error))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(ConverterError::new(
            ErrorCode::OutputUnsafe,
            "existing output is not a regular directory",
        ));
    }
    if staging {
        return Ok(());
    }
    let manifest = path.join("manifest.json");
    let bytes = fs::read(&manifest).map_err(|_| {
        ConverterError::new(
            ErrorCode::OutputUnsafe,
            "existing non-empty output is not a controlled production bundle",
        )
    })?;
    let marker = format!("\"bundle_id\": \"{BUNDLE_ID}\"");
    if !String::from_utf8_lossy(&bytes).contains(&marker) {
        return Err(ConverterError::new(
            ErrorCode::OutputUnsafe,
            "existing output bundle identity mismatch",
        ));
    }
    Ok(())
}

fn validate_output_path(output: &Path, source_root: &Path) -> Result<()> {
    let source_root = absolute(source_root)?;
    if output == source_root {
        return Err(ConverterError::new(
            ErrorCode::OutputUnsafe,
            "output cannot equal source root",
        ));
    }
    for forbidden in ["小鹤音形", "码表"] {
        if output.starts_with(source_root.join(forbidden)) {
            return Err(ConverterError::new(
                ErrorCode::OutputUnsafe,
                "output cannot be inside a raw delivery root",
            ));
        }
    }
    Ok(())
}

fn validate_output_relative(value: &str) -> Result<()> {
    let path = Path::new(value);
    if value.is_empty()
        || value.contains('\\')
        || value
            .split('/')
            .any(|part| part.is_empty() || part == "." || part == "..")
        || path.is_absolute()
        || path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err(ConverterError::new(
            ErrorCode::OutputUnsafe,
            "generated output path is unsafe",
        ));
    }
    Ok(())
}

fn absolute(path: &Path) -> Result<PathBuf> {
    if path.is_absolute() {
        Ok(path.to_path_buf())
    } else {
        std::env::current_dir()
            .map(|current| current.join(path))
            .map_err(|error| ConverterError::io(Path::new("."), &error))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_paths_cannot_escape() {
        assert!(validate_output_relative("categories/core.lex").is_ok());
        for path in ["../x", "/x", "C:/x", "a\\b", "a/./b"] {
            assert!(validate_output_relative(path).is_err(), "{path}");
        }
    }
}
