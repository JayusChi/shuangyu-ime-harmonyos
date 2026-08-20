use pinyin_syllable::normalize_syllable;

use crate::error::LineErrorReason;

pub const MAX_SYLLABLES: usize = 32;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NormalizedPinyin {
    pub key: String,
    pub syllables: Vec<String>,
}

pub fn normalize_pinyin(input: &str) -> Result<NormalizedPinyin, LineErrorReason> {
    let collapsed = input.split_whitespace().collect::<Vec<_>>().join(" ");
    if collapsed.is_empty() {
        return Err(LineErrorReason::EmptyPinyin);
    }

    let mut syllables = Vec::new();
    for (index, raw) in collapsed.split(' ').enumerate() {
        let prepared = raw.replace("U:", "v").replace("u:", "v");
        match normalize_syllable(&prepared) {
            Ok(normalized) => syllables.push(normalized),
            Err(error) => {
                return Err(LineErrorReason::InvalidPinyinSyllable {
                    syllable: raw.to_owned(),
                    index: index + 1,
                    detail: error.to_string(),
                })
            }
        }
    }

    if syllables.len() > MAX_SYLLABLES {
        return Err(LineErrorReason::TooManySyllables {
            actual: syllables.len(),
            max: MAX_SYLLABLES,
        });
    }

    Ok(NormalizedPinyin {
        key: syllables.join(" "),
        syllables,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_case_spaces_and_diaeresis_forms() {
        let normalized = normalize_pinyin(" NI   HAO ").unwrap();
        assert_eq!(normalized.key, "ni hao");

        assert_eq!(normalize_pinyin("nü").unwrap().key, "nv");
        assert_eq!(normalize_pinyin("lu:").unwrap().key, "lv");
        assert_eq!(normalize_pinyin("jv").unwrap().key, "ju");
    }

    #[test]
    fn rejects_invalid_syllable_with_index() {
        assert!(matches!(
            normalize_pinyin("shu ru invalid"),
            Err(LineErrorReason::InvalidPinyinSyllable { index: 3, .. })
        ));
    }
}
