use crate::error::LineErrorReason;

/// Validates the canonical code alphabet shared by code-table importers.
pub fn validate_code(code: &str) -> Result<(), LineErrorReason> {
    match lexicon_core::validate_code(code) {
        Ok(()) => Ok(()),
        Err(lexicon_core::CodeValidationError::Empty) => Err(LineErrorReason::EmptyCode),
        Err(lexicon_core::CodeValidationError::Invalid) => Err(LineErrorReason::InvalidCode {
            value: code.to_owned(),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_lowercase_ascii_and_rejects_future_markers() {
        assert_eq!(validate_code("uurufa"), Ok(()));
        for invalid in ["", "uu ru", "UURU", "uurufa#固", "uurufa#N", "uurufa#删"] {
            assert!(validate_code(invalid).is_err(), "{invalid}");
        }
    }
}
