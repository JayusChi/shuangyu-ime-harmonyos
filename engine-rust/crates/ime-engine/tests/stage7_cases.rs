use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::{build_binary_lexicon, LexiconEntry};

const CASES: &str = include_str!("../../../tests/fixtures/stage7_candidate_cases.tsv");

#[test]
fn stage7_candidate_regression_cases_match_test_lexicon() {
    for (line_no, line) in CASES.lines().enumerate() {
        let line_no = line_no + 1;
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let columns = line.split('\t').collect::<Vec<_>>();
        assert_eq!(columns.len(), 9, "fixture line {line_no}: {line}");

        let raw_code = columns[0];
        let expected_syllables = split_csv(columns[1]);
        let expected_first_page = split_pipe(columns[3]);
        let must_contain = split_pipe(columns[4]);
        let forbidden = split_pipe(columns[5]);
        let expected_top = columns[6];
        let expected_has_next = parse_bool(columns[7]);
        let expected_commit = columns[8];

        let mut engine = create_engine(5);
        let mut result = engine.current_state();
        for key in raw_code.chars() {
            result = engine.process_key(key);
        }

        assert_eq!(
            result.parsed_syllables, expected_syllables,
            "fixture line {line_no}"
        );
        let actual_first_page = result
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect::<Vec<_>>();
        assert!(
            actual_first_page.starts_with(&expected_first_page),
            "fixture line {line_no}: actual={actual_first_page:?}, expected prefix={expected_first_page:?}"
        );
        for text in must_contain {
            assert!(
                result
                    .candidates
                    .iter()
                    .any(|candidate| candidate.text == text),
                "fixture line {line_no}: missing {text}"
            );
        }
        for text in forbidden {
            assert!(
                result.candidates.iter().all(|candidate| {
                    candidate.text != text
                        || (expected_syllables.len() > 1
                            && candidate.reading.split_whitespace().count()
                                < expected_syllables.len())
                }),
                "fixture line {line_no}: forbidden {text}"
            );
        }
        assert_eq!(
            result
                .candidates
                .first()
                .map(|candidate| candidate.text.as_str()),
            Some(expected_top),
            "fixture line {line_no}"
        );
        assert_eq!(
            result.has_next_page, expected_has_next,
            "fixture line {line_no}"
        );

        let committed = engine.select_candidate(0).unwrap();
        assert_eq!(
            committed.commit_text, expected_commit,
            "fixture line {line_no}"
        );
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
        LexiconEntry::new(
            "你".to_owned(),
            "ni".to_owned(),
            vec!["ni".to_owned()],
            100_000,
            vec!["stage7".to_owned()],
        ),
        LexiconEntry::new(
            "你好".to_owned(),
            "ni hao".to_owned(),
            vec!["ni".to_owned(), "hao".to_owned()],
            72_000,
            vec!["stage7".to_owned()],
        ),
        LexiconEntry::new(
            "输入".to_owned(),
            "shu ru".to_owned(),
            vec!["shu".to_owned(), "ru".to_owned()],
            82_000,
            vec!["stage7".to_owned()],
        ),
        LexiconEntry::new(
            "输入法".to_owned(),
            "shu ru fa".to_owned(),
            vec!["shu".to_owned(), "ru".to_owned(), "fa".to_owned()],
            81_000,
            vec!["stage7".to_owned()],
        ),
        LexiconEntry::new(
            "其间".to_owned(),
            "qi jian".to_owned(),
            vec!["qi".to_owned(), "jian".to_owned()],
            49_000,
            vec!["stage7".to_owned()],
        ),
        LexiconEntry::new(
            "期间".to_owned(),
            "qi jian".to_owned(),
            vec!["qi".to_owned(), "jian".to_owned()],
            50_000,
            vec!["stage7".to_owned()],
        ),
    ];
    let bytes = build_binary_lexicon(&entries, 7, 1).unwrap();
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!("stage7-cases-{nanos}.lex"));
    fs::write(&path, bytes).unwrap();
    path
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
