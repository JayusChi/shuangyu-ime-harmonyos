use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use lexicon_core::LexiconEntry;

use crate::code::validate_code;
use crate::error::{BuildError, LineError, LineErrorReason};
use crate::parser::{ParseStats, ParsedLexicon};

const EXPECTED_FIELD_COUNT: usize = 2;
const TABLE_SOURCE: &str = "flypy-table";

/// Offline importer for `word<TAB>code` tables.
///
/// Inputs are consumed in the exact order supplied by the build command. Each
/// accepted physical data row receives a global zero-based `source_order`.
pub struct FlypyTableImporter {
    input_rows: usize,
    accepted_rows: usize,
    next_source_order: u32,
    entries: BTreeMap<(String, String), LexiconEntry>,
}

impl Default for FlypyTableImporter {
    fn default() -> Self {
        Self::new()
    }
}

impl FlypyTableImporter {
    pub fn new() -> Self {
        Self {
            input_rows: 0,
            accepted_rows: 0,
            next_source_order: 0,
            entries: BTreeMap::new(),
        }
    }

    pub fn import_files(mut self, paths: &[PathBuf]) -> Result<ParsedLexicon, BuildError> {
        for path in paths {
            self.import_file(path)?;
        }
        if self.accepted_rows == 0 {
            return Err(BuildError::EmptyInput {
                path: paths.first().cloned().unwrap_or_default(),
            });
        }

        let mut entries = self.entries.into_values().collect::<Vec<_>>();
        entries.sort_by(|left, right| {
            left.pinyin_key
                .cmp(&right.pinyin_key)
                .then_with(|| left.word.cmp(&right.word))
                .then_with(|| left.source_order.cmp(&right.source_order))
        });
        Ok(ParsedLexicon {
            stats: ParseStats {
                input_rows: self.input_rows,
                accepted_rows: self.accepted_rows,
                merged_duplicates: self.accepted_rows - entries.len(),
            },
            entries,
        })
    }

    fn import_file(&mut self, path: &Path) -> Result<(), BuildError> {
        let bytes = std::fs::read(path).map_err(|source| BuildError::InputIo {
            path: path.to_path_buf(),
            source,
        })?;
        let text = String::from_utf8(bytes).map_err(|source| BuildError::InvalidUtf8 {
            path: path.to_path_buf(),
            source,
        })?;
        self.import_text(path, &text)
    }

    fn import_text(&mut self, path: &Path, text: &str) -> Result<(), BuildError> {
        for (index, raw_line) in text.lines().enumerate() {
            let line_number = index + 1;
            let mut line = raw_line.strip_suffix('\r').unwrap_or(raw_line);
            if index == 0 {
                line = line.strip_prefix('\u{feff}').unwrap_or(line);
            }
            if line.trim().is_empty() {
                continue;
            }
            self.input_rows += 1;
            let (word, code) = parse_line(path, line_number, line)?;
            let source_order = self.next_source_order;
            self.next_source_order = self.next_source_order.checked_add(1).ok_or_else(|| {
                BuildError::Line(Box::new(LineError {
                    path: path.to_path_buf(),
                    line: line_number,
                    word: Some(word.clone()),
                    pinyin: Some(code.clone()),
                    field: "source_order",
                    reason: LineErrorReason::SourceOrderOutOfRange,
                }))
            })?;
            self.accepted_rows += 1;

            let key = (word.clone(), code.clone());
            self.entries.entry(key).or_insert_with(|| {
                LexiconEntry::new(
                    word,
                    code.clone(),
                    vec![code],
                    0,
                    vec![TABLE_SOURCE.to_owned()],
                )
                .with_source_order(source_order)
            });
        }
        Ok(())
    }
}

fn parse_line(path: &Path, line_number: usize, raw: &str) -> Result<(String, String), BuildError> {
    let fields = raw.split('\t').collect::<Vec<_>>();
    if fields.len() != EXPECTED_FIELD_COUNT {
        return Err(line_error(
            path,
            line_number,
            None,
            None,
            "fields",
            LineErrorReason::FieldCount {
                expected: EXPECTED_FIELD_COUNT,
                actual: fields.len(),
            },
        ));
    }

    let word = fields[0].to_owned();
    let code = fields[1].to_owned();
    if word.is_empty() {
        return Err(line_error(
            path,
            line_number,
            Some(word),
            Some(code),
            "word",
            LineErrorReason::EmptyWord,
        ));
    }
    validate_word(&word).map_err(|reason| {
        line_error(
            path,
            line_number,
            Some(word.clone()),
            Some(code.clone()),
            "word",
            reason,
        )
    })?;
    validate_code(&code).map_err(|reason| {
        line_error(
            path,
            line_number,
            Some(word.clone()),
            Some(code.clone()),
            "code",
            reason,
        )
    })?;
    Ok((word, code))
}

fn validate_word(word: &str) -> Result<(), LineErrorReason> {
    match lexicon_core::validate_system_table_word(word) {
        Ok(()) => Ok(()),
        Err(lexicon_core::WordValidationError::Empty) => Err(LineErrorReason::EmptyWord),
        Err(lexicon_core::WordValidationError::TooLong { actual, max }) => {
            Err(LineErrorReason::WordTooLong { actual, max })
        }
        Err(lexicon_core::WordValidationError::UnsupportedCharacter(ch)) => {
            Err(LineErrorReason::UnsupportedWordCharacter { ch })
        }
    }
}

fn line_error(
    path: &Path,
    line: usize,
    word: Option<String>,
    code: Option<String>,
    field: &'static str,
    reason: LineErrorReason,
) -> BuildError {
    BuildError::Line(Box::new(LineError {
        path: path.to_path_buf(),
        line,
        word,
        pinyin: code,
        field,
        reason,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(text: &str) -> Result<ParsedLexicon, BuildError> {
        let mut importer = FlypyTableImporter::new();
        importer.import_text(Path::new("fixture.txt"), text)?;
        if importer.accepted_rows == 0 {
            return Err(BuildError::EmptyInput {
                path: PathBuf::from("fixture.txt"),
            });
        }
        importer.import_files(&[])
    }

    #[test]
    fn imports_utf8_lf_crlf_and_bom_in_physical_order() {
        for text in [
            "第一词\tabz\n第二词\taba\n",
            "第一词\tabz\r\n第二词\taba\r\n",
            "\u{feff}第一词\tabz\n第二词\taba\n",
        ] {
            let parsed = parse(text).unwrap();
            let mut entries = parsed.entries;
            entries.sort_by_key(|entry| entry.source_order);
            assert_eq!(entries[0].word, "第一词");
            assert_eq!(entries[0].source_order, 0);
            assert_eq!(entries[1].word, "第二词");
            assert_eq!(entries[1].source_order, 1);
        }
    }

    #[test]
    fn rejects_malformed_rows_and_future_markers() {
        for text in [
            "第一词 abz\n",
            "第一词\tabz\textra\n",
            "\tabz\n",
            "第一词\t\n",
            "第一词\tab z\n",
            "第一词\tabz#固\n",
            "第一词\tabz#N\n",
            "第一词\tabz#删\n",
        ] {
            assert!(parse(text).is_err(), "{text:?}");
        }
    }

    #[test]
    fn error_contains_path_line_and_reason() {
        let error = parse("第一词\tabz\n第二词 bad\n").unwrap_err();
        let message = error.to_string();
        assert!(message.contains("fixture.txt:2:"), "{message}");
        assert!(
            message.contains("expected 2 TAB-separated fields"),
            "{message}"
        );
    }

    #[test]
    fn duplicate_keeps_first_source_order() {
        let parsed = parse("第一词\tabz\n第一词\tabz\n第二词\taba\n").unwrap();
        assert_eq!(parsed.stats.merged_duplicates, 1);
        let first = parsed
            .entries
            .iter()
            .find(|entry| entry.word == "第一词")
            .unwrap();
        let second = parsed
            .entries
            .iter()
            .find(|entry| entry.word == "第二词")
            .unwrap();
        assert_eq!(first.source_order, 0);
        assert_eq!(second.source_order, 2);
    }
}
