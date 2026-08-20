use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use engine_protocol::CompositionResult;
use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::{build_binary_lexicon, LexiconEntry};
use shuangpin_parser::T9PinyinParser;

fn unique_path(label: &str, extension: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();
    std::env::temp_dir().join(format!(
        "pinyin9-stage3-{label}-{}-{nanos}.{extension}",
        std::process::id()
    ))
}

fn entry(text: &str, reading: &str, frequency: u64) -> LexiconEntry {
    LexiconEntry::new(
        text.to_owned(),
        reading.to_owned(),
        reading.split_whitespace().map(str::to_owned).collect(),
        frequency,
        vec!["pinyin9-stage3".to_owned()],
    )
}

fn lexicon_path_for(entries: Vec<LexiconEntry>) -> PathBuf {
    let path = unique_path("lexicon", "lex");
    fs::write(
        &path,
        build_binary_lexicon(&entries, 3, 1).expect("lexicon build"),
    )
    .expect("lexicon write");
    path
}

fn engine(page_size: usize) -> ImeEngine {
    engine_with_entries(
        page_size,
        vec![
            entry("你", "ni", 100_000),
            entry("米", "mi", 60_000),
            entry("嗯", "ng", 30_000),
            entry("好", "hao", 99_000),
            entry("干", "gan", 40_000),
            entry("高", "gao", 70_000),
            entry("汉", "han", 50_000),
            entry("你好", "ni hao", 150_000),
            entry("米好", "mi hao", 20_000),
            entry("你干", "ni gan", 10_000),
            entry("熊", "xiong", 80_000),
        ],
    )
}

fn engine_with_entries(page_size: usize, entries: Vec<LexiconEntry>) -> ImeEngine {
    ImeEngine::new(EngineConfig {
        scheme_id: "pinyin-9".to_owned(),
        lexicon_path: Some(lexicon_path_for(entries).to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("T9 engine")
}

fn type_digits(engine: &mut ImeEngine, digits: &str) -> CompositionResult {
    let mut result = engine.current_state();
    for digit in digits.chars() {
        result = engine.process_key(digit);
    }
    result
}

fn published_combinations(result: &CompositionResult) -> Vec<String> {
    let mut values = vec![result.current_pinyin.clone()];
    values.extend(result.pinyin_combinations.clone());
    values
}

fn candidate_texts(result: &CompositionResult) -> Vec<&str> {
    result
        .candidates
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect()
}

#[test]
fn digits_64_recall_ni_and_switching_replaces_candidate_snapshot() {
    let mut engine = engine(20);
    let result = type_digits(&mut engine, "64");
    let combinations = published_combinations(&result);

    assert!(result.success);
    assert!(combinations.contains(&"ni".to_owned()));
    assert!(candidate_texts(&result).contains(&"你"));
    assert!(candidate_texts(&result).contains(&"米"));

    let ni_index = combinations.iter().position(|value| value == "ni").unwrap();
    let selected_ni = engine
        .select_pinyin_combination(ni_index)
        .expect("select ni");
    assert_eq!(selected_ni.current_pinyin, "ni");
    assert!(candidate_texts(&selected_ni).contains(&"你"));
    assert!(!candidate_texts(&selected_ni).contains(&"米"));

    let published = published_combinations(&selected_ni);
    let mi_index = published.iter().position(|value| value == "mi").unwrap();
    let selected_mi = engine
        .select_pinyin_combination(mi_index)
        .expect("select mi");
    assert_eq!(selected_mi.current_pinyin, "mi");
    assert!(candidate_texts(&selected_mi).contains(&"米"));
    assert!(!candidate_texts(&selected_mi).contains(&"你"));
}

#[test]
fn digits_64426_recall_nihao_and_existing_sentence_decoder() {
    let mut engine = engine(20);
    let result = type_digits(&mut engine, "64426");

    assert!(published_combinations(&result).contains(&"ni'hao".to_owned()));
    assert!(candidate_texts(&result).contains(&"你好"));
    let nihao = result
        .candidates
        .iter()
        .find(|candidate| candidate.text == "你好")
        .expect("你好 candidate");
    assert_eq!(nihao.reading, "ni hao");
    assert_eq!(nihao.consumed_raw_len, 5);
}

#[test]
fn explicit_boundary_delete_and_digit_delete_recompute_all_public_state() {
    let mut engine = engine(2);
    let first = type_digits(&mut engine, "64");
    let ni_index = published_combinations(&first)
        .iter()
        .position(|value| value == "ni")
        .unwrap();
    engine
        .select_pinyin_combination(ni_index)
        .expect("select ni");
    let boundary = engine.insert_segment_boundary().expect("boundary");
    assert_eq!(boundary.raw_input, "64");
    assert_eq!(boundary.segment_boundaries, [2]);

    let full = type_digits(&mut engine, "426");
    assert!(published_combinations(&full).contains(&"ni'hao".to_owned()));
    assert!(candidate_texts(&full).contains(&"你好"));
    assert_eq!(full.candidate_page, 0);

    let deleted = engine.backspace();
    assert_eq!(deleted.raw_input, "6442");
    assert_eq!(deleted.candidate_page, 0);
    assert!(!candidate_texts(&deleted).contains(&"你好"));

    engine.backspace();
    engine.backspace();
    let boundary_deleted = engine.backspace();
    assert_eq!(boundary_deleted.raw_input, "64");
    assert!(boundary_deleted.segment_boundaries.is_empty());
    assert!(published_combinations(&boundary_deleted).contains(&"ni".to_owned()));
    assert!(candidate_texts(&boundary_deleted).contains(&"你"));
}

#[test]
fn reset_scheme_switch_invalid_selection_and_long_collision_input_are_bounded() {
    let mut engine = engine(10);
    let mut at_limit = None;
    for index in 0..100 {
        let result = engine.process_key('6');
        if index < 64 {
            assert!(result.success);
            if index == 63 {
                at_limit = Some(result.clone());
            }
        } else {
            assert!(!result.success);
            assert_eq!(result.raw_input.len(), 64);
            assert_eq!(result.candidates, at_limit.as_ref().unwrap().candidates);
            assert!(result.error_message.contains("limited to 64 digits"));
        }
        assert!(result.commit_text.is_empty());
        assert!(!result.composition_finished);
    }
    assert_eq!(engine.current_state().raw_input.len(), 64);
    assert!(engine.select_pinyin_combination(usize::MAX).is_err());

    let reset = engine.reset();
    assert!(reset.raw_input.is_empty());
    assert!(reset.current_pinyin.is_empty());
    assert!(reset.pinyin_combinations.is_empty());
    assert!(reset.candidates.is_empty());

    engine.change_scheme("quanpin").expect("quanpin");
    assert_eq!(engine.scheme_id(), "quanpin");
    assert!(engine.process_key('n').success);
    engine.change_scheme("pinyin-9").expect("T9");
    assert_eq!(engine.scheme_id(), "pinyin-9");
    assert!(engine.current_state().raw_input.is_empty());
    assert!(engine.process_key('6').success);
    assert!(!engine.process_key('n').success);
}

#[test]
fn unfinished_digit_prefix_recalls_legal_pinyin_prefix_candidates() {
    let mut engine = engine(20);
    let result = type_digits(&mut engine, "9");

    assert_eq!(
        result.parser_state,
        engine_protocol::ProtocolParserState::Incomplete
    );
    assert!(published_combinations(&result)
        .iter()
        .any(|value| value == "x"));
    assert!(candidate_texts(&result).contains(&"熊"));
}

#[test]
fn repeated_collision_runs_are_identical() {
    let mut baseline_engine = engine(20);
    let baseline = type_digits(&mut baseline_engine, "64426");
    for _ in 0..10 {
        let mut repeated = engine(20);
        assert_eq!(type_digits(&mut repeated, "64426"), baseline);
    }
}

#[test]
fn lexicon_score_promotes_a_legal_path_that_was_beyond_public_32() {
    let digits = ["6442664426", "742674267426", "942644269426"]
        .into_iter()
        .find(|digits| {
            let mut parser = T9PinyinParser::new();
            parser.process_str(digits);
            parser.internal_combinations().len() > 32
        })
        .expect("collision fixture with more than 32 paths");
    let mut parser = T9PinyinParser::new();
    let parser_result = parser.process_str(digits);
    let parser_public = {
        let mut values = vec![parser_result.current_pinyin];
        values.extend(parser_result.pinyin_combinations);
        values
    };
    let internal = parser.internal_combinations();
    assert!(internal.len() > 32, "fixture must have more than 32 paths");
    let target_path = internal
        .iter()
        .find(|path| !parser_public.contains(path))
        .expect("internally retained path beyond public limit")
        .clone();
    let target_reading = target_path.replace('\'', " ");
    let mut joint_engine =
        engine_with_entries(9, vec![entry("联合优选", &target_reading, 900_000)]);

    let result = type_digits(&mut joint_engine, digits);

    assert_eq!(result.current_pinyin, target_path);
    assert!(published_combinations(&result).contains(&target_path));
    assert_eq!(result.candidates[0].text, "联合优选");
    let stats = joint_engine.last_t9_joint_stats();
    assert!(stats.lexicon_reachable_paths.contains(&target_path));
    assert!(stats.parser_internal_hypotheses > 32);
}

#[test]
fn explicit_boundary_is_a_hard_constraint_for_joint_lexicon_edges() {
    let entries = vec![
        entry("单音优先", "mian", 900_000),
        entry("分音保留", "mi an", 10_000),
    ];
    let mut unconstrained = engine_with_entries(9, entries.clone());
    assert!(type_digits(&mut unconstrained, "6426")
        .candidates
        .iter()
        .any(|item| item.text == "单音优先"));

    let mut constrained = engine_with_entries(9, entries);
    type_digits(&mut constrained, "64");
    constrained.insert_segment_boundary().expect("boundary");
    let result = type_digits(&mut constrained, "26");

    assert_eq!(result.segment_boundaries, [2]);
    assert!(result.candidates.iter().any(|item| item.text == "分音保留"));
    assert!(!result.candidates.iter().any(|item| item.text == "单音优先"));
}

#[test]
fn pagination_is_lossless_duplicate_free_and_stable() {
    let entries = (0..30)
        .map(|index| entry(&format!("候选{index:02}"), "ni", 100_000 - index))
        .collect::<Vec<_>>();
    let collect = |engine: &mut ImeEngine| {
        let mut state = type_digits(engine, "64");
        let mut values = state
            .candidates
            .iter()
            .map(|item| item.text.clone())
            .collect::<Vec<_>>();
        while state.has_next_page {
            state = engine.next_candidate_page().expect("next page");
            values.extend(state.candidates.iter().map(|item| item.text.clone()));
        }
        values
    };
    let mut first_engine = engine_with_entries(3, entries.clone());
    let first = collect(&mut first_engine);
    let mut second_engine = engine_with_entries(3, entries);
    let second = collect(&mut second_engine);

    assert_eq!(first, second);
    assert_eq!(first.len(), 30);
    assert_eq!(
        first
            .iter()
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        30
    );
}

#[test]
fn whole_word_digit_match_outranks_legacy_over_segmented_sentence() {
    let mut engine = engine_with_entries(
        9,
        vec![
            entry("帮助", "bang zhu", 10),
            entry("啊", "a", 1_000_000),
            entry("你", "ni", 1_000_000),
            entry("住", "zhu", 1_000_000),
        ],
    );

    let result = type_digits(&mut engine, "2264948");

    assert_eq!(result.candidates[0].text, "帮助");
    assert!(result
        .candidates
        .iter()
        .any(|candidate| candidate.text == "啊啊你住"));
}

#[test]
fn joint_sentence_score_can_outrank_parser_first_over_segmentation() {
    let mut engine = engine_with_entries(
        9,
        vec![
            entry("认真", "ren zhen", 80_000),
            entry("工作", "gong zuo", 100_000),
            entry("任意", "ren yi", 80_000),
            entry("恩", "en", 80_000),
        ],
    );

    // `ren zhen` and `ren yi en` have the same T9 signature. The joint
    // decoder's less fragmented sentence must be allowed to beat the first
    // parser path instead of being forced into a lower publication tier.
    let result = type_digits(&mut engine, "73694364664986");

    assert_eq!(result.candidates[0].text, "认真工作");
    assert!(result
        .candidates
        .iter()
        .any(|candidate| candidate.text == "任意恩工作"));
}
