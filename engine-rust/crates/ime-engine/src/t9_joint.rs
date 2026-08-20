use sentence_decoder::{T9JointLimits, T9JointStats};
use shuangpin_parser::T9LatticeStats;
use std::collections::BTreeSet;

/// Blends language-ranked paths with the parser's deterministic prior. A
/// bounded promotion lane lets lexicon-backed paths cross the old 32-path
/// boundary, while the parser reserve prevents a noisy joint beam from
/// replacing the entire public surface in one update.
pub(crate) fn merge_ranked_paths(
    parser_paths: &[String],
    joint_paths: &[String],
    public_limit: usize,
    joint_promotions: usize,
) -> Vec<String> {
    let mut merged = Vec::new();
    let mut seen = BTreeSet::new();
    for path in joint_paths.iter().take(joint_promotions) {
        if seen.insert(path.clone()) {
            merged.push(path.clone());
        }
    }
    for path in parser_paths {
        if merged.len() >= public_limit {
            break;
        }
        if seen.insert(path.clone()) {
            merged.push(path.clone());
        }
    }
    for path in joint_paths.iter().skip(joint_promotions) {
        if seen.insert(path.clone()) {
            merged.push(path.clone());
        }
    }
    for path in parser_paths {
        if seen.insert(path.clone()) {
            merged.push(path.clone());
        }
    }
    merged
}

/// Per-key diagnostics for the pinyin-9 joint decoder. Path lists are bounded
/// by `limits.max_diagnostic_paths` and exist only for evaluation/attribution;
/// they never alter candidate ordering.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct T9JointDecoderStats {
    pub explored_pinyin_hypotheses: usize,
    pub max_beam_states: usize,
    pub lexicon_prefix_unreachable_prunes: usize,
    pub pinyin_invalid_prunes: usize,
    pub joint_score_prunes: usize,
    pub beam_capacity_prunes: usize,
    pub candidate_output_limit_prunes: usize,
    pub parser_internal_hypotheses: usize,
    pub graph_edges: usize,
    pub peak_estimated_bytes: usize,
    pub input_limit_hit: bool,
    pub parser_generated_paths: Vec<String>,
    pub lexicon_reachable_paths: Vec<String>,
    pub joint_beam_pruned_paths: Vec<String>,
    pub ranked_internal_paths: Vec<String>,
}

impl T9JointDecoderStats {
    pub(crate) fn merge(
        parser: T9LatticeStats,
        joint: T9JointStats,
        parser_generated_paths: Vec<String>,
        lexicon_reachable_paths: Vec<String>,
        joint_beam_pruned_paths: Vec<String>,
        ranked_internal_paths: Vec<String>,
        limits: &T9JointLimits,
    ) -> Self {
        let cap = limits.max_diagnostic_paths;
        Self {
            explored_pinyin_hypotheses: joint.explored_pinyin_hypotheses,
            max_beam_states: joint.max_beam_states,
            lexicon_prefix_unreachable_prunes: joint.lexicon_prefix_unreachable_prunes,
            pinyin_invalid_prunes: parser.invalid_syllable_prunes,
            joint_score_prunes: joint.joint_score_prunes,
            beam_capacity_prunes: parser
                .beam_capacity_prunes
                .saturating_add(joint.beam_capacity_prunes),
            candidate_output_limit_prunes: joint.output_limit_prunes,
            parser_internal_hypotheses: parser.internal_hypotheses,
            graph_edges: joint.graph_edges,
            peak_estimated_bytes: joint.peak_estimated_bytes,
            input_limit_hit: parser.input_limit_hit,
            parser_generated_paths: parser_generated_paths.into_iter().take(cap).collect(),
            lexicon_reachable_paths: lexicon_reachable_paths.into_iter().take(cap).collect(),
            joint_beam_pruned_paths: joint_beam_pruned_paths.into_iter().take(cap).collect(),
            ranked_internal_paths: ranked_internal_paths.into_iter().take(cap).collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::merge_ranked_paths;

    #[test]
    fn merge_reserves_parser_paths_and_promotes_joint_paths() {
        let parser = (0..40)
            .map(|i| format!("parser-{i:02}"))
            .collect::<Vec<_>>();
        let joint = vec!["joint-a".to_owned(), "joint-b".to_owned()];

        let merged = merge_ranked_paths(&parser, &joint, 32, 8);

        assert_eq!(&merged[..2], joint.as_slice());
        assert_eq!(merged[2], "parser-00");
        assert_eq!(merged[31], "parser-29");
        assert!(merged.contains(&"parser-39".to_owned()));
    }
}
