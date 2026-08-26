impl ImeEngine {
    pub fn set_user_model_path(
        &mut self,
        path: &str,
    ) -> Result<UserModelStatus, EngineOperationError> {
        if path.trim().is_empty() {
            return Err(EngineOperationError::InvalidArgument);
        }
        let status = self.user_model
            .set_path(path)
            .map_err(EngineOperationError::UserModel)?;
        self.t9_compatibility_decode_cache.clear();
        Ok(status)
    }

    pub fn load_user_model(&mut self) -> Result<UserModelStatus, EngineOperationError> {
        let status = self.user_model
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
        let status = self.user_model
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
            source: "user-lexicon".to_owned(),
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

