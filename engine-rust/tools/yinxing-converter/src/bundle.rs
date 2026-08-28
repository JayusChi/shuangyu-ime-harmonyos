use std::collections::BTreeSet;

use code_table_runtime::CodeTableBundle;
use lexicon_core::{build_binary_lexicon_with_source_order, load_binary_lexicon, LexiconEntry};
use user_lexicon::parse_embedded_user_lexicon_bytes;

use crate::error::{ConverterError, ErrorCode, Result};
use crate::json::{self, JsonValue};
use crate::model::{
    ActionDisposition, BuildResult, BuildStatistics, CategoryBuild, OutputFile, UserRuleRecord,
    ValidatedContract,
};
use crate::report;
use crate::sha256;
use crate::version::{
    AUDITOR_VERSION, AUDIT_MANIFEST_VERSION, BUNDLE_ID, CONVERSION_CONTRACT_SHA256,
    CONVERSION_CONTRACT_VERSION, CONVERTER_BINARY_VERSION, CONVERTER_VERSION, DATA_VERSION,
    LEXICON_VERSION, PRODUCTION_FORMAT_MAJOR, PRODUCTION_FORMAT_MINOR, PRODUCTION_FORMAT_VERSION,
    PRODUCTION_MANIFEST_VERSION, SCHEME_ID, SOURCE_MANIFEST_SHA256,
};

pub const BUNDLE_FILE_NAME: &str = "xiaohe-yinxing-production.hsyx";
const MAGIC: [u8; 8] = *b"HSPYXP01";
const HEADER_LEN: usize = 128;
const FLAG_MANIFEST: u16 = 1;
const FLAG_CATEGORY: u16 = 2;
const FLAG_USER_RULES: u16 = 4;
const FLAG_ACTIONS: u16 = 8;
const FLAG_TRACE: u16 = 16;
const FLAG_REPORT: u16 = 32;

pub struct BuiltArtifacts {
    pub files: Vec<OutputFile>,
    pub result: BuildResult,
}

pub fn build_artifacts(
    categories: &[CategoryBuild],
    contract: &ValidatedContract,
) -> Result<BuiltArtifacts> {
    let mut totals = BuildStatistics::default();
    for category in categories {
        totals.add_category(&category.stats);
    }

    let mut category_files = Vec::new();
    for category in categories {
        let entries = category
            .system_records
            .iter()
            .map(|record| {
                LexiconEntry::new(
                    record.text.clone(),
                    record.code.clone(),
                    vec![record.code.clone()],
                    0,
                    vec![category.spec.category_id.clone()],
                )
                .with_source_order(record.source_order)
            })
            .collect::<Vec<_>>();
        let bytes = build_binary_lexicon_with_source_order(
            &entries,
            LEXICON_VERSION,
            CONVERTER_BINARY_VERSION,
        )
        .map_err(|error| ConverterError::new(ErrorCode::Serialization, error.to_string()))?;
        let loaded = load_binary_lexicon(&bytes)
            .map_err(|error| ConverterError::new(ErrorCode::Integrity, error.to_string()))?;
        if loaded.entries.len() != entries.len()
            || loaded.header.format_major != 1
            || loaded.header.format_minor != 1
        {
            return Err(ConverterError::new(
                ErrorCode::Integrity,
                format!("category_round_trip={}", category.spec.category_id),
            ));
        }
        category_files.push(OutputFile::new(
            format!("categories/{}.lex", category.spec.category_id),
            bytes,
            "category",
            category.spec.order,
        ));
    }

    let user_rules = collect_user_rules(categories);
    let user_rule_bytes = write_user_rules(&user_rules);
    parse_embedded_user_lexicon_bytes("user-rules.txt", &user_rule_bytes).map_err(|error| {
        ConverterError::new(
            ErrorCode::Integrity,
            format!("user_rule_round_trip:{error}"),
        )
    })?;
    let user_file = OutputFile::new("user-rules.txt", user_rule_bytes, "user_rules", 0);
    let action_file = OutputFile::new(
        "action-metadata.json",
        action_metadata(categories),
        "actions",
        0,
    );
    let trace_file = OutputFile::new("trace-index.jsonl", trace_index(categories), "trace", 0);
    let report_file = OutputFile::new(
        "build-report.json",
        report::statistics_json(categories, &totals),
        "report",
        0,
    );

    let mut content_files = category_files;
    content_files.extend([user_file, action_file, trace_file, report_file]);
    let bundle_content_sha256 = content_digest(&content_files);
    let manifest_bytes = manifest_json(
        categories,
        &content_files,
        &totals,
        contract,
        &bundle_content_sha256,
    )?;
    let manifest = OutputFile::new("manifest.json", manifest_bytes, "manifest", 0);

    let mut archive_files = vec![manifest.clone()];
    archive_files.extend(content_files.clone());
    let bundle_bytes = build_archive(&archive_files)?;
    CodeTableBundle::load_bytes(&bundle_bytes).map_err(|error| {
        ConverterError::new(ErrorCode::Integrity, format!("runtime_loader:{error}"))
    })?;
    let bundle_sha256 = sha256::hex(&bundle_bytes);
    let bundle_file = OutputFile::new(BUNDLE_FILE_NAME, bundle_bytes, "bundle", 0);

    let mut output_files = archive_files;
    output_files.push(bundle_file);
    let mut output_summary = output_files
        .iter()
        .map(|file| (file.path.clone(), file.bytes.len(), file.sha256.clone()))
        .collect::<Vec<_>>();
    output_summary.sort_by(|left, right| left.0.as_bytes().cmp(right.0.as_bytes()));
    let human = report::human_report(
        &bundle_sha256,
        output_files
            .iter()
            .find(|file| file.path == BUNDLE_FILE_NAME)
            .map_or(0, |file| file.bytes.len()),
        &bundle_content_sha256,
        &totals,
        &output_summary,
    );
    output_files.push(OutputFile::new("build-report.md", human, "human_report", 0));
    output_files.sort_by(|left, right| left.path.as_bytes().cmp(right.path.as_bytes()));

    let bundle_size = output_files
        .iter()
        .find(|file| file.path == BUNDLE_FILE_NAME)
        .map_or(0, |file| file.bytes.len());
    let final_summary = output_files
        .iter()
        .map(|file| (file.path.clone(), file.bytes.len(), file.sha256.clone()))
        .collect::<Vec<_>>();
    Ok(BuiltArtifacts {
        files: output_files,
        result: BuildResult {
            bundle_sha256,
            bundle_bytes: bundle_size,
            bundle_content_sha256,
            output_files: final_summary,
            statistics: totals,
        },
    })
}

fn collect_user_rules(categories: &[CategoryBuild]) -> Vec<UserRuleRecord> {
    let mut output = Vec::new();
    for category in categories {
        for rule in &category.user_rules {
            let mut rule = rule.clone();
            rule.source_order = output.len() as u32;
            output.push(rule);
        }
    }
    output
}

fn write_user_rules(rules: &[UserRuleRecord]) -> Vec<u8> {
    let mut output = String::new();
    for rule in rules {
        output.push_str(&rule.text);
        output.push('\t');
        output.push_str(&rule.code);
        output.push_str(&rule.action.marker());
        output.push('\t');
        output.push_str(rule.display_text.as_deref().unwrap_or(""));
        output.push('\t');
        output.push_str(&rule.category_id);
        output.push('\n');
    }
    output.into_bytes()
}

fn action_metadata(categories: &[CategoryBuild]) -> Vec<u8> {
    let actions = categories
        .iter()
        .flat_map(|category| category.actions.iter())
        .map(|action| {
            JsonValue::object([
                ("source_file_id", JsonValue::string(&action.source_file_id)),
                ("physical_line", JsonValue::Number(action.physical_line)),
                ("syntax", JsonValue::string(&action.syntax)),
                (
                    "disposition",
                    JsonValue::string(match action.disposition {
                        ActionDisposition::Deferred => "DEFERRED",
                        ActionDisposition::Rejected => "REJECTED",
                    }),
                ),
                ("reason_code", JsonValue::string(&action.reason_code)),
                ("line_digest", JsonValue::string(&action.line_digest)),
            ])
        });
    json::serialize(&JsonValue::object([
        ("action_metadata_version", JsonValue::string("1.0.0")),
        ("execution_allowed", JsonValue::Bool(false)),
        ("records", JsonValue::array(actions)),
    ]))
}

fn trace_index(categories: &[CategoryBuild]) -> Vec<u8> {
    let mut output = Vec::new();
    for category in categories {
        for record in &category.system_records {
            output.extend(json::serialize_line(&JsonValue::object([
                ("category_id", JsonValue::string(&record.category_id)),
                ("line_digest", JsonValue::string(&record.line_digest)),
                ("physical_line", JsonValue::Number(record.physical_line)),
                ("record_kind", JsonValue::string("system")),
                ("source_file_id", JsonValue::string(&record.source_file_id)),
                (
                    "source_order",
                    JsonValue::Number(u64::from(record.source_order)),
                ),
                ("source_sha256", JsonValue::string(&record.source_sha256)),
            ])));
        }
        for rule in &category.user_rules {
            output.extend(json::serialize_line(&JsonValue::object([
                ("category_id", JsonValue::string(&rule.category_id)),
                ("line_digest", JsonValue::string(&rule.line_digest)),
                ("physical_line", JsonValue::Number(rule.physical_line)),
                ("record_kind", JsonValue::string("user_rule")),
                ("source_file_id", JsonValue::string(&rule.source_file_id)),
                (
                    "source_order",
                    JsonValue::Number(u64::from(rule.source_order)),
                ),
                ("source_sha256", JsonValue::string(&rule.source_sha256)),
            ])));
        }
    }
    output
}

fn manifest_json(
    categories: &[CategoryBuild],
    files: &[OutputFile],
    totals: &BuildStatistics,
    contract: &ValidatedContract,
    content_sha256: &str,
) -> Result<Vec<u8>> {
    let category_values = categories.iter().map(|category| {
        let path = format!("categories/{}.lex", category.spec.category_id);
        let file = files
            .iter()
            .find(|value| value.path == path)
            .expect("category file");
        JsonValue::object([
            ("category_id", JsonValue::string(&category.spec.category_id)),
            (
                "display_name",
                JsonValue::string(&category.spec.display_name),
            ),
            ("role", JsonValue::string(&category.spec.role)),
            ("order", JsonValue::Number(u64::from(category.spec.order))),
            (
                "default_enabled",
                JsonValue::Bool(category.spec.default_enabled),
            ),
            ("file", JsonValue::string(path)),
            ("byte_size", JsonValue::Number(file.bytes.len() as u64)),
            ("sha256", JsonValue::string(&file.sha256)),
            (
                "entry_count",
                JsonValue::Number(category.system_records.len() as u64),
            ),
            (
                "source_file_id",
                JsonValue::string(&category.spec.source_file_id),
            ),
            (
                "source_sha256",
                JsonValue::string(&category.spec.source_sha256),
            ),
        ])
    });
    let source_files = categories.iter().map(|category| {
        JsonValue::object([
            (
                "source_file_id",
                JsonValue::string(&category.spec.source_file_id),
            ),
            (
                "relative_path",
                JsonValue::string(&category.spec.source_path),
            ),
            ("byte_size", JsonValue::Number(category.spec.source_size)),
            ("sha256", JsonValue::string(&category.spec.source_sha256)),
            ("category_id", JsonValue::string(&category.spec.category_id)),
            ("order", JsonValue::Number(u64::from(category.spec.order))),
            (
                "decision",
                JsonValue::string(&category.spec.source_decision),
            ),
        ])
    });
    let machine_file = |path: &str| -> Result<JsonValue> {
        let file = files
            .iter()
            .find(|value| value.path == path)
            .ok_or_else(|| {
                ConverterError::new(ErrorCode::Serialization, format!("missing output {path}"))
            })?;
        Ok(JsonValue::object([
            ("path", JsonValue::string(path)),
            ("byte_size", JsonValue::Number(file.bytes.len() as u64)),
            ("sha256", JsonValue::string(&file.sha256)),
        ]))
    };
    let category_order = categories
        .iter()
        .map(|category| JsonValue::string(&category.spec.category_id));
    Ok(json::serialize(&JsonValue::object([
        (
            "format_version",
            JsonValue::string(PRODUCTION_FORMAT_VERSION),
        ),
        (
            "manifest_version",
            JsonValue::Number(u64::from(PRODUCTION_MANIFEST_VERSION)),
        ),
        ("scheme_id", JsonValue::string(SCHEME_ID)),
        ("bundle_id", JsonValue::string(BUNDLE_ID)),
        ("data_version", JsonValue::string(DATA_VERSION)),
        ("converter_version", JsonValue::string(CONVERTER_VERSION)),
        ("auditor_version", JsonValue::string(AUDITOR_VERSION)),
        (
            "audit_manifest_version",
            JsonValue::string(AUDIT_MANIFEST_VERSION),
        ),
        (
            "conversion_contract_version",
            JsonValue::string(CONVERSION_CONTRACT_VERSION),
        ),
        (
            "source_manifest_sha256",
            JsonValue::string(SOURCE_MANIFEST_SHA256),
        ),
        (
            "conversion_contract_sha256",
            JsonValue::string(CONVERSION_CONTRACT_SHA256),
        ),
        (
            "command_policy_sha256",
            JsonValue::string(&contract.command_policy_sha256),
        ),
        ("build_timestamp_policy", JsonValue::string("omitted")),
        ("category_count", JsonValue::Number(categories.len() as u64)),
        ("category_order", JsonValue::array(category_order)),
        ("category_files", JsonValue::array(category_values)),
        ("source_files", JsonValue::array(source_files)),
        ("user_rule_file", machine_file("user-rules.txt")?),
        (
            "action_metadata_file",
            machine_file("action-metadata.json")?,
        ),
        ("trace_metadata_file", machine_file("trace-index.jsonl")?),
        ("statistics_file", machine_file("build-report.json")?),
        (
            "input_file_count",
            JsonValue::Number(totals.input_file_count),
        ),
        ("accepted_record_count", JsonValue::Number(totals.accepted)),
        (
            "transformed_record_count",
            JsonValue::Number(totals.transformed),
        ),
        ("rejected_record_count", JsonValue::Number(totals.rejected)),
        ("deferred_record_count", JsonValue::Number(totals.deferred)),
        (
            "duplicate_record_count",
            JsonValue::Number(totals.duplicates),
        ),
        ("conflict_record_count", JsonValue::Number(totals.conflicts)),
        ("bundle_content_sha256", JsonValue::string(content_sha256)),
    ])))
}

fn content_digest(files: &[OutputFile]) -> String {
    let mut material = Vec::new();
    let mut ordered = files.iter().collect::<Vec<_>>();
    ordered.sort_by(|left, right| left.path.as_bytes().cmp(right.path.as_bytes()));
    for file in ordered {
        append_sized(&mut material, file.path.as_bytes());
        append_sized(&mut material, &file.bytes);
    }
    sha256::hex(&material)
}

fn build_archive(files: &[OutputFile]) -> Result<Vec<u8>> {
    if files.first().map(|file| file.path.as_str()) != Some("manifest.json") {
        return Err(ConverterError::new(
            ErrorCode::Serialization,
            "manifest must be first archive entry",
        ));
    }
    let mut paths = BTreeSet::new();
    let mut records = Vec::new();
    for file in files {
        if !paths.insert(file.path.as_str()) {
            return Err(ConverterError::new(
                ErrorCode::Serialization,
                format!("duplicate archive path {}", file.path),
            ));
        }
        write_record(&mut records, file)?;
    }
    let content_hash = sha256::digest(&records);
    let source_hash = sha256::decode(SOURCE_MANIFEST_SHA256)
        .ok_or_else(|| ConverterError::new(ErrorCode::Serialization, "invalid frozen hash"))?;
    let mut bytes = vec![0_u8; HEADER_LEN];
    bytes.extend_from_slice(&records);
    bytes[..8].copy_from_slice(&MAGIC);
    bytes[8..12].copy_from_slice(&(HEADER_LEN as u32).to_le_bytes());
    bytes[12..14].copy_from_slice(&PRODUCTION_FORMAT_MAJOR.to_le_bytes());
    bytes[14..16].copy_from_slice(&PRODUCTION_FORMAT_MINOR.to_le_bytes());
    bytes[16..20].copy_from_slice(&CONVERTER_BINARY_VERSION.to_le_bytes());
    bytes[20..24].copy_from_slice(&PRODUCTION_MANIFEST_VERSION.to_le_bytes());
    bytes[24..28].copy_from_slice(
        &u32::try_from(files.len())
            .map_err(|_| ConverterError::new(ErrorCode::Serialization, "too many archive files"))?
            .to_le_bytes(),
    );
    bytes[28..32].copy_from_slice(
        &u32::try_from(files.iter().filter(|file| file.kind == "category").count())
            .map_err(|_| ConverterError::new(ErrorCode::Serialization, "too many categories"))?
            .to_le_bytes(),
    );
    bytes[32..40].copy_from_slice(&(records.len() as u64).to_le_bytes());
    bytes[40..48].copy_from_slice(&0_u64.to_le_bytes());
    bytes[48..80].copy_from_slice(&source_hash);
    bytes[80..112].copy_from_slice(&content_hash);
    Ok(bytes)
}

fn write_record(output: &mut Vec<u8>, file: &OutputFile) -> Result<()> {
    let path_len = u16::try_from(file.path.len())
        .map_err(|_| ConverterError::new(ErrorCode::Serialization, "archive path too long"))?;
    let flags = match file.kind.as_str() {
        "manifest" => FLAG_MANIFEST,
        "category" => FLAG_CATEGORY,
        "user_rules" => FLAG_USER_RULES,
        "actions" => FLAG_ACTIONS,
        "trace" => FLAG_TRACE,
        "report" => FLAG_REPORT,
        _ => {
            return Err(ConverterError::new(
                ErrorCode::Serialization,
                format!("unsupported archive kind {}", file.kind),
            ))
        }
    };
    output.extend_from_slice(&path_len.to_le_bytes());
    output.extend_from_slice(&flags.to_le_bytes());
    output.extend_from_slice(&file.order.to_le_bytes());
    output.extend_from_slice(&(file.bytes.len() as u64).to_le_bytes());
    output.extend_from_slice(
        &sha256::decode(&file.sha256)
            .ok_or_else(|| ConverterError::new(ErrorCode::Serialization, "invalid output hash"))?,
    );
    output.extend_from_slice(file.path.as_bytes());
    output.extend_from_slice(&file.bytes);
    Ok(())
}

fn append_sized(output: &mut Vec<u8>, value: &[u8]) {
    output.extend_from_slice(&(value.len() as u64).to_le_bytes());
    output.extend_from_slice(value);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        CategorySpec, CategoryStatistics, SystemRecord, UserAction, UserRuleRecord,
    };
    use code_table_runtime::{query_exact_or_prefix, CodeTableErrorKind, CodeTableMatch};
    use std::collections::BTreeMap;

    #[test]
    fn archive_magic_and_versions_are_frozen() {
        assert_eq!(&MAGIC, b"HSPYXP01");
        assert_eq!(HEADER_LEN, 128);
        assert_eq!(PRODUCTION_FORMAT_MAJOR, 1);
        assert_eq!(PRODUCTION_FORMAT_MINOR, 0);
    }

    fn synthetic_categories() -> Vec<CategoryBuild> {
        let ids = [
            "core",
            "category-secondary",
            "one-key-secondary",
            "two-key-secondary",
            "out-of-table-character",
            "full-code-word",
            "rare-character",
            "full-code-character",
        ];
        ids.iter()
            .enumerate()
            .map(|(category_index, id)| {
                let codes: Vec<&str> = if category_index == 0 {
                    vec!["a", "ab", "abc", "abcd", "abce"]
                } else {
                    vec!["zzzz"]
                };
                let system_records = codes
                    .iter()
                    .enumerate()
                    .map(|(index, code)| SystemRecord {
                        text: format!("测试{category_index}{index}"),
                        code: (*code).to_owned(),
                        source_file_id: format!("src-{category_index:02}"),
                        source_file: format!("小鹤音形/{category_index}.txt"),
                        source_sha256: format!("{category_index:064x}"),
                        category_id: (*id).to_owned(),
                        physical_line: index as u64 + 1,
                        source_order: index as u32,
                        line_digest: "1".repeat(64),
                    })
                    .collect::<Vec<_>>();
                let mut user_rules = Vec::new();
                if category_index == 0 {
                    user_rules.push(UserRuleRecord {
                        text: "固定词".into(),
                        display_text: None,
                        code: "abcd".into(),
                        action: UserAction::Fixed,
                        source_file_id: "src-00".into(),
                        source_file: "小鹤音形/0.txt".into(),
                        source_sha256: "0".repeat(64),
                        category_id: "core".into(),
                        physical_line: 99,
                        source_order: 0,
                        line_digest: "2".repeat(64),
                    });
                }
                CategoryBuild {
                    spec: CategorySpec {
                        category_id: (*id).to_owned(),
                        display_name: (*id).to_owned(),
                        role: "test_role".into(),
                        order: category_index as u32,
                        source_path: format!("小鹤音形/{category_index}.txt"),
                        source_file_id: format!("src-{category_index:02}"),
                        source_size: 1,
                        source_sha256: format!("{category_index:064x}"),
                        source_decision: "TRANSFORM".into(),
                        default_enabled: true,
                    },
                    stats: CategoryStatistics {
                        ordinary: system_records.len() as u64,
                        accepted_system: system_records.len() as u64,
                        user_fixed: user_rules.len() as u64,
                        ..CategoryStatistics::default()
                    },
                    system_records,
                    user_rules,
                    actions: Vec::new(),
                    rejected: Vec::new(),
                }
            })
            .collect()
    }

    fn synthetic_contract() -> ValidatedContract {
        ValidatedContract {
            categories: Vec::new(),
            command_findings: BTreeMap::new(),
            source_manifest_bytes: Vec::new(),
            conversion_contract_bytes: Vec::new(),
            command_policy_sha256: "0".repeat(64),
        }
    }

    #[test]
    fn production_archive_round_trip_queries_and_parses_user_rules() {
        let build = build_artifacts(&synthetic_categories(), &synthetic_contract()).unwrap();
        let bundle_file = build
            .files
            .iter()
            .find(|file| file.path == BUNDLE_FILE_NAME)
            .unwrap();
        let bundle = CodeTableBundle::load_bytes(&bundle_file.bytes).unwrap();
        assert_eq!(bundle.categories.len(), 8);
        assert!(bundle.guide.is_none());
        assert!(bundle.user_rules.is_some());
        let enabled = bundle.default_enabled_category_ids();
        for code in ["a", "ab", "abc", "abcd"] {
            let result = query_exact_or_prefix(&bundle, &enabled, code, 100);
            assert_eq!(result.match_type, Some(CodeTableMatch::Exact));
            assert!(!result.candidates.is_empty());
        }
        let fallback = query_exact_or_prefix(&bundle, &enabled, "abcx", 100);
        assert_eq!(fallback.match_type, Some(CodeTableMatch::Prefix));
        assert!(fallback.candidates.is_empty());
        assert!(query_exact_or_prefix(&bundle, &enabled, "", 100)
            .candidates
            .is_empty());
    }

    #[test]
    fn production_archive_is_deterministic_and_tamper_safe() {
        let left = build_artifacts(&synthetic_categories(), &synthetic_contract()).unwrap();
        let right = build_artifacts(&synthetic_categories(), &synthetic_contract()).unwrap();
        assert_eq!(left.files, right.files);
        let bytes = &left
            .files
            .iter()
            .find(|file| file.path == BUNDLE_FILE_NAME)
            .unwrap()
            .bytes;
        for mut damaged in [
            bytes[..bytes.len() - 1].to_vec(),
            {
                let mut value = bytes.clone();
                value[0] ^= 1;
                value
            },
            {
                let mut value = bytes.clone();
                value[12] = 2;
                value
            },
            {
                let mut value = bytes.clone();
                let last = value.len() - 1;
                value[last] ^= 1;
                value
            },
        ] {
            assert!(CodeTableBundle::load_bytes(&damaged).is_err());
            damaged.clear();
        }
        assert!(CodeTableBundle::load_bytes(&[]).is_err());
    }

    #[test]
    fn production_archive_rejects_a_manifest_declared_missing_file() {
        let build = build_artifacts(&synthetic_categories(), &synthetic_contract()).unwrap();
        let manifest = build
            .files
            .iter()
            .find(|file| file.path == "manifest.json")
            .unwrap()
            .clone();
        let mut archive_files = vec![manifest];
        archive_files.extend(
            build
                .files
                .iter()
                .filter(|file| {
                    file.path != "manifest.json"
                        && file.path != "user-rules.txt"
                        && file.path != BUNDLE_FILE_NAME
                        && file.path != "build-report.md"
                })
                .cloned(),
        );
        let bytes = build_archive(&archive_files).unwrap();
        let error = CodeTableBundle::load_bytes(&bytes).unwrap_err();
        assert_eq!(error.kind, CodeTableErrorKind::MissingBundleFile);
    }
}
