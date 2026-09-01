use std::path::PathBuf;

use engine_protocol::CompositionResult;
use ime_engine::{EngineConfig, ImeEngine};

const FORMAL_BASELINE: &str = include_str!(
    "../../../../dictionaries/audit/xiaohe-yinxing/precise-match-stage0/formal_bundle_baseline.json"
);
const PROGRESSIVE_BASELINE: &str = include_str!(
    "../../../../dictionaries/audit/xiaohe-yinxing/precise-match-stage0/progressive_behavior_baseline.json"
);
const XIAOHE_ISOLATION_BASELINE: &str = include_str!(
    "../../../../dictionaries/audit/xiaohe-yinxing/precise-match-stage0/xiaohe_isolation_baseline.json"
);
const COMPATIBILITY_BASELINE: &str = include_str!(
    "../../../../dictionaries/audit/xiaohe-yinxing/precise-match-stage0/four_code_user_rule_compatibility.json"
);

fn workspace() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

fn config(scheme_id: &str) -> EngineConfig {
    let workspace = workspace();
    EngineConfig {
        scheme_id: scheme_id.to_owned(),
        lexicon_path: Some(
            workspace
                .join("dictionaries/generated/production.lex")
                .to_string_lossy()
                .into_owned(),
        ),
        code_table_bundle_path: Some(
            workspace
                .join(
                    "dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
                )
                .to_string_lossy()
                .into_owned(),
        ),
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 50,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    }
}

fn enter(engine: &mut ImeEngine, keys: &str) -> CompositionResult {
    let mut result = engine.current_state();
    for key in keys.chars() {
        result = engine.process_key(key);
        assert!(result.success, "{}", result.error_message);
    }
    result
}

#[test]
fn precise_match_stage0_files_are_path_clean_and_tied_to_the_frozen_resource() {
    for baseline in [
        FORMAL_BASELINE,
        PROGRESSIVE_BASELINE,
        XIAOHE_ISOLATION_BASELINE,
        COMPATIBILITY_BASELINE,
    ] {
        assert!(baseline.ends_with('\n'));
        assert!(!baseline.contains("C:\\"));
        assert!(!baseline.contains("/Users/"));
        assert!(!baseline.contains("generated_at"));
        assert!(!baseline.contains("timestamp"));
    }
    assert!(FORMAL_BASELINE.contains("25397952"));
    assert!(FORMAL_BASELINE
        .contains("00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30"));
    assert!(FORMAL_BASELINE.contains("ohos.permission.VIBRATE"));
    assert!(FORMAL_BASELINE.contains("\"network_permission_present\""));
    assert!(!FORMAL_BASELINE.contains("ohos.permission.INTERNET"));
    assert!(PROGRESSIVE_BASELINE.contains("ProgressiveXiaoheYinxing"));
    assert!(PROGRESSIVE_BASELINE.contains("fifth-key-top-screen-and-replay"));
    assert!(PROGRESSIVE_BASELINE.contains("four-code-empty-split"));
    assert!(XIAOHE_ISOLATION_BASELINE.contains("\"xiaohe_result_restored\": true"));
    assert!(COMPATIBILITY_BASELINE.contains("#delete/#fixed/#N"));
}

#[test]
fn current_precise_behavior_preserves_unchanged_stage0_cases_and_uses_safe_empty_clear() {
    let mut engine = ImeEngine::new(config("xiaohe-yinxing")).expect("formal engine");
    engine
        .set_code_table_categories(
            [
                "core",
                "category-secondary",
                "quick-symbol",
                "one-key-secondary",
                "two-key-secondary",
                "out-of-table-character",
                "full-code-word",
                "symbol",
                "symbol-group",
                "rare-character",
                "full-code-character",
            ]
            .map(str::to_owned)
            .to_vec(),
        )
        .expect("enable archived all-category profile");
    for code in ["aa", "ai", "an", "ni", "hc", "ui", "vi", "wo", "xm", "xq"] {
        engine.reset();
        let result = enter(&mut engine, code);
        assert!(result.commit_text.is_empty(), "{code}");
        assert!(!result.candidates.is_empty(), "{code}");
        assert!(result
            .candidates
            .iter()
            .all(|candidate| candidate.reading == code));
        assert!(
            !result.has_next_page,
            "{code}: exact short code must stay small"
        );
    }

    engine.reset();
    let unique = enter(&mut engine, "aaba");
    assert_eq!(unique.commit_text, "阿爸");
    assert!(unique.raw_input.is_empty());
    assert!(unique.candidates.is_empty());

    engine.reset();
    let multiple = enter(&mut engine, "jumk");
    assert_eq!(multiple.raw_input, "jumk");
    assert_eq!(multiple.candidates.len(), 5);
    assert!(multiple.commit_text.is_empty());
    let fifth = engine.process_key('e');
    assert_eq!(fifth.commit_text, "驹");
    assert_eq!(fifth.raw_input, "e");
    assert!(fifth
        .candidates
        .iter()
        .all(|candidate| candidate.reading == "e"));

    engine.reset();
    let missing = enter(&mut engine, "aaa");
    assert_eq!(missing.raw_input, "aaa");
    assert!(missing.candidates.is_empty());
    assert!(missing.commit_text.is_empty());
    let cleared = engine.process_key('a');
    assert!(cleared.commit_text.is_empty());
    assert!(cleared.raw_input.is_empty());
    assert!(cleared.candidates.is_empty());
}
