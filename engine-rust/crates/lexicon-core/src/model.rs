/// A normalized lexicon entry ready to be written to the binary lexicon.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LexiconEntry {
    /// Chinese word stored in UTF-8.
    pub word: String,
    /// Canonical space-separated pinyin key, for example `ni hao`.
    pub pinyin_key: String,
    /// Canonical syllable list used to derive `pinyin_key`.
    pub syllables: Vec<String>,
    /// Deterministic base frequency stored without candidate-ranking logic.
    pub frequency: u64,
    /// Sorted, unique source tags for this entry.
    pub sources: Vec<String>,
    /// Zero-based accepted-row order in the explicitly ordered source inputs.
    ///
    /// Legacy format 1.0 lexicons use [`SOURCE_ORDER_UNSPECIFIED`] because the
    /// field was not persisted by that format.
    pub source_order: u32,
}

/// Sentinel used when an entry comes from a legacy binary without source order.
pub const SOURCE_ORDER_UNSPECIFIED: u32 = u32::MAX;

impl LexiconEntry {
    /// Creates a normalized entry.
    pub fn new(
        word: String,
        pinyin_key: String,
        syllables: Vec<String>,
        frequency: u64,
        sources: Vec<String>,
    ) -> Self {
        Self {
            word,
            pinyin_key,
            syllables,
            frequency,
            sources,
            source_order: SOURCE_ORDER_UNSPECIFIED,
        }
    }

    /// Attaches the deterministic order assigned by an offline importer.
    pub fn with_source_order(mut self, source_order: u32) -> Self {
        self.source_order = source_order;
        self
    }

    /// Returns the deterministic source string persisted in the binary file.
    pub fn source_key(&self) -> String {
        self.sources.join(",")
    }
}

/// A loaded pinyin-key index range.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PinyinIndex {
    /// Canonical pinyin key.
    pub pinyin_key: String,
    /// First entry index for this key.
    pub start: u32,
    /// Number of entries for this key.
    pub len: u32,
}
