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
    query_with_strategy_and_snapshot, wildcard_system_candidates, CodeTableCandidate,
    CodeTableMatch, CodeTableQueryStrategy, QuerySnapshot,
};

const PRECISE_HINT_CANDIDATE_LIMIT: usize = 1;

const MAX_CODE_TABLE_SOURCE_CANDIDATES: usize = 4096;
const GUIDE_PREFIX_DEFAULT_CODE: &str = "_";
const GUIDE_REPEAT_CODE: &str = ";";
const FUNCTIONAL_CATEGORY_ID: &str = "functional";
const QUICK_SYMBOL_CATEGORY_ID: &str = "quick-symbol";

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
    pub reverse_split_enabled: bool,
    pub auto_commit_length: usize,
    pub top_screen_length: usize,
    pub empty_code_clear_length: usize,
    pub normal_code_max_length: usize,
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
            reverse_split_enabled: false,
            auto_commit_length,
            top_screen_length,
            empty_code_clear_length,
            normal_code_max_length,
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
        Ok(())
    }
}

impl Default for CodeTableCommitPolicy {
    fn default() -> Self {
        Self {
            reverse_split_enabled: false,
            auto_commit_length: Self::FROZEN_DEFAULT_LENGTH,
            top_screen_length: Self::FROZEN_DEFAULT_LENGTH,
            empty_code_clear_length: Self::FROZEN_DEFAULT_LENGTH,
            normal_code_max_length: MAX_CODE_LEN,
        }
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct CodeTableProcessOutcome {
    pub commit_text: Option<String>,
    pub action: Option<FunctionalAction>,
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
    // Count before display truncation: one visible row is not necessarily unique.
    reverse_split_candidate_count: usize,
}

impl CodeTableStateMachine {
    /// Read-only lookup includes hidden character categories, so full codes
    /// remain discoverable even when their extra candidates are disabled.
    pub fn reverse_lookup(&self, text: &str) -> Vec<String> {
        let mut chars = text.chars();
        let Some(character) = chars.next() else {
            return Vec::new();
        };
        if chars.next().is_some()
            || !matches!(character as u32, 0x3007 | 0x3400..=0x9fff | 0xf900..=0xfaff | 0x20000..=0x323af)
        {
            return Vec::new();
        }
        let mut codes = std::collections::BTreeSet::new();
        for category in &self.bundle.categories {
            if category.id == QUICK_SYMBOL_CATEGORY_ID {
                continue;
            }
            for entry in &category.lexicon.entries {
                if entry.word == text {
                    codes.insert(entry.pinyin_key.clone());
                }
            }
        }
        for entry in self
            .user_lexicon
            .entries()
            .iter()
            .filter(|entry| entry.text == text)
        {
            match entry.action {
                UserLexiconAction::Delete => {
                    codes.remove(&entry.code);
                }
                UserLexiconAction::Add
                | UserLexiconAction::Fixed
                | UserLexiconAction::Position(_) => {
                    codes.insert(entry.code.clone());
                }
                _ => {}
            }
        }
        let mut codes = codes
            .into_iter()
            .filter(|code| {
                (1..=4).contains(&code.len()) && code.bytes().all(|byte| byte.is_ascii_lowercase())
            })
            .collect::<Vec<_>>();
        codes.sort_by(|left, right| right.len().cmp(&left.len()).then_with(|| left.cmp(right)));
        codes.truncate(64);
        codes
    }

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
            reverse_split_candidate_count: 0,
        })
    }

    pub fn process_key(&mut self, key: char) -> Result<CodeTableProcessOutcome, CodeTableError> {
        if key == ';' {
            if self.input_state == CodeTableInputState::GuidePrefix {
                let commit_text = self
                    .query_guide_code(GUIDE_REPEAT_CODE)
                    .candidates
                    .into_iter()
                    .find(|candidate| candidate.code == GUIDE_REPEAT_CODE)
                    .map(|candidate| candidate.text);
                if commit_text.is_some() {
                    self.reset();
                    return Ok(CodeTableProcessOutcome {
                        commit_text,
                        action: None,
                    });
                }
            }
            self.raw_code.clear();
            self.clear_query_state();
            self.input_state = CodeTableInputState::GuidePrefix;
            self.requery_guide();
            return Ok(CodeTableProcessOutcome::default());
        }
        if key == '`' {
            if matches!(
                self.input_state,
                CodeTableInputState::GuidePrefix | CodeTableInputState::GuideCode
            ) {
                self.reset();
            }
            if self.raw_code.len() >= self.commit_policy.normal_code_max_length {
                return Err(CodeTableError::new(
                    CodeTableErrorKind::CodeTooLong,
                    "universal code reached the configured limit",
                ));
            }
            self.raw_code.push(key);
            self.input_state = CodeTableInputState::NormalCode;
            self.requery();
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
        if self.raw_code.contains('`') {
            if self.raw_code.len() >= self.commit_policy.normal_code_max_length {
                return Err(CodeTableError::new(
                    CodeTableErrorKind::CodeTooLong,
                    "universal code reached the configured limit",
                ));
            }
            self.raw_code.push(key);
            self.input_state = CodeTableInputState::NormalCode;
            self.requery_with_snapshots(&category_snapshot, &user_snapshot);
            return Ok(outcome);
        }
        if self.reverse_split_candidate_count > 0 {
            // A 2+1 split is provisional while no fourth code exists. A
            // fourth code must re-enter the established full-code / 2+2 /
            // empty-code decision instead of committing the three-code hint.
            if self.raw_code.len() != 3 {
                outcome.commit_text = self
                    .all_candidates()
                    .first()
                    .filter(|row| !self.is_external_shortcut(row))
                    .map(|row| row.text.clone());
                self.reset();
            }
        } else if self.input_state == CodeTableInputState::NormalCode
            && self.raw_code.len() >= self.commit_policy.top_screen_length
            && !self.has_valid_continuation_for_snapshots(
                &self.raw_code,
                &category_snapshot,
                &user_snapshot,
            )
        {
            outcome.commit_text = self
                .exact_candidates_for_snapshots(&self.raw_code, &category_snapshot, &user_snapshot)
                .first()
                .filter(|candidate| !self.is_external_shortcut(candidate))
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
            if let Some(selection) = self.unique_exact_guide_selection() {
                match selection {
                    CodeTableSelection::CommitText(text) => outcome.commit_text = Some(text),
                    CodeTableSelection::Action(action) => outcome.action = Some(action),
                }
                self.reset();
            }
        } else {
            self.input_state = CodeTableInputState::NormalCode;
            self.requery_with_snapshots(&category_snapshot, &user_snapshot);
            if self.reverse_split_candidate_count > 0 {
                if self.reverse_split_candidate_count == 1
                    && self.raw_code.len() >= self.commit_policy.auto_commit_length
                    && outcome.commit_text.is_none()
                {
                    outcome.commit_text = self
                        .all_candidates()
                        .first()
                        .filter(|row| !self.is_external_shortcut(row))
                        .map(|row| row.text.clone());
                    self.reset();
                }
                return Ok(outcome);
            }
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
            let has_direct_exact = self.has_direct_action_exact(&self.raw_code);
            // Completing a sole four-code direct entry is its confirmation key.
            // Keep shorter, ambiguous and extendable codes available for selection.
            if outcome.commit_text.is_none()
                && self.raw_code.len() == 4
                && has_direct_exact
                && !has_continuation
                && exact.len() + self.direct_exact_count(&self.raw_code) == 1
                && self.all_candidates().len() == 1
            {
                match self.select_current_page(0)? {
                    CodeTableSelection::CommitText(text) => outcome.commit_text = Some(text),
                    CodeTableSelection::Action(action) => outcome.action = Some(action),
                }
                return Ok(outcome);
            }
            if self.raw_code.len() >= self.commit_policy.empty_code_clear_length
                && exact.is_empty()
                && !has_direct_exact
                && !has_continuation
            {
                // In traditional mode (or when 2+2 has no exact pair), never split into a shorter candidate
                // plus a replayed tail. Such a split made the fourth key look
                // like an early top-screen commit (for example `niu` + `o`).
                // The customer contract is binary here: clear the four-code
                // composition when enabled, otherwise preserve it.
                self.reset();
            } else if outcome.commit_text.is_none()
                && self.raw_code.len() >= self.commit_policy.auto_commit_length
                && exact.len() == 1
                && !self.is_external_shortcut(&exact[0])
                && !has_direct_exact
                && !has_continuation
            {
                outcome.commit_text = Some(exact[0].text.clone());
                self.reset();
            }
        }
        Ok(outcome)
    }

    /// A guide letter is the confirmation key for a sole exact quick-symbol
    /// result. Both plain symbols and closed functional actions execute at
    /// this boundary; ambiguous same-code rows still wait for selection.
    fn unique_exact_guide_selection(&self) -> Option<CodeTableSelection> {
        if self.raw_code.len() != 1 {
            return None;
        }
        let query = self.query_cache.as_ref()?;
        if query.match_type != Some(CodeTableMatch::Exact) || query.candidates.len() != 1 {
            return None;
        }
        let candidate = query.candidates.first()?;
        if candidate.category_id == QUICK_SYMBOL_CATEGORY_ID {
            return Some(CodeTableSelection::CommitText(candidate.text.clone()));
        }
        if candidate.category_id != FUNCTIONAL_CATEGORY_ID {
            return None;
        }
        let action_id = candidate.id.strip_prefix("action:")?;
        let action = &self.action_table.as_ref()?.record(action_id)?.action;
        match action {
            FunctionalAction::StaticText(text)
            | FunctionalAction::StaticSymbol(text)
            | FunctionalAction::QuickSymbol(text) => {
                Some(CodeTableSelection::CommitText(text.clone()))
            }
            action => Some(CodeTableSelection::Action(action.clone())),
        }
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
        if matches!(
            self.input_state,
            CodeTableInputState::GuidePrefix | CodeTableInputState::GuideCode
        ) {
            self.requery_guide();
        } else if !self.raw_code.is_empty() {
            self.requery();
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
        } else if let Some(entry) = self.user_lexicon.entries().iter().find(|entry| {
            entry.stable_id() == candidate.id && entry.action.external_action().is_some()
        }) {
            let action = entry.action.external_action().expect("external shortcut");
            if !user_lexicon::valid_shortcut_target(action, &entry.text) {
                return Err(CodeTableError::new(
                    CodeTableErrorKind::InvalidCandidate,
                    "invalid shortcut target",
                ));
            }
            CodeTableSelection::Action(FunctionalAction::DirectControl {
                action: action.to_owned(),
                target: entry.text.clone(),
            })
        } else {
            CodeTableSelection::CommitText(candidate.text)
        };
        self.reset();
        Ok(selection)
    }

    fn is_external_shortcut(&self, candidate: &CodeTableCandidate) -> bool {
        self.user_lexicon.entries().iter().any(|entry| {
            entry.action.external_action().is_some() && entry.stable_id() == candidate.id
        })
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
        if self.reverse_split_candidate_count > 0 {
            return self.reverse_split_candidate_count;
        }
        if self.raw_code.is_empty() {
            return 0;
        }
        self.exact_candidates_for(&self.raw_code).len()
    }

    pub fn is_unique_exact_match(&self) -> bool {
        self.exact_candidate_count() == 1
    }

    pub fn is_reverse_split(&self) -> bool {
        self.reverse_split_candidate_count > 0
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

    pub fn set_commit_policy(
        &mut self,
        policy: CodeTableCommitPolicy,
    ) -> Result<(), CodeTableError> {
        policy.validate()?;
        let mode_changed = self.commit_policy.reverse_split_enabled != policy.reverse_split_enabled;
        if !self.raw_code.is_empty() && !mode_changed {
            return Err(CodeTableError::new(
                CodeTableErrorKind::InvalidCommitPolicy,
                "commit policy can change only at a composition boundary",
            ));
        }
        if mode_changed {
            self.reset();
        }
        self.commit_policy = policy;
        Ok(())
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
        self.has_direct_action_continuation(code)
            || codes.into_iter().any(|code| {
                !self
                    .exact_candidates_for_snapshots(&code, selection, user_snapshot)
                    .is_empty()
            })
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
        let split = self.reverse_split_candidates_for_code(
            &self.raw_code,
            category_snapshot,
            user_snapshot,
        );
        self.reverse_split_candidate_count = split.len();
        let mut query = if split.is_empty() {
            self.query_for_snapshots(&self.raw_code, category_snapshot, user_snapshot)
        } else {
            QuerySnapshot {
                raw_code: self.raw_code.clone(),
                match_type: Some(CodeTableMatch::Exact),
                candidates: split,
            }
        };
        self.merge_direct_actions(&mut query, &self.raw_code);
        query.candidates.truncate(self.max_candidates);
        self.query_cache = Some(query);
        self.current_page = 0;
    }

    fn reverse_split_candidates_for_code(
        &self,
        code: &str,
        categories: &CategorySelectionSnapshot,
        user: &UserLexiconSnapshot,
    ) -> Vec<CodeTableCandidate> {
        if !self.commit_policy.reverse_split_enabled
            || self.input_state != CodeTableInputState::NormalCode
            || !matches!(code.len(), 3 | 4)
            || !code.bytes().all(|byte| byte.is_ascii_lowercase())
            || self.has_direct_action_exact(code)
            // Keep existing long-code / OK spelling / direct-action paths reachable.
            || self.has_valid_continuation_for_snapshots(code, categories, user)
            || !self.exact_candidates_for_snapshots(code, categories, user).is_empty()
        {
            return Vec::new();
        }
        // Three-code dead ends split as 2+1 immediately; four-code dead ends
        // retain the established 2+2 behavior. Both paths keep the two-code
        // front fixed at its first exact candidate.
        let front = self.exact_candidates_for_snapshots(&code[..2], categories, user);
        let Some(front) = front.first() else {
            return Vec::new();
        };
        self.exact_candidates_for_snapshots(&code[2..], categories, user)
            .into_iter()
            .enumerate()
            .map(|(index, back)| {
                let text = format!("{}{}", front.text, back.text);
                let back_display = back.display_text.as_deref().unwrap_or(&back.text);
                let display_text = if index == 0 {
                    format!(
                        "{}{}",
                        front.display_text.as_deref().unwrap_or(&front.text),
                        back_display
                    )
                } else {
                    back_display.to_owned()
                };
                CodeTableCandidate {
                    id: format!("split:{}:{}:{}", code, front.id, back.id),
                    text,
                    display_text: Some(display_text),
                    code: code.to_owned(),
                    category_id: "reverse-split".to_owned(),
                    source_order: back.source_order,
                    match_type: CodeTableMatch::Exact,
                }
            })
            .collect()
    }

    fn query_for_snapshots(
        &self,
        raw_code: &str,
        category_snapshot: &CategorySelectionSnapshot,
        user_snapshot: &UserLexiconSnapshot,
    ) -> QuerySnapshot {
        if raw_code.contains('`') {
            return QuerySnapshot {
                raw_code: raw_code.to_owned(),
                match_type: Some(CodeTableMatch::Prefix),
                candidates: wildcard_system_candidates(
                    &self.bundle,
                    category_snapshot,
                    raw_code,
                    self.max_candidates,
                ),
            };
        }
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
            display_text: entry.display_text.clone().or_else(|| {
                entry.action.external_action().map(|_| {
                    if matches!(entry.action, UserLexiconAction::OpenUrl) {
                        "打开网页"
                    } else {
                        "打开目录"
                    }
                    .to_owned()
                })
            }),
            code: entry.code.clone(),
            category_id: if entry.action.external_action().is_some() {
                "user-shortcut"
            } else {
                "user-lexicon"
            }
            .to_owned(),
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
            display_text: entry.display_text.clone().or_else(|| {
                entry.action.external_action().map(|_| {
                    if matches!(entry.action, UserLexiconAction::OpenUrl) {
                        "打开网页".to_owned()
                    } else {
                        "打开目录".to_owned()
                    }
                })
            }),
            code: entry.code.clone(),
            category_id: if entry.action.external_action().is_some() {
                "user-shortcut"
            } else {
                "user-lexicon"
            }
            .to_owned(),
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

        let hint_limit = PRECISE_HINT_CANDIDATE_LIMIT.min(self.max_candidates);
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
                display_text: entry.display_text.clone().or_else(|| {
                    entry.action.external_action().map(|_| {
                        if matches!(entry.action, UserLexiconAction::OpenUrl) {
                            "打开网页".to_owned()
                        } else {
                            "打开目录".to_owned()
                        }
                    })
                }),
                code: entry.code.clone(),
                category_id: if entry.action.external_action().is_some() {
                    "user-shortcut"
                } else {
                    "user-lexicon"
                }
                .to_owned(),
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
        let query_code = if self.raw_code.is_empty() {
            if self.input_state != CodeTableInputState::GuidePrefix {
                self.clear_query_state();
                return;
            }
            GUIDE_PREFIX_DEFAULT_CODE
        } else {
            self.raw_code.as_str()
        };
        let query = self.query_guide_code(query_code);
        self.query_cache = Some(query);
        self.current_page = 0;
    }

    fn query_guide_code(&self, query_code: &str) -> QuerySnapshot {
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
            .map(|guide| query_isolated_table(&self.bundle.bundle_id, guide, query_code))
            .unwrap_or_else(|| QuerySnapshot {
                raw_code: query_code.to_owned(),
                match_type: None,
                candidates: Vec::new(),
            });
        if quick_symbols_enabled {
            if let Some(table) = &self.action_table {
                let functional = table.query_guide_exact_or_prefix(query_code);
                let functional_exact = functional
                    .first()
                    .is_some_and(|record| record.code == query_code);
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
                        let record_match = if record.code == query_code {
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
                            display_text: None,
                            code: record.code.clone(),
                            category_id: "functional".to_owned(),
                            source_order: record.source_order,
                            match_type: record_match,
                        })
                    }));
            }
        }
        query.candidates.truncate(self.max_candidates);
        query
    }

    fn merge_direct_actions(&self, query: &mut QuerySnapshot, raw_code: &str) {
        let Some(table) = &self.action_table else {
            return;
        };
        let functional = table.query_direct_exact_or_prefix(raw_code);
        if functional.is_empty() {
            return;
        }
        let functional_exact = functional
            .first()
            .is_some_and(|record| record.code == raw_code);
        // Direct actions reserve their continuation path but stay invisible
        // until the whole code is present. Otherwise the many `o...` actions
        // would crowd ordinary one-letter candidates.
        if !functional_exact {
            return;
        }
        let candidates = functional.into_iter().map(|record| CodeTableCandidate {
            id: format!("action:{}", record.id),
            text: record.label.clone(),
            display_text: None,
            code: record.code.clone(),
            category_id: "functional".to_owned(),
            source_order: record.source_order,
            match_type: if record.code == raw_code {
                CodeTableMatch::Exact
            } else {
                CodeTableMatch::Prefix
            },
        });
        query.candidates.splice(0..0, candidates);
        query.match_type = Some(CodeTableMatch::Exact);
    }

    fn direct_exact_count(&self, code: &str) -> usize {
        let builtin = self.action_table.as_ref().map_or(0, |table| {
            table.query_direct_exact_or_prefix(code).iter().filter(|record| record.code == code).count()
        });
        builtin + self.user_lexicon.entries_for_code(code).iter().filter(|entry| {
            entry.action.external_action().is_some() && !self.user_lexicon.deletes(&entry.code, &entry.text)
        }).count()
    }

    fn has_direct_action_exact(&self, code: &str) -> bool {
        if self
            .user_lexicon
            .entries_for_code(code)
            .iter()
            .any(|entry| entry.action.external_action().is_some())
        {
            return true;
        }
        self.action_table
            .as_ref()
            .is_some_and(|table| table.has_direct_exact(code))
    }

    fn has_direct_action_continuation(&self, code: &str) -> bool {
        // External actions do not count as committable text, but their longer
        // codes must still prevent top-screen commits and reverse splitting.
        self.user_lexicon
            .entries_for_longer_prefix(code)
            .iter()
            .any(|entry| {
                entry.action.external_action().is_some()
                    && !self.user_lexicon.deletes(&entry.code, &entry.text)
            })
            || self
                .action_table
                .as_ref()
                .is_some_and(|table| table.has_direct_continuation(code))
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
                display_text: entry.display_text.clone().or_else(|| {
                    entry.action.external_action().map(|_| {
                        if matches!(entry.action, UserLexiconAction::OpenUrl) {
                            "打开网页".to_owned()
                        } else {
                            "打开目录".to_owned()
                        }
                    })
                }),
                code: entry.code.clone(),
                category_id: if entry.action.external_action().is_some() {
                    "user-shortcut"
                } else {
                    "user-lexicon"
                }
                .to_owned(),
                source_order: entry.source_order,
                match_type: CodeTableMatch::Exact,
            },
        )
        .into_iter()
        .filter(|candidate| !self.is_external_shortcut(candidate))
        .collect()
    }

    fn clear_query_state(&mut self) {
        self.reverse_split_candidate_count = 0;
        self.query_cache = None;
        self.current_page = 0;
    }
}
