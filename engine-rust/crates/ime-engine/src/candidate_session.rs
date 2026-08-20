use candidate_ranking::RankingCandidate;
use user_model::UserCandidateKey;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EngineCandidate {
    pub id: String,
    pub text: String,
    pub reading: String,
    pub source: String,
    pub consumed_raw_len: usize,
    pub learning_key: Option<UserCandidateKey>,
    /// Internal word tokens from a decoder path. They are never serialized to
    /// ArkTS and are retained only for an explicit, in-memory context window.
    pub context_words: Vec<String>,
}

impl EngineCandidate {
    pub fn from_ranking(
        candidate: RankingCandidate,
        consumed_raw_len: usize,
        learning_key: Option<UserCandidateKey>,
    ) -> Self {
        let context_words = vec![candidate.text.clone()];
        Self {
            id: candidate.id,
            text: candidate.text,
            reading: candidate.reading,
            source: candidate.source,
            consumed_raw_len,
            learning_key,
            context_words,
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct CandidateSession {
    candidates: Vec<EngineCandidate>,
    page_size: usize,
    page_index: usize,
}

impl CandidateSession {
    pub fn replace(&mut self, candidates: Vec<EngineCandidate>, page_size: usize) {
        self.candidates = candidates;
        self.page_size = page_size.max(1);
        self.page_index = 0;
    }

    /// Publishes a new snapshot only when it contains candidates. During an
    /// active composition, a temporarily empty query must not destroy the
    /// last prefix snapshot or its raw-input coverage metadata.
    pub fn replace_if_nonempty(
        &mut self,
        candidates: Vec<EngineCandidate>,
        page_size: usize,
    ) -> bool {
        if candidates.is_empty() {
            return false;
        }
        self.replace(candidates, page_size);
        true
    }

    pub fn clear(&mut self) {
        self.candidates.clear();
        self.page_size = 0;
        self.page_index = 0;
    }

    pub fn retain_covered_by(&mut self, raw_len: usize) {
        self.candidates
            .retain(|candidate| candidate.consumed_raw_len <= raw_len);
        if self.candidates.is_empty() {
            self.clear();
        } else if self.page_index.saturating_mul(self.page_size) >= self.candidates.len() {
            self.page_index = 0;
        }
    }

    pub fn current_page(&self) -> &[EngineCandidate] {
        if self.candidates.is_empty() || self.page_size == 0 {
            return &[];
        }
        let start = self.page_index.saturating_mul(self.page_size);
        if start >= self.candidates.len() {
            return &[];
        }
        let end = start
            .saturating_add(self.page_size)
            .min(self.candidates.len());
        &self.candidates[start..end]
    }

    pub fn all_candidates(&self) -> &[EngineCandidate] {
        &self.candidates
    }

    pub fn select_current_page(&self, index: usize) -> Option<&EngineCandidate> {
        self.current_page().get(index)
    }

    pub fn has_next_page(&self) -> bool {
        if self.page_size == 0 {
            return false;
        }
        (self.page_index + 1).saturating_mul(self.page_size) < self.candidates.len()
    }

    pub fn has_previous_page(&self) -> bool {
        self.page_index > 0
    }

    pub fn page_index(&self) -> usize {
        self.page_index
    }

    pub fn next_page(&mut self) -> bool {
        if !self.has_next_page() {
            return false;
        }
        self.page_index += 1;
        true
    }

    pub fn previous_page(&mut self) -> bool {
        if !self.has_previous_page() {
            return false;
        }
        self.page_index -= 1;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn candidate(text: &str) -> EngineCandidate {
        EngineCandidate::from_ranking(
            RankingCandidate::new(
                format!("id-{text}"),
                text,
                "ni",
                "stage7",
                1,
                candidate_ranking::CandidateMatchType::Exact,
            ),
            2,
            None,
        )
    }

    #[test]
    fn paginates_first_middle_and_last_pages() {
        let mut session = CandidateSession::default();
        session.replace(vec![candidate("一"), candidate("二"), candidate("三")], 1);

        assert_eq!(session.current_page()[0].text, "一");
        assert!(!session.has_previous_page());
        assert!(session.has_next_page());

        assert!(session.next_page());
        assert_eq!(session.current_page()[0].text, "二");
        assert!(session.has_previous_page());
        assert!(session.has_next_page());

        assert!(session.next_page());
        assert_eq!(session.current_page()[0].text, "三");
        assert!(!session.has_next_page());
        assert!(!session.next_page());
    }

    #[test]
    fn clear_removes_page_state() {
        let mut session = CandidateSession::default();
        session.replace(vec![candidate("一"), candidate("二")], 1);
        assert!(session.next_page());
        session.clear();

        assert!(session.current_page().is_empty());
        assert!(!session.has_next_page());
        assert!(!session.has_previous_page());
    }

    #[test]
    fn temporary_empty_snapshot_preserves_candidates_and_page() {
        let mut session = CandidateSession::default();
        session.replace(vec![candidate("一"), candidate("二")], 1);
        assert!(session.next_page());

        assert!(!session.replace_if_nonempty(Vec::new(), 9));
        assert_eq!(session.current_page()[0].text, "二");
        assert!(session.has_previous_page());
    }

    #[test]
    fn backspace_below_candidate_coverage_drops_stale_snapshot() {
        let mut session = CandidateSession::default();
        session.replace(vec![candidate("一")], 1);
        session.retain_covered_by(1);
        assert!(session.current_page().is_empty());
    }
}
