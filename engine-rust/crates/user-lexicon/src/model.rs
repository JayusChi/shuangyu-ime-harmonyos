#[derive(Clone, Debug, Eq, PartialEq)]
pub enum UserLexiconAction {
    Add,
    Delete,
    Fixed,
    Position(u16),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserLexiconEntry {
    pub text: String,
    pub code: String,
    pub action: UserLexiconAction,
    pub source_order: u32,
}

impl UserLexiconEntry {
    /// Stable internal identifier with a source namespace distinct from system ids.
    pub fn stable_id(&self) -> String {
        let mut hash = 0xcbf2_9ce4_8422_2325_u64;
        for byte in self
            .code
            .as_bytes()
            .iter()
            .chain([0_u8].iter())
            .chain(self.text.as_bytes())
        {
            hash ^= u64::from(*byte);
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
        format!("user-lexicon-{hash:016x}")
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct UserLexiconStats {
    pub accepted: usize,
    pub effective: usize,
    pub added: usize,
    pub deleted: usize,
    pub fixed: usize,
    pub positioned: usize,
}
