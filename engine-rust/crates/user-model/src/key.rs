use std::fmt;

use crate::error::UserModelError;

const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

/// Coarse candidate origin stored in the user model.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum CandidateSourceKind {
    /// Candidate came directly from the system lexicon query path.
    SystemLexicon,
    /// Candidate came from a sentence-decoder path.
    SentencePath,
}

impl CandidateSourceKind {
    pub const fn as_u8(self) -> u8 {
        match self {
            Self::SystemLexicon => 1,
            Self::SentencePath => 2,
        }
    }

    pub const fn from_u8(value: u8) -> Option<Self> {
        match value {
            1 => Some(Self::SystemLexicon),
            2 => Some(Self::SentencePath),
            _ => None,
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::SystemLexicon => "system",
            Self::SentencePath => "sentence",
        }
    }
}

impl fmt::Display for CandidateSourceKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Privacy-preserving stable key for a learnable candidate.
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub struct UserCandidateKey {
    pub scheme_id: String,
    pub lexicon_version: u32,
    pub source_kind: CandidateSourceKind,
    pub candidate_hash: u64,
}

impl UserCandidateKey {
    /// Builds a stable key by hashing the internal candidate identity.
    ///
    /// The original candidate id may contain candidate text in older stages, so
    /// only the deterministic hash is stored in persistent snapshots.
    pub fn from_stable_id(
        scheme_id: impl Into<String>,
        lexicon_version: u32,
        source_kind: CandidateSourceKind,
        stable_id: &str,
    ) -> Result<Self, UserModelError> {
        let scheme_id = scheme_id.into();
        validate_scheme_id(&scheme_id)?;
        if stable_id.is_empty() {
            return Err(UserModelError::InvalidPath);
        }
        let candidate_hash = hash_candidate_id(stable_id);
        if candidate_hash == 0 {
            return Err(UserModelError::Corrupt("zero candidate hash"));
        }
        Ok(Self {
            scheme_id,
            lexicon_version,
            source_kind,
            candidate_hash,
        })
    }
}

pub(crate) fn key_from_parts(
    scheme_id: String,
    lexicon_version: u32,
    source_kind: CandidateSourceKind,
    candidate_hash: u64,
) -> Result<UserCandidateKey, UserModelError> {
    validate_scheme_id(&scheme_id)?;
    if candidate_hash == 0 {
        return Err(UserModelError::Corrupt("zero candidate hash"));
    }
    Ok(UserCandidateKey {
        scheme_id,
        lexicon_version,
        source_kind,
        candidate_hash,
    })
}

fn validate_scheme_id(value: &str) -> Result<(), UserModelError> {
    if value.is_empty()
        || value.len() > crate::limits::UserModelConfig::default().max_scheme_id_len
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-')
    {
        return Err(UserModelError::InvalidPath);
    }
    Ok(())
}

fn hash_candidate_id(value: &str) -> u64 {
    let mut hash = FNV_OFFSET;
    for byte in value.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    hash
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stable_id_is_hashed_without_storing_text() {
        let key = UserCandidateKey::from_stable_id(
            "xiaohe",
            8,
            CandidateSourceKind::SystemLexicon,
            "lex-v8-ni-你",
        )
        .expect("key should be valid");

        assert_eq!(key.scheme_id, "xiaohe");
        assert_ne!(key.candidate_hash, 0);
    }

    #[test]
    fn invalid_scheme_is_rejected() {
        assert!(UserCandidateKey::from_stable_id(
            "xiao he",
            8,
            CandidateSourceKind::SystemLexicon,
            "id",
        )
        .is_err());
    }
}
