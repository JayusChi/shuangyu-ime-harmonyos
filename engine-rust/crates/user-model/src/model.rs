use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use crate::error::UserModelError;
use crate::key::UserCandidateKey;
use crate::limits::{UserModelConfig, DATA_VERSION, FORMAT_VERSION};
use crate::persistence::{write_snapshot_atomic, ModelSnapshot};
use crate::record::UserRecord;
use crate::recovery::{clear_persisted, load_recovering, LoadReport};
use crate::scoring::score_record;

/// In-memory user learning model with delayed persistence state.
#[derive(Clone, Debug)]
pub struct UserModel {
    records: BTreeMap<UserCandidateKey, UserRecord>,
    sequence: u64,
    path: Option<PathBuf>,
    config: UserModelConfig,
    loaded: bool,
    dirty: bool,
    unsaved_events: u32,
    user_learning_enabled: bool,
    session_learning_allowed: bool,
    last_error_code: String,
}

impl Default for UserModel {
    fn default() -> Self {
        Self::new(UserModelConfig::default())
    }
}

impl UserModel {
    /// Creates an empty model with explicit limits.
    pub fn new(config: UserModelConfig) -> Self {
        Self {
            records: BTreeMap::new(),
            sequence: 0,
            path: None,
            config,
            loaded: false,
            dirty: false,
            unsaved_events: 0,
            user_learning_enabled: true,
            session_learning_allowed: true,
            last_error_code: String::new(),
        }
    }

    /// Sets the user model snapshot path without reading or writing it.
    pub fn set_path(&mut self, path: impl AsRef<Path>) -> Result<UserModelStatus, UserModelError> {
        let path = path.as_ref();
        validate_path(path, &self.config)?;
        self.path = Some(path.to_path_buf());
        Ok(self.status())
    }

    /// Loads the snapshot from the configured path with corruption recovery.
    pub fn load(&mut self) -> Result<LoadReport, UserModelError> {
        let path = self.path.as_ref().ok_or(UserModelError::InvalidPath)?;
        let report = load_recovering(path, &self.config)?;
        self.records = report.snapshot.records.clone();
        self.sequence = report.snapshot.sequence;
        self.loaded = true;
        self.dirty = false;
        self.unsaved_events = 0;
        self.last_error_code = report.last_error_code.clone();
        Ok(report)
    }

    /// Persists pending changes if the delayed flush threshold is reached.
    pub fn flush_if_needed(&mut self) -> Result<Option<UserModelStatus>, UserModelError> {
        if self.dirty && self.unsaved_events >= self.config.max_unsaved_events {
            self.flush().map(Some)
        } else {
            Ok(None)
        }
    }

    /// Explicitly persists the model if it is dirty.
    pub fn flush(&mut self) -> Result<UserModelStatus, UserModelError> {
        if !self.dirty {
            return Ok(self.status());
        }
        let path = self.path.clone().ok_or(UserModelError::InvalidPath)?;
        self.compact();
        let snapshot = self.snapshot();
        write_snapshot_atomic(&path, &snapshot, &self.config)?;
        self.dirty = false;
        self.unsaved_events = 0;
        self.last_error_code.clear();
        Ok(self.status())
    }

    /// Clears memory and persisted files. Repeated clear is accepted.
    pub fn clear(&mut self) -> Result<UserModelStatus, UserModelError> {
        self.records.clear();
        self.sequence = 0;
        self.dirty = false;
        self.unsaved_events = 0;
        if let Some(path) = &self.path {
            clear_persisted(path)?;
        }
        self.last_error_code.clear();
        Ok(self.status())
    }

    /// Records a successful candidate selection if learning policy allows it.
    pub fn record_selection(&mut self, key: UserCandidateKey) -> bool {
        if !self.should_learn() {
            return false;
        }
        self.sequence = self.sequence.saturating_add(1);
        match self.records.get_mut(&key) {
            Some(record) => record.record_selection(self.sequence),
            None => {
                self.records.insert(key, UserRecord::new(self.sequence));
            }
        }
        self.dirty = true;
        self.unsaved_events = self.unsaved_events.saturating_add(1);
        if self.records.len() > self.config.max_records.saturating_mul(2) {
            self.compact();
        }
        true
    }

    /// Returns the bounded user score for a key under the active ranking policy.
    pub fn score(&self, key: &UserCandidateKey) -> i64 {
        if !self.should_apply_user_ranking() {
            return 0;
        }
        self.records
            .get(key)
            .map(|record| score_record(record, self.sequence))
            .unwrap_or(0)
    }

    /// Number of records currently in memory.
    pub fn record_count(&self) -> usize {
        self.records.len()
    }

    /// Returns whether the model has unsaved changes.
    pub fn dirty(&self) -> bool {
        self.dirty
    }

    /// Returns the current logical sequence.
    pub fn sequence(&self) -> u64 {
        self.sequence
    }

    /// Updates the global user learning policy.
    pub fn set_user_learning_enabled(&mut self, enabled: bool) -> UserModelStatus {
        self.user_learning_enabled = enabled;
        self.status()
    }

    /// Updates the current session privacy learning policy.
    pub fn set_session_learning_allowed(&mut self, allowed: bool) -> UserModelStatus {
        self.session_learning_allowed = allowed;
        self.status()
    }

    /// Returns a status object safe to expose to ArkTS.
    pub fn status(&self) -> UserModelStatus {
        UserModelStatus {
            loaded: self.loaded,
            enabled: self.user_learning_enabled,
            session_learning_allowed: self.session_learning_allowed,
            dirty: self.dirty,
            record_count: self.records.len(),
            format_version: FORMAT_VERSION,
            data_version: DATA_VERSION,
            last_error_code: self.last_error_code.clone(),
        }
    }

    fn should_learn(&self) -> bool {
        self.user_learning_enabled && self.session_learning_allowed
    }

    fn should_apply_user_ranking(&self) -> bool {
        self.user_learning_enabled && self.session_learning_allowed
    }

    fn snapshot(&self) -> ModelSnapshot {
        ModelSnapshot {
            sequence: self.sequence,
            records: self.records.clone(),
        }
    }

    fn compact(&mut self) {
        if self.records.len() <= self.config.max_records {
            return;
        }
        let sequence = self.sequence;
        let mut ranked = self
            .records
            .iter()
            .map(|(key, record)| {
                (
                    key.clone(),
                    record.clone(),
                    score_record(record, sequence),
                    record.last_selected_seq,
                )
            })
            .collect::<Vec<_>>();
        ranked.sort_by(|left, right| {
            right
                .2
                .cmp(&left.2)
                .then_with(|| right.3.cmp(&left.3))
                .then_with(|| left.0.cmp(&right.0))
        });
        ranked.truncate(self.config.max_records);
        self.records = ranked
            .into_iter()
            .map(|(key, record, _, _)| (key, record))
            .collect();
    }
}

/// User model state safe to expose across the native bridge.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserModelStatus {
    pub loaded: bool,
    pub enabled: bool,
    pub session_learning_allowed: bool,
    pub dirty: bool,
    pub record_count: usize,
    pub format_version: u16,
    pub data_version: u16,
    pub last_error_code: String,
}

impl UserModelStatus {
    /// Serializes status without exposing user records.
    pub fn to_json(&self) -> String {
        format!(
            "{{\"loaded\":{},\"enabled\":{},\"sessionLearningAllowed\":{},\"dirty\":{},\"recordCount\":{},\"formatVersion\":{},\"dataVersion\":{},\"lastErrorCode\":\"{}\"}}",
            bool_json(self.loaded),
            bool_json(self.enabled),
            bool_json(self.session_learning_allowed),
            bool_json(self.dirty),
            self.record_count,
            self.format_version,
            self.data_version,
            escape_json(&self.last_error_code),
        )
    }
}

fn validate_path(path: &Path, config: &UserModelConfig) -> Result<(), UserModelError> {
    let value = path.to_string_lossy();
    if value.trim().is_empty() {
        return Err(UserModelError::InvalidPath);
    }
    if value.len() > config.max_path_len {
        return Err(UserModelError::PathTooLong);
    }
    if path.file_name().is_none() {
        return Err(UserModelError::InvalidPath);
    }
    Ok(())
}

fn bool_json(value: bool) -> &'static str {
    if value {
        "true"
    } else {
        "false"
    }
}

fn escape_json(value: &str) -> String {
    let mut escaped = String::new();
    for ch in value.chars() {
        match ch {
            '\\' => escaped.push_str("\\\\"),
            '"' => escaped.push_str("\\\""),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            c if c.is_control() => escaped.push_str(&format!("\\u{:04x}", c as u32)),
            c => escaped.push(c),
        }
    }
    escaped
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use crate::persistence::{encode_snapshot, patch_format_version_for_test};
    use crate::{
        CandidateSourceKind, LoadAction, UserCandidateKey, MAX_SELECTION_COUNT, MAX_USER_WEIGHT,
    };

    use super::*;

    static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

    fn test_path(name: &str) -> PathBuf {
        let index = TEST_COUNTER.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!("harmony-stage9-{name}-{index}.dat"))
    }

    fn key(id: &str) -> UserCandidateKey {
        UserCandidateKey::from_stable_id("xiaohe", 8, CandidateSourceKind::SystemLexicon, id)
            .expect("key")
    }

    #[test]
    fn empty_model_loads_when_file_is_missing() {
        let path = test_path("missing");
        let mut model = UserModel::default();
        model.set_path(&path).expect("path");
        let report = model.load().expect("load");

        assert_eq!(report.action, LoadAction::EmptyMissing);
        assert_eq!(model.record_count(), 0);
        assert!(model.status().loaded);
    }

    #[test]
    fn repeated_selection_updates_count_and_recency() {
        let mut model = UserModel::default();
        assert!(model.record_selection(key("b")));
        assert!(model.record_selection(key("b")));

        assert_eq!(model.record_count(), 1);
        assert_eq!(model.sequence(), 2);
        assert!(model.dirty());
    }

    #[test]
    fn disabled_learning_does_not_update() {
        let mut model = UserModel::default();
        model.set_user_learning_enabled(false);

        assert!(!model.record_selection(key("b")));
        assert_eq!(model.record_count(), 0);
        assert!(!model.dirty());
    }

    #[test]
    fn session_disabled_learning_does_not_update() {
        let mut model = UserModel::default();
        model.set_session_learning_allowed(false);

        assert!(!model.record_selection(key("b")));
        assert_eq!(model.record_count(), 0);
    }

    #[test]
    fn score_is_bounded_and_disabled_policy_returns_zero() {
        let key = key("b");
        let mut model = UserModel::default();
        for _ in 0..2_000 {
            model.record_selection(key.clone());
        }

        assert_eq!(model.score(&key), MAX_USER_WEIGHT);
        model.set_user_learning_enabled(false);
        assert_eq!(model.score(&key), 0);
    }

    #[test]
    fn count_saturates_without_overflow() {
        let key = key("b");
        let mut model = UserModel::default();
        for _ in 0..2_000 {
            model.record_selection(key.clone());
        }
        let record = model.records.get(&key).expect("record");

        assert_eq!(record.selection_count, MAX_SELECTION_COUNT);
    }

    #[test]
    fn save_and_reload_preserves_statistics() {
        let path = test_path("reload");
        let key = key("b");
        let mut model = UserModel::default();
        model.set_path(&path).expect("path");
        model.record_selection(key.clone());
        model.flush().expect("flush");

        let mut reloaded = UserModel::default();
        reloaded.set_path(&path).expect("path");
        reloaded.load().expect("load");

        assert!(reloaded.score(&key) > 0);
        let _ = fs::remove_file(path);
    }

    #[test]
    fn delayed_flush_waits_until_threshold() {
        let path = test_path("delay");
        let mut model = UserModel::new(UserModelConfig {
            max_unsaved_events: 2,
            ..UserModelConfig::default()
        });
        model.set_path(&path).expect("path");
        model.record_selection(key("a"));

        assert!(model.flush_if_needed().expect("flush").is_none());
        model.record_selection(key("b"));
        assert!(model.flush_if_needed().expect("flush").is_some());
        assert!(!model.dirty());
        let _ = fs::remove_file(path);
    }

    #[test]
    fn clear_removes_memory_and_files() {
        let path = test_path("clear");
        let mut model = UserModel::default();
        model.set_path(&path).expect("path");
        model.record_selection(key("b"));
        model.flush().expect("flush");
        assert!(path.exists());

        model.clear().expect("clear");
        model.clear().expect("clear again");

        assert_eq!(model.record_count(), 0);
        assert!(!path.exists());
    }

    #[test]
    fn truncated_file_recovers_to_empty() {
        let path = test_path("truncated");
        fs::write(&path, b"HUM9").expect("write");
        let mut model = UserModel::default();
        model.set_path(&path).expect("path");
        let report = model.load().expect("load");

        assert_eq!(report.action, LoadAction::RecoveredEmpty);
        assert_eq!(model.record_count(), 0);
        assert_eq!(model.status().last_error_code, "corrupt");
    }

    #[test]
    fn bad_magic_recovers_to_empty() {
        let path = test_path("bad-magic");
        fs::write(&path, b"BAD!12345678901234567890").expect("write");
        let mut model = UserModel::default();
        model.set_path(&path).expect("path");
        let report = model.load().expect("load");

        assert_eq!(report.action, LoadAction::RecoveredEmpty);
    }

    #[test]
    fn unsupported_version_is_reported_and_recovered() {
        let path = test_path("version");
        let mut model = UserModel::default();
        model.record_selection(key("b"));
        let mut bytes = encode_snapshot(&model.snapshot()).expect("encode");
        patch_format_version_for_test(&mut bytes, 99);
        fs::write(&path, bytes).expect("write");

        let mut loaded = UserModel::default();
        loaded.set_path(&path).expect("path");
        let report = loaded.load().expect("load");

        assert_eq!(report.action, LoadAction::RecoveredEmpty);
        assert_eq!(loaded.status().last_error_code, "unsupported_version");
    }

    #[test]
    fn backup_is_used_when_primary_is_corrupt() {
        let path = test_path("backup");
        let mut model = UserModel::default();
        model.set_path(&path).expect("path");
        model.record_selection(key("b"));
        model.flush().expect("flush");
        fs::write(&path, b"BAD!").expect("corrupt");

        let mut loaded = UserModel::default();
        loaded.set_path(&path).expect("path");
        let report = loaded.load().expect("load");

        assert_eq!(report.action, LoadAction::LoadedBackup);
        assert_eq!(loaded.record_count(), 1);
    }

    #[test]
    fn max_record_compaction_keeps_high_value_records() {
        let mut model = UserModel::new(UserModelConfig {
            max_records: 2,
            ..UserModelConfig::default()
        });
        model.record_selection(key("a"));
        model.record_selection(key("b"));
        model.record_selection(key("c"));
        model.compact();

        assert_eq!(model.record_count(), 2);
    }

    #[test]
    fn persisted_file_does_not_contain_raw_input_sentinel() {
        let path = test_path("privacy");
        let mut model = UserModel::default();
        model.set_path(&path).expect("path");
        model.record_selection(
            UserCandidateKey::from_stable_id(
                "xiaohe",
                8,
                CandidateSourceKind::SystemLexicon,
                "rawInput_SENTINEL_nihc_你好",
            )
            .expect("key"),
        );
        model.flush().expect("flush");

        let bytes = fs::read(&path).expect("read");
        let haystack = String::from_utf8_lossy(&bytes);
        assert!(!haystack.contains("rawInput_SENTINEL"));
        assert!(!haystack.contains("你好"));
    }
}
