use std::collections::{BTreeMap, BTreeSet};
use std::path::{Component, Path};

use crate::error::FixtureError;
use crate::json::{self, JsonValue};

pub const MANIFEST_FORMAT_VERSION: u32 = 1;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CategoryManifest {
    pub id: String,
    pub display_name: String,
    pub source_path: String,
    pub order: u32,
    pub default_enabled: bool,
    pub expected_entry_count: usize,
    pub source_sha256: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GuideManifest {
    pub id: String,
    pub source_path: String,
    pub expected_entry_count: usize,
    pub source_sha256: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FixtureManifest {
    pub format_version: u32,
    pub bundle_id: String,
    pub display_name: String,
    pub fixture_only: bool,
    pub categories: Vec<CategoryManifest>,
    pub guide_table: GuideManifest,
}

impl FixtureManifest {
    pub fn from_bytes(bytes: &[u8], file: &str) -> Result<Self, FixtureError> {
        let value = json::parse(bytes).map_err(|reason| {
            FixtureError::diagnostic("CTF_MANIFEST_JSON", file, 0, "manifest", reason)
        })?;
        let root = object(value, file, "manifest")?;
        let categories = array(required(&root, "categories", file)?, file, "categories")?
            .into_iter()
            .enumerate()
            .map(|(index, value)| parse_category(value, file, index))
            .collect::<Result<Vec<_>, _>>()?;
        let guide = parse_guide(required(&root, "guideTable", file)?.clone(), file)?;
        let manifest = Self {
            format_version: number(
                required(&root, "formatVersion", file)?,
                file,
                "formatVersion",
            )?
            .try_into()
            .map_err(|_| field_error(file, "formatVersion", "value exceeds u32"))?,
            bundle_id: string(required(&root, "bundleId", file)?, file, "bundleId")?,
            display_name: string(required(&root, "displayName", file)?, file, "displayName")?,
            fixture_only: boolean(required(&root, "fixtureOnly", file)?, file, "fixtureOnly")?,
            categories,
            guide_table: guide,
        };
        manifest.validate(file)?;
        Ok(manifest)
    }

    pub fn to_json_bytes(&self) -> Vec<u8> {
        let mut output = String::new();
        output.push_str("{\n");
        output.push_str(&format!("  \"formatVersion\": {},\n", self.format_version));
        output.push_str(&format!(
            "  \"bundleId\": {},\n",
            json::quote(&self.bundle_id)
        ));
        output.push_str(&format!(
            "  \"displayName\": {},\n",
            json::quote(&self.display_name)
        ));
        output.push_str(&format!("  \"fixtureOnly\": {},\n", self.fixture_only));
        output.push_str("  \"categories\": [\n");
        for (index, category) in self.categories.iter().enumerate() {
            output.push_str("    {\n");
            output.push_str(&format!("      \"id\": {},\n", json::quote(&category.id)));
            output.push_str(&format!(
                "      \"displayName\": {},\n",
                json::quote(&category.display_name)
            ));
            output.push_str(&format!(
                "      \"sourcePath\": {},\n",
                json::quote(&category.source_path)
            ));
            output.push_str(&format!("      \"order\": {},\n", category.order));
            output.push_str(&format!(
                "      \"defaultEnabled\": {},\n",
                category.default_enabled
            ));
            output.push_str(&format!(
                "      \"expectedEntryCount\": {},\n",
                category.expected_entry_count
            ));
            output.push_str(&format!(
                "      \"sourceSha256\": {}\n",
                json::quote(&category.source_sha256)
            ));
            output.push_str(if index + 1 == self.categories.len() {
                "    }\n"
            } else {
                "    },\n"
            });
        }
        output.push_str("  ],\n");
        output.push_str("  \"guideTable\": {\n");
        output.push_str(&format!(
            "    \"id\": {},\n",
            json::quote(&self.guide_table.id)
        ));
        output.push_str(&format!(
            "    \"sourcePath\": {},\n",
            json::quote(&self.guide_table.source_path)
        ));
        output.push_str(&format!(
            "    \"expectedEntryCount\": {},\n",
            self.guide_table.expected_entry_count
        ));
        output.push_str(&format!(
            "    \"sourceSha256\": {}\n",
            json::quote(&self.guide_table.source_sha256)
        ));
        output.push_str("  }\n}\n");
        output.into_bytes()
    }

    pub fn validate(&self, file: &str) -> Result<(), FixtureError> {
        if self.format_version != MANIFEST_FORMAT_VERSION {
            return Err(field_error(
                file,
                "formatVersion",
                "unsupported manifest format version",
            ));
        }
        if !self.fixture_only {
            return Err(FixtureError::diagnostic(
                "CTF_MANIFEST_NOT_FIXTURE",
                file,
                0,
                "fixtureOnly",
                "fixtureOnly must be true",
            ));
        }
        let bundle_id = self.bundle_id.to_ascii_lowercase();
        if !["fixture", "test", "synthetic"]
            .iter()
            .any(|marker| bundle_id.contains(marker))
        {
            return Err(FixtureError::diagnostic(
                "CTF_BUNDLE_ID_UNSAFE",
                file,
                0,
                "bundleId",
                "bundle id must contain a test-only marker",
            ));
        }
        if self.display_name != "码表输入（测试）" {
            return Err(field_error(
                file,
                "displayName",
                "fixture display name must remain 码表输入（测试）",
            ));
        }
        if self.categories.is_empty() {
            return Err(field_error(
                file,
                "categories",
                "at least one category is required",
            ));
        }

        let mut ids = BTreeSet::new();
        let mut orders = BTreeSet::new();
        let mut paths = BTreeSet::new();
        for category in &self.categories {
            validate_id(&category.id, file, "categories.id")?;
            if category.id == "guide" {
                return Err(FixtureError::diagnostic(
                    "CTF_GUIDE_IN_CATEGORIES",
                    file,
                    0,
                    "categories.id",
                    "guide table cannot be a normal category",
                ));
            }
            if !ids.insert(category.id.clone()) {
                return Err(FixtureError::diagnostic(
                    "CTF_CATEGORY_ID_DUPLICATE",
                    file,
                    0,
                    "categories.id",
                    "category id is duplicated",
                ));
            }
            if !orders.insert(category.order) {
                return Err(FixtureError::diagnostic(
                    "CTF_CATEGORY_ORDER_DUPLICATE",
                    file,
                    0,
                    "categories.order",
                    "category order is duplicated",
                ));
            }
            validate_source_path(&category.source_path, file, "categories.sourcePath")?;
            if !paths.insert(category.source_path.clone()) {
                return Err(field_error(
                    file,
                    "categories.sourcePath",
                    "source path is reused",
                ));
            }
            validate_count(
                category.expected_entry_count,
                file,
                "categories.expectedEntryCount",
            )?;
            validate_hash(&category.source_sha256, file, "categories.sourceSha256")?;
        }

        if self.guide_table.id != "guide" {
            return Err(FixtureError::diagnostic(
                "CTF_NORMAL_TABLE_AS_GUIDE",
                file,
                0,
                "guideTable.id",
                "guideTable id must be guide",
            ));
        }
        validate_source_path(&self.guide_table.source_path, file, "guideTable.sourcePath")?;
        if !paths.insert(self.guide_table.source_path.clone()) {
            return Err(FixtureError::diagnostic(
                "CTF_GUIDE_IN_CATEGORIES",
                file,
                0,
                "guideTable.sourcePath",
                "guide source is also used by a normal category",
            ));
        }
        validate_count(
            self.guide_table.expected_entry_count,
            file,
            "guideTable.expectedEntryCount",
        )?;
        validate_hash(
            &self.guide_table.source_sha256,
            file,
            "guideTable.sourceSha256",
        )?;
        Ok(())
    }
}

fn parse_category(
    value: JsonValue,
    file: &str,
    _index: usize,
) -> Result<CategoryManifest, FixtureError> {
    let value = object(value, file, "categories")?;
    Ok(CategoryManifest {
        id: string(required(&value, "id", file)?, file, "categories.id")?,
        display_name: string(
            required(&value, "displayName", file)?,
            file,
            "categories.displayName",
        )?,
        source_path: string(
            required(&value, "sourcePath", file)?,
            file,
            "categories.sourcePath",
        )?,
        order: number(required(&value, "order", file)?, file, "categories.order")?
            .try_into()
            .map_err(|_| field_error(file, "categories.order", "value exceeds u32"))?,
        default_enabled: boolean(
            required(&value, "defaultEnabled", file)?,
            file,
            "categories.defaultEnabled",
        )?,
        expected_entry_count: number(
            required(&value, "expectedEntryCount", file)?,
            file,
            "categories.expectedEntryCount",
        )?
        .try_into()
        .map_err(|_| field_error(file, "categories.expectedEntryCount", "value exceeds usize"))?,
        source_sha256: string(
            required(&value, "sourceSha256", file)?,
            file,
            "categories.sourceSha256",
        )?,
    })
}

fn parse_guide(value: JsonValue, file: &str) -> Result<GuideManifest, FixtureError> {
    let value = object(value, file, "guideTable")?;
    Ok(GuideManifest {
        id: string(required(&value, "id", file)?, file, "guideTable.id")?,
        source_path: string(
            required(&value, "sourcePath", file)?,
            file,
            "guideTable.sourcePath",
        )?,
        expected_entry_count: number(
            required(&value, "expectedEntryCount", file)?,
            file,
            "guideTable.expectedEntryCount",
        )?
        .try_into()
        .map_err(|_| field_error(file, "guideTable.expectedEntryCount", "value exceeds usize"))?,
        source_sha256: string(
            required(&value, "sourceSha256", file)?,
            file,
            "guideTable.sourceSha256",
        )?,
    })
}

fn required<'a>(
    object: &'a BTreeMap<String, JsonValue>,
    key: &str,
    file: &str,
) -> Result<&'a JsonValue, FixtureError> {
    object
        .get(key)
        .ok_or_else(|| field_error(file, "manifest", format!("missing required field {key}")))
}

fn object(
    value: JsonValue,
    file: &str,
    field: &'static str,
) -> Result<BTreeMap<String, JsonValue>, FixtureError> {
    match value {
        JsonValue::Object(value) => Ok(value),
        _ => Err(field_error(file, field, "expected object")),
    }
}

fn array(
    value: &JsonValue,
    file: &str,
    field: &'static str,
) -> Result<Vec<JsonValue>, FixtureError> {
    match value {
        JsonValue::Array(value) => Ok(value.clone()),
        _ => Err(field_error(file, field, "expected array")),
    }
}

fn string(value: &JsonValue, file: &str, field: &'static str) -> Result<String, FixtureError> {
    match value {
        JsonValue::String(value) => Ok(value.clone()),
        _ => Err(field_error(file, field, "expected string")),
    }
}

fn number(value: &JsonValue, file: &str, field: &'static str) -> Result<u64, FixtureError> {
    match value {
        JsonValue::Number(value) => Ok(*value),
        _ => Err(field_error(file, field, "expected non-negative integer")),
    }
}

fn boolean(value: &JsonValue, file: &str, field: &'static str) -> Result<bool, FixtureError> {
    match value {
        JsonValue::Bool(value) => Ok(*value),
        _ => Err(field_error(file, field, "expected boolean")),
    }
}

fn validate_id(value: &str, file: &str, field: &'static str) -> Result<(), FixtureError> {
    if value.is_empty()
        || !value
            .bytes()
            .all(|value| value.is_ascii_lowercase() || value.is_ascii_digit() || value == b'-')
    {
        return Err(field_error(
            file,
            field,
            "id must use lowercase ASCII, digits, or hyphen",
        ));
    }
    Ok(())
}

fn validate_source_path(value: &str, file: &str, field: &'static str) -> Result<(), FixtureError> {
    let path = Path::new(value);
    if path.is_absolute() || value.contains(':') {
        return Err(FixtureError::diagnostic(
            "CTF_PATH_ABSOLUTE",
            file,
            0,
            field,
            "absolute source paths are forbidden",
        ));
    }
    if value.contains('\\') {
        return Err(FixtureError::diagnostic(
            "CTF_PATH_NON_PORTABLE",
            file,
            0,
            field,
            "manifest paths must use forward slashes",
        ));
    }
    if path.components().any(|value| {
        matches!(
            value,
            Component::ParentDir | Component::RootDir | Component::Prefix(_)
        )
    }) {
        return Err(FixtureError::diagnostic(
            "CTF_PATH_TRAVERSAL",
            file,
            0,
            field,
            "source path escapes the manifest root",
        ));
    }
    if value.is_empty() {
        return Err(field_error(file, field, "source path must not be empty"));
    }
    Ok(())
}

fn validate_count(value: usize, file: &str, field: &'static str) -> Result<(), FixtureError> {
    if value == 0 {
        return Err(field_error(file, field, "expected count must be positive"));
    }
    Ok(())
}

fn validate_hash(value: &str, file: &str, field: &'static str) -> Result<(), FixtureError> {
    if value.len() != 64 || !value.bytes().all(|value| value.is_ascii_hexdigit()) {
        return Err(field_error(
            file,
            field,
            "SHA-256 must contain exactly 64 hex digits",
        ));
    }
    Ok(())
}

fn field_error(file: &str, field: &'static str, reason: impl Into<String>) -> FixtureError {
    FixtureError::diagnostic("CTF_MANIFEST_FIELD", file, 0, field, reason)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Diagnostic;

    fn sample() -> FixtureManifest {
        FixtureManifest {
            format_version: 1,
            bundle_id: "code-table-fixture-synthetic-v1".into(),
            display_name: "码表输入（测试）".into(),
            fixture_only: true,
            categories: vec![CategoryManifest {
                id: "core".into(),
                display_name: "核心测试".into(),
                source_path: "source/core.txt".into(),
                order: 10,
                default_enabled: true,
                expected_entry_count: 1,
                source_sha256: "0".repeat(64),
            }],
            guide_table: GuideManifest {
                id: "guide".into(),
                source_path: "source/guide.txt".into(),
                expected_entry_count: 1,
                source_sha256: "1".repeat(64),
            },
        }
    }

    #[test]
    fn canonical_json_round_trips() {
        let expected = sample();
        let actual =
            FixtureManifest::from_bytes(&expected.to_json_bytes(), "manifest.json").unwrap();
        assert_eq!(actual, expected);
    }

    #[test]
    fn rejects_duplicate_ids_orders_and_unsafe_paths() {
        let mut value = sample();
        value.categories.push(value.categories[0].clone());
        assert!(matches!(
            value.validate("manifest.json"),
            Err(FixtureError::Diagnostic(Diagnostic {
                code: "CTF_CATEGORY_ID_DUPLICATE",
                ..
            }))
        ));

        let mut value = sample();
        value.categories[0].source_path = "../escape.txt".into();
        assert!(matches!(
            value.validate("manifest.json"),
            Err(FixtureError::Diagnostic(Diagnostic {
                code: "CTF_PATH_TRAVERSAL",
                ..
            }))
        ));

        let mut value = sample();
        let mut second = value.categories[0].clone();
        second.id = "phrases".into();
        second.source_path = "source/phrases.txt".into();
        value.categories.push(second);
        assert!(matches!(
            value.validate("manifest.json"),
            Err(FixtureError::Diagnostic(Diagnostic {
                code: "CTF_CATEGORY_ORDER_DUPLICATE",
                ..
            }))
        ));

        let mut value = sample();
        value.categories[0].source_path = "C:/absolute.txt".into();
        assert!(matches!(
            value.validate("manifest.json"),
            Err(FixtureError::Diagnostic(Diagnostic {
                code: "CTF_PATH_ABSOLUTE",
                ..
            }))
        ));

        let mut value = sample();
        value.categories[0].id = "guide".into();
        assert!(matches!(
            value.validate("manifest.json"),
            Err(FixtureError::Diagnostic(Diagnostic {
                code: "CTF_GUIDE_IN_CATEGORIES",
                ..
            }))
        ));

        let mut value = sample();
        value.guide_table.id = "core".into();
        assert!(matches!(
            value.validate("manifest.json"),
            Err(FixtureError::Diagnostic(Diagnostic {
                code: "CTF_NORMAL_TABLE_AS_GUIDE",
                ..
            }))
        ));

        let mut value = sample();
        value.guide_table.source_path = value.categories[0].source_path.clone();
        assert!(matches!(
            value.validate("manifest.json"),
            Err(FixtureError::Diagnostic(Diagnostic {
                code: "CTF_GUIDE_IN_CATEGORIES",
                ..
            }))
        ));
    }
}
