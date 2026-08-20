use std::fs::{self, File, OpenOptions};
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use crate::error::{UserLexiconError, UserLexiconField, UserLexiconReason};
use crate::parser::parse_user_lexicon_file;
use crate::snapshot::UserLexiconSnapshot;

static SAVE_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum UserLexiconLoadAction {
    EmptyMissing,
    LoadedPrimary,
    LoadedBackup,
    RecoveredEmpty,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserLexiconLoadReport {
    pub action: UserLexiconLoadAction,
    pub snapshot: UserLexiconSnapshot,
    pub warning_code: String,
}

#[derive(Clone, Debug, Default)]
pub struct UserLexiconStore {
    path: Option<PathBuf>,
    snapshot: UserLexiconSnapshot,
    last_report: Option<UserLexiconLoadReport>,
}

impl UserLexiconStore {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self {
            path: Some(path.into()),
            ..Self::default()
        }
    }

    pub fn snapshot(&self) -> &UserLexiconSnapshot {
        &self.snapshot
    }

    pub fn last_report(&self) -> Option<&UserLexiconLoadReport> {
        self.last_report.as_ref()
    }

    pub fn load(&mut self) -> Result<&UserLexiconLoadReport, UserLexiconError> {
        let path = self
            .path
            .as_ref()
            .ok_or_else(|| invalid_path(Path::new("")))?;
        let report = load_snapshot_recovering(path)?;
        self.snapshot = report.snapshot.clone();
        self.last_report = Some(report);
        Ok(self.last_report.as_ref().expect("report was just set"))
    }

    /// Reloads only after a complete valid parse. Corruption keeps the current snapshot.
    pub fn reload(&mut self) -> Result<&UserLexiconLoadReport, UserLexiconError> {
        let path = self
            .path
            .as_ref()
            .ok_or_else(|| invalid_path(Path::new("")))?;
        let report = load_snapshot_recovering(path)?;
        if report.action != UserLexiconLoadAction::RecoveredEmpty {
            self.snapshot = report.snapshot.clone();
        }
        self.last_report = Some(report);
        Ok(self.last_report.as_ref().expect("report was just set"))
    }

    pub fn save(&mut self, snapshot: UserLexiconSnapshot) -> Result<(), UserLexiconError> {
        let path = self
            .path
            .as_ref()
            .ok_or_else(|| invalid_path(Path::new("")))?;
        save_snapshot_atomic(path, &snapshot)?;
        self.snapshot = snapshot;
        Ok(())
    }
}

pub fn load_snapshot_recovering(path: &Path) -> Result<UserLexiconLoadReport, UserLexiconError> {
    validate_path(path)?;
    let backup = sibling_path(path, "bak")?;
    if !path.exists() {
        if !backup.exists() {
            return Ok(UserLexiconLoadReport {
                action: UserLexiconLoadAction::EmptyMissing,
                snapshot: UserLexiconSnapshot::empty(),
                warning_code: String::new(),
            });
        }
        return match parse_user_lexicon_file(&backup) {
            Ok(parsed) => Ok(UserLexiconLoadReport {
                action: UserLexiconLoadAction::LoadedBackup,
                snapshot: parsed.into_snapshot(),
                warning_code: "primary_missing".to_owned(),
            }),
            Err(_) => Ok(UserLexiconLoadReport {
                action: UserLexiconLoadAction::RecoveredEmpty,
                snapshot: UserLexiconSnapshot::empty(),
                warning_code: "corrupt".to_owned(),
            }),
        };
    }

    match parse_user_lexicon_file(path) {
        Ok(parsed) => Ok(UserLexiconLoadReport {
            action: UserLexiconLoadAction::LoadedPrimary,
            snapshot: parsed.into_snapshot(),
            warning_code: String::new(),
        }),
        Err(primary_error) => {
            if backup.exists() {
                if let Ok(parsed) = parse_user_lexicon_file(&backup) {
                    return Ok(UserLexiconLoadReport {
                        action: UserLexiconLoadAction::LoadedBackup,
                        snapshot: parsed.into_snapshot(),
                        warning_code: primary_error.code().to_owned(),
                    });
                }
            }
            Ok(UserLexiconLoadReport {
                action: UserLexiconLoadAction::RecoveredEmpty,
                snapshot: UserLexiconSnapshot::empty(),
                warning_code: "corrupt".to_owned(),
            })
        }
    }
}

pub fn save_snapshot_atomic(
    path: &Path,
    snapshot: &UserLexiconSnapshot,
) -> Result<(), UserLexiconError> {
    validate_path(path)?;
    let _guard = SAVE_LOCK
        .get_or_init(|| Mutex::new(()))
        .lock()
        .map_err(|_| storage_error(path, ErrorKind::Other))?;
    save_snapshot_atomic_locked(path, snapshot)
}

/// Atomically saves a complete snapshot only when the current on-disk
/// revision still matches the revision loaded by the caller.
pub fn save_snapshot_atomic_if_revision(
    path: &Path,
    expected_revision: &str,
    snapshot: &UserLexiconSnapshot,
) -> Result<(), UserLexiconError> {
    validate_path(path)?;
    let _guard = SAVE_LOCK
        .get_or_init(|| Mutex::new(()))
        .lock()
        .map_err(|_| storage_error(path, ErrorKind::Other))?;
    let current = load_snapshot_recovering(path)?;
    if expected_revision.is_empty() || current.snapshot.revision() != expected_revision {
        return Err(UserLexiconError::new(
            path,
            0,
            UserLexiconField::Storage,
            UserLexiconReason::RevisionConflict,
        ));
    }
    save_snapshot_atomic_locked(path, snapshot)
}

fn save_snapshot_atomic_locked(
    path: &Path,
    snapshot: &UserLexiconSnapshot,
) -> Result<(), UserLexiconError> {
    let parent = path.parent().ok_or_else(|| invalid_path(path))?;
    fs::create_dir_all(parent).map_err(|error| storage_error(path, error.kind()))?;
    let tmp = sibling_path(path, "tmp")?;
    let backup_tmp = sibling_path(path, "bak.tmp")?;
    let backup = sibling_path(path, "bak")?;
    let old = sibling_path(path, "old")?;
    cleanup_if_exists(&tmp, path)?;
    cleanup_if_exists(&backup_tmp, path)?;
    cleanup_if_exists(&old, path)?;

    let result = (|| {
        write_synced(&tmp, &snapshot.normalized_bytes(), path)?;
        let verified = parse_user_lexicon_file(&tmp)?.into_snapshot();
        if verified.normalized_bytes() != snapshot.normalized_bytes() {
            return Err(UserLexiconError::new(
                path,
                0,
                UserLexiconField::Storage,
                UserLexiconReason::Io("temporary snapshot verification mismatch".to_owned()),
            ));
        }

        if path.exists() {
            fs::copy(path, &backup_tmp).map_err(|error| storage_error(path, error.kind()))?;
            sync_existing(&backup_tmp, path)?;
            replace_with_valid_fallback(&backup_tmp, &backup, None, path)?;

            // Windows cannot rename over an existing file. Moving the primary
            // aside preserves both the backup and a rollback copy until the
            // fully synced temporary file becomes the new primary.
            fs::rename(path, &old).map_err(|error| storage_error(path, error.kind()))?;
            if let Err(error) = fs::rename(&tmp, path) {
                let _ = fs::rename(&old, path);
                return Err(storage_error(path, error.kind()));
            }
            cleanup_if_exists(&old, path)?;
        } else {
            fs::rename(&tmp, path).map_err(|error| storage_error(path, error.kind()))?;
        }

        fs::copy(path, &backup_tmp).map_err(|error| storage_error(path, error.kind()))?;
        sync_existing(&backup_tmp, path)?;
        replace_with_valid_fallback(&backup_tmp, &backup, Some(path), path)?;
        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_file(&tmp);
        let _ = fs::remove_file(&backup_tmp);
        if old.exists() && !path.exists() {
            let _ = fs::rename(&old, path);
        }
    }
    result
}

fn replace_with_valid_fallback(
    source: &Path,
    destination: &Path,
    fallback: Option<&Path>,
    diagnostic_path: &Path,
) -> Result<(), UserLexiconError> {
    if destination.exists() {
        fs::remove_file(destination)
            .map_err(|error| storage_error(diagnostic_path, error.kind()))?;
    }
    if let Err(error) = fs::rename(source, destination) {
        if fallback.is_none_or(|path| !path.exists()) {
            return Err(storage_error(diagnostic_path, error.kind()));
        }
        return Err(storage_error(diagnostic_path, error.kind()));
    }
    Ok(())
}

fn write_synced(path: &Path, bytes: &[u8], diagnostic: &Path) -> Result<(), UserLexiconError> {
    let mut file = File::create(path).map_err(|error| storage_error(diagnostic, error.kind()))?;
    file.write_all(bytes)
        .map_err(|error| storage_error(diagnostic, error.kind()))?;
    file.flush()
        .map_err(|error| storage_error(diagnostic, error.kind()))?;
    file.sync_all()
        .map_err(|error| storage_error(diagnostic, error.kind()))
}

fn sync_existing(path: &Path, diagnostic: &Path) -> Result<(), UserLexiconError> {
    OpenOptions::new()
        .write(true)
        .open(path)
        .and_then(|file| file.sync_all())
        .map_err(|error| storage_error(diagnostic, error.kind()))
}

fn cleanup_if_exists(path: &Path, diagnostic: &Path) -> Result<(), UserLexiconError> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
        Err(error) => Err(storage_error(diagnostic, error.kind())),
    }
}

fn sibling_path(path: &Path, suffix: &str) -> Result<PathBuf, UserLexiconError> {
    let name = path.file_name().ok_or_else(|| invalid_path(path))?;
    let mut sibling = name.to_os_string();
    sibling.push(".");
    sibling.push(suffix);
    Ok(path
        .parent()
        .ok_or_else(|| invalid_path(path))?
        .join(sibling))
}

fn validate_path(path: &Path) -> Result<(), UserLexiconError> {
    if path.as_os_str().is_empty() || path.file_name().is_none() || path.parent().is_none() {
        return Err(invalid_path(path));
    }
    Ok(())
}

fn invalid_path(path: &Path) -> UserLexiconError {
    UserLexiconError::new(
        path,
        0,
        UserLexiconField::Storage,
        UserLexiconReason::InvalidPath,
    )
}

fn storage_error(path: &Path, kind: ErrorKind) -> UserLexiconError {
    UserLexiconError::new(
        path,
        0,
        UserLexiconField::Storage,
        UserLexiconReason::Io(kind.to_string()),
    )
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::thread;

    use crate::parse_user_lexicon_bytes;

    use super::*;

    static COUNTER: AtomicUsize = AtomicUsize::new(0);

    fn path(name: &str) -> PathBuf {
        let id = COUNTER.fetch_add(1, Ordering::Relaxed);
        let directory = std::env::current_dir()
            .unwrap()
            .join("target")
            .join("user-lexicon-tests");
        fs::create_dir_all(&directory).unwrap();
        directory.join(format!(
            "user-lexicon-{name}-{}-{id}.txt",
            std::process::id()
        ))
    }

    fn snapshot(text: &str) -> UserLexiconSnapshot {
        parse_user_lexicon_bytes("fixture.txt", text.as_bytes())
            .unwrap()
            .into_snapshot()
    }

    #[test]
    fn first_save_overwrite_and_identical_save_are_deterministic() {
        let path = path("save");
        let first = snapshot("甲词\tabc\n");
        save_snapshot_atomic(&path, &first).unwrap();
        assert_eq!(fs::read(&path).unwrap(), first.normalized_bytes());
        let bytes = fs::read(&path).unwrap();
        save_snapshot_atomic(&path, &first).unwrap();
        assert_eq!(fs::read(&path).unwrap(), bytes);
        let second = snapshot("乙词\tabc#固\n");
        save_snapshot_atomic(&path, &second).unwrap();
        assert_eq!(fs::read(&path).unwrap(), second.normalized_bytes());
    }

    #[test]
    fn missing_corrupt_and_backup_recovery_are_explicit() {
        let path = path("recover");
        assert_eq!(
            load_snapshot_recovering(&path).unwrap().action,
            UserLexiconLoadAction::EmptyMissing
        );
        let valid = snapshot("甲词\tabc\n");
        save_snapshot_atomic(&path, &valid).unwrap();
        fs::write(&path, b"broken").unwrap();
        let recovered = load_snapshot_recovering(&path).unwrap();
        assert_eq!(recovered.action, UserLexiconLoadAction::LoadedBackup);
        assert_eq!(recovered.snapshot, valid);
        fs::write(
            path.with_file_name(format!(
                "{}.bak",
                path.file_name().unwrap().to_string_lossy()
            )),
            b"broken",
        )
        .unwrap();
        assert_eq!(
            load_snapshot_recovering(&path).unwrap().action,
            UserLexiconLoadAction::RecoveredEmpty
        );
    }

    #[test]
    fn failed_reload_keeps_last_valid_snapshot() {
        let path = path("reload");
        let valid = snapshot("甲词\tabc\n");
        save_snapshot_atomic(&path, &valid).unwrap();
        let mut store = UserLexiconStore::new(&path);
        store.load().unwrap();
        fs::write(&path, b"broken").unwrap();
        let backup = path.with_file_name(format!(
            "{}.bak",
            path.file_name().unwrap().to_string_lossy()
        ));
        fs::write(backup, b"broken").unwrap();
        store.reload().unwrap();
        assert_eq!(store.snapshot(), &valid);
    }

    #[test]
    fn concurrent_saves_leave_a_complete_parseable_file() {
        let path = Arc::new(path("concurrent"));
        let mut joins = Vec::new();
        for text in ["甲词\tabc\n", "乙词\tabc#2\n"] {
            let path = Arc::clone(&path);
            let snapshot = snapshot(text);
            joins.push(thread::spawn(move || {
                save_snapshot_atomic(&path, &snapshot)
            }));
        }
        for join in joins {
            join.join().unwrap().unwrap();
        }
        parse_user_lexicon_file(&path).unwrap();
    }

    #[test]
    fn compare_and_swap_rejects_stale_revision_without_changing_primary() {
        let path = path("revision-conflict");
        let first = snapshot("甲词\tabc\n");
        save_snapshot_atomic(&path, &first).unwrap();
        let stale_revision = load_snapshot_recovering(&path).unwrap().snapshot.revision();

        let second = snapshot("乙词\tdef#固\n");
        save_snapshot_atomic_if_revision(&path, &stale_revision, &second).unwrap();

        let third = snapshot("丙词\tghi#2\n");
        let error = save_snapshot_atomic_if_revision(&path, &stale_revision, &third).unwrap_err();
        assert_eq!(error.code(), "revision_conflict");
        assert_eq!(
            load_snapshot_recovering(&path)
                .unwrap()
                .snapshot
                .normalized_bytes(),
            second.normalized_bytes()
        );
    }
}
