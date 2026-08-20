use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use lexicon_core::LexiconEntry;

use crate::error::{BuildError, LineError, LineErrorReason};
use crate::pinyin::normalize_pinyin;

const EXPECTED_FIELD_COUNT: usize = 4;
const MAX_WORD_CHARS: usize = 32;
const MAX_FREQUENCY: u64 = 1_000_000;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ParseStats {
    pub input_rows: usize,
    pub accepted_rows: usize,
    pub merged_duplicates: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ParsedLexicon {
    pub entries: Vec<LexiconEntry>,
    pub stats: ParseStats,
}

#[derive(Clone, Debug)]
struct AccumulatedEntry {
    word: String,
    pinyin_key: String,
    syllables: Vec<String>,
    frequency: u64,
    sources: BTreeSet<String>,
}

pub fn parse_source_file(path: &Path) -> Result<ParsedLexicon, BuildError> {
    let bytes = std::fs::read(path).map_err(|source| BuildError::InputIo {
        path: path.to_path_buf(),
        source,
    })?;
    let text = String::from_utf8(bytes).map_err(|source| BuildError::InvalidUtf8 {
        path: path.to_path_buf(),
        source,
    })?;
    parse_source_text(path, &text)
}

/// Parses and deterministically merges one or more normalized TSV sources.
pub fn parse_source_files(paths: &[PathBuf]) -> Result<ParsedLexicon, BuildError> {
    let mut input_rows = 0_usize;
    let mut accepted_rows = 0_usize;
    let mut merged = BTreeMap::<(String, String), AccumulatedEntry>::new();
    for path in paths {
        let parsed = parse_source_file(path)?;
        input_rows += parsed.stats.input_rows;
        accepted_rows += parsed.stats.accepted_rows;
        for entry in parsed.entries {
            let key = (entry.word.clone(), entry.pinyin_key.clone());
            merged
                .entry(key)
                .and_modify(|existing| {
                    existing.frequency = existing.frequency.saturating_add(entry.frequency);
                    existing.sources.extend(entry.sources.iter().cloned());
                })
                .or_insert_with(|| AccumulatedEntry {
                    word: entry.word,
                    pinyin_key: entry.pinyin_key,
                    syllables: entry.syllables,
                    frequency: entry.frequency,
                    sources: entry.sources.into_iter().collect(),
                });
        }
    }
    if accepted_rows == 0 {
        return Err(BuildError::EmptyInput {
            path: paths.first().cloned().unwrap_or_default(),
        });
    }
    let mut entries = merged
        .into_values()
        .map(|entry| {
            LexiconEntry::new(
                entry.word,
                entry.pinyin_key,
                entry.syllables,
                entry.frequency,
                entry.sources.into_iter().collect(),
            )
        })
        .collect::<Vec<_>>();
    entries.sort_by(|left, right| {
        left.pinyin_key
            .cmp(&right.pinyin_key)
            .then_with(|| left.word.cmp(&right.word))
            .then_with(|| left.source_key().cmp(&right.source_key()))
            .then_with(|| left.frequency.cmp(&right.frequency))
    });
    Ok(ParsedLexicon {
        stats: ParseStats {
            input_rows,
            accepted_rows,
            merged_duplicates: accepted_rows - entries.len(),
        },
        entries,
    })
}

pub fn parse_source_text(path: &Path, text: &str) -> Result<ParsedLexicon, BuildError> {
    let mut input_rows = 0_usize;
    let mut accepted_rows = 0_usize;
    let mut merged = BTreeMap::<(String, String), AccumulatedEntry>::new();

    for (index, raw_line) in text.lines().enumerate() {
        let line_number = index + 1;
        let line = raw_line.strip_suffix('\r').unwrap_or(raw_line);
        if line.trim().is_empty() || line.trim_start().starts_with('#') {
            continue;
        }
        input_rows += 1;
        let row = parse_line(path, line_number, line)?;
        accepted_rows += 1;
        let key = (row.word.clone(), row.pinyin_key.clone());
        merged
            .entry(key)
            .and_modify(|existing| {
                existing.frequency = existing.frequency.saturating_add(row.frequency);
                existing.sources.insert(row.source.clone());
            })
            .or_insert_with(|| {
                let mut sources = BTreeSet::new();
                sources.insert(row.source.clone());
                AccumulatedEntry {
                    word: row.word,
                    pinyin_key: row.pinyin_key,
                    syllables: row.syllables,
                    frequency: row.frequency,
                    sources,
                }
            });
    }

    if accepted_rows == 0 {
        return Err(BuildError::EmptyInput {
            path: path.to_path_buf(),
        });
    }

    let mut entries = merged
        .into_values()
        .map(|entry| {
            LexiconEntry::new(
                entry.word,
                entry.pinyin_key,
                entry.syllables,
                entry.frequency,
                entry.sources.into_iter().collect(),
            )
        })
        .collect::<Vec<_>>();
    entries.sort_by(|left, right| {
        left.pinyin_key
            .cmp(&right.pinyin_key)
            .then_with(|| left.word.cmp(&right.word))
            .then_with(|| left.source_key().cmp(&right.source_key()))
            .then_with(|| left.frequency.cmp(&right.frequency))
    });

    Ok(ParsedLexicon {
        stats: ParseStats {
            input_rows,
            accepted_rows,
            merged_duplicates: accepted_rows - entries.len(),
        },
        entries,
    })
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct SourceRow {
    word: String,
    pinyin_key: String,
    syllables: Vec<String>,
    frequency: u64,
    source: String,
}

fn parse_line(path: &Path, line: usize, raw: &str) -> Result<SourceRow, BuildError> {
    let fields = raw.split('\t').collect::<Vec<_>>();
    if fields.len() != EXPECTED_FIELD_COUNT {
        return Err(line_error(
            path,
            line,
            None,
            None,
            "fields",
            LineErrorReason::FieldCount {
                expected: EXPECTED_FIELD_COUNT,
                actual: fields.len(),
            },
        ));
    }

    let word = clean_field(fields[0]);
    let pinyin = clean_field(fields[1]);
    let frequency = clean_field(fields[2]);
    let source = clean_field(fields[3]);

    reject_control(path, line, "word", &word, Some(&word), Some(&pinyin))?;
    reject_control(path, line, "pinyin", &pinyin, Some(&word), Some(&pinyin))?;
    reject_control(
        path,
        line,
        "frequency",
        &frequency,
        Some(&word),
        Some(&pinyin),
    )?;
    reject_control(path, line, "source", &source, Some(&word), Some(&pinyin))?;

    if word.is_empty() {
        return Err(line_error(
            path,
            line,
            Some(word),
            Some(pinyin),
            "word",
            LineErrorReason::EmptyWord,
        ));
    }
    if pinyin.is_empty() {
        return Err(line_error(
            path,
            line,
            Some(word),
            Some(pinyin),
            "pinyin",
            LineErrorReason::EmptyPinyin,
        ));
    }
    if source.is_empty() {
        return Err(line_error(
            path,
            line,
            Some(word),
            Some(pinyin),
            "source",
            LineErrorReason::EmptySource,
        ));
    }

    validate_word(path, line, &word, &pinyin)?;
    validate_source(path, line, &word, &pinyin, &source)?;

    let frequency_value = parse_frequency(path, line, &word, &pinyin, &frequency)?;
    let normalized = normalize_pinyin(&pinyin).map_err(|reason| {
        line_error(
            path,
            line,
            Some(word.clone()),
            Some(pinyin.clone()),
            "pinyin",
            reason,
        )
    })?;

    let word_chars = word.chars().count();
    if word_chars != normalized.syllables.len() {
        return Err(line_error(
            path,
            line,
            Some(word),
            Some(pinyin),
            "pinyin",
            LineErrorReason::SyllableCountMismatch {
                word_chars,
                syllables: normalized.syllables.len(),
            },
        ));
    }

    Ok(SourceRow {
        word,
        pinyin_key: normalized.key,
        syllables: normalized.syllables,
        frequency: frequency_value,
        source,
    })
}

fn clean_field(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn reject_control(
    path: &Path,
    line: usize,
    field: &'static str,
    value: &str,
    word: Option<&str>,
    pinyin: Option<&str>,
) -> Result<(), BuildError> {
    if let Some(ch) = value.chars().find(|ch| ch.is_control()) {
        return Err(line_error(
            path,
            line,
            word.map(str::to_owned),
            pinyin.map(str::to_owned),
            field,
            LineErrorReason::ControlCharacter { field, ch },
        ));
    }
    Ok(())
}

fn validate_word(path: &Path, line: usize, word: &str, pinyin: &str) -> Result<(), BuildError> {
    let chars = word.chars().count();
    if chars > MAX_WORD_CHARS {
        return Err(line_error(
            path,
            line,
            Some(word.to_owned()),
            Some(pinyin.to_owned()),
            "word",
            LineErrorReason::WordTooLong {
                actual: chars,
                max: MAX_WORD_CHARS,
            },
        ));
    }
    if let Some(ch) = word.chars().find(|&ch| !is_common_cjk(ch)) {
        return Err(line_error(
            path,
            line,
            Some(word.to_owned()),
            Some(pinyin.to_owned()),
            "word",
            LineErrorReason::UnsupportedWordCharacter { ch },
        ));
    }
    Ok(())
}

fn validate_source(
    path: &Path,
    line: usize,
    word: &str,
    pinyin: &str,
    source: &str,
) -> Result<(), BuildError> {
    let valid = source.len() <= 64
        && source
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '_' | '-' | '.'));
    if !valid {
        return Err(line_error(
            path,
            line,
            Some(word.to_owned()),
            Some(pinyin.to_owned()),
            "source",
            LineErrorReason::InvalidSource {
                value: source.to_owned(),
            },
        ));
    }
    Ok(())
}

fn parse_frequency(
    path: &Path,
    line: usize,
    word: &str,
    pinyin: &str,
    value: &str,
) -> Result<u64, BuildError> {
    if value.starts_with('-') {
        return Err(line_error(
            path,
            line,
            Some(word.to_owned()),
            Some(pinyin.to_owned()),
            "frequency",
            LineErrorReason::FrequencyOutOfRange {
                value: value.to_owned(),
            },
        ));
    }
    let parsed = value.parse::<u64>().map_err(|error| {
        let reason = if error.to_string().contains("too large") {
            LineErrorReason::FrequencyOutOfRange {
                value: value.to_owned(),
            }
        } else {
            LineErrorReason::InvalidFrequency {
                value: value.to_owned(),
            }
        };
        line_error(
            path,
            line,
            Some(word.to_owned()),
            Some(pinyin.to_owned()),
            "frequency",
            reason,
        )
    })?;
    if parsed > MAX_FREQUENCY {
        return Err(line_error(
            path,
            line,
            Some(word.to_owned()),
            Some(pinyin.to_owned()),
            "frequency",
            LineErrorReason::FrequencyOutOfRange {
                value: value.to_owned(),
            },
        ));
    }
    Ok(parsed)
}

fn is_common_cjk(ch: char) -> bool {
    ('\u{4E00}'..='\u{9FFF}').contains(&ch)
}

fn line_error(
    path: &Path,
    line: usize,
    word: Option<String>,
    pinyin: Option<String>,
    field: &'static str,
    reason: LineErrorReason,
) -> BuildError {
    BuildError::Line(Box::new(LineError {
        path: PathBuf::from(path),
        line,
        word,
        pinyin,
        field,
        reason,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_comments_empty_lines_and_crlf() {
        let input = "# header\r\n\r\n你\tNI\t1\tstage6\r\n好\thao\t2\tstage6\r\n";
        let parsed = parse_source_text(Path::new("test.tsv"), input).unwrap();
        assert_eq!(parsed.stats.input_rows, 2);
        assert_eq!(parsed.entries.len(), 2);
        assert_eq!(parsed.entries[1].pinyin_key, "ni");
    }

    #[test]
    fn merges_duplicate_entries_deterministically() {
        let input = "你好\tni hao\t10\tb\n你好\tNI   HAO\t20\ta\n";
        let parsed = parse_source_text(Path::new("dup.tsv"), input).unwrap();
        assert_eq!(parsed.stats.merged_duplicates, 1);
        assert_eq!(parsed.entries.len(), 1);
        assert_eq!(parsed.entries[0].frequency, 30);
        assert_eq!(
            parsed.entries[0].sources,
            vec!["a".to_owned(), "b".to_owned()]
        );
    }

    #[test]
    fn keeps_same_word_different_pinyin_as_separate_entries() {
        let input = "行\txing\t10\ta\n行\thang\t20\ta\n";
        let parsed = parse_source_text(Path::new("multi.tsv"), input).unwrap();
        assert_eq!(parsed.entries.len(), 2);
    }

    #[test]
    fn reports_field_count_and_frequency_errors() {
        assert!(matches!(
            parse_source_text(Path::new("bad.tsv"), "你\tni\t1\n"),
            Err(BuildError::Line(error))
                if matches!(error.reason, LineErrorReason::FieldCount { expected: 4, actual: 3 })
        ));
        assert!(matches!(
            parse_source_text(Path::new("bad.tsv"), "你\tni\tabc\ttest\n"),
            Err(BuildError::Line(error))
                if matches!(error.reason, LineErrorReason::InvalidFrequency { .. })
        ));
        assert!(matches!(
            parse_source_text(Path::new("bad.tsv"), "你\tni\t-1\ttest\n"),
            Err(BuildError::Line(error))
                if matches!(error.reason, LineErrorReason::FrequencyOutOfRange { .. })
        ));
    }

    #[test]
    fn reports_empty_and_unsupported_values() {
        assert!(matches!(
            parse_source_text(Path::new("bad.tsv"), "\tni\t1\ttest\n"),
            Err(BuildError::Line(error)) if matches!(error.reason, LineErrorReason::EmptyWord)
        ));
        assert!(matches!(
            parse_source_text(Path::new("bad.tsv"), "A\tai\t1\ttest\n"),
            Err(BuildError::Line(error))
                if matches!(error.reason, LineErrorReason::UnsupportedWordCharacter { .. })
        ));
        assert!(matches!(
            parse_source_text(Path::new("bad.tsv"), "你\t\t1\ttest\n"),
            Err(BuildError::Line(error)) if matches!(error.reason, LineErrorReason::EmptyPinyin)
        ));
        assert!(matches!(
            parse_source_text(Path::new("bad.tsv"), "你\tni\t1\tbad/source\n"),
            Err(BuildError::Line(error))
                if matches!(error.reason, LineErrorReason::InvalidSource { .. })
        ));
    }

    #[test]
    fn reports_invalid_pinyin_and_mismatch() {
        assert!(matches!(
            parse_source_text(Path::new("bad.tsv"), "输入法\tshu ru invalid\t1\ttest\n"),
            Err(BuildError::Line(error))
                if matches!(
                    error.reason,
                    LineErrorReason::InvalidPinyinSyllable { index: 3, .. }
                )
        ));
        assert!(matches!(
            parse_source_text(Path::new("bad.tsv"), "你好\tni\t1\ttest\n"),
            Err(BuildError::Line(error))
                if matches!(error.reason, LineErrorReason::SyllableCountMismatch { .. })
        ));
    }

    #[test]
    fn rejects_hard_frequency_limit_and_abnormal_unicode() {
        assert!(matches!(
            parse_source_text(Path::new("bad.tsv"), "你\tni\t1000001\ttest\n"),
            Err(BuildError::Line(error))
                if matches!(error.reason, LineErrorReason::FrequencyOutOfRange { .. })
        ));
        assert!(matches!(
            parse_source_text(Path::new("bad.tsv"), "你\u{200b}\tni\t1\ttest\n"),
            Err(BuildError::Line(error))
                if matches!(error.reason, LineErrorReason::UnsupportedWordCharacter { .. })
        ));
    }
}
