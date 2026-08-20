use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::{build_binary_lexicon, LexiconEntry};

fn unique_path(label: &str, extension: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();
    std::env::temp_dir().join(format!(
        "quanpin-stage2-{label}-{}-{nanos}.{extension}",
        std::process::id()
    ))
}

fn entry(text: &str, reading: &str, frequency: u64) -> LexiconEntry {
    LexiconEntry::new(
        text.to_owned(),
        reading.to_owned(),
        reading.split_whitespace().map(str::to_owned).collect(),
        frequency,
        vec!["quanpin-stage2".to_owned()],
    )
}

fn lexicon_path() -> PathBuf {
    let entries = vec![
        entry("你", "ni", 100_000),
        entry("嗯", "n", 31_983),
        entry("唔", "n", 1_127),
        entry("能", "neng", 90_000),
        entry("那", "na", 95_000),
        entry("好", "hao", 99_000),
        entry("你好", "ni hao", 120_000),
        entry("中", "zhong", 100_000),
        entry("国", "guo", 99_000),
        entry("中国", "zhong guo", 121_000),
        entry("先", "xian", 110_000),
        entry("西", "xi", 80_000),
        entry("安", "an", 80_000),
        entry("西安", "xi an", 105_000),
        entry("过几天", "guo ji tian", 118_000),
    ];
    let path = unique_path("lexicon", "lex");
    fs::write(
        &path,
        build_binary_lexicon(&entries, 2, 1).expect("lexicon build"),
    )
    .expect("lexicon write");
    path
}

fn engine(scheme_id: &str, user_lexicon_path: Option<&PathBuf>) -> ImeEngine {
    let path = lexicon_path();
    ImeEngine::new(EngineConfig {
        scheme_id: scheme_id.to_owned(),
        lexicon_path: Some(path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: user_lexicon_path.map(|value| value.to_string_lossy().into_owned()),
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 10,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("engine")
}

fn type_text(engine: &mut ImeEngine, input: &str) -> engine_protocol::CompositionResult {
    let mut result = engine.current_state();
    for key in input.chars() {
        result = engine.process_key(key);
    }
    result
}

fn candidate_texts(result: &engine_protocol::CompositionResult) -> Vec<&str> {
    result
        .candidates
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect()
}

#[test]
fn common_full_pinyin_exact_prefix_sentence_and_paging_work() {
    let mut engine = engine("quanpin", None);

    let ni = type_text(&mut engine, "ni");
    assert!(ni.success);
    assert_eq!(ni.current_pinyin, "ni");
    assert!(candidate_texts(&ni).contains(&"你"));

    engine.reset();
    let nihao = type_text(&mut engine, "nihao");
    assert_eq!(nihao.current_pinyin, "ni'hao");
    assert_eq!(nihao.display_segments, ["ni", "hao"]);
    assert!(candidate_texts(&nihao).contains(&"你好"));

    engine.reset();
    let zhongguo = type_text(&mut engine, "zhongguo");
    assert_eq!(zhongguo.current_pinyin, "zhong'guo");
    assert!(candidate_texts(&zhongguo).contains(&"中国"));

    engine.reset();
    let zhon = type_text(&mut engine, "zhon");
    assert_eq!(
        zhon.parser_state,
        engine_protocol::ProtocolParserState::Incomplete
    );
    assert!(candidate_texts(&zhon).contains(&"中"));
}

#[test]
fn terminal_n_recalls_common_prefixes_before_standalone_interjections() {
    let mut engine = engine("quanpin", None);
    let result = engine.process_key('n');
    let texts = candidate_texts(&result);

    assert!(result.success);
    assert_eq!(result.raw_input, "n");
    assert_eq!(result.commit_text, "");

    // After Stage 2 quality revision (2026-08-11): "n" is both a standalone reading and a prefix.
    // Standalone "嗯/唔" participate in frequency ranking instead of being hardcoded first.
    // With the test fixture frequencies (你=100k, 那=95k, 能=90k, 嗯=31k), prefix candidates
    // should rank higher than standalone interjections, matching the quality revision goal.
    assert!(texts.contains(&"嗯"));

    assert!(
        texts.contains(&"你"),
        "Expected prefix candidate 你, got: {texts:?}"
    );
    assert!(
        texts.iter().position(|text| *text == "你") < texts.iter().position(|text| *text == "嗯"),
        "Expected 你 before 嗯 given fixture frequencies, got: {:?}",
        texts
    );
}

#[test]
fn ambiguity_explicit_boundary_and_backspace_recover_deterministically() {
    let mut engine = engine("quanpin", None);
    let xian = type_text(&mut engine, "xian");
    assert_eq!(xian.current_pinyin, "xian");
    assert!(xian
        .pinyin_combinations
        .iter()
        .any(|value| value == "xi'an"));
    assert!(candidate_texts(&xian).contains(&"先"));
    assert!(candidate_texts(&xian).contains(&"西安"));

    let xia = engine.backspace();
    assert_eq!(xia.raw_input, "xia");
    assert_eq!(engine.process_key('n').current_pinyin, "xian");

    engine.reset();
    engine.process_key('x');
    engine.process_key('i');
    engine.insert_segment_boundary().expect("explicit boundary");
    let explicit = type_text(&mut engine, "an");
    assert_eq!(explicit.current_pinyin, "xi'an");
    assert_eq!(explicit.segment_boundaries, [2]);
    assert!(candidate_texts(&explicit).contains(&"西安"));
}

#[test]
fn candidate_selection_and_scheme_switch_clear_and_restore_parser_semantics() {
    let mut engine = engine("quanpin", None);
    let result = type_text(&mut engine, "nihao");
    let index = result
        .candidates
        .iter()
        .position(|candidate| candidate.text == "你好")
        .expect("你好 candidate");
    let committed = engine.select_candidate(index).expect("selection");
    assert_eq!(committed.commit_text, "你好");
    assert!(committed.composition_finished);

    engine.change_scheme("xiaohe").expect("switch to xiaohe");
    assert_eq!(engine.scheme_id(), "xiaohe");
    assert_eq!(type_text(&mut engine, "ni").current_pinyin, "ni");

    engine.change_scheme("quanpin").expect("switch to quanpin");
    assert_eq!(engine.scheme_id(), "quanpin");
    assert!(engine.current_state().raw_input.is_empty());
    assert_eq!(type_text(&mut engine, "nihao").current_pinyin, "ni'hao");
}

#[test]
fn quanpin_manual_rules_use_a_namespace_separate_from_xiaohe_raw_codes() {
    let user_path = unique_path("user", "txt");
    fs::write(&user_path, "双拼专属\tni#固\n全拼专属\tqpni#固\n").expect("user lexicon write");

    let mut quanpin = engine("quanpin", Some(&user_path));
    let quanpin_result = type_text(&mut quanpin, "ni");
    assert_eq!(quanpin_result.candidates[0].text, "全拼专属");
    assert!(!candidate_texts(&quanpin_result).contains(&"双拼专属"));

    let mut xiaohe = engine("xiaohe", Some(&user_path));
    let xiaohe_result = type_text(&mut xiaohe, "ni");
    assert_eq!(xiaohe_result.candidates[0].text, "双拼专属");
    assert!(!candidate_texts(&xiaohe_result).contains(&"全拼专属"));
}

#[test]
fn long_quanpin_never_commits_without_an_explicit_user_action() {
    let mut engine = engine("quanpin", None);
    let chunk = "ni".repeat(12);
    let before_split = type_text(&mut engine, &chunk);
    assert!(before_split.success);
    assert_eq!(before_split.raw_input.len(), 24);
    assert!(!before_split.candidates.is_empty());

    let continued = engine.process_key('h');

    assert!(continued.success);
    assert!(continued.commit_text.is_empty());
    assert_eq!(continued.raw_input, format!("{chunk}h"));
    assert!(!continued.composition_finished);
}

#[test]
fn quanpin_initials_and_mixed_spelling_share_the_editable_lattice() {
    let mut engine = engine("quanpin", None);
    for raw in ["gj", "gjt", "guojt", "gjitian"] {
        engine.reset();
        let result = type_text(&mut engine, raw);
        assert_eq!(result.raw_input, raw);
        assert!(result.commit_text.is_empty());
        assert!(!result.composition_finished);
        assert!(candidate_texts(&result).contains(&"过几天"), "{raw}");
    }
}

#[test]
fn quanpin_has_no_fixed_length_gate_and_backspace_restores_state() {
    let mut engine = engine("quanpin", None);
    for index in 1..=320 {
        let last = engine.process_key('v');
        assert!(last.success, "letter {index}");
        assert!(last.commit_text.is_empty(), "letter {index}");
        assert!(!last.composition_finished, "letter {index}");
        assert_eq!(last.raw_input.len(), index, "letter {index}");
        if [32, 64, 128, 256, 320].contains(&index) {
            assert_eq!(last.raw_input, "v".repeat(index));
        }
    }

    let restored = engine.backspace();
    assert!(restored.success);
    assert_eq!(restored.raw_input.len(), 319);
    assert!(restored.commit_text.is_empty());
    assert!(!restored.composition_finished);
}

#[test]
fn incomplete_tail_retains_a_covered_prefix_candidate_and_partial_selection() {
    let mut engine = engine("quanpin", None);
    let stable = type_text(&mut engine, "nihao");
    assert!(candidate_texts(&stable).contains(&"你好"));

    let tailed = type_text(&mut engine, "qx");
    assert_eq!(tailed.raw_input, "nihaoqx");
    assert_eq!(tailed.pending_code, "qx");
    assert!(tailed.commit_text.is_empty());
    let index = tailed
        .candidates
        .iter()
        .position(|candidate| candidate.text == "你好")
        .expect("stable prefix candidate");
    assert_eq!(tailed.candidates[index].consumed_raw_len, 5);

    let committed = engine.select_candidate(index).expect("partial selection");
    assert_eq!(committed.commit_text, "你好");
    assert_eq!(committed.raw_input, "qx");
    assert!(!committed.composition_finished);
}
