use std::collections::{BTreeMap, BTreeSet};

use pinyin_syllable::is_valid_syllable;

use crate::error::SchemaError;
use crate::model::{FinalMapping, KeyMapping, RuntimeSchema, ShuangpinSchema, SpecialSyllableRule};

/// Validates a shuangpin schema and returns its generated runtime index.
///
/// The validator checks identity fields, mapping key legality, duplicate
/// mappings, special syllable targets, zero-initial rules, and runtime index
/// generation.
pub fn validate_schema(schema: ShuangpinSchema) -> Result<RuntimeSchema, SchemaError> {
    validate_identity(&schema)?;
    let allowed = validate_allowed_keys(&schema.allowed_input_keys)?;
    validate_initials("ordinary_initials", &schema.ordinary_initials, &allowed)?;
    validate_initials("double_initials", &schema.double_initials, &allowed)?;
    validate_finals(&schema.finals, &allowed)?;
    validate_zero_initial(&schema)?;
    validate_special_rules(&schema.special_syllables, &allowed)?;

    let runtime = RuntimeSchema::new(schema)?;
    validate_special_conflicts(&runtime)?;
    Ok(runtime)
}

fn validate_identity(schema: &ShuangpinSchema) -> Result<(), SchemaError> {
    if schema.id.trim().is_empty() {
        return Err(SchemaError::EmptyId);
    }
    if schema.name.trim().is_empty() {
        return Err(SchemaError::EmptyName);
    }
    if schema.version == 0 {
        return Err(SchemaError::InvalidVersion { version: 0 });
    }
    Ok(())
}

fn validate_allowed_keys(keys: &[char]) -> Result<BTreeSet<char>, SchemaError> {
    let mut seen = BTreeSet::new();
    for key in keys {
        if !is_valid_key(*key) {
            return Err(SchemaError::InvalidKey {
                section: "allowed_input_keys".to_owned(),
                key: key.to_string(),
            });
        }
        if !seen.insert(*key) {
            return Err(SchemaError::DuplicateMapping {
                section: "allowed_input_keys".to_owned(),
                key: key.to_string(),
            });
        }
    }
    Ok(seen)
}

fn validate_initials(
    section: &str,
    mappings: &[KeyMapping],
    allowed: &BTreeSet<char>,
) -> Result<(), SchemaError> {
    let mut seen = BTreeMap::new();
    for mapping in mappings {
        validate_key(section, mapping.key, allowed)?;
        if mapping.value.is_empty() {
            return Err(SchemaError::EmptyMappingTarget {
                section: section.to_owned(),
                key: mapping.key.to_string(),
            });
        }
        if seen.insert(mapping.key, mapping.value.clone()).is_some() {
            return Err(SchemaError::DuplicateMapping {
                section: section.to_owned(),
                key: mapping.key.to_string(),
            });
        }
    }
    Ok(())
}

fn validate_finals(mappings: &[FinalMapping], allowed: &BTreeSet<char>) -> Result<(), SchemaError> {
    let mut seen_keys = BTreeSet::new();
    for mapping in mappings {
        validate_key("finals", mapping.key, allowed)?;
        if !seen_keys.insert(mapping.key) {
            return Err(SchemaError::DuplicateMapping {
                section: "finals".to_owned(),
                key: mapping.key.to_string(),
            });
        }
        let mut seen_values = BTreeSet::new();
        for value in &mapping.values {
            if value.is_empty() {
                return Err(SchemaError::EmptyMappingTarget {
                    section: "finals".to_owned(),
                    key: mapping.key.to_string(),
                });
            }
            if !seen_values.insert(value) {
                return Err(SchemaError::DuplicateMapping {
                    section: "finals".to_owned(),
                    key: format!("{}:{value}", mapping.key),
                });
            }
        }
    }
    Ok(())
}

fn validate_zero_initial(schema: &ShuangpinSchema) -> Result<(), SchemaError> {
    let all_finals = schema
        .finals
        .iter()
        .flat_map(|mapping| mapping.values.iter())
        .collect::<BTreeSet<_>>();

    let rule = &schema.zero_initial;
    if !rule.duplicate_single_letter_finals
        && rule.direct_full_code_finals.is_empty()
        && rule.first_letter_with_final_key_finals.is_empty()
    {
        return Err(SchemaError::InvalidZeroInitialRule {
            reason: "no zero-initial behavior declared".to_owned(),
        });
    }

    for final_part in rule
        .direct_full_code_finals
        .iter()
        .chain(rule.first_letter_with_final_key_finals.iter())
    {
        if !all_finals.contains(final_part) {
            return Err(SchemaError::InvalidZeroInitialRule {
                reason: format!("final not mapped: {final_part}"),
            });
        }
        if !is_valid_syllable(final_part) {
            return Err(SchemaError::InvalidSyllable {
                syllable: final_part.clone(),
            });
        }
    }
    Ok(())
}

fn validate_special_rules(
    rules: &[SpecialSyllableRule],
    allowed: &BTreeSet<char>,
) -> Result<(), SchemaError> {
    let mut seen = BTreeSet::new();
    for rule in rules {
        if rule.code.is_empty() {
            return Err(SchemaError::InvalidConfig {
                reason: "special rule code is empty".to_owned(),
            });
        }
        for key in rule.code.chars() {
            validate_key("special_syllables", key, allowed)?;
        }
        if !seen.insert(&rule.code) {
            return Err(SchemaError::DuplicateMapping {
                section: "special_syllables".to_owned(),
                key: rule.code.clone(),
            });
        }
        if !is_valid_syllable(&rule.syllable) {
            return Err(SchemaError::InvalidSyllable {
                syllable: rule.syllable.clone(),
            });
        }
    }
    Ok(())
}

fn validate_special_conflicts(runtime: &RuntimeSchema) -> Result<(), SchemaError> {
    for rule in &runtime.schema().special_syllables {
        if let Some(zero) = runtime.zero_syllable_for_code(&rule.code) {
            if zero.syllable != rule.syllable {
                return Err(SchemaError::ConflictingMapping {
                    code: rule.code.clone(),
                    first: zero.syllable.clone(),
                    second: rule.syllable.clone(),
                });
            }
        }
    }
    Ok(())
}

fn validate_key(section: &str, key: char, allowed: &BTreeSet<char>) -> Result<(), SchemaError> {
    if !is_valid_key(key) || !allowed.contains(&key) {
        return Err(SchemaError::InvalidKey {
            section: section.to_owned(),
            key: key.to_string(),
        });
    }
    Ok(())
}

fn is_valid_key(key: char) -> bool {
    key.is_ascii_lowercase()
}
