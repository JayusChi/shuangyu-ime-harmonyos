use shuangpin_parser::{ParseError, ParseStatus, ParserState, QueryIntent, ShuangpinParser};
use shuangpin_schema::{load_builtin_schema, SchemaError};

const CASES: &str = include_str!("../../../tests/fixtures/stage4_parser_cases.tsv");

#[test]
fn parser_fixture_cases_match_expected_results() {
    for (line_no, line) in CASES.lines().enumerate() {
        let line_no = line_no + 1;
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }

        let columns = line.split('\t').collect::<Vec<_>>();
        assert_eq!(columns.len(), 6, "fixture line {line_no}: {line}");

        let code = columns[1];
        let expected_status = parse_status(columns[2].trim());
        let expected_syllables = split_csv(columns[3]);
        let expected_pending = columns[4].trim();
        let expected_error = columns[5].trim();

        let mut parser = ShuangpinParser::xiaohe().unwrap();
        let result = parser.process_str(code);

        assert_eq!(result.status, expected_status, "fixture line {line_no}");
        assert_eq!(
            result
                .syllables
                .iter()
                .map(|item| item.syllable.as_str())
                .collect::<Vec<_>>(),
            expected_syllables,
            "fixture line {line_no}"
        );
        assert_eq!(
            result.pending_code, expected_pending,
            "fixture line {line_no}"
        );
        assert_error_kind(result.error.as_ref(), expected_error, line_no);
    }
}

#[test]
fn invalid_key_classes_are_rejected_without_panic() {
    for input in ["N", "1", "!", " ", "你"] {
        let mut parser = ShuangpinParser::xiaohe().unwrap();
        let result = parser.process_str(input);
        assert_eq!(result.status, ParseStatus::Invalid, "input={input:?}");
        assert!(matches!(result.error, Some(ParseError::InvalidKey { .. })));
    }
}

#[test]
fn backspace_covers_empty_incomplete_complete_multi_and_invalid_states() {
    let mut parser = ShuangpinParser::xiaohe().unwrap();
    assert_eq!(parser.backspace().status, ParseStatus::Empty);

    parser.process_str("n");
    assert_eq!(parser.state(), ParserState::Incomplete);
    assert_eq!(parser.backspace().status, ParseStatus::Empty);

    parser.process_str("ni");
    assert_eq!(parser.state(), ParserState::CompleteSequence);
    let result = parser.backspace();
    assert_eq!(result.status, ParseStatus::Incomplete);
    assert_eq!(result.pending_code, "n");

    parser.reset();
    parser.process_str("nixm");
    assert_eq!(parser.current_state().syllables.len(), 2);
    assert_eq!(parser.backspace().status, ParseStatus::Incomplete);
    assert_eq!(parser.backspace().status, ParseStatus::Complete);
    assert_eq!(parser.current_state().syllables[0].syllable, "ni");

    parser.process_key('1');
    assert_eq!(parser.state(), ParserState::Invalid);
    assert_eq!(parser.backspace().status, ParseStatus::Complete);

    for _ in 0..8 {
        parser.backspace();
    }
    assert_eq!(parser.state(), ParserState::Empty);
}

#[test]
fn query_intent_follows_the_xiaohe_single_complete_partial_and_multi_contract() {
    for key in ['h', 'a', 'o'] {
        let mut parser = ShuangpinParser::xiaohe().unwrap();
        let result = parser.process_key(key);
        assert_eq!(result.query_intent, QueryIntent::SingleKeyPrefix);
        assert!(result.syllables.is_empty());
        assert_eq!(result.pending_code, key.to_string());
    }

    for code in ["hc", "ni", "ui", "vi", "aa", "oo"] {
        let mut parser = ShuangpinParser::xiaohe().unwrap();
        assert_eq!(
            parser.process_str(code).query_intent,
            QueryIntent::CompleteSyllable,
            "code={code}"
        );
    }

    let mut parser = ShuangpinParser::xiaohe().unwrap();
    assert_eq!(
        parser.process_str("nih").query_intent,
        QueryIntent::IncompleteSyllable
    );
    assert_eq!(
        parser.process_key('c').query_intent,
        QueryIntent::MultiSyllable
    );
    assert_eq!(parser.process_key('1').query_intent, QueryIntent::Invalid);
}

#[test]
fn ambiguous_complete_code_is_one_logical_syllable_intent() {
    let mut parser = ShuangpinParser::xiaohe().unwrap();
    let result = parser.process_str("lo");

    assert_eq!(result.status, ParseStatus::Ambiguous);
    assert_eq!(result.query_intent, QueryIntent::CompleteSyllable);
    assert_eq!(result.logical_syllable_count, 1);
    assert_eq!(
        result
            .syllables
            .iter()
            .map(|syllable| syllable.logical_index)
            .collect::<Vec<_>>(),
        vec![0, 0]
    );
    assert_eq!(
        result
            .syllables
            .iter()
            .map(|syllable| syllable.syllable.as_str())
            .collect::<Vec<_>>(),
        vec!["lo", "luo"]
    );

    let repeated = parser.process_str("lo");
    assert_eq!(repeated.query_intent, QueryIntent::MultiSyllable);
    assert_eq!(repeated.logical_syllable_count, 2);
    assert_eq!(
        repeated
            .syllables
            .iter()
            .map(|syllable| syllable.logical_index)
            .collect::<Vec<_>>(),
        vec![0, 0, 1, 1]
    );
}

#[test]
fn query_intent_rolls_back_one_level_per_backspace() {
    let mut parser = ShuangpinParser::xiaohe().unwrap();
    assert_eq!(
        parser.process_str("nihc").query_intent,
        QueryIntent::MultiSyllable
    );
    assert_eq!(
        parser.backspace().query_intent,
        QueryIntent::IncompleteSyllable
    );
    assert_eq!(
        parser.backspace().query_intent,
        QueryIntent::CompleteSyllable
    );
    assert_eq!(
        parser.backspace().query_intent,
        QueryIntent::SingleKeyPrefix
    );
    assert_eq!(parser.backspace().query_intent, QueryIntent::Empty);
}

#[test]
fn reset_allows_clean_reentry() {
    let mut parser = ShuangpinParser::xiaohe().unwrap();
    parser.process_str("nixm");
    assert_eq!(parser.reset().status, ParseStatus::Empty);
    let result = parser.process_str("vh");
    assert_eq!(result.syllables[0].syllable, "zhang");
}

#[test]
fn schema_switch_clears_state_and_invalid_switch_preserves_parser() {
    let mut parser = ShuangpinParser::xiaohe().unwrap();
    parser.process_str("ni");

    let mut test_schema = load_builtin_schema("xiaohe").unwrap().schema().clone();
    test_schema.id = "test-xiaohe".to_owned();
    let switched = parser.change_schema(test_schema).unwrap();
    assert_eq!(switched.status, ParseStatus::Empty);
    assert_eq!(parser.schema_id(), "test-xiaohe");
    assert_eq!(parser.raw_code(), "");

    let mut invalid_schema = load_builtin_schema("xiaohe").unwrap().schema().clone();
    invalid_schema.id.clear();
    assert!(matches!(
        parser.change_schema(invalid_schema),
        Err(ParseError::Schema(SchemaError::EmptyId))
    ));
    assert_eq!(parser.schema_id(), "test-xiaohe");
    assert_eq!(parser.process_str("xm").syllables[0].syllable, "xian");
}

#[test]
fn unknown_schema_returns_structured_error() {
    assert!(matches!(
        load_builtin_schema("missing"),
        Err(SchemaError::SchemaNotFound { .. })
    ));
}

#[test]
fn short_ascii_sequences_do_not_panic() {
    let mut parser = ShuangpinParser::xiaohe().unwrap();
    for byte in 0_u8..=127 {
        parser.process_key(byte as char);
    }
    for _ in 0..256 {
        parser.backspace();
    }
    for _ in 0..16 {
        parser.reset();
    }
    assert_eq!(parser.state(), ParserState::Empty);
}

#[test]
fn repeated_schema_switches_do_not_break_state() {
    let mut parser = ShuangpinParser::xiaohe().unwrap();
    let schema = load_builtin_schema("xiaohe").unwrap().schema().clone();

    for index in 0..16 {
        let mut next = schema.clone();
        next.id = format!("test-{index}");
        assert!(parser.change_schema(next).is_ok());
        assert_eq!(parser.process_str("ni").syllables[0].syllable, "ni");
        parser.reset();
    }
}

fn parse_status(value: &str) -> ParseStatus {
    match value {
        "Empty" => ParseStatus::Empty,
        "Incomplete" => ParseStatus::Incomplete,
        "Complete" => ParseStatus::Complete,
        "Invalid" => ParseStatus::Invalid,
        "Ambiguous" => ParseStatus::Ambiguous,
        other => panic!("unknown status in fixture: {other}"),
    }
}

fn split_csv(value: &str) -> Vec<&str> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        Vec::new()
    } else {
        trimmed.split(',').collect()
    }
}

fn assert_error_kind(error: Option<&ParseError>, expected: &str, line_no: usize) {
    match expected {
        "none" => assert!(error.is_none(), "fixture line {line_no}"),
        "InvalidCode" => assert!(
            matches!(error, Some(ParseError::InvalidCode { .. })),
            "fixture line {line_no}: {error:?}"
        ),
        "InvalidKey" => assert!(
            matches!(error, Some(ParseError::InvalidKey { .. })),
            "fixture line {line_no}: {error:?}"
        ),
        other => panic!("unknown error kind in fixture line {line_no}: {other}"),
    }
}
