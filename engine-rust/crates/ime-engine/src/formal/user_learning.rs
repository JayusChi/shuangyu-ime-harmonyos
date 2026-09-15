impl ImeEngine {
    /// Only aligned, impossible two-key syllables are eligible. A valid
    /// sound/final pair and an explicit boundary retain their parser meaning.
    fn xiaohe_fixed_initial_words(&self, result: &ParseResult) -> Vec<FixedWordConstraint> {
        if self.scheme_id != "xiaohe" || self.user_lexicon.is_empty() {
            return Vec::new();
        }
        let mut words = Vec::new();
        let mut raw_offset = 0;
        for slot in 0..result.logical_syllable_count {
            let Some(left) = result.syllables.iter().find(|s| s.logical_index == slot) else {
                continue;
            };
            let start = raw_offset;
            raw_offset += left.raw_code.len();
            if start % 2 != 0
                || left.raw_code.len() != 1
                || !left.final_part.is_empty()
                || result.segment_boundaries.contains(&(start + 1))
            {
                continue;
            }
            let Some(right) = result
                .syllables
                .iter()
                .find(|s| s.logical_index == slot + 1)
            else {
                continue;
            };
            if right.raw_code.len() != 1 || !right.final_part.is_empty() {
                continue;
            }
            let code = format!("{}{}", left.raw_code, right.raw_code);
            // Source order matches the existing fixed-candidate prefix. Only
            // literal two-character fixed rules take part in sentence decoding.
            if let Some(entry) =
                self.user_lexicon
                    .entries_for_code(&code)
                    .into_iter()
                    .find(|entry| {
                        matches!(entry.action, UserLexiconAction::Fixed)
                            && entry.text.chars().count() == 2
                    })
            {
                words.push(FixedWordConstraint {
                    start: slot,
                    end: slot + 2,
                    text: entry.text.clone(),
                    entry_id: entry.stable_id(),
                });
            }
        }
        words
    }

    pub fn set_user_model_path(
        &mut self,
        path: &str,
    ) -> Result<UserModelStatus, EngineOperationError> {
        if path.trim().is_empty() {
            return Err(EngineOperationError::InvalidArgument);
        }
        let status = self
            .user_model
            .set_path(path)
            .map_err(EngineOperationError::UserModel)?;
        self.t9_compatibility_decode_cache.clear();
        Ok(status)
    }

    pub fn load_user_model(&mut self) -> Result<UserModelStatus, EngineOperationError> {
        let status = self
            .user_model
            .load()
            .map(|_| self.user_model.status())
            .map_err(EngineOperationError::UserModel)?;
        self.t9_compatibility_decode_cache.clear();
        Ok(status)
    }

    pub fn flush_user_model(&mut self) -> Result<UserModelStatus, EngineOperationError> {
        self.user_model
            .flush()
            .map_err(EngineOperationError::UserModel)
    }

    pub fn clear_user_model(&mut self) -> Result<UserModelStatus, EngineOperationError> {
        let status = self
            .user_model
            .clear()
            .map_err(EngineOperationError::UserModel)?;
        self.t9_compatibility_decode_cache.clear();
        Ok(status)
    }

    pub fn set_user_learning_enabled(&mut self, enabled: bool) -> UserModelStatus {
        let status = self.user_model.set_user_learning_enabled(enabled);
        self.t9_compatibility_decode_cache.clear();
        status
    }

    pub fn set_session_learning_allowed(&mut self, allowed: bool) -> UserModelStatus {
        self.quanpin_context_reranker.set_context_allowed(allowed);
        let status = self.user_model.set_session_learning_allowed(allowed);
        self.t9_compatibility_decode_cache.clear();
        status
    }

    /// Reloads the external user overlay without exposing a partially parsed
    /// snapshot. Corruption keeps the last valid in-memory rules.
    fn apply_user_lexicon(
        &self,
        candidates: Vec<EngineCandidate>,
        allow_prefix_fallback: bool,
    ) -> Vec<EngineCandidate> {
        if self.user_lexicon.is_empty()
            || self
                .parser
                .as_ref()
                .expect("phonetic parser")
                .raw_input()
                .is_empty()
        {
            return candidates;
        }
        let raw_len = self
            .parser
            .as_ref()
            .expect("phonetic parser")
            .raw_input()
            .chars()
            .filter(|character| *character != '\'')
            .count();
        let lookup_code = self.user_lexicon_lookup_code();
        let make_candidate = |entry: &UserLexiconEntry| EngineCandidate {
            id: entry.stable_id(),
            text: entry.text.clone(),
            reading: if self.scheme_id == "quanpin" {
                entry
                    .code
                    .strip_prefix("qp")
                    .unwrap_or(&entry.code)
                    .to_owned()
            } else if self.scheme_id == "pinyin-9" {
                entry
                    .code
                    .strip_prefix("p9")
                    .unwrap_or(&entry.code)
                    .to_owned()
            } else {
                entry.code.clone()
            },
            source: if entry.action.external_action().is_some() {
                "functional"
            } else {
                "user-lexicon"
            }
            .to_owned(),
            consumed_raw_len: raw_len,
            learning_key: None,
            // An imported user lexicon is a fixed candidate source. It may be
            // selected, but it is never copied into the transient n-gram
            // context window.
            context_words: Vec::new(),
        };
        if allow_prefix_fallback {
            merge_candidates_exact_or_prefix(
                &self.user_lexicon,
                &lookup_code,
                candidates,
                |candidate| candidate.text.as_str(),
                make_candidate,
            )
        } else {
            merge_candidates(
                &self.user_lexicon,
                &lookup_code,
                candidates,
                |candidate| candidate.text.as_str(),
                make_candidate,
            )
        }
    }

    /// Existing user rules remain Xiaohe raw-code rules. Quanpin uses an
    /// explicit lowercase `qp` namespace within the unchanged two-column file
    /// format (for example `自定义词\tqpzidingyici`).
    fn user_lexicon_lookup_code(&self) -> String {
        let raw = self
            .parser
            .as_ref()
            .expect("phonetic parser")
            .raw_input()
            .chars()
            .filter(|character| *character != '\'')
            .collect::<String>();
        if self.scheme_id == "quanpin" {
            format!("qp{raw}")
        } else if self.scheme_id == "pinyin-9" {
            let current = self
                .parser
                .as_ref()
                .expect("phonetic parser")
                .current_state()
                .current_pinyin
                .chars()
                .filter(|character| character.is_ascii_lowercase())
                .collect::<String>();
            format!("p9{current}")
        } else {
            raw
        }
    }

    fn user_score_for_sentence(&self, candidate: &SentenceCandidate, lexicon_version: u32) -> i64 {
        self.learning_key(
            CandidateSourceKind::SentencePath,
            lexicon_version,
            &candidate.id,
        )
        .map(|key| self.user_model.score(&key))
        .unwrap_or(0)
    }

    fn learning_key(
        &self,
        source_kind: CandidateSourceKind,
        lexicon_version: u32,
        stable_id: &str,
    ) -> Option<UserCandidateKey> {
        UserCandidateKey::from_stable_id(
            self.scheme_id.clone(),
            lexicon_version,
            source_kind,
            stable_id,
        )
        .ok()
    }
}

fn load_user_lexicon(path: &str) -> UserLexiconSnapshot {
    load_snapshot_recovering(std::path::Path::new(path))
        .map(|report| report.snapshot)
        .unwrap_or_default()
}
