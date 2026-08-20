use crate::limits::MAX_USER_WEIGHT;
use crate::record::UserRecord;

const COUNT_LINEAR_LIMIT: u32 = 5;
const COUNT_LINEAR_STEP: i64 = 600;
const COUNT_SLOW_STEP: i64 = 120;
const MAX_COUNT_WEIGHT: i64 = 4_000;
const MAX_RECENCY_WEIGHT: i64 = 1_000;
const RECENCY_DECAY_PER_EVENT: i64 = 125;

/// Computes the bounded user score for one record at a logical sequence.
pub fn score_record(record: &UserRecord, current_sequence: u64) -> i64 {
    let count_weight = count_weight(record.selection_count);
    let age = current_sequence.saturating_sub(record.last_selected_seq);
    let recency_weight = MAX_RECENCY_WEIGHT
        .saturating_sub((age.min(8) as i64).saturating_mul(RECENCY_DECAY_PER_EVENT));
    (count_weight + recency_weight).min(MAX_USER_WEIGHT)
}

fn count_weight(selection_count: u32) -> i64 {
    if selection_count == 0 {
        return 0;
    }
    if selection_count <= COUNT_LINEAR_LIMIT {
        return i64::from(selection_count) * COUNT_LINEAR_STEP;
    }
    let slow_count = selection_count - COUNT_LINEAR_LIMIT;
    (i64::from(COUNT_LINEAR_LIMIT) * COUNT_LINEAR_STEP)
        .saturating_add(i64::from(slow_count).saturating_mul(COUNT_SLOW_STEP))
        .min(MAX_COUNT_WEIGHT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repeated_selection_is_bounded() {
        let record = UserRecord {
            selection_count: 10_000,
            last_selected_seq: 10,
            first_record_version: 1,
            updated_seq: 10,
        };

        assert_eq!(score_record(&record, 10), MAX_USER_WEIGHT);
    }

    #[test]
    fn recency_decays_by_logical_sequence() {
        let record = UserRecord {
            selection_count: 1,
            last_selected_seq: 1,
            first_record_version: 1,
            updated_seq: 1,
        };

        assert!(score_record(&record, 1) > score_record(&record, 8));
    }
}
