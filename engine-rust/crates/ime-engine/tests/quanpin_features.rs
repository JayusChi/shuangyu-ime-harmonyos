use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use ime_engine::{EngineConfig, FuzzyOption, ImeEngine, QuanpinFeatureConfig};
use lexicon_core::{build_binary_lexicon, LexiconEntry};

fn entry(text: &str, reading: &str, frequency: u64) -> LexiconEntry {
    LexiconEntry::new(
        text.to_owned(),
        reading.to_owned(),
        reading.split_whitespace().map(str::to_owned).collect(),
        frequency,
        vec!["quanpin-feature-test".to_owned()],
    )
}

fn test_lexicon(crowd_ni_prefix: bool) -> PathBuf {
    let mut entries = vec![
        entry("你好", "ni hao", 100_000),
        entry("泥好", "ni hao", 90_000),
        entry("拟好", "ni hao", 80_000),
        entry("你", "ni", 70_000),
        entry("资", "zi", 69_000),
        entry("次", "ci", 68_000),
        entry("四", "si", 67_000),
        entry("心", "xin", 66_000),
        entry("岑", "cen", 65_000),
        entry("蓝", "lan", 64_000),
        entry("先", "xian", 63_000),
    ];
    for (index, reading) in ["ni ba", "ni ma", "ni ne", "ni la"].into_iter().enumerate() {
        entries.push(entry(
            &format!("倪{index}"),
            reading,
            400_000 - index as u64,
        ));
    }
    if crowd_ni_prefix {
        for index in 0..4 {
            entries.push(entry(&format!("妮{index}"), "ni", 500_000 - index as u64));
        }
    }
    for (group, reading) in ["li", "zhi", "chi", "shi", "xing", "ceng", "lang", "xiang"]
        .into_iter()
        .enumerate()
    {
        for index in 0..4 {
            entries.push(entry(
                &format!("占{group}{index}"),
                reading,
                300_000 - (group as u64 * 10 + index as u64),
            ));
        }
    }
    let bytes = build_binary_lexicon(&entries, 1, 1).expect("build feature lexicon");
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();
    let path = std::env::temp_dir().join(format!("quanpin-features-{nanos}.lex"));
    fs::write(&path, bytes).expect("write feature lexicon");
    path
}

fn engine(spelling: bool, fuzzy: &[FuzzyOption]) -> ImeEngine {
    ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        lexicon_path: Some(test_lexicon(spelling).to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 100,
        quanpin_features: QuanpinFeatureConfig::new(spelling, fuzzy.iter().copied()),
        quanpin_context_reranking: Default::default(),
    })
    .expect("quanpin feature engine")
}

fn type_text(engine: &mut ImeEngine, input: &str) -> engine_protocol::CompositionResult {
    let mut result = engine.current_state();
    for key in input.chars() {
        result = engine.process_key(key);
        assert!(result.success, "key {key} failed for {input}");
    }
    result
}

fn candidate<'a>(
    result: &'a engine_protocol::CompositionResult,
    text: &str,
) -> Option<&'a engine_protocol::FormalCandidate> {
    result
        .candidates
        .iter()
        .find(|candidate| candidate.text == text)
}

#[test]
fn all_four_single_edit_spelling_errors_recall_without_changing_raw_input() {
    let mut enabled = engine(true, &[]);
    let mut disabled = engine(false, &[]);
    for input in ["ihao", "nihxao", "nigao", "niaho"] {
        enabled.reset();
        disabled.reset();
        let corrected = type_text(&mut enabled, input);
        let recalled = corrected
            .candidates
            .iter()
            .find(|item| item.reading == "ni hao" && item.source.starts_with("quanpin-correction-"))
            .unwrap_or_else(|| {
                panic!(
                    "corrected ni hao missing for {input}: {:?}",
                    corrected.candidates
                )
            });
        assert_eq!(corrected.raw_input, input);
        assert_eq!(
            recalled.consumed_raw_len as usize,
            input.len(),
            "input={input}, source={}",
            recalled.source
        );
        assert!(
            recalled.source.starts_with("quanpin-correction-"),
            "input={input}, source={}",
            recalled.source
        );
        assert!(
            enabled
                .last_quanpin_expansion_stats()
                .sentence_decoder_paths
                <= 28
        );
        assert!(type_text(&mut disabled, input)
            .candidates
            .iter()
            .all(|item| !item.source.starts_with("quanpin-correction-")));
    }
}

#[test]
fn every_fuzzy_pair_is_independently_switchable() {
    let cases = [
        (FuzzyOption::Nl, "li", "你"),
        (FuzzyOption::ZZh, "zhi", "资"),
        (FuzzyOption::CCh, "chi", "次"),
        (FuzzyOption::SSh, "shi", "四"),
        (FuzzyOption::InIng, "xing", "心"),
        (FuzzyOption::EnEng, "ceng", "岑"),
        (FuzzyOption::AnAng, "lang", "蓝"),
        (FuzzyOption::IanIang, "xiang", "先"),
    ];
    for (option, input, expected) in cases {
        let fuzzy = type_text(&mut engine(false, &[option]), input);
        let recalled = candidate(&fuzzy, expected).unwrap_or_else(|| {
            panic!(
                "enabled fuzzy candidate missing for {input}: {:?}",
                fuzzy.candidates
            )
        });
        assert_eq!(recalled.source, "quanpin-fuzzy-1");
        assert_eq!(recalled.consumed_raw_len as usize, input.len());
        assert!(candidate(&type_text(&mut engine(false, &[]), input), expected).is_none());
    }
}

#[test]
fn defaults_are_off_and_preserve_exact_candidate_order() {
    let mut implicit = engine(false, &[]);
    let mut explicit = engine(false, &[]);
    let left = type_text(&mut implicit, "nihao");
    let right = type_text(&mut explicit, "nihao");
    assert_eq!(left.candidates, right.candidates);
    assert_eq!(
        left.candidates.first().map(|item| item.text.as_str()),
        Some("你好")
    );
}

#[test]
fn enabled_features_keep_exact_candidates_first_and_stably_deduplicated() {
    let result = type_text(&mut engine(true, &[FuzzyOption::Nl]), "nihao");
    assert_eq!(
        result.candidates.first().map(|item| item.text.as_str()),
        Some("你好")
    );
    assert!(
        !result.candidates[0]
            .source
            .starts_with("quanpin-correction-")
            && !result.candidates[0].source.starts_with("quanpin-fuzzy-"),
        "unexpected clean source: {:?}",
        result.candidates
    );
    let unique = result
        .candidates
        .iter()
        .map(|item| item.text.as_str())
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(unique.len(), result.candidates.len());
    assert!(result.commit_text.is_empty());
    assert_eq!(result.raw_input, "nihao");
}

#[test]
fn feature_candidates_follow_normal_backspace_and_reset_lifecycle() {
    let mut enabled = engine(true, &[]);
    let corrected = type_text(&mut enabled, "nigao");
    assert!(candidate(&corrected, "你好").is_some());
    let after_backspace = enabled.backspace();
    assert_eq!(after_backspace.raw_input, "niga");
    let reset = enabled.reset();
    assert!(reset.raw_input.is_empty());
    assert!(reset.candidates.is_empty());
}

#[test]
fn expansion_output_is_deterministic_across_engines() {
    let first = type_text(&mut engine(true, &[FuzzyOption::Nl]), "nigao");
    let second = type_text(&mut engine(true, &[FuzzyOption::Nl]), "nigao");
    assert_eq!(first.candidates, second.candidates);
}

#[test]
fn confident_exact_result_skips_spelling_but_low_confidence_typo_does_not() {
    let mut enabled = engine(true, &[]);
    let exact = type_text(&mut enabled, "nihao");
    assert_eq!(exact.candidates[0].text, "你好");
    let exact_stats = enabled.last_quanpin_expansion_stats();
    assert!(exact_stats.correction_skipped_high_confidence);
    assert_eq!(exact_stats.correction_query_paths, 0);

    enabled.reset();
    let typo = type_text(&mut enabled, "nigao");
    assert!(candidate(&typo, "你好").is_some());
    assert!(
        !enabled
            .last_quanpin_expansion_stats()
            .correction_skipped_high_confidence
    );
}

#[test]
fn reset_reuses_bounded_expansion_cache_for_the_same_prefix() {
    let mut enabled = engine(true, &[]);
    type_text(&mut enabled, "nigao");
    assert!(!enabled.last_quanpin_expansion_stats().expansion_cache_hit);

    enabled.reset();
    type_text(&mut enabled, "nigao");
    assert!(enabled.last_quanpin_expansion_stats().expansion_cache_hit);
}

#[test]
fn usable_incomplete_syllable_prefix_defers_correction_until_more_input() {
    let mut enabled = engine(true, &[]);
    let incomplete = type_text(&mut enabled, "nih");
    assert_eq!(incomplete.raw_input, "nih");
    let stats = enabled.last_quanpin_expansion_stats();
    assert!(stats.correction_deferred_incomplete);
    assert_eq!(stats.correction_query_paths, 0);

    let corrected = type_text(&mut enabled, "gao");
    assert_eq!(corrected.raw_input, "nihgao");
    assert!(
        !enabled
            .last_quanpin_expansion_stats()
            .correction_deferred_incomplete
    );
}
