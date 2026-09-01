use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;

use code_table_fixture_generator::{build_bundle, generate_fixture};
use engine_protocol::{DateTimeFormatId, ProtocolAction};
use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::{build_binary_lexicon, LexiconEntry};
use user_lexicon::{parse_user_lexicon_bytes, save_snapshot_atomic};

static USER_FILE_COUNTER: AtomicUsize = AtomicUsize::new(0);

fn fixture_bundle_path() -> &'static PathBuf {
    static PATH: OnceLock<PathBuf> = OnceLock::new();
    PATH.get_or_init(|| {
        let root = std::env::temp_dir().join(format!(
            "stage11-6-3-ime-engine-fixture-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        let report = generate_fixture(&root).expect("generate fixture");
        let build = build_bundle(&report.manifest_path).expect("build fixture bundle");
        let path = root.join("code-table-fixture-synthetic.bundle");
        fs::write(&path, build.bytes).expect("write fixture bundle");
        path
    })
}

fn xiaohe_lexicon_path() -> PathBuf {
    let entries = vec![LexiconEntry::new(
        "你好".to_owned(),
        "ni hao".to_owned(),
        vec!["ni".to_owned(), "hao".to_owned()],
        100,
        vec!["test".to_owned()],
    )];
    let sequence = USER_FILE_COUNTER.fetch_add(1, Ordering::Relaxed);
    let path = std::env::temp_dir().join(format!(
        "stage11-6-3-xiaohe-{}-{sequence}.lex",
        std::process::id()
    ));
    fs::write(&path, build_binary_lexicon(&entries, 11_603, 1).unwrap()).unwrap();
    path
}

fn engine(page_size: usize) -> ImeEngine {
    ImeEngine::new(EngineConfig {
        scheme_id: "code-table-fixture".to_owned(),
        lexicon_path: None,
        code_table_bundle_path: Some(fixture_bundle_path().to_string_lossy().into_owned()),
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("code-table fixture engine")
}

fn action_fixture_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/code-table/stage11_6_6_actions.json")
}

fn engine_with_actions(page_size: usize) -> ImeEngine {
    ImeEngine::new(EngineConfig {
        scheme_id: "code-table-fixture".to_owned(),
        lexicon_path: None,
        code_table_bundle_path: Some(fixture_bundle_path().to_string_lossy().into_owned()),
        user_lexicon_path: None,
        code_table_action_fixture_path: Some(action_fixture_path().to_string_lossy().into_owned()),
        code_table_action_fixture_sha256: Some(
            "05a7653e44fe72c45b1b5b0dc1dc245baaafbc1f4becd5c2ec6c657687c59b63".to_owned(),
        ),
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("code-table fixture engine with actions")
}

fn user_lexicon_path(name: &str) -> PathBuf {
    let id = USER_FILE_COUNTER.fetch_add(1, Ordering::Relaxed);
    std::env::temp_dir().join(format!(
        "stage11-6-4-{name}-{}-{id}.txt",
        std::process::id()
    ))
}

fn engine_with_user_file(path: &std::path::Path, page_size: usize) -> ImeEngine {
    ImeEngine::new(EngineConfig {
        scheme_id: "code-table-fixture".to_owned(),
        lexicon_path: None,
        code_table_bundle_path: Some(fixture_bundle_path().to_string_lossy().into_owned()),
        user_lexicon_path: Some(path.to_string_lossy().into_owned()),
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("code-table fixture engine with user overlay")
}

fn engine_with_rules(rules: &str, page_size: usize) -> ImeEngine {
    let path = user_lexicon_path("rules");
    fs::write(&path, rules).unwrap();
    engine_with_user_file(&path, page_size)
}

fn input(engine: &mut ImeEngine, code: &str) {
    for key in code.chars() {
        let result = engine.process_key(key);
        assert!(result.success, "{}", result.error_message);
    }
}

fn all_paged_candidates(engine: &mut ImeEngine) -> Vec<(String, String)> {
    let mut result = engine.current_state();
    let mut candidates = Vec::new();
    loop {
        candidates.extend(
            result
                .candidates
                .iter()
                .map(|candidate| (candidate.text.clone(), candidate.source.clone())),
        );
        if !result.has_next_page {
            break;
        }
        result = engine.next_candidate_page().expect("next candidate page");
    }
    candidates
}

#[test]
fn guide_state_is_isolated_and_backspace_is_stepwise() {
    let mut engine = engine_with_actions(3);
    let prefix = engine.process_key(';');
    assert_eq!(prefix.raw_input, ";");
    assert!(prefix.candidates.is_empty());

    let guide = engine.process_key('g');
    assert_eq!(guide.raw_input, ";g");
    assert!(!guide.candidates.is_empty());
    assert!(guide
        .candidates
        .iter()
        .all(|candidate| candidate.source == "guide"));

    assert_eq!(engine.backspace().raw_input, ";");
    assert_eq!(engine.backspace().raw_input, "");
    assert_eq!(engine.process_key(';').raw_input, ";");
    assert_eq!(engine.process_key(';').raw_input, ";");
}

#[test]
fn quick_symbols_preserve_source_order_then_page_and_commit_as_text() {
    let mut engine = engine_with_actions(3);
    engine.process_key(';');
    let first = engine.process_key('q');
    assert_eq!(
        first
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        ["快符 01", "快符 02", "快符 03"]
    );
    assert!(first.has_next_page);
    let second = engine.next_candidate_page().expect("second quick page");
    assert_eq!(
        second
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>(),
        ["快符 04", "快符 05", "快符 06"]
    );
    let committed = engine.select_candidate(0).expect("quick symbol");
    assert_eq!(committed.commit_text, "④");
    assert!(committed.action.is_none());
}

#[test]
fn date_time_and_pair_selection_return_one_typed_action() {
    let mut engine = engine_with_actions(5);
    input(&mut engine, ";di");
    let date = engine.select_candidate(0).expect("date action");
    assert_eq!(date.commit_text, "");
    assert_eq!(
        date.action,
        Some(ProtocolAction::DateTimeText {
            format_id: DateTimeFormatId::DateIso
        })
    );

    input(&mut engine, ";pa");
    let pair = engine.select_candidate(0).expect("pair action");
    assert_eq!(pair.commit_text, "");
    assert_eq!(
        pair.action,
        Some(ProtocolAction::InsertPair {
            text: "()".to_owned(),
            cursor_offset_utf16: 1
        })
    );
}

#[test]
fn action_fixture_requires_frozen_hash_and_fixture_scheme() {
    let mut config = EngineConfig {
        scheme_id: "code-table-fixture".to_owned(),
        lexicon_path: None,
        code_table_bundle_path: Some(fixture_bundle_path().to_string_lossy().into_owned()),
        user_lexicon_path: None,
        code_table_action_fixture_path: Some(action_fixture_path().to_string_lossy().into_owned()),
        code_table_action_fixture_sha256: Some("00".repeat(32)),
        candidate_page_size: 5,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    };
    assert!(ImeEngine::new(config.clone()).is_err());
    config.scheme_id = "xiaohe-yinxing".to_owned();
    assert!(ImeEngine::new(config).is_err());
}

#[test]
fn fixture_backend_uses_raw_code_and_exact_priority() {
    let mut engine = engine(9);
    input(&mut engine, "ab");
    let result = engine.current_state();
    assert_eq!(result.raw_input, "ab");
    assert!(result.parsed_syllables.is_empty());
    assert_eq!(result.candidates.len(), 3);
    assert!(result
        .candidates
        .iter()
        .all(|candidate| candidate.reading == "ab"));
    assert!(!result
        .candidates
        .iter()
        .any(|candidate| candidate.reading == "abcd"));
}

#[test]
fn fixture_backend_prefix_fallback_preserves_category_then_source_order() {
    let mut engine = engine(9);
    input(&mut engine, "z");
    let result = engine.current_state();
    assert_eq!(result.candidates[0].source, "core");
    assert_eq!(result.candidates[0].reading, "zzzz");
    assert_eq!(result.candidates[0].text, "核心辛000008");
    assert_eq!(result.candidates[1].text, "核心甲000009");
}

#[test]
fn fixture_backend_stably_deduplicates_cross_category_text() {
    let mut engine = engine(9);
    input(&mut engine, "a");
    let result = engine.current_state();
    assert_eq!(result.candidates.len(), 1);
    assert_eq!(result.candidates[0].text, "共享同码同词000001");
    assert_eq!(result.candidates[0].source, "core");
}

#[test]
fn fixture_backend_paginates_after_global_merge() {
    let mut engine = engine(9);
    input(&mut engine, "zzzz");
    let first = engine.current_state();
    assert_eq!(first.candidates.len(), 9);
    assert!(first.has_next_page);
    let next = engine.next_candidate_page().unwrap();
    assert_eq!(next.candidate_page, 1);
    assert_eq!(next.candidates[0].text, "核心甲000017");
}

#[test]
fn fixture_backend_backspace_and_reset_requery_without_stale_candidates() {
    let mut engine = engine(9);
    input(&mut engine, "ab");
    let exact = engine.current_state().candidates;
    let after_backspace = engine.backspace();
    assert_eq!(after_backspace.raw_input, "a");
    assert_ne!(after_backspace.candidates, exact);
    let reset = engine.reset();
    assert!(reset.raw_input.is_empty());
    assert!(reset.candidates.is_empty());
}

#[test]
fn backend_switch_resets_state_and_keeps_xiaohe_behavior_isolated() {
    let xiaohe = xiaohe_lexicon_path();
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "code-table-fixture".to_owned(),
        lexicon_path: Some(xiaohe.to_string_lossy().into_owned()),
        code_table_bundle_path: Some(fixture_bundle_path().to_string_lossy().into_owned()),
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 9,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .unwrap();
    input(&mut engine, "ab");
    let switched = engine.change_scheme("xiaohe").unwrap();
    assert!(switched.raw_input.is_empty());
    assert!(switched.candidates.is_empty());
    input(&mut engine, "nihc");
    assert_eq!(engine.current_state().candidates[0].text, "你好");
    let switched_back = engine.change_scheme("code-table-fixture").unwrap();
    assert!(switched_back.raw_input.is_empty());
    assert!(switched_back.candidates.is_empty());
}

#[test]
fn missing_fixture_bundle_is_a_structured_create_error() {
    let error = ImeEngine::new(EngineConfig {
        scheme_id: "code-table-fixture".to_owned(),
        lexicon_path: None,
        code_table_bundle_path: Some("missing-stage11-6-3.bundle".to_owned()),
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 5,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .unwrap_err();
    assert_eq!(error.to_string(), "code-table bundle not found");
}

#[test]
fn fixture_backend_applies_add_delete_fixed_and_global_position_rules() {
    let mut engine = engine_with_rules(
        concat!(
            "普通用户词\tzzzz\n",
            "固顶甲\tzzzz#固\n",
            "固顶乙\tzzzz#固\n",
            "位置词\tzzzz#2\n",
        ),
        9,
    );
    input(&mut engine, "zzzz");
    let candidates = all_paged_candidates(&mut engine);
    assert_eq!(
        candidates[..3]
            .iter()
            .map(|candidate| candidate.0.as_str())
            .collect::<Vec<_>>(),
        ["固顶甲", "固顶乙", "位置词"]
    );
    assert_eq!(candidates[0].1, "user-lexicon");
    assert_eq!(candidates.last().unwrap().0, "普通用户词");
    assert!(candidates[3..candidates.len() - 1]
        .iter()
        .all(|candidate| candidate.1 != "user-lexicon"));

    engine.reset();
    input(&mut engine, "aow");
    let auto_committed = engine.process_key('k');
    assert_eq!(auto_committed.commit_text, "测");
    assert!(auto_committed.raw_input.is_empty());
    assert!(auto_committed.candidates.is_empty());

    let path = user_lexicon_path("delete");
    fs::write(&path, "测\taowk#删\n").unwrap();
    let mut deleted = engine_with_user_file(&path, 9);
    input(&mut deleted, "aowk");
    assert!(deleted.current_state().candidates.is_empty());
    deleted.reset();
    input(&mut deleted, "dzq");
    let unaffected = deleted.process_key('c');
    assert_eq!(unaffected.commit_text, "测");
}

#[test]
fn fixture_backend_uses_only_the_last_effective_rule() {
    let mut engine = engine_with_rules(
        concat!(
            "覆盖词\tzzzz\n",
            "覆盖词\tzzzz#删\n",
            "覆盖词\tzzzz#固\n",
            "覆盖词\tzzzz#2\n",
            "最终固顶\tzzzz#2\n",
            "最终固顶\tzzzz#固\n",
        ),
        9,
    );
    input(&mut engine, "zzzz");
    let result = engine.current_state();
    assert_eq!(result.candidates[0].text, "最终固顶");
    assert_eq!(result.candidates[1].text, "覆盖词");
    assert_eq!(
        result
            .candidates
            .iter()
            .filter(|candidate| candidate.text == "覆盖词")
            .count(),
        1
    );
}

#[test]
fn fixture_backend_applies_rules_before_every_page_and_refills_after_delete() {
    let mut engine = engine_with_rules(
        concat!(
            "分页固顶\tzzzz#固\n",
            "分页位置\tzzzz#2\n",
            "普通分页\tzzzz\n",
        ),
        5,
    );
    input(&mut engine, "zzzz");
    let first = engine.current_state();
    assert_eq!(first.candidates[0].text, "分页固顶");
    assert_eq!(first.candidates[1].text, "分页位置");
    assert_ne!(first.candidates[2].source, "user-lexicon");
    let second = engine.next_candidate_page().unwrap();
    assert_eq!(second.candidate_page, 1);
    let second_again = engine.current_state();
    assert_eq!(second, second_again);
    let mut last = second;
    while last.has_next_page {
        last = engine.next_candidate_page().unwrap();
    }
    assert_eq!(last.candidates.last().unwrap().text, "普通分页");
    let after_backspace = engine.backspace();
    assert_eq!(after_backspace.candidate_page, 0);
    assert_eq!(after_backspace.raw_input, "zzz");
}

#[test]
fn user_overlay_survives_engine_recreation_reset_and_learning_clear() {
    let path = user_lexicon_path("restart");
    fs::write(&path, "重启固顶\tzzzz#固\n重启普通\tzzzz\n").unwrap();
    let expected = {
        let mut first = engine_with_user_file(&path, 9);
        input(&mut first, "zzzz");
        let result = first.current_state();
        assert_eq!(result.candidates[0].text, "重启固顶");
        first.clear_user_model().unwrap();
        let reset = first.reset();
        assert!(reset.candidates.is_empty());
        input(&mut first, "zzzz");
        first.current_state().candidates
    };
    let mut recreated = engine_with_user_file(&path, 9);
    input(&mut recreated, "zzzz");
    assert_eq!(recreated.current_state().candidates, expected);
}

#[test]
fn corrupt_primary_recovers_backup_and_double_corruption_keeps_system_available() {
    let path = user_lexicon_path("recover");
    let snapshot = parse_user_lexicon_bytes("fixture.txt", "恢复固顶\tzzzz#固\n".as_bytes())
        .unwrap()
        .into_snapshot();
    save_snapshot_atomic(&path, &snapshot).unwrap();
    fs::write(&path, b"broken").unwrap();
    let mut recovered = engine_with_user_file(&path, 9);
    input(&mut recovered, "zzzz");
    assert_eq!(recovered.current_state().candidates[0].text, "恢复固顶");

    let backup = path.with_file_name(format!(
        "{}.bak",
        path.file_name().unwrap().to_string_lossy()
    ));
    fs::write(&backup, b"broken").unwrap();
    let mut degraded = engine_with_user_file(&path, 9);
    input(&mut degraded, "zzzz");
    let result = degraded.current_state();
    assert!(result.success);
    assert!(!result.candidates.is_empty());
    assert_ne!(result.candidates[0].text, "恢复固顶");
}

#[test]
fn empty_user_file_is_an_empty_overlay_and_scheme_switch_stays_isolated() {
    let path = user_lexicon_path("empty");
    fs::write(&path, b"").unwrap();
    let xiaohe = xiaohe_lexicon_path();
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "code-table-fixture".to_owned(),
        lexicon_path: Some(xiaohe.to_string_lossy().into_owned()),
        code_table_bundle_path: Some(fixture_bundle_path().to_string_lossy().into_owned()),
        user_lexicon_path: Some(path.to_string_lossy().into_owned()),
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 9,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .unwrap();
    input(&mut engine, "ab");
    assert!(!engine.current_state().candidates.is_empty());
    engine.change_scheme("xiaohe").unwrap();
    input(&mut engine, "nihc");
    assert_eq!(engine.current_state().candidates[0].text, "你好");
}

#[test]
fn category_api_returns_contract_and_recomputes_without_commit() {
    let mut engine = engine(2);
    let config = engine.code_table_category_config().unwrap();
    assert_eq!(config.schema_version(), 1);
    assert!(config.enabled_category_ids().len() <= config.definitions().len());
    assert!(config.enabled_category_ids().iter().any(|id| id == "core"));
    assert!(config
        .definitions()
        .iter()
        .find(|definition| definition.id == "core")
        .is_some_and(|definition| definition.required && !definition.user_toggleable));

    input(&mut engine, "un");
    let changed = engine
        .set_code_table_categories(vec![
            "phrases".to_owned(),
            "core".to_owned(),
            "phrases".to_owned(),
        ])
        .unwrap();

    assert!(changed.success);
    assert_eq!(changed.raw_input, "un");
    assert_eq!(changed.candidate_page, 0);
    assert!(changed.commit_text.is_empty());
    assert!(!changed.composition_finished);
    let normalized = engine.code_table_category_config().unwrap();
    assert_eq!(normalized.enabled_category_ids(), ["core", "phrases"]);
}

#[test]
fn category_selection_survives_switching_away_and_back() {
    let mut engine = engine(5);
    engine
        .set_code_table_categories(vec!["core".to_owned()])
        .unwrap();
    engine.change_scheme("xiaohe").unwrap();
    assert!(engine.code_table_category_config().is_err());
    engine.change_scheme("code-table-fixture").unwrap();
    assert_eq!(
        engine
            .code_table_category_config()
            .unwrap()
            .enabled_category_ids(),
        ["core"]
    );
}

#[test]
fn category_api_rejects_xiaohe_without_mutating_shuangpin() {
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(xiaohe_lexicon_path().to_string_lossy().into_owned()),
        ..EngineConfig::default()
    })
    .unwrap();
    input(&mut engine, "nihc");
    let before = engine.current_state();
    assert!(engine.code_table_category_config().is_err());
    assert!(engine
        .set_code_table_categories(vec!["core".to_owned()])
        .is_err());
    assert_eq!(engine.current_state(), before);
}

#[test]
fn stage11_6_7_four_code_auto_commit_and_top_screen_use_existing_protocol() {
    let mut engine = engine(9);
    input(&mut engine, "aow");
    let unique = engine.process_key('k');
    assert!(unique.success);
    assert_eq!(unique.commit_text, "测");
    assert!(unique.action.is_none());
    assert!(unique.raw_input.is_empty());
    assert!(unique.composition_finished);

    input(&mut engine, "zzzz");
    let old_first = engine.current_state().candidates[0].text.clone();
    let topped = engine.process_key('a');
    assert!(topped.success);
    assert_eq!(topped.commit_text, old_first);
    assert!(topped.action.is_none());
    assert_eq!(topped.raw_input, "a");
    assert_eq!(topped.candidates.len(), 1);
    assert!(!topped.composition_finished);
}

#[test]
fn stage11_6_7_multiple_candidates_and_valid_continuation_do_not_auto_commit() {
    let mut engine = engine(9);
    input(&mut engine, "zzzz");
    let multiple = engine.current_state();
    assert!(multiple.commit_text.is_empty());
    assert_eq!(multiple.raw_input, "zzzz");
    assert!(multiple.candidates.len() > 1);

    engine.reset();
    engine
        .set_code_table_categories(vec!["core".to_owned()])
        .unwrap();
    input(&mut engine, "abcd");
    let continued = engine.current_state();
    assert!(continued.commit_text.is_empty());
    assert_eq!(continued.raw_input, "abcd");
    assert_eq!(continued.candidates.len(), 1);
}

#[test]
fn stage11_6_7_user_delete_prevents_auto_commit_and_fixed_rule_changes_top_screen() {
    let mut deleted = engine_with_rules("测\taowk#删\n", 9);
    input(&mut deleted, "aow");
    let cleared = deleted.process_key('k');
    // Deleting the full-code candidate prevents that candidate's auto-commit.
    // The resulting empty full code clears without committing a shorter
    // prefix or replaying a suffix.
    assert!(cleared.commit_text.is_empty());
    assert!(cleared.raw_input.is_empty());
    assert!(cleared.candidates.is_empty());

    let mut fixed = engine_with_rules("用户首选\tzzzz#固\n", 9);
    input(&mut fixed, "zzzz");
    let topped = fixed.process_key('a');
    assert_eq!(topped.commit_text, "用户首选");
    assert_eq!(topped.raw_input, "a");
}

#[test]
fn empty_full_codes_clear_without_forward_or_reverse_split_commits() {
    let mut forward = engine_with_rules("正向切分段\twxq\n正向右段\tr\n", 9);
    input(&mut forward, "wxq");
    let forward_result = forward.process_key('r');
    assert!(forward_result.success);
    assert!(forward_result.commit_text.is_empty());
    assert!(forward_result.raw_input.is_empty());
    assert!(forward_result.candidates.is_empty());
    assert!(forward_result.action.is_none());
    assert!(!forward_result.composition_finished);

    let mut reverse = engine_with_rules("反向合法后段\trst\n", 9);
    input(&mut reverse, "qrs");
    let reverse_result = reverse.process_key('t');
    assert!(reverse_result.success);
    assert!(reverse_result.commit_text.is_empty());
    assert!(reverse_result.raw_input.is_empty());
    assert!(reverse_result.candidates.is_empty());
    assert!(reverse_result.action.is_none());
    assert!(!reverse_result.composition_finished);
}
