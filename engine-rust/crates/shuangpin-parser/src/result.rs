use crate::error::ParseError;

/// Product-level query meaning derived by the parser.
///
/// Downstream query, ranking, and sentence decoding code must branch on this
/// value instead of independently guessing from raw-key or candidate counts.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QueryIntent {
    Empty,
    /// One allowed key is a pinyin/initial prefix. A final mapping on the same
    /// key does not participate unless a future schema contract says so.
    SingleKeyPrefix,
    /// One complete two-key code, including explicit zero-initial and special
    /// syllable rules. Ambiguous readings remain one logical syllable.
    CompleteSyllable,
    /// One complete syllable followed by one pending key.
    IncompleteSyllable,
    /// At least two logical syllable slots, complete or with a pending tail.
    MultiSyllable,
    Invalid,
}

/// High-level parse status for the current raw key sequence.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ParseStatus {
    /// No input has been processed.
    Empty,
    /// The trailing code is a valid prefix but is not a full syllable yet.
    Incomplete,
    /// The raw code has produced one or more complete syllables.
    Complete,
    /// The current code cannot be parsed.
    Invalid,
    /// At least one complete two-key code has multiple valid syllables.
    Ambiguous,
}

/// One parsed pinyin syllable.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ParsedSyllable {
    /// Zero-based logical two-key slot. Multiple legal readings for one raw
    /// code share the same slot instead of pretending to be consecutive
    /// syllables.
    pub logical_index: usize,
    /// Raw one- or two-key code that produced this syllable.
    pub raw_code: String,
    /// Normalized pinyin syllable.
    pub syllable: String,
    /// Parsed pinyin initial.
    pub initial: String,
    /// Parsed pinyin final.
    pub final_part: String,
    /// Whether the syllable came from an explicit special rule.
    pub special_rule: bool,
}

/// Full parser result after processing input, backspace, reset, or schema
/// change.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ParseResult {
    /// Exact raw key history owned by this parser.
    pub raw_input: String,
    /// Frozen query meaning for all downstream layers.
    pub query_intent: QueryIntent,
    /// Current parse status.
    pub status: ParseStatus,
    /// Complete syllables produced so far. Ambiguous codes may contribute more
    /// than one entry with the same raw code.
    pub syllables: Vec<ParsedSyllable>,
    /// Number of complete logical two-key slots. This is independent from the
    /// number of alternative readings in `syllables`.
    pub logical_syllable_count: usize,
    /// Last single key that is waiting for the next key, if any.
    pub pending_code: String,
    /// Parser-owned raw input segments for candidate-bar presentation.
    pub display_segments: Vec<String>,
    /// Explicit segment boundaries, expressed as raw letter offsets. Boundary
    /// markers are parser-owned metadata and are never normal input keys.
    pub segment_boundaries: Vec<usize>,
    /// Preferred normalized pinyin path for the current raw input.
    pub current_pinyin: String,
    /// Alternative normalized paths. Xiaohe shuangpin has no user-selectable
    /// alternatives, so its adapter returns an empty list.
    pub pinyin_combinations: Vec<String>,
    /// Structured error for invalid states.
    pub error: Option<ParseError>,
}

impl ParseResult {
    /// Returns an empty parse result.
    pub fn empty() -> Self {
        Self {
            raw_input: String::new(),
            query_intent: QueryIntent::Empty,
            status: ParseStatus::Empty,
            syllables: Vec::new(),
            logical_syllable_count: 0,
            pending_code: String::new(),
            display_segments: Vec::new(),
            segment_boundaries: Vec::new(),
            current_pinyin: String::new(),
            pinyin_combinations: Vec::new(),
            error: None,
        }
    }
}
