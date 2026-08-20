/// Magic bytes for stage 9 user model snapshots.
pub const FILE_MAGIC: &[u8; 4] = b"HUM9";

/// Current user model file format version.
pub const FORMAT_VERSION: u16 = 1;

/// Current logical data version inside the format.
pub const DATA_VERSION: u16 = 1;

/// Saturating maximum stored selection count per candidate.
pub const MAX_SELECTION_COUNT: u32 = 1_024;

/// Maximum user ranking contribution exposed by the scoring module.
pub const MAX_USER_WEIGHT: i64 = 5_000;

/// Centralized user model limits.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserModelConfig {
    pub max_records: usize,
    pub max_file_size: u64,
    pub max_path_len: usize,
    pub max_scheme_id_len: usize,
    pub max_unsaved_events: u32,
}

impl Default for UserModelConfig {
    fn default() -> Self {
        Self {
            max_records: 2_048,
            max_file_size: 1_048_576,
            max_path_len: 4_096,
            max_scheme_id_len: 64,
            max_unsaved_events: 8,
        }
    }
}
