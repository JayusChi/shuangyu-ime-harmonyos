use std::collections::{BTreeMap, BTreeSet};

use crate::error::SchemaError;

/// A single-key mapping used by initial sections.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct KeyMapping {
    /// Lowercase ASCII input key.
    pub key: char,
    /// Mapping target, such as `b`, `zh`, or `sh`.
    pub value: String,
}

/// A final mapping. Some shuangpin keys represent multiple finals, and the
/// parser later filters generated syllables through the pinyin inventory.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FinalMapping {
    /// Lowercase ASCII input key.
    pub key: char,
    /// One or more pinyin finals represented by this key.
    pub values: Vec<String>,
}

/// Zero-initial behavior for syllables such as `ai`, `ang`, and `ou`.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ZeroInitialRule {
    /// When true, one-letter finals use a doubled code (`a` -> `aa`).
    pub duplicate_single_letter_finals: bool,
    /// Finals that may be typed directly as their full pinyin spelling.
    pub direct_full_code_finals: Vec<String>,
    /// Finals that use first pinyin letter plus the final's shuangpin key.
    pub first_letter_with_final_key_finals: Vec<String>,
}

/// Explicit syllable-level override used for apical vowels and other special
/// spellings.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SpecialSyllableRule {
    /// Raw shuangpin code.
    pub code: String,
    /// Normalized pinyin syllable.
    pub syllable: String,
    /// Parsed initial part exposed to callers.
    pub initial: String,
    /// Parsed final part exposed to callers.
    pub final_part: String,
}

/// Data model for one shuangpin schema.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ShuangpinSchema {
    /// Stable schema id, such as `xiaohe`.
    pub id: String,
    /// Human-readable schema name.
    pub name: String,
    /// Positive schema format/content version.
    pub version: u32,
    /// Lowercase ASCII keys accepted by the schema.
    pub allowed_input_keys: Vec<char>,
    /// Ordinary single-letter initials.
    pub ordinary_initials: Vec<KeyMapping>,
    /// Double-letter initials represented by one key, such as `zh`.
    pub double_initials: Vec<KeyMapping>,
    /// Final mappings.
    pub finals: Vec<FinalMapping>,
    /// Zero-initial encoding rules.
    pub zero_initial: ZeroInitialRule,
    /// Explicit special syllable rules.
    pub special_syllables: Vec<SpecialSyllableRule>,
    /// Optional schema notes.
    pub description: Option<String>,
}

/// A generated syllable entry available at runtime.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RuntimeSyllable {
    /// Raw shuangpin code.
    pub code: String,
    /// Normalized pinyin syllable.
    pub syllable: String,
    /// Parsed initial part.
    pub initial: String,
    /// Parsed final part.
    pub final_part: String,
    /// Whether this entry came from an explicit special rule.
    pub special_rule: bool,
}

/// Validated runtime index for a shuangpin schema.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RuntimeSchema {
    schema: ShuangpinSchema,
    allowed_keys: BTreeSet<char>,
    initial_by_key: BTreeMap<char, String>,
    finals_by_key: BTreeMap<char, Vec<String>>,
    zero_by_code: BTreeMap<String, RuntimeSyllable>,
    special_by_code: BTreeMap<String, RuntimeSyllable>,
}

impl RuntimeSchema {
    /// Builds a runtime index from a schema that has already passed validation.
    ///
    /// Returns a structured error when the schema cannot produce consistent
    /// runtime lookup tables.
    pub fn new(schema: ShuangpinSchema) -> Result<Self, SchemaError> {
        let allowed_keys = schema.allowed_input_keys.iter().copied().collect();
        let initial_by_key = schema
            .ordinary_initials
            .iter()
            .chain(schema.double_initials.iter())
            .map(|mapping| (mapping.key, mapping.value.clone()))
            .collect();
        let finals_by_key = schema
            .finals
            .iter()
            .map(|mapping| (mapping.key, mapping.values.clone()))
            .collect::<BTreeMap<_, _>>();
        let zero_by_code = build_zero_index(&schema, &finals_by_key)?;
        let special_by_code = schema
            .special_syllables
            .iter()
            .map(|rule| {
                (
                    rule.code.clone(),
                    RuntimeSyllable {
                        code: rule.code.clone(),
                        syllable: rule.syllable.clone(),
                        initial: rule.initial.clone(),
                        final_part: rule.final_part.clone(),
                        special_rule: true,
                    },
                )
            })
            .collect();

        Ok(Self {
            schema,
            allowed_keys,
            initial_by_key,
            finals_by_key,
            zero_by_code,
            special_by_code,
        })
    }

    /// Returns the source schema.
    pub fn schema(&self) -> &ShuangpinSchema {
        &self.schema
    }

    /// Returns true when `key` is accepted by this schema.
    pub fn is_allowed_key(&self, key: char) -> bool {
        self.allowed_keys.contains(&key)
    }

    /// Returns the initial mapped by `key`, if any.
    pub fn initial_for_key(&self, key: char) -> Option<&str> {
        self.initial_by_key.get(&key).map(String::as_str)
    }

    /// Returns all finals mapped by `key`, if any.
    pub fn finals_for_key(&self, key: char) -> Option<&[String]> {
        self.finals_by_key.get(&key).map(Vec::as_slice)
    }

    /// Returns a zero-initial syllable generated for `code`, if any.
    pub fn zero_syllable_for_code(&self, code: &str) -> Option<&RuntimeSyllable> {
        self.zero_by_code.get(code)
    }

    /// Returns a special syllable rule generated for `code`, if any.
    pub fn special_syllable_for_code(&self, code: &str) -> Option<&RuntimeSyllable> {
        self.special_by_code.get(code)
    }
}

fn build_zero_index(
    schema: &ShuangpinSchema,
    finals_by_key: &BTreeMap<char, Vec<String>>,
) -> Result<BTreeMap<String, RuntimeSyllable>, SchemaError> {
    let mut index = BTreeMap::new();

    if schema.zero_initial.duplicate_single_letter_finals {
        for final_part in ["a", "o", "e"] {
            if final_key(final_part, finals_by_key).is_none() {
                return Err(SchemaError::InvalidZeroInitialRule {
                    reason: format!("final not mapped: {final_part}"),
                });
            }
            insert_zero(&mut index, final_part.repeat(2), final_part)?;
        }
    }

    for final_part in &schema.zero_initial.direct_full_code_finals {
        insert_zero(&mut index, final_part.clone(), final_part)?;
    }

    for final_part in &schema.zero_initial.first_letter_with_final_key_finals {
        let first =
            final_part
                .chars()
                .next()
                .ok_or_else(|| SchemaError::InvalidZeroInitialRule {
                    reason: "empty zero-initial final".to_owned(),
                })?;
        let key = final_key(final_part, finals_by_key).ok_or_else(|| {
            SchemaError::InvalidZeroInitialRule {
                reason: format!("final not mapped: {final_part}"),
            }
        })?;
        insert_zero(&mut index, format!("{first}{key}"), final_part)?;
    }

    Ok(index)
}

fn insert_zero(
    index: &mut BTreeMap<String, RuntimeSyllable>,
    code: String,
    final_part: &str,
) -> Result<(), SchemaError> {
    let syllable = final_part.to_owned();
    if let Some(existing) = index.get(&code) {
        if existing.syllable != syllable {
            return Err(SchemaError::ConflictingMapping {
                code,
                first: existing.syllable.clone(),
                second: syllable,
            });
        }
        return Ok(());
    }

    index.insert(
        code.clone(),
        RuntimeSyllable {
            code,
            syllable,
            initial: String::new(),
            final_part: final_part.to_owned(),
            special_rule: false,
        },
    );
    Ok(())
}

fn final_key(final_part: &str, finals_by_key: &BTreeMap<char, Vec<String>>) -> Option<char> {
    finals_by_key.iter().find_map(|(key, finals)| {
        finals
            .iter()
            .any(|candidate| candidate == final_part)
            .then_some(*key)
    })
}
