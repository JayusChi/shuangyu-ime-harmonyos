use crate::DecodeError;

/// Centralized stage 8 sentence decoder limits.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DecodeLimits {
    /// Maximum raw ASCII shuangpin key buffer length.
    pub max_raw_len: usize,
    /// Maximum complete pinyin syllables decoded in one request.
    pub max_syllables: usize,
    /// Maximum syllables a single lexicon edge may cover.
    pub max_word_syllables: usize,
    /// Maximum graph edges retained for one decode request.
    pub max_edges: usize,
    /// Maximum path states retained at each graph position.
    pub beam_width: usize,
    /// Maximum complete paths converted to candidates before partial options.
    pub max_output_paths: usize,
    /// Maximum lexicon entries read for one exact pinyin key.
    pub max_entries_per_key: usize,
    /// Maximum final candidates returned to the IME engine.
    pub max_output_candidates: usize,
}

impl Default for DecodeLimits {
    fn default() -> Self {
        Self {
            max_raw_len: 64,
            max_syllables: 32,
            max_word_syllables: 9,
            max_edges: 256,
            beam_width: 8,
            max_output_paths: 8,
            max_entries_per_key: 8,
            max_output_candidates: 16,
        }
    }
}

impl DecodeLimits {
    pub(crate) fn validate(&self) -> Result<(), DecodeError> {
        for (field, value) in [
            ("max_raw_len", self.max_raw_len),
            ("max_syllables", self.max_syllables),
            ("max_word_syllables", self.max_word_syllables),
            ("max_edges", self.max_edges),
            ("beam_width", self.beam_width),
            ("max_output_paths", self.max_output_paths),
            ("max_entries_per_key", self.max_entries_per_key),
            ("max_output_candidates", self.max_output_candidates),
        ] {
            if value == 0 {
                return Err(DecodeError::InvalidLimit { field });
            }
        }
        Ok(())
    }
}
