use std::collections::BTreeSet;

use crate::error::{ConverterError, ErrorCode, Result};
use crate::input::SourceInput;
use crate::model::{
    ActionDisposition, ActionRecord, CategoryBuild, CategoryStatistics, CommandFinding,
    RejectedRecord, SystemRecord, UserAction, UserRuleRecord, ValidatedContract,
};
use crate::sha256;
use crate::unicode_validation::{
    normalize_code, normalize_code_with_limit, validate_action_argument, validate_word, TextError,
};
use crate::version::MAX_OK_SPELLING_CODE_LEN;

pub fn parse_all(
    inputs: &[SourceInput],
    contract: &ValidatedContract,
) -> Result<Vec<CategoryBuild>> {
    inputs
        .iter()
        .map(|input| parse_category(input, contract))
        .collect()
}

pub fn parse_category(input: &SourceInput, contract: &ValidatedContract) -> Result<CategoryBuild> {
    let text = decode_text(&input.bytes, &input.spec.source_file_id)?;
    let mut stats = CategoryStatistics {
        input_bytes: input.bytes.len() as u64,
        ..CategoryStatistics::default()
    };
    let mut system_records = Vec::new();
    let mut user_rules = Vec::new();
    let mut actions = Vec::new();
    let mut rejected = Vec::new();
    let mut duplicate_keys = BTreeSet::new();

    for (index, raw_line) in text.split_terminator('\n').enumerate() {
        let physical_line = index as u64 + 1;
        stats.physical_lines += 1;
        let line = raw_line.strip_suffix('\r').unwrap_or(raw_line);
        if line.contains('\r') {
            return Err(ConverterError::new(
                ErrorCode::UnsafeControl,
                format!(
                    "source_file_id={} physical_line={} embedded_carriage_return",
                    input.spec.source_file_id, physical_line
                ),
            ));
        }
        if line.chars().any(|ch| ch.is_control() && ch != '\t') {
            return Err(ConverterError::new(
                ErrorCode::UnsafeControl,
                format!(
                    "source_file_id={} physical_line={}",
                    input.spec.source_file_id, physical_line
                ),
            ));
        }
        let digest = sha256::hex(line.trim().as_bytes());
        if let Some(finding) = contract
            .command_findings
            .get(&(input.spec.source_path.clone(), physical_line))
        {
            if finding.summary_sha256 != digest {
                return Err(ConverterError::new(
                    ErrorCode::ContractInvalid,
                    format!(
                        "command_policy_digest_mismatch source_file_id={} physical_line={}",
                        input.spec.source_file_id, physical_line
                    ),
                ));
            }
            record_policy_finding(
                finding,
                &input.spec.source_file_id,
                physical_line,
                &digest,
                line,
                &mut stats,
                &mut actions,
                &mut rejected,
            )?;
            continue;
        }
        if line.is_empty() {
            stats.empty += 1;
            continue;
        }
        if is_configuration_header(line) {
            stats.configuration_headers += 1;
            continue;
        }
        if is_comment(line) {
            stats.comments += 1;
            continue;
        }
        if line.contains("$ddcmd") || line.contains("$cmd") {
            let syntax = if line.contains("$ddcmd") {
                "ddcmd"
            } else {
                "cmd"
            };
            if syntax == "ddcmd" {
                stats.ddcmd += 1;
            } else {
                stats.cmd += 1;
            }
            let action_expression = line.split('\t').next().unwrap_or(line);
            if validate_action_argument(action_expression).is_err() {
                reject(
                    &mut stats,
                    &mut rejected,
                    &input.spec.source_file_id,
                    physical_line,
                    "REJECT_ACTION_ARGUMENT_TOO_LONG",
                    "action argument exceeded policy",
                    &digest,
                );
            } else {
                actions.push(ActionRecord {
                    source_file_id: input.spec.source_file_id.clone(),
                    physical_line,
                    syntax: syntax.to_owned(),
                    disposition: ActionDisposition::Rejected,
                    reason_code: if syntax == "ddcmd" {
                        "REJECT_UNKNOWN_COMMAND_SYNTAX".to_owned()
                    } else {
                        "REJECT_UNSUPPORTED_COMMAND".to_owned()
                    },
                    line_digest: digest.clone(),
                });
                reject(
                    &mut stats,
                    &mut rejected,
                    &input.spec.source_file_id,
                    physical_line,
                    if syntax == "ddcmd" {
                        "REJECT_UNKNOWN_COMMAND_SYNTAX"
                    } else {
                        "REJECT_UNSUPPORTED_COMMAND"
                    },
                    "command excluded by frozen policy",
                    &digest,
                );
            }
            continue;
        }

        let fields = line.split('\t').collect::<Vec<_>>();
        if fields.len() != 2 {
            reject(
                &mut stats,
                &mut rejected,
                &input.spec.source_file_id,
                physical_line,
                if fields.len() < 2 {
                    "REJECT_TAB_MISSING"
                } else {
                    "REJECT_TAB_EXTRA"
                },
                "exactly two TAB-separated fields are required",
                &digest,
            );
            continue;
        }
        let text_field = fields[0];
        let code_field = fields[1];
        if text_field.trim() != text_field || code_field.trim() != code_field {
            reject(
                &mut stats,
                &mut rejected,
                &input.spec.source_file_id,
                physical_line,
                "REJECT_SURROUNDING_WHITESPACE",
                "surrounding whitespace is forbidden",
                &digest,
            );
            continue;
        }
        let is_direct = code_field.ends_with("#直");
        let (commit_text, display_text) = if is_direct {
            match text_field.split_once(',') {
                Some((commit_text, display_text))
                    if !commit_text.is_empty() && !display_text.is_empty() =>
                {
                    (commit_text, Some(display_text))
                }
                Some(_) => {
                    reject(
                        &mut stats,
                        &mut rejected,
                        &input.spec.source_file_id,
                        physical_line,
                        "REJECT_DIRECT_TEXT_INVALID",
                        "direct commit and display text must both be non-empty",
                        &digest,
                    );
                    continue;
                }
                None => (text_field, None),
            }
        } else {
            (text_field, None)
        };
        let features = match validate_word(commit_text) {
            Ok(value) => value,
            Err(error) => {
                reject(
                    &mut stats,
                    &mut rejected,
                    &input.spec.source_file_id,
                    physical_line,
                    text_reason(error),
                    "word failed centralized Unicode policy",
                    &digest,
                );
                continue;
            }
        };
        if let Some(display_text) = display_text {
            if let Err(error) = validate_word(display_text) {
                reject(
                    &mut stats,
                    &mut rejected,
                    &input.spec.source_file_id,
                    physical_line,
                    text_reason(error),
                    "direct display text failed centralized Unicode policy",
                    &digest,
                );
                continue;
            }
        }
        let (base_code, action) = match parse_code_and_action(code_field) {
            Ok(value) => value,
            Err(reason) => {
                if reason == "REJECT_MIXED_USER_RULE" {
                    stats.mixed_rule += 1;
                }
                reject(
                    &mut stats,
                    &mut rejected,
                    &input.spec.source_file_id,
                    physical_line,
                    reason,
                    "code or user rule failed frozen policy",
                    &digest,
                );
                continue;
            }
        };
        let symbol_group_code;
        let code_to_normalize = if input.spec.category_id == "symbol-group" {
            symbol_group_code = format!("o{base_code}");
            symbol_group_code.as_str()
        } else {
            base_code
        };
        let (code, normalized_changed) =
            match normalize_category_code(&input.spec.category_id, code_to_normalize) {
                Ok(value) => value,
                Err(reason) => {
                    reject(
                        &mut stats,
                        &mut rejected,
                        &input.spec.source_file_id,
                        physical_line,
                        reason,
                        "code failed the category-specific ASCII grammar",
                        &digest,
                    );
                    continue;
                }
            };
        let changed = normalized_changed || input.spec.category_id == "symbol-group";
        stats.max_code_length = stats.max_code_length.max(code.len() as u64);
        stats.max_word_length = stats.max_word_length.max(
            commit_text
                .chars()
                .count()
                .max(display_text.map_or(0, |value| value.chars().count())) as u64,
        );
        stats.cjk_extension_records += u64::from(features.cjk_extension);
        stats.emoji_or_special_records += u64::from(features.emoji_or_special);
        stats.normalized += u64::from(changed);

        let force_user_add = matches!(
            input.spec.role.as_str(),
            "user_addition" | "user_mixed_rule"
        );
        if action.is_some() || force_user_add {
            let action = action.unwrap_or(UserAction::Add);
            match action {
                UserAction::Add => stats.user_add += 1,
                UserAction::Delete => stats.user_delete += 1,
                UserAction::Fixed => stats.user_fixed += 1,
                UserAction::Position(_) => stats.user_position += 1,
            }
            let source_order = u32::try_from(user_rules.len()).map_err(|_| {
                ConverterError::new(ErrorCode::InvalidRecord, "user source_order overflow")
            })?;
            user_rules.push(UserRuleRecord {
                text: commit_text.to_owned(),
                display_text: display_text.map(str::to_owned),
                code,
                action,
                source_file_id: input.spec.source_file_id.clone(),
                source_file: input.spec.source_path.clone(),
                source_sha256: input.spec.source_sha256.clone(),
                category_id: input.spec.category_id.clone(),
                physical_line,
                source_order,
                line_digest: digest,
            });
            continue;
        }

        stats.ordinary += 1;
        let duplicate_key = (commit_text.to_owned(), code.clone());
        if !duplicate_keys.insert(duplicate_key) {
            stats.duplicates += 1;
            continue;
        }
        let source_order = u32::try_from(system_records.len()).map_err(|_| {
            ConverterError::new(ErrorCode::InvalidRecord, "system source_order overflow")
        })?;
        stats.accepted_system += 1;
        system_records.push(SystemRecord {
            text: commit_text.to_owned(),
            code,
            source_file_id: input.spec.source_file_id.clone(),
            source_file: input.spec.source_path.clone(),
            source_sha256: input.spec.source_sha256.clone(),
            category_id: input.spec.category_id.clone(),
            physical_line,
            source_order,
            line_digest: digest,
        });
    }
    if !text.is_empty() && stats.physical_lines == 0 {
        stats.physical_lines = 1;
    }
    if system_records.is_empty() {
        return Err(ConverterError::new(
            ErrorCode::InvalidRecord,
            format!(
                "source_file_id={} has no system records",
                input.spec.source_file_id
            ),
        ));
    }
    Ok(CategoryBuild {
        spec: input.spec.clone(),
        system_records,
        user_rules,
        actions,
        rejected,
        stats,
    })
}

/// The customer quick-symbol format reserves `_` for the bare guide prefix and
/// `;` for pressing the guide key a second time.  Keep those two triggers in
/// the isolated quick-symbol lexicon; every ordinary category continues to use
/// the frozen one-to-four ASCII-letter grammar.
fn normalize_category_code(
    category_id: &str,
    value: &str,
) -> std::result::Result<(String, bool), &'static str> {
    if category_id == "quick-symbol" && matches!(value, "_" | ";") {
        return Ok((value.to_owned(), false));
    }
    if category_id == "ok-spelling" {
        let (code, changed) = normalize_code_with_limit(value, MAX_OK_SPELLING_CODE_LEN)?;
        if !code.starts_with("ok") || !matches!(code.len(), 6 | 8) {
            return Err("YX_OK_SPELLING_CODE_INVALID");
        }
        return Ok((code, changed));
    }
    normalize_code(value)
}

fn decode_text<'a>(bytes: &'a [u8], source_file_id: &str) -> Result<&'a str> {
    let bytes = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]).unwrap_or(bytes);
    let text = std::str::from_utf8(bytes).map_err(|error| {
        ConverterError::new(
            ErrorCode::InvalidUtf8,
            format!(
                "source_file_id={source_file_id} valid_up_to={}",
                error.valid_up_to()
            ),
        )
    })?;
    if text.contains('\u{feff}') {
        return Err(ConverterError::new(
            ErrorCode::UnsafeControl,
            format!("source_file_id={source_file_id} unexpected_bom"),
        ));
    }
    Ok(text)
}

fn is_configuration_header(line: &str) -> bool {
    (line.starts_with("----") || line.starts_with("--leadkey") || line.starts_with("--config"))
        && line.contains('=')
}

fn is_comment(line: &str) -> bool {
    line.starts_with("--")
        || line.starts_with("//")
        || line.starts_with(';')
        || line.starts_with("##")
}

fn parse_code_and_action(
    value: &str,
) -> std::result::Result<(&str, Option<UserAction>), &'static str> {
    let marker_count = value.matches('#').count();
    if marker_count > 1 {
        return Err("REJECT_MIXED_USER_RULE");
    }
    let Some((base, marker)) = value.rsplit_once('#') else {
        return Ok((value, None));
    };
    if base.is_empty() || marker.is_empty() {
        return Err("REJECT_USER_RULE_INVALID");
    }
    let action = match marker {
        // `#直` is a source-table-only spelling for an exact-input entry that
        // must stay out of universal-key lookup.  The production bundle stores
        // it in the isolated user-rule layer as an Add record; ordinary exact
        // queries merge that layer, while wildcard queries intentionally read
        // system categories only.
        "直" => UserAction::Add,
        "删" => UserAction::Delete,
        "固" => UserAction::Fixed,
        digits if digits.bytes().all(|byte| byte.is_ascii_digit()) => {
            if digits.starts_with('0') {
                return Err("REJECT_USER_POSITION_INVALID");
            }
            let position = digits
                .parse::<u16>()
                .map_err(|_| "REJECT_USER_POSITION_INVALID")?;
            if position == 0 {
                return Err("REJECT_USER_POSITION_INVALID");
            }
            UserAction::Position(position)
        }
        _ => return Err("REJECT_USER_RULE_UNKNOWN"),
    };
    Ok((base, Some(action)))
}

#[allow(clippy::too_many_arguments)]
fn record_policy_finding(
    finding: &CommandFinding,
    source_file_id: &str,
    physical_line: u64,
    digest: &str,
    line: &str,
    stats: &mut CategoryStatistics,
    actions: &mut Vec<ActionRecord>,
    rejected: &mut Vec<RejectedRecord>,
) -> Result<()> {
    let syntax = if line.contains("$ddcmd") {
        stats.ddcmd += 1;
        "ddcmd"
    } else if line.contains("$cmd") {
        stats.cmd += 1;
        "cmd"
    } else {
        "security_finding"
    };
    let disposition = if finding.decision == "DEFERRED" {
        stats.deferred += 1;
        ActionDisposition::Deferred
    } else {
        stats.rejected += 1;
        ActionDisposition::Rejected
    };
    actions.push(ActionRecord {
        source_file_id: source_file_id.to_owned(),
        physical_line,
        syntax: syntax.to_owned(),
        disposition: disposition.clone(),
        reason_code: finding.reason_code.clone(),
        line_digest: digest.to_owned(),
    });
    if disposition == ActionDisposition::Rejected {
        rejected.push(RejectedRecord {
            source_file_id: source_file_id.to_owned(),
            physical_line,
            reason_code: finding.reason_code.clone(),
            safe_summary: format!("{} excluded by command policy", finding.finding_type),
            line_digest: digest.to_owned(),
        });
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn reject(
    stats: &mut CategoryStatistics,
    rejected: &mut Vec<RejectedRecord>,
    source_file_id: &str,
    physical_line: u64,
    reason_code: &str,
    safe_summary: &str,
    line_digest: &str,
) {
    stats.rejected += 1;
    rejected.push(RejectedRecord {
        source_file_id: source_file_id.to_owned(),
        physical_line,
        reason_code: reason_code.to_owned(),
        safe_summary: safe_summary.to_owned(),
        line_digest: line_digest.to_owned(),
    });
}

fn text_reason(error: TextError) -> &'static str {
    match error {
        TextError::Empty => "REJECT_WORD_EMPTY",
        TextError::TooLong => "REJECT_WORD_TOO_LONG",
        TextError::Control => "REJECT_WORD_CONTROL_CHARACTER",
        TextError::Delimiter => "REJECT_WORD_DELIMITER",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{CategorySpec, ValidatedContract};
    use std::collections::BTreeMap;

    fn input(bytes: &[u8]) -> SourceInput {
        SourceInput {
            spec: CategorySpec {
                category_id: "core".into(),
                display_name: "核心".into(),
                role: "core_code_table".into(),
                order: 0,
                source_path: "小鹤音形/test.txt".into(),
                source_file_id: "src-00".into(),
                source_size: bytes.len() as u64,
                source_sha256: sha256::hex(bytes),
                source_decision: "TRANSFORM".into(),
                default_enabled: true,
            },
            bytes: bytes.to_vec(),
        }
    }

    fn quick_symbol_input(bytes: &[u8]) -> SourceInput {
        let mut source = input(bytes);
        source.spec.category_id = "quick-symbol".into();
        source.spec.role = "quick_symbol".into();
        source
    }

    fn full_code_word_input(bytes: &[u8]) -> SourceInput {
        let mut source = input(bytes);
        source.spec.category_id = "full-code-word".into();
        source.spec.role = "full_code_word".into();
        source
    }

    fn ok_spelling_input(bytes: &[u8]) -> SourceInput {
        let mut source = input(bytes);
        source.spec.category_id = "ok-spelling".into();
        source.spec.role = "spelling_resource".into();
        source
    }

    fn contract() -> ValidatedContract {
        ValidatedContract {
            categories: Vec::new(),
            command_findings: BTreeMap::new(),
            source_manifest_bytes: Vec::new(),
            conversion_contract_bytes: Vec::new(),
            command_policy_sha256: "0".repeat(64),
        }
    }

    #[test]
    fn parses_all_user_rule_forms_and_rejects_mixed_or_invalid_positions() {
        assert_eq!(parse_code_and_action("AbCd").unwrap(), ("AbCd", None));
        assert_eq!(
            parse_code_and_action("abc#直").unwrap().1,
            Some(UserAction::Add)
        );
        assert_eq!(
            parse_code_and_action("abc#删").unwrap().1,
            Some(UserAction::Delete)
        );
        assert_eq!(
            parse_code_and_action("abc#固").unwrap().1,
            Some(UserAction::Fixed)
        );
        assert_eq!(
            parse_code_and_action("abc#1").unwrap().1,
            Some(UserAction::Position(1))
        );
        assert_eq!(
            parse_code_and_action("abc#65535").unwrap().1,
            Some(UserAction::Position(65535))
        );
        for value in ["abc#0", "abc#65536", "abc#删#固", "abc#unknown", "#固"] {
            assert!(parse_code_and_action(value).is_err(), "{value}");
        }
    }

    #[test]
    fn direct_marker_supports_distinct_commit_and_display_text_in_any_category() {
        let result = parse_category(
            &full_code_word_input("普通词\tabcd\n直通词\tefgh#直\n".as_bytes()),
            &contract(),
        )
        .unwrap();
        assert_eq!(result.system_records.len(), 1);
        assert_eq!(result.system_records[0].text, "普通词");
        assert_eq!(result.user_rules.len(), 1);
        assert_eq!(result.user_rules[0].text, "直通词");
        assert_eq!(result.user_rules[0].display_text, None);
        assert_eq!(result.user_rules[0].action, UserAction::Add);
        assert_eq!(result.stats.user_add, 1);

        let core = parse_category(
            &input("普通词\tabcd\n给予,给ʲⁱ̌予\tgwyu#直\n".as_bytes()),
            &contract(),
        )
        .unwrap();
        assert_eq!(core.user_rules[0].text, "给予");
        assert_eq!(core.user_rules[0].display_text.as_deref(), Some("给ʲⁱ̌予"));
        assert_eq!(core.user_rules[0].category_id, "core");

        let rejected = parse_category(
            &input("普通词\tabcd\n,空上屏\tgwyu#直\n空提示,\tgwyv#直\n".as_bytes()),
            &contract(),
        )
        .unwrap();
        assert_eq!(rejected.stats.rejected, 2);
        assert!(rejected
            .rejected
            .iter()
            .all(|record| record.reason_code == "REJECT_DIRECT_TEXT_INVALID"));
    }

    #[test]
    fn ok_spelling_accepts_only_six_or_eight_letter_ok_codes() {
        let result = parse_category(
            &ok_spelling_input(
                "六位\tOkAbCd\n八位\tokabcdef\n过短\tokab\n错前缀\totabcd\n过长\tokabcdefg\n"
                    .as_bytes(),
            ),
            &contract(),
        )
        .unwrap();

        assert_eq!(
            result
                .system_records
                .iter()
                .map(|record| (record.text.as_str(), record.code.as_str()))
                .collect::<Vec<_>>(),
            [("六位", "okabcd"), ("八位", "okabcdef")]
        );
        assert_eq!(result.stats.rejected, 3);
    }

    #[test]
    fn configuration_comments_and_commands_are_distinct() {
        assert!(is_configuration_header("----syntax=cn, code"));
        assert!(is_configuration_header("--leadkey='"));
        assert!(is_comment("-- ordinary comment"));
        assert!(!is_comment("$cmd(x,x)\tabcd"));
    }

    #[test]
    fn quick_symbol_prefix_and_repeat_triggers_are_preserved_but_stay_isolated() {
        let result = parse_category(
            &quick_symbol_input("：\t_\n；\t;\n：“\tq\n".as_bytes()),
            &contract(),
        )
        .unwrap();
        assert_eq!(
            result
                .system_records
                .iter()
                .map(|record| (record.text.as_str(), record.code.as_str()))
                .collect::<Vec<_>>(),
            [("：", "_"), ("；", ";"), ("：“", "q")]
        );
        assert!(normalize_category_code("core", "_").is_err());
        assert!(normalize_category_code("symbol", ";").is_err());
    }

    #[test]
    fn bom_is_removed_only_at_file_start_and_invalid_utf8_is_rejected() {
        assert_eq!(
            decode_text(b"\xef\xbb\xbfword\tabc", "src").unwrap(),
            "word\tabc"
        );
        assert!(decode_text("x\u{feff}y".as_bytes(), "src").is_err());
        assert!(decode_text(b"\xff", "src").is_err());
    }

    #[test]
    fn reads_lf_crlf_and_unterminated_lines_with_physical_numbers() {
        for bytes in [
            "甲\ta\n乙\tab\n".as_bytes(),
            "\u{feff}甲\ta\r\n乙\tab\r\n".as_bytes(),
            "甲\ta\n乙\tab".as_bytes(),
        ] {
            let result = parse_category(&input(bytes), &contract()).unwrap();
            assert_eq!(result.system_records.len(), 2);
            assert_eq!(result.system_records[1].physical_line, 2);
        }
    }

    #[test]
    fn rejects_bad_rows_without_silently_swallowing_them() {
        let bytes = concat!(
            "有效\tabcd\n",
            "missing-tab\n",
            "\tabcd\n",
            "空码\t\n",
            "多栏\tab\textra\n",
            "过长\tabcde\n",
            "混合\tab#删#固\n",
        )
        .as_bytes();
        let result = parse_category(&input(bytes), &contract()).unwrap();
        assert_eq!(result.system_records.len(), 1);
        assert_eq!(result.stats.rejected, 6);
        assert_eq!(result.stats.mixed_rule, 1);
        assert_eq!(result.rejected[0].physical_line, 2);
    }

    #[test]
    fn unsafe_file_controls_block_instead_of_becoming_rejections() {
        for bytes in [
            b"valid\tab\ninvalid\0\tab".as_slice(),
            b"valid\tab\ninvalid\x1f\tab",
        ] {
            let error = parse_category(&input(bytes), &contract()).unwrap_err();
            assert_eq!(error.code, ErrorCode::UnsafeControl);
        }
    }
}
