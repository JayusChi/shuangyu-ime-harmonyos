use crate::version::{MAX_ACTION_ARGUMENT_CHARS, MAX_PRODUCTION_CODE_LEN, MAX_WORD_CHARS};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TextError {
    Empty,
    TooLong,
    Control,
    Delimiter,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct TextFeatures {
    pub cjk_extension: bool,
    pub emoji_or_special: bool,
}

pub fn validate_word(value: &str) -> Result<TextFeatures, TextError> {
    if value.is_empty() {
        return Err(TextError::Empty);
    }
    if value.chars().count() > MAX_WORD_CHARS {
        return Err(TextError::TooLong);
    }
    if value.contains(['\t', '\n', '\r']) {
        return Err(TextError::Delimiter);
    }
    if value.chars().any(is_forbidden_control) {
        return Err(TextError::Control);
    }
    let mut features = TextFeatures::default();
    for ch in value.chars() {
        features.cjk_extension |= is_cjk_extension(ch);
        features.emoji_or_special |= is_emoji_or_special(ch);
    }
    Ok(features)
}

pub fn normalize_code(value: &str) -> Result<(String, bool), &'static str> {
    if value.is_empty() {
        return Err("YX_CODE_EMPTY");
    }
    if value.len() > MAX_PRODUCTION_CODE_LEN {
        return Err("YX_CODE_TOO_LONG");
    }
    if !value.bytes().all(|byte| byte.is_ascii_alphabetic()) {
        return Err("YX_CODE_INVALID_CHARACTER");
    }
    let normalized = value.to_ascii_lowercase();
    let changed = normalized != value;
    Ok((normalized, changed))
}

pub fn validate_action_argument(value: &str) -> Result<(), TextError> {
    if value.chars().count() > MAX_ACTION_ARGUMENT_CHARS {
        return Err(TextError::TooLong);
    }
    if value.chars().any(is_forbidden_control) {
        return Err(TextError::Control);
    }
    Ok(())
}

pub fn is_forbidden_control(ch: char) -> bool {
    ch == '\0' || ch.is_control()
}

fn is_cjk_extension(ch: char) -> bool {
    matches!(
        ch as u32,
        0x3400..=0x4DBF
            | 0x20000..=0x2A6DF
            | 0x2A700..=0x2B73F
            | 0x2B740..=0x2B81F
            | 0x2B820..=0x2CEAF
            | 0x2CEB0..=0x2EBEF
            | 0x30000..=0x3134F
    )
}

fn is_emoji_or_special(ch: char) -> bool {
    let value = ch as u32;
    matches!(value, 0x1F000..=0x1FAFF | 0xFE00..=0xFE0F | 0x200D)
        || (0x300..=0x36F).contains(&value)
        || (!ch.is_ascii_alphanumeric()
            && !('\u{3400}'..='\u{9FFF}').contains(&ch)
            && !is_cjk_extension(ch))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_extensions_emoji_variants_joiners_and_combining_text() {
        assert!(validate_word("𩽾").unwrap().cjk_extension);
        assert!(validate_word("😀").unwrap().emoji_or_special);
        assert!(validate_word("❤️").unwrap().emoji_or_special);
        assert!(validate_word("👨‍👩‍👧").unwrap().emoji_or_special);
        assert!(validate_word("e\u{301}").unwrap().emoji_or_special);
        assert!(validate_word("（）").unwrap().emoji_or_special);
    }

    #[test]
    fn rejects_delimiters_controls_and_scalar_length_overflow() {
        for value in ["", "a\tb", "a\nb", "a\0b", "a\u{0085}b"] {
            assert!(validate_word(value).is_err());
        }
        assert!(validate_word(&"𩽾".repeat(MAX_WORD_CHARS + 1)).is_err());
        assert_eq!(normalize_code("AbCd").unwrap(), ("abcd".to_owned(), true));
        assert!(normalize_code("abcde").is_err());
    }
}
