use std::collections::BTreeSet;
use std::sync::Arc;

use crate::{CodeTableBundle, CodeTableError, CodeTableErrorKind};

pub const CATEGORY_SCHEMA_VERSION: u32 = 1;
pub const MAX_CATEGORY_ID_LEN: usize = 64;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CategoryKind {
    Primary,
    PrimaryEquivalent,
    Extension,
    User,
    Functional,
}

impl CategoryKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Primary => "PRIMARY",
            Self::PrimaryEquivalent => "PRIMARY_EQUIVALENT",
            Self::Extension => "EXTENSION",
            Self::User => "USER",
            Self::Functional => "FUNCTIONAL",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CategoryDefinition {
    pub id: String,
    pub display_name: String,
    pub kind: CategoryKind,
    pub order: u32,
    pub default_enabled: bool,
    pub required: bool,
    pub user_toggleable: bool,
    pub authoritative_file: String,
    pub entry_count: usize,
    pub sha256: [u8; 32],
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CategorySelectionSnapshot {
    schema_version: u32,
    definitions: Arc<[CategoryDefinition]>,
    enabled_category_ids: Vec<String>,
    enabled: BTreeSet<String>,
}

impl CategorySelectionSnapshot {
    pub fn defaults(bundle: &CodeTableBundle) -> Result<Self, CodeTableError> {
        let requested = bundle
            .categories
            .iter()
            .filter(|category| category.default_enabled)
            .map(|category| category.id.clone())
            .collect::<Vec<_>>();
        Self::from_requested(bundle, &requested)
    }

    pub fn from_requested(
        bundle: &CodeTableBundle,
        requested: &[String],
    ) -> Result<Self, CodeTableError> {
        let definitions = bundle
            .categories
            .iter()
            .map(|category| {
                let required = category.id == "core";
                CategoryDefinition {
                    id: category.id.clone(),
                    display_name: category.display_name.clone(),
                    kind: kind_for_id(&category.id),
                    order: category.order,
                    default_enabled: category.default_enabled,
                    required,
                    user_toggleable: !required,
                    authoritative_file: category.binary_file.clone(),
                    entry_count: category.entry_count,
                    sha256: category.binary_sha256,
                }
            })
            .collect::<Vec<_>>();
        let known = definitions
            .iter()
            .map(|definition| definition.id.as_str())
            .collect::<BTreeSet<_>>();
        let mut requested_set = BTreeSet::new();
        for id in requested {
            if id.is_empty()
                || id.len() > MAX_CATEGORY_ID_LEN
                || !id
                    .bytes()
                    .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
            {
                return Err(CodeTableError::for_category(
                    CodeTableErrorKind::MissingCategory,
                    id,
                    "runtime category id is invalid",
                ));
            }
            if !known.contains(id.as_str()) {
                return Err(CodeTableError::for_category(
                    CodeTableErrorKind::MissingCategory,
                    id,
                    "runtime configuration references an unknown category",
                ));
            }
            requested_set.insert(id.as_str());
        }

        let enabled_category_ids = definitions
            .iter()
            .filter(|definition| {
                definition.required || requested_set.contains(definition.id.as_str())
            })
            .map(|definition| definition.id.clone())
            .collect::<Vec<_>>();
        let enabled = enabled_category_ids.iter().cloned().collect();
        Ok(Self {
            schema_version: CATEGORY_SCHEMA_VERSION,
            definitions: definitions.into(),
            enabled_category_ids,
            enabled,
        })
    }

    pub const fn schema_version(&self) -> u32 {
        self.schema_version
    }

    pub fn definitions(&self) -> &[CategoryDefinition] {
        &self.definitions
    }

    pub fn enabled_category_ids(&self) -> &[String] {
        &self.enabled_category_ids
    }

    pub fn is_enabled(&self, id: &str) -> bool {
        self.enabled.contains(id)
    }
}

fn kind_for_id(id: &str) -> CategoryKind {
    match id {
        "core" => CategoryKind::Primary,
        "category-secondary" | "one-key-secondary" | "two-key-secondary" => {
            CategoryKind::PrimaryEquivalent
        }
        _ => CategoryKind::Extension,
    }
}
