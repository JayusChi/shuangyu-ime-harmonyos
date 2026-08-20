use std::fs;
use std::path::Path;

use crate::error::UserModelError;
use crate::limits::UserModelConfig;
use crate::persistence::{
    read_snapshot, remove_model_files, sibling_path, write_snapshot_atomic, ModelSnapshot,
};

/// Recovery action taken during load.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LoadAction {
    EmptyMissing,
    LoadedPrimary,
    LoadedBackup,
    RecoveredEmpty,
}

/// Result of loading a user model with recovery.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LoadReport {
    pub action: LoadAction,
    pub(crate) snapshot: ModelSnapshot,
    pub last_error_code: String,
}

pub(crate) fn load_recovering(
    path: &Path,
    config: &UserModelConfig,
) -> Result<LoadReport, UserModelError> {
    let tmp = sibling_path(path, "tmp")?;
    let _ = fs::remove_file(tmp);

    if !path.exists() {
        return Ok(LoadReport {
            action: LoadAction::EmptyMissing,
            snapshot: ModelSnapshot::empty(),
            last_error_code: String::new(),
        });
    }

    match read_snapshot(path, config) {
        Ok(snapshot) => Ok(LoadReport {
            action: LoadAction::LoadedPrimary,
            snapshot,
            last_error_code: String::new(),
        }),
        Err(primary_error) => {
            let bak = sibling_path(path, "bak")?;
            if bak.exists() {
                if let Ok(snapshot) = read_snapshot(&bak, config) {
                    write_snapshot_atomic(path, &snapshot, config)?;
                    return Ok(LoadReport {
                        action: LoadAction::LoadedBackup,
                        snapshot,
                        last_error_code: primary_error.code().to_owned(),
                    });
                }
            }
            quarantine_corrupt_file(path)?;
            Ok(LoadReport {
                action: LoadAction::RecoveredEmpty,
                snapshot: ModelSnapshot::empty(),
                last_error_code: primary_error.code().to_owned(),
            })
        }
    }
}

pub(crate) fn clear_persisted(path: &Path) -> Result<(), UserModelError> {
    remove_model_files(path)
}

fn quarantine_corrupt_file(path: &Path) -> Result<(), UserModelError> {
    if !path.exists() {
        return Ok(());
    }
    let corrupt = sibling_path(path, "corrupt")?;
    if corrupt.exists() {
        let _ = fs::remove_file(&corrupt);
    }
    fs::rename(path, corrupt)?;
    Ok(())
}
