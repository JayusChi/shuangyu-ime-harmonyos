use crate::error::SyllableError;
use crate::inventory;

/// Normalizes a tone-less pinyin syllable and verifies it against the maintained
/// Mandarin syllable set.
///
/// ASCII uppercase input is accepted and converted to lowercase. Unicode
/// diaeresis forms (`u` with diaeresis) are converted to the engine's ASCII `v`
/// convention before final pinyin spelling normalization is applied.
pub fn normalize_syllable(input: &str) -> Result<String, SyllableError> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err(SyllableError::Empty);
    }

    let mut ascii = String::with_capacity(trimmed.len());
    for ch in trimmed.chars() {
        match ch {
            'a'..='z' => ascii.push(ch),
            'A'..='Z' => ascii.push(ch.to_ascii_lowercase()),
            'ü' | 'ǖ' | 'ǘ' | 'ǚ' | 'ǜ' | 'Ü' | 'Ǖ' | 'Ǘ' | 'Ǚ' | 'Ǜ' => ascii.push('v'),
            _ => return Err(SyllableError::InvalidCharacter { ch }),
        }
    }

    let normalized = normalize_v_after_jqxy(&ascii);
    if inventory::contains(&normalized) {
        Ok(normalized)
    } else {
        Err(SyllableError::InvalidSyllable {
            syllable: normalized,
        })
    }
}

/// Returns true when `input` can be normalized to a maintained Mandarin pinyin
/// syllable.
pub fn is_valid_syllable(input: &str) -> bool {
    normalize_syllable(input).is_ok()
}

fn normalize_v_after_jqxy(input: &str) -> String {
    for prefix in ["j", "q", "x", "y"] {
        if let Some(rest) = input.strip_prefix(prefix) {
            if let Some(after_v) = rest.strip_prefix('v') {
                return format!("{prefix}u{after_v}");
            }
        }
    }
    input.to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_uppercase_by_normalizing() {
        assert_eq!(normalize_syllable("ZHONG"), Ok("zhong".to_owned()));
    }

    #[test]
    fn normalizes_v_and_diaeresis() {
        assert_eq!(normalize_syllable("jv"), Ok("ju".to_owned()));
        assert_eq!(normalize_syllable("qüe"), Ok("que".to_owned()));
        assert_eq!(normalize_syllable("nü"), Ok("nv".to_owned()));
        assert_eq!(normalize_syllable("lüe"), Ok("lve".to_owned()));
    }

    #[test]
    fn rejects_invalid_values() {
        assert_eq!(normalize_syllable(""), Err(SyllableError::Empty));
        assert!(matches!(
            normalize_syllable("b@"),
            Err(SyllableError::InvalidCharacter { ch: '@' })
        ));
        assert!(matches!(
            normalize_syllable("biong"),
            Err(SyllableError::InvalidSyllable { .. })
        ));
    }
}
