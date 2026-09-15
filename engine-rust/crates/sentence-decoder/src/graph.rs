use std::collections::{BTreeMap, BTreeSet};

use lexicon_core::{runtime_index, BinaryLexicon, LexiconEntry};

use crate::{DecodeError, DecodeLimits};

/// Index reading records by complete initial sequences. This avoids expanding
/// every initial into a Cartesian product of possible syllables at each key.
#[derive(Debug)]
pub(crate) struct InitialLexiconIndex {
    records: BTreeMap<String, Vec<usize>>,
}

fn initial(reading: &str) -> &str {
    if reading.starts_with("zh") || reading.starts_with("ch") || reading.starts_with("sh") {
        &reading[..2]
    } else {
        reading.get(..1).unwrap_or("")
    }
}

impl InitialLexiconIndex {
    pub(crate) fn build(lexicon: &BinaryLexicon) -> Self {
        let mut records = BTreeMap::<String, Vec<usize>>::new();
        for (index, record) in lexicon.index.iter().enumerate() {
            let key = record
                .pinyin_key
                .split_whitespace()
                .map(initial)
                .collect::<Vec<_>>()
                .join(" ");
            records.entry(key).or_default().push(index);
        }
        Self { records }
    }

    fn entries<'a>(
        &self,
        lexicon: &'a BinaryLexicon,
        syllables: &[String],
        initials: &[bool],
        limit: usize,
    ) -> Vec<&'a LexiconEntry> {
        let key = syllables
            .iter()
            .map(|s| initial(s))
            .collect::<Vec<_>>()
            .join(" ");
        let Some(records) = self.records.get(&key) else {
            return Vec::new();
        };
        let mut entries = Vec::new();
        for index in records {
            let reading = &lexicon.index[*index].pinyin_key;
            if reading.split_whitespace().zip(syllables).zip(initials).all(
                |((actual, expected), initial_only)| {
                    if *initial_only {
                        initial(actual) == expected
                    } else {
                        actual == expected
                    }
                },
            ) {
                entries.extend(runtime_index::entries_for_exact_key(
                    lexicon, reading, limit,
                ));
            }
        }
        entries.sort_by(|left, right| {
            right
                .frequency
                .cmp(&left.frequency)
                .then_with(|| left.word.cmp(&right.word))
                .then_with(|| left.pinyin_key.cmp(&right.pinyin_key))
        });
        entries.truncate(limit);
        entries
    }
}

/// A word edge in the stage 8 syllable DAG.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WordEdge {
    pub entry_id: String,
    pub text: String,
    pub reading: String,
    pub start: usize,
    pub end: usize,
    pub syllable_count: usize,
    pub frequency: u64,
    pub source: String,
    pub fallback: bool,
}

/// A caller-owned literal word occupying an exact range of phonetic slots.
/// Paths may not split or cross this range with a different lexical edge.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FixedWordConstraint {
    pub start: usize,
    pub end: usize,
    pub text: String,
    pub entry_id: String,
}

impl WordEdge {
    pub fn path_token(&self) -> String {
        format!(
            "{}:{}:{}:{}",
            self.start,
            self.end,
            self.reading.replace(' ', "_"),
            self.text
        )
    }
}

/// A directed acyclic graph whose nodes are syllable positions.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SyllableGraph {
    syllables: Vec<String>,
    edges_by_start: Vec<Vec<WordEdge>>,
    edge_count: usize,
}

impl SyllableGraph {
    pub fn build(
        lexicon: &BinaryLexicon,
        syllables: &[String],
        limits: &DecodeLimits,
    ) -> Result<Self, DecodeError> {
        Self::build_internal(lexicon, syllables, limits, None)
    }

    pub(crate) fn build_with_initials(
        lexicon: &BinaryLexicon,
        syllables: &[String],
        initials: &[bool],
        limits: &DecodeLimits,
        index: &InitialLexiconIndex,
    ) -> Result<Self, DecodeError> {
        Self::build_internal(lexicon, syllables, limits, Some((initials, index)))
    }

    fn build_internal(
        lexicon: &BinaryLexicon,
        syllables: &[String],
        limits: &DecodeLimits,
        initial_query: Option<(&[bool], &InitialLexiconIndex)>,
    ) -> Result<Self, DecodeError> {
        limits.validate()?;
        if syllables.len() > limits.max_syllables {
            return Err(DecodeError::TooManySyllables {
                actual: syllables.len(),
                max: limits.max_syllables,
            });
        }

        let mut graph = Self {
            syllables: syllables.to_vec(),
            edges_by_start: vec![Vec::new(); syllables.len() + 1],
            edge_count: 0,
        };

        let mut seen = BTreeSet::<(usize, usize, String, String)>::new();
        for start in 0..syllables.len() {
            let max_end = start
                .saturating_add(limits.max_word_syllables)
                .min(syllables.len());
            for end in start + 1..=max_end {
                if graph.edge_count >= limits.max_edges {
                    break;
                }
                let reading = syllables[start..end].join(" ");
                let entries = if let Some((initials, index)) =
                    initial_query.filter(|(flags, _)| flags[start..end].iter().any(|flag| *flag))
                {
                    index.entries(
                        lexicon,
                        &syllables[start..end],
                        &initials[start..end],
                        limits.max_entries_per_key,
                    )
                } else {
                    runtime_index::entries_for_exact_key(
                        lexicon,
                        &reading,
                        limits.max_entries_per_key,
                    )
                };
                for entry in entries {
                    if graph.edge_count >= limits.max_edges {
                        break;
                    }
                    let edge = edge_from_entry(lexicon, entry, start, end);
                    let dedupe_key = (start, end, edge.text.clone(), edge.reading.clone());
                    if seen.insert(dedupe_key) {
                        graph.edges_by_start[start].push(edge);
                        graph.edge_count += 1;
                    }
                }
            }

            if initial_query.is_none()
                && graph.edges_by_start[start].is_empty()
                && graph.edge_count < limits.max_edges
            {
                graph.edges_by_start[start].push(fallback_edge(syllables, start));
                graph.edge_count += 1;
            }
        }

        for edges in &mut graph.edges_by_start {
            edges.sort_by(|left, right| {
                left.start
                    .cmp(&right.start)
                    .then_with(|| left.end.cmp(&right.end))
                    .then_with(|| left.fallback.cmp(&right.fallback))
                    .then_with(|| right.frequency.cmp(&left.frequency))
                    .then_with(|| left.text.cmp(&right.text))
                    .then_with(|| left.reading.cmp(&right.reading))
                    .then_with(|| left.entry_id.cmp(&right.entry_id))
            });
        }

        Ok(graph)
    }

    pub fn syllable_count(&self) -> usize {
        self.syllables.len()
    }

    pub(crate) fn apply_fixed_words(
        &mut self,
        words: &[FixedWordConstraint],
    ) -> Result<(), DecodeError> {
        let mut previous_end = 0;
        for word in words {
            if word.start < previous_end
                || word.start >= word.end
                || word.end > self.syllables.len()
                || word.text.is_empty()
            {
                return Err(DecodeError::InvalidLimit {
                    field: "fixed word range",
                });
            }
            previous_end = word.end;
        }
        for word in words {
            // Remove overlapping edges, including longer system words that
            // would otherwise swallow a user-defined pair in mid-sentence.
            for edges in &mut self.edges_by_start {
                edges.retain(|edge| edge.end <= word.start || edge.start >= word.end);
            }
            self.edges_by_start[word.start].push(WordEdge {
                entry_id: word.entry_id.clone(),
                text: word.text.clone(),
                reading: self.syllables[word.start..word.end].join(" "),
                start: word.start,
                end: word.end,
                syllable_count: word.end - word.start,
                frequency: 1_000_000,
                source: "user-lexicon".to_owned(),
                fallback: false,
            });
        }
        self.edge_count = self.edges_by_start.iter().map(Vec::len).sum();
        Ok(())
    }

    pub fn edge_count(&self) -> usize {
        self.edge_count
    }

    pub fn edges_from(&self, start: usize) -> &[WordEdge] {
        self.edges_by_start
            .get(start)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }
}

fn edge_from_entry(
    lexicon: &BinaryLexicon,
    entry: &LexiconEntry,
    start: usize,
    end: usize,
) -> WordEdge {
    WordEdge {
        entry_id: stable_entry_id(
            lexicon.header.lexicon_version,
            &entry.pinyin_key,
            &entry.word,
        ),
        text: entry.word.clone(),
        reading: entry.pinyin_key.clone(),
        start,
        end,
        syllable_count: end - start,
        frequency: entry.frequency,
        source: entry.source_key(),
        fallback: false,
    }
}

fn fallback_edge(syllables: &[String], start: usize) -> WordEdge {
    let reading = syllables[start].clone();
    WordEdge {
        entry_id: format!("fallback:{start}:{reading}"),
        text: reading.clone(),
        reading,
        start,
        end: start + 1,
        syllable_count: 1,
        frequency: 0,
        source: "fallback".to_owned(),
        fallback: true,
    }
}

fn stable_entry_id(lexicon_version: u32, reading: &str, text: &str) -> String {
    format!(
        "lex-v{}-{}-{}",
        lexicon_version,
        reading.replace(' ', "_"),
        text
    )
}

#[cfg(test)]
mod tests {
    use lexicon_core::{build_binary_lexicon, load_binary_lexicon, LexiconEntry};

    use super::*;

    #[test]
    fn graph_adds_fallback_only_for_uncovered_starts() {
        let lexicon = sample_lexicon();
        let limits = DecodeLimits::default();
        let syllables = vec!["ni".to_owned(), "xian".to_owned()];
        let graph = SyllableGraph::build(&lexicon, &syllables, &limits).unwrap();

        assert!(graph.edges_from(0).iter().any(|edge| edge.text == "你"));
        assert!(graph.edges_from(1).iter().any(|edge| edge.fallback));
        assert!(graph.edge_count() <= limits.max_edges);
    }

    fn sample_lexicon() -> BinaryLexicon {
        let entries = vec![LexiconEntry::new(
            "你".to_owned(),
            "ni".to_owned(),
            vec!["ni".to_owned()],
            100,
            vec!["stage8".to_owned()],
        )];
        let bytes = build_binary_lexicon(&entries, 8, 1).unwrap();
        load_binary_lexicon(&bytes).unwrap()
    }
}
