#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    use lexicon_core::{build_binary_lexicon, LexiconEntry};

    use super::*;

    fn create_test_lexicon() -> PathBuf {
        let entries = vec![
            LexiconEntry::new(
                "你".to_owned(),
                "ni".to_owned(),
                vec!["ni".to_owned()],
                100_000,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "你好".to_owned(),
                "ni hao".to_owned(),
                vec!["ni".to_owned(), "hao".to_owned()],
                72_000,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "输入".to_owned(),
                "shu ru".to_owned(),
                vec!["shu".to_owned(), "ru".to_owned()],
                82_000,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "输入法".to_owned(),
                "shu ru fa".to_owned(),
                vec!["shu".to_owned(), "ru".to_owned(), "fa".to_owned()],
                81_000,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "其间".to_owned(),
                "qi jian".to_owned(),
                vec!["qi".to_owned(), "jian".to_owned()],
                49_000,
                vec!["stage7".to_owned()],
            ),
            LexiconEntry::new(
                "期间".to_owned(),
                "qi jian".to_owned(),
                vec!["qi".to_owned(), "jian".to_owned()],
                50_000,
                vec!["stage7".to_owned()],
            ),
        ];
        let bytes = build_binary_lexicon(&entries, 7, 1).unwrap();
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("stage7-ime-engine-{nanos}.lex"));
        fs::write(&path, bytes).unwrap();
        path
    }

    fn create_engine() -> ImeEngine {
        let path = create_test_lexicon();
        ImeEngine::new(EngineConfig {
            scheme_id: "xiaohe".to_owned(),
            lexicon_path: Some(path.to_string_lossy().into_owned()),
            code_table_bundle_path: None,
            user_lexicon_path: None,
            code_table_action_fixture_path: None,
            code_table_action_fixture_sha256: None,
            candidate_page_size: 1,
            quanpin_features: QuanpinFeatureConfig::default(),
            quanpin_context_reranking: QuanpinContextRerankingConfig::default(),
        })
        .unwrap()
    }

    fn create_stage8_engine(page_size: usize) -> ImeEngine {
        let entries = vec![
            stage8_entry("你", "ni", 100_000),
            stage8_entry("好", "hao", 95_000),
            stage8_entry("你好", "ni hao", 120_000),
            stage8_entry("法", "fa", 80_000),
            stage8_entry("输入", "shu ru", 82_000),
            stage8_entry("输入法", "shu ru fa", 90_000),
            stage8_entry("小鹤", "xiao he", 85_000),
            stage8_entry("双拼", "shuang pin", 84_000),
            stage8_entry("小鹤双拼", "xiao he shuang pin", 88_000),
            stage8_entry("期间", "qi jian", 70_000),
            stage8_entry("其间", "qi jian", 70_000),
        ];
        let bytes = build_binary_lexicon(&entries, 8, 1).unwrap();
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("stage8-ime-engine-{nanos}.lex"));
        fs::write(&path, bytes).unwrap();
        ImeEngine::new(EngineConfig {
            scheme_id: "xiaohe".to_owned(),
            lexicon_path: Some(path.to_string_lossy().into_owned()),
            code_table_bundle_path: None,
            user_lexicon_path: None,
            code_table_action_fixture_path: None,
            code_table_action_fixture_sha256: None,
            candidate_page_size: page_size,
            quanpin_features: QuanpinFeatureConfig::default(),
            quanpin_context_reranking: QuanpinContextRerankingConfig::default(),
        })
        .unwrap()
    }

    fn create_candidate_stage4_contract_engine(page_size: usize) -> ImeEngine {
        let entries = vec![
            stage8_entry("和", "he", 100_000),
            stage8_entry("好", "hao", 99_000),
            stage8_entry("航", "hang", 98_000),
            stage8_entry("昂", "ang", 97_000),
            stage8_entry("安", "an", 96_000),
            stage8_entry("哦", "o", 95_000),
            stage8_entry("欧", "ou", 94_000),
            stage8_entry("咯", "lo", 93_000),
            stage8_entry("罗", "luo", 92_000),
            stage8_entry("咯你", "lo ni", 91_500),
            stage8_entry("罗你", "luo ni", 91_400),
            stage8_entry("落后", "luo hou", 91_300),
            stage8_entry("你", "ni", 91_000),
            stage8_entry("是", "shi", 90_000),
            stage8_entry("知", "zhi", 89_000),
            stage8_entry("你好", "ni hao", 88_000),
            stage8_entry("你很", "ni hen", 87_000),
        ];
        create_learning_engine(page_size, entries)
    }

    fn create_learning_engine(page_size: usize, entries: Vec<LexiconEntry>) -> ImeEngine {
        let bytes = build_binary_lexicon(&entries, 9, 1).unwrap();
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("stage9-ime-engine-{nanos}.lex"));
        fs::write(&path, bytes).unwrap();
        ImeEngine::new(EngineConfig {
            scheme_id: "xiaohe".to_owned(),
            lexicon_path: Some(path.to_string_lossy().into_owned()),
            code_table_bundle_path: None,
            user_lexicon_path: None,
            code_table_action_fixture_path: None,
            code_table_action_fixture_sha256: None,
            candidate_page_size: page_size,
            quanpin_features: QuanpinFeatureConfig::default(),
            quanpin_context_reranking: QuanpinContextRerankingConfig::default(),
        })
        .unwrap()
    }

    fn create_close_ni_learning_engine() -> ImeEngine {
        create_learning_engine(
            5,
            vec![
                stage8_entry("你", "ni", 10_000),
                stage8_entry("泥", "ni", 9_000),
            ],
        )
    }

    fn create_stage3_prefix_engine(page_size: usize) -> ImeEngine {
        let entries = (0..150)
            .map(|index| {
                stage8_entry(
                    &format!("候选{index:03}"),
                    "ni",
                    10_000u64.saturating_sub(index),
                )
            })
            .collect();
        create_learning_engine(page_size, entries)
    }

    fn stage9_model_path(name: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("stage9-{name}-{nanos}.dat"))
    }

    fn stage8_entry(word: &str, pinyin: &str, frequency: u64) -> LexiconEntry {
        LexiconEntry::new(
            word.to_owned(),
            pinyin.to_owned(),
            pinyin.split(' ').map(str::to_owned).collect(),
            frequency,
            vec!["stage8".to_owned()],
        )
    }

    #[test]
    fn creates_default_xiaohe_engine() {
        let engine = ImeEngine::new(EngineConfig::default()).unwrap();
        assert_eq!(engine.scheme_id(), "xiaohe");
        assert_eq!(engine.version(), ENGINE_VERSION_DIRECT_ACTIONS);
        assert_eq!(
            engine.current_state().parser_state,
            ProtocolParserState::Empty
        );
    }

    #[test]
    fn pinyin9_learning_keys_are_isolated_from_other_schemes() {
        let mut engine = create_engine();
        engine.change_scheme("pinyin-9").unwrap();
        let pinyin9 = engine
            .learning_key(CandidateSourceKind::SystemLexicon, 1, "stable-candidate")
            .unwrap();

        engine.change_scheme("quanpin").unwrap();
        let quanpin = engine
            .learning_key(CandidateSourceKind::SystemLexicon, 1, "stable-candidate")
            .unwrap();

        assert_eq!(pinyin9.scheme_id, "pinyin-9");
        assert_eq!(quanpin.scheme_id, "quanpin");
        assert_ne!(pinyin9, quanpin);
    }

    #[test]
    fn scheme_switch_updates_sentence_decoder_limits_deterministically() {
        let mut engine = create_engine();
        assert_eq!(
            engine.sentence_decoder.as_ref().unwrap().limits(),
            &decoder_limits_for_scheme("xiaohe")
        );

        engine.change_scheme("pinyin-9").unwrap();
        assert_eq!(
            engine.sentence_decoder.as_ref().unwrap().limits(),
            &decoder_limits_for_scheme("pinyin-9")
        );

        engine.change_scheme("quanpin").unwrap();
        assert_eq!(
            engine.sentence_decoder.as_ref().unwrap().limits(),
            &decoder_limits_for_scheme("quanpin")
        );

        engine.change_scheme("xiaohe").unwrap();
        assert_eq!(
            engine.sentence_decoder.as_ref().unwrap().limits(),
            &decoder_limits_for_scheme("xiaohe")
        );
    }

    #[test]
    fn pinyin9_compatibility_cache_is_bounded_and_invalidated_with_user_scores() {
        let mut engine = create_stage8_engine(5);
        engine.change_scheme("pinyin-9").unwrap();
        for digit in "64426".chars() {
            engine.process_key(digit);
        }

        assert!(!engine.t9_compatibility_decode_cache.is_empty());
        assert!(
            engine.t9_compatibility_decode_cache.len()
                <= T9_COMPATIBILITY_DECODE_CACHE_CAPACITY
        );

        engine.set_user_learning_enabled(false);
        assert!(engine.t9_compatibility_decode_cache.is_empty());
    }

    #[test]
    fn pinyin9_candidate_selection_reuses_the_existing_user_model() {
        let mut engine = create_close_ni_learning_engine();
        engine.change_scheme("pinyin-9").unwrap();
        engine.process_key('6');
        let initial = engine.process_key('4');
        assert_eq!(initial.candidates[0].text, "你");
        assert_eq!(initial.candidates[1].text, "泥");

        engine.select_candidate(1).unwrap();
        engine.process_key('6');
        let learned = engine.process_key('4');

        assert_eq!(learned.candidates[0].text, "泥");
    }

    #[test]
    fn loads_lexicon_at_create_time() {
        let path = create_test_lexicon();
        let engine = ImeEngine::new(EngineConfig {
            scheme_id: "xiaohe".to_owned(),
            lexicon_path: Some(path.to_string_lossy().into_owned()),
            code_table_bundle_path: None,
            user_lexicon_path: None,
            code_table_action_fixture_path: None,
            code_table_action_fixture_sha256: None,
            candidate_page_size: 5,
            quanpin_features: QuanpinFeatureConfig::default(),
            quanpin_context_reranking: QuanpinContextRerankingConfig::default(),
        })
        .unwrap();

        assert!(engine.has_lexicon());
    }

    #[test]
    fn invalid_lexicon_path_returns_structured_error() {
        let error = ImeEngine::new(EngineConfig {
            scheme_id: "xiaohe".to_owned(),
            lexicon_path: Some("missing-stage7.lex".to_owned()),
            code_table_bundle_path: None,
            user_lexicon_path: None,
            code_table_action_fixture_path: None,
            code_table_action_fixture_sha256: None,
            candidate_page_size: 5,
            quanpin_features: QuanpinFeatureConfig::default(),
            quanpin_context_reranking: QuanpinContextRerankingConfig::default(),
        })
        .unwrap_err();

        assert!(matches!(error, EngineCreateError::LexiconNotFound));
        assert_eq!(error.code(), ImeErrorCode::LexiconNotFound);
    }

    #[test]
    fn processes_complete_key_and_returns_candidates() {
        let mut engine = create_engine();
        engine.process_key('n');
        let complete = engine.process_key('i');

        assert_eq!(complete.parser_state, ProtocolParserState::Complete);
        assert_eq!(complete.parsed_syllables, vec!["ni".to_owned()]);
        assert_eq!(complete.display_segments, vec!["ni".to_owned()]);
        assert_eq!(complete.current_pinyin, "ni");
        assert!(complete.pinyin_combinations.is_empty());
        assert_eq!(complete.candidates[0].text, "你");
        assert_eq!(complete.highlighted_index, 0);
    }

    #[test]
    fn processes_continuous_input_for_existing_word() {
        let mut engine = create_engine();
        for key in "nihc".chars() {
            engine.process_key(key);
        }
        let complete = engine.current_state();

        assert_eq!(
            complete.parsed_syllables,
            vec!["ni".to_owned(), "hao".to_owned()]
        );
        assert_eq!(complete.display_segments, vec!["ni", "hc"]);
        assert_eq!(complete.current_pinyin, "ni'hao");
        assert_eq!(complete.candidates[0].text, "你好");
    }

    #[test]
    fn prefix_query_for_incomplete_code_returns_candidates() {
        let mut engine = create_engine();
        let incomplete = engine.process_key('n');

        assert_eq!(incomplete.parser_state, ProtocolParserState::Incomplete);
        assert_eq!(incomplete.candidates[0].text, "你");
        assert!(incomplete.has_next_page);
    }

    #[test]
    fn candidate_stage4_single_keys_use_only_pinyin_prefix_semantics() {
        let mut engine = create_candidate_stage4_contract_engine(8);
        let h = engine.process_key('h');
        let h_readings = h
            .candidates
            .iter()
            .map(|candidate| candidate.reading.as_str())
            .collect::<Vec<_>>();
        assert!(h_readings.iter().all(|reading| reading.starts_with('h')));
        assert!(h_readings.contains(&"he"));
        assert!(h_readings.contains(&"hao"));
        assert!(h_readings.contains(&"hang"));
        assert!(!h.candidates.iter().any(|candidate| candidate.text == "昂"));

        let first_h = h.candidates;
        let empty = engine.backspace();
        assert!(empty.candidates.is_empty());
        let cached_h = engine.process_key('h');
        assert_eq!(cached_h.candidates, first_h);

        engine.reset();
        let a = engine.process_key('a');
        assert!(a
            .candidates
            .iter()
            .all(|candidate| candidate.reading.starts_with('a')));
        assert!(a.candidates.iter().any(|candidate| candidate.text == "安"));
        assert!(a.candidates.iter().any(|candidate| candidate.text == "昂"));

        engine.reset();
        let o = engine.process_key('o');
        assert!(o
            .candidates
            .iter()
            .all(|candidate| candidate.reading.starts_with('o')));
        assert!(o.candidates.iter().any(|candidate| candidate.text == "哦"));
        // ExactOrPrefix mode: if "o" has exact matches, only show exact;
        // otherwise show prefix matches. "欧" is "ou" (prefix), not "o" (exact).
        // Since "哦" exists as exact "o", "欧" won't appear.
    }

    #[test]
    fn candidate_stage4_complete_codes_use_exact_queries() {
        for (code, reading) in [("hc", "hao"), ("ni", "ni"), ("ui", "shi"), ("vi", "zhi")] {
            let mut engine = create_candidate_stage4_contract_engine(8);
            let mut result = CompositionResult::interface_error(ImeErrorCode::InvalidArgument);
            for key in code.chars() {
                result = engine.process_key(key);
            }
            assert_eq!(result.parser_state, ProtocolParserState::Complete);
            assert_eq!(result.parsed_syllables, vec![reading.to_owned()]);
            assert!(!result.candidates.is_empty(), "code={code}");
            // ExactOrPrefix mode: complete codes with exact matches show only exact matches
            assert!(
                result
                    .candidates
                    .iter()
                    .all(|candidate| candidate.reading == reading),
                "code={code}"
            );
        }
    }

    #[test]
    fn candidate_stage4_ambiguous_complete_code_merges_exact_readings() {
        let mut engine = create_candidate_stage4_contract_engine(8);
        let result = engine.process_key('l');
        assert_eq!(result.parser_state, ProtocolParserState::Incomplete);
        let result = engine.process_key('o');

        assert_eq!(result.parser_state, ProtocolParserState::Ambiguous);
        assert_eq!(
            result.parsed_syllables,
            vec!["lo".to_owned(), "luo".to_owned()]
        );
        assert_eq!(
            result
                .candidates
                .iter()
                .map(|candidate| candidate.reading.as_str())
                .collect::<std::collections::BTreeSet<_>>(),
            std::collections::BTreeSet::from(["lo", "luo"])
        );
    }

    #[test]
    fn candidate_stage4_ambiguous_sentence_keeps_every_legal_reading_path() {
        let mut engine = create_candidate_stage4_contract_engine(8);
        let mut result = CompositionResult::interface_error(ImeErrorCode::InvalidArgument);
        for key in "loni".chars() {
            result = engine.process_key(key);
        }

        assert_eq!(result.parser_state, ProtocolParserState::Ambiguous);
        assert_eq!(result.candidates[0].text, "咯你");
        assert_eq!(result.candidates[0].reading, "lo ni");
        assert!(result
            .candidates
            .iter()
            .any(|candidate| candidate.reading == "luo ni"));
    }

    #[test]
    fn candidate_stage4_ambiguous_reading_survives_incomplete_and_complete_tail() {
        let mut engine = create_candidate_stage4_contract_engine(8);
        let mut incomplete = CompositionResult::interface_error(ImeErrorCode::InvalidArgument);
        for key in "loh".chars() {
            incomplete = engine.process_key(key);
        }
        assert_eq!(incomplete.parser_state, ProtocolParserState::Incomplete);
        assert!(incomplete
            .candidates
            .iter()
            .any(|candidate| candidate.text == "落后" && candidate.reading == "luo hou"));

        let complete = engine.process_key('z');
        assert_eq!(complete.parser_state, ProtocolParserState::Ambiguous);
        assert!(complete
            .candidates
            .iter()
            .any(|candidate| candidate.text == "落后" && candidate.reading == "luo hou"));
    }

    #[test]
    fn candidate_stage4_input_and_backspace_reset_mode_page_and_snapshot() {
        let mut engine = create_candidate_stage4_contract_engine(2);
        let h = engine.process_key('h');
        assert!(h.has_next_page);
        assert_eq!(engine.next_candidate_page().unwrap().candidate_page, 1);

        let exact = engine.process_key('c');
        assert_eq!(exact.raw_input, "hc");
        assert_eq!(exact.candidate_page, 0);
        assert!(!exact.has_previous_page);
        assert!(exact
            .candidates
            .iter()
            .all(|candidate| candidate.reading == "hao"));

        engine.reset();
        let mut sentence = CompositionResult::interface_error(ImeErrorCode::InvalidArgument);
        for key in "nihc".chars() {
            sentence = engine.process_key(key);
        }
        assert_eq!(sentence.candidates[0].text, "你好");

        let incomplete = engine.backspace();
        assert_eq!(incomplete.raw_input, "nih");
        assert_eq!(incomplete.candidate_page, 0);
        assert!(incomplete
            .candidates
            .iter()
            .all(|candidate| candidate.reading.starts_with("ni h")));

        let complete = engine.backspace();
        assert_eq!(complete.raw_input, "ni");
        assert!(complete
            .candidates
            .iter()
            .all(|candidate| candidate.reading == "ni"));

        let single = engine.backspace();
        assert_eq!(single.raw_input, "n");
        assert!(single
            .candidates
            .iter()
            .all(|candidate| candidate.reading.starts_with('n')));

        let empty = engine.backspace();
        assert_eq!(empty.raw_input, "");
        assert!(empty.candidates.is_empty());
        assert_eq!(empty.candidate_page, 0);
        assert!(!empty.has_previous_page);
        assert!(!empty.has_next_page);
    }

    #[test]
    fn stage3_prefix_snapshot_and_exact_return_all_150_candidates() {
        let mut engine = create_stage3_prefix_engine(50);
        let first = engine.process_key('n');
        let mut prefix_texts = first
            .candidates
            .iter()
            .map(|candidate| candidate.text.clone())
            .collect::<Vec<_>>();
        let mut page = first;
        while page.has_next_page {
            page = engine.next_candidate_page().unwrap();
            prefix_texts.extend(
                page.candidates
                    .iter()
                    .map(|candidate| candidate.text.clone()),
            );
        }
        assert_eq!(prefix_texts.len(), 150);
        assert_eq!(
            prefix_texts
                .iter()
                .collect::<std::collections::BTreeSet<_>>()
                .len(),
            150
        );

        engine.reset();
        engine.process_key('n');
        let mut exact = engine.process_key('i');
        let mut exact_count = exact.candidates.len();
        while exact.has_next_page {
            exact = engine.next_candidate_page().unwrap();
            exact_count += exact.candidates.len();
        }
        assert_eq!(exact_count, 150);
    }

    #[test]
    fn stage3_user_learning_reorders_the_global_prefix_pool_before_snapshot() {
        let mut engine = create_stage3_prefix_engine(50);
        let learned_id = "lex-v9-ni-候选140";
        let key = engine
            .learning_key(CandidateSourceKind::SystemLexicon, 9, learned_id)
            .unwrap();
        assert!(engine.user_model.record_selection(key));

        let result = engine.process_key('n');

        assert_eq!(result.candidates[0].text, "候选140");
    }

    #[test]
    fn invalid_sequence_is_a_successful_composition_result_without_candidates() {
        let mut engine = create_engine();
        engine.process_key('q');
        let result = engine.process_key('g');
        assert!(result.success);
        assert_eq!(result.error_code.as_i32(), 0);
        assert_eq!(result.parser_state, ProtocolParserState::Invalid);
        assert!(result.candidates.is_empty());
    }

    #[test]
    fn backspace_updates_candidates_and_returns_first_page() {
        let mut engine = create_engine();
        engine.process_key('n');
        engine.process_key('i');
        let after_backspace = engine.backspace();

        assert_eq!(
            after_backspace.parser_state,
            ProtocolParserState::Incomplete
        );
        assert_eq!(after_backspace.raw_input, "n");
        assert_eq!(after_backspace.candidate_page, 0);
        assert_eq!(after_backspace.candidates[0].text, "你");
    }

    #[test]
    fn explicit_segment_boundary_requeries_and_backspace_restores_candidates() {
        let mut engine = create_engine();
        engine.process_key('n');
        let before = engine.process_key('i');
        let before_candidates = before
            .candidates
            .iter()
            .map(|candidate| candidate.text.clone())
            .collect::<Vec<_>>();

        let segmented = engine.insert_segment_boundary().unwrap();
        assert_eq!(segmented.raw_input, "ni'");
        assert_eq!(segmented.segment_boundaries, vec![2]);
        assert_eq!(
            segmented
                .candidates
                .iter()
                .map(|candidate| candidate.text.clone())
                .collect::<Vec<_>>(),
            before_candidates
        );

        let restored = engine.backspace();
        assert_eq!(restored.raw_input, "ni");
        assert!(restored.segment_boundaries.is_empty());
        assert_eq!(restored.candidates[0].text, before.candidates[0].text);
    }

    #[test]
    fn invalid_segment_boundary_preserves_composition() {
        let mut engine = create_engine();
        engine.process_key('n');
        let before = engine.current_state();
        assert_eq!(
            engine.insert_segment_boundary(),
            Err(EngineOperationError::InvalidArgument)
        );
        assert_eq!(engine.current_state(), before);
    }

    #[test]
    fn partial_candidate_commit_consumes_boundary_without_leaking_it() {
        let mut engine = create_stage8_engine(9);
        for key in "uuru".chars() {
            engine.process_key(key);
        }
        engine.insert_segment_boundary().unwrap();
        engine.process_key('f');
        let composed = engine.process_key('a');
        let partial_index = composed
            .candidates
            .iter()
            .position(|candidate| candidate.text == "输入")
            .unwrap();

        let remaining = engine.select_candidate(partial_index).unwrap();
        assert_eq!(remaining.commit_text, "输入");
        assert_eq!(remaining.raw_input, "fa");
        assert!(remaining.segment_boundaries.is_empty());
        assert!(!remaining.commit_text.contains('\''));
    }

    #[test]
    fn reset_clears_state_and_candidates() {
        let mut engine = create_engine();
        engine.process_key('n');
        engine.process_key('i');
        let result = engine.reset();
        assert_eq!(result.parser_state, ProtocolParserState::Empty);
        assert_eq!(result.raw_input, "");
        assert!(result.candidates.is_empty());
    }

    #[test]
    fn candidate_pages_move_forward_and_backward() {
        let mut engine = create_engine();
        engine.process_key('n');
        let next = engine.next_candidate_page().unwrap();
        assert_eq!(next.candidate_page, 1);
        assert!(next.has_previous_page);
        let previous = engine.previous_candidate_page().unwrap();
        assert_eq!(previous.candidate_page, 0);
    }

    #[test]
    fn select_candidate_returns_commit_text_and_clears_composition() {
        let mut engine = create_engine();
        engine.process_key('n');
        engine.process_key('i');
        let result = engine.select_candidate(0).unwrap();

        assert_eq!(result.commit_text, "你");
        assert!(result.composition_finished);
        assert!(engine.current_state().candidates.is_empty());
        assert_eq!(engine.current_state().raw_input, "");
    }

    #[test]
    fn invalid_candidate_index_returns_error() {
        let mut engine = create_engine();
        engine.process_key('n');
        assert_eq!(
            engine.select_candidate(99),
            Err(EngineOperationError::InvalidCandidate)
        );
    }

    #[test]
    fn lexicon_not_loaded_returns_explicit_error_on_query() {
        let mut engine = ImeEngine::new(EngineConfig::default()).unwrap();
        engine.process_key('n');
        let result = engine.process_key('i');

        assert!(!result.success);
        assert_eq!(result.error_code, ImeErrorCode::EngineNotInitialized);
        assert_eq!(result.error_message, "lexicon is not loaded");
    }

    #[test]
    fn stage8_sentence_decoder_returns_full_sentence_and_partial_candidate() {
        let mut engine = create_stage8_engine(5);
        for key in "uurufa".chars() {
            engine.process_key(key);
        }
        let result = engine.current_state();

        assert_eq!(
            result.parsed_syllables,
            vec!["shu".to_owned(), "ru".to_owned(), "fa".to_owned()]
        );
        assert_eq!(result.candidates[0].text, "输入法");
        assert!(result
            .candidates
            .iter()
            .any(|candidate| candidate.text == "输入"));
    }

    #[test]
    fn stage8_selecting_partial_candidate_keeps_remaining_raw_input() {
        let mut engine = create_stage8_engine(5);
        for key in "uurufa".chars() {
            engine.process_key(key);
        }
        let partial_index = engine
            .current_state()
            .candidates
            .iter()
            .position(|candidate| candidate.text == "输入")
            .unwrap();

        let result = engine.select_candidate(partial_index).unwrap();

        assert_eq!(result.commit_text, "输入");
        assert!(!result.composition_finished);
        assert_eq!(result.raw_input, "fa");
        assert_eq!(result.parsed_syllables, vec!["fa".to_owned()]);
        assert_eq!(result.candidates[0].text, "法");
    }

    #[test]
    fn stage8_remaining_input_can_be_committed_after_partial_selection() {
        let mut engine = create_stage8_engine(5);
        for key in "uurufa".chars() {
            engine.process_key(key);
        }
        let partial_index = engine
            .current_state()
            .candidates
            .iter()
            .position(|candidate| candidate.text == "输入")
            .unwrap();
        engine.select_candidate(partial_index).unwrap();

        let result = engine.select_candidate(0).unwrap();

        assert_eq!(result.commit_text, "法");
        assert!(result.composition_finished);
        assert_eq!(engine.current_state().raw_input, "");
    }

    #[test]
    fn stage8_backspace_recomputes_candidates_after_partial_commit() {
        let mut engine = create_stage8_engine(5);
        for key in "uurufa".chars() {
            engine.process_key(key);
        }
        let partial_index = engine
            .current_state()
            .candidates
            .iter()
            .position(|candidate| candidate.text == "输入")
            .unwrap();
        engine.select_candidate(partial_index).unwrap();

        let result = engine.backspace();

        assert_eq!(result.raw_input, "f");
        assert_eq!(result.pending_code, "f");
        assert_eq!(result.candidate_page, 0);
        assert_eq!(result.candidates[0].text, "法");
    }

    #[test]
    fn stage8_sentence_candidates_are_deterministic() {
        let mut engine = create_stage8_engine(5);
        for key in "xnheulpb".chars() {
            engine.process_key(key);
        }
        let first = engine.current_state().candidates;

        let mut second_engine = create_stage8_engine(5);
        for key in "xnheulpb".chars() {
            second_engine.process_key(key);
        }

        assert_eq!(first, second_engine.current_state().candidates);
        assert_eq!(first[0].text, "小鹤双拼");
    }

    #[test]
    fn stage8_reset_clears_sentence_state() {
        let mut engine = create_stage8_engine(5);
        for key in "xnheulpb".chars() {
            engine.process_key(key);
        }
        let result = engine.reset();

        assert_eq!(result.parser_state, ProtocolParserState::Empty);
        assert!(result.candidates.is_empty());
        assert_eq!(engine.current_state().raw_input, "");
    }

    #[test]
    fn stage8_extreme_long_input_is_limited_without_panic() {
        let mut engine = create_stage8_engine(5);
        let mut result = engine.current_state();
        for _ in 0..33 {
            let _ = engine.process_key('n');
            result = engine.process_key('i');
        }

        assert!(!result.success);
        assert_eq!(result.error_code, ImeErrorCode::InvalidArgument);
        assert!(result.error_message.contains("raw input is too long"));
    }

    #[test]
    fn stage9_non_first_candidate_rises_after_selection() {
        let mut engine = create_close_ni_learning_engine();
        engine.process_key('n');
        let initial = engine.process_key('i');
        assert_eq!(initial.candidates[0].text, "你");
        assert_eq!(initial.candidates[1].text, "泥");

        engine.select_candidate(1).unwrap();
        engine.process_key('n');
        let learned = engine.process_key('i');

        assert_eq!(learned.candidates[0].text, "泥");
    }

    #[test]
    fn stage9_user_weight_is_bounded_by_base_frequency_gap() {
        let mut engine = create_learning_engine(
            5,
            vec![
                stage8_entry("你", "ni", 100_000),
                stage8_entry("泥", "ni", 1),
            ],
        );
        for _ in 0..64 {
            engine.process_key('n');
            engine.process_key('i');
            engine.select_candidate(1).unwrap();
        }

        engine.process_key('n');
        let result = engine.process_key('i');

        assert_eq!(result.candidates[0].text, "你");
        assert_eq!(result.candidates[1].text, "泥");
    }

    #[test]
    fn stage9_persisted_learning_survives_engine_recreation() {
        let path = stage9_model_path("persist");
        let mut engine = create_close_ni_learning_engine();
        engine
            .set_user_model_path(&path.to_string_lossy())
            .expect("set path");
        engine.load_user_model().expect("load");
        engine.process_key('n');
        engine.process_key('i');
        engine.select_candidate(1).unwrap();
        engine.flush_user_model().expect("flush");

        let mut reloaded = create_close_ni_learning_engine();
        reloaded
            .set_user_model_path(&path.to_string_lossy())
            .expect("set path");
        reloaded.load_user_model().expect("load");
        reloaded.process_key('n');
        let result = reloaded.process_key('i');

        assert_eq!(result.candidates[0].text, "泥");
        let _ = fs::remove_file(path);
    }

    #[test]
    fn stage9_disabled_session_does_not_learn() {
        let mut engine = create_close_ni_learning_engine();
        engine.set_session_learning_allowed(false);
        for _ in 0..4 {
            engine.process_key('n');
            engine.process_key('i');
            engine.select_candidate(1).unwrap();
        }

        engine.process_key('n');
        let result = engine.process_key('i');

        assert_eq!(result.candidates[0].text, "你");
    }

    #[test]
    fn stage9_clear_restores_base_order() {
        let path = stage9_model_path("clear");
        let mut engine = create_close_ni_learning_engine();
        engine
            .set_user_model_path(&path.to_string_lossy())
            .expect("set path");
        engine.load_user_model().expect("load");
        engine.process_key('n');
        engine.process_key('i');
        engine.select_candidate(1).unwrap();
        engine.flush_user_model().expect("flush");
        engine.clear_user_model().expect("clear");

        engine.process_key('n');
        let result = engine.process_key('i');

        assert_eq!(result.candidates[0].text, "你");
        assert!(!path.exists());
    }

    #[test]
    fn stage9_corrupt_model_load_keeps_system_candidates_available() {
        let path = stage9_model_path("corrupt");
        fs::write(&path, b"BAD!").unwrap();
        let mut engine = create_close_ni_learning_engine();
        engine
            .set_user_model_path(&path.to_string_lossy())
            .expect("set path");
        let status = engine.load_user_model().expect("load");
        assert_eq!(status.last_error_code, "corrupt");

        engine.process_key('n');
        let result = engine.process_key('i');

        assert!(result.success);
        assert_eq!(result.candidates[0].text, "你");
    }

    #[test]
    fn stage9_partial_commit_learns_only_committed_prefix() {
        let mut engine = create_stage8_engine(5);
        for key in "uurufa".chars() {
            engine.process_key(key);
        }
        let partial_index = engine
            .current_state()
            .candidates
            .iter()
            .position(|candidate| candidate.text == "输入")
            .unwrap();
        engine.select_candidate(partial_index).unwrap();
        engine.reset();

        for key in "uurufa".chars() {
            engine.process_key(key);
        }
        let result = engine.current_state();

        assert_eq!(result.candidates[0].text, "输入法");
        assert!(result
            .candidates
            .iter()
            .any(|candidate| candidate.text == "输入"));
    }

    #[test]
    fn failed_scheme_change_preserves_previous_state() {
        let mut engine = create_engine();
        engine.process_key('n');
        engine.process_key('i');

        assert!(engine.change_scheme("missing").is_err());
        let result = engine.current_state();
        assert_eq!(engine.scheme_id(), "xiaohe");
        assert_eq!(result.raw_input, "ni");
        assert_eq!(result.parsed_syllables, vec!["ni".to_owned()]);
    }
}
