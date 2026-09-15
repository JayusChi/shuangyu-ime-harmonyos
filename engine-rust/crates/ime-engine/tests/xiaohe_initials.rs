use std::fs;
use std::path::PathBuf;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use engine_protocol::CompositionResult;
use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::{build_binary_lexicon, LexiconEntry};

fn create_engine(path: PathBuf) -> ImeEngine {
    ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 16,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .unwrap()
}

fn sample_engine() -> ImeEngine {
    // Neither requested full sentence is stored: the decoder must compose words.
    let entries = [
        ("还是", "hai shi", 100_000),
        ("其实", "qi shi", 100_000),
        ("很", "hen", 90_000),
        ("好", "hao", 90_000),
        ("的", "de", 1_000_000),
        ("简单", "jian dan", 100_000),
        ("你", "ni", 90_000),
        ("你好", "ni hao", 100_000),
        ("你是", "ni shi", 100_000),
        ("你吃", "ni chi", 100_000),
        ("你知", "ni zhi", 100_000),
        ("简", "jian", 80_000),
        ("单", "dan", 80_000),
        ("啊", "a", 90_000),
        ("饿", "e", 90_000),
        ("哦", "o", 90_000),
    ]
    .into_iter()
    .map(|(text, reading, frequency)| {
        LexiconEntry::new(
            text.to_owned(),
            reading.to_owned(),
            reading.split_whitespace().map(str::to_owned).collect(),
            frequency,
            vec!["initial-regression".to_owned()],
        )
    })
    .collect::<Vec<_>>();
    let bytes = build_binary_lexicon(&entries, 8, 1).unwrap();
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!("xiaohe-initials-{nanos}.lex"));
    fs::write(&path, bytes).unwrap();
    let engine = create_engine(path.clone());
    fs::remove_file(path).unwrap();
    engine
}

fn enter(engine: &mut ImeEngine, raw: &str) -> CompositionResult {
    engine.reset();
    let mut state = engine.current_state();
    for key in raw.chars() {
        state = if key == '\'' {
            engine.insert_segment_boundary().unwrap()
        } else {
            engine.process_key(key)
        };
        assert!(state.success, "raw={raw}, key={key}, state={state:?}");
    }
    state
}

#[test]
fn trailing_initial_and_impossible_pair_compose_and_commit_full_sentences() {
    let mut engine = sample_engine();
    for (raw, expected) in [
        ("hduihfhcd", "还是很好的"),
        ("hd'ui'hf'hc'd", "还是很好的"),
        ("qiuihfjdd", "其实很简单的"),
        ("qi'ui'hf'jd'd", "其实很简单的"),
    ] {
        let state = enter(&mut engine, raw);
        assert_eq!(
            state.candidates[0].text, expected,
            "raw={raw}, state={state:?}"
        );
        assert_eq!(state.candidates[0].consumed_raw_len, 9);
        let selected = engine.select_candidate(0).unwrap();
        assert_eq!(selected.commit_text, expected);
        assert!(selected.raw_input.is_empty());
        assert!(selected.composition_finished);
    }
}

#[test]
fn partial_selection_consumes_initial_slots_by_actual_key_count() {
    let mut engine = sample_engine();
    for raw in ["jdd", "jd'd"] {
        let state = enter(&mut engine, raw);
        assert!(state
            .candidates
            .iter()
            .all(|candidate| candidate.text != "简"));
        let index = state
            .candidates
            .iter()
            .position(|candidate| candidate.text == "简单")
            .unwrap();
        assert_eq!(state.candidates[index].consumed_raw_len, 2);
        assert!(state.candidates[index].id.starts_with("sentence:2:"));
        let selected = engine.select_candidate(index).unwrap();
        assert_eq!(selected.commit_text, "简单");
        assert_eq!(selected.raw_input, "d");
        assert!(!selected.composition_finished);
        assert_eq!(selected.candidates[0].text, "的");
    }
}

#[test]
fn completing_and_deleting_a_final_keeps_initial_candidates_recoverable() {
    let mut engine = sample_engine();
    let initial = enter(&mut engine, "hduihfhcd");
    let completed = engine.process_key('e');
    assert_eq!(completed.candidates[0].text, "还是很好的");
    assert_eq!(completed.candidates[0].consumed_raw_len, 10);
    let deleted = engine.backspace();
    assert_eq!(deleted.candidates, initial.candidates);
    let further = engine.backspace();
    assert_eq!(further.raw_input, "hduihfhc");
    assert_eq!(further.candidates[0].text, "还是很好");
}

#[test]
fn mapped_retroflex_initials_and_valid_pair_priority_are_preserved() {
    let mut engine = sample_engine();
    for (key, text) in [
        ("nih", "你好"),
        ("niu", "你是"),
        ("nii", "你吃"),
        ("niv", "你知"),
    ] {
        let state = enter(&mut engine, key);
        assert_eq!(state.candidates[0].text, text, "raw={key}");
        assert_eq!(state.candidates[0].consumed_raw_len, 3);
    }
    let state = enter(&mut engine, "nihc");
    assert_eq!(state.candidates[0].text, "你好");
    assert!(state
        .candidates
        .iter()
        .all(|candidate| !candidate.reading.starts_with("ni hai")));
}

#[test]
fn packaged_lexicon_recognizes_user_examples_with_and_without_boundaries() {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .join("dictionaries/generated/production.lex");
    let mut engine = create_engine(path);
    for (raw, expected) in [
        ("hduihfhcd", "还是很好的"),
        ("hd'ui'hf'hc'd", "还是很好的"),
        ("qiuihfjdd", "其实很简单的"),
        ("qi'ui'hf'jd'd", "其实很简单的"),
    ] {
        let started = Instant::now();
        let state = enter(&mut engine, raw);
        println!(
            "{raw}: {:?}; elapsed={:?}",
            state
                .candidates
                .iter()
                .map(|candidate| &candidate.text)
                .collect::<Vec<_>>(),
            started.elapsed()
        );
        let index = state
            .candidates
            .iter()
            .position(|candidate| candidate.text == expected)
            .unwrap_or_else(|| panic!("missing {expected}, state={state:?}"));
        assert_eq!(state.candidates[index].consumed_raw_len, 9);
        let selected = engine.select_candidate(index).unwrap();
        assert_eq!(selected.commit_text, expected);
        assert!(selected.composition_finished);
        assert!(selected.raw_input.is_empty());
    }
}

#[test]
fn trailing_vowel_prefixes_compose_commit_complete_and_backspace() {
    let mut engine = sample_engine();
    for (raw, key, expected) in [
        ("nia", 'a', "你啊"),
        ("nie", 'e', "你饿"),
        ("nio", 'o', "你哦"),
    ] {
        let state = enter(&mut engine, raw);
        assert_eq!(state.candidates[0].text, expected, "{raw}: {state:?}");
        assert_eq!(state.candidates[0].consumed_raw_len, 3);
        let complete = engine.process_key(key);
        assert_eq!(complete.candidates[0].text, expected);
        assert_eq!(complete.candidates[0].consumed_raw_len, 4);
        let pending = engine.backspace();
        assert_eq!(pending.candidates, state.candidates);
        let selected = engine.select_candidate(0).unwrap();
        assert_eq!(selected.commit_text, expected);
        assert!(selected.raw_input.is_empty());
        assert!(selected.composition_finished);
    }
}

#[test]
fn packaged_lexicon_includes_and_consumes_customer_sentence_final_a() {
    let production = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../dictionaries/generated/production.lex");
    let mut engine = create_engine(production);
    for raw in ["buuinia", "bu'ui'ni'a"] {
        let state = enter(&mut engine, raw);
        let index = state
            .candidates
            .iter()
            .position(|c| c.text == "不是你啊")
            .unwrap_or_else(|| panic!("{raw}: {state:?}"));
        assert_eq!(state.candidates[index].consumed_raw_len, 7);
        let selected = engine.select_candidate(index).unwrap();
        assert_eq!(selected.commit_text, "不是你啊");
        assert!(selected.raw_input.is_empty());
        assert!(selected.composition_finished);
    }
}

#[test]
fn partial_selection_preserves_one_pending_vowel_key() {
    let mut engine = sample_engine();
    let state = enter(&mut engine, "nihca");
    let prefix = state
        .candidates
        .iter()
        .position(|c| c.text == "你好")
        .unwrap();
    assert_eq!(state.candidates[prefix].consumed_raw_len, 4);
    let remaining = engine.select_candidate(prefix).unwrap();
    assert_eq!(remaining.commit_text, "你好");
    assert_eq!(remaining.raw_input, "a");
    let index = remaining
        .candidates
        .iter()
        .position(|c| c.text == "啊")
        .unwrap();
    let selected = engine.select_candidate(index).unwrap();
    assert_eq!(selected.commit_text, "啊");
    assert!(selected.raw_input.is_empty());
}
