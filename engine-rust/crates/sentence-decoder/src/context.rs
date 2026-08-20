use std::collections::HashMap;

use lexicon_core::BinaryLexicon;

const MAX_ENTRY_WEIGHT: u64 = 100_000;
const MAGNITUDE_POINTS: i64 = 45;
const BUCKET_DIVISOR: u64 = 5_000;
const MAX_BUCKET_POINTS: u64 = 180;

/// A compact character-bigram model derived deterministically from the
/// multi-character entries already present in the production lexicon.
///
/// The score is used only at boundaries between decoder edges. An entry's own
/// internal character sequence is already represented by its lexicon frequency
/// and multi-syllable bonus, so scoring it again would double count evidence.
#[derive(Clone, Debug, Default)]
pub(crate) struct CharacterBigramModel {
    weights: HashMap<(char, char), u64>,
}

impl CharacterBigramModel {
    pub(crate) fn from_lexicon(lexicon: &BinaryLexicon) -> Self {
        let mut weights = HashMap::new();
        for entry in &lexicon.entries {
            let contribution = entry.frequency.clamp(1, MAX_ENTRY_WEIGHT);
            let mut characters = entry.word.chars();
            let Some(mut previous) = characters.next() else {
                continue;
            };
            for current in characters {
                let weight = weights.entry((previous, current)).or_insert(0_u64);
                *weight = weight.saturating_add(contribution);
                previous = current;
            }
        }
        Self { weights }
    }

    pub(crate) fn transition_score(&self, previous: &str, next: &str) -> i64 {
        let Some(left) = previous.chars().next_back() else {
            return 0;
        };
        let Some(right) = next.chars().next() else {
            return 0;
        };
        let Some(weight) = self.weights.get(&(left, right)).copied() else {
            return 0;
        };
        let magnitude = weight.ilog10() as i64 + 1;
        let bucket = (weight / BUCKET_DIVISOR).min(MAX_BUCKET_POINTS) as i64;
        magnitude * MAGNITUDE_POINTS + bucket
    }
}

#[cfg(test)]
mod tests {
    use lexicon_core::{build_binary_lexicon, load_binary_lexicon, LexiconEntry};

    use super::*;

    #[test]
    fn learns_adjacent_characters_without_scoring_unseen_pairs() {
        let entry = LexiconEntry::new(
            "你好啊".to_owned(),
            "ni hao a".to_owned(),
            vec!["ni".to_owned(), "hao".to_owned(), "a".to_owned()],
            50_000,
            vec!["test".to_owned()],
        );
        let bytes = build_binary_lexicon(&[entry], 1, 1).expect("build lexicon");
        let lexicon = load_binary_lexicon(&bytes).expect("load lexicon");
        let model = CharacterBigramModel::from_lexicon(&lexicon);

        assert!(model.transition_score("你", "好") > 0);
        assert!(model.transition_score("好", "啊") > 0);
        assert_eq!(model.transition_score("你", "啊"), 0);
    }
}
