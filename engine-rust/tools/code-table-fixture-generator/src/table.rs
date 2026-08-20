use std::collections::{BTreeMap, BTreeSet};

use lexicon_core::{validate_system_table_word, WordValidationError, MAX_CODE_LEN};

use crate::error::FixtureError;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TableRow {
    pub word: String,
    pub code: String,
    pub physical_line: usize,
    pub source_order: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ValidatedTable {
    pub entry_count: usize,
    pub rows: Vec<TableRow>,
    pub code_lengths: BTreeSet<usize>,
    pub max_same_code_count: usize,
}

pub fn validate_table_bytes(bytes: &[u8], file: &str) -> Result<ValidatedTable, FixtureError> {
    let text = std::str::from_utf8(bytes).map_err(|error| {
        let physical_line = bytes[..error.valid_up_to()]
            .iter()
            .filter(|value| **value == b'\n')
            .count()
            + 1;
        FixtureError::diagnostic(
            "CTF_INVALID_UTF8",
            file,
            physical_line,
            "file",
            "source is not valid UTF-8",
        )
    })?;
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let mut rows = Vec::new();
    let mut duplicates = BTreeSet::new();
    let mut code_counts = BTreeMap::<String, usize>::new();
    let mut code_lengths = BTreeSet::new();

    for (index, raw_line) in text.split('\n').enumerate() {
        let physical_line = index + 1;
        let line = raw_line.strip_suffix('\r').unwrap_or(raw_line);
        if line.is_empty() {
            continue;
        }
        if line.contains('\r') {
            return Err(line_error(
                "CTF_CONTROL_CHARACTER",
                file,
                physical_line,
                "line",
                "embedded carriage return is forbidden",
            ));
        }
        if line.contains('\0') {
            return Err(line_error(
                "CTF_NUL_CHARACTER",
                file,
                physical_line,
                "line",
                "NUL is forbidden",
            ));
        }
        if line
            .chars()
            .any(|value| value.is_control() && value != '\t')
        {
            return Err(line_error(
                "CTF_CONTROL_CHARACTER",
                file,
                physical_line,
                "line",
                "control character is forbidden",
            ));
        }
        let fields = line.split('\t').collect::<Vec<_>>();
        if fields.len() != 2 {
            return Err(line_error(
                if fields.len() < 2 {
                    "CTF_TAB_MISSING"
                } else {
                    "CTF_TAB_EXTRA"
                },
                file,
                physical_line,
                "fields",
                "exactly two TAB-separated fields are required",
            ));
        }
        let word = fields[0];
        let code = fields[1];
        if word.is_empty() {
            return Err(line_error(
                "CTF_WORD_EMPTY",
                file,
                physical_line,
                "word",
                "word must not be empty",
            ));
        }
        if code.is_empty() {
            return Err(line_error(
                "CTF_CODE_EMPTY",
                file,
                physical_line,
                "code",
                "code must not be empty",
            ));
        }
        if word.trim() != word || code.trim() != code {
            return Err(line_error(
                "CTF_SURROUNDING_WHITESPACE",
                file,
                physical_line,
                if word.trim() != word { "word" } else { "code" },
                "surrounding whitespace is forbidden",
            ));
        }
        if code.contains("#删")
            || code.contains("#固")
            || code.split_once('#').is_some_and(|(_, value)| {
                !value.is_empty() && value.bytes().all(|b| b.is_ascii_digit())
            })
        {
            return Err(line_error(
                "CTF_USER_MARKER_FORBIDDEN",
                file,
                physical_line,
                "code",
                "user-lexicon marker is forbidden in a system table",
            ));
        }
        if code.len() > MAX_CODE_LEN {
            return Err(line_error(
                "CTF_CODE_TOO_LONG",
                file,
                physical_line,
                "code",
                "code exceeds the frozen maximum length",
            ));
        }
        if !code.bytes().all(|value| value.is_ascii_lowercase()) {
            return Err(line_error(
                "CTF_CODE_INVALID_CHARACTER",
                file,
                physical_line,
                "code",
                "code must contain lowercase ASCII letters only",
            ));
        }
        match validate_system_table_word(word) {
            Ok(()) => {}
            Err(WordValidationError::Empty) => unreachable!("empty word handled above"),
            Err(WordValidationError::TooLong { .. }) => {
                return Err(line_error(
                    "CTF_WORD_TOO_LONG",
                    file,
                    physical_line,
                    "word",
                    "word exceeds the frozen maximum character length",
                ));
            }
            Err(WordValidationError::UnsupportedCharacter(_)) => {
                return Err(line_error(
                    "CTF_WORD_INVALID_CHARACTER",
                    file,
                    physical_line,
                    "word",
                    "word contains a character outside the system-table policy",
                ));
            }
        }
        let duplicate_key = (word.to_owned(), code.to_owned());
        if !duplicates.insert(duplicate_key) {
            return Err(line_error(
                "CTF_DUPLICATE_ROW",
                file,
                physical_line,
                "row",
                "an identical word and code already exists in this category",
            ));
        }
        let source_order = u32::try_from(rows.len()).map_err(|_| {
            line_error(
                "CTF_SOURCE_ORDER_OVERFLOW",
                file,
                physical_line,
                "source_order",
                "source order exceeds u32",
            )
        })?;
        code_lengths.insert(code.len());
        *code_counts.entry(code.to_owned()).or_default() += 1;
        rows.push(TableRow {
            word: word.to_owned(),
            code: code.to_owned(),
            physical_line,
            source_order,
        });
    }
    if rows.is_empty() {
        return Err(FixtureError::diagnostic(
            "CTF_TABLE_EMPTY",
            file,
            0,
            "file",
            "table has no valid data rows",
        ));
    }
    Ok(ValidatedTable {
        entry_count: rows.len(),
        rows,
        code_lengths,
        max_same_code_count: code_counts.values().copied().max().unwrap_or(0),
    })
}

fn line_error(
    code: &'static str,
    file: &str,
    line: usize,
    field: &'static str,
    reason: &'static str,
) -> FixtureError {
    FixtureError::diagnostic(code, file, line, field, reason)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Diagnostic;

    #[test]
    fn accepts_lf_crlf_bom_and_mixed_synthetic_text() {
        for bytes in [
            "测试A0001\tabcd\n符号★\tabce\n".as_bytes(),
            "测试A0001\tabcd\r\n符号★\tabce\r\n".as_bytes(),
            "\u{feff}测试A0001\tabcd\n符号★\tabce".as_bytes(),
        ] {
            let table = validate_table_bytes(bytes, "fixture.txt").unwrap();
            assert_eq!(table.entry_count, 2);
            assert_eq!(table.rows[1].source_order, 1);
        }
    }

    #[test]
    fn negative_rows_have_stable_precise_diagnostics() {
        let cases: &[(&[u8], &str, usize, &str)] = &[
            (b"\xff\n", "CTF_INVALID_UTF8", 1, "file"),
            (b"word code\n", "CTF_TAB_MISSING", 1, "fields"),
            (b"word\tcode\textra\n", "CTF_TAB_EXTRA", 1, "fields"),
            (b"\tabcd\n", "CTF_WORD_EMPTY", 1, "word"),
            ("测试\t\n".as_bytes(), "CTF_CODE_EMPTY", 1, "code"),
            (
                "测试\tab1d\n".as_bytes(),
                "CTF_CODE_INVALID_CHARACTER",
                1,
                "code",
            ),
            (
                "测试\tabcd#删\n".as_bytes(),
                "CTF_USER_MARKER_FORBIDDEN",
                1,
                "code",
            ),
            (
                "测试\tabcd\n测试\tabcd\n".as_bytes(),
                "CTF_DUPLICATE_ROW",
                2,
                "row",
            ),
            ("测试\0\tabcd\n".as_bytes(), "CTF_NUL_CHARACTER", 1, "line"),
        ];
        for (bytes, code, line, field) in cases {
            let error = validate_table_bytes(bytes, "invalid.fixture").unwrap_err();
            let FixtureError::Diagnostic(diagnostic) = error else {
                panic!("expected diagnostic");
            };
            assert_eq!(diagnostic.code, *code);
            assert_eq!(diagnostic.file, "invalid.fixture");
            assert_eq!(diagnostic.line, *line);
            assert_eq!(diagnostic.field, *field);
            assert!(!diagnostic.reason.is_empty());
        }
    }

    #[test]
    fn rejects_all_user_marker_forms_and_length_boundaries() {
        for marker in ["#删", "#固", "#2"] {
            let input = format!("测试\tabcd{marker}\n");
            assert!(matches!(
                validate_table_bytes(input.as_bytes(), "invalid.fixture"),
                Err(FixtureError::Diagnostic(Diagnostic {
                    code: "CTF_USER_MARKER_FORBIDDEN",
                    ..
                }))
            ));
        }
        let code = "a".repeat(MAX_CODE_LEN + 1);
        let input = format!("测试\t{code}\n");
        assert!(matches!(
            validate_table_bytes(input.as_bytes(), "invalid.fixture"),
            Err(FixtureError::Diagnostic(Diagnostic {
                code: "CTF_CODE_TOO_LONG",
                ..
            }))
        ));
        let word = "测".repeat(lexicon_core::MAX_WORD_CHARS + 1);
        let input = format!("{word}\tabcd\n");
        assert!(matches!(
            validate_table_bytes(input.as_bytes(), "invalid.fixture"),
            Err(FixtureError::Diagnostic(Diagnostic {
                code: "CTF_WORD_TOO_LONG",
                ..
            }))
        ));
    }
}
