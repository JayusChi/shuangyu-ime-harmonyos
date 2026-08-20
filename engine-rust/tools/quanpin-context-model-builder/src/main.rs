use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use context_reranker::{sha256_hex, NgramBuildInput, WordNgramModel};
use lexicon_core::{load_binary_lexicon, BinaryLexicon, LexiconEntry};

const DERIVED_BIGRAM_LIMIT: usize = 2_048;
const DERIVED_TRIGRAM_LIMIT: usize = 1_024;
const MAX_DERIVED_TOKEN_SYLLABLES: usize = 3;
const MAX_ENTRY_CONTRIBUTION: u32 = 100_000;

fn main() {
    if let Err(error) = run() {
        eprintln!("quanpin-context-model-builder: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut args = std::env::args_os().skip(1);
    let command = args
        .next()
        .and_then(|value| value.into_string().ok())
        .ok_or_else(usage)?;
    match command.as_str() {
        "derive" => derive_command(args),
        "derive-audit" => derive_audit_command(args),
        "tsv" => tsv_command(args),
        _ => Err(usage()),
    }
}

fn derive_audit_command(mut args: impl Iterator<Item = std::ffi::OsString>) -> Result<(), String> {
    let lexicon_path = args.next().map(PathBuf::from).ok_or_else(usage)?;
    let output = args.next().map(PathBuf::from).ok_or_else(usage)?;
    if args.next().is_some() {
        return Err(usage());
    }
    let lexicon_bytes = fs::read(&lexicon_path).map_err(|error| error.to_string())?;
    let lexicon = load_binary_lexicon(&lexicon_bytes).map_err(|error| error.to_string())?;
    let input = derive_ngrams(&lexicon);
    let bytes = render_audit(&input);
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(&output, &bytes).map_err(|error| error.to_string())?;
    println!(
        "audit={} bytes={} sha256={} bigrams={} trigrams={}",
        output.display(),
        bytes.len(),
        sha256_hex(&bytes),
        input.bigrams.len(),
        input.trigrams.len()
    );
    Ok(())
}

fn render_audit(input: &NgramBuildInput) -> Vec<u8> {
    let mut bigrams = input.bigrams.clone();
    bigrams.sort_by(|left, right| {
        left.0
            .cmp(&right.0)
            .then_with(|| left.1.cmp(&right.1))
            .then_with(|| left.2.cmp(&right.2))
    });
    let mut trigrams = input.trigrams.clone();
    trigrams.sort_by(|left, right| {
        left.0
            .cmp(&right.0)
            .then_with(|| left.1.cmp(&right.1))
            .then_with(|| left.2.cmp(&right.2))
            .then_with(|| left.3.cmp(&right.3))
    });
    let mut output = String::from("kind\tleft\tmiddle\tright\tcount\n");
    for (left, right, count) in bigrams {
        output.push_str(&format!("bigram\t{left}\t\t{right}\t{count}\n"));
    }
    for (left, middle, right, count) in trigrams {
        output.push_str(&format!("trigram\t{left}\t{middle}\t{right}\t{count}\n"));
    }
    output.into_bytes()
}

fn tsv_command(mut args: impl Iterator<Item = std::ffi::OsString>) -> Result<(), String> {
    let bigrams = args.next().map(PathBuf::from).ok_or_else(usage)?;
    let trigrams = args.next().map(PathBuf::from).ok_or_else(usage)?;
    let output = args.next().map(PathBuf::from).ok_or_else(usage)?;
    let lexicon_version = args
        .next()
        .and_then(|value| value.into_string().ok())
        .and_then(|value| value.parse::<u32>().ok())
        .ok_or_else(usage)?;
    if args.next().is_some() {
        return Err(usage());
    }
    let input = NgramBuildInput {
        bigrams: parse_bigrams(&bigrams)?,
        trigrams: parse_trigrams(&trigrams)?,
    };
    let bytes =
        WordNgramModel::build_bytes(lexicon_version, &input).map_err(|error| error.to_string())?;
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(&output, &bytes).map_err(|error| error.to_string())?;
    println!(
        "model={} bytes={} sha256={} lexiconVersion={}",
        output.display(),
        bytes.len(),
        sha256_hex(&bytes),
        lexicon_version
    );
    Ok(())
}

fn derive_command(mut args: impl Iterator<Item = std::ffi::OsString>) -> Result<(), String> {
    let lexicon_path = args.next().map(PathBuf::from).ok_or_else(usage)?;
    let output = args.next().map(PathBuf::from).ok_or_else(usage)?;
    if args.next().is_some() {
        return Err(usage());
    }
    let lexicon_bytes = fs::read(&lexicon_path).map_err(|error| error.to_string())?;
    let lexicon = load_binary_lexicon(&lexicon_bytes).map_err(|error| error.to_string())?;
    let input = derive_ngrams(&lexicon);
    let bytes = WordNgramModel::build_bytes(lexicon.header.lexicon_version, &input)
        .map_err(|error| error.to_string())?;
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(&output, &bytes).map_err(|error| error.to_string())?;
    println!(
        "model={} bytes={} sha256={} lexiconVersion={} bigrams={} trigrams={} sourceLexiconSha256={}",
        output.display(),
        bytes.len(),
        sha256_hex(&bytes),
        lexicon.header.lexicon_version,
        input.bigrams.len(),
        input.trigrams.len(),
        sha256_hex(&lexicon_bytes),
    );
    Ok(())
}

fn derive_ngrams(lexicon: &BinaryLexicon) -> NgramBuildInput {
    let mut by_reading = BTreeMap::<Vec<String>, Vec<&LexiconEntry>>::new();
    for entry in &lexicon.entries {
        if entry.word.chars().count() < 2 || entry.syllables.len() < 2 {
            continue;
        }
        by_reading
            .entry(entry.syllables.clone())
            .or_default()
            .push(entry);
    }
    for entries in by_reading.values_mut() {
        entries.sort_by(|left, right| {
            right
                .frequency
                .cmp(&left.frequency)
                .then_with(|| left.word.cmp(&right.word))
                .then_with(|| left.pinyin_key.cmp(&right.pinyin_key))
        });
    }

    let mut bigrams = BTreeMap::<(String, String), u32>::new();
    let mut trigrams = BTreeMap::<(String, String, String), u32>::new();
    for source in &lexicon.entries {
        if source.syllables.len() < 4 {
            continue;
        }
        let Some(words) = segment_into_known_words(source, &by_reading) else {
            continue;
        };
        if words.len() < 2 {
            continue;
        }
        let contribution = source.frequency.clamp(1, u64::from(MAX_ENTRY_CONTRIBUTION)) as u32;
        for pair in words.windows(2) {
            add_count(
                &mut bigrams,
                (pair[0].clone(), pair[1].clone()),
                contribution,
            );
        }
        for triple in words.windows(3) {
            add_count(
                &mut trigrams,
                (triple[0].clone(), triple[1].clone(), triple[2].clone()),
                contribution,
            );
        }
    }

    NgramBuildInput {
        bigrams: top_bigrams(bigrams),
        trigrams: top_trigrams(trigrams),
    }
}

fn segment_into_known_words(
    source: &LexiconEntry,
    by_reading: &BTreeMap<Vec<String>, Vec<&LexiconEntry>>,
) -> Option<Vec<String>> {
    let syllables = &source.syllables;
    let source_characters = source.word.chars().collect::<Vec<_>>();
    if source_characters.len() != syllables.len() {
        return None;
    }
    let mut paths = vec![None::<Vec<String>>; syllables.len() + 1];
    paths[0] = Some(Vec::new());
    for start in 0..syllables.len() {
        let Some(prefix) = paths[start].clone() else {
            continue;
        };
        let max_end = (start + MAX_DERIVED_TOKEN_SYLLABLES).min(syllables.len());
        for end in start + 2..=max_end {
            if start == 0 && end == syllables.len() {
                continue;
            }
            let key = syllables[start..end].to_vec();
            // Reading alone is insufficient because it can substitute an
            // unrelated homophone. Every derived token must also be the exact
            // text substring of the source production entry.
            let Some(entry) = by_reading.get(&key).and_then(|entries| {
                entries.iter().find(|entry| {
                    entry
                        .word
                        .chars()
                        .eq(source_characters[start..end].iter().copied())
                })
            }) else {
                continue;
            };
            let mut candidate = prefix.clone();
            candidate.push(entry.word.clone());
            let replace = paths[end].as_ref().is_none_or(|existing| {
                candidate.len() < existing.len()
                    || (candidate.len() == existing.len() && candidate < *existing)
            });
            if replace {
                paths[end] = Some(candidate);
            }
        }
    }
    paths.pop().flatten()
}

fn add_count<K: Ord>(counts: &mut BTreeMap<K, u32>, key: K, contribution: u32) {
    counts
        .entry(key)
        .and_modify(|count| *count = count.saturating_add(contribution).min(1_000_000))
        .or_insert(contribution);
}

fn top_bigrams(counts: BTreeMap<(String, String), u32>) -> Vec<(String, String, u32)> {
    let mut rows = counts
        .into_iter()
        .map(|((left, right), count)| (left, right, count))
        .collect::<Vec<_>>();
    rows.sort_by(|left, right| {
        right
            .2
            .cmp(&left.2)
            .then_with(|| left.0.cmp(&right.0))
            .then_with(|| left.1.cmp(&right.1))
    });
    rows.truncate(DERIVED_BIGRAM_LIMIT);
    rows
}

fn top_trigrams(
    counts: BTreeMap<(String, String, String), u32>,
) -> Vec<(String, String, String, u32)> {
    let mut rows = counts
        .into_iter()
        .map(|((left, middle, right), count)| (left, middle, right, count))
        .collect::<Vec<_>>();
    rows.sort_by(|left, right| {
        right
            .3
            .cmp(&left.3)
            .then_with(|| left.0.cmp(&right.0))
            .then_with(|| left.1.cmp(&right.1))
            .then_with(|| left.2.cmp(&right.2))
    });
    rows.truncate(DERIVED_TRIGRAM_LIMIT);
    rows
}

fn parse_bigrams(path: &Path) -> Result<Vec<(String, String, u32)>, String> {
    parse_rows(path, 3)?
        .into_iter()
        .map(|row| Ok((row[0].clone(), row[1].clone(), parse_count(&row[2], path)?)))
        .collect()
}

fn parse_trigrams(path: &Path) -> Result<Vec<(String, String, String, u32)>, String> {
    parse_rows(path, 4)?
        .into_iter()
        .map(|row| {
            Ok((
                row[0].clone(),
                row[1].clone(),
                row[2].clone(),
                parse_count(&row[3], path)?,
            ))
        })
        .collect()
}

fn parse_rows(path: &Path, expected_columns: usize) -> Result<Vec<Vec<String>>, String> {
    let contents = fs::read_to_string(path).map_err(|error| error.to_string())?;
    let mut rows = Vec::new();
    for (line_number, line) in contents.lines().enumerate() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let fields = line.split('\t').map(str::to_owned).collect::<Vec<_>>();
        if fields.len() != expected_columns || fields.iter().any(|field| field.trim() != field) {
            return Err(format!(
                "{}:{} expected {} trimmed tab-separated fields",
                path.display(),
                line_number + 1,
                expected_columns
            ));
        }
        rows.push(fields);
    }
    Ok(rows)
}

fn parse_count(value: &str, path: &Path) -> Result<u32, String> {
    value
        .parse::<u32>()
        .ok()
        .filter(|value| *value > 0)
        .ok_or_else(|| format!("{} has invalid n-gram count {value:?}", path.display()))
}

fn usage() -> String {
    "usage: quanpin-context-model-builder derive <production.lex> <output.qng> | quanpin-context-model-builder derive-audit <production.lex> <output.tsv> | quanpin-context-model-builder tsv <bigrams.tsv> <trigrams.tsv> <output.qng> <production-lexicon-version>".to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use lexicon_core::{build_binary_lexicon, load_binary_lexicon, LexiconEntry};

    #[test]
    fn derived_model_is_word_level_and_deterministic() {
        let entries = vec![
            entry("今天", "jin tian", 100),
            entry("津贴", "jin tian", 1_000),
            entry("天气", "tian qi", 90),
            entry("天启", "tian qi", 900),
            entry("预报", "yu bao", 80),
            entry("今天天气", "jin tian tian qi", 70),
            entry("今天天气预报", "jin tian tian qi yu bao", 60),
        ];
        let bytes = build_binary_lexicon(&entries, 7, 1).unwrap();
        let lexicon = load_binary_lexicon(&bytes).unwrap();
        let first = derive_ngrams(&lexicon);
        let second = derive_ngrams(&lexicon);
        assert_eq!(first.bigrams, second.bigrams);
        assert!(first
            .bigrams
            .iter()
            .any(|(left, right, _)| left == "今天" && right == "天气"));
        assert!(first
            .trigrams
            .iter()
            .any(|(left, middle, right, _)| left == "今天" && middle == "天气" && right == "预报"));
        assert!(first
            .bigrams
            .iter()
            .all(|(left, right, _)| { left.chars().count() >= 2 && right.chars().count() >= 2 }));
        assert!(!first
            .bigrams
            .iter()
            .any(|(left, right, _)| left == "津贴" || right == "天启"));
        assert_eq!(render_audit(&first), render_audit(&second));
    }

    fn entry(word: &str, pinyin: &str, frequency: u64) -> LexiconEntry {
        LexiconEntry::new(
            word.to_owned(),
            pinyin.to_owned(),
            pinyin.split_whitespace().map(str::to_owned).collect(),
            frequency,
            vec!["test".to_owned()],
        )
    }
}
