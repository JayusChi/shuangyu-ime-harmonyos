use std::sync::{Arc, RwLock};

use lexicon_core::MAX_CODE_LEN;
use user_lexicon::{
    merge_code_table_candidates, merge_code_table_exact_candidates,
    merge_code_table_hint_candidates, merge_code_table_progressive_candidates, UserLexiconAction,
    UserLexiconEntry, UserLexiconSnapshot,
};

use crate::action::{FunctionalAction, FunctionalActionTable};
use crate::bundle::CodeTableBundle;
use crate::category::CategorySelectionSnapshot;
use crate::error::{CodeTableError, CodeTableErrorKind};
use crate::query::{
    exact_system_candidates, longer_system_candidates, longer_system_codes, query_isolated_table,
    query_with_strategy_and_snapshot, CodeTableCandidate, CodeTableMatch, CodeTableQueryStrategy,
    QuerySnapshot,
};

const MAX_PRECISE_HINT_CANDIDATES: usize = 9;

const MAX_CODE_TABLE_SOURCE_CANDIDATES: usize = 4096;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CodeTableInputState {
    Idle,
    NormalCode,
    GuidePrefix,
    GuideCode,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CodeTableSelection {
    CommitText(String),
    Action(FunctionalAction),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CodeTableCommitPolicy {
    pub auto_commit_length: usize,
    pub top_screen_length: usize,
    pub empty_code_clear_length: usize,
    pub normal_code_max_length: usize,
    pub empty_code_split_max_length: usize,
}

impl CodeTableCommitPolicy {
    pub const FROZEN_DEFAULT_LENGTH: usize = 4;

    pub fn new(
        auto_commit_length: usize,
        top_screen_length: usize,
        empty_code_clear_length: usize,
        normal_code_max_length: usize,
    ) -> Result<Self, CodeTableError> {
        let policy = Self {
            auto_commit_length,
            top_screen_length,
            empty_code_clear_length,
            normal_code_max_length,
            empty_code_split_max_length: normal_code_max_length,
        };
        policy.validate()?;
        Ok(policy)
    }

    pub fn new_with_split_limit(
        auto_commit_length: usize,
        top_screen_length: usize,
        empty_code_clear_length: usize,
        normal_code_max_length: usize,
        empty_code_split_max_length: usize,
    ) -> Result<Self, CodeTableError> {
        let policy = Self {
            auto_commit_length,
            top_screen_length,
            empty_code_clear_length,
            normal_code_max_length,
            empty_code_split_max_length,
        };
        policy.validate()?;
        Ok(policy)
    }

    fn validate(self) -> Result<(), CodeTableError> {
        let lengths = [
            ("auto_commit_length", self.auto_commit_length),
            ("top_screen_length", self.top_screen_length),
            ("empty_code_clear_length", self.empty_code_clear_length),
            ("normal_code_max_length", self.normal_code_max_length),
            (
                "empty_code_split_max_length",
                self.empty_code_split_max_length,
            ),
        ];
        for (name, value) in lengths {
            if !(1..=MAX_CODE_LEN).contains(&value) {
                return Err(CodeTableError::new(
                    CodeTableErrorKind::InvalidCommitPolicy,
                    format!("{name} must be in 1..={MAX_CODE_LEN}"),
                ));
            }
        }
        for (name, value) in lengths.into_iter().take(3) {
            if value > self.normal_code_max_length {
                return Err(CodeTableError::new(
                    CodeTableErrorKind::InvalidCommitPolicy,
                    format!("{name} exceeds normal_code_max_length"),
                ));
            }
        }
        if self.empty_code_split_max_length < self.empty_code_clear_length
            || self.empty_code_split_max_length > self.normal_code_max_length
        {
            return Err(CodeTableError::new(
                CodeTableErrorKind::InvalidCommitPolicy,
                "empty_code_split_max_length must be between empty_code_clear_length and normal_code_max_length",
            ));
        }
        Ok(())
    }
}

impl Default for CodeTableCommitPolicy {
    fn default() -> Self {
        Self {
            auto_commit_length: Self::FROZEN_DEFAULT_LENGTH,
            top_screen_length: Self::FROZEN_DEFAULT_LENGTH,
            empty_code_clear_length: Self::FROZEN_DEFAULT_LENGTH,
            normal_code_max_length: MAX_CODE_LEN,
            empty_code_split_max_length: MAX_CODE_LEN,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct EmptyCodeSplit {
    commit_text: String,
    remaining_code: String,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct CodeTableProcessOutcome {
    pub commit_text: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResourceState {
    pub bundle_id: String,
    pub enabled_category_ids: Vec<String>,
    pub category_count: usize,
}

#[derive(Clone, Debug)]
pub struct CodeTableStateMachine {
    bundle: Arc<CodeTableBundle>,
    raw_code: String,
    query_cache: Option<QuerySnapshot>,
    current_page: usize,
    page_size: usize,
    max_candidates: usize,
    category_selection: Arc<RwLock<Arc<CategorySelectionSnapshot>>>,
    user_lexicon: Arc<UserLexiconSnapshot>,
    action_table: Option<Arc<FunctionalActionTable>>,
    input_state: CodeTableInputState,
    commit_policy: CodeTableCommitPolicy,
    query_strategy: CodeTableQueryStrategy,
}

impl CodeTableStateMachine {
    pub fn new(
        bundle: Arc<CodeTableBundle>,
        page_size: usize,
        max_candidates: usize,
    ) -> Result<Self, CodeTableError> {
        Self::new_with_user_lexicon(
            bundle,
            page_size,
            max_candidates,
            Arc::new(UserLexiconSnapshot::empty()),
        )
    }

    pub fn new_with_user_lexicon(
        bundle: Arc<CodeTableBundle>,
        page_size: usize,
        max_candidates: usize,
        user_lexicon: Arc<UserLexiconSnapshot>,
    ) -> Result<Self, CodeTableError> {
        Self::new_with_policy(
            bundle,
            page_size,
            max_candidates,
            user_lexicon,
            CodeTableCommitPolicy::default(),
        )
    }

    pub fn new_with_query_strategy(
        bundle: Arc<CodeTableBundle>,
        page_size: usize,
        max_candidates: usize,
        user_lexicon: Arc<UserLexiconSnapshot>,
        query_strategy: CodeTableQueryStrategy,
    ) -> Result<Self, CodeTableError> {
        Self::new_with_policy_and_query_strategy(
            bundle,
            page_size,
            max_candidates,
            user_lexicon,
            CodeTableCommitPolicy::default(),
            query_strategy,
        )
    }

    pub fn new_with_policy(
        bundle: Arc<CodeTableBundle>,
        page_size: usize,
        max_candidates: usize,
        user_lexicon: Arc<UserLexiconSnapshot>,
        commit_policy: CodeTableCommitPolicy,
    ) -> Result<Self, CodeTableError> {
        Self::new_with_policy_and_query_strategy(
            bundle,
            page_size,
            max_candidates,
            user_lexicon,
            commit_policy,
            CodeTableQueryStrategy::ExactOrPrefixFallback,
        )
    }

    pub fn new_with_policy_and_query_strategy(
        bundle: Arc<CodeTableBundle>,
        page_size: usize,
        max_candidates: usize,
        user_lexicon: Arc<UserLexiconSnapshot>,
        commit_policy: CodeTableCommitPolicy,
        query_strategy: CodeTableQueryStrategy,
    ) -> Result<Self, CodeTableError> {
        if page_size == 0 || max_candidates == 0 || page_size > max_candidates {
            return Err(CodeTableError::new(
                CodeTableErrorKind::InvalidPage,
                "page size and candidate limit must be positive and bounded",
            ));
        }
        commit_policy.validate()?;
        let category_selection = Arc::new(CategorySelectionSnapshot::defaults(&bundle)?);
        Ok(Self {
            bundle,
            raw_code: String::new(),
            query_cache: None,
            current_page: 0,
            page_size,
            max_candidates,
            category_selection: Arc::new(RwLock::new(category_selection)),
            user_lexicon,
            action_table: None,
            input_state: CodeTableInputState::Idle,
            commit_policy,
            query_strategy,
        })
    }

    pub fn process_key(&mut self, key: char) -> Result<CodeTableProcessOutcome, CodeTableError> {
        if key == ';' {
            self.raw_code.clear();
            self.clear_query_state();
            self.input_state = CodeTableInputState::GuidePrefix;
            return Ok(CodeTableProcessOutcome::default());
        }
        if !key.is_ascii_lowercase() {
            if matches!(
                self.input_state,
                CodeTableInputState::GuidePrefix | CodeTableInputState::GuideCode
            ) {
                self.reset();
            }
            return Err(CodeTableError::new(
                CodeTableErrorKind::InvalidKey,
                "only lowercase ASCII code keys are accepted",
            ));
        }
        let category_snapshot = self.category_selection_snapshot();
        let user_snapshot = Arc::clone(&self.user_lexicon);
        let mut outcome = CodeTableProcessOutcome::default();
        if self.input_state == CodeTableInputState::NormalCode
            && self.raw_code.len() >= self.commit_policy.top_screen_length
        {
            outcome.commit_text = self
                .exact_candidates_for_snapshots(&self.raw_code, &category_snapshot, &user_snapshot)
                .first()
                .map(|candidate| candidate.text.clone());
            self.raw_code.clear();
            self.clear_query_state();
            self.input_state = CodeTableInputState::Idle;
        }
        if self.raw_code.len() >= self.commit_policy.normal_code_max_length {
            return Err(CodeTableError::new(
                CodeTableErrorKind::CodeTooLong,
                format!(
                    "raw code reached the {}-byte limit",
                    self.commit_policy.normal_code_max_length
                ),
            ));
        }
        self.raw_code.push(key);
        if matches!(
            self.input_state,
            CodeTableInputState::GuidePrefix | CodeTableInputState::GuideCode
        ) {
            self.input_state = CodeTableInputState::GuideCode;
            self.requery_guide();
        } else {
            self.input_state = CodeTableInputState::NormalCode;
            self.requery_with_snapshots(&category_snapshot, &user_snapshot);
            let exact = self.exact_candidates_for_snapshots(
                &self.raw_code,
                &category_snapshot,
                &user_snapshot,
            );
            let has_continuation = self.has_valid_continuation_for_snapshots(
                &self.raw_code,
                &category_snapshot,
                &user_snapshot,
            );
            if self.raw_code.len() >= self.commit_policy.empty_code_clear_length
                && exact.is_empty()
                && !has_continuation
            {
                if let Some(split) = self.empty_code_split_for_snapshots(
                    &self.raw_code,
                    &category_snapshot,
                    &user_snapshot,
                ) {
                    outcome.commit_text = Some(split.commit_text);
                    self.raw_code = split.remaining_code;
                    self.input_state = CodeTableInputState::NormalCode;
                    self.requery_with_snapshots(&category_snapshot, &user_snapshot);
                } else {
                    self.reset();
                }
            } else if outcome.commit_text.is_none()
                && self.raw_code.len() >= self.commit_policy.auto_commit_length
                && exact.len() == 1
                && !has_continuation
            {
                outcome.commit_text = Some(exact[0].text.clone());
                self.reset();
            }
        }
        Ok(outcome)
    }

    pub fn backspace(&mut self) {
        if self.input_state == CodeTableInputState::GuidePrefix {
            self.reset();
            return;
        }
        self.raw_code.pop();
        if self.raw_code.is_empty() {
            self.clear_query_state();
            self.input_state = if self.input_state == CodeTableInputState::GuideCode {
                CodeTableInputState::GuidePrefix
            } else {
                CodeTableInputState::Idle
            };
        } else if self.input_state == CodeTableInputState::GuideCode {
            self.requery_guide();
        } else {
            self.requery();
        }
    }

    pub fn reset(&mut self) {
        self.raw_code.clear();
        self.clear_query_state();
        self.input_state = CodeTableInputState::Idle;
    }

    pub fn set_enabled_categories(&mut self, ids: Vec<String>) -> Result<(), CodeTableError> {
        let next = Arc::new(CategorySelectionSnapshot::from_requested(
            &self.bundle,
            &ids,
        )?);
        *self
            .category_selection
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = next;
        if self.raw_code.is_empty() {
            self.clear_query_state();
        } else if self.input_state == CodeTableInputState::GuideCode {
            self.requery_guide();
        } else {
            self.requery();
        }
        Ok(())
    }

    /// Atomically replaces the immutable user overlay observed by subsequent
    /// queries. An in-flight query keeps its previously captured `Arc`.
    pub fn set_user_lexicon_snapshot(&mut self, snapshot: Arc<UserLexiconSnapshot>) {
        self.user_lexicon = snapshot;
        if self.raw_code.is_empty() {
            self.clear_query_state();
        } else if self.input_state == CodeTableInputState::GuideCode {
            self.requery_guide();
        } else {
            self.requery();
        }
    }

    pub fn set_action_table(&mut self, table: Option<Arc<FunctionalActionTable>>) {
        self.action_table = table;
        if self.input_state == CodeTableInputState::GuideCode {
            self.requery_guide();
        }
    }

    pub fn next_page(&mut self) -> Result<(), CodeTableError> {
        if !self.has_next_page() {
            return Err(CodeTableError::new(
                CodeTableErrorKind::InvalidPage,
                "there is no next candidate page",
            ));
        }
        self.current_page += 1;
        Ok(())
    }

    pub fn previous_page(&mut self) -> Result<(), CodeTableError> {
        if self.current_page == 0 {
            return Err(CodeTableError::new(
                CodeTableErrorKind::InvalidPage,
                "there is no previous candidate page",
            ));
        }
        self.current_page -= 1;
        Ok(())
    }

    pub fn select_current_page(
        &mut self,
        index: usize,
    ) -> Result<CodeTableSelection, CodeTableError> {
        let candidate = self
            .current_candidates()
            .get(index)
            .cloned()
            .ok_or_else(|| {
                CodeTableError::new(
                    CodeTableErrorKind::InvalidCandidate,
                    "candidate index is outside the current page",
                )
            })?;
        let selection = if candidate.category_id == "functional" {
            let action_id = candidate.id.strip_prefix("action:").ok_or_else(|| {
                CodeTableError::new(
                    CodeTableErrorKind::InvalidCandidate,
                    "functional candidate id is invalid",
                )
            })?;
            let action = self
                .action_table
                .as_ref()
                .and_then(|table| table.record(action_id))
                .map(|record| record.action.clone())
                .ok_or_else(|| {
                    CodeTableError::new(
                        CodeTableErrorKind::InvalidCandidate,
                        "functional action is unavailable",
                    )
                })?;
            match action {
                FunctionalAction::StaticText(text)
                | FunctionalAction::StaticSymbol(text)
                | FunctionalAction::QuickSymbol(text) => CodeTableSelection::CommitText(text),
                action => CodeTableSelection::Action(action),
            }
        } else {
            CodeTableSelection::CommitText(candidate.text)
        };
        self.reset();
        Ok(selection)
    }

    pub fn raw_code(&self) -> &str {
        &self.raw_code
    }

    pub fn input_state(&self) -> CodeTableInputState {
        self.input_state
    }

    pub fn current_candidates(&self) -> &[CodeTableCandidate] {
        let Some(snapshot) = &self.query_cache else {
            return &[];
        };
        let start = self.current_page.saturating_mul(self.page_size);
        if start >= snapshot.candidates.len() {
            return &[];
        }
        let end = start
            .saturating_add(self.page_size)
            .min(snapshot.candidates.len());
        &snapshot.candidates[start..end]
    }

    pub fn all_candidates(&self) -> &[CodeTableCandidate] {
        self.query_cache
            .as_ref()
            .map(|snapshot| snapshot.candidates.as_slice())
            .unwrap_or(&[])
    }

    pub fn query_cache(&self) -> Option<&QuerySnapshot> {
        self.query_cache.as_ref()
    }

    pub const fn current_page(&self) -> usize {
        self.current_page
    }

    pub fn has_next_page(&self) -> bool {
        let total = self
            .query_cache
            .as_ref()
            .map(|snapshot| snapshot.candidates.len())
            .unwrap_or(0);
        self.current_page
            .saturating_add(1)
            .saturating_mul(self.page_size)
            < total
    }

    pub const fn has_previous_page(&self) -> bool {
        self.current_page > 0
    }

    pub fn resource_state(&self) -> ResourceState {
        let selection = self.category_selection_snapshot();
        ResourceState {
            bundle_id: self.bundle.bundle_id.clone(),
            enabled_category_ids: selection.enabled_category_ids().to_vec(),
            category_count: self.bundle.categories.len(),
        }
    }

    pub fn category_selection_snapshot(&self) -> Arc<CategorySelectionSnapshot> {
        Arc::clone(
            &self
                .category_selection
                .read()
                .unwrap_or_else(|poisoned| poisoned.into_inner()),
        )
    }

    pub fn exact_candidate_count(&self) -> usize {
        if self.raw_code.is_empty() {
            return 0;
        }
        self.exact_candidates_for(&self.raw_code).len()
    }

    pub fn is_unique_exact_match(&self) -> bool {
        self.exact_candidate_count() == 1
    }

    pub fn has_valid_continuation(&self) -> bool {
        if self.raw_code.is_empty() {
            return false;
        }
        let selection = self.category_selection_snapshot();
        let user_snapshot = Arc::clone(&self.user_lexicon);
        self.has_valid_continuation_for_snapshots(&self.raw_code, &selection, &user_snapshot)
    }

    pub const fn commit_policy(&self) -> CodeTableCommitPolicy {
        self.commit_policy
    }

    pub const fn query_strategy(&self) -> CodeTableQueryStrategy {
        self.query_strategy
    }

    fn has_valid_continuation_for_snapshots(
        &self,
        code: &str,
        selection: &CategorySelectionSnapshot,
        user_snapshot: &UserLexiconSnapshot,
    ) -> bool {
        let mut codes = longer_system_codes(&self.bundle, selection, code);
        codes.extend(
            user_snapshot
                .entries_for_longer_prefix(code)
                .into_iter()
                .filter(|entry| !matches!(entry.action, UserLexiconAction::Delete))
                .map(|entry| entry.code.clone()),
        );
        codes.into_iter().any(|code| {
            !self
                .exact_candidates_for_snapshots(&code, selection, user_snapshot)
                .is_empty()
        })
    }

    fn empty_code_split_for_snapshots(
        &self,
        code: &str,
        selection: &CategorySelectionSnapshot,
        user_snapshot: &UserLexiconSnapshot,
    ) -> Option<EmptyCodeSplit> {
        if code.len() < 2 || code.len() > self.commit_policy.empty_code_split_max_length {
            return None;
        }

        for split_at in (1..code.len()).rev() {
            let prefix = &code[..split_at];
            let Some(candidate) = self
                .exact_candidates_for_snapshots(prefix, selection, user_snapshot)
                .into_iter()
                .next()
            else {
                continue;
            };
            return Some(EmptyCodeSplit {
                commit_text: candidate.text,
                remaining_code: code[split_at..].to_owned(),
            });
        }

        for split_at in 1..code.len() {
            let suffix = &code[split_at..];
            let suffix_is_visible = !self
                .exact_candidates_for_snapshots(suffix, selection, user_snapshot)
                .is_empty()
                || self.has_valid_continuation_for_snapshots(suffix, selection, user_snapshot);
            if suffix_is_visible {
                return Some(EmptyCodeSplit {
                    commit_text: code[..split_at].to_owned(),
                    remaining_code: suffix.to_owned(),
                });
            }
        }

        None
    }

    fn requery(&mut self) {
        let user_snapshot = Arc::clone(&self.user_lexicon);
        let category_snapshot = self.category_selection_snapshot();
        self.requery_with_snapshots(&category_snapshot, &user_snapshot);
    }

    fn requery_with_snapshots(
        &mut self,
        category_snapshot: &CategorySelectionSnapshot,
        user_snapshot: &UserLexiconSnapshot,
    ) {
        let mut query = self.query_for_snapshots(&self.raw_code, category_snapshot, user_snapshot);
        query.candidates.truncate(self.max_candidates);
        self.query_cache = Some(query);
        self.current_page = 0;
    }

    fn query_for_snapshots(
        &self,
        raw_code: &str,
        category_snapshot: &CategorySelectionSnapshot,
        user_snapshot: &UserLexiconSnapshot,
    ) -> QuerySnapshot {
        if self.query_strategy == CodeTableQueryStrategy::DeterministicXiaoheYinxing {
            return self.query_deterministic_for_snapshots(
                raw_code,
                category_snapshot,
                user_snapshot,
            );
        }
        // Reserve enough system rows to refill the bounded result after every
        // effective user rule has run. Pagination still observes at most
        // `max_candidates` candidates after the overlay and stable de-dup.
        let reserved_source_limit = self
            .max_candidates
            .saturating_add(user_snapshot.entries().len());
        let source_limit = if self.query_strategy == CodeTableQueryStrategy::ExactOrPrefixFallback {
            reserved_source_limit
        } else {
            reserved_source_limit.min(MAX_CODE_TABLE_SOURCE_CANDIDATES)
        };
        let mut query = query_with_strategy_and_snapshot(
            &self.bundle,
            category_snapshot,
            raw_code,
            source_limit,
            self.query_strategy,
        );
        let make_user_candidate = |entry: &UserLexiconEntry| CodeTableCandidate {
            id: entry.stable_id(),
            text: entry.text.clone(),
            code: entry.code.clone(),
            category_id: "user-lexicon".to_owned(),
            source_order: entry.source_order,
            match_type: if entry.code == raw_code {
                CodeTableMatch::Exact
            } else {
                CodeTableMatch::Prefix
            },
        };
        query.candidates = match self.query_strategy {
            CodeTableQueryStrategy::ExactOnly
            | CodeTableQueryStrategy::DeterministicXiaoheYinxing => {
                merge_code_table_exact_candidates(
                    user_snapshot,
                    raw_code,
                    query.candidates,
                    |candidate| candidate.text.as_str(),
                    |candidate| candidate.code.as_str(),
                    make_user_candidate,
                )
            }
            CodeTableQueryStrategy::ExactOrPrefixFallback => merge_code_table_candidates(
                user_snapshot,
                raw_code,
                query.candidates,
                |candidate| candidate.text.as_str(),
                |candidate| candidate.code.as_str(),
                make_user_candidate,
            ),
            CodeTableQueryStrategy::ProgressiveXiaoheYinxing
                if (1..=3).contains(&raw_code.len()) =>
            {
                merge_code_table_progressive_candidates(
                    user_snapshot,
                    raw_code,
                    query.candidates,
                    |candidate| candidate.text.as_str(),
                    |candidate| candidate.code.as_str(),
                    make_user_candidate,
                )
            }
            CodeTableQueryStrategy::ProgressiveXiaoheYinxing => merge_code_table_exact_candidates(
                user_snapshot,
                raw_code,
                query.candidates,
                |candidate| candidate.text.as_str(),
                |candidate| candidate.code.as_str(),
                make_user_candidate,
            ),
        };
        query
    }

    fn query_deterministic_for_snapshots(
        &self,
        raw_code: &str,
        category_snapshot: &CategorySelectionSnapshot,
        user_snapshot: &UserLexiconSnapshot,
    ) -> QuerySnapshot {
        if raw_code.is_empty() {
            return QuerySnapshot {
                raw_code: String::new(),
                match_type: None,
                candidates: Vec::new(),
            };
        }

        let system_exact = exact_system_candidates(&self.bundle, category_snapshot, raw_code);
        let exact_path_exists =
            !system_exact.is_empty() || !user_snapshot.entries_for_code(raw_code).is_empty();
        let make_user_candidate = |entry: &UserLexiconEntry| CodeTableCandidate {
            id: entry.stable_id(),
            text: entry.text.clone(),
            code: entry.code.clone(),
            category_id: "user-lexicon".to_owned(),
            source_order: entry.source_order,
            match_type: CodeTableMatch::Exact,
        };
        let exact = merge_code_table_exact_candidates(
            user_snapshot,
            raw_code,
            system_exact,
            |candidate| candidate.text.as_str(),
            |candidate| candidate.code.as_str(),
            make_user_candidate,
        );
        if exact_path_exists || !exact.is_empty() {
            return QuerySnapshot {
                raw_code: raw_code.to_owned(),
                match_type: Some(CodeTableMatch::Exact),
                candidates: exact,
            };
        }

        let hint_limit = MAX_PRECISE_HINT_CANDIDATES.min(self.max_candidates);
        let source_limit = hint_limit
            .saturating_add(user_snapshot.entries().len())
            .min(MAX_CODE_TABLE_SOURCE_CANDIDATES);
        let system_hints =
            longer_system_candidates(&self.bundle, category_snapshot, raw_code, source_limit);
        let hints = merge_code_table_hint_candidates(
            user_snapshot,
            raw_code,
            system_hints,
            |candidate| candidate.text.as_str(),
            |candidate| candidate.code.as_str(),
            |entry: &UserLexiconEntry| CodeTableCandidate {
                id: entry.stable_id(),
                text: entry.text.clone(),
                code: entry.code.clone(),
                category_id: "user-lexicon".to_owned(),
                source_order: entry.source_order,
                match_type: CodeTableMatch::Prefix,
            },
        );
        QuerySnapshot {
            raw_code: raw_code.to_owned(),
            match_type: Some(CodeTableMatch::Prefix),
            candidates: hints.into_iter().take(hint_limit).collect(),
        }
    }

    fn requery_guide(&mut self) {
        if self.raw_code.is_empty() {
            self.clear_query_state();
            return;
        }
        let category_snapshot = self.category_selection_snapshot();
        let production_quick_symbols = self
            .bundle
            .categories
            .iter()
            .find(|category| category.id == "quick-symbol");
        let quick_symbols_enabled = production_quick_symbols
            .is_none_or(|category| category_snapshot.is_enabled(&category.id));
        let guide_category = self
            .bundle
            .guide
            .as_ref()
            .or_else(|| production_quick_symbols.filter(|_| quick_symbols_enabled));
        let mut query = guide_category
            .map(|guide| query_isolated_table(&self.bundle.bundle_id, guide, &self.raw_code))
            .unwrap_or_else(|| QuerySnapshot {
                raw_code: self.raw_code.clone(),
                match_type: None,
                candidates: Vec::new(),
            });
        if quick_symbols_enabled {
            if let Some(table) = &self.action_table {
                let functional = table.query_exact_or_prefix(&self.raw_code);
                let functional_exact = functional
                    .first()
                    .is_some_and(|record| record.code == self.raw_code);
                if functional_exact {
                    query.candidates.clear();
                }
                if query.candidates.is_empty()
                    || (query.match_type == Some(CodeTableMatch::Prefix) && functional_exact)
                {
                    query.match_type = Some(if functional_exact {
                        CodeTableMatch::Exact
                    } else {
                        CodeTableMatch::Prefix
                    });
                }
                let effective_match = query.match_type;
                query
                    .candidates
                    .extend(functional.into_iter().filter_map(|record| {
                        let record_match = if record.code == self.raw_code {
                            CodeTableMatch::Exact
                        } else {
                            CodeTableMatch::Prefix
                        };
                        if effective_match == Some(CodeTableMatch::Exact)
                            && record_match != CodeTableMatch::Exact
                        {
                            return None;
                        }
                        Some(CodeTableCandidate {
                            id: format!("action:{}", record.id),
                            text: record.label.clone(),
                            code: record.code.clone(),
                            category_id: "functional".to_owned(),
                            source_order: record.source_order,
                            match_type: record_match,
                        })
                    }));
            }
        }
        query.candidates.truncate(self.max_candidates);
        self.query_cache = Some(query);
        self.current_page = 0;
    }

    fn exact_candidates_for(&self, code: &str) -> Vec<CodeTableCandidate> {
        let category_snapshot = self.category_selection_snapshot();
        let user_snapshot = Arc::clone(&self.user_lexicon);
        self.exact_candidates_for_snapshots(code, &category_snapshot, &user_snapshot)
    }

    fn exact_candidates_for_snapshots(
        &self,
        code: &str,
        category_snapshot: &CategorySelectionSnapshot,
        user_snapshot: &UserLexiconSnapshot,
    ) -> Vec<CodeTableCandidate> {
        merge_code_table_exact_candidates(
            user_snapshot,
            code,
            exact_system_candidates(&self.bundle, category_snapshot, code),
            |candidate| candidate.text.as_str(),
            |candidate| candidate.code.as_str(),
            |entry: &UserLexiconEntry| CodeTableCandidate {
                id: entry.stable_id(),
                text: entry.text.clone(),
                code: entry.code.clone(),
                category_id: "user-lexicon".to_owned(),
                source_order: entry.source_order,
                match_type: CodeTableMatch::Exact,
            },
        )
    }

    fn clear_query_state(&mut self) {
        self.query_cache = None;
        self.current_page = 0;
    }
}
