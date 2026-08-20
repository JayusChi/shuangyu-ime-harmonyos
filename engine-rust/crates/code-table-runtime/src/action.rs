use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;

use crate::error::{CodeTableError, CodeTableErrorKind};
use crate::json::{self, JsonValue};
use crate::sha256::sha256;

pub const ACTION_TABLE_FORMAT_VERSION: u64 = 1;
pub const MAX_ACTION_ID_LEN: usize = 64;
pub const MAX_ACTION_TEXT_BYTES: usize = 128;
pub const MAX_PAIR_CURSOR_OFFSET_UTF16: u32 = 16;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DateTimeFormatId {
    DateIso,
    DateLocal,
    TimeHm,
    DateTimeLocal,
}

impl DateTimeFormatId {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::DateIso => "DATE_ISO",
            Self::DateLocal => "DATE_LOCAL",
            Self::TimeHm => "TIME_HM",
            Self::DateTimeLocal => "DATETIME_LOCAL",
        }
    }

    fn parse(value: &str) -> Option<Self> {
        match value {
            "DATE_ISO" => Some(Self::DateIso),
            "DATE_LOCAL" => Some(Self::DateLocal),
            "TIME_HM" => Some(Self::TimeHm),
            "DATETIME_LOCAL" => Some(Self::DateTimeLocal),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum FunctionalAction {
    StaticText(String),
    StaticSymbol(String),
    QuickSymbol(String),
    DateTimeText(DateTimeFormatId),
    InsertPair {
        text: String,
        cursor_offset_utf16: u32,
    },
    RepeatCommit,
    UndoCommit,
    MoveLineEnd,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ActionRecord {
    pub id: String,
    pub code: String,
    pub label: String,
    pub source_order: u32,
    pub action: FunctionalAction,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FunctionalActionTable {
    pub fixture_only: bool,
    pub records: Vec<ActionRecord>,
    pub file_sha256: String,
}

impl FunctionalActionTable {
    /// Production actions are deliberately compiled into the trusted runtime.
    /// The source tables contain platform-private `$cmd` expressions; those
    /// expressions remain rejected and are never interpreted at runtime.
    pub fn production_defaults() -> Self {
        let records = vec![
            production_record(
                "undo-commit",
                "i",
                "撤销上屏",
                FunctionalAction::UndoCommit,
                0,
            ),
            production_record(
                "pair-corner",
                "o",
                "「」",
                FunctionalAction::InsertPair {
                    text: "「」".to_owned(),
                    cursor_offset_utf16: 1,
                },
                1,
            ),
            production_record(
                "pair-double-corner",
                "p",
                "『』",
                FunctionalAction::InsertPair {
                    text: "『』".to_owned(),
                    cursor_offset_utf16: 1,
                },
                2,
            ),
            production_record(
                "repeat-commit",
                "f",
                "重复",
                FunctionalAction::RepeatCommit,
                3,
            ),
            production_record(
                "pair-title",
                "h",
                "《》",
                FunctionalAction::InsertPair {
                    text: "《》".to_owned(),
                    cursor_offset_utf16: 1,
                },
                4,
            ),
            production_record(
                "pair-quote",
                "j",
                "“”",
                FunctionalAction::InsertPair {
                    text: "“”".to_owned(),
                    cursor_offset_utf16: 1,
                },
                5,
            ),
            production_record(
                "pair-round-cn",
                "k",
                "（）",
                FunctionalAction::InsertPair {
                    text: "（）".to_owned(),
                    cursor_offset_utf16: 1,
                },
                6,
            ),
            production_record(
                "pair-lenticular",
                "l",
                "〔〕",
                FunctionalAction::InsertPair {
                    text: "〔〕".to_owned(),
                    cursor_offset_utf16: 1,
                },
                7,
            ),
            production_record(
                "move-line-end",
                "n",
                "End",
                FunctionalAction::MoveLineEnd,
                8,
            ),
        ];
        Self {
            fixture_only: false,
            records,
            file_sha256: "built-in-production-actions-v1".to_owned(),
        }
    }

    pub fn load_fixture_file(
        path: impl AsRef<Path>,
        expected_sha256: &str,
    ) -> Result<Self, CodeTableError> {
        let bytes = fs::read(path.as_ref()).map_err(|error| {
            CodeTableError::new(
                CodeTableErrorKind::ResourceMissing,
                format!("action table read failed: {}", error.kind()),
            )
        })?;
        let actual = hex(sha256(&bytes));
        if !valid_hash(expected_sha256) || !actual.eq_ignore_ascii_case(expected_sha256) {
            return Err(action_error(
                CodeTableErrorKind::ChecksumMismatch,
                "action table SHA-256 mismatch",
            ));
        }
        Self::load_fixture_bytes(&bytes, actual)
    }

    pub fn load_fixture_bytes(bytes: &[u8], file_sha256: String) -> Result<Self, CodeTableError> {
        let root = object(
            json::parse(bytes)
                .map_err(|detail| action_error(CodeTableErrorKind::InvalidManifest, detail))?,
        )?;
        reject_unknown(&root, &["formatVersion", "fixtureOnly", "records"])?;
        if number(required(&root, "formatVersion")?, "formatVersion")?
            != ACTION_TABLE_FORMAT_VERSION
        {
            return Err(action_error(
                CodeTableErrorKind::UnsupportedVersion,
                "action table format version is unsupported",
            ));
        }
        if !boolean(required(&root, "fixtureOnly")?, "fixtureOnly")? {
            return Err(action_error(
                CodeTableErrorKind::InvalidManifest,
                "only explicitly fixture-only action data is accepted",
            ));
        }
        let JsonValue::Array(values) = required(&root, "records")? else {
            return Err(field("records", "expected array"));
        };
        let mut ids = BTreeSet::new();
        let mut records = Vec::with_capacity(values.len());
        for (index, value) in values.iter().enumerate() {
            let record = object_ref(value, "records[]")?;
            reject_unknown(
                record,
                &[
                    "id",
                    "code",
                    "label",
                    "type",
                    "text",
                    "formatId",
                    "cursorOffsetUtf16",
                ],
            )?;
            let id = string(required(record, "id")?, "records.id")?.to_owned();
            validate_ascii_id(&id, "records.id")?;
            if !ids.insert(id.clone()) {
                return Err(field("records.id", "duplicate action id"));
            }
            let code = string(required(record, "code")?, "records.code")?.to_owned();
            if code.is_empty()
                || code.len() > lexicon_core::MAX_CODE_LEN
                || !code.bytes().all(|byte| byte.is_ascii_lowercase())
            {
                return Err(field(
                    "records.code",
                    "code must be 1..=64 lowercase ASCII letters",
                ));
            }
            let label = string(required(record, "label")?, "records.label")?.to_owned();
            validate_text(&label, "records.label")?;
            let kind = string(required(record, "type")?, "records.type")?;
            let action = match kind {
                "STATIC_TEXT" => FunctionalAction::StaticText(required_text(record)?),
                "STATIC_SYMBOL" => FunctionalAction::StaticSymbol(required_text(record)?),
                "QUICK_SYMBOL" => FunctionalAction::QuickSymbol(required_text(record)?),
                "DATE_TIME_TEXT" => {
                    reject_present(record, &["text", "cursorOffsetUtf16"])?;
                    let format_id = DateTimeFormatId::parse(string(
                        required(record, "formatId")?,
                        "records.formatId",
                    )?)
                    .ok_or_else(|| field("records.formatId", "unknown date/time format id"))?;
                    FunctionalAction::DateTimeText(format_id)
                }
                "INSERT_PAIR" => {
                    reject_present(record, &["formatId"])?;
                    let text = required_text(record)?;
                    let offset = u32::try_from(number(
                        required(record, "cursorOffsetUtf16")?,
                        "records.cursorOffsetUtf16",
                    )?)
                    .map_err(|_| field("records.cursorOffsetUtf16", "value exceeds u32"))?;
                    let units = text.encode_utf16().count() as u32;
                    if offset == 0 || offset >= units || offset > MAX_PAIR_CURSOR_OFFSET_UTF16 {
                        return Err(field(
                            "records.cursorOffsetUtf16",
                            "pair offset must point strictly inside text and be <= 16 UTF-16 units",
                        ));
                    }
                    FunctionalAction::InsertPair {
                        text,
                        cursor_offset_utf16: offset,
                    }
                }
                "REPEAT_COMMIT" => {
                    reject_present(record, &["text", "formatId", "cursorOffsetUtf16"])?;
                    FunctionalAction::RepeatCommit
                }
                "UNDO_COMMIT" => {
                    reject_present(record, &["text", "formatId", "cursorOffsetUtf16"])?;
                    FunctionalAction::UndoCommit
                }
                "MOVE_LINE_END" => {
                    reject_present(record, &["text", "formatId", "cursorOffsetUtf16"])?;
                    FunctionalAction::MoveLineEnd
                }
                _ => return Err(field("records.type", "unknown or unsafe action type")),
            };
            records.push(ActionRecord {
                id,
                code,
                label,
                source_order: index as u32,
                action,
            });
        }
        Ok(Self {
            fixture_only: true,
            records,
            file_sha256,
        })
    }

    pub fn query_exact_or_prefix(&self, code: &str) -> Vec<&ActionRecord> {
        if code.is_empty() {
            return Vec::new();
        }
        let exact = self.records.iter().any(|record| record.code == code);
        self.records
            .iter()
            .filter(|record| {
                if exact {
                    record.code == code
                } else {
                    record.code.starts_with(code)
                }
            })
            .collect()
    }

    pub fn record(&self, id: &str) -> Option<&ActionRecord> {
        self.records.iter().find(|record| record.id == id)
    }
}

fn production_record(
    id: &str,
    code: &str,
    label: &str,
    action: FunctionalAction,
    source_order: u32,
) -> ActionRecord {
    ActionRecord {
        id: id.to_owned(),
        code: code.to_owned(),
        label: label.to_owned(),
        source_order,
        action,
    }
}

fn required_text(object: &BTreeMap<String, JsonValue>) -> Result<String, CodeTableError> {
    let value = string(required(object, "text")?, "records.text")?.to_owned();
    validate_text(&value, "records.text")?;
    Ok(value)
}

fn validate_text(value: &str, field_name: &'static str) -> Result<(), CodeTableError> {
    let lower = value.to_ascii_lowercase();
    if value.is_empty()
        || value.len() > MAX_ACTION_TEXT_BYTES
        || value.chars().any(char::is_control)
        || [
            "$cmd",
            "$ddcmd",
            "://",
            "www.",
            "ftp",
            "webdav",
            "powershell",
            "cmd.exe",
            "android.intent",
        ]
        .iter()
        .any(|marker| lower.contains(marker))
    {
        return Err(field(
            field_name,
            "text is empty, oversized, controlled, or unsafe",
        ));
    }
    Ok(())
}

fn validate_ascii_id(value: &str, field_name: &'static str) -> Result<(), CodeTableError> {
    if value.is_empty()
        || value.len() > MAX_ACTION_ID_LEN
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
    {
        return Err(field(field_name, "id must be lowercase ASCII/digit/hyphen"));
    }
    Ok(())
}

fn reject_present(
    object: &BTreeMap<String, JsonValue>,
    fields: &[&str],
) -> Result<(), CodeTableError> {
    if fields.iter().any(|field| object.contains_key(*field)) {
        return Err(field(
            "records",
            "action contains parameters for another type",
        ));
    }
    Ok(())
}

fn reject_unknown(
    object: &BTreeMap<String, JsonValue>,
    allowed: &[&str],
) -> Result<(), CodeTableError> {
    if object.keys().any(|key| !allowed.contains(&key.as_str())) {
        return Err(field("actionTable", "unknown or reserved field"));
    }
    Ok(())
}

fn object(value: JsonValue) -> Result<BTreeMap<String, JsonValue>, CodeTableError> {
    match value {
        JsonValue::Object(value) => Ok(value),
        _ => Err(field("actionTable", "expected object")),
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
    value.as_str().ok_or_else(|| field(name, "expected string"))
}

fn number(value: &JsonValue, name: &'static str) -> Result<u64, CodeTableError> {
    value
        .as_u64()
        .ok_or_else(|| field(name, "expected unsigned integer"))
}

fn boolean(value: &JsonValue, name: &'static str) -> Result<bool, CodeTableError> {
    value
        .as_bool()
        .ok_or_else(|| field(name, "expected boolean"))
}

fn valid_hash(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn hex(value: [u8; 32]) -> String {
    use std::fmt::Write;
    let mut output = String::with_capacity(64);
    for byte in value {
        write!(&mut output, "{byte:02x}").expect("String formatting cannot fail");
    }
    output
}

fn field(name: &'static str, detail: &'static str) -> CodeTableError {
    action_error(
        CodeTableErrorKind::InvalidManifest,
        format!("{name}: {detail}"),
    )
}

fn action_error(kind: CodeTableErrorKind, detail: impl Into<String>) -> CodeTableError {
    CodeTableError {
        kind,
        resource: "code-table-action-table",
        category_id: None,
        detail: detail.into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_table() -> Vec<u8> {
        br#"{"formatVersion":1,"fixtureOnly":true,"records":[{"id":"static","code":"a","label":"text","type":"STATIC_TEXT","text":"hello"},{"id":"date","code":"dt","label":"date","type":"DATE_TIME_TEXT","formatId":"DATE_ISO"},{"id":"pair","code":"pp","label":"pair","type":"INSERT_PAIR","text":"()","cursorOffsetUtf16":1}]}"#.to_vec()
    }

    #[test]
    fn loads_closed_action_model_and_preserves_order() {
        let table = FunctionalActionTable::load_fixture_bytes(&valid_table(), "00".repeat(32))
            .expect("valid table");
        assert_eq!(table.records.len(), 3);
        assert_eq!(table.query_exact_or_prefix("d")[0].id, "date");
        assert!(table.query_exact_or_prefix("").is_empty());
    }

    #[test]
    fn production_actions_expose_only_the_approved_direct_codes() {
        let table = FunctionalActionTable::production_defaults();
        assert!(!table.fixture_only);
        assert!(matches!(
            table.query_exact_or_prefix("f")[0].action,
            FunctionalAction::RepeatCommit
        ));
        assert!(matches!(
            table.query_exact_or_prefix("i")[0].action,
            FunctionalAction::UndoCommit
        ));
        assert!(matches!(
            table.query_exact_or_prefix("n")[0].action,
            FunctionalAction::MoveLineEnd
        ));
        assert!(matches!(
            table.query_exact_or_prefix("j")[0].action,
            FunctionalAction::InsertPair { .. }
        ));
        assert!(table.query_exact_or_prefix("x").is_empty());
    }

    #[test]
    fn rejects_unknown_dangerous_and_invalid_pair_actions() {
        for input in [
            br#"{"formatVersion":1,"fixtureOnly":true,"records":[{"id":"x","code":"a","label":"x","type":"SHELL","text":"echo"}]}"#.as_slice(),
            br#"{"formatVersion":1,"fixtureOnly":true,"records":[{"id":"x","code":"a","label":"x","type":"STATIC_TEXT","text":"https://unsafe.invalid"}]}"#.as_slice(),
            br#"{"formatVersion":1,"fixtureOnly":true,"records":[{"id":"x","code":"a","label":"x","type":"INSERT_PAIR","text":"()","cursorOffsetUtf16":9}]}"#.as_slice(),
            br#"{"formatVersion":1,"fixtureOnly":true,"records":[{"id":"x","code":"a","label":"x","type":"STATIC_TEXT","text":"ok","reserved":1}]}"#.as_slice(),
        ] {
            assert!(FunctionalActionTable::load_fixture_bytes(input, "00".repeat(32)).is_err());
        }
    }
}
