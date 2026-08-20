impl ImeEngine {
    pub fn process_key(&mut self, key: char) -> CompositionResult {
        if let EngineBackend::CodeTable(machine) = &mut self.backend {
            return match machine.process_key(key) {
                Ok(outcome) => code_table_result_with_commit(machine, outcome.commit_text),
                Err(error) => {
                    code_table_failure(machine, ImeErrorCode::InvalidArgument, &error.to_string())
                }
            };
        }
        let valid_key = if self.scheme_id == "pinyin-9" {
            matches!(key, '2'..='9')
        } else {
            key.is_ascii_lowercase()
        };
        if !valid_key {
            return CompositionResult::interface_error(ImeErrorCode::InvalidArgument);
        }
        if self.scheme_id == "pinyin-9"
            && self
                .parser
                .as_ref()
                .expect("phonetic parser")
                .raw_input()
                .len()
                >= T9_MAX_RAW_DIGITS
        {
            self.last_t9_joint_stats.input_limit_hit = true;
            let mut output = self.current_state();
            output.success = false;
            output.error_code = ImeErrorCode::InvalidArgument;
            output.error_message = format!(
                "pinyin-9 input is limited to {T9_MAX_RAW_DIGITS} digits; composition was preserved"
            );
            return output;
        }
        let result = self
            .parser
            .as_mut()
            .expect("shuangpin parser")
            .process_key(key);
        self.refresh_candidates(result)
    }

    pub fn insert_segment_boundary(&mut self) -> Result<CompositionResult, EngineOperationError> {
        if matches!(self.backend, EngineBackend::CodeTable(_)) {
            return Err(EngineOperationError::InvalidArgument);
        }
        let result = self
            .parser
            .as_mut()
            .expect("shuangpin parser")
            .insert_segment_boundary()
            .map_err(|_| EngineOperationError::InvalidArgument)?;
        Ok(self.refresh_candidates(result))
    }

    pub fn backspace(&mut self) -> CompositionResult {
        self.quanpin_context_reranker.clear_context();
        if let EngineBackend::CodeTable(machine) = &mut self.backend {
            machine.backspace();
            return code_table_result(machine);
        }
        let result = self.parser.as_mut().expect("shuangpin parser").backspace();
        self.refresh_candidates(result)
    }

    pub fn reset(&mut self) -> CompositionResult {
        self.quanpin_context_reranker.clear_context();
        self.last_t9_joint_stats = T9JointDecoderStats::default();
        self.t9_joint_session.clear();
        if let EngineBackend::CodeTable(machine) = &mut self.backend {
            machine.reset();
            self.session.clear();
            return code_table_result(machine);
        }
        let result = self.parser.as_mut().expect("shuangpin parser").reset();
        self.session.clear();
        self.session.clear();
        self.to_composition_result(result)
    }

    pub fn next_candidate_page(&mut self) -> Result<CompositionResult, EngineOperationError> {
        if let EngineBackend::CodeTable(machine) = &mut self.backend {
            machine
                .next_page()
                .map_err(|_| EngineOperationError::InvalidPage)?;
            return Ok(code_table_result(machine));
        }
        if !self.session.next_page() {
            return Err(EngineOperationError::InvalidPage);
        }
        Ok(self.current_state())
    }

    pub fn previous_candidate_page(&mut self) -> Result<CompositionResult, EngineOperationError> {
        if let EngineBackend::CodeTable(machine) = &mut self.backend {
            machine
                .previous_page()
                .map_err(|_| EngineOperationError::InvalidPage)?;
            return Ok(code_table_result(machine));
        }
        if !self.session.previous_page() {
            return Err(EngineOperationError::InvalidPage);
        }
        Ok(self.current_state())
    }

    pub fn current_state(&self) -> CompositionResult {
        match &self.backend {
            EngineBackend::CodeTable(machine) => code_table_result(machine),
            EngineBackend::Shuangpin => self.to_composition_result(
                self.parser
                    .as_ref()
                    .expect("phonetic parser")
                    .current_state(),
            ),
        }
    }

    fn to_composition_result(&self, result: ParseResult) -> CompositionResult {
        let segment_boundaries = result
            .segment_boundaries
            .iter()
            .map(|boundary| *boundary as u32)
            .collect::<Vec<_>>();
        let parsed_syllables = result
            .syllables
            .iter()
            .map(|syllable| syllable.syllable.clone())
            .collect::<Vec<_>>();
        let preedit_text = build_preedit_text(&parsed_syllables, &result.pending_code);
        let candidates = self
            .session
            .current_page()
            .iter()
            .map(to_formal_candidate)
            .collect::<Vec<_>>();
        CompositionResult::success(
            self.parser.as_ref().expect("phonetic parser").raw_input(),
            &preedit_text,
            parsed_syllables,
            &result.pending_code,
            protocol_state(result.status),
        )
        .with_phonetic_metadata(
            result.display_segments,
            &result.current_pinyin,
            result.pinyin_combinations,
        )
        .with_segment_boundaries(segment_boundaries)
        .with_candidates(
            candidates,
            self.session.page_index() as u32,
            self.session.has_previous_page(),
            self.session.has_next_page(),
        )
    }

    fn failure_from_parse(
        &self,
        result: ParseResult,
        code: ImeErrorCode,
        message: &str,
    ) -> CompositionResult {
        let segment_boundaries = result
            .segment_boundaries
            .iter()
            .map(|boundary| *boundary as u32)
            .collect::<Vec<_>>();
        let parsed_syllables = result
            .syllables
            .iter()
            .map(|syllable| syllable.syllable.clone())
            .collect::<Vec<_>>();
        let preedit_text = build_preedit_text(&parsed_syllables, &result.pending_code);
        let mut output = CompositionResult::success(
            &result.raw_input,
            &preedit_text,
            parsed_syllables,
            &result.pending_code,
            protocol_state(result.status),
        )
        .with_phonetic_metadata(
            result.display_segments,
            &result.current_pinyin,
            result.pinyin_combinations,
        )
        .with_segment_boundaries(segment_boundaries);
        output.success = false;
        output.error_code = code;
        output.error_message = message.to_owned();
        output
    }
}

