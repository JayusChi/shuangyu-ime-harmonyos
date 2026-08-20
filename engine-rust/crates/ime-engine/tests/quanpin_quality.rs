use std::path::PathBuf;

use ime_engine::{EngineConfig, ImeEngine};

fn production_lexicon() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("..")
        .join("entry")
        .join("src")
        .join("main")
        .join("resources")
        .join("rawfile")
        .join("production.lex")
}

fn engine() -> ImeEngine {
    ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        lexicon_path: Some(production_lexicon().to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 50,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("production quanpin engine")
}

fn type_text(engine: &mut ImeEngine, input: &str) -> engine_protocol::CompositionResult {
    let mut result = engine.current_state();
    for key in input.chars() {
        result = engine.process_key(key);
        assert!(result.success, "key {key} failed for {input}");
        assert!(
            result.commit_text.is_empty(),
            "full pinyin committed without an explicit user action for {input}"
        );
    }
    result
}

#[test]
fn common_real_world_full_pinyin_sentences_are_first_candidates() {
    let cases = [
        ("meiwenti", "没问题"),
        ("jintianxingqiyi", "今天星期一"),
        ("niweishenmezheyangshuo", "你为什么这样说"),
        ("zhegeshishenmeyisi", "这个是什么意思"),
        ("nishenmeshihouhuilai", "你什么时候回来"),
        ("jintianwanshangchishenme", "今天晚上吃什么"),
        ("shoudaoyihouqinghuifu", "收到以后请回复"),
        ("zhegewentiyijingjiejue", "这个问题已经解决"),
        ("shurufabuyaozidongshangping", "输入法不要自动上屏"),
    ];
    let mut engine = engine();

    for (input, expected) in cases {
        engine.reset();
        let result = type_text(&mut engine, input);
        assert_eq!(
            result
                .candidates
                .first()
                .map(|candidate| candidate.text.as_str()),
            Some(expected),
            "unexpected first candidate for {input}"
        );
    }
}

#[test]
fn search_or_input_remains_chinese_composition() {
    let input = "sousuohuoshuru";
    let mut engine = engine();
    let result = type_text(&mut engine, input);

    assert_eq!(result.raw_input, input);
    assert!(result.commit_text.is_empty());
    assert!(!result.composition_finished);
    assert_eq!(
        result
            .candidates
            .first()
            .map(|candidate| candidate.text.as_str()),
        Some("搜索或输入")
    );
}

#[test]
fn partial_selection_requeries_only_the_remaining_raw_input() {
    let mut engine = engine();
    let composed = type_text(&mut engine, "nishizgyisi");
    let prefix_index = composed
        .candidates
        .iter()
        .position(|candidate| candidate.text == "你是")
        .expect("partial 你是 candidate");

    let remaining = engine
        .select_candidate(prefix_index)
        .expect("select partial candidate");

    assert_eq!(remaining.commit_text, "你是");
    assert_eq!(remaining.raw_input, "zgyisi");
    assert!(remaining
        .candidates
        .iter()
        .all(|candidate| candidate.text != "你是"));
}

#[test]
fn mixed_initials_and_full_pinyin_do_not_leave_a_stale_prefix_snapshot() {
    let mut engine = engine();
    let result = type_text(&mut engine, "pgshouji");
    let texts = result
        .candidates
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect::<Vec<_>>();

    assert_eq!(
        texts.first(),
        Some(&"苹果手机"),
        "unexpected candidates for pgshouji: {:?}",
        texts.iter().take(10).collect::<Vec<_>>()
    );
}

#[test]
fn terminal_n_prefers_common_prefix_candidates_in_production() {
    let mut engine = engine();
    let result = type_text(&mut engine, "n");
    let texts = result
        .candidates
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect::<Vec<_>>();

    // After Stage 2 quality revision (2026-08-11): "n" is both a standalone reading and a prefix.
    // The parser preserves full state while using prefix recall; standalone "嗯/唔" participate
    // in frequency ranking and are no longer hardcoded before common prefix candidates like "你、那、能".
    assert!(texts.contains(&"你"));
    assert!(texts.contains(&"嗯"));
    assert!(
        texts.iter().position(|text| *text == "你") < texts.iter().position(|text| *text == "嗯"),
        "common prefix candidate should precede the standalone interjection: {texts:?}"
    );
}

#[test]
fn long_compositions_remain_editable_until_the_user_commits() {
    let input = "jintianxingqiyiniweishenmezheyangshuo";
    let mut engine = engine();
    let result = type_text(&mut engine, input);

    assert_eq!(result.raw_input, input);
    assert!(result.commit_text.is_empty());
    assert!(!result.composition_finished);
}

#[test]
fn production_initial_and_mixed_pinyin_recall_remains_composing() {
    let mut engine = engine();
    for input in ["gj", "gjt", "guojt", "gjitian"] {
        engine.reset();
        let result = type_text(&mut engine, input);
        assert_eq!(result.raw_input, input);
        assert!(result.commit_text.is_empty());
        assert!(!result.composition_finished);
        if input == "gj" {
            assert!(!result.candidates.is_empty());
        } else {
            assert!(
                result
                    .candidates
                    .iter()
                    .any(|candidate| candidate.text == "过几天"),
                "missing 过几天 for {input}: {:?}",
                result
                    .candidates
                    .iter()
                    .take(10)
                    .map(|candidate| candidate.text.as_str())
                    .collect::<Vec<_>>()
            );
        }
    }
}

#[test]
fn existing_editor_text_does_not_change_the_diyigeren_composition_contract() {
    let mut engine = engine();
    let result = type_text(&mut engine, "diyigeren");

    assert_eq!(result.raw_input, "diyigeren");
    assert!(result.commit_text.is_empty());
    assert!(!result.composition_finished);
    assert!(
        result
            .candidates
            .iter()
            .any(|candidate| candidate.text == "第一个人"),
        "missing 第一个人: {:?}",
        result
            .candidates
            .iter()
            .take(10)
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>()
    );
}
