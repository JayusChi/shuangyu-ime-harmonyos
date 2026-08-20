use std::path::{Path, PathBuf};

use engine_protocol::{CompositionResult, FormalCandidate};
use ime_engine::{EngineConfig, ImeEngine};

const PAGE_SIZE: usize = 50;
const PROGRESSIVE_PATHS: [(&str, &str); 2] = [
    ("unique-four-code-path", "aaba"),
    ("multiple-four-code-path", "jumk"),
];
const REQUIRED_TWO_CODES: [&str; 10] = ["aa", "ai", "an", "ni", "hc", "ui", "vi", "wo", "xm", "xq"];
const TRANSITIONS: [(&str, &str); 5] = [
    ("unique-four-code-auto-commit", "aaba"),
    ("multiple-four-code-remains-composing", "jumk"),
    ("fifth-key-top-screen-and-replay", "jumke"),
    ("three-code-no-result", "aaa"),
    ("four-code-empty-split", "aaaa"),
];

fn main() {
    let workspace = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let lexicon = workspace.join("dictionaries/generated/production.lex");
    let bundle = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            workspace.join(
                "dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
            )
        });

    let mut json = String::from("{\n");
    field_string(
        &mut json,
        1,
        "schema_version",
        "xiaohe-yinxing-precise-match-stage0-progressive/1",
        true,
    );
    field_string(&mut json, 1, "scheme_id", "xiaohe-yinxing", true);
    field_string(
        &mut json,
        1,
        "query_strategy",
        "ProgressiveXiaoheYinxing",
        true,
    );
    field_number(&mut json, 1, "page_size", PAGE_SIZE, true);
    field_number(&mut json, 1, "candidate_snapshot_limit", 512, true);

    line(&mut json, 1, "\"progressive_paths\": [");
    for (index, (id, keys)) in PROGRESSIVE_PATHS.iter().enumerate() {
        line(&mut json, 2, "{");
        field_string(&mut json, 3, "case_id", id, true);
        field_string(&mut json, 3, "key_sequence", keys, true);
        line(&mut json, 3, "\"key_states\": [");
        let mut engine = new_engine(&lexicon, &bundle);
        for (key_index, key) in keys.chars().enumerate() {
            let state = engine.process_key(key);
            assert!(state.success, "{}", state.error_message);
            write_state(&mut json, 4, &state);
            if key_index + 1 != keys.len() {
                json.push(',');
            }
            json.push('\n');
        }
        line(&mut json, 3, "]");
        write_indent(&mut json, 2);
        json.push('}');
        if index + 1 != PROGRESSIVE_PATHS.len() {
            json.push(',');
        }
        json.push('\n');
    }
    line(&mut json, 1, "],");

    line(&mut json, 1, "\"required_two_code_snapshots\": [");
    for (index, code) in REQUIRED_TWO_CODES.iter().enumerate() {
        let (first, all) = collect_all_candidates(&lexicon, &bundle, code);
        line(&mut json, 2, "{");
        field_string(&mut json, 3, "raw_code", code, true);
        field_number(&mut json, 3, "candidate_count", all.len(), true);
        field_number(
            &mut json,
            3,
            "current_page_json_bytes",
            first.to_json().len(),
            true,
        );
        field_bool(
            &mut json,
            3,
            "remains_composing",
            first.commit_text.is_empty() && first.raw_input == *code,
            true,
        );
        line(&mut json, 3, "\"first_page\": [");
        write_candidates(&mut json, 4, &first.candidates);
        line(&mut json, 3, "],");
        line(&mut json, 3, "\"all_candidate_ids\": [");
        write_string_values(
            &mut json,
            4,
            &all.iter()
                .map(|candidate| candidate.id.clone())
                .collect::<Vec<_>>(),
        );
        line(&mut json, 3, "]");
        write_indent(&mut json, 2);
        json.push('}');
        if index + 1 != REQUIRED_TWO_CODES.len() {
            json.push(',');
        }
        json.push('\n');
    }
    line(&mut json, 1, "],");

    line(&mut json, 1, "\"transition_snapshots\": [");
    for (index, (id, keys)) in TRANSITIONS.iter().enumerate() {
        let mut engine = new_engine(&lexicon, &bundle);
        let mut commits = Vec::new();
        let mut final_state = engine.current_state();
        for key in keys.chars() {
            final_state = engine.process_key(key);
            assert!(final_state.success, "{}", final_state.error_message);
            if !final_state.commit_text.is_empty() {
                commits.push(final_state.commit_text.clone());
            }
        }
        line(&mut json, 2, "{");
        field_string(&mut json, 3, "case_id", id, true);
        field_string(&mut json, 3, "key_sequence", keys, true);
        field_string_array(&mut json, 3, "commits", &commits, true);
        field_string(
            &mut json,
            3,
            "final_raw_input",
            &final_state.raw_input,
            true,
        );
        field_number(
            &mut json,
            3,
            "final_candidate_count_on_page",
            final_state.candidates.len(),
            true,
        );
        field_bool(
            &mut json,
            3,
            "composition_finished",
            final_state.composition_finished,
            true,
        );
        line(&mut json, 3, "\"final_page\": [");
        write_candidates(&mut json, 4, &final_state.candidates);
        line(&mut json, 3, "]");
        write_indent(&mut json, 2);
        json.push('}');
        if index + 1 != TRANSITIONS.len() {
            json.push(',');
        }
        json.push('\n');
    }
    line(&mut json, 1, "],");

    let mut backspace_engine = new_engine(&lexicon, &bundle);
    enter(&mut backspace_engine, "nia");
    let after_backspace = backspace_engine.backspace();
    line(&mut json, 1, "\"lifecycle_snapshot\": {");
    field_string(
        &mut json,
        2,
        "raw_after_nia_backspace",
        &after_backspace.raw_input,
        true,
    );
    field_number(
        &mut json,
        2,
        "candidate_count_after_nia_backspace_on_page",
        after_backspace.candidates.len(),
        true,
    );
    let reset = backspace_engine.reset();
    field_bool(
        &mut json,
        2,
        "reset_clears_composition_and_candidates",
        reset.raw_input.is_empty() && reset.candidates.is_empty(),
        false,
    );
    line(&mut json, 1, "}");
    json.push_str("}\n");
    print!("{json}");
}

fn new_engine(lexicon: &Path, bundle: &Path) -> ImeEngine {
    ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe-yinxing".to_owned(),
        lexicon_path: Some(lexicon.to_string_lossy().into_owned()),
        code_table_bundle_path: Some(bundle.to_string_lossy().into_owned()),
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: PAGE_SIZE,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("formal progressive engine")
}

fn enter(engine: &mut ImeEngine, keys: &str) -> CompositionResult {
    let mut result = engine.current_state();
    for key in keys.chars() {
        result = engine.process_key(key);
        assert!(result.success, "{}", result.error_message);
    }
    result
}

fn collect_all_candidates(
    lexicon: &Path,
    bundle: &Path,
    keys: &str,
) -> (CompositionResult, Vec<FormalCandidate>) {
    let mut engine = new_engine(lexicon, bundle);
    let first = enter(&mut engine, keys);
    let mut current = first.clone();
    let mut all = current.candidates.clone();
    while current.has_next_page {
        current = engine.next_candidate_page().expect("next candidate page");
        all.extend(current.candidates.clone());
    }
    (first, all)
}

fn write_state(json: &mut String, indent: usize, state: &CompositionResult) {
    line(json, indent, "{");
    field_string(json, indent + 1, "raw_input", &state.raw_input, true);
    field_string(json, indent + 1, "commit_text", &state.commit_text, true);
    field_number(
        json,
        indent + 1,
        "candidate_count_on_page",
        state.candidates.len(),
        true,
    );
    field_number(
        json,
        indent + 1,
        "protocol_json_bytes",
        state.to_json().len(),
        true,
    );
    field_bool(json, indent + 1, "has_next_page", state.has_next_page, true);
    field_bool(
        json,
        indent + 1,
        "composition_finished",
        state.composition_finished,
        true,
    );
    line(json, indent + 1, "\"current_page\": [");
    write_candidates(json, indent + 2, &state.candidates);
    line(json, indent + 1, "]");
    write_indent(json, indent);
    json.push('}');
}

fn write_candidates(json: &mut String, indent: usize, candidates: &[FormalCandidate]) {
    for (index, candidate) in candidates.iter().enumerate() {
        line(json, indent, "{");
        field_string(json, indent + 1, "id", &candidate.id, true);
        field_string(json, indent + 1, "text", &candidate.text, true);
        field_string(json, indent + 1, "reading", &candidate.reading, true);
        field_string(json, indent + 1, "source", &candidate.source, false);
        write_indent(json, indent);
        json.push('}');
        if index + 1 != candidates.len() {
            json.push(',');
        }
        json.push('\n');
    }
}

fn write_string_values(json: &mut String, indent: usize, values: &[String]) {
    for (index, value) in values.iter().enumerate() {
        write_indent(json, indent);
        json.push_str(&quote(value));
        if index + 1 != values.len() {
            json.push(',');
        }
        json.push('\n');
    }
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

fn field_number(json: &mut String, indent: usize, name: &str, value: usize, comma: bool) {
    write_indent(json, indent);
    json.push_str(&quote(name));
    json.push_str(": ");
    json.push_str(&value.to_string());
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
