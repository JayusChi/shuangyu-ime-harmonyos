use std::path::{Path, PathBuf};

use lexicon_core::{validate_code, validate_word, CodeValidationError, WordValidationError};

use crate::error::{UserLexiconError, UserLexiconField, UserLexiconReason};
use crate::model::{UserLexiconAction, UserLexiconEntry};
use crate::snapshot::UserLexiconSnapshot;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ParsedUserLexicon {
    pub entries: Vec<UserLexiconEntry>,
    pub accepted_rows: usize,
}

impl ParsedUserLexicon {
    pub fn into_snapshot(self) -> UserLexiconSnapshot {
        UserLexiconSnapshot::from_entries(self.entries, self.accepted_rows)
    }
}

pub fn parse_user_lexicon_file(path: &Path) -> Result<ParsedUserLexicon, UserLexiconError> {
    let bytes = std::fs::read(path).map_err(|error| {
        UserLexiconError::new(
            path,
            0,
            UserLexiconField::File,
            UserLexiconReason::Io(error.kind().to_string()),
        )
    })?;
    parse_user_lexicon_bytes(path, &bytes)
}

pub fn parse_user_lexicon_bytes(
    path: impl Into<PathBuf>,
    bytes: &[u8],
) -> Result<ParsedUserLexicon, UserLexiconError> {
    parse_user_lexicon_bytes_with_profile(path, bytes, false)
}

/// Parses the bundle-owned rule layer. Its four-field extension carries a
/// candidate-only label and the owning system category; the public format
/// remains two TAB-separated fields, including user-managed `#直` rows.
pub fn parse_embedded_user_lexicon_bytes(
    path: impl Into<PathBuf>,
    bytes: &[u8],
) -> Result<ParsedUserLexicon, UserLexiconError> {
    parse_user_lexicon_bytes_with_profile(path, bytes, true)
}

fn parse_user_lexicon_bytes_with_profile(
    path: impl Into<PathBuf>,
    bytes: &[u8],
    allow_embedded_metadata: bool,
) -> Result<ParsedUserLexicon, UserLexiconError> {
    let path = path.into();
    let text = std::str::from_utf8(bytes).map_err(|_| {
        UserLexiconError::new(
            path.clone(),
            0,
            UserLexiconField::File,
            UserLexiconReason::InvalidUtf8,
        )
    })?;
    let mut entries = Vec::new();
    let mut next_source_order = 0_u32;

    for (index, raw_line) in text.split('\n').enumerate() {
        let line_number = index + 1;
        let mut line = raw_line.strip_suffix('\r').unwrap_or(raw_line);
        if index == 0 {
            line = line.strip_prefix('\u{feff}').unwrap_or(line);
        }
        if line.trim().is_empty() {
            continue;
        }
        let fields = line.split('\t').collect::<Vec<_>>();
        if fields.len() != 2 && fields.len() != 3 && !(allow_embedded_metadata && fields.len() == 4)
        {
            return Err(error(
                &path,
                line_number,
                UserLexiconField::Fields,
                UserLexiconReason::FieldCount {
                    actual: fields.len(),
                },
            ));
        }
        let (code, action) = parse_code_and_action(&path, line_number, fields[1])?;
        if fields.len() == 3 && action.external_action().is_none() {
            return Err(error(
                &path,
                line_number,
                UserLexiconField::Fields,
                UserLexiconReason::FieldCount {
                    actual: fields.len(),
                },
            ));
        }
        let (text, inline_display_text) = if matches!(action, UserLexiconAction::Direct) {
            parse_direct_word_and_display(&path, line_number, fields[0])?
        } else {
            (fields[0], None)
        };
        if let Some(external_action) = action.external_action() {
            if !crate::valid_shortcut_target(external_action, text) {
                return Err(error(
                    &path,
                    line_number,
                    UserLexiconField::Word,
                    UserLexiconReason::InvalidPath,
                ));
            }
        } else {
            validate_word(text).map_err(|reason| {
                let reason = match reason {
                    WordValidationError::Empty => UserLexiconReason::EmptyWord,
                    WordValidationError::TooLong { actual, max } => {
                        UserLexiconReason::WordTooLong { actual, max }
                    }
                    WordValidationError::UnsupportedCharacter(ch) => {
                        UserLexiconReason::UnsupportedWordCharacter {
                            codepoint: ch as u32,
                        }
                    }
                };
                error(&path, line_number, UserLexiconField::Word, reason)
            })?;
        }
        let (display_text, category_id) = if fields.len() == 4 {
            let display_text = if fields[2].is_empty() {
                inline_display_text.map(str::to_owned)
            } else {
                if inline_display_text.is_some() {
                    return Err(error(
                        &path,
                        line_number,
                        UserLexiconField::DisplayText,
                        UserLexiconReason::InvalidDisplayText,
                    ));
                }
                validate_display_text(&path, line_number, fields[2])?;
                Some(fields[2].to_owned())
            };
            validate_category_id(&path, line_number, fields[3])?;
            (display_text, Some(fields[3].to_owned()))
        } else if fields.len() == 3 {
            if !fields[2].is_empty() {
                validate_display_text(&path, line_number, fields[2])?;
            }
            (
                if fields[2].is_empty() {
                    None
                } else {
                    Some(fields[2].to_owned())
                },
                None,
            )
        } else {
            (inline_display_text.map(str::to_owned), None)
        };
        let source_order = next_source_order;
        next_source_order = next_source_order.checked_add(1).ok_or_else(|| {
            error(
                &path,
                line_number,
                UserLexiconField::SourceOrder,
                UserLexiconReason::SourceOrderOutOfRange,
            )
        })?;
        entries.push(UserLexiconEntry {
            text: text.to_owned(),
            display_text,
            code,
            action,
            source_order,
            category_id,
        });
    }

    Ok(ParsedUserLexicon {
        accepted_rows: entries.len(),
        entries,
    })
}

fn parse_direct_word_and_display<'a>(
    path: &Path,
    line: usize,
    value: &'a str,
) -> Result<(&'a str, Option<&'a str>), UserLexiconError> {
    let Some((text, display_text)) = value.split_once(',') else {
        return Ok((value, None));
    };
    if text.is_empty() {
        return Err(error(
            path,
            line,
            UserLexiconField::Word,
            UserLexiconReason::EmptyWord,
        ));
    }
    validate_display_text(path, line, display_text)?;
    Ok((text, Some(display_text)))
}

fn validate_display_text(path: &Path, line: usize, value: &str) -> Result<(), UserLexiconError> {
    if value.is_empty()
        || value.chars().count() > 64
        || value
            .chars()
            .any(|character| character.is_control() || matches!(character, '\t' | '\r' | '\n'))
    {
        return Err(error(
            path,
            line,
            UserLexiconField::DisplayText,
            UserLexiconReason::InvalidDisplayText,
        ));
    }
    Ok(())
}

fn validate_category_id(path: &Path, line: usize, value: &str) -> Result<(), UserLexiconError> {
    if value.is_empty()
        || value.len() > 64
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
    {
        return Err(error(
            path,
            line,
            UserLexiconField::Category,
            UserLexiconReason::InvalidCategory,
        ));
    }
    Ok(())
}

fn parse_code_and_action(
    path: &Path,
    line: usize,
    raw: &str,
) -> Result<(String, UserLexiconAction), UserLexiconError> {
    if raw.is_empty() {
        return Err(error(
            path,
            line,
            UserLexiconField::Code,
            UserLexiconReason::EmptyCode,
        ));
    }
    let hash_count = raw.bytes().filter(|byte| *byte == b'#').count();
    if hash_count > 1 {
        return Err(error(
            path,
            line,
            UserLexiconField::Marker,
            UserLexiconReason::MultipleMarkers,
        ));
    }
    let (code, action) = match raw.find('#') {
        None => (raw, UserLexiconAction::Add),
        Some(index) => {
            if index == 0 {
                return Err(error(
                    path,
                    line,
                    UserLexiconField::Code,
                    UserLexiconReason::EmptyCode,
                ));
            }
            let code = &raw[..index];
            let marker = &raw[index + 1..];
            let action = match marker {
                "直" => UserLexiconAction::Direct,
                "网页" => UserLexiconAction::OpenUrl,
                "目录" => UserLexiconAction::OpenDirectory,
                "删" => UserLexiconAction::Delete,
                "固" => UserLexiconAction::Fixed,
                "" => {
                    return Err(error(
                        path,
                        line,
                        UserLexiconField::Marker,
                        UserLexiconReason::UnknownMarker,
                    ))
                }
                value if value.bytes().all(|byte| byte.is_ascii_digit()) => {
                    if value.starts_with('0') {
                        return Err(error(
                            path,
                            line,
                            UserLexiconField::Position,
                            UserLexiconReason::InvalidPosition,
                        ));
                    }
                    let position = value.parse::<u16>().map_err(|_| {
                        error(
                            path,
                            line,
                            UserLexiconField::Position,
                            UserLexiconReason::PositionOutOfRange,
                        )
                    })?;
                    if position == 0 {
                        return Err(error(
                            path,
                            line,
                            UserLexiconField::Position,
                            UserLexiconReason::InvalidPosition,
                        ));
                    }
                    UserLexiconAction::Position(position)
                }
                value
                    if value.starts_with('直')
                        || value.starts_with('删')
                        || value.starts_with('固') =>
                {
                    return Err(error(
                        path,
                        line,
                        UserLexiconField::Marker,
                        UserLexiconReason::MarkerNotAtEnd,
                    ))
                }
                _ => {
                    return Err(error(
                        path,
                        line,
                        UserLexiconField::Marker,
                        UserLexiconReason::UnknownMarker,
                    ))
                }
            };
            (code, action)
        }
    };
    validate_code(code).map_err(|reason| {
        let reason = match reason {
            CodeValidationError::Empty => UserLexiconReason::EmptyCode,
            CodeValidationError::Invalid => UserLexiconReason::InvalidCode,
        };
        error(path, line, UserLexiconField::Code, reason)
    })?;
    Ok((code.to_owned(), action))
}

fn error(
    path: &Path,
    line: usize,
    field: UserLexiconField,
    reason: UserLexiconReason,
) -> UserLexiconError {
    UserLexiconError::new(path, line, field, reason)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(text: &[u8]) -> Result<ParsedUserLexicon, UserLexiconError> {
        parse_user_lexicon_bytes("fixture.txt", text)
    }

    #[test]
    fn parses_all_actions_bom_lf_crlf_and_no_final_newline() {
        let parsed = parse(
            "\u{feff}自定义词\tzidycl\r\n直通词,候选提示\tzhitc#直\r\n删除词\tshanc#删\r\n固定词\tgudic#固\r\n第二词\tdeerc#2"
                .as_bytes(),
        )
        .unwrap();
        assert_eq!(parsed.entries.len(), 5);
        assert_eq!(parsed.entries[0].action, UserLexiconAction::Add);
        assert_eq!(parsed.entries[1].action, UserLexiconAction::Direct);
        assert_eq!(parsed.entries[1].text, "直通词");
        assert_eq!(parsed.entries[1].display_text.as_deref(), Some("候选提示"));
        assert_eq!(parsed.entries[2].action, UserLexiconAction::Delete);
        assert_eq!(parsed.entries[3].action, UserLexiconAction::Fixed);
        assert_eq!(parsed.entries[4].action, UserLexiconAction::Position(2));
    }

    #[test]
    fn accepts_empty_file_and_max_position() {
        assert!(parse(b"").unwrap().entries.is_empty());
        assert_eq!(
            parse("最长位\tabc#65535\n".as_bytes()).unwrap().entries[0].action,
            UserLexiconAction::Position(u16::MAX)
        );
    }

    #[test]
    fn rejects_invalid_utf8_fields_codes_and_markers() {
        let invalid: &[&[u8]] = &[
            &[0xff],
            "缺少分隔 abc\n".as_bytes(),
            "多字段\tabc\textra\n".as_bytes(),
            "\tabc\n".as_bytes(),
            "空编码\t\n".as_bytes(),
            "非法码\tab c\n".as_bytes(),
            "未知\tabc#未知\n".as_bytes(),
            "重复\tabc#1#固\n".as_bytes(),
            "零位\tabc#0\n".as_bytes(),
            "负数\tabc#-1\n".as_bytes(),
            "正号\tabc#+1\n".as_bytes(),
            "小数\tabc#1.5\n".as_bytes(),
            "溢出\tabc#65536\n".as_bytes(),
            "后缀\tabc#删abc\n".as_bytes(),
            "固后缀\tabc#固2\n".as_bytes(),
            "直通空提示,\tabc#直\n".as_bytes(),
            ",只有提示\tabc#直\n".as_bytes(),
            "直通后缀\tabc#直x\n".as_bytes(),
        ];
        for bytes in invalid {
            assert!(parse(bytes).is_err(), "{bytes:?}");
        }
    }

    #[test]
    fn diagnostics_include_path_line_field_and_reason_without_row_echo() {
        let error = parse("好词\tabc\n坏词 abc\n".as_bytes()).unwrap_err();
        let message = error.to_string();
        assert!(message.contains("fixture.txt:2"));
        assert!(message.contains("field=fields"));
        assert!(message.contains("error="));
        assert!(!message.contains("坏词 abc"));
    }

    #[test]
    fn embedded_profile_preserves_display_text_and_category_scope() {
        let parsed = parse_embedded_user_lexicon_bytes(
            "embedded.txt",
            "给予\tgwyu\t给ʲⁱ̌予\tcore\n普通\tptaa\t\tfull-code-word\n".as_bytes(),
        )
        .unwrap();
        assert_eq!(parsed.entries[0].text, "给予");
        assert_eq!(parsed.entries[0].display_text.as_deref(), Some("给ʲⁱ̌予"));
        assert_eq!(parsed.entries[0].category_id.as_deref(), Some("core"));
        assert_eq!(parsed.entries[1].display_text, None);
        assert_eq!(
            parsed.entries[1].category_id.as_deref(),
            Some("full-code-word")
        );

        assert!(
            parse_user_lexicon_bytes("external.txt", "给予\tgwyu\t给ʲⁱ̌予\tcore\n".as_bytes())
                .is_err()
        );
    }
}
