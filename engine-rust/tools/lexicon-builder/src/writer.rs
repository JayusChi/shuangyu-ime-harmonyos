use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};

use crate::error::BuildError;

pub fn write_atomically(path: &Path, bytes: &[u8]) -> Result<(), BuildError> {
    let temp_path = temp_path_for(path);
    if let Some(parent) = temp_path.parent() {
        fs::create_dir_all(parent).map_err(|source| BuildError::OutputIo {
            path: parent.to_path_buf(),
            source,
        })?;
    }

    let write_result = (|| -> Result<(), BuildError> {
        let mut file = File::create(&temp_path).map_err(|source| BuildError::OutputIo {
            path: temp_path.clone(),
            source,
        })?;
        file.write_all(bytes)
            .map_err(|source| BuildError::OutputIo {
                path: temp_path.clone(),
                source,
            })?;
        file.sync_all().map_err(|source| BuildError::OutputIo {
            path: temp_path.clone(),
            source,
        })?;
        if path.exists() {
            fs::remove_file(path).map_err(|source| BuildError::OutputIo {
                path: path.to_path_buf(),
                source,
            })?;
        }
        fs::rename(&temp_path, path).map_err(|source| BuildError::OutputIo {
            path: path.to_path_buf(),
            source,
        })?;
        Ok(())
    })();

    if write_result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    write_result
}

fn temp_path_for(path: &Path) -> PathBuf {
    let mut temp_name = path
        .file_name()
        .map(|name| name.to_os_string())
        .unwrap_or_else(|| "lexicon".into());
    temp_name.push(".tmp");
    path.with_file_name(temp_name)
}
