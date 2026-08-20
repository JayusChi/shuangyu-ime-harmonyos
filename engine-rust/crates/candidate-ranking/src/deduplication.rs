use std::collections::{btree_map::Entry, BTreeMap, BTreeSet};

use crate::{CandidateMatchType, RankingCandidate};

/// Deduplicates by `text + normalized reading` and merges source tags.
pub fn deduplicate_candidates(candidates: Vec<RankingCandidate>) -> Vec<RankingCandidate> {
    let mut by_key = BTreeMap::<(String, String), RankingCandidate>::new();

    for candidate in candidates {
        let key = (candidate.text.clone(), candidate.reading.clone());
        match by_key.entry(key) {
            Entry::Vacant(slot) => {
                slot.insert(candidate);
            }
            Entry::Occupied(mut slot) => {
                merge_candidate(slot.get_mut(), candidate);
            }
        }
    }

    by_key.into_values().collect()
}

/// Deduplicates without changing an order already established by the caller.
pub fn deduplicate_candidates_stable(candidates: Vec<RankingCandidate>) -> Vec<RankingCandidate> {
    let mut positions = BTreeMap::<(String, String), usize>::new();
    let mut deduplicated: Vec<RankingCandidate> = Vec::new();
    for candidate in candidates {
        let key = (candidate.text.clone(), candidate.reading.clone());
        if let Some(position) = positions.get(&key).copied() {
            merge_candidate(&mut deduplicated[position], candidate);
        } else {
            positions.insert(key, deduplicated.len());
            deduplicated.push(candidate);
        }
    }
    deduplicated
}

fn merge_candidate(existing: &mut RankingCandidate, incoming: RankingCandidate) {
    existing.frequency = existing.frequency.max(incoming.frequency);
    existing.match_type = best_match_type(existing.match_type, incoming.match_type);
    existing.source = merge_sources(&existing.source, &incoming.source);
    existing.id = stable_id(&existing.reading, &existing.text);
    existing.source_order = existing.source_order.min(incoming.source_order);
}

fn best_match_type(left: CandidateMatchType, right: CandidateMatchType) -> CandidateMatchType {
    if left <= right {
        left
    } else {
        right
    }
}

fn merge_sources(left: &str, right: &str) -> String {
    let mut sources = BTreeSet::new();
    for source in left.split(',').chain(right.split(',')) {
        let trimmed = source.trim();
        if !trimmed.is_empty() {
            sources.insert(trimmed.to_owned());
        }
    }
    sources.into_iter().collect::<Vec<_>>().join(",")
}

fn stable_id(reading: &str, text: &str) -> String {
    format!("lexicon:{}:{}", reading.replace(' ', "_"), text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merges_same_text_and_reading_deterministically() {
        let candidates = vec![
            RankingCandidate::new("b", "你", "ni", "secondary", 10, CandidateMatchType::Prefix),
            RankingCandidate::new("a", "你", "ni", "primary", 20, CandidateMatchType::Exact),
        ];

        let deduped = deduplicate_candidates(candidates);

        assert_eq!(deduped.len(), 1);
        assert_eq!(deduped[0].frequency, 20);
        assert_eq!(deduped[0].match_type, CandidateMatchType::Exact);
        assert_eq!(deduped[0].source, "primary,secondary");
    }
}
