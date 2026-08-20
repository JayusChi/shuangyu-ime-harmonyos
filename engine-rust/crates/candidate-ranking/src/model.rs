use std::cmp::Ordering;

/// Explicit boundary between production ranking and code-table row order.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Hash)]
pub enum CandidateOrder {
    #[default]
    ExistingRanking,
    SourceOrder,
}

/// Candidate match class allowed in stage 7 ranking.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CandidateMatchType {
    /// The normalized pinyin key exactly matches the query reading.
    Exact,
    /// The normalized pinyin key starts with the query reading.
    Prefix,
}

impl CandidateMatchType {
    pub const fn rank_priority(self) -> u8 {
        match self {
            Self::Exact => 0,
            Self::Prefix => 1,
        }
    }
}

impl Ord for CandidateMatchType {
    fn cmp(&self, other: &Self) -> Ordering {
        self.rank_priority().cmp(&other.rank_priority())
    }
}

impl PartialOrd for CandidateMatchType {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// Internal candidate data used by stage 7 ranking.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RankingCandidate {
    pub id: String,
    pub text: String,
    pub reading: String,
    pub source: String,
    pub frequency: u64,
    pub match_type: CandidateMatchType,
    pub source_order: u32,
}

impl RankingCandidate {
    pub fn new(
        id: impl Into<String>,
        text: impl Into<String>,
        reading: impl Into<String>,
        source: impl Into<String>,
        frequency: u64,
        match_type: CandidateMatchType,
    ) -> Self {
        Self {
            id: id.into(),
            text: text.into(),
            reading: reading.into(),
            source: source.into(),
            frequency,
            match_type,
            source_order: u32::MAX,
        }
    }

    pub fn with_source_order(mut self, source_order: u32) -> Self {
        self.source_order = source_order;
        self
    }
}
