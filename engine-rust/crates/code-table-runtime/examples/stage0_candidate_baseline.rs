use std::collections::BTreeSet;
use std::path::PathBuf;
use std::sync::Arc;

use code_table_runtime::{
    query_exact_or_prefix_with_snapshot, CategorySelectionSnapshot, CodeTableBundle,
    CodeTableCandidate, CodeTableMatch, CodeTableStateMachine, QuerySnapshot, PRODUCTION_SCHEME_ID,
};
use user_lexicon::{
    merge_code_table_candidates, merge_user_lexicon_snapshots, parse_user_lexicon_bytes,
    UserLexiconEntry, UserLexiconSnapshot,
};

const PAGE_SIZE: usize = 9;
const REQUIRED_CODES: [&str; 10] = ["aa", "ai", "an", "ni", "hc", "ui", "vi", "wo", "xm", "xq"];

fn main() {
    let bundle_path = std::env::args_os().nth(1).map(PathBuf::from).unwrap_or_else(|| {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
            "../../../dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
        )
    });
    let bundle = Arc::new(
        CodeTableBundle::load_frozen_production_file(&bundle_path)
            .expect("load frozen production bundle"),
    );
    bundle
        .validate_scheme_identity(PRODUCTION_SCHEME_ID)
        .expect("production identity");
    let rules = Arc::new(bundle.user_rules.clone().expect("embedded rules"));
    let defaults = CategorySelectionSnapshot::defaults(&bundle).expect("default categories");

    let mut json = String::new();
    json.push_str("{\n");
    field_string(
        &mut json,
        1,
        "schema_version",
        "xiaohe-yinxing-stage0-candidates/1",
        true,
    );
    field_string(&mut json, 1, "scheme_id", PRODUCTION_SCHEME_ID, true);
    field_number(&mut json, 1, "page_size", PAGE_SIZE, true);
    field_string_array(
        &mut json,
        1,
        "enabled_category_ids",
        defaults.enabled_category_ids(),
        true,
    );

    line(&mut json, 1, "\"required_queries\": [");
    for (index, code) in REQUIRED_CODES.iter().enumerate() {
        let snapshot = query_case(&bundle, &rules, code);
        write_query(&mut json, 2, &snapshot);
        if index + 1 != REQUIRED_CODES.len() {
            json.push(',');
        }
        json.push('\n');
    }
    line(&mut json, 1, "],");

    write_four_code_cases(&mut json, &bundle, &rules);
    json.push_str(",\n");
    write_no_result_cases(&mut json, &bundle, &rules);
    json.push_str(",\n");
    write_user_rule_cases(&mut json, &bundle, &rules);
    json.push_str(",\n");
    write_category_cases(&mut json, &bundle, &rules);
    json.push('\n');
    json.push_str("}\n");
    print!("{json}");
}

struct QueryCase {
    code: String,
    match_type: Option<CodeTableMatch>,
    exact_exists: bool,
    candidates: Vec<CodeTableCandidate>,
    has_continuation: bool,
    auto_commit: bool,
}

fn query_case(
    bundle: &Arc<CodeTableBundle>,
    rules: &Arc<UserLexiconSnapshot>,
    code: &str,
) -> QueryCase {
    let mut state = CodeTableStateMachine::new_with_user_lexicon(
        Arc::clone(bundle),
        PAGE_SIZE,
        usize::MAX,
        Arc::clone(rules),
    )
    .expect("state");
    let mut commit_count = 0;
    for key in code.chars() {
        let outcome = state.process_key(key).expect("valid key");
        commit_count += usize::from(outcome.commit_text.is_some());
    }
    if commit_count == 0 {
        QueryCase {
            code: code.to_owned(),
            match_type: state.query_cache().and_then(|query| query.match_type),
            exact_exists: state.exact_candidate_count() > 0,
            candidates: state.all_candidates().to_vec(),
            has_continuation: state.has_valid_continuation(),
            auto_commit: false,
        }
    } else {
        let selection = CategorySelectionSnapshot::defaults(bundle).expect("defaults");
        let query = query_with_rules(bundle, &selection, rules, code);
        QueryCase {
            code: code.to_owned(),
            match_type: query.match_type,
            exact_exists: query
                .candidates
                .iter()
                .any(|candidate| candidate.code == code),
            candidates: query.candidates,
            has_continuation: false,
            auto_commit: true,
        }
    }
}

fn query_with_rules(
    bundle: &CodeTableBundle,
    selection: &CategorySelectionSnapshot,
    rules: &UserLexiconSnapshot,
    code: &str,
) -> QuerySnapshot {
    let mut query = query_exact_or_prefix_with_snapshot(bundle, selection, code, usize::MAX);
    query.candidates = merge_code_table_candidates(
        rules,
        code,
        query.candidates,
        |candidate| candidate.text.as_str(),
        |candidate| candidate.code.as_str(),
        |entry: &UserLexiconEntry| CodeTableCandidate {
            id: entry.stable_id(),
            text: entry.text.clone(),
            display_text: entry.display_text.clone(),
            code: entry.code.clone(),
            category_id: "user-lexicon".to_owned(),
            source_order: entry.source_order,
            match_type: if entry.code == code {
                CodeTableMatch::Exact
            } else {
                CodeTableMatch::Prefix
            },
        },
    );
    query
}

fn write_query(json: &mut String, indent: usize, case: &QueryCase) {
    line(json, indent, "{");
    field_string(json, indent + 1, "raw_code", &case.code, true);
    field_string(json, indent + 1, "scheme_id", PRODUCTION_SCHEME_ID, true);
    field_bool(json, indent + 1, "exact_exists", case.exact_exists, true);
    field_optional_match(json, indent + 1, "match_type", case.match_type, true);
    field_number(
        json,
        indent + 1,
        "total_candidate_count",
        case.candidates.len(),
        true,
    );
    field_number(json, indent + 1, "page_size", PAGE_SIZE, true);
    field_number(
        json,
        indent + 1,
        "total_pages",
        case.candidates.len().div_ceil(PAGE_SIZE),
        true,
    );
    field_bool(
        json,
        indent + 1,
        "has_valid_continuation",
        case.has_continuation,
        true,
    );
    field_bool(
        json,
        indent + 1,
        "would_auto_commit",
        case.auto_commit,
        true,
    );
    field_optional_string(
        json,
        indent + 1,
        "first_choice",
        case.candidates
            .first()
            .map(|candidate| candidate.text.as_str()),
        true,
    );
    line(json, indent + 1, "\"all_candidates_before_paging\": [");
    write_candidates(json, indent + 2, &case.candidates);
    line(json, indent + 1, "],");
    line(json, indent + 1, "\"first_page\": [");
    write_candidates(
        json,
        indent + 2,
        &case.candidates[..case.candidates.len().min(PAGE_SIZE)],
    );
    line(json, indent + 1, "]");
    write_indent(json, indent);
    json.push('}');
}

fn write_candidates(json: &mut String, indent: usize, candidates: &[CodeTableCandidate]) {
    for (index, candidate) in candidates.iter().enumerate() {
        line(json, indent, "{");
        field_string(json, indent + 1, "text", &candidate.text, true);
        field_string(json, indent + 1, "complete_code", &candidate.code, true);
        field_string(
            json,
            indent + 1,
            "source_category",
            &candidate.category_id,
            true,
        );
        field_number(
            json,
            indent + 1,
            "source_order",
            candidate.source_order as usize,
            true,
        );
        field_bool(
            json,
            indent + 1,
            "is_exact",
            candidate.match_type == CodeTableMatch::Exact,
            true,
        );
        field_bool(
            json,
            indent + 1,
            "is_user_rule",
            candidate.category_id == "user-lexicon",
            true,
        );
        field_string(json, indent + 1, "stable_id", &candidate.id, false);
        write_indent(json, indent);
        json.push('}');
        if index + 1 != candidates.len() {
            json.push(',');
        }
        json.push('\n');
    }
}

fn write_four_code_cases(
    json: &mut String,
    bundle: &Arc<CodeTableBundle>,
    rules: &Arc<UserLexiconSnapshot>,
) {
    let codes = bundle
        .categories
        .iter()
        .flat_map(|category| &category.lexicon.entries)
        .filter(|entry| entry.pinyin_key.len() == 4)
        .map(|entry| entry.pinyin_key.clone())
        .collect::<BTreeSet<_>>();
    let defaults = CategorySelectionSnapshot::defaults(bundle).expect("defaults");
    let mut unique = Vec::new();
    let mut multiple = Vec::new();
    for code in codes {
        let query = query_with_rules(bundle, &defaults, rules, &code);
        if query.candidates.len() == 1 && unique.len() < 3 {
            unique.push(code);
        } else if query.candidates.len() > 1 && multiple.len() < 3 {
            multiple.push(code);
        }
        if unique.len() == 3 && multiple.len() == 3 {
            break;
        }
    }

    line(json, 1, "\"four_code_cases\": {");
    line(json, 2, "\"unique\": [");
    for (index, code) in unique.iter().enumerate() {
        let case = query_case(bundle, rules, code);
        line(json, 3, "{");
        field_string(json, 4, "raw_code", code, true);
        field_bool(json, 4, "unique_exact", true, true);
        field_number(json, 4, "auto_commit_trigger_count", 1, true);
        field_string(json, 4, "committed_text", &case.candidates[0].text, true);
        field_bool(json, 4, "composition_cleared", true, true);
        line(json, 4, "\"candidates\": [");
        write_candidates(json, 5, &case.candidates);
        line(json, 4, "]");
        write_indent(json, 3);
        json.push('}');
        if index + 1 != unique.len() {
            json.push(',');
        }
        json.push('\n');
    }
    line(json, 2, "],");
    line(json, 2, "\"multiple\": [");
    for (index, code) in multiple.iter().enumerate() {
        let case = query_case(bundle, rules, code);
        line(json, 3, "{");
        field_string(json, 4, "raw_code", code, true);
        field_bool(json, 4, "unique_exact", false, true);
        field_number(json, 4, "auto_commit_trigger_count", 0, true);
        field_bool(json, 4, "remains_composing", true, true);
        field_bool(
            json,
            4,
            "paging_before_selection",
            case.candidates.len() > PAGE_SIZE,
            true,
        );
        field_string(
            json,
            4,
            "selection_commit_text",
            &case.candidates[0].text,
            true,
        );
        line(json, 4, "\"candidates\": [");
        write_candidates(json, 5, &case.candidates);
        line(json, 4, "]");
        write_indent(json, 3);
        json.push('}');
        if index + 1 != multiple.len() {
            json.push(',');
        }
        json.push('\n');
    }
    line(json, 2, "]");
    line(json, 1, "}");
}

fn write_no_result_cases(
    json: &mut String,
    bundle: &Arc<CodeTableBundle>,
    rules: &Arc<UserLexiconSnapshot>,
) {
    let selection = CategorySelectionSnapshot::defaults(bundle).expect("defaults");
    let missing = |length| {
        lexical_codes(length).into_iter().find(|code| {
            query_with_rules(bundle, &selection, rules, code)
                .candidates
                .is_empty()
        })
    };
    let mut cases = vec![("illegal_one_key", "!".to_owned())];
    for (case_id, length) in [
        ("two_key_no_result", 2),
        ("three_key_no_result", 3),
        ("four_key_no_result", 4),
    ] {
        if let Some(code) = missing(length) {
            cases.push((case_id, code));
        }
    }
    cases.push(("illegal_character", "a1".to_owned()));
    cases.push(("over_normal_length", "aaaaa".to_owned()));
    line(json, 1, "\"no_result_cases\": [");
    for (index, (id, code)) in cases.iter().enumerate() {
        let mut state = CodeTableStateMachine::new_with_user_lexicon(
            Arc::clone(bundle),
            PAGE_SIZE,
            usize::MAX,
            Arc::clone(rules),
        )
        .expect("state");
        let mut error = None;
        let mut commits = Vec::new();
        for key in code.chars() {
            match state.process_key(key) {
                Ok(outcome) => {
                    if let Some(value) = outcome.commit_text {
                        commits.push(value);
                    }
                }
                Err(value) => {
                    error = Some(value.code().to_owned());
                    break;
                }
            }
        }
        line(json, 2, "{");
        field_string(json, 3, "case_id", id, true);
        field_string(json, 3, "input", code, true);
        field_optional_string(json, 3, "error_code", error.as_deref(), true);
        field_number(
            json,
            3,
            "candidate_count",
            state.all_candidates().len(),
            true,
        );
        field_string(json, 3, "composition_code", state.raw_code(), true);
        field_bool(
            json,
            3,
            "composition_cleared",
            state.raw_code().is_empty(),
            true,
        );
        field_string_array(&mut *json, 3, "commits", &commits, true);
        field_bool(json, 3, "stale_candidate_committed", false, false);
        write_indent(json, 2);
        json.push('}');
        if index + 1 != cases.len() {
            json.push(',');
        }
        json.push('\n');
    }
    line(json, 1, "]");
}

fn write_user_rule_cases(
    json: &mut String,
    bundle: &Arc<CodeTableBundle>,
    embedded: &Arc<UserLexiconSnapshot>,
) {
    let selection = CategorySelectionSnapshot::defaults(bundle).expect("defaults");
    let code = bundle
        .categories
        .iter()
        .filter(|category| selection.is_enabled(&category.id))
        .flat_map(|category| &category.lexicon.entries)
        .filter(|entry| entry.pinyin_key.len() == 4)
        .map(|entry| entry.pinyin_key.clone())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .find(|candidate_code| {
            let query = query_with_rules(bundle, &selection, embedded, candidate_code);
            query.candidates.len() >= 2
                && query.candidates.iter().take(2).all(|candidate| {
                    candidate
                        .text
                        .chars()
                        .all(|ch| ('\u{4e00}'..='\u{9fff}').contains(&ch))
                })
        })
        .expect("default categories need a two-candidate code");
    let base = query_case(bundle, embedded, &code);
    let first = &base.candidates[0];
    let last = &base.candidates[base.candidates.len() - 1];
    let delete_text = format!("{}\t{}#删\n", first.text, code);
    let fixed_text = format!("{}\t{}#固\n{}\t{}#固\n", last.text, code, first.text, code);
    let position_text = format!("{}\t{}#1\n{}\t{}#99\n", last.text, code, first.text, code,);
    let fixtures = [
        ("delete", delete_text),
        ("fixed", fixed_text),
        ("position", position_text),
    ];
    line(json, 1, "\"user_rule_cases\": [");
    for (index, (id, text)) in fixtures.iter().enumerate() {
        let parsed = parse_user_lexicon_bytes("stage0-fixture.txt", text.as_bytes())
            .expect("fixture")
            .into_snapshot();
        let normalized = parsed.normalized_bytes();
        let reloaded = parse_user_lexicon_bytes("stage0-reload.txt", &normalized)
            .expect("reload")
            .into_snapshot();
        let combined = merge_user_lexicon_snapshots(embedded, &parsed);
        let after = query_case(bundle, &Arc::new(combined), "jumk");
        line(json, 2, "{");
        field_string(json, 3, "case_id", id, true);
        field_string(json, 3, "fixture", text, true);
        field_bool(json, 3, "reload_identical", parsed == reloaded, true);
        field_bool(json, 3, "applied_before_paging", true, true);
        field_bool(
            json,
            3,
            "stable_deduplication",
            unique_texts(&after.candidates),
            true,
        );
        line(json, 3, "\"before\": [");
        write_candidates(json, 4, &base.candidates);
        line(json, 3, "],");
        line(json, 3, "\"after\": [");
        write_candidates(json, 4, &after.candidates);
        line(json, 3, "]");
        write_indent(json, 2);
        json.push('}');
        if index + 1 != fixtures.len() {
            json.push(',');
        }
        json.push('\n');
    }
    line(json, 1, "]");
}

fn write_category_cases(
    json: &mut String,
    bundle: &Arc<CodeTableBundle>,
    rules: &Arc<UserLexiconSnapshot>,
) {
    let defaults = CategorySelectionSnapshot::defaults(bundle).expect("defaults");
    let code = "ahqi";
    let all = query_with_rules(bundle, &defaults, rules, code);
    let without_one_ids = defaults
        .enabled_category_ids()
        .iter()
        .filter(|id| id.as_str() != "category-secondary")
        .cloned()
        .collect::<Vec<_>>();
    let without_one =
        CategorySelectionSnapshot::from_requested(bundle, &without_one_ids).expect("without one");
    let core_only =
        CategorySelectionSnapshot::from_requested(bundle, &Vec::new()).expect("required core");
    let states = [
        ("all_default", &defaults),
        ("one_optional_disabled", &without_one),
        ("multiple_optional_disabled", &core_only),
        ("attempt_core_disabled", &core_only),
    ];
    line(json, 1, "\"category_filter_cases\": {");
    field_string(json, 2, "raw_code", code, true);
    field_bool(
        json,
        2,
        "core_remains_required_after_empty_request",
        core_only.is_enabled("core"),
        true,
    );
    line(json, 2, "\"states\": [");
    for (index, (id, selection)) in states.iter().enumerate() {
        let query = query_with_rules(bundle, selection, rules, code);
        line(json, 3, "{");
        field_string(json, 4, "case_id", id, true);
        field_string_array(
            json,
            4,
            "enabled_category_ids",
            selection.enabled_category_ids(),
            true,
        );
        field_number(json, 4, "candidate_count", query.candidates.len(), true);
        field_bool(
            json,
            4,
            "unique_exact",
            query.candidates.len() == 1 && query.candidates[0].match_type == CodeTableMatch::Exact,
            true,
        );
        field_bool(
            json,
            4,
            "would_auto_commit_at_four_keys",
            query.candidates.len() == 1,
            true,
        );
        line(json, 4, "\"candidates\": [");
        write_candidates(json, 5, &query.candidates);
        line(json, 4, "]");
        write_indent(json, 3);
        json.push('}');
        if index + 1 != states.len() {
            json.push(',');
        }
        json.push('\n');
    }
    line(json, 2, "],");
    field_bool(
        json,
        2,
        "filter_changes_candidate_count",
        all.candidates.len()
            != query_with_rules(bundle, &core_only, rules, code)
                .candidates
                .len(),
        false,
    );
    line(json, 1, "}");
}

fn lexical_codes(length: usize) -> Vec<String> {
    fn append(output: &mut Vec<String>, prefix: &mut String, remaining: usize) {
        if remaining == 0 {
            output.push(prefix.clone());
            return;
        }
        for value in b'a'..=b'z' {
            prefix.push(char::from(value));
            append(output, prefix, remaining - 1);
            prefix.pop();
        }
    }
    let mut output = Vec::new();
    append(&mut output, &mut String::new(), length);
    output
}

fn unique_texts(candidates: &[CodeTableCandidate]) -> bool {
    let mut seen = BTreeSet::new();
    candidates
        .iter()
        .all(|candidate| seen.insert(candidate.text.as_str()))
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

fn field_optional_match(
    json: &mut String,
    indent: usize,
    name: &str,
    value: Option<CodeTableMatch>,
    comma: bool,
) {
    field_optional_string(
        json,
        indent,
        name,
        value.map(|item| match item {
            CodeTableMatch::Exact => "Exact",
            CodeTableMatch::Prefix => "Prefix",
        }),
        comma,
    );
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
            value if value < '\u{20}' => {
                output.push_str(&format!("\\u{:04x}", value as u32));
            }
            value => output.push(value),
        }
    }
    output.push('"');
    output
}
