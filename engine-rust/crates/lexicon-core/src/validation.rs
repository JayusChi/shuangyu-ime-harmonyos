//! Shared validation for text code-table importers.

/// Maximum number of lowercase ASCII bytes in a code.
pub const MAX_CODE_LEN: usize = 64;
/// Maximum number of CJK characters in a word.
pub const MAX_WORD_CHARS: usize = 32;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CodeValidationError {
    Empty,
    Invalid,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum WordValidationError {
    Empty,
    TooLong { actual: usize, max: usize },
    UnsupportedCharacter(char),
}

/// Validates an offline system code-table entry.
///
/// The synthetic system fixture may use ASCII labels and a frozen symbol set.
/// This remains separate from `validate_word`, so user lexicons retain their
/// existing CJK-only contract.
pub fn validate_system_table_word(word: &str) -> Result<(), WordValidationError> {
    if word.is_empty() {
        return Err(WordValidationError::Empty);
    }
    let char_count = word.chars().count();
    if char_count > MAX_WORD_CHARS {
        return Err(WordValidationError::TooLong {
            actual: char_count,
            max: MAX_WORD_CHARS,
        });
    }
    if let Some(ch) = word.chars().find(|ch| !is_system_table_character(*ch)) {
        return Err(WordValidationError::UnsupportedCharacter(ch));
    }
    Ok(())
}

fn is_system_table_character(ch: char) -> bool {
    ('\u{4E00}'..='\u{9FFF}').contains(&ch)
        || ch.is_ascii_alphanumeric()
        || matches!(
            ch,
            '.' | ','
                | '!'
                | '?'
                | ':'
                | ';'
                | '+'
                | '-'
                | '*'
                | '/'
                | '='
                | '_'
                | '('
                | ')'
                | '['
                | ']'
                | '{'
                | '}'
                | '<'
                | '>'
                | '@'
                | '#'
                | '$'
                | '%'
                | '^'
                | '&'
                | '|'
                | '~'
                | '★'
                | '☆'
                | '※'
                | '℃'
        )
}

/// Validates the canonical code alphabet shared by system and user tables.
pub fn validate_code(code: &str) -> Result<(), CodeValidationError> {
    if code.is_empty() {
        return Err(CodeValidationError::Empty);
    }
    if code.len() > MAX_CODE_LEN || !code.bytes().all(|byte| byte.is_ascii_lowercase()) {
        return Err(CodeValidationError::Invalid);
    }
    Ok(())
}

/// Validates the common-CJK word policy used by text table importers.
pub fn validate_word(word: &str) -> Result<(), WordValidationError> {
    if word.is_empty() {
        return Err(WordValidationError::Empty);
    }
    let char_count = word.chars().count();
    if char_count > MAX_WORD_CHARS {
        return Err(WordValidationError::TooLong {
            actual: char_count,
            max: MAX_WORD_CHARS,
        });
    }
    if let Some(ch) = word
        .chars()
        .find(|ch| !('\u{4E00}'..='\u{9FFF}').contains(ch))
    {
        return Err(WordValidationError::UnsupportedCharacter(ch));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validation_is_shared_and_strict() {
        assert_eq!(validate_code("uurufa"), Ok(()));
        assert_eq!(validate_word("输入法"), Ok(()));
        assert_eq!(validate_code("uu ru"), Err(CodeValidationError::Invalid));
        assert_eq!(
            validate_word("input"),
            Err(WordValidationError::UnsupportedCharacter('i'))
        );
    }

    #[test]
    fn system_table_policy_does_not_widen_user_words() {
        assert_eq!(validate_system_table_word("测试A0001"), Ok(()));
        assert_eq!(validate_system_table_word("符号★"), Ok(()));
        assert!(validate_word("测试A0001").is_err());
        assert!(validate_system_table_word("bad word").is_err());
    }
}
