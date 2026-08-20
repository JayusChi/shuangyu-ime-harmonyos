use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::{build_binary_lexicon, LexiconEntry};

const CASES: &str = include_str!("../../../tests/fixtures/stage9_user_learning_cases.tsv");

#[test]
fn stage9_user_learning_regression_cases_match_fixture() {
    for (line_no, line) in CASES.lines().enumerate() {
        let line_no = line_no + 1;
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let columns = line.split('\t').collect::<Vec<_>>();
        assert_eq!(columns.len(), 11, "fixture line {line_no}: {line}");

        let case_id = columns[0];
        let scheme_id = columns[1];
        let raw_input = columns[2];
        let initial_order = split_pipe(columns[3]);
        let selected_candidate_id = columns[4];
        let selection_count = parse_usize(columns[5]);
        let expected_order = split_pipe(columns[6]);
        let learning_enabled = parse_bool(columns[7]);
        let session_learning_allowed = parse_bool(columns[8]);
        let restart_before_assert = parse_bool(columns[9]);
        let clear_before_assert = parse_bool(columns[10]);

        let high_gap = case_id == "weight_cap";
        let model_path = temp_model_path(case_id);
        let mut engine = create_engine(scheme_id, high_gap);
        engine
            .set_user_model_path(&model_path.to_string_lossy())
            .expect("set user model path");
        engine.load_user_model().expect("load user model");
        engine.set_user_learning_enabled(learning_enabled);
        engine.set_session_learning_allowed(session_learning_allowed);

        let initial = process_raw(&mut engine, raw_input);
        assert_order_prefix(&initial, &initial_order, line_no);

        for _ in 0..selection_count {
            let current = engine.current_state();
            let selected_index = current
                .candidates
                .iter()
                .position(|candidate| candidate.id == selected_candidate_id)
                .expect("selected candidate must exist");
            let selected = engine.select_candidate(selected_index).expect("select");
            if !selected.composition_finished {
                engine.reset();
            }
            if !engine.current_state().raw_input.is_empty() {
                engine.reset();
            }
            let _ = process_raw(&mut engine, raw_input);
        }
        engine.reset();

        if clear_before_assert {
            engine.clear_user_model().expect("clear user model");
        }

        if restart_before_assert {
            if case_id == "corrupt_recovery" {
                fs::write(&model_path, b"BAD!").expect("write corrupt model");
            } else {
                engine.flush_user_model().expect("flush");
            }
            engine = create_engine(scheme_id, high_gap);
            engine
                .set_user_model_path(&model_path.to_string_lossy())
                .expect("set user model path after restart");
            let _ = engine.load_user_model().expect("load after restart");
        }

        let actual = process_raw(&mut engine, raw_input);
        assert_order_prefix(&actual, &expected_order, line_no);
        let _ = fs::remove_file(model_path);
    }
}

fn create_engine(scheme_id: &str, high_gap: bool) -> ImeEngine {
    let path = create_lexicon(high_gap);
    ImeEngine::new(EngineConfig {
        scheme_id: scheme_id.to_owned(),
        lexicon_path: Some(path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 5,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("engine")
}

fn create_lexicon(high_gap: bool) -> PathBuf {
    let (top_frequency, second_frequency) = if high_gap {
        (100_000, 1)
    } else {
        (10_000, 9_000)
    };
    let entries = vec![
        entry("你", "ni", top_frequency),
        entry("泥", "ni", second_frequency),
        entry("法", "fa", 80_000),
        entry("输入", "shu ru", 82_000),
        entry("输入法", "shu ru fa", 90_000),
    ];
    let bytes = build_binary_lexicon(&entries, 9, 1).expect("lexicon");
    let path = temp_model_path("lexicon").with_extension("lex");
    fs::write(&path, bytes).expect("write lexicon");
    path
}

fn entry(word: &str, pinyin: &str, frequency: u64) -> LexiconEntry {
    LexiconEntry::new(
        word.to_owned(),
        pinyin.to_owned(),
        pinyin.split(' ').map(str::to_owned).collect(),
        frequency,
        vec!["stage9".to_owned()],
    )
}

fn process_raw(engine: &mut ImeEngine, raw_input: &str) -> engine_protocol::CompositionResult {
    engine.reset();
    let mut result = engine.current_state();
    for key in raw_input.chars() {
        result = engine.process_key(key);
    }
    result
}

fn assert_order_prefix(
    result: &engine_protocol::CompositionResult,
    expected: &[&str],
    line_no: usize,
) {
    let actual = result
        .candidates
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect::<Vec<_>>();
    assert!(
        actual.starts_with(expected),
        "fixture line {line_no}: actual={actual:?}, expected={expected:?}"
    );
}

fn temp_model_path(name: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time")
        .as_nanos();
    std::env::temp_dir().join(format!("stage9-fixture-{name}-{nanos}.dat"))
}

fn split_pipe(value: &str) -> Vec<&str> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        Vec::new()
    } else {
        trimmed.split('|').collect()
    }
}

fn parse_bool(value: &str) -> bool {
    match value {
        "true" => true,
        "false" => false,
        other => panic!("invalid boolean in fixture: {other}"),
    }
}

fn parse_usize(value: &str) -> usize {
    value
        .parse::<usize>()
        .unwrap_or_else(|_| panic!("invalid usize in fixture: {value}"))
}
