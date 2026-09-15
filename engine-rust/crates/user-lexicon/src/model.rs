#[derive(Clone, Debug, Eq, PartialEq)]
pub enum UserLexiconAction {
    Add,
    /// A user-managed direct word. It commits `text`, may present
    /// `display_text`, and is excluded from wildcard enumeration by the
    /// code-table query path.
    Direct,
    OpenUrl,
    OpenDirectory,
    Delete,
    Fixed,
    Position(u16),
}

impl UserLexiconAction {
    pub fn is_direct(&self) -> bool {
        matches!(self, Self::Direct | Self::OpenUrl | Self::OpenDirectory)
    }

    pub fn external_action(&self) -> Option<&'static str> {
        match self {
            Self::OpenUrl => Some("url.open"),
            Self::OpenDirectory => Some("directory.open"),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserLexiconEntry {
    pub text: String,
    /// Optional candidate-only label. Text actions commit `text`; external
    /// shortcuts use it as their URI and never commit the label or URI.
    pub display_text: Option<String>,
    pub code: String,
    pub action: UserLexiconAction,
    pub source_order: u32,
    /// Owning system category for bundle-embedded rules. External user
    /// lexicons leave this unset and remain independent from category toggles.
    pub category_id: Option<String>,
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
        if let Some(display_text) = &self.display_text {
            for byte in [0_u8].iter().chain(display_text.as_bytes()) {
                hash ^= u64::from(*byte);
                hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
            }
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
