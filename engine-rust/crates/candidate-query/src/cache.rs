use std::collections::VecDeque;

use crate::model::QueryMode;
use candidate_ranking::CandidateOrder;
use candidate_ranking::RankingCandidate;

/// Cache key for full ranked query results.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CacheKey {
    pub scheme_id: String,
    pub reading: String,
    pub mode: QueryMode,
    pub candidate_order: CandidateOrder,
    pub page_size: usize,
    pub lexicon_version: u32,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct QueryCacheStats {
    pub hits: usize,
    pub misses: usize,
    pub len: usize,
}

#[derive(Clone, Debug)]
pub struct BoundedQueryCache {
    capacity: usize,
    entries: VecDeque<(CacheKey, Vec<RankingCandidate>)>,
    hits: usize,
    misses: usize,
}

impl BoundedQueryCache {
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity,
            entries: VecDeque::new(),
            hits: 0,
            misses: 0,
        }
    }

    pub fn get(&mut self, key: &CacheKey) -> Option<Vec<RankingCandidate>> {
        let Some(position) = self
            .entries
            .iter()
            .position(|(candidate_key, _)| candidate_key == key)
        else {
            self.misses += 1;
            return None;
        };
        let entry = self.entries.remove(position)?;
        let result = entry.1.clone();
        self.entries.push_back(entry);
        self.hits += 1;
        Some(result)
    }

    pub fn insert(&mut self, key: CacheKey, candidates: Vec<RankingCandidate>) {
        if self.capacity == 0 {
            return;
        }
        if let Some(position) = self
            .entries
            .iter()
            .position(|(candidate_key, _)| candidate_key == &key)
        {
            self.entries.remove(position);
        }
        while self.entries.len() >= self.capacity {
            self.entries.pop_front();
        }
        self.entries.push_back((key, candidates));
    }

    pub fn clear(&mut self) {
        self.entries.clear();
    }

    pub fn stats(&self) -> QueryCacheStats {
        QueryCacheStats {
            hits: self.hits,
            misses: self.misses,
            len: self.entries.len(),
        }
    }
}
