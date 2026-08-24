use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;

use crate::error::{ConverterError, ErrorCode, Result};
use crate::json::{self, JsonValue};
use crate::model::{CategorySpec, CommandFinding, ValidatedContract};
use crate::sha256;
use crate::version::{
    AUDITOR_VERSION, AUDIT_MANIFEST_VERSION, BUNDLE_ID, CATEGORY_COUNT, CONVERSION_CONTRACT_SHA256,
    CONVERSION_CONTRACT_VERSION, DATA_VERSION, FROZEN_CONVERTER_PLACEHOLDER,
    SANITIZED_CONFIGURATION_SHA256, SCHEME_ID, SOURCE_MANIFEST_SHA256,
};

const EXPECTED_CATEGORIES: [(&str, &str, &str); CATEGORY_COUNT] = [
    ("core", "core_code_table", "小鹤音形/0.0.小鹤.txt"),
    (
        "category-secondary",
        "category_table",
        "小鹤音形/1.0.分类.txt",
    ),
    ("quick-symbol", "quick_symbol", "小鹤音形/1.2.快符-外接.txt"),
    (
        "one-key-secondary",
        "one_key_secondary_table",
        "小鹤音形/2.1.一简次选.txt",
    ),
    (
        "two-key-secondary",
        "two_key_secondary_table",
        "小鹤音形/2.2.二简次选.txt",
    ),
    (
        "out-of-table-character",
        "out_of_table_character",
        "小鹤音形/2.4.表外字.txt",
    ),
    (
        "full-code-word",
        "full_code_word",
        "小鹤音形/2.5.全码词.txt",
    ),
    ("symbol", "symbol_table", "小鹤音形/2.6.符号.txt"),
    ("symbol-group", "symbol_group", "小鹤音形/2.7.符号组.txt"),
    (
        "rare-character",
        "rare_character",
        "小鹤音形/2.8.生僻字.txt",
    ),
    (
        "full-code-character",
        "full_code_character",
        "小鹤音形/2.9.全码字.txt",
    ),
    ("ok-spelling", "spelling_resource", "小鹤音形/0.2.拼字.txt"),
];

pub fn load_and_validate(
    contract_path: &Path,
    source_manifest_path: &Path,
    command_policy_path: &Path,
    sanitized_configuration_path: &Path,
) -> Result<ValidatedContract> {
    let contract_bytes = read(contract_path)?;
    let source_manifest_bytes = read(source_manifest_path)?;
    let command_policy_bytes = read(command_policy_path)?;
    let sanitized_bytes = read(sanitized_configuration_path)?;
    verify_hash(
        "conversion_contract",
        &contract_bytes,
        CONVERSION_CONTRACT_SHA256,
    )?;
    verify_hash(
        "source_manifest",
        &source_manifest_bytes,
        SOURCE_MANIFEST_SHA256,
    )?;
    verify_hash(
        "sanitized_configuration",
        &sanitized_bytes,
        SANITIZED_CONFIGURATION_SHA256,
    )?;

    let contract = parse_object(&contract_bytes, "conversion_contract")?;
    let manifest = parse_object(&source_manifest_bytes, "source_manifest")?;
    validate_identity(&contract, &manifest)?;
    let categories = validate_categories(&contract, &manifest)?;
    let command_findings = parse_command_policy(&command_policy_bytes)?;
    Ok(ValidatedContract {
        categories,
        command_findings,
        source_manifest_bytes,
        conversion_contract_bytes: contract_bytes,
        command_policy_sha256: sha256::hex(&command_policy_bytes),
    })
}

fn read(path: &Path) -> Result<Vec<u8>> {
    fs::read(path).map_err(|error| ConverterError::io(path, &error))
}

fn verify_hash(name: &str, bytes: &[u8], expected: &str) -> Result<()> {
    let actual = sha256::hex(bytes);
    if actual != expected {
        return Err(ConverterError::new(
            ErrorCode::FrozenHashMismatch,
            format!("artifact={name} expected={expected} actual={actual}"),
        ));
    }
    Ok(())
}

fn parse_object(bytes: &[u8], name: &str) -> Result<BTreeMap<String, JsonValue>> {
    json::parse(bytes)
        .map_err(|detail| ConverterError::new(ErrorCode::JsonInvalid, format!("{name}:{detail}")))?
        .as_object()
        .cloned()
        .ok_or_else(|| ConverterError::new(ErrorCode::JsonInvalid, format!("{name}:not_object")))
}

fn validate_identity(
    contract: &BTreeMap<String, JsonValue>,
    manifest: &BTreeMap<String, JsonValue>,
) -> Result<()> {
    expect_string(
        contract,
        "contract_version",
        CONVERSION_CONTRACT_VERSION,
        ErrorCode::ContractVersion,
    )?;
    expect_string(
        contract,
        "scheme_id",
        SCHEME_ID,
        ErrorCode::IdentityMismatch,
    )?;
    expect_string(
        contract,
        "bundle_id",
        BUNDLE_ID,
        ErrorCode::IdentityMismatch,
    )?;
    expect_string(
        contract,
        "data_version",
        DATA_VERSION,
        ErrorCode::IdentityMismatch,
    )?;
    expect_string(
        contract,
        "converter_version",
        FROZEN_CONVERTER_PLACEHOLDER,
        ErrorCode::IdentityMismatch,
    )?;
    expect_string(
        contract,
        "audit_manifest_sha256",
        SOURCE_MANIFEST_SHA256,
        ErrorCode::FrozenHashMismatch,
    )?;
    if !get_bool(contract, "conversion_allowed")? {
        return Err(invalid("conversion_allowed must be true"));
    }
    if !get_array(contract, "blocking_reasons")?.is_empty() {
        return Err(invalid("blocking_reasons must be empty"));
    }

    expect_string(
        manifest,
        "audit_manifest_version",
        AUDIT_MANIFEST_VERSION,
        ErrorCode::ContractVersion,
    )?;
    expect_string(
        manifest,
        "scheme_id",
        SCHEME_ID,
        ErrorCode::IdentityMismatch,
    )?;
    expect_string(
        manifest,
        "bundle_id",
        BUNDLE_ID,
        ErrorCode::IdentityMismatch,
    )?;
    expect_string(
        manifest,
        "data_version",
        DATA_VERSION,
        ErrorCode::IdentityMismatch,
    )?;
    expect_string(
        manifest,
        "converter_version",
        AUDITOR_VERSION,
        ErrorCode::IdentityMismatch,
    )?;
    Ok(())
}

fn validate_categories(
    contract: &BTreeMap<String, JsonValue>,
    manifest: &BTreeMap<String, JsonValue>,
) -> Result<Vec<CategorySpec>> {
    let source_values = get_array(contract, "source_files")?;
    let mut contract_sources = BTreeMap::new();
    let mut conversion_inputs = BTreeSet::new();
    for value in source_values {
        let object = object(value, "source_files[]")?;
        let path = get_string(object, "source")?.to_owned();
        if contract_sources.insert(path.clone(), object).is_some() {
            return Err(invalid("duplicate source file path"));
        }
        if get_bool(object, "conversion_input")? {
            conversion_inputs.insert(path);
        }
    }
    if conversion_inputs.len() != CATEGORY_COUNT {
        return Err(ConverterError::new(
            ErrorCode::CategoryInvalid,
            format!("conversion_input_count={}", conversion_inputs.len()),
        ));
    }

    let manifest_values = get_array(manifest, "files")?;
    let mut manifest_files = BTreeMap::new();
    for value in manifest_values {
        let object = object(value, "files[]")?;
        let source_root = get_string(object, "source_root")?;
        let relative_path = get_string(object, "relative_path")?;
        manifest_files.insert(format!("{source_root}/{relative_path}"), object);
    }

    let category_values = get_array(contract, "categories")?;
    let merge_values = get_array(contract, "merge_plan")?;
    if category_values.len() != CATEGORY_COUNT || merge_values.len() != CATEGORY_COUNT {
        return Err(ConverterError::new(
            ErrorCode::CategoryInvalid,
            "category or merge-plan count does not match the frozen profile",
        ));
    }
    let mut ids = BTreeSet::new();
    let mut output = Vec::with_capacity(CATEGORY_COUNT);
    for (index, ((expected_id, expected_role, expected_path), category_value)) in
        EXPECTED_CATEGORIES.iter().zip(category_values).enumerate()
    {
        let category = object(category_value, "categories[]")?;
        let id = get_string(category, "category_id")?;
        let role = get_string(category, "role")?;
        let path = get_string(category, "authoritative_source")?;
        if id != *expected_id || role != *expected_role || path != *expected_path {
            return Err(ConverterError::new(
                ErrorCode::CategoryInvalid,
                format!("category_order_mismatch index={index}"),
            ));
        }
        if !ids.insert(id) {
            return Err(ConverterError::new(
                ErrorCode::CategoryInvalid,
                format!("duplicate_category_id={id}"),
            ));
        }
        if !get_array(category, "supplemental_sources")?.is_empty()
            || get_array(category, "merge_order")?.len() != 1
            || get_array(category, "merge_order")?[0].as_str() != Some(path)
            || get_string(category, "first_release_scope")? != "authoritative_source_only"
            || get_bool(category, "requires_manual_confirmation")?
        {
            return Err(ConverterError::new(
                ErrorCode::CategoryInvalid,
                format!("category_contract_not_frozen id={id}"),
            ));
        }

        let merge = object(&merge_values[index], "merge_plan[]")?;
        if get_string(merge, "category_id")? != id
            || get_bool(merge, "blocked")?
            || get_array(merge, "ordered_sources")?.len() != 1
            || get_array(merge, "ordered_sources")?[0].as_str() != Some(path)
        {
            return Err(ConverterError::new(
                ErrorCode::CategoryInvalid,
                format!("merge_plan_mismatch id={id}"),
            ));
        }

        let source = contract_sources
            .get(path)
            .copied()
            .ok_or_else(|| invalid("authoritative source missing from source_files"))?;
        if !get_bool(source, "conversion_input")?
            || get_string(source, "role")? != role
            || !matches!(get_string(source, "decision")?, "ACCEPTED" | "TRANSFORM")
        {
            return Err(ConverterError::new(
                ErrorCode::CategoryInvalid,
                format!("source_not_authorized path={path}"),
            ));
        }
        let manifest_file = manifest_files
            .get(path)
            .copied()
            .ok_or_else(|| invalid("authoritative source missing from source manifest"))?;
        if get_string(manifest_file, "file_role")? != role
            || !matches!(
                get_string(manifest_file, "decision")?,
                "ACCEPTED" | "TRANSFORM"
            )
            || get_string(manifest_file, "sha256")? != get_string(source, "sha256")?
        {
            return Err(ConverterError::new(
                ErrorCode::CategoryInvalid,
                format!("manifest_source_mismatch path={path}"),
            ));
        }
        conversion_inputs.remove(path);
        output.push(CategorySpec {
            category_id: id.to_owned(),
            display_name: get_string(category, "display_name")?.to_owned(),
            role: role.to_owned(),
            order: u32::try_from(index).map_err(|_| {
                ConverterError::new(ErrorCode::CategoryInvalid, "category order overflow")
            })?,
            source_path: path.to_owned(),
            source_file_id: format!("src-{index:02}"),
            source_size: get_number(manifest_file, "byte_size")?,
            source_sha256: get_string(source, "sha256")?.to_owned(),
            source_decision: get_string(source, "decision")?.to_owned(),
            default_enabled: get_bool(category, "default_enabled")?,
        });
    }
    if !conversion_inputs.is_empty() {
        return Err(ConverterError::new(
            ErrorCode::CategoryInvalid,
            "contract contains conversion input outside frozen categories",
        ));
    }
    Ok(output)
}

fn parse_command_policy(bytes: &[u8]) -> Result<BTreeMap<(String, u64), CommandFinding>> {
    let policy = parse_object(bytes, "command_policy")?;
    expect_string(
        &policy,
        "policy_version",
        "1.0.0",
        ErrorCode::ContractVersion,
    )?;
    let whitelist = get_array(&policy, "candidate_whitelist")?;
    for required in [
        "plain_text",
        "plain_symbol",
        "date_time_metadata",
        "approved_paired_symbol",
        "internal_cursor_action_metadata",
    ] {
        if !whitelist
            .iter()
            .any(|value| value.as_str() == Some(required))
        {
            return Err(invalid("command whitelist is incomplete"));
        }
    }
    let mut findings = BTreeMap::new();
    for value in get_array(&policy, "findings")? {
        let object = object(value, "findings[]")?;
        let finding = CommandFinding {
            source_file: get_string(object, "source_file")?.to_owned(),
            physical_line: get_number(object, "physical_line")?,
            finding_type: get_string(object, "finding_type")?.to_owned(),
            summary_sha256: get_string(object, "summary_sha256")?.to_owned(),
            decision: get_string(object, "decision")?.to_owned(),
            reason_code: get_string(object, "reason_code")?.to_owned(),
        };
        let key = (finding.source_file.clone(), finding.physical_line);
        // A single quarantined line can carry more than one security finding
        // (for example credential plus URL). The converter never reads those
        // non-input sources; for an authorized source line the first frozen
        // disposition is sufficient and remains deterministic.
        findings.entry(key).or_insert(finding);
    }
    Ok(findings)
}

fn object<'a>(value: &'a JsonValue, field: &str) -> Result<&'a BTreeMap<String, JsonValue>> {
    value
        .as_object()
        .ok_or_else(|| invalid(format!("{field} must be object")))
}

fn required<'a>(object: &'a BTreeMap<String, JsonValue>, field: &str) -> Result<&'a JsonValue> {
    object
        .get(field)
        .ok_or_else(|| invalid(format!("missing field {field}")))
}

fn get_string<'a>(object: &'a BTreeMap<String, JsonValue>, field: &str) -> Result<&'a str> {
    required(object, field)?
        .as_str()
        .ok_or_else(|| invalid(format!("field {field} must be string")))
}

fn get_number(object: &BTreeMap<String, JsonValue>, field: &str) -> Result<u64> {
    required(object, field)?
        .as_u64()
        .ok_or_else(|| invalid(format!("field {field} must be unsigned integer")))
}

fn get_bool(object: &BTreeMap<String, JsonValue>, field: &str) -> Result<bool> {
    required(object, field)?
        .as_bool()
        .ok_or_else(|| invalid(format!("field {field} must be boolean")))
}

fn get_array<'a>(object: &'a BTreeMap<String, JsonValue>, field: &str) -> Result<&'a [JsonValue]> {
    required(object, field)?
        .as_array()
        .ok_or_else(|| invalid(format!("field {field} must be array")))
}

fn expect_string(
    object: &BTreeMap<String, JsonValue>,
    field: &str,
    expected: &str,
    code: ErrorCode,
) -> Result<()> {
    let actual = get_string(object, field)?;
    if actual != expected {
        return Err(ConverterError::new(
            code,
            format!("field={field} expected={expected} actual={actual}"),
        ));
    }
    Ok(())
}

fn invalid(detail: impl Into<String>) -> ConverterError {
    ConverterError::new(ErrorCode::ContractInvalid, detail)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn contract_identity() -> BTreeMap<String, JsonValue> {
        JsonValue::object([
            (
                "audit_manifest_sha256",
                JsonValue::string(SOURCE_MANIFEST_SHA256),
            ),
            ("blocking_reasons", JsonValue::array([])),
            ("bundle_id", JsonValue::string(BUNDLE_ID)),
            (
                "contract_version",
                JsonValue::string(CONVERSION_CONTRACT_VERSION),
            ),
            ("conversion_allowed", JsonValue::Bool(true)),
            (
                "converter_version",
                JsonValue::string(FROZEN_CONVERTER_PLACEHOLDER),
            ),
            ("data_version", JsonValue::string(DATA_VERSION)),
            ("scheme_id", JsonValue::string(SCHEME_ID)),
        ])
        .as_object()
        .unwrap()
        .clone()
    }

    fn manifest_identity() -> BTreeMap<String, JsonValue> {
        JsonValue::object([
            (
                "audit_manifest_version",
                JsonValue::string(AUDIT_MANIFEST_VERSION),
            ),
            ("bundle_id", JsonValue::string(BUNDLE_ID)),
            ("converter_version", JsonValue::string(AUDITOR_VERSION)),
            ("data_version", JsonValue::string(DATA_VERSION)),
            ("scheme_id", JsonValue::string(SCHEME_ID)),
        ])
        .as_object()
        .unwrap()
        .clone()
    }

    #[test]
    fn expected_category_order_is_unique_and_exact() {
        let ids = EXPECTED_CATEGORIES
            .iter()
            .map(|value| value.0)
            .collect::<BTreeSet<_>>();
        assert_eq!(ids.len(), CATEGORY_COUNT);
        assert_eq!(
            EXPECTED_CATEGORIES.map(|value| value.0),
            [
                "core",
                "category-secondary",
                "quick-symbol",
                "one-key-secondary",
                "two-key-secondary",
                "out-of-table-character",
                "full-code-word",
                "symbol",
                "symbol-group",
                "rare-character",
                "full-code-character",
                "ok-spelling",
            ]
        );
    }

    #[test]
    fn identity_version_and_blocking_failures_are_distinct() {
        assert!(validate_identity(&contract_identity(), &manifest_identity()).is_ok());
        let cases = [
            ("scheme_id", "other"),
            ("bundle_id", "other"),
            ("contract_version", "2.0.0"),
            ("data_version", "other"),
        ];
        for (field, value) in cases {
            let mut contract = contract_identity();
            contract.insert(field.to_owned(), JsonValue::string(value));
            assert!(
                validate_identity(&contract, &manifest_identity()).is_err(),
                "{field}"
            );
        }
        let mut contract = contract_identity();
        contract.insert("conversion_allowed".into(), JsonValue::Bool(false));
        assert!(validate_identity(&contract, &manifest_identity()).is_err());
        let mut contract = contract_identity();
        contract.insert(
            "blocking_reasons".into(),
            JsonValue::array([JsonValue::string("blocked")]),
        );
        assert!(validate_identity(&contract, &manifest_identity()).is_err());
    }
}
