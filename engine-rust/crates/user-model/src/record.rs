use crate::limits::{FORMAT_VERSION, MAX_SELECTION_COUNT};

/// Bounded selection statistics for one candidate key.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserRecord {
    pub selection_count: u32,
    pub last_selected_seq: u64,
    pub first_record_version: u16,
    pub updated_seq: u64,
}

impl UserRecord {
    pub(crate) fn new(sequence: u64) -> Self {
        Self {
            selection_count: 1,
            last_selected_seq: sequence,
            first_record_version: FORMAT_VERSION,
            updated_seq: sequence,
        }
    }

    pub(crate) fn record_selection(&mut self, sequence: u64) {
        self.selection_count = self
            .selection_count
            .saturating_add(1)
            .min(MAX_SELECTION_COUNT);
        self.last_selected_seq = sequence;
        self.updated_seq = sequence;
    }

    pub(crate) fn merge(&mut self, other: &Self) {
        self.selection_count = self
            .selection_count
            .saturating_add(other.selection_count)
            .min(MAX_SELECTION_COUNT);
        self.last_selected_seq = self.last_selected_seq.max(other.last_selected_seq);
        self.first_record_version = self.first_record_version.min(other.first_record_version);
        self.updated_seq = self.updated_seq.max(other.updated_seq);
    }
}
