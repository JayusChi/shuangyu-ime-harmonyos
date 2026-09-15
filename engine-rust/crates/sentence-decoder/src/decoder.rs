use std::sync::{Arc, OnceLock};

use lexicon_core::BinaryLexicon;

use crate::context::CharacterBigramModel;
use crate::graph::{FixedWordConstraint, InitialLexiconIndex, SyllableGraph, WordEdge};
use crate::path::{
    compare_path, compare_path_parts, deduplicate_candidates, SentenceCandidate, SentencePath,
};
use crate::scorer::{SentenceScorer, SentenceScoring};
use crate::t9_joint::{T9JointDecodeResult, T9JointLimits, T9JointSession, T9LexiconIndex};
use crate::{DecodeError, DecodeLimits};

pub struct XiaoheSentenceQuery<'a> {
    pub raw_input: &'a str,
    pub syllables: &'a [String],
    pub initials: &'a [bool],
    pub raw_lengths: &'a [usize],
    pub fixed_words: &'a [FixedWordConstraint],
}

/// Decoded sentence candidates and debug-friendly graph counts.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DecodeResult {
    pub candidates: Vec<SentenceCandidate>,
    pub graph_edge_count: usize,
}

/// Reusable decoder bound to one already loaded binary lexicon.
#[derive(Clone, Debug)]
pub struct SentenceDecoder {
    lexicon: Arc<BinaryLexicon>,
    context_model: CharacterBigramModel,
    limits: DecodeLimits,
    t9_index: Arc<OnceLock<T9LexiconIndex>>,
    initial_index: Arc<OnceLock<InitialLexiconIndex>>,
}

impl SentenceDecoder {
    pub fn new(lexicon: BinaryLexicon, limits: DecodeLimits) -> Result<Self, DecodeError> {
        Self::new_shared(Arc::new(lexicon), limits)
    }

    pub fn new_shared(
        lexicon: Arc<BinaryLexicon>,
        limits: DecodeLimits,
    ) -> Result<Self, DecodeError> {
        limits.validate()?;
        let context_model = CharacterBigramModel::from_lexicon(&lexicon);
        Ok(Self {
            lexicon,
            context_model,
            limits,
            t9_index: Arc::new(OnceLock::new()),
            initial_index: Arc::new(OnceLock::new()),
        })
    }

    pub fn limits(&self) -> &DecodeLimits {
        &self.limits
    }

    /// Reconfigures the bounded search without rebuilding the lexicon-backed
    /// decoder. Scheme switches use this to keep their work ceilings
    /// independent from the scheme that originally created the engine.
    pub fn set_limits(&mut self, limits: DecodeLimits) -> Result<(), DecodeError> {
        limits.validate()?;
        self.limits = limits;
        Ok(())
    }

    pub fn lexicon_version(&self) -> u32 {
        self.lexicon.header.lexicon_version
    }

    /// Joint digit/pinyin/lexicon/word search used only by `schemeId=pinyin-9`.
    /// The digit index is built lazily and then reused across key updates.
    pub fn decode_t9_joint(
        &self,
        raw_digits: &str,
        explicit_boundaries: &[usize],
        limits: &T9JointLimits,
    ) -> Result<T9JointDecodeResult, DecodeError> {
        if raw_digits.len() > limits.max_raw_digits {
            return Err(DecodeError::RawInputTooLong {
                actual: raw_digits.len(),
                max: limits.max_raw_digits,
            });
        }
        let index = self
            .t9_index
            .get_or_init(|| T9LexiconIndex::build(&self.lexicon));
        Ok(index.decode(
            &self.lexicon,
            &self.context_model,
            raw_digits,
            explicit_boundaries,
            limits,
        ))
    }

    pub fn update_t9_joint(
        &self,
        session: &mut T9JointSession,
        raw_digits: &str,
        explicit_boundaries: &[usize],
        limits: &T9JointLimits,
    ) -> Result<T9JointDecodeResult, DecodeError> {
        if raw_digits.len() > limits.max_raw_digits {
            return Err(DecodeError::RawInputTooLong {
                actual: raw_digits.len(),
                max: limits.max_raw_digits,
            });
        }
        let index = self
            .t9_index
            .get_or_init(|| T9LexiconIndex::build(&self.lexicon));
        Ok(index.update_session(
            &self.lexicon,
            &self.context_model,
            session,
            raw_digits,
            explicit_boundaries,
            limits,
        ))
    }

    /// Build once at Xiaohe engine load, rather than on the first odd key.
    pub fn prepare_initial_queries(&self) {
        self.initial_index
            .get_or_init(|| InitialLexiconIndex::build(&self.lexicon));
    }

    /// Moves one-time digit-index construction into explicit pinyin-9 engine
    /// load instead of charging it to the first key latency.
    pub fn prepare_t9_joint(&self) {
        self.t9_index
            .get_or_init(|| T9LexiconIndex::build(&self.lexicon));
    }

    pub fn decode(
        &self,
        raw_input: &str,
        syllables: &[String],
        pending_code: &str,
    ) -> Result<DecodeResult, DecodeError> {
        self.decode_with_user_scores(raw_input, syllables, pending_code, |_| 0)
    }

    pub fn decode_with_user_scores(
        &self,
        raw_input: &str,
        syllables: &[String],
        pending_code: &str,
        mut user_score: impl FnMut(&SentenceCandidate) -> i64,
    ) -> Result<DecodeResult, DecodeError> {
        if raw_input.len() > self.limits.max_raw_len {
            return Err(DecodeError::RawInputTooLong {
                actual: raw_input.len(),
                max: self.limits.max_raw_len,
            });
        }
        if syllables.is_empty() {
            return Ok(DecodeResult {
                candidates: Vec::new(),
                graph_edge_count: 0,
            });
        }

        let graph = SyllableGraph::build(&self.lexicon, syllables, &self.limits)?;
        self.decode_graph(
            &graph,
            !pending_code.is_empty(),
            &vec![2; syllables.len()],
            SentenceScoring::Standard,
            &mut user_score,
        )
    }

    /// Initial slots are lexical constraints, never committed raw Latin text.
    /// Their raw lengths also keep partial selections aligned after a 声声 pair.
    pub fn decode_with_initials_and_user_scores(
        &self,
        raw_input: &str,
        syllables: &[String],
        initials: &[bool],
        raw_lengths: &[usize],
        user_score: impl FnMut(&SentenceCandidate) -> i64,
    ) -> Result<DecodeResult, DecodeError> {
        self.decode_xiaohe_query(
            XiaoheSentenceQuery {
                raw_input,
                syllables,
                initials,
                raw_lengths,
                fixed_words: &[],
            },
            SentenceScoring::Initials,
            user_score,
        )
    }

    pub fn decode_xiaohe_with_user_scores(
        &self,
        query: XiaoheSentenceQuery<'_>,
        user_score: impl FnMut(&SentenceCandidate) -> i64,
    ) -> Result<DecodeResult, DecodeError> {
        let scoring = if query.initials.iter().any(|flag| *flag) {
            SentenceScoring::Initials
        } else {
            SentenceScoring::Xiaohe
        };
        self.decode_xiaohe_query(query, scoring, user_score)
    }

    fn decode_xiaohe_query(
        &self,
        query: XiaoheSentenceQuery<'_>,
        scoring: SentenceScoring,
        mut user_score: impl FnMut(&SentenceCandidate) -> i64,
    ) -> Result<DecodeResult, DecodeError> {
        let XiaoheSentenceQuery {
            raw_input,
            syllables,
            initials,
            raw_lengths,
            fixed_words,
        } = query;
        if raw_input.len() > self.limits.max_raw_len {
            return Err(DecodeError::RawInputTooLong {
                actual: raw_input.len(),
                max: self.limits.max_raw_len,
            });
        }
        if syllables.len() != initials.len() || syllables.len() != raw_lengths.len() {
            return Err(DecodeError::InvalidLimit {
                field: "syllable constraint lengths",
            });
        }
        if syllables.is_empty() {
            return Ok(DecodeResult {
                candidates: Vec::new(),
                graph_edge_count: 0,
            });
        }
        if syllables.len() > self.limits.max_syllables {
            return Err(DecodeError::TooManySyllables {
                actual: syllables.len(),
                max: self.limits.max_syllables,
            });
        }
        let index = self
            .initial_index
            .get_or_init(|| InitialLexiconIndex::build(&self.lexicon));
        let mut graph_limits = self.limits.clone();
        if fixed_words.len() >= graph_limits.max_edges {
            return Err(DecodeError::InvalidLimit {
                field: "fixed word edge budget",
            });
        }
        graph_limits.max_edges -= fixed_words.len();
        let mut graph = if initials.iter().any(|flag| *flag) {
            SyllableGraph::build_with_initials(
                &self.lexicon,
                syllables,
                initials,
                &graph_limits,
                index,
            )?
        } else {
            SyllableGraph::build(&self.lexicon, syllables, &graph_limits)?
        };
        graph.apply_fixed_words(fixed_words)?;
        let pending_tail =
            raw_lengths.iter().sum::<usize>() < raw_input.chars().filter(|ch| *ch != '\'').count();
        self.decode_graph(&graph, pending_tail, raw_lengths, scoring, &mut user_score)
    }

    fn decode_graph(
        &self,
        graph: &SyllableGraph,
        pending_tail: bool,
        raw_lengths: &[usize],
        scoring: SentenceScoring,
        mut user_score: impl FnMut(&SentenceCandidate) -> i64,
    ) -> Result<DecodeResult, DecodeError> {
        let complete_paths = self.search_complete_paths(graph, pending_tail, scoring);
        let mut candidates = Vec::new();
        let has_clean_complete_path = complete_paths.iter().any(|path| path.fallback_count() == 0);
        for path in complete_paths
            .iter()
            .filter(|path| !has_clean_complete_path || path.fallback_count() == 0)
            .take(self.limits.max_output_paths)
        {
            let complete_coverage =
                path.consumed_syllables() == graph.syllable_count() && !pending_tail;
            candidates.push(SentenceCandidate::from_path(
                path,
                raw_lengths[..path.consumed_syllables()].iter().sum(),
                complete_coverage,
            ));
        }

        candidates.extend(self.prefix_candidates(graph, raw_lengths, scoring));
        let mut candidates = deduplicate_candidates(candidates);
        candidates
            .sort_by(|left, right| compare_candidate_with_user_score(left, right, &mut user_score));
        candidates.truncate(self.limits.max_output_candidates);
        Ok(DecodeResult {
            candidates,
            graph_edge_count: graph.edge_count(),
        })
    }

    fn search_complete_paths(
        &self,
        graph: &SyllableGraph,
        pending_tail: bool,
        scoring: SentenceScoring,
    ) -> Vec<SentencePath> {
        let node_count = graph.syllable_count();
        let mut beams = vec![Vec::<PathState>::new(); node_count + 1];
        beams[0].push(PathState::default());

        for position in 0..node_count {
            let states = beams[position].clone();
            if states.is_empty() {
                continue;
            }
            for state in states {
                for edge in graph.edges_from(position) {
                    let mut next = state.extend(edge.clone(), &self.context_model, scoring);
                    // Broad initial matches must retain word segmentation in
                    // the beam; otherwise high-frequency single characters
                    // crowd out words before the terminal penalty is applied.
                    if !state.edges.is_empty() {
                        next.score -= scoring.extra_word_penalty();
                    }
                    if edge.end == node_count {
                        next.score +=
                            SentenceScorer::terminal_score(next.edges.len(), true, pending_tail);
                    }
                    beams[edge.end].push(next);
                }
            }
            trim_beams(&mut beams, self.limits.beam_width);
        }

        let mut paths = beams[node_count]
            .iter()
            .map(|state| SentencePath {
                edges: state.edges.clone(),
                score: state.score,
            })
            .collect::<Vec<_>>();
        paths.sort_by(compare_path);
        paths.truncate(self.limits.max_output_paths);
        paths
    }

    fn prefix_candidates(
        &self,
        graph: &SyllableGraph,
        raw_lengths: &[usize],
        scoring: SentenceScoring,
    ) -> Vec<SentenceCandidate> {
        let syllable_count = graph.syllable_count();
        if syllable_count < 3 {
            return Vec::new();
        }

        let mut candidates = graph
            .edges_from(0)
            .iter()
            .filter(|edge| !edge.fallback && edge.end < syllable_count)
            // Do not cut a 声声 pair in half: re-pairing its second key with
            // the next syllable would change the untouched input's reading.
            .filter(|edge| raw_lengths[..edge.end].iter().sum::<usize>() % 2 == 0)
            .map(|edge| {
                let score =
                    scoring.edge_score(edge) + SentenceScorer::terminal_score(1, false, false);
                SentenceCandidate::from_prefix_edge(
                    edge,
                    raw_lengths[..edge.end].iter().sum(),
                    score,
                )
            })
            .collect::<Vec<_>>();
        candidates.sort_by(|left, right| {
            right
                .score
                .cmp(&left.score)
                .then_with(|| right.consumed_syllables.cmp(&left.consumed_syllables))
                .then_with(|| left.text.cmp(&right.text))
                .then_with(|| left.reading.cmp(&right.reading))
        });
        candidates
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
struct PathState {
    edges: Vec<WordEdge>,
    score: i64,
}

impl PathState {
    fn extend(
        &self,
        edge: WordEdge,
        context_model: &CharacterBigramModel,
        scoring: SentenceScoring,
    ) -> Self {
        let mut edges = self.edges.clone();
        let transition_score = edges
            .last()
            .map(|previous| context_model.transition_score(&previous.text, &edge.text))
            .unwrap_or(0);
        let score = self.score + scoring.edge_score(&edge) + transition_score;
        edges.push(edge);
        Self { edges, score }
    }
}

fn trim_beams(beams: &mut [Vec<PathState>], beam_width: usize) {
    for states in beams {
        if states.len() <= beam_width {
            continue;
        }
        states.sort_by(|left, right| {
            compare_path_parts(left.score, &left.edges, right.score, &right.edges)
        });
        states.truncate(beam_width);
    }
}

fn compare_candidate_with_user_score(
    left: &SentenceCandidate,
    right: &SentenceCandidate,
    user_score: &mut impl FnMut(&SentenceCandidate) -> i64,
) -> std::cmp::Ordering {
    let left_score = i128::from(left.score) + i128::from(user_score(left));
    let right_score = i128::from(right.score) + i128::from(user_score(right));
    right
        .complete_coverage
        .cmp(&left.complete_coverage)
        .then_with(|| right_score.cmp(&left_score))
        .then_with(|| right.consumed_syllables.cmp(&left.consumed_syllables))
        .then_with(|| left.text.cmp(&right.text))
        .then_with(|| left.reading.cmp(&right.reading))
        .then_with(|| left.path_key.cmp(&right.path_key))
}

#[cfg(test)]
mod tests {
    use lexicon_core::{build_binary_lexicon, load_binary_lexicon, BinaryLexicon, LexiconEntry};

    use super::*;

    #[test]
    fn empty_input_returns_no_candidates() {
        let decoder = sample_decoder();
        let result = decoder.decode("", &[], "").unwrap();

        assert!(result.candidates.is_empty());
        assert_eq!(result.graph_edge_count, 0);
    }

    #[test]
    fn initial_queries_match_words_and_keep_actual_raw_coverage() {
        let decoder = sample_decoder();
        let result = decoder
            .decode_with_initials_and_user_scores(
                "ni'h",
                &syllables(["ni", "h"]),
                &[false, true],
                &[2, 1],
                |_| 0,
            )
            .unwrap();
        assert_eq!(result.candidates[0].text, "你好");
        assert_eq!(result.candidates[0].reading, "ni hao");
        assert_eq!(result.candidates[0].raw_end, 3);
        assert!(result.candidates[0].id.starts_with("sentence:3:"));
        assert!(result.candidates[0].complete_coverage);
        let pending = decoder
            .decode_with_initials_and_user_scores(
                "niha",
                &syllables(["ni", "h"]),
                &[false, true],
                &[2, 1],
                |_| 0,
            )
            .unwrap();
        assert!(!pending.candidates[0].complete_coverage);
        assert_eq!(pending.candidates[0].raw_end, 3);
    }

    #[test]
    fn unresolved_initials_never_become_latin_fallback_candidates() {
        let decoder = sample_decoder();
        let result = decoder
            .decode_with_initials_and_user_scores(
                "niz",
                &syllables(["ni", "z"]),
                &[false, true],
                &[2, 1],
                |_| 0,
            )
            .unwrap();
        assert!(result.candidates.is_empty());
    }

    #[test]
    fn initial_query_validation_and_search_limits_are_preserved() {
        let decoder = sample_decoder();
        assert!(decoder
            .decode_with_initials_and_user_scores("", &[], &[], &[], |_| 0)
            .unwrap()
            .candidates
            .is_empty());
        assert!(matches!(
            decoder.decode_with_initials_and_user_scores("h", &syllables(["h"]), &[], &[1], |_| 0),
            Err(DecodeError::InvalidLimit { .. })
        ));
        assert!(matches!(
            decoder.decode_with_initials_and_user_scores(&"h".repeat(65), &[], &[], &[], |_| 0),
            Err(DecodeError::RawInputTooLong { .. })
        ));
        let long_syllables = vec!["h".to_owned(); 33];
        assert!(matches!(
            decoder.decode_with_initials_and_user_scores(
                &"h".repeat(33),
                &long_syllables,
                &[true; 33],
                &[1; 33],
                |_| 0
            ),
            Err(DecodeError::TooManySyllables { .. })
        ));
        let limits = DecodeLimits {
            max_edges: 2,
            max_output_candidates: 1,
            ..DecodeLimits::default()
        };
        let bounded = SentenceDecoder::new(sample_lexicon(), limits).unwrap();
        let result = bounded
            .decode_with_initials_and_user_scores(
                "nih",
                &syllables(["ni", "h"]),
                &[false, true],
                &[2, 1],
                |_| 0,
            )
            .unwrap();
        assert!(result.graph_edge_count <= 2);
        assert!(result.candidates.len() <= 1);
    }

    #[test]
    fn single_syllable_input_returns_single_word() {
        let decoder = sample_decoder();
        let result = decoder.decode("ni", &syllables(["ni"]), "").unwrap();

        assert_eq!(result.candidates[0].text, "你");
        assert!(result.candidates[0].complete_coverage);
    }

    #[test]
    fn two_syllables_can_form_one_word() {
        let decoder = sample_decoder();
        let result = decoder
            .decode("nihc", &syllables(["ni", "hao"]), "")
            .unwrap();

        assert_eq!(result.candidates[0].text, "你好");
        assert_eq!(result.candidates[0].raw_end, 4);
    }

    #[test]
    fn multi_syllable_phrase_is_preferred_over_segmentation() {
        let decoder = sample_decoder();
        let result = decoder
            .decode("xnheulpb", &syllables(["xiao", "he", "shuang", "pin"]), "")
            .unwrap();

        assert_eq!(result.candidates[0].text, "小鹤双拼");
        assert!(result.candidates.iter().any(|item| item.text == "小鹤"));
    }

    #[test]
    fn same_input_can_return_full_and_partial_candidates() {
        let decoder = sample_decoder();
        let result = decoder
            .decode("uurufa", &syllables(["shu", "ru", "fa"]), "")
            .unwrap();

        assert_eq!(result.candidates[0].text, "输入法");
        assert!(result
            .candidates
            .iter()
            .any(|item| item.text == "输入" && item.raw_end == 4));
    }

    #[test]
    fn complete_coverage_is_ranked_ahead_of_partial_word() {
        let decoder = sample_decoder();
        let result = decoder
            .decode("uurufa", &syllables(["shu", "ru", "fa"]), "")
            .unwrap();

        let full = result
            .candidates
            .iter()
            .position(|item| item.text == "输入法")
            .unwrap();
        let partial = result
            .candidates
            .iter()
            .position(|item| item.text == "输入")
            .unwrap();
        assert!(full < partial);
    }

    #[test]
    fn unknown_fragment_uses_penalized_fallback() {
        let decoder = sample_decoder();
        let result = decoder
            .decode("nixm", &syllables(["ni", "xian"]), "")
            .unwrap();

        assert!(result.candidates[0].text.contains("xian"));
        assert!(result.candidates[0].source.contains("fallback"));
    }

    #[test]
    fn incomplete_tail_is_not_marked_complete() {
        let decoder = sample_decoder();
        let result = decoder.decode("nih", &syllables(["ni"]), "h").unwrap();

        assert_eq!(result.candidates[0].text, "你");
        assert!(!result.candidates[0].complete_coverage);
        assert_eq!(result.candidates[0].raw_end, 2);
    }

    #[test]
    fn text_dedup_keeps_one_sentence_candidate() {
        let decoder = sample_decoder();
        let result = decoder
            .decode("uurufa", &syllables(["shu", "ru", "fa"]), "")
            .unwrap();

        assert_eq!(
            result
                .candidates
                .iter()
                .filter(|item| item.text == "输入法")
                .count(),
            1
        );
    }

    #[test]
    fn path_identity_is_stable_across_repeated_runs() {
        let decoder = sample_decoder();
        let first = decoder
            .decode("xnheulpb", &syllables(["xiao", "he", "shuang", "pin"]), "")
            .unwrap();
        for _ in 0..8 {
            assert_eq!(
                first.candidates,
                decoder
                    .decode("xnheulpb", &syllables(["xiao", "he", "shuang", "pin"]), "")
                    .unwrap()
                    .candidates
            );
        }
    }

    #[test]
    fn tie_breaker_is_stable_for_equal_score_words() {
        let decoder = sample_decoder();
        let result = decoder
            .decode("qijm", &syllables(["qi", "jian"]), "")
            .unwrap();

        assert!(result.candidates.len() >= 2);
        let texts = result
            .candidates
            .iter()
            .take(2)
            .map(|item| item.text.as_str())
            .collect::<Vec<_>>();
        assert_eq!(texts, vec!["其间", "期间"]);
    }

    #[test]
    fn zero_user_scores_preserve_sentence_order() {
        let decoder = sample_decoder();
        let base = decoder
            .decode("qijm", &syllables(["qi", "jian"]), "")
            .unwrap();
        let scored = decoder
            .decode_with_user_scores("qijm", &syllables(["qi", "jian"]), "", |_| 0)
            .unwrap();

        assert_eq!(base.candidates, scored.candidates);
    }

    #[test]
    fn user_score_can_lift_close_sentence_candidate() {
        let decoder = sample_decoder();
        let result = decoder
            .decode_with_user_scores("qijm", &syllables(["qi", "jian"]), "", |candidate| {
                if candidate.text == "期间" {
                    1
                } else {
                    0
                }
            })
            .unwrap();

        assert_eq!(result.candidates[0].text, "期间");
    }

    #[test]
    fn lexicon_derived_character_context_ranks_natural_cross_word_boundaries() {
        let entries = vec![
            entry("你", "ni", 10_000),
            entry("泥", "ni", 10_000),
            entry("好", "hao", 10_000),
            entry("号", "hao", 10_000),
            // This longer phrase contributes the 你→好 context pair without
            // becoming a direct edge for the shorter `ni hao` query.
            entry("你好啊", "ni hao a", 100_000),
        ];
        let bytes = build_binary_lexicon(&entries, 8, 1).expect("build context lexicon");
        let lexicon = load_binary_lexicon(&bytes).expect("load context lexicon");
        let decoder = SentenceDecoder::new(lexicon, DecodeLimits::default()).unwrap();

        let result = decoder
            .decode("nihao", &syllables(["ni", "hao"]), "")
            .unwrap();

        assert_eq!(result.candidates[0].text, "你好");
    }

    #[test]
    fn beam_width_caps_intermediate_paths() {
        let limits = DecodeLimits {
            beam_width: 1,
            ..DecodeLimits::default()
        };
        let decoder = SentenceDecoder::new(sample_lexicon(), limits).unwrap();
        let result = decoder
            .decode("xnheulpb", &syllables(["xiao", "he", "shuang", "pin"]), "")
            .unwrap();

        assert!(!result.candidates.is_empty());
        assert_eq!(decoder.limits().beam_width, 1);
    }

    #[test]
    fn graph_edge_limit_is_respected() {
        let limits = DecodeLimits {
            max_edges: 2,
            ..DecodeLimits::default()
        };
        let decoder = SentenceDecoder::new(sample_lexicon(), limits).unwrap();
        let result = decoder
            .decode("xnheulpb", &syllables(["xiao", "he", "shuang", "pin"]), "")
            .unwrap();

        assert!(result.graph_edge_count <= 2);
    }

    #[test]
    fn raw_input_limit_returns_error() {
        let limits = DecodeLimits {
            max_raw_len: 2,
            ..DecodeLimits::default()
        };
        let decoder = SentenceDecoder::new(sample_lexicon(), limits).unwrap();

        assert_eq!(
            decoder
                .decode("nihc", &syllables(["ni", "hao"]), "")
                .unwrap_err(),
            DecodeError::RawInputTooLong { actual: 4, max: 2 }
        );
    }

    #[test]
    fn syllable_limit_returns_error() {
        let limits = DecodeLimits {
            max_syllables: 1,
            ..DecodeLimits::default()
        };
        let decoder = SentenceDecoder::new(sample_lexicon(), limits).unwrap();

        assert_eq!(
            decoder
                .decode("nihc", &syllables(["ni", "hao"]), "")
                .unwrap_err(),
            DecodeError::TooManySyllables { actual: 2, max: 1 }
        );
    }

    #[test]
    fn invalid_zero_limit_is_rejected() {
        let limits = DecodeLimits {
            beam_width: 0,
            ..DecodeLimits::default()
        };

        assert!(matches!(
            SentenceDecoder::new(sample_lexicon(), limits),
            Err(DecodeError::InvalidLimit {
                field: "beam_width"
            })
        ));
    }

    #[test]
    fn reconfiguring_limits_is_validated_before_mutation() {
        let mut decoder = sample_decoder();
        let original = decoder.limits().clone();
        let invalid = DecodeLimits {
            beam_width: 0,
            ..original.clone()
        };

        assert!(decoder.set_limits(invalid).is_err());
        assert_eq!(decoder.limits(), &original);

        let compact = DecodeLimits {
            beam_width: 4,
            max_output_paths: 4,
            max_output_candidates: 4,
            ..original
        };
        decoder.set_limits(compact.clone()).unwrap();
        assert_eq!(decoder.limits(), &compact);
    }

    fn sample_decoder() -> SentenceDecoder {
        SentenceDecoder::new(sample_lexicon(), DecodeLimits::default()).unwrap()
    }

    fn sample_lexicon() -> BinaryLexicon {
        let entries = vec![
            entry("你", "ni", 100_000),
            entry("好", "hao", 95_000),
            entry("你好", "ni hao", 120_000),
            entry("输", "shu", 20_000),
            entry("入", "ru", 20_000),
            entry("法", "fa", 80_000),
            entry("输入", "shu ru", 82_000),
            entry("输入法", "shu ru fa", 90_000),
            entry("小", "xiao", 50_000),
            entry("鹤", "he", 50_000),
            entry("双", "shuang", 50_000),
            entry("拼", "pin", 50_000),
            entry("小鹤", "xiao he", 85_000),
            entry("双拼", "shuang pin", 84_000),
            entry("小鹤双拼", "xiao he shuang pin", 88_000),
            entry("期间", "qi jian", 70_000),
            entry("其间", "qi jian", 70_000),
        ];
        let bytes = build_binary_lexicon(&entries, 8, 1).unwrap();
        load_binary_lexicon(&bytes).unwrap()
    }

    fn entry(word: &str, pinyin: &str, frequency: u64) -> LexiconEntry {
        LexiconEntry::new(
            word.to_owned(),
            pinyin.to_owned(),
            pinyin.split(' ').map(str::to_owned).collect(),
            frequency,
            vec!["stage8".to_owned()],
        )
    }

    fn syllables<const N: usize>(items: [&str; N]) -> Vec<String> {
        items.iter().map(|item| (*item).to_owned()).collect()
    }
}
