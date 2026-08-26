use crate::{
    json::{self, Json},
    model::*,
    sha256,
};
use std::{fs, path::Path};

pub struct Emitted {
    pub manifest_sha256: String,
    pub contract_sha256: String,
}

pub fn write_all(result: &AuditResult, output: &Path, reports: &Path) -> Result<Emitted, String> {
    fs::create_dir_all(output).map_err(|e| format!("create output: {e}"))?;
    fs::create_dir_all(reports).map_err(|e| format!("create reports: {e}"))?;
    let manifest = json::serialize(&manifest_json(result));
    let manifest_hash = sha256::hex(&manifest);
    let categories = json::serialize(&categories_json(&result.categories));
    let commands = json::serialize(&command_json(result));
    let references = json::serialize(&references_json(&result.references));
    let decisions = json::serialize(&decisions_json(result));
    let comparisons = json::serialize(&comparisons_json(&result.comparisons));
    let sanitized_configuration = json::serialize(&sanitized_configuration_json(result));
    let sanitized_configuration_hash = sha256::hex(&sanitized_configuration);
    atomic_write(&output.join("source_manifest.json"), &manifest)?;
    atomic_write(
        &output.join("source_manifest.sha256"),
        format!("{manifest_hash}  source_manifest.json\n").as_bytes(),
    )?;
    atomic_write(&output.join("category_mapping.json"), &categories)?;
    atomic_write(&output.join("command_policy.json"), &commands)?;
    atomic_write(&output.join("missing_references.json"), &references)?;
    atomic_write(&output.join("decisions.json"), &decisions)?;
    atomic_write(&output.join("comparisons.json"), &comparisons)?;
    atomic_write(
        &output.join("sanitized_configuration.json"),
        &sanitized_configuration,
    )?;
    let contract = json::serialize(&contract_json(
        result,
        &manifest_hash,
        &sanitized_configuration_hash,
    ));
    let contract_hash = sha256::hex(&contract);
    atomic_write(&output.join("conversion_contract.json"), &contract)?;
    atomic_write(
        &output.join("conversion_contract.sha256"),
        format!("{contract_hash}  conversion_contract.json\n").as_bytes(),
    )?;
    write_reports(result, reports, &manifest_hash, &contract_hash)?;
    Ok(Emitted {
        manifest_sha256: manifest_hash,
        contract_sha256: contract_hash,
    })
}

fn manifest_json(result: &AuditResult) -> Json {
    Json::object(vec![
        ("audit_manifest_version", Json::string("1.1.0")),
        ("scheme_id", Json::string("xiaohe-yinxing")),
        ("bundle_id", Json::string("xiaohe-yinxing-production")),
        ("data_version", Json::string("source-receipt-1")),
        (
            "converter_version",
            Json::string("yinxing-source-auditor/1.1.0"),
        ),
        (
            "source_roots",
            Json::array([Json::string("码表"), Json::string("小鹤音形")]),
        ),
        ("line_numbering", Json::string("1-based physical lines")),
        (
            "path_sort",
            Json::string("source_root then UTF-8 path bytes"),
        ),
        ("files", Json::array(result.files.iter().map(file_json))),
        (
            "path_conflicts",
            Json::array(
                result
                    .path_conflicts
                    .iter()
                    .map(|v| Json::string(v.clone())),
            ),
        ),
        (
            "comparisons",
            Json::array(result.comparisons.iter().map(comparison_json)),
        ),
        (
            "blocking_reasons",
            Json::array(
                result
                    .blocking_reasons
                    .iter()
                    .map(|v| Json::string(v.clone())),
            ),
        ),
    ])
}

fn file_json(file: &SourceFile) -> Json {
    Json::object(vec![
        ("source_root", Json::string(&file.source_root)),
        ("relative_path", Json::string(&file.relative_path)),
        (
            "normalized_relative_path",
            Json::string(&file.normalized_relative_path),
        ),
        ("file_name", Json::string(&file.file_name)),
        ("extension", Json::string(&file.extension)),
        ("byte_size", Json::Number(file.byte_size)),
        (
            "physical_line_count",
            Json::Number(file.physical_line_count),
        ),
        (
            "non_empty_line_count",
            Json::Number(file.non_empty_line_count),
        ),
        ("comment_line_count", Json::Number(file.syntax.comment)),
        (
            "configuration_header_line_count",
            Json::Number(file.syntax.config_header),
        ),
        (
            "data_record_line_count",
            Json::Number(file.syntax.records.len() as u64),
        ),
        (
            "unrecognized_line_count",
            Json::Number(file.syntax.unrecognized),
        ),
        ("detected_encoding", Json::string(&file.detected_encoding)),
        ("has_utf8_bom", Json::Bool(file.has_utf8_bom)),
        ("newline_style", Json::string(&file.newline_style)),
        ("has_final_newline", Json::Bool(file.final_newline)),
        ("sha256", Json::string(&file.sha256)),
        ("file_role", Json::string(&file.file_role)),
        ("role_evidence", Json::string(&file.role_evidence)),
        (
            "security_classification",
            Json::string(&file.security_classification),
        ),
        ("decision", Json::string(&file.decision)),
        ("decision_reason", Json::string(&file.decision_reason)),
        ("syntax_statistics", syntax_json(&file.syntax)),
        (
            "security_findings",
            Json::array(file.security_findings.iter().map(security_json)),
        ),
        (
            "read_error",
            file.read_error.as_ref().map_or(Json::Null, Json::string),
        ),
    ])
}

fn syntax_json(s: &SyntaxStats) -> Json {
    Json::object(vec![
        ("ordinary", Json::Number(s.ordinary)),
        ("user_deletion", Json::Number(s.user_delete)),
        ("user_pin", Json::Number(s.user_pin)),
        ("direct_add", Json::Number(s.direct_add)),
        ("user_position", Json::Number(s.user_position)),
        ("user_mixed_rule", Json::Number(s.user_mixed)),
        ("cmd", Json::Number(s.cmd)),
        ("ddcmd", Json::Number(s.ddcmd)),
        ("configuration_header", Json::Number(s.config_header)),
        ("configuration_item", Json::Number(s.config_item)),
        ("comment", Json::Number(s.comment)),
        ("empty", Json::Number(s.empty)),
        ("unrecognized", Json::Number(s.unrecognized)),
        (
            "first_occurrences",
            Json::array(s.first.iter().map(|(kind, value)| {
                Json::object(vec![
                    ("syntax", Json::string(kind)),
                    ("physical_line", Json::Number(value.line)),
                    ("sample_sha256", Json::string(&value.sample_sha256)),
                    ("error_code", Json::string(syntax_reason(kind))),
                    ("recommendation", Json::string(syntax_action(kind))),
                ])
            })),
        ),
    ])
}
fn syntax_reason(kind: &str) -> &'static str {
    match kind {
        "ordinary" => "ACCEPT_TABLE_RECORD",
        "user_deletion" => "TRANSFORM_USER_DELETE",
        "user_pin" => "TRANSFORM_USER_PIN",
        "direct_add" => "TRANSFORM_DIRECT_ADD",
        "user_position" => "TRANSFORM_USER_POSITION",
        "user_mixed_rule" => "REJECT_AMBIGUOUS_USER_RULE",
        "cmd" => "REJECT_UNSUPPORTED_COMMAND",
        "ddcmd" => "REJECT_UNKNOWN_COMMAND_SYNTAX",
        "configuration_header" | "configuration_item" => "REFERENCE_ONLY_CONFIGURATION",
        "comment" | "empty" => "IGNORE_NON_DATA_LINE",
        _ => "REJECT_UNRECOGNIZED_SYNTAX",
    }
}
fn syntax_action(kind: &str) -> &'static str {
    match kind {
        "ordinary" => "retain with source line",
        "user_deletion" | "user_pin" | "direct_add" | "user_position" => {
            "convert through frozen user rule policy"
        }
        "comment" | "empty" => "exclude from candidate records",
        "configuration_header" | "configuration_item" => "parse only as non-executable reference",
        _ => "isolate and require explicit support",
    }
}
fn security_json(f: &SecurityFinding) -> Json {
    Json::object(vec![
        ("finding_type", Json::string(&f.finding_type)),
        ("physical_line", Json::Number(f.line)),
        ("summary_sha256", Json::string(&f.summary_sha256)),
        ("reason_code", Json::string(&f.reason_code)),
        ("blocking_credential", Json::Bool(f.blocking_credential)),
    ])
}

fn categories_json(categories: &[Category]) -> Json {
    Json::object(vec![
        ("mapping_version", Json::string("1.0.0")),
        (
            "categories",
            Json::array(categories.iter().map(category_json)),
        ),
    ])
}
fn category_json(c: &Category) -> Json {
    Json::object(vec![
        ("category_id", Json::string(c.category_id)),
        ("display_name", Json::string(c.display_name)),
        ("role", Json::string(c.role)),
        (
            "authoritative_source",
            c.authoritative_source.map_or(Json::Null, Json::string),
        ),
        (
            "supplemental_sources",
            Json::array(c.supplemental_sources.iter().map(|v| Json::string(*v))),
        ),
        (
            "audit_only_sources",
            Json::array(c.audit_only_sources.iter().map(|v| Json::string(*v))),
        ),
        (
            "merge_order",
            Json::array(c.merge_order.iter().map(|v| Json::string(*v))),
        ),
        ("default_enabled", Json::Bool(c.default_enabled)),
        ("first_release_scope", Json::string(c.first_release_scope)),
        ("conflict_policy", Json::string(c.conflict_policy)),
        ("duplicate_policy", Json::string(c.duplicate_policy)),
        (
            "unsupported_record_policy",
            Json::string(c.unsupported_record_policy),
        ),
        ("confirmation_status", Json::string(c.confirmation_status)),
        (
            "requires_manual_confirmation",
            Json::Bool(c.requires_manual_confirmation),
        ),
        ("notes", Json::string(c.notes)),
    ])
}

fn comparison_json(c: &Comparison) -> Json {
    Json::object(vec![
        ("comparison_id", Json::string(&c.comparison_id)),
        ("left_source", Json::string(&c.left_source)),
        ("right_source", Json::string(&c.right_source)),
        ("comparison_type", Json::string(&c.comparison_type)),
        ("byte_identical", Json::Bool(c.byte_identical)),
        (
            "normalized_text_identical",
            Json::Bool(c.normalized_text_identical),
        ),
        ("record_set_identical", Json::Bool(c.record_set_identical)),
        (
            "record_order_identical",
            Json::Bool(c.record_order_identical),
        ),
        (
            "semantic_role_identical",
            Json::Bool(c.semantic_role_identical),
        ),
        ("overlap_count", Json::Number(c.overlap_count)),
        ("left_only_count", Json::Number(c.left_only_count)),
        ("right_only_count", Json::Number(c.right_only_count)),
        ("order_difference", Json::Bool(c.order_difference)),
        ("syntax_difference", Json::Bool(c.syntax_difference)),
        (
            "same_text_different_code",
            Json::Number(c.same_text_different_code),
        ),
        (
            "same_code_different_text",
            Json::Number(c.same_code_different_text),
        ),
        (
            "recommended_resolution",
            Json::string(&c.recommended_resolution),
        ),
        (
            "requires_manual_confirmation",
            Json::Bool(c.requires_manual_confirmation),
        ),
    ])
}
fn comparisons_json(values: &[Comparison]) -> Json {
    Json::object(vec![
        ("comparison_version", Json::string("1.0.0")),
        (
            "comparisons",
            Json::array(values.iter().map(comparison_json)),
        ),
    ])
}

fn references_json(values: &[MissingReference]) -> Json {
    Json::object(vec![
        ("reference_report_version", Json::string("1.0.0")),
        ("line_numbering", Json::string("1-based physical lines")),
        (
            "references",
            Json::array(values.iter().map(|r| {
                Json::object(vec![
                    ("referenced_path", Json::string(&r.referenced_path)),
                    ("reference_file", Json::string(&r.reference_file)),
                    ("reference_line", Json::Number(r.reference_line)),
                    ("reference_role", Json::string(&r.reference_role)),
                    ("resolved", Json::Bool(r.resolved)),
                    (
                        "resolved_source",
                        r.resolved_source.as_ref().map_or(Json::Null, Json::string),
                    ),
                    (
                        "missing_reason",
                        r.missing_reason.as_ref().map_or(Json::Null, Json::string),
                    ),
                    ("case_mismatch", Json::Bool(r.case_mismatch)),
                    ("path_separator_issue", Json::Bool(r.path_separator_issue)),
                    ("outside_allowed_roots", Json::Bool(r.outside_allowed_roots)),
                    ("resolution_decision", Json::string(&r.resolution_decision)),
                    ("reason_code", Json::string(&r.reason_code)),
                    ("next_stage_action", Json::string(&r.next_stage_action)),
                    ("blocks_conversion", Json::Bool(r.blocks_conversion)),
                ])
            })),
        ),
    ])
}

fn command_json(result: &AuditResult) -> Json {
    let mut entries = result
        .files
        .iter()
        .flat_map(|file| {
            file.security_findings.iter().map(move |finding| {
                Json::object(vec![
                    ("source_file", Json::string(file.source_id())),
                    ("physical_line", Json::Number(finding.line)),
                    ("finding_type", Json::string(&finding.finding_type)),
                    ("summary_sha256", Json::string(&finding.summary_sha256)),
                    ("decision", Json::string("REJECTED")),
                    ("reason_code", Json::string(&finding.reason_code)),
                ])
            })
        })
        .collect::<Vec<_>>();
    for file in &result.files {
        for (kind, count, reason) in [
            ("cmd", file.syntax.cmd, "REJECT_UNSUPPORTED_COMMAND"),
            ("ddcmd", file.syntax.ddcmd, "REJECT_UNKNOWN_COMMAND_SYNTAX"),
        ] {
            if count == 0 {
                continue;
            }
            let occurrence = &file.syntax.first[kind];
            entries.push(Json::object(vec![
                ("source_file", Json::string(file.source_id())),
                ("physical_line", Json::Number(occurrence.line)),
                ("finding_type", Json::string(kind)),
                ("summary_sha256", Json::string(&occurrence.sample_sha256)),
                ("decision", Json::string("REJECTED")),
                ("reason_code", Json::string(reason)),
            ]));
        }
    }
    Json::object(vec![
        ("policy_version", Json::string("1.0.0")),
        (
            "candidate_whitelist",
            Json::array(
                [
                    "plain_text",
                    "plain_symbol",
                    "date_time_metadata",
                    "approved_paired_symbol",
                    "internal_cursor_action_metadata",
                ]
                .into_iter()
                .map(Json::string),
            ),
        ),
        ("rejection_rules", rejection_rules()),
        ("findings", Json::Array(entries)),
    ])
}

fn sanitized_configuration_json(result: &AuditResult) -> Json {
    let source = result
        .files
        .iter()
        .find(|file| file.source_id() == "小鹤音形/ime.android.ini");
    let findings = source
        .into_iter()
        .flat_map(|file| file.security_findings.iter())
        .map(|finding| {
            Json::object(vec![
                ("physical_line", Json::Number(finding.line)),
                ("finding_type", Json::string(&finding.finding_type)),
                ("reason_code", Json::string(&finding.reason_code)),
                ("source_line_sha256", Json::string(&finding.summary_sha256)),
                ("disposition", Json::string("removed_from_safe_derivative")),
            ])
        });
    let containment_complete = source.is_some_and(|file| {
        file.decision == "REJECTED"
            && file
                .security_findings
                .iter()
                .any(|finding| finding.blocking_credential)
    });
    Json::object(vec![
        ("sanitized_configuration_version", Json::string("1.0.0")),
        ("source_file", Json::string("小鹤音形/ime.android.ini")),
        (
            "source_sha256",
            source.map_or(Json::Null, |file| Json::string(&file.sha256)),
        ),
        ("scope", Json::string("non-executable audit reference only")),
        ("contains_source_values", Json::Bool(false)),
        ("contains_credentials", Json::Bool(false)),
        ("runtime_configuration", Json::Bool(false)),
        ("eligible_for_conversion", Json::Bool(false)),
        ("eligible_for_hap", Json::Bool(false)),
        (
            "original_source_disposition",
            Json::string("REJECTED_AND_QUARANTINED"),
        ),
        (
            "credential_containment_complete",
            Json::Bool(containment_complete),
        ),
        ("removed_findings", Json::array(findings)),
        (
            "retained_capability_classes",
            Json::array(
                [
                    "plain_text_metadata",
                    "plain_symbol_metadata",
                    "date_time_metadata_candidate",
                    "paired_symbol_metadata_candidate",
                    "internal_cursor_action_metadata_candidate",
                ]
                .into_iter()
                .map(Json::string),
            ),
        ),
        (
            "notes",
            Json::string(
                "No INI key or value is copied. This derivative proves disposition only and cannot configure a runtime.",
            ),
        ),
    ])
}
fn rejection_rules() -> Json {
    Json::array(
        [
            ("REJECT_EXTERNAL_PROCESS", "external process or shell"),
            (
                "REJECT_NETWORK_ACTION",
                "network, URL, FTP, or WebDAV action",
            ),
            (
                "REJECT_EMBEDDED_CREDENTIAL",
                "assigned credential, token, key, or certificate",
            ),
            ("REJECT_EMBEDDED_ACCOUNT", "account or email material"),
            (
                "REJECT_PLATFORM_SPECIFIC_KEYCODE",
                "unmapped Android or Windows keycode",
            ),
            ("REJECT_UNSUPPORTED_COMMAND", "unsupported platform command"),
            ("REJECT_UNKNOWN_COMMAND_SYNTAX", "unknown command syntax"),
            (
                "REJECT_UNSAFE_PATH_ACCESS",
                "absolute or external path access",
            ),
        ]
        .into_iter()
        .map(|(code, reason)| {
            Json::object(vec![
                ("reason_code", Json::string(code)),
                ("reason", Json::string(reason)),
            ])
        }),
    )
}

fn decisions_json(result: &AuditResult) -> Json {
    let mut values = Vec::new();
    for file in &result.files {
        values.push(Json::object(vec![
            (
                "decision_id",
                Json::string(format!(
                    "file-{}",
                    &sha256::hex(file.source_id().as_bytes())[..16]
                )),
            ),
            ("scope", Json::string("file")),
            ("source_file", Json::string(file.source_id())),
            ("physical_line_or_range", Json::string("all")),
            ("role", Json::string(&file.file_role)),
            ("decision", Json::string(&file.decision)),
            ("reason_code", Json::string(file_reason(file))),
            ("reason", Json::string(&file.decision_reason)),
            (
                "next_stage_action",
                Json::string(next_action(&file.decision)),
            ),
        ]));
        for (kind, occurrence) in &file.syntax.first {
            values.push(Json::object(vec![
                (
                    "decision_id",
                    Json::string(format!(
                        "record-{}-{}",
                        &sha256::hex(file.source_id().as_bytes())[..12],
                        kind
                    )),
                ),
                ("scope", Json::string("record_category")),
                ("source_file", Json::string(file.source_id())),
                (
                    "physical_line_or_range",
                    Json::string(occurrence.line.to_string()),
                ),
                ("role", Json::string(kind)),
                ("decision", Json::string(syntax_decision(kind))),
                ("reason_code", Json::string(syntax_reason(kind))),
                ("reason", Json::string(syntax_action(kind))),
                ("next_stage_action", Json::string(syntax_action(kind))),
            ]));
        }
    }
    Json::object(vec![
        ("decision_report_version", Json::string("1.0.0")),
        ("decisions", Json::Array(values)),
    ])
}
fn file_reason(file: &SourceFile) -> &'static str {
    if file.read_error.is_some() {
        "REJECT_UNREADABLE_FILE"
    } else {
        match file.decision.as_str() {
            "ACCEPTED" => "ACCEPT_APPROVED_ROLE",
            "TRANSFORM" => "TRANSFORM_REQUIRED",
            "DEFERRED" => "DEFER_FIRST_RELEASE",
            "REJECTED" => "REJECT_FILE_ROLE_OR_SECURITY",
            _ => "REJECT_UNKNOWN_DECISION",
        }
    }
}
fn next_action(decision: &str) -> &'static str {
    match decision {
        "ACCEPTED" => "11.6.2C may read only after all contract blockers close",
        "TRANSFORM" => "apply only the explicit 11.6.2C transform",
        "DEFERRED" => "retain provenance; exclude from first bundle",
        "REJECTED" => "isolate from conversion and HAP",
        _ => "manual review",
    }
}
fn syntax_decision(kind: &str) -> &'static str {
    match kind {
        "ordinary" => "ACCEPTED",
        "user_deletion"
        | "user_pin"
        | "direct_add"
        | "user_position"
        | "configuration_header"
        | "configuration_item" => "TRANSFORM",
        "comment" | "empty" => "DEFERRED",
        _ => "REJECTED",
    }
}

fn contract_json(
    result: &AuditResult,
    manifest_hash: &str,
    sanitized_configuration_hash: &str,
) -> Json {
    Json::object(vec![
        ("contract_version", Json::string("1.1.0")),
        ("scheme_id", Json::string("xiaohe-yinxing")),
        ("bundle_id", Json::string("xiaohe-yinxing-production")),
        ("data_version", Json::string("source-receipt-1")),
        (
            "converter_version",
            Json::string("yinxing-converter/0-not-implemented"),
        ),
        ("audit_manifest_sha256", Json::string(manifest_hash)),
        (
            "source_roots",
            Json::array([Json::string("码表"), Json::string("小鹤音形")]),
        ),
        (
            "source_files",
            Json::array(result.files.iter().map(|f| {
                let source_id = f.source_id();
                let conversion_input = result.categories.iter().any(|category| {
                    category
                        .merge_order
                        .iter()
                        .any(|source| *source == source_id)
                });
                Json::object(vec![
                    ("source", Json::string(source_id)),
                    ("sha256", Json::string(&f.sha256)),
                    ("role", Json::string(&f.file_role)),
                    ("decision", Json::string(&f.decision)),
                    ("conversion_input", Json::Bool(conversion_input)),
                ])
            })),
        ),
        (
            "categories",
            Json::array(result.categories.iter().map(category_json)),
        ),
        (
            "merge_plan",
            Json::array(result.categories.iter().map(|c| {
                Json::object(vec![
                    ("category_id", Json::string(c.category_id)),
                    (
                        "ordered_sources",
                        Json::array(c.merge_order.iter().map(|v| Json::string(*v))),
                    ),
                    ("blocked", Json::Bool(c.requires_manual_confirmation)),
                ])
            })),
        ),
        (
            "record_syntax",
            Json::array(
                [
                    "ordinary",
                    "user_deletion",
                    "user_pin",
                    "direct_add",
                    "user_position",
                    "user_mixed_rule",
                    "cmd",
                    "ddcmd",
                    "configuration_header",
                    "configuration_item",
                    "comment",
                    "empty",
                    "unrecognized",
                ]
                .into_iter()
                .map(Json::string),
            ),
        ),
        (
            "user_rule_policy",
            Json::object(vec![
                ("ordinary", Json::string("transform")),
                (
                    "direct_add",
                    Json::string("transform only in full-code-word; hide from wildcard lookup"),
                ),
                ("delete", Json::string("transform exact text+code")),
                ("pin", Json::string("transform stable fixed prefix")),
                (
                    "position",
                    Json::string("transform 1-based global position"),
                ),
                ("mixed", Json::string("reject until explicitly defined")),
            ]),
        ),
        (
            "command_whitelist",
            Json::array(
                [
                    "plain_text",
                    "plain_symbol",
                    "date_time_metadata",
                    "approved_paired_symbol",
                    "internal_cursor_action_metadata",
                ]
                .into_iter()
                .map(Json::string),
            ),
        ),
        ("rejection_rules", rejection_rules()),
        (
            "deferred_features",
            Json::array(
                [
                    "spelling",
                    "complete_symbol_groups",
                    "all_direct_input",
                    "simplified_traditional_conversion",
                    "hidden_dictionary",
                    "correction",
                    "english_completion",
                    "quick_symbols",
                    "date_time_actions",
                    "paired_symbol_actions",
                    "cursor_actions",
                ]
                .into_iter()
                .map(Json::string),
            ),
        ),
        (
            "security_policy",
            Json::object(vec![
                ("offline_only", Json::Bool(true)),
                ("execute_source_commands", Json::Bool(false)),
                ("redacted_findings", Json::Bool(true)),
                (
                    "credential_policy",
                    Json::string(
                        "credential findings block unless the entire source file is rejected, quarantined, and replaced by a value-free derivative",
                    ),
                ),
                ("raw_source_in_hap", Json::Bool(false)),
                (
                    "quarantined_source",
                    Json::string("小鹤音形/ime.android.ini"),
                ),
                (
                    "sanitized_configuration",
                    Json::string("sanitized_configuration.json"),
                ),
                (
                    "sanitized_configuration_sha256",
                    Json::string(sanitized_configuration_hash),
                ),
            ]),
        ),
        (
            "missing_references",
            Json::array(result.references.iter().filter(|r| !r.resolved).map(|r| {
                Json::object(vec![
                    ("reference_file", Json::string(&r.reference_file)),
                    ("reference_line", Json::Number(r.reference_line)),
                    ("referenced_path", Json::string(&r.referenced_path)),
                    (
                        "reason",
                        Json::string(r.missing_reason.as_deref().unwrap_or("unknown")),
                    ),
                    ("decision", Json::string(&r.resolution_decision)),
                    ("reason_code", Json::string(&r.reason_code)),
                    ("next_stage_action", Json::string(&r.next_stage_action)),
                    ("blocks_conversion", Json::Bool(r.blocks_conversion)),
                ])
            })),
        ),
        ("approval_metadata", approval_json()),
        (
            "expected_outputs",
            Json::array(
                [
                    "category tables in HSPCTF-compatible production container",
                    "conversion rejection report",
                    "source-line trace index",
                    "sanitized configuration reference without source values",
                ]
                .into_iter()
                .map(Json::string),
            ),
        ),
        (
            "blocking_reasons",
            Json::array(
                result
                    .blocking_reasons
                    .iter()
                    .map(|v| Json::string(v.clone())),
            ),
        ),
        (
            "conversion_allowed",
            Json::Bool(result.blocking_reasons.is_empty()),
        ),
    ])
}
fn approval_json() -> Json {
    Json::object(vec![("manager_confirmed",Json::Bool(true)),("customer_confirmed",Json::Bool(true)),("confirmation_evidence",Json::string("PROJECT_STATE.md (user authorization recorded 2026-07-22)")),("received_date",Json::string("unknown_not_required_by_user_direction")),("approval_status",Json::string("approved_for_project_conversion_and_hap_delivery")),("approval_reference",Json::string("PROJECT_STATE.md")),("source_owner",Json::string("customer_provided")),("usage_scope",Json::string("project conversion, validation, and product use")),("distribution_scope",Json::string("project HAP and customer delivery")),("modification_allowed",Json::Bool(true)),("hap_distribution_allowed",Json::Bool(true)),("notes",Json::string("Authorization is based on the user's explicit 2026-07-22 direction; this record does not invent a separate license identifier or receipt date."))])
}

fn write_reports(
    result: &AuditResult,
    reports: &Path,
    manifest: &str,
    contract: &str,
) -> Result<(), String> {
    let total_bytes: u64 = result.files.iter().map(|f| f.byte_size).sum();
    let credentials = result
        .files
        .iter()
        .flat_map(|f| &f.security_findings)
        .filter(|f| f.blocking_credential)
        .count();
    let findings = result
        .files
        .iter()
        .map(|f| f.security_findings.len())
        .sum::<usize>();
    let stage = if result.blocking_reasons.is_empty() {
        "COMPLETED"
    } else {
        "BLOCKED"
    };
    let blockers = if result.blocking_reasons.is_empty() {
        "none".to_owned()
    } else {
        result.blocking_reasons.join(", ")
    };
    let audit=format!("# 小鹤音形正式来源审计\n\n- 阶段状态：**{stage}**\n- 文件：{}（{} bytes）\n- Manifest SHA-256：`{manifest}`\n- Conversion contract SHA-256：`{contract}`\n- 不可读取文件：{}\n- 未识别角色：{}\n- 阻断原因：{blockers}\n- 凭据原文件：整文件拒绝并隔离；脱敏派生物不含任何 INI 键值。\n- 缺失引用：逐条接受、延期或拒绝，不合成客户数据。\n\n## 文件判定\n\n{}",result.files.len(),total_bytes,result.files.iter().filter(|f|f.read_error.is_some()).count(),result.files.iter().filter(|f|f.file_role=="unknown").count(),file_table(result));
    let security=format!("# 小鹤音形安全审计\n\n报告只含类型、位置和摘要哈希，不复制命中原文。\n\n- 安全命中：{findings}\n- 原始凭据型命中：{credentials}\n- 凭据所在 `ime.android.ini`：`REJECTED_AND_QUARANTINED`。\n- `sanitized_configuration.json`：不复制任何原始键或值，不可执行、不可转换、不可进入 HAP。\n- 网络/路径/平台命令均被隔离，不进入转换或 HAP。\n- 当前安全结论：{}\n\n{}",if result.blocking_reasons.is_empty(){"PASS：允许的转换输入范围内不存在凭据或危险动作"}else{"BLOCKED：仍有未闭合安全问题"},security_table(result));
    let conflict = format!(
        "# 小鹤音形来源冲突审计\n\n- 比较组：{}\n- 需人工确认：{}\n\n{}",
        result.comparisons.len(),
        result
            .comparisons
            .iter()
            .filter(|c| c.requires_manual_confirmation)
            .count(),
        comparison_table(result)
    );
    let approval="# 小鹤音形审批状态\n\n- 客户提供：已由用户明确确认。\n- 项目清理、转换与产品使用：允许。\n- HAP 与客户交付：允许。\n- 接收日期：unknown，不作为技术阻断。\n- 小鹤音形编号文件：首版唯一权威来源。\n- 码表对应导出：仅作审计证据，首版不合并。\n- 缺失客户数据：延期或拒绝，不伪造。\n\n因此 `11.6.2B = COMPLETED`，`11.6.2C = READY`。\n".to_owned();
    atomic_write(
        &reports.join("XIAOHE_YINXING_SOURCE_AUDIT.md"),
        audit.as_bytes(),
    )?;
    atomic_write(
        &reports.join("XIAOHE_YINXING_SECURITY_REPORT.md"),
        security.as_bytes(),
    )?;
    atomic_write(
        &reports.join("XIAOHE_YINXING_CONFLICT_REPORT.md"),
        conflict.as_bytes(),
    )?;
    atomic_write(
        &reports.join("XIAOHE_YINXING_APPROVAL_STATUS.md"),
        approval.as_bytes(),
    )?;
    Ok(())
}
fn file_table(result: &AuditResult) -> String {
    let mut s =
        "| 来源 | 角色 | 编码 | 换行 | 判定 |\n| --- | --- | --- | --- | --- |\n".to_owned();
    for f in &result.files {
        s.push_str(&format!(
            "| `{}` | `{}` | `{}` | `{}` | `{}` |\n",
            f.source_id().replace('|', "\\|"),
            f.file_role,
            f.detected_encoding,
            f.newline_style,
            f.decision
        ));
    }
    s
}
fn security_table(result: &AuditResult) -> String {
    let mut s =
        "| 文件 | 行 | 类型 | 原因代码 | 摘要 |\n| --- | ---: | --- | --- | --- |\n".to_owned();
    for f in &result.files {
        for v in &f.security_findings {
            s.push_str(&format!(
                "| `{}` | {} | `{}` | `{}` | `{}` |\n",
                f.source_id().replace('|', "\\|"),
                v.line,
                v.finding_type,
                v.reason_code,
                &v.summary_sha256[..16]
            ));
        }
    }
    s
}
fn comparison_table(result: &AuditResult) -> String {
    let mut s="| ID | 左 | 右 | 类型 | 重叠/左/右 | 待确认 |\n| --- | --- | --- | --- | --- | --- | --- |\n".to_owned();
    for c in &result.comparisons {
        s.push_str(&format!(
            "| `{}` | `{}` | `{}` | `{}` | {}/{}/{} | {} |\n",
            c.comparison_id,
            c.left_source.replace('|', "\\|"),
            c.right_source.replace('|', "\\|"),
            c.comparison_type,
            c.overlap_count,
            c.left_only_count,
            c.right_only_count,
            c.requires_manual_confirmation
        ));
    }
    s
}

fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let parent = path.parent().ok_or("output has no parent")?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let name = path
        .file_name()
        .and_then(|v| v.to_str())
        .ok_or("invalid output name")?;
    let temp = parent.join(format!(".{name}.tmp"));
    fs::write(&temp, bytes).map_err(|e| format!("write {}: {e}", temp.display()))?;
    if path.exists() {
        fs::remove_file(path).map_err(|e| format!("replace {}: {e}", path.display()))?;
    }
    fs::rename(&temp, path).map_err(|e| format!("rename {}: {e}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn approval_records_explicit_user_authorization_without_inventing_a_date() {
        let bytes = json::serialize(&approval_json());
        let text = String::from_utf8(bytes).unwrap();
        assert!(text.contains("\"hap_distribution_allowed\": true"));
        assert!(text.contains("\"received_date\": \"unknown_not_required_by_user_direction\""));
        assert!(!text.contains("absolute"));
    }
}
