use std::collections::{BTreeMap, BTreeSet};

use crate::error::{CodeTableError, CodeTableErrorKind};
use crate::json::{self, JsonValue};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CategoryManifest {
    pub id: String,
    pub display_name: String,
    pub source_path: String,
    pub order: u32,
    pub default_enabled: bool,
    pub expected_entry_count: usize,
    pub source_sha256: [u8; 32],
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GuideManifest {
    pub id: String,
    pub expected_entry_count: usize,
    pub source_sha256: [u8; 32],
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BundleManifest {
    pub format_version: u32,
    pub bundle_id: String,
    pub categories: Vec<CategoryManifest>,
    pub guide: GuideManifest,
}

impl BundleManifest {
    pub fn parse(bytes: &[u8]) -> Result<Self, CodeTableError> {
        let root =
            object(json::parse(bytes).map_err(|detail| {
                CodeTableError::new(CodeTableErrorKind::InvalidManifest, detail)
            })?)?;
        let format_version = number(required(&root, "formatVersion")?, "formatVersion")?;
        if format_version != 1 {
            return Err(CodeTableError::new(
                CodeTableErrorKind::UnsupportedVersion,
                "manifest format version is not 1",
            ));
        }
        if !boolean(required(&root, "fixtureOnly")?, "fixtureOnly")? {
            return Err(CodeTableError::new(
                CodeTableErrorKind::InvalidManifest,
                "fixtureOnly must be true",
            ));
        }
        if string(required(&root, "displayName")?, "displayName")? != "码表输入（测试）" {
            return Err(CodeTableError::new(
                CodeTableErrorKind::InvalidManifest,
                "unexpected fixture display name",
            ));
        }
        let bundle_id = string(required(&root, "bundleId")?, "bundleId")?.to_owned();
        let lower = bundle_id.to_ascii_lowercase();
        if !["fixture", "synthetic", "test"]
            .iter()
            .any(|marker| lower.contains(marker))
        {
            return Err(CodeTableError::new(
                CodeTableErrorKind::InvalidManifest,
                "bundle id is not test-only",
            ));
        }

        let JsonValue::Array(category_values) = required(&root, "categories")? else {
            return Err(field("categories", "expected array"));
        };
        if category_values.is_empty() {
            return Err(CodeTableError::new(
                CodeTableErrorKind::EmptyCategories,
                "manifest category list is empty",
            ));
        }
        let mut categories = Vec::with_capacity(category_values.len());
        let mut ids = BTreeSet::new();
        let mut orders = BTreeSet::new();
        for value in category_values {
            let object = object_ref(value, "categories[]")?;
            let id = string(required(object, "id")?, "categories.id")?.to_owned();
            validate_id(&id)?;
            if !ids.insert(id.clone()) {
                return Err(CodeTableError::for_category(
                    CodeTableErrorKind::DuplicateCategoryId,
                    id,
                    "duplicate category id in manifest",
                ));
            }
            let order = u32::try_from(number(required(object, "order")?, "categories.order")?)
                .map_err(|_| field("categories.order", "value exceeds u32"))?;
            if !orders.insert(order) {
                return Err(field("categories.order", "duplicate category order"));
            }
            let count = usize::try_from(number(
                required(object, "expectedEntryCount")?,
                "categories.expectedEntryCount",
            )?)
            .map_err(|_| field("categories.expectedEntryCount", "value exceeds usize"))?;
            if count == 0 {
                return Err(CodeTableError::for_category(
                    CodeTableErrorKind::MissingCategory,
                    &id,
                    "category has zero entries",
                ));
            }
            categories.push(CategoryManifest {
                id,
                display_name: string(required(object, "displayName")?, "categories.displayName")?
                    .to_owned(),
                source_path: string(required(object, "sourcePath")?, "categories.sourcePath")?
                    .to_owned(),
                order,
                default_enabled: boolean(
                    required(object, "defaultEnabled")?,
                    "categories.defaultEnabled",
                )?,
                expected_entry_count: count,
                source_sha256: hash(
                    string(required(object, "sourceSha256")?, "categories.sourceSha256")?,
                    "categories.sourceSha256",
                )?,
            });
        }
        categories.sort_by_key(|category| category.order);

        let guide_object = object_ref(required(&root, "guideTable")?, "guideTable")?;
        let guide_id = string(required(guide_object, "id")?, "guideTable.id")?.to_owned();
        validate_id(&guide_id)?;
        if ids.contains(&guide_id) {
            return Err(CodeTableError::for_category(
                CodeTableErrorKind::DuplicateCategoryId,
                guide_id,
                "guide id duplicates a category id",
            ));
        }
        let guide_count = usize::try_from(number(
            required(guide_object, "expectedEntryCount")?,
            "guideTable.expectedEntryCount",
        )?)
        .map_err(|_| field("guideTable.expectedEntryCount", "value exceeds usize"))?;
        if guide_count == 0 {
            return Err(field(
                "guideTable.expectedEntryCount",
                "guide table is empty",
            ));
        }

        Ok(Self {
            format_version: format_version as u32,
            bundle_id,
            categories,
            guide: GuideManifest {
                id: guide_id,
                expected_entry_count: guide_count,
                source_sha256: hash(
                    string(
                        required(guide_object, "sourceSha256")?,
                        "guideTable.sourceSha256",
                    )?,
                    "guideTable.sourceSha256",
                )?,
            },
        })
    }
}

fn object(value: JsonValue) -> Result<BTreeMap<String, JsonValue>, CodeTableError> {
    match value {
        JsonValue::Object(value) => Ok(value),
        _ => Err(field("manifest", "expected object")),
    }
}

fn object_ref<'a>(
    value: &'a JsonValue,
    name: &'static str,
) -> Result<&'a BTreeMap<String, JsonValue>, CodeTableError> {
    match value {
        JsonValue::Object(value) => Ok(value),
        _ => Err(field(name, "expected object")),
    }
}

fn required<'a>(
    object: &'a BTreeMap<String, JsonValue>,
    key: &'static str,
) -> Result<&'a JsonValue, CodeTableError> {
    object.get(key).ok_or_else(|| field(key, "missing field"))
}

fn string<'a>(value: &'a JsonValue, name: &'static str) -> Result<&'a str, CodeTableError> {
    match value {
        JsonValue::String(value) => Ok(value),
        _ => Err(field(name, "expected string")),
    }
}

fn number(value: &JsonValue, name: &'static str) -> Result<u64, CodeTableError> {
    match value {
        JsonValue::Number(value) => Ok(*value),
        _ => Err(field(name, "expected unsigned integer")),
    }
}

fn boolean(value: &JsonValue, name: &'static str) -> Result<bool, CodeTableError> {
    match value {
        JsonValue::Bool(value) => Ok(*value),
        _ => Err(field(name, "expected boolean")),
    }
}

fn validate_id(value: &str) -> Result<(), CodeTableError> {
    if value.is_empty()
        || value.len() > 64
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
    {
        return Err(field("id", "id must be lowercase ASCII/digit/hyphen"));
    }
    Ok(())
}

fn hash(value: &str, name: &'static str) -> Result<[u8; 32], CodeTableError> {
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(field(name, "expected 64 hexadecimal characters"));
    }
    let mut output = [0_u8; 32];
    for (index, slot) in output.iter_mut().enumerate() {
        *slot = u8::from_str_radix(&value[index * 2..index * 2 + 2], 16)
            .map_err(|_| field(name, "invalid hexadecimal checksum"))?;
    }
    Ok(output)
}

fn field(name: &'static str, detail: &'static str) -> CodeTableError {
    CodeTableError::new(
        CodeTableErrorKind::InvalidManifest,
        format!("{name}: {detail}"),
    )
}
