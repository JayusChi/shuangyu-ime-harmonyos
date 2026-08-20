use std::cmp::Ordering;

use crate::{
    deduplicate_candidates, deduplicate_candidates_stable, CandidateOrder, RankingCandidate,
};

/// Applies the explicitly selected candidate ordering policy.
pub fn rank_candidates_with_order(
    candidates: Vec<RankingCandidate>,
    order: CandidateOrder,
) -> Vec<RankingCandidate> {
    match order {
        CandidateOrder::ExistingRanking => rank_candidates(candidates),
        CandidateOrder::SourceOrder => rank_candidates_by_source_order(candidates),
    }
}

/// Orders code-table candidates by their persisted source row before deduplication.
pub fn rank_candidates_by_source_order(
    mut candidates: Vec<RankingCandidate>,
) -> Vec<RankingCandidate> {
    candidates.sort_by(|left, right| {
        left.source_order
            .cmp(&right.source_order)
            .then_with(|| left.id.cmp(&right.id))
    });
    deduplicate_candidates_stable(candidates)
}

/// Ranks candidates with the stage 7 deterministic policy.
pub fn rank_candidates(candidates: Vec<RankingCandidate>) -> Vec<RankingCandidate> {
    let mut ranked = deduplicate_candidates(candidates);
    ranked.sort_by(compare_candidates);
    ranked
}

/// Ranks candidates with a bounded user score supplied by the caller.
///
/// A zero score for every candidate produces the same order as `rank_candidates`.
pub fn rank_candidates_with_user_scores(
    candidates: Vec<RankingCandidate>,
    mut user_score: impl FnMut(&RankingCandidate) -> i64,
) -> Vec<RankingCandidate> {
    let mut ranked = deduplicate_candidates(candidates);
    ranked.sort_by(|left, right| compare_candidates_with_user_scores(left, right, &mut user_score));
    ranked
}

/// Ranks candidates for a broad single-key or incomplete-prefix query.
///
/// This profile is deliberately separate from exact-query ranking. It keeps
/// match type and lexicon frequency authoritative while applying bounded,
/// deterministic quality penalties to long and single-character-repetition
/// candidates.
pub fn rank_prefix_candidates(candidates: Vec<RankingCandidate>) -> Vec<RankingCandidate> {
    let mut ranked = deduplicate_candidates(candidates);
    ranked.sort_by(compare_prefix_candidates);
    ranked
}

/// Applies bounded user learning to the complete deduplicated prefix pool
/// before the caller truncates the stable candidate snapshot.
pub fn rank_prefix_candidates_with_user_scores(
    candidates: Vec<RankingCandidate>,
    mut user_score: impl FnMut(&RankingCandidate) -> i64,
) -> Vec<RankingCandidate> {
    let mut ranked = deduplicate_candidates(candidates);
    ranked.sort_by(|left, right| {
        compare_prefix_candidates_with_user_scores(left, right, &mut user_score)
    });
    ranked
}

/// Comparator kept public so tests and future modules can audit the policy.
pub fn compare_candidates(left: &RankingCandidate, right: &RankingCandidate) -> Ordering {
    left.match_type
        .cmp(&right.match_type)
        .then_with(|| right.frequency.cmp(&left.frequency))
        .then_with(|| left.text.cmp(&right.text))
        .then_with(|| left.reading.cmp(&right.reading))
        .then_with(|| left.source.cmp(&right.source))
        .then_with(|| left.id.cmp(&right.id))
}

/// Comparator for broad prefix queries. Exactness remains the hard boundary;
/// the quality score is then followed by raw frequency and stable fields.
pub fn compare_prefix_candidates(left: &RankingCandidate, right: &RankingCandidate) -> Ordering {
    left.match_type
        .cmp(&right.match_type)
        .then_with(|| prefix_quality_score(right).cmp(&prefix_quality_score(left)))
        .then_with(|| right.frequency.cmp(&left.frequency))
        .then_with(|| left.text.cmp(&right.text))
        .then_with(|| left.reading.cmp(&right.reading))
        .then_with(|| left.source.cmp(&right.source))
        .then_with(|| left.id.cmp(&right.id))
}

/// Returns the auditable system score used only by broad prefix queries.
///
/// One- and two-character candidates keep their source frequency. Three
/// characters use a 2x divisor and four or more use a capped 8x divisor.
/// Candidates made from one repeated character receive one additional capped
/// 8x divisor. No candidate is filtered, and the penalty does not grow without
/// bound as text becomes longer.
pub fn prefix_quality_score(candidate: &RankingCandidate) -> u64 {
    let mut characters = candidate.text.chars();
    let first = characters.next();
    let mut character_count = usize::from(first.is_some());
    let mut repeats_one_character = first.is_some();
    for character in characters {
        character_count = character_count.saturating_add(1);
        if Some(character) != first {
            repeats_one_character = false;
        }
    }

    let length_divisor = match character_count {
        0..=2 => 1_u64,
        3 => 2,
        _ => 8,
    };
    let repetition_divisor = if character_count >= 2 && repeats_one_character {
        8_u64
    } else {
        1
    };
    candidate
        .frequency
        .checked_div(length_divisor.saturating_mul(repetition_divisor))
        .unwrap_or(0)
}

fn compare_candidates_with_user_scores(
    left: &RankingCandidate,
    right: &RankingCandidate,
    user_score: &mut impl FnMut(&RankingCandidate) -> i64,
) -> Ordering {
    let left_score = i128::from(left.frequency) + i128::from(user_score(left));
    let right_score = i128::from(right.frequency) + i128::from(user_score(right));
    left.match_type
        .cmp(&right.match_type)
        .then_with(|| right_score.cmp(&left_score))
        .then_with(|| left.text.cmp(&right.text))
        .then_with(|| left.reading.cmp(&right.reading))
        .then_with(|| left.source.cmp(&right.source))
        .then_with(|| left.id.cmp(&right.id))
}

fn compare_prefix_candidates_with_user_scores(
    left: &RankingCandidate,
    right: &RankingCandidate,
    user_score: &mut impl FnMut(&RankingCandidate) -> i64,
) -> Ordering {
    let left_score = i128::from(prefix_quality_score(left)) + i128::from(user_score(left));
    let right_score = i128::from(prefix_quality_score(right)) + i128::from(user_score(right));
    left.match_type
        .cmp(&right.match_type)
        .then_with(|| right_score.cmp(&left_score))
        .then_with(|| right.frequency.cmp(&left.frequency))
        .then_with(|| left.text.cmp(&right.text))
        .then_with(|| left.reading.cmp(&right.reading))
        .then_with(|| left.source.cmp(&right.source))
        .then_with(|| left.id.cmp(&right.id))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::CandidateMatchType;

    fn candidate(
        id: &str,
        text: &str,
        reading: &str,
        source: &str,
        frequency: u64,
        match_type: CandidateMatchType,
    ) -> RankingCandidate {
        RankingCandidate::new(id, text, reading, source, frequency, match_type)
    }

    #[test]
    fn exact_match_ranks_before_prefix_match() {
        let ranked = rank_candidates(vec![
            candidate(
                "prefix",
                "你好",
                "ni hao",
                "stage",
                999,
                CandidateMatchType::Prefix,
            ),
            candidate("exact", "你", "ni", "stage", 1, CandidateMatchType::Exact),
        ]);

        assert_eq!(ranked[0].text, "你");
    }

    #[test]
    fn higher_base_frequency_ranks_first() {
        let ranked = rank_candidates(vec![
            candidate(
                "low",
                "其间",
                "qi jian",
                "stage",
                10,
                CandidateMatchType::Exact,
            ),
            candidate(
                "high",
                "期间",
                "qi jian",
                "stage",
                20,
                CandidateMatchType::Exact,
            ),
        ]);

        assert_eq!(ranked[0].text, "期间");
    }

    #[test]
    fn equal_scores_use_stable_tie_breakers() {
        let left = vec![
            candidate("b", "乙", "yi", "b", 10, CandidateMatchType::Exact),
            candidate("a", "甲", "yi", "a", 10, CandidateMatchType::Exact),
        ];
        let right = vec![
            candidate("a", "甲", "yi", "a", 10, CandidateMatchType::Exact),
            candidate("b", "乙", "yi", "b", 10, CandidateMatchType::Exact),
        ];

        assert_eq!(rank_candidates(left), rank_candidates(right.clone()));
        assert_eq!(rank_candidates(right)[0].text, "乙");
    }

    #[test]
    fn same_text_different_reading_is_not_deduplicated() {
        let ranked = rank_candidates(vec![
            candidate("a", "行", "xing", "stage", 10, CandidateMatchType::Exact),
            candidate("b", "行", "hang", "stage", 10, CandidateMatchType::Exact),
        ]);

        assert_eq!(ranked.len(), 2);
    }

    #[test]
    fn same_text_and_reading_is_deduplicated() {
        let ranked = rank_candidates(vec![
            candidate("a", "你", "ni", "alpha", 10, CandidateMatchType::Exact),
            candidate("b", "你", "ni", "beta", 20, CandidateMatchType::Exact),
        ]);

        assert_eq!(ranked.len(), 1);
        assert_eq!(ranked[0].frequency, 20);
        assert_eq!(ranked[0].source, "alpha,beta");
    }

    #[test]
    fn repeated_runs_are_identical() {
        let input = vec![
            candidate("c", "三", "san", "stage", 3, CandidateMatchType::Exact),
            candidate("a", "一", "yi", "stage", 1, CandidateMatchType::Exact),
            candidate("b", "二", "er", "stage", 2, CandidateMatchType::Exact),
        ];

        let first = rank_candidates(input.clone());
        for _ in 0..16 {
            assert_eq!(first, rank_candidates(input.clone()));
        }
    }

    #[test]
    fn zero_user_scores_preserve_base_order() {
        let input = vec![
            candidate("b", "乙", "yi", "stage", 10, CandidateMatchType::Exact),
            candidate("a", "甲", "yi", "stage", 11, CandidateMatchType::Exact),
        ];

        assert_eq!(
            rank_candidates(input.clone()),
            rank_candidates_with_user_scores(input, |_| 0)
        );
    }

    #[test]
    fn source_order_policy_sorts_before_stable_deduplication() {
        let ranked = rank_candidates_with_order(
            vec![
                candidate(
                    "third",
                    "第三词",
                    "abz",
                    "table",
                    999,
                    CandidateMatchType::Prefix,
                )
                .with_source_order(2),
                candidate(
                    "first",
                    "第一词",
                    "abz",
                    "table",
                    1,
                    CandidateMatchType::Prefix,
                )
                .with_source_order(0),
                candidate(
                    "duplicate",
                    "第一词",
                    "abz",
                    "other",
                    2,
                    CandidateMatchType::Prefix,
                )
                .with_source_order(3),
                candidate(
                    "second",
                    "第二词",
                    "aba",
                    "table",
                    5,
                    CandidateMatchType::Prefix,
                )
                .with_source_order(1),
            ],
            CandidateOrder::SourceOrder,
        );

        assert_eq!(
            ranked
                .iter()
                .map(|item| item.text.as_str())
                .collect::<Vec<_>>(),
            vec!["第一词", "第二词", "第三词"]
        );
        assert_eq!(ranked[0].source_order, 0);
    }

    #[test]
    fn repeated_user_selection_can_lift_close_candidate() {
        let ranked = rank_candidates_with_user_scores(
            vec![
                candidate("a", "甲", "yi", "stage", 10_000, CandidateMatchType::Exact),
                candidate("b", "乙", "yi", "stage", 9_000, CandidateMatchType::Exact),
            ],
            |candidate| if candidate.id == "b" { 1_500 } else { 0 },
        );

        assert_eq!(ranked[0].id, "b");
    }

    #[test]
    fn user_weight_does_not_cross_match_type_boundary() {
        let ranked = rank_candidates_with_user_scores(
            vec![
                candidate("exact", "你", "ni", "stage", 1, CandidateMatchType::Exact),
                candidate(
                    "prefix",
                    "你好",
                    "ni hao",
                    "stage",
                    1,
                    CandidateMatchType::Prefix,
                ),
            ],
            |candidate| if candidate.id == "prefix" { 5_000 } else { 0 },
        );

        assert_eq!(ranked[0].id, "exact");
    }

    #[test]
    fn prefix_quality_is_isolated_from_exact_ranking() {
        let input = vec![
            candidate(
                "long",
                "异常业务短语",
                "hui fu ri qi",
                "stage",
                80_000,
                CandidateMatchType::Prefix,
            ),
            candidate(
                "short",
                "回复",
                "hui fu",
                "stage",
                20_000,
                CandidateMatchType::Prefix,
            ),
        ];

        assert_eq!(rank_candidates(input.clone())[0].id, "long");
        assert_eq!(rank_prefix_candidates(input)[0].id, "short");
    }

    #[test]
    fn prefix_quality_penalty_is_bounded_and_does_not_filter_long_words() {
        let long = candidate(
            "long",
            "高频常用四字词",
            "gao pin chang yong",
            "stage",
            800_000,
            CandidateMatchType::Prefix,
        );
        let short = candidate(
            "short",
            "短词",
            "duan ci",
            "stage",
            90_000,
            CandidateMatchType::Prefix,
        );

        assert_eq!(prefix_quality_score(&long), 100_000);
        assert_eq!(rank_prefix_candidates(vec![short, long])[0].id, "long");
    }

    #[test]
    fn repeated_interjection_gets_an_auxiliary_prefix_penalty() {
        let repeated = candidate(
            "repeated",
            "哈哈",
            "ha ha",
            "stage",
            80_000,
            CandidateMatchType::Prefix,
        );
        let common = candidate(
            "common",
            "回来",
            "hui lai",
            "stage",
            20_000,
            CandidateMatchType::Prefix,
        );

        assert_eq!(prefix_quality_score(&repeated), 10_000);
        assert_eq!(
            rank_prefix_candidates(vec![repeated, common])[0].id,
            "common"
        );
    }

    #[test]
    fn prefix_user_learning_is_applied_before_stable_tie_breakers() {
        let input = vec![
            candidate(
                "first",
                "甲词",
                "jia ci",
                "stage",
                10_000,
                CandidateMatchType::Prefix,
            ),
            candidate(
                "learned",
                "乙词",
                "yi ci",
                "stage",
                9_000,
                CandidateMatchType::Prefix,
            ),
        ];

        let ranked = rank_prefix_candidates_with_user_scores(input, |candidate| {
            if candidate.id == "learned" {
                1_500
            } else {
                0
            }
        });

        assert_eq!(ranked[0].id, "learned");
    }
}
