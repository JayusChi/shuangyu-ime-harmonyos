impl ImeEngine {
    pub fn new(config: EngineConfig) -> Result<Self, EngineCreateError> {
        Self::new_with_query_config(config, QueryConfig::default())
    }

    /// Internal diagnostics/rollback constructor. Production callers use
    /// `new`; frozen baseline tooling can explicitly select legacy recall
    /// without changing the cross-language configuration.
    #[doc(hidden)]
    pub fn new_with_query_config(
        config: EngineConfig,
        mut query_config: QueryConfig,
    ) -> Result<Self, EngineCreateError> {
        if !config.quanpin_features.validate() || !config.quanpin_context_reranking.validate() {
            return Err(EngineCreateError::InvalidConfig);
        }
        query_config.default_page_size = query_config
            .normalize_page_size(config.candidate_page_size)
            .map_err(|_| EngineCreateError::InvalidConfig)?;
        let decode_limits = decoder_limits_for_scheme(&config.scheme_id);
        let (query_engine, sentence_decoder) = match config.lexicon_path.as_deref() {
            Some(path) if !path.trim().is_empty() => {
                let lexicon = Arc::new(load_lexicon(path)?);
                let query_engine =
                    CandidateQueryEngine::new_shared(Arc::clone(&lexicon), query_config.clone());
                let sentence_decoder = SentenceDecoder::new_shared(lexicon, decode_limits)
                    .map_err(|error| EngineCreateError::LexiconLoadFailed(error.to_string()))?;
                (Some(query_engine), Some(sentence_decoder))
            }
            _ => (None, None),
        };
        let reranker_lexicon_version = sentence_decoder
            .as_ref()
            .map(SentenceDecoder::lexicon_version);
        let quanpin_context_reranker = QuanpinContextReranker::new(
            &config.quanpin_context_reranking,
            reranker_lexicon_version,
        );
        let user_lexicon_path = config
            .user_lexicon_path
            .as_deref()
            .filter(|path| !path.trim().is_empty())
            .map(str::to_owned);
        let user_lexicon = Arc::new(
            user_lexicon_path
                .as_deref()
                .map(load_user_lexicon)
                .unwrap_or_default(),
        );
        // A pure Xiaohe handle must not read or validate an unrelated code-table
        // path. Code-table resources are loaded only for an explicitly selected
        // code-table scheme and then retained for an explicit switch back.
        let code_table_bundle = if matches!(
            config.scheme_id.as_str(),
            FIXTURE_SCHEME_ID | PRODUCTION_SCHEME_ID
        ) {
            let path = config
                .code_table_bundle_path
                .as_deref()
                .filter(|path| !path.trim().is_empty())
                .ok_or(EngineCreateError::CodeTableNotFound)?;
            Some(load_code_table_bundle_for_scheme(path, &config.scheme_id)?)
        } else {
            None
        };
        let mut code_table_action_table = None;
        let (parser, backend) = match config.scheme_id.as_str() {
            "xiaohe" | "quanpin" | "pinyin-9" => (
                Some(create_parser_for_scheme(&config.scheme_id)?),
                EngineBackend::Shuangpin,
            ),
            FIXTURE_SCHEME_ID | PRODUCTION_SCHEME_ID => {
                let bundle = code_table_bundle
                    .as_ref()
                    .ok_or(EngineCreateError::CodeTableNotFound)?;
                let default_categories = bundle.default_enabled_category_ids();
                let rules = code_table_rules(
                    bundle,
                    &config.scheme_id,
                    &user_lexicon,
                    &default_categories,
                );
                let state = CodeTableStateMachine::new_with_query_strategy(
                    Arc::clone(bundle),
                    query_config.default_page_size,
                    code_table_candidate_limit(&config.scheme_id, query_config.max_candidates),
                    rules,
                    code_table_query_strategy(&config.scheme_id),
                )
                .map_err(|error| EngineCreateError::CodeTableLoadFailed(error.to_string()))?;
                let mut state = state;
                if config.scheme_id == FIXTURE_SCHEME_ID {
                    match (
                        config.code_table_action_fixture_path.as_deref(),
                        config.code_table_action_fixture_sha256.as_deref(),
                    ) {
                        (Some(path), Some(hash)) if !path.trim().is_empty() => {
                            let table = FunctionalActionTable::load_fixture_file(path, hash)
                                .map_err(|error| {
                                    EngineCreateError::CodeTableLoadFailed(error.to_string())
                                })?;
                            let table = Arc::new(table);
                            state.set_action_table(Some(Arc::clone(&table)));
                            code_table_action_table = Some(table);
                        }
                        (None, None) => {}
                        _ => return Err(EngineCreateError::InvalidConfig),
                    }
                } else if config.code_table_action_fixture_path.is_some()
                    || config.code_table_action_fixture_sha256.is_some()
                {
                    return Err(EngineCreateError::InvalidConfig);
                } else {
                    let table = Arc::new(FunctionalActionTable::production_defaults());
                    state.set_action_table(Some(Arc::clone(&table)));
                    code_table_action_table = Some(table);
                }
                (None, EngineBackend::CodeTable(state))
            }
            other => return Err(create_parser_for_scheme(other).unwrap_err().into()),
        };
        let code_table_category_ids = match &backend {
            EngineBackend::CodeTable(machine) => machine
                .category_selection_snapshot()
                .enabled_category_ids()
                .to_vec(),
            EngineBackend::Shuangpin => code_table_bundle
                .as_ref()
                .map(|bundle| bundle.default_enabled_category_ids())
                .unwrap_or_default(),
        };
        if config.scheme_id == "xiaohe" {
            if let Some(decoder) = &sentence_decoder {
                decoder.prepare_initial_queries();
            }
        }
        if config.scheme_id == "pinyin-9" {
            if let Some(decoder) = &sentence_decoder {
                decoder.prepare_t9_joint();
            }
        }
        if config.scheme_id == "quanpin" {
            if let Some(query_engine) = &query_engine {
                query_engine.prepare_quanpin_indexes();
            }
        }
        Ok(Self {
            convenience: Default::default(),
            parser,
            scheme_id: config.scheme_id,
            backend,
            code_table_bundle,
            code_table_action_table,
            code_table_category_ids,
            query_engine,
            sentence_decoder,
            user_model: UserModel::default(),
            quanpin_context_reranker,
            user_lexicon_path,
            user_lexicon,
            session: CandidateSession::default(),
            query_config,
            quanpin_features: config.quanpin_features,
            quanpin_expansion_cache: VecDeque::with_capacity(QUANPIN_EXPANSION_CACHE_CAPACITY),
            last_quanpin_expansion_stats: QuanpinExpansionStats::default(),
            last_quanpin_reranking_stats: RerankStats::default(),
            t9_joint_limits: T9JointLimits::default(),
            t9_joint_session: T9JointSession::default(),
            t9_compatibility_decode_cache: VecDeque::new(),
            last_t9_joint_stats: T9JointDecoderStats::default(),
        })
    }

    pub fn version(&self) -> &str {
        ENGINE_VERSION_DIRECT_ACTIONS
    }

    pub fn scheme_id(&self) -> &str {
        &self.scheme_id
    }

    pub fn has_lexicon(&self) -> bool {
        match self.backend {
            EngineBackend::Shuangpin => self.query_engine.is_some(),
            EngineBackend::CodeTable(_) => true,
        }
    }

    pub fn quanpin_feature_config(&self) -> &QuanpinFeatureConfig {
        &self.quanpin_features
    }

    pub fn last_quanpin_expansion_stats(&self) -> QuanpinExpansionStats {
        self.last_quanpin_expansion_stats
    }

    pub fn quanpin_context_reranking_status(&self) -> QuanpinContextRerankingStatus {
        self.quanpin_context_reranker.status()
    }

    pub fn last_quanpin_reranking_stats(&self) -> RerankStats {
        self.last_quanpin_reranking_stats.clone()
    }

    pub fn t9_joint_limits(&self) -> &T9JointLimits {
        &self.t9_joint_limits
    }

    pub fn last_t9_joint_stats(&self) -> T9JointDecoderStats {
        self.last_t9_joint_stats.clone()
    }

    pub fn set_quanpin_feature_config(
        &mut self,
        config: QuanpinFeatureConfig,
    ) -> Result<(), EngineOperationError> {
        if self.scheme_id != "quanpin" || !config.validate() {
            return Err(EngineOperationError::InvalidArgument);
        }
        if self.quanpin_features != config {
            self.quanpin_expansion_cache.clear();
            self.quanpin_features = config;
        }
        self.last_quanpin_expansion_stats = QuanpinExpansionStats::default();
        Ok(())
    }

    pub fn reload_user_lexicon(&mut self) -> Result<CompositionResult, EngineOperationError> {
        let path = self
            .user_lexicon_path
            .as_deref()
            .ok_or(EngineOperationError::InvalidArgument)?;
        let report = load_snapshot_recovering(std::path::Path::new(path))
            .map_err(EngineOperationError::UserLexicon)?;
        if report.action == UserLexiconLoadAction::RecoveredEmpty {
            return Err(EngineOperationError::UserLexicon(UserLexiconError::new(
                path,
                0,
                UserLexiconField::Storage,
                UserLexiconReason::CorruptPrimaryAndBackup,
            )));
        }
        let external = Arc::new(report.snapshot);
        self.user_lexicon = Arc::clone(&external);
        match &mut self.backend {
            EngineBackend::CodeTable(machine) => {
                let bundle = self
                    .code_table_bundle
                    .as_ref()
                    .expect("code-table backend retains its validated bundle");
                machine.set_user_lexicon_snapshot(code_table_rules(
                    bundle,
                    &self.scheme_id,
                    &external,
                    &self.code_table_category_ids,
                ));
                Ok(code_table_result(machine))
            }
            EngineBackend::Shuangpin => {
                let current = self
                    .parser
                    .as_ref()
                    .expect("shuangpin parser")
                    .current_state();
                Ok(self.refresh_candidates(current))
            }
        }
    }

    pub fn code_table_category_config(
        &self,
    ) -> Result<Arc<CategorySelectionSnapshot>, EngineOperationError> {
        match &self.backend {
            EngineBackend::CodeTable(machine) => Ok(machine.category_selection_snapshot()),
            EngineBackend::Shuangpin => Err(EngineOperationError::UnsupportedOperation),
        }
    }

    pub fn set_code_table_categories(
        &mut self,
        category_ids: Vec<String>,
    ) -> Result<CompositionResult, EngineOperationError> {
        let bundle = self
            .code_table_bundle
            .as_ref()
            .cloned()
            .ok_or(EngineOperationError::UnsupportedOperation)?;
        let external = Arc::clone(&self.user_lexicon);
        let scheme_id = self.scheme_id.clone();
        let EngineBackend::CodeTable(machine) = &mut self.backend else {
            return Err(EngineOperationError::UnsupportedOperation);
        };
        if machine.set_enabled_categories(category_ids).is_err() {
            return Ok(code_table_failure(
                machine,
                ImeErrorCode::InvalidArgument,
                "category update rejected",
            ));
        }
        self.code_table_category_ids = machine
            .category_selection_snapshot()
            .enabled_category_ids()
            .to_vec();
        machine.set_user_lexicon_snapshot(code_table_rules(
            &bundle,
            &scheme_id,
            &external,
            &self.code_table_category_ids,
        ));
        Ok(code_table_result(machine))
    }

    pub fn set_code_table_commit_policy(
        &mut self,
        auto_commit_length: usize,
        empty_code_clear_length: usize,
    ) -> Result<CompositionResult, EngineOperationError> {
        let EngineBackend::CodeTable(machine) = &self.backend else {
            return Err(EngineOperationError::UnsupportedOperation);
        };
        self.configure_code_table_commit_policy(
            auto_commit_length,
            empty_code_clear_length,
            machine.commit_policy().reverse_split_enabled,
        )
    }

    pub fn configure_code_table_commit_policy(
        &mut self,
        auto_commit_length: usize,
        empty_code_clear_length: usize,
        reverse_split_enabled: bool,
    ) -> Result<CompositionResult, EngineOperationError> {
        let EngineBackend::CodeTable(machine) = &mut self.backend else {
            return Err(EngineOperationError::UnsupportedOperation);
        };
        let mut policy = match CodeTableCommitPolicy::new(
            auto_commit_length,
            CodeTableCommitPolicy::FROZEN_DEFAULT_LENGTH,
            empty_code_clear_length,
            64,
        ) {
            Ok(value) => value,
            Err(_) => {
                return Ok(code_table_failure(
                    machine,
                    ImeErrorCode::InvalidArgument,
                    "commit policy update rejected",
                ));
            }
        };
        policy.reverse_split_enabled = reverse_split_enabled;
        if machine.set_commit_policy(policy).is_err() {
            return Ok(code_table_failure(
                machine,
                ImeErrorCode::InvalidArgument,
                "commit policy update rejected",
            ));
        }
        Ok(code_table_result(machine))
    }

    pub fn change_scheme(
        &mut self,
        scheme_id: &str,
    ) -> Result<CompositionResult, shuangpin_parser::ParseError> {
        let (parser, backend) = match scheme_id {
            "xiaohe" | "quanpin" | "pinyin-9" => (
                Some(create_parser_for_scheme(scheme_id)?),
                EngineBackend::Shuangpin,
            ),
            FIXTURE_SCHEME_ID | PRODUCTION_SCHEME_ID => {
                let Some(bundle) = &self.code_table_bundle else {
                    return Err(shuangpin_parser::ParseError::Schema(
                        shuangpin_schema::SchemaError::SchemaNotFound {
                            id: scheme_id.to_owned(),
                        },
                    ));
                };
                if bundle.validate_scheme_identity(scheme_id).is_err() {
                    return Err(shuangpin_parser::ParseError::Schema(
                        shuangpin_schema::SchemaError::SchemaNotFound {
                            id: scheme_id.to_owned(),
                        },
                    ));
                }
                let rules = code_table_rules(
                    bundle,
                    scheme_id,
                    &self.user_lexicon,
                    &self.code_table_category_ids,
                );
                let mut state = CodeTableStateMachine::new_with_query_strategy(
                    Arc::clone(bundle),
                    self.query_config.default_page_size,
                    code_table_candidate_limit(scheme_id, self.query_config.max_candidates),
                    rules,
                    code_table_query_strategy(scheme_id),
                )
                .map_err(|_| {
                    shuangpin_parser::ParseError::Schema(
                        shuangpin_schema::SchemaError::SchemaNotFound {
                            id: scheme_id.to_owned(),
                        },
                    )
                })?;
                // The table is handle-owned and survives a temporary switch
                // to a phonetic scheme. Reattach it for both fixture and
                // production code-table backends; otherwise production guide
                // actions disappear after xiaohe-yinxing -> xiaohe ->
                // xiaohe-yinxing on the same native handle.
                state.set_action_table(self.code_table_action_table.clone());
                state
                    .set_enabled_categories(self.code_table_category_ids.clone())
                    .map_err(|_| {
                        shuangpin_parser::ParseError::Schema(
                            shuangpin_schema::SchemaError::SchemaNotFound {
                                id: scheme_id.to_owned(),
                            },
                        )
                    })?;
                (None, EngineBackend::CodeTable(state))
            }
            other => return Err(create_parser_for_scheme(other).unwrap_err()),
        };
        if let EngineBackend::CodeTable(machine) = &mut self.backend {
            machine.reset();
        }
        if let Some(current) = &mut self.parser {
            current.reset();
        }
        self.convenience.clear();
        self.parser = parser;
        self.backend = backend;
        self.scheme_id = scheme_id.to_owned();
        if let Some(decoder) = &mut self.sentence_decoder {
            decoder
                .set_limits(decoder_limits_for_scheme(scheme_id))
                .expect("built-in scheme decoder limits must remain valid");
        }
        if scheme_id == "xiaohe" {
            if let Some(decoder) = &self.sentence_decoder {
                decoder.prepare_initial_queries();
            }
        }
        if scheme_id == "pinyin-9" {
            if let Some(decoder) = &self.sentence_decoder {
                decoder.prepare_t9_joint();
            }
        }
        if scheme_id == "quanpin" {
            if let Some(query_engine) = &self.query_engine {
                query_engine.prepare_quanpin_indexes();
            }
        }
        self.session.clear();
        self.last_t9_joint_stats = T9JointDecoderStats::default();
        self.t9_joint_session.clear();
        self.t9_compatibility_decode_cache.clear();
        self.quanpin_context_reranker.clear_context();
        if let Some(query_engine) = &mut self.query_engine {
            query_engine.clear_cache();
        }
        Ok(self.current_state())
    }

    fn refresh_candidates(&mut self, result: ParseResult) -> CompositionResult {
        if self.is_phonetic_profile_command() {
            let table = FunctionalActionTable::production_defaults();
            let candidates = table
                .query_direct_exact_or_prefix("ofa")
                .iter()
                .map(|record| EngineCandidate {
                    id: record.id.clone(),
                    text: record.label.clone(),
                    reading: "ofa".to_owned(),
                    source: "functional".to_owned(),
                    consumed_raw_len: 3,
                    learning_key: None,
                    context_words: Vec::new(),
                })
                .collect();
            self.session
                .replace(candidates, self.query_config.default_page_size);
            return self.phonetic_profile_command().expect("profile command");
        }
        self.last_quanpin_expansion_stats = QuanpinExpansionStats::default();
        self.last_quanpin_reranking_stats = RerankStats::default();
        let expansion_result = result.clone();
        let base = self.refresh_candidates_without_quanpin_features(result);
        if self.scheme_id != "quanpin" || !self.quanpin_features.is_enabled() || !base.success {
            return base;
        }
        self.append_quanpin_feature_candidates(&expansion_result);
        self.to_composition_result(expansion_result)
    }

    fn refresh_candidates_without_quanpin_features(
        &mut self,
        result: ParseResult,
    ) -> CompositionResult {
        if self.scheme_id == "pinyin-9" {
            return self.refresh_t9_candidates(result);
        }
        if self.scheme_id == "quanpin" {
            self.session
                .retain_covered_by(raw_letter_count_without_boundaries(&result.raw_input));
            if let Some(output) = self.refresh_quanpin_lattice_candidates(&result) {
                return output;
            }
        }
        if self.scheme_id == "quanpin"
            && result.pending_code.is_empty()
            && !result.pinyin_combinations.is_empty()
        {
            return self.refresh_quanpin_path_candidates(result);
        }
        if result.query_intent == QueryIntent::MultiSyllable
            || (self.scheme_id == "xiaohe"
                && result.query_intent == QueryIntent::IncompleteSyllable
                && self
                    .parser
                    .as_ref()
                    .and_then(|parser| parser.xiaohe_pending_initial())
                    .is_some())
        {
            return self.refresh_sentence_candidates(result);
        }

        let Some(plan) = query_plan_for_parse_result(&result) else {
            if result.raw_input.is_empty() || self.scheme_id != "quanpin" {
                self.session.clear();
            }
            return self.to_composition_result(result);
        };
        if self.query_engine.is_none() {
            self.session.clear();
            return self.failure_from_parse(
                result,
                ImeErrorCode::EngineNotInitialized,
                "lexicon is not loaded",
            );
        }
        // Quanpin single-letter input must recall a bounded prefix pool
        // even when that letter is also a standalone reading (`n` -> 嗯/唔).
        // ExactOrPrefix intentionally stops at exact hits, which previously
        // made the later ranking adjustment ineffective and hid ni/na/neng.
        // Keep Xiaohe and every other query contract unchanged.
        let mode =
            if self.scheme_id == "quanpin" && result.query_intent == QueryIntent::SingleKeyPrefix {
                QueryMode::PrefixLexical
            } else {
                plan.mode
            };
        let query_output = {
            let query_engine = self.query_engine.as_mut().expect("checked above");
            let lexicon_version = query_engine.lexicon_version();
            let mut candidates = Vec::new();
            let mut page_size = self.query_config.default_page_size;
            let mut error = None;
            for reading in plan.readings {
                let request = QueryRequest::new(
                    self.scheme_id.clone(),
                    reading,
                    mode,
                    self.query_config.default_page_size,
                );
                match query_engine.query(request) {
                    Ok(mut query_result) => {
                        if self.scheme_id == "quanpin"
                            && result.query_intent == QueryIntent::SingleKeyPrefix
                            && result.pending_code.is_empty()
                        {
                            // `n` is both a standalone interjection reading and
                            // the initial of many common syllables. Full-pinyin
                            // keyboards should recall the broad prefix pool and
                            // rank the standalone `n` readings by frequency
                            // instead of pinning 嗯/唔 ahead of 你/那/能.
                            for candidate in &mut query_result.candidates {
                                if candidate.match_type == CandidateMatchType::Exact {
                                    candidate.match_type = CandidateMatchType::Prefix;
                                }
                            }
                        }
                        page_size = query_result.page_size;
                        candidates.extend(query_result.candidates);
                    }
                    Err(query_error) => {
                        error = Some(query_error);
                        break;
                    }
                }
            }
            error.map_or_else(
                || {
                    Ok((
                        deduplicate_candidates(candidates),
                        page_size,
                        lexicon_version,
                    ))
                },
                Err,
            )
        };
        match query_output {
            Ok((candidates, page_size, lexicon_version)) => {
                let consumed_raw_len = self
                    .parser
                    .as_ref()
                    .expect("phonetic parser")
                    .raw_input()
                    .chars()
                    .filter(|character| *character != '\'')
                    .count();
                let mut ranked = self.rank_lexicon_candidates(candidates, lexicon_version, mode);
                if matches!(mode, QueryMode::Prefix | QueryMode::PrefixLexical) {
                    ranked.truncate(self.query_config.prefix_snapshot_limit);
                } else {
                    ranked.truncate(self.query_config.max_candidates);
                }
                let candidates = ranked
                    .into_iter()
                    .map(|candidate| {
                        let learning_key = self.learning_key(
                            CandidateSourceKind::SystemLexicon,
                            lexicon_version,
                            &candidate.id,
                        );
                        EngineCandidate::from_ranking(candidate, consumed_raw_len, learning_key)
                    })
                    .collect::<Vec<_>>();
                let candidates = self.apply_user_lexicon(
                    candidates,
                    matches!(mode, QueryMode::Prefix | QueryMode::PrefixLexical),
                );
                if self.scheme_id == "quanpin" {
                    self.session.replace_if_nonempty(candidates, page_size);
                } else {
                    self.session.replace(candidates, page_size);
                }
                self.to_composition_result(result)
            }
            Err(error) => {
                let message = error.to_string();
                let code = match error {
                    candidate_query::QueryError::InvalidReading => ImeErrorCode::InvalidArgument,
                    candidate_query::QueryError::InvalidPageSize => ImeErrorCode::InvalidPage,
                };
                if self.scheme_id == "quanpin" && !result.raw_input.is_empty() {
                    self.to_composition_result(result)
                } else {
                    self.session.clear();
                    self.failure_from_parse(result, code, &message)
                }
            }
        }
    }

    fn append_quanpin_feature_candidates(&mut self, result: &ParseResult) {
        if self.query_engine.is_none() || self.sentence_decoder.is_none() {
            return;
        }
        let base = self
            .session
            .all_candidates()
            .iter()
            .filter(|candidate| !is_quanpin_feature_source(&candidate.source))
            .cloned()
            .collect::<Vec<_>>();
        let mut effective_config = self.quanpin_features.clone();
        let correction_skipped_high_confidence = effective_config.spelling_correction_enabled
            && has_high_confidence_quanpin_base(result, &base);
        let correction_deferred_incomplete = effective_config.spelling_correction_enabled
            && should_defer_correction_for_incomplete_prefix(result, &base);
        if correction_skipped_high_confidence || correction_deferred_incomplete {
            effective_config.spelling_correction_enabled = false;
        }
        let (paths, mut stats) =
            self.cached_quanpin_expansion_paths(&result.raw_input, &effective_config);
        stats.correction_skipped_high_confidence = correction_skipped_high_confidence;
        stats.correction_deferred_incomplete = correction_deferred_incomplete;
        if paths.is_empty() {
            self.session
                .replace_if_nonempty(base, self.query_config.default_page_size);
            self.last_quanpin_expansion_stats = stats;
            return;
        }

        let consumed_raw_len = raw_letter_count_without_boundaries(&result.raw_input);
        let high_confidence_base_count = base.len().min(3);
        let spelling_protected_base_count = if result.pending_code.is_empty()
            && matches!(
                result.status,
                ParseStatus::Complete | ParseStatus::Ambiguous
            ) {
            base.len().min(5)
        } else {
            high_confidence_base_count
        };
        let mut merged = base[..high_confidence_base_count].to_vec();
        let mut seen_text = merged
            .iter()
            .map(|candidate| candidate.text.clone())
            .collect::<BTreeSet<_>>();
        let mut expanded = Vec::new();
        let mut fuzzy_sentence_decodes = 0usize;
        let mut spelling_sentence_decodes = [0usize; 4];
        let mut combined_sentence_decodes = 0usize;
        for (path_index, path) in paths.into_iter().enumerate() {
            let tier = match path.kind {
                ExpansionKind::Fuzzy { changes: 1 } => 0usize,
                ExpansionKind::Fuzzy { .. } => 1,
                ExpansionKind::Spelling(_) => 2,
                ExpansionKind::SpellingAndFuzzy(_) => 3,
            };
            let spelling_kind_index = match path.kind {
                ExpansionKind::Spelling(kind) => Some(kind as usize),
                _ => None,
            };
            let allow_sentence_decode = match path.kind {
                ExpansionKind::Fuzzy { .. } => {
                    fuzzy_sentence_decodes < MAX_FUZZY_SENTENCE_DECODE_PATHS
                }
                ExpansionKind::Spelling(_) => {
                    spelling_sentence_decodes[spelling_kind_index.expect("spelling kind")]
                        < MAX_SENTENCE_DECODE_PATHS_BY_SPELLING_KIND
                            [spelling_kind_index.expect("spelling kind")]
                }
                ExpansionKind::SpellingAndFuzzy(_) => {
                    combined_sentence_decodes < MAX_COMBINED_SENTENCE_DECODE_PATHS
                }
            };
            let (candidates, used_sentence_decoder, decoder_budget_skipped) = self
                .candidates_for_quanpin_expansion(
                    &path.raw,
                    &path.syllables,
                    &path.source,
                    consumed_raw_len,
                    allow_sentence_decode,
                );
            stats.truncated_by_limit |= decoder_budget_skipped;
            if used_sentence_decoder {
                stats.sentence_decoder_paths += 1;
                match path.kind {
                    ExpansionKind::Fuzzy { .. } => fuzzy_sentence_decodes += 1,
                    ExpansionKind::Spelling(_) => {
                        spelling_sentence_decodes[spelling_kind_index.expect("spelling kind")] += 1
                    }
                    ExpansionKind::SpellingAndFuzzy(_) => combined_sentence_decodes += 1,
                }
            }
            stats.candidate_expansions += candidates.len();
            let single_letter_syllables = path
                .syllables
                .iter()
                .filter(|syllable| syllable.len() == 1)
                .count();
            let syllable_count = path.syllables.len();
            expanded.extend(candidates.into_iter().map(|(score, candidate)| {
                (
                    tier,
                    single_letter_syllables,
                    syllable_count,
                    score,
                    path_index,
                    candidate,
                )
            }));
        }
        expanded.sort_by(|left, right| {
            left.0
                .cmp(&right.0)
                .then_with(|| left.1.cmp(&right.1))
                .then_with(|| left.2.cmp(&right.2))
                .then_with(|| right.3.cmp(&left.3))
                .then_with(|| left.4.cmp(&right.4))
                .then_with(|| left.5.id.cmp(&right.5.id))
        });
        let (fuzzy, spelling): (Vec<_>, Vec<_>) =
            expanded.into_iter().partition(|candidate| candidate.0 <= 1);
        for (_, _, _, _, _, candidate) in fuzzy {
            merge_quanpin_candidate(&mut merged, &mut seen_text, candidate);
        }
        for candidate in base
            .iter()
            .skip(high_confidence_base_count)
            .take(spelling_protected_base_count - high_confidence_base_count)
        {
            if seen_text.insert(candidate.text.clone()) {
                merged.push(candidate.clone());
            }
        }
        for (_, _, _, _, _, candidate) in spelling {
            merge_quanpin_candidate(&mut merged, &mut seen_text, candidate);
        }
        for candidate in base.into_iter().skip(spelling_protected_base_count) {
            if merged.len() >= MAX_MERGED_CANDIDATES {
                stats.truncated_by_limit = true;
                break;
            }
            if seen_text.insert(candidate.text.clone()) {
                merged.push(candidate);
            }
        }
        self.session
            .replace_if_nonempty(merged, self.query_config.default_page_size);
        self.last_quanpin_expansion_stats = stats;
    }

    fn cached_quanpin_expansion_paths(
        &mut self,
        raw_input: &str,
        config: &QuanpinFeatureConfig,
    ) -> (
        Vec<crate::quanpin_features::ExpansionPath>,
        QuanpinExpansionStats,
    ) {
        if let Some(position) = self
            .quanpin_expansion_cache
            .iter()
            .position(|(raw, cached_config, _, _)| raw == raw_input && cached_config == config)
        {
            let entry = self
                .quanpin_expansion_cache
                .remove(position)
                .expect("cached quanpin expansion position");
            let mut stats = entry.3;
            stats.expansion_cache_hit = true;
            let paths = entry.2.clone();
            self.quanpin_expansion_cache.push_back(entry);
            return (paths, stats);
        }

        let (paths, stats) = expansion_paths(raw_input, config);
        if QUANPIN_EXPANSION_CACHE_CAPACITY > 0 {
            while self.quanpin_expansion_cache.len() >= QUANPIN_EXPANSION_CACHE_CAPACITY {
                self.quanpin_expansion_cache.pop_front();
            }
            self.quanpin_expansion_cache.push_back((
                raw_input.to_owned(),
                config.clone(),
                paths.clone(),
                stats,
            ));
        }
        (paths, stats)
    }

    fn candidates_for_quanpin_expansion(
        &mut self,
        corrected_raw: &str,
        syllables: &[String],
        source: &str,
        consumed_raw_len: usize,
        allow_sentence_decode: bool,
    ) -> (Vec<(i64, EngineCandidate)>, bool, bool) {
        let exact_reading = if syllables.len() == 1 {
            syllables[0].clone()
        } else {
            syllables.join(" ")
        };
        let exact = {
            let query_engine = self.query_engine.as_mut().expect("checked above");
            let lexicon_version = query_engine.lexicon_version();
            let request = QueryRequest::new(
                self.scheme_id.clone(),
                exact_reading,
                QueryMode::Exact,
                self.query_config.default_page_size,
            );
            let Ok(output) = query_engine.query(request) else {
                return (Vec::new(), false, false);
            };
            (output.candidates, lexicon_version)
        };
        if syllables.len() == 1 || !exact.0.is_empty() {
            return (
                self.rank_lexicon_candidates(exact.0, exact.1, QueryMode::Exact)
                    .into_iter()
                    .take(MAX_CANDIDATES_PER_EXPANSION_PATH)
                    .map(|candidate| {
                        let score = candidate.frequency.min(i64::MAX as u64) as i64;
                        let learning_key = self.learning_key(
                            CandidateSourceKind::SystemLexicon,
                            exact.1,
                            &candidate.id,
                        );
                        let mut candidate = EngineCandidate::from_ranking(
                            candidate,
                            consumed_raw_len,
                            learning_key,
                        );
                        candidate.source = source.to_owned();
                        (score, candidate)
                    })
                    .collect(),
                false,
                false,
            );
        }
        if !allow_sentence_decode {
            return (Vec::new(), false, true);
        }

        let decoder = self.sentence_decoder.as_ref().expect("checked above");
        let lexicon_version = decoder.lexicon_version();
        let Ok(decoded) =
            decoder.decode_with_user_scores(corrected_raw, syllables, "", |candidate| {
                self.user_score_for_sentence(candidate, lexicon_version)
            })
        else {
            return (Vec::new(), true, false);
        };
        let decoded_candidates = self.rerank_sentence_candidates(decoded.candidates);
        (
            decoded_candidates
                .into_iter()
                .take(MAX_CANDIDATES_PER_EXPANSION_PATH)
                .map(|candidate| {
                    let score = candidate.score;
                    let mut candidate =
                        self.engine_candidate_from_sentence(candidate, lexicon_version);
                    candidate.consumed_raw_len = consumed_raw_len;
                    candidate.source = source.to_owned();
                    (score, candidate)
                })
                .collect(),
            true,
            false,
        )
    }

    fn refresh_t9_candidates(&mut self, mut result: ParseResult) -> CompositionResult {
        self.session.clear();
        self.last_t9_joint_stats = T9JointDecoderStats::default();
        if result.raw_input.is_empty() || result.query_intent == QueryIntent::Invalid {
            return self.to_composition_result(result);
        }
        if self.query_engine.is_none() || self.sentence_decoder.is_none() {
            return self.failure_from_parse(
                result,
                ImeErrorCode::EngineNotInitialized,
                "lexicon is not loaded",
            );
        }

        let explicit_selection = self
            .parser
            .as_ref()
            .expect("phonetic parser")
            .has_explicit_pinyin_selection();
        let parser_generated_paths = self
            .parser
            .as_ref()
            .expect("phonetic parser")
            .t9_internal_combinations();
        let mut joint = T9JointDecodeResult::default();
        let mut ranked_internal_paths = parser_generated_paths.clone();
        if !explicit_selection {
            if let Ok(decoded) = self
                .sentence_decoder
                .as_ref()
                .expect("checked above")
                .update_t9_joint(
                    &mut self.t9_joint_session,
                    &result.raw_input,
                    &result.segment_boundaries,
                    &self.t9_joint_limits,
                )
            {
                joint = decoded;
            }
            let confident_promotions = joint
                .ranked_pinyin_paths
                .len()
                .min(self.t9_joint_limits.max_joint_public_promotions);
            ranked_internal_paths = merge_ranked_paths(
                &parser_generated_paths,
                &joint.ranked_pinyin_paths,
                T9_MAX_PINYIN_COMBINATIONS,
                confident_promotions,
            );
            result = self
                .parser
                .as_mut()
                .expect("phonetic parser")
                .publish_t9_joint_order(&ranked_internal_paths);
        }
        let parser_lattice_stats = self
            .parser
            .as_ref()
            .expect("phonetic parser")
            .t9_lattice_stats()
            .unwrap_or_default();
        self.last_t9_joint_stats = T9JointDecoderStats::merge(
            parser_lattice_stats,
            joint.stats.clone(),
            parser_generated_paths,
            joint.lexicon_reachable_paths.clone(),
            joint.beam_pruned_paths.clone(),
            ranked_internal_paths.clone(),
            &self.t9_joint_limits,
        );

        let mut combinations = vec![result.current_pinyin.clone()];
        if !explicit_selection {
            combinations.extend(result.pinyin_combinations.iter().cloned());
        }
        combinations.retain(|value| !value.is_empty());
        combinations.truncate(T9_MAX_PINYIN_COMBINATIONS);
        let raw_digit_count = result.raw_input.len();
        let incomplete = result.status == ParseStatus::Incomplete;
        // Tier is an explicit trust boundary: whole-word digit matches lead;
        // compact compatibility and lexicon-backed joint sentences then share
        // one calibrated score space. This lets language evidence beat a
        // parser-first over-segmentation without weakening whole-word recall.
        let mut scored = Vec::<(u8, i64, usize, EngineCandidate)>::new();
        let public_ranks = combinations
            .iter()
            .enumerate()
            .map(|(rank, path)| (path.clone(), rank))
            .collect::<BTreeMap<_, _>>();
        let fallback_path_limit = if explicit_selection {
            1
        } else if raw_digit_count <= self.t9_joint_limits.max_compatibility_decode_digits {
            self.t9_joint_limits.max_compatibility_decode_paths
        } else if incomplete || result.logical_syllable_count <= 1 {
            1
        } else {
            0
        };

        if !explicit_selection {
            let lexicon_version = self
                .sentence_decoder
                .as_ref()
                .expect("checked above")
                .lexicon_version();
            for candidate in joint.candidates {
                let tier = if candidate.words.len() == 1 {
                    T9_JOINT_WHOLE_WORD_TIER
                } else if is_compact_t9_joint_sentence(&candidate) {
                    T9_JOINT_SENTENCE_TIER
                } else {
                    T9_JOINT_SPECULATIVE_SENTENCE_TIER
                };
                let combination = candidate
                    .reading
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join("'");
                let combination_rank = public_ranks
                    .get(&combination)
                    .copied()
                    .unwrap_or(T9_MAX_PINYIN_COMBINATIONS);
                let score = candidate
                    .score
                    .saturating_add(T9_COMPLETE_COVERAGE_SCORE_BONUS)
                    .saturating_add(self.user_score_for_sentence(&candidate, lexicon_version));
                scored.push((
                    tier,
                    score,
                    combination_rank,
                    self.engine_candidate_from_sentence(candidate, lexicon_version),
                ));
            }
        }

        let fallback_combinations = combinations
            .into_iter()
            .take(fallback_path_limit)
            .collect::<Vec<_>>();
        for (combination_rank, combination) in fallback_combinations.into_iter().enumerate() {
            let cache_combination = combination.clone();
            let mut syllables = combination
                .split('\'')
                .filter(|value| !value.is_empty())
                .map(str::to_owned)
                .collect::<Vec<_>>();
            let pending = if incomplete {
                syllables.pop().unwrap_or_default()
            } else {
                String::new()
            };

            if syllables.is_empty() || (pending.is_empty() && syllables.len() == 1) {
                let reading = if syllables.is_empty() {
                    pending.clone()
                } else {
                    syllables[0].clone()
                };
                if reading.is_empty() {
                    continue;
                }
                let mode = if syllables.is_empty() {
                    QueryMode::Prefix
                } else {
                    QueryMode::Exact
                };
                let query_output = {
                    let query_engine = self.query_engine.as_mut().expect("checked above");
                    let lexicon_version = query_engine.lexicon_version();
                    let request = QueryRequest::new(
                        self.scheme_id.clone(),
                        reading,
                        mode,
                        self.query_config.default_page_size,
                    );
                    query_engine
                        .query(request)
                        .map(|output| (output.candidates, lexicon_version))
                };
                if let Ok((candidates, lexicon_version)) = query_output {
                    let mut ranked =
                        self.rank_lexicon_candidates(candidates, lexicon_version, mode);
                    ranked.truncate(self.query_config.max_candidates);
                    for candidate in ranked {
                        let learning_key = self.learning_key(
                            CandidateSourceKind::SystemLexicon,
                            lexicon_version,
                            &candidate.id,
                        );
                        let user_score = learning_key
                            .as_ref()
                            .map(|key| self.user_model.score(key))
                            .unwrap_or(0);
                        let score = (candidate.frequency.min(i64::MAX as u64) as i64)
                            .saturating_add(user_score)
                            .saturating_add(if pending.is_empty() {
                                T9_COMPLETE_COVERAGE_SCORE_BONUS
                            } else {
                                0
                            });
                        scored.push((
                            if explicit_selection {
                                T9_JOINT_WHOLE_WORD_TIER
                            } else {
                                T9_COMPATIBILITY_TIER
                            },
                            score,
                            combination_rank,
                            EngineCandidate::from_ranking(candidate, raw_digit_count, learning_key),
                        ));
                    }
                }
                continue;
            }

            let lexicon_version = self
                .sentence_decoder
                .as_ref()
                .expect("checked above")
                .lexicon_version();
            let cache_position = self.t9_compatibility_decode_cache.iter().position(|entry| {
                entry.incomplete == incomplete && entry.combination == cache_combination
            });
            let decoded_candidates = if let Some(position) = cache_position {
                // Keep recently reused paths at the back so an unusually long
                // composition evicts stale prefixes first.
                let entry = self
                    .t9_compatibility_decode_cache
                    .remove(position)
                    .expect("cache position came from the same deque");
                let candidates = entry.candidates.clone();
                self.t9_compatibility_decode_cache.push_back(entry);
                Some(candidates)
            } else {
                let decoded = self
                    .sentence_decoder
                    .as_ref()
                    .expect("checked above")
                    .decode_with_user_scores(&result.raw_input, &syllables, &pending, |candidate| {
                        self.user_score_for_sentence(candidate, lexicon_version)
                    })
                    .ok();
                decoded.map(|decoded| {
                    let candidates = decoded.candidates;
                    if self.t9_compatibility_decode_cache.len()
                        >= T9_COMPATIBILITY_DECODE_CACHE_CAPACITY
                    {
                        self.t9_compatibility_decode_cache.pop_front();
                    }
                    self.t9_compatibility_decode_cache
                        .push_back(T9CompatibilityDecodeCacheEntry {
                            combination: cache_combination,
                            incomplete,
                            candidates: candidates.clone(),
                        });
                    candidates
                })
            };
            if let Some(decoded_candidates) = decoded_candidates {
                scored.extend(decoded_candidates.into_iter().map(|candidate| {
                    let score = candidate
                        .score
                        .saturating_sub(t9_sentence_candidate_penalty(&candidate))
                        .saturating_add(if candidate.complete_coverage && pending.is_empty() {
                            T9_COMPLETE_COVERAGE_SCORE_BONUS
                        } else {
                            0
                        });
                    (
                        if explicit_selection {
                            T9_JOINT_SENTENCE_TIER
                        } else {
                            T9_COMPATIBILITY_TIER
                        },
                        score,
                        combination_rank,
                        self.engine_candidate_from_sentence(candidate, lexicon_version),
                    )
                }));
            }
        }

        scored.sort_by(|left, right| {
            right
                .0
                .cmp(&left.0)
                .then_with(|| right.1.cmp(&left.1))
                .then_with(|| left.2.cmp(&right.2))
                .then_with(|| left.3.text.cmp(&right.3.text))
                .then_with(|| left.3.reading.cmp(&right.3.reading))
                .then_with(|| left.3.id.cmp(&right.3.id))
        });
        let mut seen_text = BTreeSet::new();
        let mut candidates = scored
            .into_iter()
            .map(|(_, _, _, candidate)| candidate)
            .filter(|candidate| seen_text.insert(candidate.text.clone()))
            .take(T9_MAX_CANDIDATE_SNAPSHOT)
            .collect::<Vec<_>>();
        candidates = self.apply_user_lexicon(candidates, incomplete);
        candidates.truncate(T9_MAX_CANDIDATE_SNAPSHOT);
        self.session
            .replace(candidates, self.query_config.default_page_size);
        self.to_composition_result(result)
    }

    /// Adds the tolerant initial/full-pinyin lattice as a lower recall tier.
    /// The query engine excludes zero-cost exact paths, so exact full pinyin
    /// always stays owned by the normal exact/sentence decoder.
    fn refresh_quanpin_lattice_candidates(
        &mut self,
        result: &ParseResult,
    ) -> Option<CompositionResult> {
        if !matches!(
            result.status,
            ParseStatus::Invalid | ParseStatus::Incomplete
        ) {
            return None;
        }
        let query_engine = self.query_engine.as_ref()?;
        let recalled = query_engine
            .recall_quanpin_lattice(&result.raw_input, self.query_config.max_candidates);
        if recalled.is_empty() {
            return None;
        }
        let lexicon_version = query_engine.lexicon_version();
        let consumed_raw_len = raw_letter_count_without_boundaries(&result.raw_input);
        let candidates = recalled
            .into_iter()
            .map(|candidate| {
                let learning_key = self.learning_key(
                    CandidateSourceKind::SystemLexicon,
                    lexicon_version,
                    &candidate.id,
                );
                EngineCandidate::from_ranking(candidate, consumed_raw_len, learning_key)
            })
            .collect::<Vec<_>>();
        let candidates = self.apply_user_lexicon(candidates, true);
        self.session
            .replace_if_nonempty(candidates, self.query_config.default_page_size);
        Some(self.to_composition_result(result.clone()))
    }

    fn refresh_sentence_candidates(&mut self, result: ParseResult) -> CompositionResult {
        let syllable_paths = logical_syllable_reading_paths(&result);
        if syllable_paths.is_empty() {
            self.session.clear();
            return self.failure_from_parse(
                result,
                ImeErrorCode::InvalidArgument,
                "parsed sentence has an empty syllable slot",
            );
        }
        let Some(decoder) = &self.sentence_decoder else {
            self.session.clear();
            return self.failure_from_parse(
                result,
                ImeErrorCode::EngineNotInitialized,
                "lexicon is not loaded",
            );
        };

        let lexicon_version = decoder.lexicon_version();
        let mut decoded_any_path = false;
        let fixed_words = self.xiaohe_fixed_initial_words(&result);
        let mut first_error = None;
        let mut decoded_candidates = Vec::<(usize, SentenceCandidate)>::new();
        for (path_rank, mut syllables) in syllable_paths.into_iter().enumerate() {
            let mut initials = Vec::new();
            let mut raw_lengths = Vec::new();
            if self.scheme_id == "xiaohe" {
                for logical_index in 0..result.logical_syllable_count {
                    let parsed = result
                        .syllables
                        .iter()
                        .find(|s| s.logical_index == logical_index)
                        .expect("validated slot");
                    initials.push(parsed.raw_code.len() == 1 && parsed.final_part.is_empty());
                    raw_lengths.push(parsed.raw_code.len());
                }
                if let Some(initial) = self
                    .parser
                    .as_ref()
                    .and_then(|parser| parser.xiaohe_pending_initial())
                {
                    syllables.push(initial.to_owned());
                    initials.push(true);
                    raw_lengths.push(1);
                }
            }
            let uses_initials = initials.iter().any(|flag| *flag);
            let primary = if self.scheme_id == "xiaohe" {
                decoder.decode_xiaohe_with_user_scores(
                    XiaoheSentenceQuery {
                        raw_input: &result.raw_input,
                        syllables: &syllables,
                        initials: &initials,
                        raw_lengths: &raw_lengths,
                        fixed_words: &fixed_words,
                    },
                    |candidate| self.user_score_for_sentence(candidate, lexicon_version),
                )
            } else {
                decoder.decode_with_user_scores(
                    &result.raw_input,
                    &syllables,
                    &result.pending_code,
                    |candidate| self.user_score_for_sentence(candidate, lexicon_version),
                )
            };
            let decoded = if uses_initials
                || result.pending_code.is_empty()
                || primary
                    .as_ref()
                    .is_ok_and(|decoded| !decoded.candidates.is_empty())
            {
                primary
            } else {
                // The current tail may be merely incomplete or structurally
                // opaque. Query the stable parsed prefix as a second bounded
                // tier and retain its exact raw coverage.
                let stable_raw = syllables.concat();
                decoder.decode_with_user_scores(&stable_raw, &syllables, "", |candidate| {
                    self.user_score_for_sentence(candidate, lexicon_version)
                })
            };
            match decoded {
                Ok(decoded) => {
                    decoded_any_path = true;
                    decoded_candidates.extend(
                        decoded
                            .candidates
                            .into_iter()
                            .map(|candidate| (path_rank, candidate)),
                    );
                }
                Err(error) => {
                    if first_error.is_none() {
                        first_error = Some(error);
                    }
                }
            }
        }

        if decoded_any_path {
            // Compare candidates from every legal reading path with the
            // same score contract used inside one decoder invocation.
            // Schema order is only the stable tie-breaker; it no longer
            // suppresses a valid `luo ...` phrase behind the `lo ...`
            // reading of the same raw Xiaohe code.
            decoded_candidates.sort_by(|left, right| {
                let left_score = i128::from(left.1.score)
                    + i128::from(self.user_score_for_sentence(&left.1, lexicon_version));
                let right_score = i128::from(right.1.score)
                    + i128::from(self.user_score_for_sentence(&right.1, lexicon_version));
                right
                    .1
                    .complete_coverage
                    .cmp(&left.1.complete_coverage)
                    .then_with(|| right_score.cmp(&left_score))
                    .then_with(|| right.1.consumed_syllables.cmp(&left.1.consumed_syllables))
                    .then_with(|| left.0.cmp(&right.0))
                    .then_with(|| left.1.text.cmp(&right.1.text))
                    .then_with(|| left.1.reading.cmp(&right.1.reading))
                    .then_with(|| left.1.path_key.cmp(&right.1.path_key))
            });
            let mut seen_text = BTreeSet::new();
            let decoded_candidates = decoded_candidates
                .into_iter()
                .map(|(_, candidate)| candidate)
                .filter(|candidate| seen_text.insert(candidate.text.clone()))
                .take(self.query_config.max_candidates)
                .collect::<Vec<_>>();
            let mut candidates = self
                .rerank_sentence_candidates(decoded_candidates)
                .into_iter()
                .map(|candidate| self.engine_candidate_from_sentence(candidate, lexicon_version))
                .collect::<Vec<_>>();
            if self.scheme_id == "quanpin" {
                let raw_letter_count = raw_letter_count_without_boundaries(&result.raw_input);
                let mut exact =
                    self.quanpin_long_exact_candidates(&result.raw_input, raw_letter_count);
                exact.extend(candidates);
                let mut seen_text = BTreeSet::new();
                exact.retain(|candidate| seen_text.insert(candidate.text.clone()));
                candidates = exact;
            }
            let candidates = self.apply_user_lexicon(candidates, false);
            if self.scheme_id == "quanpin" {
                self.session
                    .replace_if_nonempty(candidates, self.query_config.default_page_size);
            } else {
                self.session
                    .replace(candidates, self.query_config.default_page_size);
            }
            self.to_composition_result(result)
        } else {
            let error = first_error.expect("at least one bounded sentence path was decoded");
            if self.scheme_id == "quanpin" {
                // Decoder budgets bound candidate work, not composition
                // ownership. Parsing and editing remain available and the
                // previous covered candidate snapshot stays intact.
                self.to_composition_result(result)
            } else {
                self.session.clear();
                self.failure_from_parse(result, ImeErrorCode::InvalidArgument, &error.to_string())
            }
        }
    }

    /// Decodes every bounded full-pinyin segmentation. Preferred-parser paths
    /// are appended first, while lexicon and sentence scores still order the
    /// candidates within each path. Stable text de-duplication prevents the
    /// same phrase from appearing once per legal segmentation.
    fn refresh_quanpin_path_candidates(&mut self, result: ParseResult) -> CompositionResult {
        if self.query_engine.is_none() || self.sentence_decoder.is_none() {
            self.session.clear();
            return self.failure_from_parse(
                result,
                ImeErrorCode::EngineNotInitialized,
                "lexicon is not loaded",
            );
        }

        let decode_path_limit = QUANPIN_MAX_DECODE_PATHS;
        let mut combinations = Vec::with_capacity(decode_path_limit);
        combinations.push(result.current_pinyin.clone());
        combinations.extend(
            result
                .pinyin_combinations
                .iter()
                .take(decode_path_limit.saturating_sub(1))
                .cloned(),
        );
        let raw_letter_count = result
            .raw_input
            .chars()
            .filter(|character| *character != '\'')
            .count();
        let mut exact_phrases = Vec::<EngineCandidate>::new();
        let mut combined = Vec::<EngineCandidate>::new();

        exact_phrases
            .extend(self.quanpin_long_exact_candidates(&result.raw_input, raw_letter_count));

        for combination in combinations {
            let syllables = combination
                .split('\'')
                .filter(|value| !value.is_empty())
                .map(str::to_owned)
                .collect::<Vec<_>>();
            if syllables.len() == 1 {
                let query_output = {
                    let query_engine = self.query_engine.as_mut().expect("checked above");
                    let lexicon_version = query_engine.lexicon_version();
                    let request = QueryRequest::new(
                        self.scheme_id.clone(),
                        syllables[0].clone(),
                        QueryMode::Exact,
                        self.query_config.default_page_size,
                    );
                    query_engine
                        .query(request)
                        .map(|output| (output.candidates, lexicon_version))
                };
                if let Ok((candidates, lexicon_version)) = query_output {
                    combined.extend(
                        self.rank_lexicon_candidates(candidates, lexicon_version, QueryMode::Exact)
                            .into_iter()
                            .take(self.query_config.max_candidates)
                            .map(|candidate| {
                                let learning_key = self.learning_key(
                                    CandidateSourceKind::SystemLexicon,
                                    lexicon_version,
                                    &candidate.id,
                                );
                                EngineCandidate::from_ranking(
                                    candidate,
                                    raw_letter_count,
                                    learning_key,
                                )
                            }),
                    );
                }
                continue;
            }

            let decoder = self.sentence_decoder.as_ref().expect("checked above");
            let lexicon_version = decoder.lexicon_version();
            if let Ok(decoded) =
                decoder.decode_with_user_scores(&result.raw_input, &syllables, "", |candidate| {
                    self.user_score_for_sentence(candidate, lexicon_version)
                })
            {
                combined.extend(
                    self.rerank_sentence_candidates(decoded.candidates)
                        .into_iter()
                        .map(|candidate| {
                            self.engine_candidate_from_sentence(candidate, lexicon_version)
                        }),
                );
            }
        }

        exact_phrases.extend(combined);
        let mut combined = exact_phrases;
        let mut seen_text = BTreeSet::new();
        combined.retain(|candidate| seen_text.insert(candidate.text.clone()));
        combined.truncate(self.query_config.max_candidates);
        let combined = self.apply_user_lexicon(combined, false);
        self.session
            .replace_if_nonempty(combined, self.query_config.default_page_size);
        self.to_composition_result(result)
    }

    fn engine_candidate_from_sentence(
        &self,
        candidate: SentenceCandidate,
        lexicon_version: u32,
    ) -> EngineCandidate {
        let has_fixed_word = candidate
            .source
            .split(',')
            .any(|source| source == "user-lexicon");
        let learning_key = if has_fixed_word {
            None
        } else {
            self.learning_key(
                CandidateSourceKind::SentencePath,
                lexicon_version,
                &candidate.id,
            )
        };
        let consumed_raw_len = if self.scheme_id == "quanpin" {
            candidate
                .reading
                .chars()
                .filter(|character| character.is_ascii_lowercase())
                .count()
        } else if self.scheme_id == "pinyin-9" {
            t9_digits_for_reading(&candidate.reading)
        } else {
            candidate.raw_end
        };
        EngineCandidate {
            id: candidate.id,
            text: candidate.text,
            reading: candidate.reading,
            source: candidate.source,
            consumed_raw_len,
            learning_key,
            context_words: if has_fixed_word {
                Vec::new()
            } else {
                candidate.words
            },
        }
    }

    fn quanpin_long_exact_candidates(
        &self,
        raw_input: &str,
        consumed_raw_len: usize,
    ) -> Vec<EngineCandidate> {
        let Some(query_engine) = self.query_engine.as_ref() else {
            return Vec::new();
        };
        let lexicon_version = query_engine.lexicon_version();
        let candidates =
            query_engine.recall_quanpin_long_exact(raw_input, QUANPIN_MAX_EXACT_PHRASE_CANDIDATES);
        self.rank_lexicon_candidates(candidates, lexicon_version, QueryMode::Exact)
            .into_iter()
            .take(QUANPIN_MAX_EXACT_PHRASE_CANDIDATES)
            .map(|candidate| {
                let learning_key = self.learning_key(
                    CandidateSourceKind::SystemLexicon,
                    lexicon_version,
                    &candidate.id,
                );
                EngineCandidate::from_ranking(candidate, consumed_raw_len, learning_key)
            })
            .collect()
    }

    /// Applies V2 only after the formal decoder has recalled and de-duplicated
    /// sentence paths. The re-ranker has no candidate-generation API and the
    /// returned path order is still converted through the existing stable-ID,
    /// user-rule, and pagination pipeline.
    fn rerank_sentence_candidates(
        &mut self,
        candidates: Vec<SentenceCandidate>,
    ) -> Vec<SentenceCandidate> {
        if self.scheme_id != "quanpin" {
            return candidates;
        }
        // A single key can expose several legal full-pinyin segmentations.
        // Only the preferred formal path is eligible for V2 so the advertised
        // candidate/query/time limits are hard per-key limits, not per path.
        if self.last_quanpin_reranking_stats.enabled {
            self.last_quanpin_reranking_stats.skipped_rerank_calls = self
                .last_quanpin_reranking_stats
                .skipped_rerank_calls
                .saturating_add(1);
            return candidates;
        }
        let (candidates, stats) = self.quanpin_context_reranker.rerank(candidates);
        self.last_quanpin_reranking_stats.add_assign(&stats);
        candidates
    }

    fn rank_lexicon_candidates(
        &self,
        candidates: Vec<RankingCandidate>,
        lexicon_version: u32,
        mode: QueryMode,
    ) -> Vec<RankingCandidate> {
        let user_score = |candidate: &RankingCandidate| {
            self.learning_key(
                CandidateSourceKind::SystemLexicon,
                lexicon_version,
                &candidate.id,
            )
            .map(|key| self.user_model.score(&key))
            .unwrap_or(0)
        };
        if mode == QueryMode::Prefix
            && self.query_config.prefix_recall_strategy == PrefixRecallStrategy::GlobalTopK
        {
            rank_prefix_candidates_with_user_scores(candidates, user_score)
        } else {
            rank_candidates_with_user_scores(candidates, user_score)
        }
    }
}

fn decoder_limits_for_scheme(scheme_id: &str) -> DecodeLimits {
    match scheme_id {
        "quanpin" => DecodeLimits {
            // Full-pinyin composition has no input-length cliff. Search work
            // remains bounded by the inherited graph and beam ceilings.
            max_raw_len: usize::MAX,
            max_syllables: usize::MAX,
            ..DecodeLimits::default()
        },
        "pinyin-9" => DecodeLimits {
            // Compatibility recall covers all 32 published pinyin paths, but
            // each contributes only a compact Top-4. The direct digit index
            // and joint beam own wider candidate recall.
            max_edges: 128,
            beam_width: 4,
            max_output_paths: 4,
            max_entries_per_key: 4,
            max_output_candidates: 4,
            ..DecodeLimits::default()
        },
        _ => DecodeLimits::default(),
    }
}

fn is_quanpin_feature_source(source: &str) -> bool {
    source.starts_with("quanpin-correction-") || source.starts_with("quanpin-fuzzy-")
}

/// Promotes only joint paths whose word segmentation is backed by multi-
/// syllable lexicon entries. Fragmented paths remain available for recall but
/// cannot replace a parser-backed candidate solely through a speculative joint
/// score. This distinction is T9-only because digit collisions make those
/// segmentations substantially more common than in full pinyin.
fn is_compact_t9_joint_sentence(candidate: &SentenceCandidate) -> bool {
    let syllable_count = candidate.reading.split_whitespace().count();
    syllable_count >= 2 && candidate.words.len().saturating_mul(2) <= syllable_count
}

/// Treats only a fully covered, compact top path as a confident exact result.
/// A typo that merely leaves a usable prefix snapshot or forces the decoder
/// through many one-syllable words stays eligible for spelling correction.
fn has_high_confidence_quanpin_base(result: &ParseResult, candidates: &[EngineCandidate]) -> bool {
    if !result.pending_code.is_empty()
        || !matches!(
            result.status,
            ParseStatus::Complete | ParseStatus::Ambiguous
        )
    {
        return false;
    }
    let raw_len = raw_letter_count_without_boundaries(&result.raw_input);
    let Some(top) = candidates.first().filter(|candidate| {
        candidate.consumed_raw_len == raw_len
            && candidate
                .reading
                .bytes()
                .filter(u8::is_ascii_lowercase)
                .count()
                == raw_len
    }) else {
        return false;
    };

    // Exact lexicon rows carry one context token and do not use sentence IDs.
    // For composed sentences, require the winning path to cover at least two
    // syllables per lexical token; noisy typo parses usually fragment into
    // short one-syllable edges and therefore remain low-confidence.
    if !top.id.starts_with("sentence:") {
        return true;
    }
    let syllable_count = top.reading.split_whitespace().count();
    syllable_count >= 2 && top.context_words.len().saturating_mul(2) <= syllable_count
}

/// A trailing legal syllable prefix (for example `nih` after `ni`) normally
/// means that the user is still typing, not that the composition needs typo
/// recovery. Keep the already covered prefix snapshot and wait until the tail
/// becomes complete or invalid before paying the correction cost.
fn should_defer_correction_for_incomplete_prefix(
    result: &ParseResult,
    candidates: &[EngineCandidate],
) -> bool {
    if result.status != ParseStatus::Incomplete
        || result.pending_code.len() != 1
        || candidates.is_empty()
    {
        return false;
    }
    all_syllables().any(|syllable| {
        syllable.len() > result.pending_code.len() && syllable.starts_with(&result.pending_code)
    })
}

fn merge_quanpin_candidate(
    merged: &mut Vec<EngineCandidate>,
    seen_text: &mut BTreeSet<String>,
    candidate: EngineCandidate,
) {
    if !seen_text.insert(candidate.text.clone()) {
        if let Some(existing) = merged
            .iter_mut()
            .find(|existing| existing.text == candidate.text)
        {
            if candidate.consumed_raw_len > existing.consumed_raw_len {
                *existing = candidate;
            }
        }
        return;
    }
    if merged.len() < MAX_MERGED_CANDIDATES {
        merged.push(candidate);
    }
}

fn raw_letter_count_without_boundaries(raw_input: &str) -> usize {
    raw_input.bytes().filter(|byte| *byte != b'\'').count()
}

fn code_table_rules(
    bundle: &CodeTableBundle,
    scheme_id: &str,
    external: &Arc<UserLexiconSnapshot>,
    enabled_category_ids: &[String],
) -> Arc<UserLexiconSnapshot> {
    // Every embedded rule carries its authoritative source category. Filter
    // that immutable layer by the active snapshot, then merge external user
    // rules, which intentionally have no category scope.
    if scheme_id == PRODUCTION_SCHEME_ID {
        let embedded = bundle
            .user_rules
            .as_ref()
            .expect("frozen production bundle includes validated user rules");
        let enabled_embedded = embedded.for_enabled_categories(enabled_category_ids);
        Arc::new(merge_user_lexicon_snapshots(&enabled_embedded, external))
    } else {
        Arc::clone(external)
    }
}

fn code_table_query_strategy(scheme_id: &str) -> CodeTableQueryStrategy {
    if scheme_id == PRODUCTION_SCHEME_ID {
        CodeTableQueryStrategy::DeterministicXiaoheYinxing
    } else {
        CodeTableQueryStrategy::ExactOrPrefixFallback
    }
}

fn code_table_candidate_limit(scheme_id: &str, default_limit: usize) -> usize {
    if scheme_id == PRODUCTION_SCHEME_ID {
        PROGRESSIVE_CODE_TABLE_MAX_CANDIDATES
    } else {
        default_limit
    }
}

fn remaining_raw_input(raw_input: &str, consumed_letters: usize) -> String {
    let mut letters_seen = 0usize;
    let mut remaining_start = raw_input.len();
    for (index, ch) in raw_input.char_indices() {
        if ch != '\'' {
            if letters_seen == consumed_letters {
                remaining_start = index;
                break;
            }
            letters_seen += 1;
        }
    }
    raw_input[remaining_start..]
        .trim_start_matches('\'')
        .to_owned()
}

fn load_lexicon(path: &str) -> Result<BinaryLexicon, EngineCreateError> {
    let bytes = fs::read(path).map_err(|error| {
        if error.kind() == ErrorKind::NotFound {
            EngineCreateError::LexiconNotFound
        } else {
            EngineCreateError::LexiconLoadFailed(error.kind().to_string())
        }
    })?;
    Ok(load_binary_lexicon(&bytes)?)
}

fn load_code_table_bundle(path: &str) -> Result<CodeTableBundle, EngineCreateError> {
    CodeTableBundle::load_file(path).map_err(|error| {
        if error.kind == CodeTableErrorKind::ResourceMissing {
            EngineCreateError::CodeTableNotFound
        } else {
            EngineCreateError::CodeTableLoadFailed(error.to_string())
        }
    })
}

fn load_code_table_bundle_for_scheme(
    path: &str,
    scheme_id: &str,
) -> Result<Arc<CodeTableBundle>, EngineCreateError> {
    let bundle = if scheme_id == PRODUCTION_SCHEME_ID {
        CodeTableBundle::load_frozen_production_file_shared(path).map_err(|error| {
            if error.kind == CodeTableErrorKind::ResourceMissing {
                EngineCreateError::CodeTableNotFound
            } else {
                EngineCreateError::CodeTableLoadFailed(error.to_string())
            }
        })?
    } else {
        Arc::new(load_code_table_bundle(path)?)
    };
    bundle
        .validate_scheme_identity(scheme_id)
        .map_err(|error| EngineCreateError::CodeTableLoadFailed(error.to_string()))?;
    Ok(bundle)
}

fn create_parser_for_scheme(
    scheme_id: &str,
) -> Result<PhoneticParserKind, shuangpin_parser::ParseError> {
    match scheme_id {
        "xiaohe" => PhoneticParserKind::xiaohe(),
        "quanpin" => Ok(PhoneticParserKind::quanpin()),
        "pinyin-9" => Ok(PhoneticParserKind::t9_pinyin()),
        _ => Err(shuangpin_parser::ParseError::Schema(
            shuangpin_schema::SchemaError::SchemaNotFound {
                id: scheme_id.to_owned(),
            },
        )),
    }
}

fn t9_digits_for_reading(reading: &str) -> usize {
    reading
        .split_whitespace()
        .filter_map(t9_signature)
        .map(|signature| signature.len())
        .sum()
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct LexiconQueryPlan {
    readings: Vec<String>,
    mode: QueryMode,
}

fn query_plan_for_parse_result(result: &ParseResult) -> Option<LexiconQueryPlan> {
    match result.query_intent {
        QueryIntent::SingleKeyPrefix => Some(LexiconQueryPlan {
            readings: vec![if result.pending_code.is_empty() {
                result.current_pinyin.clone()
            } else {
                result.pending_code.clone()
            }],
            mode: QueryMode::ExactOrPrefix,
        }),
        QueryIntent::CompleteSyllable => Some(LexiconQueryPlan {
            // One raw double-key code may have multiple legal readings. Treat
            // every schema-declared reading as exact and let the existing
            // deterministic ranking contract order their merged candidates.
            readings: result
                .syllables
                .iter()
                .map(|syllable| syllable.syllable.clone())
                .collect(),
            mode: QueryMode::ExactOrPrefix,
        }),
        QueryIntent::IncompleteSyllable => Some(LexiconQueryPlan {
            readings: logical_syllable_reading_paths(result)
                .into_iter()
                .map(|mut syllables| {
                    syllables.push(result.pending_code.clone());
                    syllables.join(" ")
                })
                .collect(),
            mode: QueryMode::ExactOrPrefix,
        }),
        QueryIntent::Empty | QueryIntent::MultiSyllable | QueryIntent::Invalid => None,
    }
}

fn logical_syllable_reading_paths(result: &ParseResult) -> Vec<Vec<String>> {
    let mut paths = vec![Vec::with_capacity(result.logical_syllable_count)];
    for logical_index in 0..result.logical_syllable_count {
        let alternatives = result
            .syllables
            .iter()
            .filter(|syllable| syllable.logical_index == logical_index)
            .map(|syllable| syllable.syllable.as_str())
            .collect::<Vec<_>>();
        if alternatives.is_empty() {
            return Vec::new();
        }

        let mut expanded = Vec::new();
        'paths: for path in &paths {
            for alternative in &alternatives {
                let mut next = path.clone();
                next.push((*alternative).to_owned());
                expanded.push(next);
                if expanded.len() >= SHUANGPIN_MAX_AMBIGUOUS_READING_PATHS {
                    break 'paths;
                }
            }
        }
        paths = expanded;
    }
    paths
}

fn to_formal_candidate(candidate: &EngineCandidate) -> FormalCandidate {
    FormalCandidate {
        id: candidate.id.clone(),
        text: candidate.text.clone(),
        display_text: String::new(),
        reading: candidate.reading.clone(),
        source: candidate.source.clone(),
        consumed_raw_len: candidate.consumed_raw_len.min(u32::MAX as usize) as u32,
    }
}

fn protocol_state(status: ParseStatus) -> ProtocolParserState {
    match status {
        ParseStatus::Empty => ProtocolParserState::Empty,
        ParseStatus::Incomplete => ProtocolParserState::Incomplete,
        ParseStatus::Complete => ProtocolParserState::Complete,
        ParseStatus::Invalid => ProtocolParserState::Invalid,
        ParseStatus::Ambiguous => ProtocolParserState::Ambiguous,
    }
}

fn build_preedit_text(parsed_syllables: &[String], pending_code: &str) -> String {
    let mut preedit = parsed_syllables.join("'");
    if !pending_code.is_empty() {
        if !preedit.is_empty() {
            preedit.push('\'');
        }
        preedit.push_str(pending_code);
    }
    preedit
}
