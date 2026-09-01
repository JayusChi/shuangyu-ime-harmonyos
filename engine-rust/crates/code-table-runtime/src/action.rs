use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;

use crate::error::{CodeTableError, CodeTableErrorKind};
use crate::json::{self, JsonValue};
use crate::sha256::sha256;

pub const ACTION_TABLE_FORMAT_VERSION: u64 = 1;
pub const MAX_ACTION_ID_LEN: usize = 64;
pub const MAX_ACTION_TEXT_BYTES: usize = 128;
pub const MAX_PRODUCTION_ACTION_TEXT_BYTES: usize = 512;
pub const MAX_PAIR_CURSOR_OFFSET_UTF16: u32 = 16;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DateTimeFormatId {
    DateIso,
    DateLocal,
    DateLocalUnpadded,
    TimeHm,
    TimeHms,
    TimeLocalHms,
    TimeWeekday,
    TimeLocalHm,
    LunarDateFestival,
    DateTimeLocal,
    UnixTimestamp,
}

impl DateTimeFormatId {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::DateIso => "DATE_ISO",
            Self::DateLocal => "DATE_LOCAL",
            Self::DateLocalUnpadded => "DATE_LOCAL_UNPADDED",
            Self::TimeHm => "TIME_HM",
            Self::TimeHms => "TIME_HMS",
            Self::TimeLocalHms => "TIME_LOCAL_HMS",
            Self::TimeWeekday => "TIME_WEEKDAY",
            Self::TimeLocalHm => "TIME_LOCAL_HM",
            Self::LunarDateFestival => "LUNAR_DATE_FESTIVAL",
            Self::DateTimeLocal => "DATETIME_LOCAL",
            Self::UnixTimestamp => "UNIX_TIMESTAMP",
        }
    }

    fn parse(value: &str) -> Option<Self> {
        match value {
            "DATE_ISO" => Some(Self::DateIso),
            "DATE_LOCAL" => Some(Self::DateLocal),
            "DATE_LOCAL_UNPADDED" => Some(Self::DateLocalUnpadded),
            "TIME_HM" => Some(Self::TimeHm),
            "TIME_HMS" => Some(Self::TimeHms),
            "TIME_LOCAL_HMS" => Some(Self::TimeLocalHms),
            "TIME_WEEKDAY" => Some(Self::TimeWeekday),
            "TIME_LOCAL_HM" => Some(Self::TimeLocalHm),
            "LUNAR_DATE_FESTIVAL" => Some(Self::LunarDateFestival),
            "DATETIME_LOCAL" => Some(Self::DateTimeLocal),
            "UNIX_TIMESTAMP" => Some(Self::UnixTimestamp),
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
    DirectControl {
        action: String,
        target: String,
    },
    ImportUserLexicon,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ActionScope {
    /// The action is reached after the semicolon quick-symbol guide.
    Guide,
    /// The action is reached from the ordinary code stream.
    Direct,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ActionRecord {
    pub id: String,
    pub code: String,
    pub label: String,
    pub source_order: u32,
    pub scope: ActionScope,
    pub action: FunctionalAction,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FunctionalActionTable {
    pub fixture_only: bool,
    pub records: Vec<ActionRecord>,
    pub file_sha256: String,
}

impl FunctionalActionTable {
    /// Production guide actions stay in the trusted runtime, while ordinary
    /// direct-action codes, labels, ordering and typed payloads come from the
    /// normalized customer table. The raw platform `$cmd` syntax is converted
    /// offline and is never interpreted here.
    pub fn production_defaults() -> Self {
        let mut records = vec![
            guide_record(
                "symbol-colon-default",
                "_",
                "：",
                FunctionalAction::StaticSymbol("：".to_owned()),
                0,
            ),
            guide_record(
                "symbol-semicolon",
                ";",
                "；",
                FunctionalAction::StaticSymbol("；".to_owned()),
                0,
            ),
            guide_record(
                "symbol-colon-open-quote",
                "q",
                "：“",
                FunctionalAction::StaticSymbol("：“".to_owned()),
                1,
            ),
            guide_record(
                "symbol-question",
                "w",
                "？",
                FunctionalAction::StaticSymbol("？".to_owned()),
                2,
            ),
            guide_record(
                "symbol-open-round",
                "e",
                "（",
                FunctionalAction::StaticSymbol("（".to_owned()),
                3,
            ),
            guide_record(
                "symbol-close-round",
                "r",
                "）",
                FunctionalAction::StaticSymbol("）".to_owned()),
                4,
            ),
            guide_record(
                "literal-tab",
                "t",
                "Tab",
                FunctionalAction::StaticText("\t".to_owned()),
                5,
            ),
            guide_record(
                "symbol-open-title",
                "y",
                "《",
                FunctionalAction::StaticSymbol("《".to_owned()),
                6,
            ),
            guide_record(
                "symbol-close-title",
                "u",
                "》",
                FunctionalAction::StaticSymbol("》".to_owned()),
                7,
            ),
            guide_record(
                "undo-commit",
                "i",
                "[撤销]",
                FunctionalAction::UndoCommit,
                8,
            ),
            guide_record(
                "pair-corner",
                "o",
                "「」",
                FunctionalAction::InsertPair {
                    text: "「」".to_owned(),
                    cursor_offset_utf16: 1,
                },
                9,
            ),
            guide_record(
                "pair-angle",
                "p",
                "〈〉",
                FunctionalAction::InsertPair {
                    text: "〈〉".to_owned(),
                    cursor_offset_utf16: 1,
                },
                10,
            ),
            guide_record(
                "symbol-exclamation",
                "a",
                "！",
                FunctionalAction::StaticSymbol("！".to_owned()),
                11,
            ),
            guide_record(
                "symbol-ellipsis",
                "s",
                "……",
                FunctionalAction::StaticSymbol("……".to_owned()),
                12,
            ),
            guide_record(
                "symbol-pause",
                "d",
                "、",
                FunctionalAction::StaticSymbol("、".to_owned()),
                13,
            ),
            guide_record(
                "repeat-commit",
                "f",
                "重复",
                FunctionalAction::RepeatCommit,
                14,
            ),
            guide_record(
                "symbol-middle-dot",
                "g",
                "·",
                FunctionalAction::StaticSymbol("·".to_owned()),
                15,
            ),
            guide_record(
                "pair-title",
                "h",
                "《》",
                FunctionalAction::InsertPair {
                    text: "《》".to_owned(),
                    cursor_offset_utf16: 1,
                },
                16,
            ),
            guide_record(
                "pair-quote",
                "j",
                "“”",
                FunctionalAction::InsertPair {
                    text: "“”".to_owned(),
                    cursor_offset_utf16: 1,
                },
                17,
            ),
            guide_record(
                "pair-round-cn",
                "k",
                "（）",
                FunctionalAction::InsertPair {
                    text: "（）".to_owned(),
                    cursor_offset_utf16: 1,
                },
                18,
            ),
            guide_record(
                "pair-lenticular",
                "l",
                "〔〕",
                FunctionalAction::InsertPair {
                    text: "〔〕".to_owned(),
                    cursor_offset_utf16: 1,
                },
                19,
            ),
            guide_record(
                "symbol-open-quote",
                "z",
                "“",
                FunctionalAction::StaticSymbol("“".to_owned()),
                20,
            ),
            guide_record(
                "symbol-arrow-right",
                "x",
                "→",
                FunctionalAction::StaticSymbol("→".to_owned()),
                21,
            ),
            guide_record(
                "symbol-close-quote",
                "c",
                "”",
                FunctionalAction::StaticSymbol("”".to_owned()),
                22,
            ),
            guide_record(
                "symbol-em-dash",
                "v",
                "——",
                FunctionalAction::StaticSymbol("——".to_owned()),
                23,
            ),
            guide_record(
                "symbol-ideographic-space",
                "b",
                "⎵",
                FunctionalAction::StaticSymbol("　".to_owned()),
                24,
            ),
            guide_record(
                "move-line-end",
                "n",
                "[End]",
                FunctionalAction::MoveLineEnd,
                25,
            ),
            guide_record(
                "symbol-at",
                "m",
                "@",
                FunctionalAction::StaticSymbol("@".to_owned()),
                26,
            ),
        ];
        let direct_bytes = include_bytes!("../data/production-direct-actions.json");
        let direct_hash = hex(sha256(direct_bytes));
        let direct = Self::load_production_bytes(direct_bytes, direct_hash.clone())
            .expect("generated production direct-action table must be valid");
        records.extend(direct.records);
        Self {
            fixture_only: false,
            records,
            file_sha256: direct_hash,
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
                scope: ActionScope::Guide,
                action,
            });
        }
        Ok(Self {
            fixture_only: true,
            records,
            file_sha256,
        })
    }

    /// Loads the deterministic, offline-normalized direct-action table used by
    /// production. This format contains typed records only: source `$cmd`
    /// expressions are deliberately absent and can never reach runtime.
    pub fn load_production_bytes(
        bytes: &[u8],
        file_sha256: String,
    ) -> Result<Self, CodeTableError> {
        let root = object(
            json::parse(bytes)
                .map_err(|detail| action_error(CodeTableErrorKind::InvalidManifest, detail))?,
        )?;
        reject_unknown(
            &root,
            &[
                "formatVersion",
                "fixtureOnly",
                "source",
                "sourceRecordCount",
                "rejectedRecordCount",
                "records",
            ],
        )?;
        if number(required(&root, "formatVersion")?, "formatVersion")?
            != ACTION_TABLE_FORMAT_VERSION
        {
            return Err(action_error(
                CodeTableErrorKind::UnsupportedVersion,
                "action table format version is unsupported",
            ));
        }
        if boolean(required(&root, "fixtureOnly")?, "fixtureOnly")? {
            return Err(action_error(
                CodeTableErrorKind::InvalidManifest,
                "production action data cannot be fixture-only",
            ));
        }
        let source = string(required(&root, "source")?, "source")?;
        if source.is_empty() || !source.ends_with("5.直通.txt") {
            return Err(field("source", "expected customer direct-table provenance"));
        }
        let source_count = usize::try_from(number(
            required(&root, "sourceRecordCount")?,
            "sourceRecordCount",
        )?)
        .map_err(|_| field("sourceRecordCount", "value exceeds usize"))?;
        let rejected_count = usize::try_from(number(
            required(&root, "rejectedRecordCount")?,
            "rejectedRecordCount",
        )?)
        .map_err(|_| field("rejectedRecordCount", "value exceeds usize"))?;
        let JsonValue::Array(values) = required(&root, "records")? else {
            return Err(field("records", "expected array"));
        };
        if source_count != values.len().saturating_add(rejected_count) {
            return Err(field(
                "sourceRecordCount",
                "accepted and rejected record counts do not cover the source table",
            ));
        }

        let mut ids = BTreeSet::new();
        let mut records = Vec::with_capacity(values.len());
        for (index, value) in values.iter().enumerate() {
            let record = object_ref(value, "records[]")?;
            reject_unknown(
                record,
                &[
                    "id",
                    "scope",
                    "code",
                    "label",
                    "type",
                    "text",
                    "formatId",
                    "cursorOffsetUtf16",
                    "action",
                    "target",
                ],
            )?;
            let id = string(required(record, "id")?, "records.id")?.to_owned();
            validate_ascii_id(&id, "records.id")?;
            if !ids.insert(id.clone()) {
                return Err(field("records.id", "duplicate action id"));
            }
            if string(required(record, "scope")?, "records.scope")? != "DIRECT" {
                return Err(field("records.scope", "production records must use DIRECT"));
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
            validate_production_label(&label)?;
            let kind = string(required(record, "type")?, "records.type")?;
            let action = match kind {
                "STATIC_TEXT" => {
                    reject_present(
                        record,
                        &["formatId", "cursorOffsetUtf16", "action", "target"],
                    )?;
                    let text = string(required(record, "text")?, "records.text")?.to_owned();
                    validate_production_static_text(&text)?;
                    FunctionalAction::StaticText(text)
                }
                "DATE_TIME_TEXT" => {
                    reject_present(record, &["text", "cursorOffsetUtf16", "action", "target"])?;
                    let format_id = DateTimeFormatId::parse(string(
                        required(record, "formatId")?,
                        "records.formatId",
                    )?)
                    .ok_or_else(|| field("records.formatId", "unknown date/time format id"))?;
                    FunctionalAction::DateTimeText(format_id)
                }
                "DIRECT_CONTROL" => {
                    reject_present(record, &["text", "formatId", "cursorOffsetUtf16"])?;
                    let action = string(required(record, "action")?, "records.action")?.to_owned();
                    let target = string(required(record, "target")?, "records.target")?.to_owned();
                    if !trusted_direct_control(&action, &target) {
                        return Err(field(
                            "records.action",
                            "direct-control action/target is not approved",
                        ));
                    }
                    FunctionalAction::DirectControl { action, target }
                }
                "IMPORT_USER_LEXICON" => {
                    reject_present(
                        record,
                        &["text", "formatId", "cursorOffsetUtf16", "action", "target"],
                    )?;
                    FunctionalAction::ImportUserLexicon
                }
                _ => {
                    return Err(field(
                        "records.type",
                        "unknown or unsafe production action type",
                    ))
                }
            };
            records.push(ActionRecord {
                id,
                code,
                label,
                source_order: index as u32,
                scope: ActionScope::Direct,
                action,
            });
        }
        Ok(Self {
            fixture_only: false,
            records,
            file_sha256,
        })
    }

    pub fn query_exact_or_prefix(&self, code: &str) -> Vec<&ActionRecord> {
        self.query_guide_exact_or_prefix(code)
    }

    pub fn query_guide_exact_or_prefix(&self, code: &str) -> Vec<&ActionRecord> {
        self.query_scope_exact_or_prefix(ActionScope::Guide, code)
    }

    pub fn query_direct_exact_or_prefix(&self, code: &str) -> Vec<&ActionRecord> {
        self.query_scope_exact_or_prefix(ActionScope::Direct, code)
    }

    pub fn has_direct_exact(&self, code: &str) -> bool {
        !code.is_empty()
            && self
                .records
                .iter()
                .any(|record| record.scope == ActionScope::Direct && record.code == code)
    }

    pub fn has_direct_continuation(&self, code: &str) -> bool {
        !code.is_empty()
            && self.records.iter().any(|record| {
                record.scope == ActionScope::Direct
                    && record.code.len() > code.len()
                    && record.code.starts_with(code)
            })
    }

    fn query_scope_exact_or_prefix(&self, scope: ActionScope, code: &str) -> Vec<&ActionRecord> {
        if code.is_empty() {
            return Vec::new();
        }
        let exact = self
            .records
            .iter()
            .any(|record| record.scope == scope && record.code == code);
        self.records
            .iter()
            .filter(|record| {
                if record.scope != scope {
                    false
                } else if exact {
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
    scope: ActionScope,
) -> ActionRecord {
    ActionRecord {
        id: id.to_owned(),
        code: code.to_owned(),
        label: label.to_owned(),
        source_order,
        scope,
        action,
    }
}

fn guide_record(
    id: &str,
    code: &str,
    label: &str,
    action: FunctionalAction,
    source_order: u32,
) -> ActionRecord {
    production_record(id, code, label, action, source_order, ActionScope::Guide)
}

fn required_text(object: &BTreeMap<String, JsonValue>) -> Result<String, CodeTableError> {
    let value = string(required(object, "text")?, "records.text")?.to_owned();
    validate_text(&value, "records.text")?;
    Ok(value)
}

fn validate_production_label(value: &str) -> Result<(), CodeTableError> {
    if value.is_empty()
        || value.len() > MAX_ACTION_TEXT_BYTES
        || value.chars().any(char::is_control)
        || value.to_ascii_lowercase().contains("$cmd")
    {
        return Err(field(
            "records.label",
            "label is empty, too long, contains control data, or leaks command syntax",
        ));
    }
    Ok(())
}

fn validate_production_static_text(value: &str) -> Result<(), CodeTableError> {
    let lower = value.to_ascii_lowercase();
    let forbidden_control = value
        .chars()
        .any(|character| character.is_control() && character != '\r' && character != '\n');
    let unsafe_network = lower.contains("://") && value != "https://flypy.cc";
    if value.is_empty()
        || value.len() > MAX_PRODUCTION_ACTION_TEXT_BYTES
        || forbidden_control
        || lower.contains("$cmd")
        || lower.contains("$ddcmd")
        || unsafe_network
    {
        return Err(field(
            "records.text",
            "production static text is empty, too long, or unsafe",
        ));
    }
    Ok(())
}

fn trusted_direct_control(action: &str, target: &str) -> bool {
    match action {
        "category.enable" | "category.disable" => target == "two-key-secondary",
        "category.preset" => matches!(target, "experienced" | "standard" | "beginner"),
        "settings.smart-period" => matches!(target, "0" | "600"),
        "settings.punctuation" | "settings.fullwidth" | "settings.traditional" => {
            target == "toggle"
        }
        "settings.numeric-period" => matches!(target, "enabled" | "disabled"),
        "settings.empty-clear" => matches!(target, "4" | "12"),
        "settings.commit-policy" => matches!(target, "top-screen" | "auto-commit"),
        "url.open" => matches!(target, "flypy-home" | "flypy-help" | "flypy-help-mobile"),
        "app.open" => matches!(target, "settings" | "user-lexicon"),
        "editor.delete-line" => target.is_empty(),
        _ => false,
    }
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
        assert!(matches!(
            table.query_exact_or_prefix("x")[0].action,
            FunctionalAction::StaticSymbol(ref text) if text == "→"
        ));
        assert!(table.query_exact_or_prefix("oba").is_empty());
        assert!(table.query_direct_exact_or_prefix("oba").is_empty());
        assert_eq!(
            table
                .records
                .iter()
                .filter(|record| record.scope == ActionScope::Direct)
                .count(),
            31
        );
        assert_eq!(table.file_sha256.len(), 64);
        assert!(matches!(
            table.query_direct_exact_or_prefix("xhgw")[0].action,
            FunctionalAction::DirectControl { ref action, ref target }
                if action == "url.open" && target == "flypy-home"
        ));
        assert_eq!(
            table.query_direct_exact_or_prefix("xhgw")[0].label,
            "「小鹤官网」"
        );
        assert!(matches!(
            table.query_direct_exact_or_prefix("oui")[0].action,
            FunctionalAction::DirectControl { ref action, ref target }
                if action == "editor.delete-line" && target.is_empty()
        ));
        assert!(table.query_direct_exact_or_prefix("oiz").is_empty());
    }

    #[test]
    fn production_direct_data_rejects_raw_commands_and_unapproved_targets() {
        let cases = [
            r#"{"formatVersion":1,"fixtureOnly":false,"source":"5.直通.txt","sourceRecordCount":1,"rejectedRecordCount":0,"records":[{"id":"x","scope":"DIRECT","code":"abc","label":"x","type":"STATIC_TEXT","text":"$cmd(run(calc))"}]}"#.as_bytes(),
            r#"{"formatVersion":1,"fixtureOnly":false,"source":"5.直通.txt","sourceRecordCount":1,"rejectedRecordCount":0,"records":[{"id":"x","scope":"DIRECT","code":"abc","label":"x","type":"DIRECT_CONTROL","action":"url.open","target":"unapproved"}]}"#.as_bytes(),
            r#"{"formatVersion":1,"fixtureOnly":false,"source":"5.直通.txt","sourceRecordCount":1,"rejectedRecordCount":0,"records":[{"id":"x","scope":"GUIDE","code":"abc","label":"x","type":"IMPORT_USER_LEXICON"}]}"#.as_bytes(),
        ];
        for input in cases {
            assert!(FunctionalActionTable::load_production_bytes(input, "00".repeat(32)).is_err());
        }
    }

    #[test]
    fn production_quick_symbols_match_the_clearwind_kf_map() {
        let table = FunctionalActionTable::production_defaults();
        let expected = [
            ("_", "："),
            (";", "；"),
            ("q", "：“"),
            ("w", "？"),
            ("e", "（"),
            ("r", "）"),
            ("t", "Tab"),
            ("y", "《"),
            ("u", "》"),
            ("i", "[撤销]"),
            ("o", "「」"),
            ("p", "〈〉"),
            ("a", "！"),
            ("s", "……"),
            ("d", "、"),
            ("f", "重复"),
            ("g", "·"),
            ("h", "《》"),
            ("j", "“”"),
            ("k", "（）"),
            ("l", "〔〕"),
            ("z", "“"),
            ("x", "→"),
            ("c", "”"),
            ("v", "——"),
            ("b", "⎵"),
            ("n", "[End]"),
            ("m", "@"),
        ];
        for (code, label) in expected {
            let records = table.query_guide_exact_or_prefix(code);
            assert_eq!(records.len(), 1, "guide code {code}");
            assert_eq!(records[0].label, label, "guide code {code}");
            assert_eq!(records[0].scope, ActionScope::Guide);
        }
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
