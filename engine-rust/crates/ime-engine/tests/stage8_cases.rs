use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::{build_binary_lexicon, LexiconEntry};

const CASES: &str = include_str!("../../../tests/fixtures/stage8_sentence_cases.tsv");

#[test]
fn stage8_sentence_regression_cases_match_test_lexicon() {
    for (line_no, line) in CASES.lines().enumerate() {
        let line_no = line_no + 1;
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let columns = line.split('\t').collect::<Vec<_>>();
        assert_eq!(columns.len(), 9, "fixture line {line_no}: {line}");

        let raw_code = columns[0];
        let expected_syllables = split_csv(columns[1]);
        let expected_top = columns[2];
        let allowed = split_pipe(columns[3]);
        let forbidden = split_pipe(columns[4]);
        let partial_allowed = parse_bool(columns[5]);
        let partial_text = columns[6];
        let remaining_raw = columns[7];
        let expected_remaining_top = columns[8];

        let mut engine = create_engine(8);
        let mut result = engine.current_state();
        for key in raw_code.chars() {
            result = engine.process_key(key);
        }

        assert!(result.success, "fixture line {line_no}: {line}");
        assert_eq!(
            result.parsed_syllables, expected_syllables,
            "fixture line {line_no}"
        );
        assert_eq!(
            result
                .candidates
                .first()
                .map(|candidate| candidate.text.as_str()),
            Some(expected_top),
            "fixture line {line_no}"
        );

        for text in allowed {
            assert!(
                result
                    .candidates
                    .iter()
                    .any(|candidate| candidate.text == text),
                "fixture line {line_no}: missing allowed candidate {text}"
            );
        }
        for text in forbidden {
            assert!(
                result
                    .candidates
                    .iter()
                    .all(|candidate| candidate.text != text),
                "fixture line {line_no}: forbidden candidate {text}"
            );
        }

        if partial_allowed {
            let partial_index = result
                .candidates
                .iter()
                .position(|candidate| candidate.text == partial_text)
                .expect("partial candidate should exist");
            let after_partial = engine.select_candidate(partial_index).unwrap();
            assert_eq!(
                after_partial.commit_text, partial_text,
                "fixture line {line_no}"
            );
            assert_eq!(
                after_partial.raw_input, remaining_raw,
                "fixture line {line_no}"
            );
            assert!(
                !after_partial.composition_finished,
                "fixture line {line_no}"
            );
            assert_eq!(
                after_partial
                    .candidates
                    .first()
                    .map(|candidate| candidate.text.as_str()),
                Some(expected_remaining_top),
                "fixture line {line_no}"
            );
        }
    }
}

fn create_engine(page_size: usize) -> ImeEngine {
    let path = create_test_lexicon();
    ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .unwrap()
}

fn create_test_lexicon() -> PathBuf {
    let entries = vec![
        entry("你", "ni", 100_000),
        entry("好", "hao", 95_000),
        entry("你好", "ni hao", 120_000),
        entry("法", "fa", 80_000),
        entry("输入", "shu ru", 82_000),
        entry("输入法", "shu ru fa", 90_000),
        entry("小鹤", "xiao he", 85_000),
        entry("双拼", "shuang pin", 84_000),
        entry("小鹤双拼", "xiao he shuang pin", 88_000),
        entry("期间", "qi jian", 70_000),
        entry("其间", "qi jian", 70_000),
    ];
    let bytes = build_binary_lexicon(&entries, 8, 1).unwrap();
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!("stage8-cases-{nanos}.lex"));
    fs::write(&path, bytes).unwrap();
    path
}

fn entry(word: &str, pinyin: &str, frequency: u64) -> LexiconEntry {
    LexiconEntry::new(
        word.to_owned(),
        pinyin.to_owned(),
        pinyin.split(' ').map(str::to_owned).collect(),
        frequency,
        vec!["stage8".to_owned()],
    )
}

fn split_csv(value: &str) -> Vec<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        Vec::new()
    } else {
        trimmed.split(',').map(str::to_owned).collect()
    }
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
