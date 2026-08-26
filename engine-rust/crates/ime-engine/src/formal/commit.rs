impl ImeEngine {
    pub fn select_candidate(
        &mut self,
        page_index: usize,
    ) -> Result<CompositionResult, EngineOperationError> {
        if let EngineBackend::CodeTable(machine) = &mut self.backend {
            let selection = machine
                .select_current_page(page_index)
                .map_err(|_| EngineOperationError::InvalidCandidate)?;
            return Ok(match selection {
                CodeTableSelection::CommitText(text) => CompositionResult::committed(&text),
                CodeTableSelection::Action(action) => action_result(action),
            });
        }
        let Some(candidate) = self.session.select_current_page(page_index).cloned() else {
            return Err(EngineOperationError::InvalidCandidate);
        };
        // Selection can mutate user ranking, so no compatibility decode that
        // captured the previous user scores may survive the commit.
        self.t9_compatibility_decode_cache.clear();
        let commit_text = candidate.text;
        if let Some(learning_key) = candidate.learning_key {
            if self.user_model.record_selection(learning_key) {
                let _ = self.user_model.flush_if_needed();
            }
        }
        let raw_input = self
            .parser
            .as_ref()
            .expect("phonetic parser")
            .raw_input()
            .to_owned();
        let raw_letter_count = raw_input.chars().filter(|ch| *ch != '\'').count();
        let consumed = candidate.consumed_raw_len.min(raw_letter_count);
        if consumed >= raw_letter_count {
            self.parser.as_mut().expect("phonetic parser").reset();
            self.session.clear();
            self.quanpin_context_reranker
                .record_explicit_commit(&candidate.context_words);
            return Ok(CompositionResult::committed(&commit_text));
        }

        let remaining = remaining_raw_input(&raw_input, consumed);
        self.parser.as_mut().expect("phonetic parser").reset();
        // A partial selection starts a new logical composition for the raw
        // tail. Quanpin normally preserves the last non-empty prefix snapshot
        // while a user keeps typing, but that snapshot belongs to the already
        // committed prefix here and must never be offered for the remainder.
        self.session.clear();
        self.quanpin_context_reranker.clear_context();
        let result = self
            .parser
            .as_mut()
            .expect("phonetic parser")
            .process_str(&remaining);
        let mut output = self.refresh_candidates(result);
        output.commit_text = commit_text;
        output.composition_finished = false;
        Ok(output)
    }

    pub fn select_pinyin_combination(
        &mut self,
        combination_index: usize,
    ) -> Result<CompositionResult, EngineOperationError> {
        if self.scheme_id != "pinyin-9" || matches!(self.backend, EngineBackend::CodeTable(_)) {
            return Err(EngineOperationError::InvalidArgument);
        }
        let result = self
            .parser
            .as_mut()
            .expect("phonetic parser")
            .select_pinyin_combination(combination_index)
            .map_err(|_| EngineOperationError::InvalidArgument)?;
        self.session.clear();
        Ok(self.refresh_candidates(result))
    }

}
