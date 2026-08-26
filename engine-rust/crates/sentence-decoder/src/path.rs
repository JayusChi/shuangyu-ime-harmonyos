use std::collections::{BTreeMap, BTreeSet};

use crate::graph::WordEdge;

/// A decoded sentence path produced by bounded Viterbi search.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SentencePath {
    pub edges: Vec<WordEdge>,
    pub score: i64,
}

impl SentencePath {
    pub fn text(&self) -> String {
        self.edges
            .iter()
            .map(|edge| edge.text.as_str())
            .collect::<Vec<_>>()
            .join("")
    }

    pub fn reading(&self) -> String {
        self.edges
            .iter()
            .map(|edge| edge.reading.as_str())
            .collect::<Vec<_>>()
            .join(" ")
    }

    pub fn source(&self) -> String {
        merge_sources(self.edges.iter().map(|edge| edge.source.as_str()))
    }

    pub fn consumed_syllables(&self) -> usize {
        self.edges.last().map(|edge| edge.end).unwrap_or(0)
    }

    pub fn fallback_count(&self) -> usize {
        self.edges.iter().filter(|edge| edge.fallback).count()
    }

    pub fn path_key(&self) -> String {
        self.edges
            .iter()
            .map(WordEdge::path_token)
            .collect::<Vec<_>>()
            .join(">")
    }
}

/// Internal candidate data passed from the decoder to `ime-engine`.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SentenceCandidate {
    pub id: String,
    pub text: String,
    pub reading: String,
    pub source: String,
    pub consumed_syllables: usize,
    pub raw_start: usize,
    pub raw_end: usize,
    pub complete_coverage: bool,
    pub score: i64,
    pub path_key: String,
    /// Decoder-owned word segmentation. This is not exposed through the IME
    /// protocol; it lets a later word-level re-ranker score only existing paths.
    pub words: Vec<String>,
    pub fallback_count: usize,
}

impl SentenceCandidate {
    pub(crate) fn from_path(path: &SentencePath, raw_end: usize, complete_coverage: bool) -> Self {
        let text = path.text();
        let reading = path.reading();
        let path_key = path.path_key();
        Self {
            id: stable_candidate_id(raw_end, &reading, &text),
            text,
            reading,
            source: path.source(),
            consumed_syllables: path.consumed_syllables(),
            raw_start: 0,
            raw_end,
            complete_coverage,
            score: path.score,
            path_key,
            words: path.edges.iter().map(|edge| edge.text.clone()).collect(),
            fallback_count: path.fallback_count(),
        }
    }

    pub(crate) fn from_prefix_edge(edge: &WordEdge, score: i64) -> Self {
        Self {
            id: stable_candidate_id(edge.end * 2, &edge.reading, &edge.text),
            text: edge.text.clone(),
            reading: edge.reading.clone(),
            source: edge.source.clone(),
            consumed_syllables: edge.end,
            raw_start: 0,
            raw_end: edge.end * 2,
            complete_coverage: false,
            score,
            path_key: edge.path_token(),
            words: vec![edge.text.clone()],
            fallback_count: usize::from(edge.fallback),
        }
    }
}

pub(crate) fn deduplicate_candidates(
    candidates: impl IntoIterator<Item = SentenceCandidate>,
) -> Vec<SentenceCandidate> {
    let mut by_text = BTreeMap::<String, SentenceCandidate>::new();
    let mut seen_paths = BTreeSet::<String>::new();
    for candidate in candidates {
        if !seen_paths.insert(candidate.path_key.clone()) {
            continue;
        }
        match by_text.get(&candidate.text) {
            Some(existing) if compare_candidate(existing, &candidate).is_lt() => {}
            _ => {
                by_text.insert(candidate.text.clone(), candidate);
            }
        }
    }
    let mut values = by_text.into_values().collect::<Vec<_>>();
    values.sort_by(compare_candidate);
    values
}

pub(crate) fn compare_path(left: &SentencePath, right: &SentencePath) -> std::cmp::Ordering {
    compare_path_parts(left.score, &left.edges, right.score, &right.edges)
}

pub(crate) fn compare_path_parts(
    left_score: i64,
    left_edges: &[WordEdge],
    right_score: i64,
    right_edges: &[WordEdge],
) -> std::cmp::Ordering {
    right_score
        .cmp(&left_score)
        .then_with(|| {
            left_edges
                .iter()
                .filter(|edge| edge.fallback)
                .count()
                .cmp(&right_edges.iter().filter(|edge| edge.fallback).count())
        })
        .then_with(|| left_edges.len().cmp(&right_edges.len()))
        // String ordering is byte-lexicographic. Compare the borrowed pieces
        // directly so hot sort comparisons do not rebuild joined Strings.
        .then_with(|| {
            left_edges
                .iter()
                .flat_map(|edge| edge.text.bytes())
                .cmp(right_edges.iter().flat_map(|edge| edge.text.bytes()))
        })
        .then_with(|| joined_reading_bytes(left_edges).cmp(joined_reading_bytes(right_edges)))
        // Path identity is the final, rarely reached tie-break. Keep the
        // existing token contract exactly rather than changing ordering.
        .then_with(|| path_key_for_edges(left_edges).cmp(&path_key_for_edges(right_edges)))
}

fn joined_reading_bytes(edges: &[WordEdge]) -> impl Iterator<Item = u8> + '_ {
    edges.iter().enumerate().flat_map(|(index, edge)| {
        std::iter::once(b' ')
            .take(usize::from(index > 0))
            .chain(edge.reading.bytes())
    })
}

fn path_key_for_edges(edges: &[WordEdge]) -> String {
    edges
        .iter()
        .map(WordEdge::path_token)
        .collect::<Vec<_>>()
        .join(">")
}

fn compare_candidate(left: &SentenceCandidate, right: &SentenceCandidate) -> std::cmp::Ordering {
    right
        .complete_coverage
        .cmp(&left.complete_coverage)
        .then_with(|| right.score.cmp(&left.score))
        .then_with(|| right.consumed_syllables.cmp(&left.consumed_syllables))
        .then_with(|| left.text.cmp(&right.text))
        .then_with(|| left.reading.cmp(&right.reading))
        .then_with(|| left.path_key.cmp(&right.path_key))
}

fn stable_candidate_id(raw_end: usize, reading: &str, text: &str) -> String {
    format!("sentence:{raw_end}:{}:{text}", reading.replace(' ', "_"))
}

fn merge_sources<'a>(sources: impl Iterator<Item = &'a str>) -> String {
    let mut unique = BTreeSet::new();
    for source in sources {
        for item in source.split(',') {
            let trimmed = item.trim();
            if !trimmed.is_empty() {
                unique.insert(trimmed.to_owned());
            }
        }
    }
    unique.into_iter().collect::<Vec<_>>().join(",")
}
