use crate::graph::WordEdge;

const COMPLETE_COVERAGE_BONUS: i64 = 1_200;
const PENDING_TAIL_PENALTY: i64 = 600;
const EXTRA_WORD_PENALTY: i64 = 180;
const FALLBACK_EDGE_PENALTY: i64 = 3_500;
const MULTI_SYLLABLE_BONUS: i64 = 520;

/// Scores sentence paths independently from the stage 7 candidate ranker.
#[derive(Clone, Debug, Default)]
pub struct SentenceScorer;

#[derive(Clone, Copy)]
pub(crate) enum SentenceScoring {
    Standard,
    Initials,
    Xiaohe,
}

impl SentenceScoring {
    pub(crate) fn edge_score(self, edge: &WordEdge) -> i64 {
        if !matches!(self, Self::Xiaohe) || edge.fallback {
            return SentenceScorer::edge_score(edge);
        }
        // A bounded log-frequency cost per word avoids giving a rare long
        // dictionary entry a quadratic advantage over common shorter words.
        // The linear coverage term is constant for every complete path.
        let frequency = edge.frequency.clamp(1, 1_000_000);
        let magnitude = frequency.ilog2();
        let base = 1_u64 << magnitude;
        let fraction = ((frequency - base) * 100 / base) as i64;
        i64::from(magnitude) * 100 + fraction - 2_000
            + edge.syllable_count as i64 * MULTI_SYLLABLE_BONUS
    }

    pub(crate) fn extra_word_penalty(self) -> i64 {
        if matches!(self, Self::Initials) {
            1_400
        } else {
            0
        }
    }
}

impl SentenceScorer {
    pub fn edge_score(edge: &WordEdge) -> i64 {
        if edge.fallback {
            return -FALLBACK_EDGE_PENALTY;
        }

        frequency_points(edge.frequency)
            + ((edge.syllable_count * edge.syllable_count) as i64 * MULTI_SYLLABLE_BONUS)
    }

    pub fn terminal_score(edge_count: usize, complete_coverage: bool, pending_tail: bool) -> i64 {
        let mut score = 0;
        if complete_coverage {
            score += COMPLETE_COVERAGE_BONUS;
        }
        if pending_tail {
            score -= PENDING_TAIL_PENALTY;
        }
        if edge_count > 1 {
            score -= (edge_count - 1) as i64 * EXTRA_WORD_PENALTY;
        }
        score
    }
}

fn frequency_points(frequency: u64) -> i64 {
    if frequency == 0 {
        return 0;
    }
    let capped = frequency.min(1_000_000);
    let magnitude = capped.ilog10() as i64 + 1;
    let bucket = (capped / 1_000).min(900) as i64;
    magnitude * 70 + bucket
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn multi_syllable_edge_gets_independent_bonus() {
        let single = edge("你", "ni", 1, 100_000, false);
        let word = edge("你好", "ni hao", 2, 80_000, false);

        assert!(SentenceScorer::edge_score(&word) > SentenceScorer::edge_score(&single));
    }

    #[test]
    fn fallback_edges_are_penalized() {
        let known = edge("你", "ni", 1, 1, false);
        let fallback = edge("xian", "xian", 1, 0, true);

        assert!(SentenceScorer::edge_score(&fallback) < SentenceScorer::edge_score(&known));
    }

    #[test]
    fn xiaohe_retains_frequency_order_within_a_logarithmic_bucket() {
        let common = edge("期间", "qi jian", 2, 50_000, false);
        let less_common = edge("其间", "qi jian", 2, 49_000, false);
        assert!(
            SentenceScoring::Xiaohe.edge_score(&common)
                > SentenceScoring::Xiaohe.edge_score(&less_common)
        );
    }

    fn edge(
        text: &str,
        reading: &str,
        syllable_count: usize,
        frequency: u64,
        fallback: bool,
    ) -> WordEdge {
        WordEdge {
            entry_id: text.to_owned(),
            text: text.to_owned(),
            reading: reading.to_owned(),
            start: 0,
            end: syllable_count,
            syllable_count,
            frequency,
            source: "stage8".to_owned(),
            fallback,
        }
    }
}
