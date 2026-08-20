use crate::graph::WordEdge;

const COMPLETE_COVERAGE_BONUS: i64 = 1_200;
const PENDING_TAIL_PENALTY: i64 = 600;
const EXTRA_WORD_PENALTY: i64 = 180;
const FALLBACK_EDGE_PENALTY: i64 = 3_500;
const MULTI_SYLLABLE_BONUS: i64 = 520;

/// Scores sentence paths independently from the stage 7 candidate ranker.
#[derive(Clone, Debug, Default)]
pub struct SentenceScorer;

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
