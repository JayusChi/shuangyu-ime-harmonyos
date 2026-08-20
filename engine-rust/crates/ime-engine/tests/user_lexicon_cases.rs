use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::{build_binary_lexicon, LexiconEntry};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

fn test_path(name: &str, extension: &str) -> PathBuf {
    let directory = std::env::current_dir()
        .unwrap()
        .join("target")
        .join("user-lexicon-engine-tests");
    fs::create_dir_all(&directory).unwrap();
    directory.join(format!(
        "{name}-{}-{}.{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed),
        extension
    ))
}

fn system_entry(text: &str, frequency: u64) -> LexiconEntry {
    LexiconEntry::new(
        text.to_owned(),
        "ni".to_owned(),
        vec!["ni".to_owned()],
        frequency,
        vec!["system".to_owned()],
    )
}

fn engine(user_rules: Option<&str>, page_size: usize) -> ImeEngine {
    let lexicon_path = test_path("system", "lex");
    let bytes = build_binary_lexicon(
        &[
            system_entry("你", 10_000),
            system_entry("泥", 9_000),
            system_entry("尼", 8_000),
        ],
        12,
        1,
    )
    .unwrap();
    fs::write(&lexicon_path, bytes).unwrap();
    let user_lexicon_path = user_rules.map(|rules| {
        let path = test_path("user", "txt");
        fs::write(&path, rules.as_bytes()).unwrap();
        path.to_string_lossy().into_owned()
    });
    ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .unwrap()
}

fn query_ni(engine: &mut ImeEngine) -> engine_protocol::CompositionResult {
    engine.process_key('n');
    engine.process_key('i')
}

fn texts(result: &engine_protocol::CompositionResult) -> Vec<&str> {
    result
        .candidates
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect()
}

#[test]
fn hard_rules_apply_after_soft_ranking_before_pagination() {
    let mut engine = engine(Some("你\tni#删\n泥\tni#固\n妮\tni\n尼\tni#2\n"), 5);
    let result = query_ni(&mut engine);
    assert_eq!(texts(&result), vec!["泥", "尼", "妮"]);
    assert_eq!(result.candidates[0].source, "system");
    assert_eq!(result.candidates[2].source, "user-lexicon");
}

#[test]
fn ordinary_addition_follows_all_system_candidates_with_the_same_code() {
    let mut engine = engine(Some("妮\tni\n"), 5);
    let result = query_ni(&mut engine);

    assert_eq!(texts(&result), vec!["你", "泥", "尼", "妮"]);
    assert_eq!(result.candidates[3].source, "user-lexicon");
}

#[test]
fn user_candidate_is_selectable_and_position_is_global_before_pages() {
    let mut engine = engine(Some("妮\tni#2\n"), 2);
    let result = query_ni(&mut engine);
    assert_eq!(texts(&result), vec!["你", "妮"]);
    assert!(result.has_next_page);
    let committed = engine.select_candidate(1).unwrap();
    assert_eq!(committed.commit_text, "妮");
    assert!(committed.composition_finished);
}

#[test]
fn fixed_rule_cannot_be_crossed_by_user_learning() {
    let mut engine = engine(Some("泥\tni#固\n"), 5);
    for _ in 0..8 {
        let result = query_ni(&mut engine);
        let system_index = result
            .candidates
            .iter()
            .position(|candidate| candidate.text == "你")
            .unwrap();
        engine.select_candidate(system_index).unwrap();
    }
    assert_eq!(query_ni(&mut engine).candidates[0].text, "泥");
}

#[test]
fn missing_or_corrupt_user_lexicon_keeps_system_behavior() {
    let mut baseline = engine(None, 5);
    let expected = texts(&query_ni(&mut baseline))
        .into_iter()
        .map(str::to_owned)
        .collect::<Vec<_>>();

    let lexicon_path = test_path("system-missing", "lex");
    fs::write(
        &lexicon_path,
        build_binary_lexicon(
            &[system_entry("你", 10_000), system_entry("泥", 9_000)],
            12,
            1,
        )
        .unwrap(),
    )
    .unwrap();
    let mut missing = ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: Some(test_path("missing", "txt").to_string_lossy().into_owned()),
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 5,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .unwrap();
    assert_eq!(texts(&query_ni(&mut missing)), vec!["你", "泥"]);

    let mut corrupt = engine(Some("not-a-valid-row"), 5);
    assert_eq!(texts(&query_ni(&mut corrupt)), expected);
}
