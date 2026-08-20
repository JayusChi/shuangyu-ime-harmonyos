use std::collections::BTreeMap;

use crate::error::SchemaError;
use crate::json::{parse_json, JsonValue};
use crate::model::{
    FinalMapping, KeyMapping, RuntimeSchema, ShuangpinSchema, SpecialSyllableRule, ZeroInitialRule,
};
use crate::validator::validate_schema;

const XIAOHE_JSON: &str = include_str!("../../../schemas/xiaohe.json");

/// Loads and validates a built-in schema by id.
///
/// Stage 4 ships only `xiaohe`; callers can use `load_schema_from_str` for
/// tests or future user-provided schemas.
pub fn load_builtin_schema(id: &str) -> Result<RuntimeSchema, SchemaError> {
    match id {
        "xiaohe" => load_schema_from_str(XIAOHE_JSON),
        other => Err(SchemaError::SchemaNotFound {
            id: other.to_owned(),
        }),
    }
}

/// Parses a schema JSON string and returns a validated runtime schema.
///
/// No third-party JSON dependency is used in stage 4; the parser supports the
/// JSON value shapes needed by schema files and reports malformed input as a
/// structured configuration error.
pub fn load_schema_from_str(content: &str) -> Result<RuntimeSchema, SchemaError> {
    let value = parse_json(content).map_err(|reason| SchemaError::InvalidConfig { reason })?;
    let schema = schema_from_json(value)?;
    validate_schema(schema)
}

fn schema_from_json(value: JsonValue) -> Result<ShuangpinSchema, SchemaError> {
    let object = object(value, "root")?;
    let id = required_string(&object, "id")?;
    let name = required_string(&object, "name")?;
    let version = required_u32(&object, "version")?;
    let allowed_input_keys = required_string(&object, "allowed_input_keys")?
        .chars()
        .collect();
    let ordinary_initials = mapping_array(&object, "ordinary_initials")?;
    let double_initials = mapping_array(&object, "double_initials")?;
    let finals = final_array(&object, "finals")?;
    let zero_initial = zero_initial_rule(&object)?;
    let special_syllables = special_syllable_array(&object)?;
    let description = optional_string(&object, "description")?;

    Ok(ShuangpinSchema {
        id,
        name,
        version,
        allowed_input_keys,
        ordinary_initials,
        double_initials,
        finals,
        zero_initial,
        special_syllables,
        description,
    })
}

fn mapping_array(
    object: &BTreeMap<String, JsonValue>,
    field: &str,
) -> Result<Vec<KeyMapping>, SchemaError> {
    let array = required_array(object, field)?;
    array
        .iter()
        .map(|value| {
            let item = value_object(value, field)?;
            Ok(KeyMapping {
                key: single_char(&required_string(item, "key")?, field)?,
                value: required_string(item, "value")?,
            })
        })
        .collect()
}

fn final_array(
    object: &BTreeMap<String, JsonValue>,
    field: &str,
) -> Result<Vec<FinalMapping>, SchemaError> {
    let array = required_array(object, field)?;
    array
        .iter()
        .map(|value| {
            let item = value_object(value, field)?;
            Ok(FinalMapping {
                key: single_char(&required_string(item, "key")?, field)?,
                values: required_string_array(item, "values")?,
            })
        })
        .collect()
}

fn zero_initial_rule(object: &BTreeMap<String, JsonValue>) -> Result<ZeroInitialRule, SchemaError> {
    let zero_object = value_object(required_value(object, "zero_initial")?, "zero_initial")?;
    Ok(ZeroInitialRule {
        duplicate_single_letter_finals: required_bool(
            zero_object,
            "duplicate_single_letter_finals",
        )?,
        direct_full_code_finals: required_string_array(zero_object, "direct_full_code_finals")?,
        first_letter_with_final_key_finals: required_string_array(
            zero_object,
            "first_letter_with_final_key_finals",
        )?,
    })
}

fn special_syllable_array(
    object: &BTreeMap<String, JsonValue>,
) -> Result<Vec<SpecialSyllableRule>, SchemaError> {
    let Some(value) = object.get("special_syllables") else {
        return Ok(Vec::new());
    };
    let JsonValue::Array(array) = value else {
        return Err(SchemaError::InvalidConfig {
            reason: "special_syllables must be an array".to_owned(),
        });
    };
    array
        .iter()
        .map(|value| {
            let item = value_object(value, "special_syllables")?;
            Ok(SpecialSyllableRule {
                code: required_string(item, "code")?,
                syllable: required_string(item, "syllable")?,
                initial: required_string(item, "initial")?,
                final_part: required_string(item, "final")?,
            })
        })
        .collect()
}

fn object(value: JsonValue, field: &str) -> Result<BTreeMap<String, JsonValue>, SchemaError> {
    match value {
        JsonValue::Object(object) => Ok(object),
        _ => Err(SchemaError::InvalidConfig {
            reason: format!("{field} must be an object"),
        }),
    }
}

fn value_object<'a>(
    value: &'a JsonValue,
    field: &str,
) -> Result<&'a BTreeMap<String, JsonValue>, SchemaError> {
    match value {
        JsonValue::Object(object) => Ok(object),
        _ => Err(SchemaError::InvalidConfig {
            reason: format!("{field} item must be an object"),
        }),
    }
}

fn required_value<'a>(
    object: &'a BTreeMap<String, JsonValue>,
    field: &str,
) -> Result<&'a JsonValue, SchemaError> {
    object.get(field).ok_or_else(|| SchemaError::MissingField {
        field: field.to_owned(),
    })
}

fn required_string(
    object: &BTreeMap<String, JsonValue>,
    field: &str,
) -> Result<String, SchemaError> {
    match required_value(object, field)? {
        JsonValue::String(value) => Ok(value.clone()),
        _ => Err(SchemaError::InvalidConfig {
            reason: format!("{field} must be a string"),
        }),
    }
}

fn optional_string(
    object: &BTreeMap<String, JsonValue>,
    field: &str,
) -> Result<Option<String>, SchemaError> {
    match object.get(field) {
        Some(JsonValue::String(value)) => Ok(Some(value.clone())),
        Some(JsonValue::Null) | None => Ok(None),
        _ => Err(SchemaError::InvalidConfig {
            reason: format!("{field} must be a string or null"),
        }),
    }
}

fn required_u32(object: &BTreeMap<String, JsonValue>, field: &str) -> Result<u32, SchemaError> {
    match required_value(object, field)? {
        JsonValue::Number(value) if *value >= 0 && *value <= u32::MAX as i64 => Ok(*value as u32),
        _ => Err(SchemaError::InvalidConfig {
            reason: format!("{field} must be a non-negative integer"),
        }),
    }
}

fn required_bool(object: &BTreeMap<String, JsonValue>, field: &str) -> Result<bool, SchemaError> {
    match required_value(object, field)? {
        JsonValue::Bool(value) => Ok(*value),
        _ => Err(SchemaError::InvalidConfig {
            reason: format!("{field} must be a boolean"),
        }),
    }
}

fn required_array<'a>(
    object: &'a BTreeMap<String, JsonValue>,
    field: &str,
) -> Result<&'a [JsonValue], SchemaError> {
    match required_value(object, field)? {
        JsonValue::Array(values) => Ok(values),
        _ => Err(SchemaError::InvalidConfig {
            reason: format!("{field} must be an array"),
        }),
    }
}

fn required_string_array(
    object: &BTreeMap<String, JsonValue>,
    field: &str,
) -> Result<Vec<String>, SchemaError> {
    required_array(object, field)?
        .iter()
        .map(|value| match value {
            JsonValue::String(item) => Ok(item.clone()),
            _ => Err(SchemaError::InvalidConfig {
                reason: format!("{field} must contain only strings"),
            }),
        })
        .collect()
}

fn single_char(value: &str, section: &str) -> Result<char, SchemaError> {
    let mut chars = value.chars();
    let Some(ch) = chars.next() else {
        return Err(SchemaError::InvalidKey {
            section: section.to_owned(),
            key: value.to_owned(),
        });
    };
    if chars.next().is_some() {
        return Err(SchemaError::InvalidKey {
            section: section.to_owned(),
            key: value.to_owned(),
        });
    }
    Ok(ch)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loads_builtin_xiaohe_schema() {
        let runtime = load_builtin_schema("xiaohe").unwrap();

        assert_eq!(runtime.schema().id, "xiaohe");
        assert!(runtime.is_allowed_key('a'));
        assert_eq!(runtime.initial_for_key('v'), Some("zh"));
        assert_eq!(
            runtime.finals_for_key('v').unwrap(),
            &["ui".to_owned(), "v".to_owned()]
        );
        assert_eq!(
            runtime.zero_syllable_for_code("ah").unwrap().syllable,
            "ang"
        );
        assert!(runtime.special_syllable_for_code("vi").is_some());
    }

    #[test]
    fn rejects_unknown_builtin_schema() {
        assert!(matches!(
            load_builtin_schema("missing"),
            Err(SchemaError::SchemaNotFound { .. })
        ));
    }

    #[test]
    fn rejects_empty_id() {
        let json = XIAOHE_JSON.replace("\"id\": \"xiaohe\"", "\"id\": \"\"");
        assert_eq!(load_schema_from_str(&json), Err(SchemaError::EmptyId));
    }

    #[test]
    fn rejects_invalid_key() {
        let json = XIAOHE_JSON.replacen(
            "{ \"key\": \"b\", \"value\": \"b\" }",
            "{ \"key\": \"1\", \"value\": \"b\" }",
            1,
        );
        assert!(matches!(
            load_schema_from_str(&json),
            Err(SchemaError::InvalidKey { .. })
        ));
    }

    #[test]
    fn rejects_duplicate_mapping() {
        let json = XIAOHE_JSON.replacen(
            "{ \"key\": \"p\", \"value\": \"p\" }",
            "{ \"key\": \"b\", \"value\": \"p\" }",
            1,
        );
        assert!(matches!(
            load_schema_from_str(&json),
            Err(SchemaError::DuplicateMapping { .. })
        ));
    }

    #[test]
    fn rejects_conflicting_special_mapping() {
        let json = XIAOHE_JSON.replacen(
            "\"special_syllables\": [",
            "\"special_syllables\": [\n    { \"code\": \"aa\", \"syllable\": \"ai\", \"initial\": \"\", \"final\": \"ai\" },",
            1,
        );
        assert!(matches!(
            load_schema_from_str(&json),
            Err(SchemaError::ConflictingMapping { .. })
        ));
    }

    #[test]
    fn rejects_invalid_target_syllable() {
        let json = XIAOHE_JSON.replacen(
            "{ \"code\": \"vi\", \"syllable\": \"zhi\", \"initial\": \"zh\", \"final\": \"i\" }",
            "{ \"code\": \"vi\", \"syllable\": \"zzzz\", \"initial\": \"zh\", \"final\": \"i\" }",
            1,
        );
        assert!(matches!(
            load_schema_from_str(&json),
            Err(SchemaError::InvalidSyllable { .. })
        ));
    }

    #[test]
    fn rejects_corrupted_json() {
        assert!(matches!(
            load_schema_from_str("{"),
            Err(SchemaError::InvalidConfig { .. })
        ));
    }

    #[test]
    fn rejects_missing_required_field() {
        assert!(matches!(
            load_schema_from_str("{\"id\":\"x\",\"version\":1}"),
            Err(SchemaError::MissingField { .. })
        ));
    }

    #[test]
    fn rejects_zero_version() {
        let json = XIAOHE_JSON.replace("\"version\": 1", "\"version\": 0");
        assert_eq!(
            load_schema_from_str(&json),
            Err(SchemaError::InvalidVersion { version: 0 })
        );
    }
}
