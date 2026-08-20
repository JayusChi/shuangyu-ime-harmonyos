use std::path::PathBuf;

use engine_protocol::CompositionResult;
use ime_engine::{EngineConfig, ImeEngine};

const CASES: [(&str, &str); 4] = [
    ("你好", "nihc"),
    ("输入法", "uurufa"),
    ("小鹤", "xnhe"),
    ("双拼", "ulpb"),
];

fn main() {
    let workspace = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let lexicon = workspace.join("dictionaries/generated/production.lex");
    let bundle = workspace
        .join("dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx");
    let config = || EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(lexicon.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 9,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    };

    let mut json = String::from("{\n");
    field_string(
        &mut json,
        1,
        "schema_version",
        "xiaohe-stage0-isolation/1",
        true,
    );
    field_string(&mut json, 1, "scheme_id", "xiaohe", true);
    line(&mut json, 1, "\"text_cases\": [");
    for (case_index, (target, keys)) in CASES.iter().enumerate() {
        let mut engine = ImeEngine::new(config()).expect("xiaohe engine");
        line(&mut json, 2, "{");
        field_string(&mut json, 3, "target_text", target, true);
        field_string(&mut json, 3, "key_sequence", keys, true);
        line(&mut json, 3, "\"intermediate_states\": [");
        for (key_index, key) in keys.chars().enumerate() {
            let result = engine.process_key(key);
            write_state(&mut json, 4, &result);
            if key_index + 1 != keys.len() {
                json.push(',');
            }
            json.push('\n');
        }
        line(&mut json, 3, "],");
        let final_state = engine.current_state();
        field_optional_string(
            &mut json,
            3,
            "first_choice",
            final_state
                .candidates
                .first()
                .map(|candidate| candidate.text.as_str()),
            true,
        );
        field_bool(
            &mut json,
            3,
            "has_next_page",
            final_state.has_next_page,
            true,
        );
        let page_probe = if final_state.has_next_page {
            let next = engine.next_candidate_page().expect("next page");
            engine.previous_candidate_page().expect("previous page");
            format!("next_page_candidate_count={}", next.candidates.len())
        } else {
            "no_next_page".to_owned()
        };
        field_string(&mut json, 3, "paging_probe", &page_probe, true);
        let selected = engine.select_candidate(0).expect("select first");
        field_string(&mut json, 3, "committed_text", &selected.commit_text, true);
        field_bool(
            &mut json,
            3,
            "target_is_first_and_committed",
            final_state
                .candidates
                .first()
                .is_some_and(|candidate| candidate.text == *target)
                && selected.commit_text == *target,
            true,
        );

        let mut deletion_engine = ImeEngine::new(config()).expect("delete engine");
        for key in keys.chars() {
            deletion_engine.process_key(key);
        }
        let deleted = deletion_engine.backspace();
        field_string(
            &mut json,
            3,
            "raw_after_backspace",
            &deleted.raw_input,
            true,
        );
        let reset = deletion_engine.reset();
        field_bool(
            &mut json,
            3,
            "reset_clears_composition",
            reset.raw_input.is_empty() && reset.candidates.is_empty(),
            true,
        );

        let mut recreated = ImeEngine::new(config()).expect("recreated engine");
        let recreated_final = enter(&mut recreated, keys);
        field_bool(
            &mut json,
            3,
            "recreated_session_same_first_choice",
            recreated_final
                .candidates
                .first()
                .map(|candidate| candidate.text.as_str())
                == final_state
                    .candidates
                    .first()
                    .map(|candidate| candidate.text.as_str()),
            false,
        );
        write_indent(&mut json, 2);
        json.push('}');
        if case_index + 1 != CASES.len() {
            json.push(',');
        }
        json.push('\n');
    }
    line(&mut json, 1, "],");

    let mut switching = ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe-yinxing".to_owned(),
        lexicon_path: Some(lexicon.to_string_lossy().into_owned()),
        code_table_bundle_path: Some(bundle.to_string_lossy().into_owned()),
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 9,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("formal engine");
    switching.process_key('n');
    switching
        .change_scheme("xiaohe")
        .expect("switch back to xiaohe");
    let switched = enter(&mut switching, "nihc");
    line(&mut json, 1, "\"scheme_switch_isolation\": {");
    field_string(&mut json, 2, "from_scheme", "xiaohe-yinxing", true);
    field_string(&mut json, 2, "to_scheme", "xiaohe", true);
    field_bool(
        &mut json,
        2,
        "old_composition_cleared",
        switched.raw_input == "nihc",
        true,
    );
    field_optional_string(
        &mut json,
        2,
        "first_choice_after_return",
        switched
            .candidates
            .first()
            .map(|candidate| candidate.text.as_str()),
        true,
    );
    field_bool(
        &mut json,
        2,
        "xiaohe_result_restored",
        switched
            .candidates
            .first()
            .is_some_and(|candidate| candidate.text == "你好"),
        false,
    );
    line(&mut json, 1, "}");
    json.push_str("}\n");
    print!("{json}");
}

fn enter(engine: &mut ImeEngine, keys: &str) -> CompositionResult {
    let mut result = engine.current_state();
    for key in keys.chars() {
        result = engine.process_key(key);
        assert!(result.success, "{}", result.error_message);
    }
    result
}

fn write_state(json: &mut String, indent: usize, result: &CompositionResult) {
    line(json, indent, "{");
    field_string(json, indent + 1, "raw_input", &result.raw_input, true);
    field_string(json, indent + 1, "preedit_text", &result.preedit_text, true);
    field_string_array(
        json,
        indent + 1,
        "parsed_syllables",
        &result.parsed_syllables,
        true,
    );
    field_string(
        json,
        indent + 1,
        "parser_state",
        result.parser_state.as_str(),
        true,
    );
    line(json, indent + 1, "\"first_page\": [");
    for (index, candidate) in result.candidates.iter().enumerate() {
        line(json, indent + 2, "{");
        field_string(json, indent + 3, "id", &candidate.id, true);
        field_string(json, indent + 3, "text", &candidate.text, true);
        field_string(json, indent + 3, "reading", &candidate.reading, true);
        field_string(json, indent + 3, "source", &candidate.source, false);
        write_indent(json, indent + 2);
        json.push('}');
        if index + 1 != result.candidates.len() {
            json.push(',');
        }
        json.push('\n');
    }
    line(json, indent + 1, "]");
    write_indent(json, indent);
    json.push('}');
}

fn field_string(json: &mut String, indent: usize, name: &str, value: &str, comma: bool) {
    write_indent(json, indent);
    json.push_str(&quote(name));
    json.push_str(": ");
    json.push_str(&quote(value));
    if comma {
        json.push(',');
    }
    json.push('\n');
}

fn field_optional_string(
    json: &mut String,
    indent: usize,
    name: &str,
    value: Option<&str>,
    comma: bool,
) {
    write_indent(json, indent);
    json.push_str(&quote(name));
    json.push_str(": ");
    json.push_str(&value.map(quote).unwrap_or_else(|| "null".to_owned()));
    if comma {
        json.push(',');
    }
    json.push('\n');
}

fn field_bool(json: &mut String, indent: usize, name: &str, value: bool, comma: bool) {
    write_indent(json, indent);
    json.push_str(&quote(name));
    json.push_str(": ");
    json.push_str(if value { "true" } else { "false" });
    if comma {
        json.push(',');
    }
    json.push('\n');
}

fn field_string_array(
    json: &mut String,
    indent: usize,
    name: &str,
    values: &[String],
    comma: bool,
) {
    write_indent(json, indent);
    json.push_str(&quote(name));
    json.push_str(": [");
    for (index, value) in values.iter().enumerate() {
        if index > 0 {
            json.push_str(", ");
        }
        json.push_str(&quote(value));
    }
    json.push(']');
    if comma {
        json.push(',');
    }
    json.push('\n');
}

fn line(json: &mut String, indent: usize, value: &str) {
    write_indent(json, indent);
    json.push_str(value);
    json.push('\n');
}

fn write_indent(json: &mut String, indent: usize) {
    for _ in 0..indent {
        json.push_str("  ");
    }
}

fn quote(value: &str) -> String {
    let mut output = String::from("\"");
    for character in value.chars() {
        match character {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            value if value < '\u{20}' => output.push_str(&format!("\\u{:04x}", value as u32)),
            value => output.push(value),
        }
    }
    output.push('"');
    output
}
