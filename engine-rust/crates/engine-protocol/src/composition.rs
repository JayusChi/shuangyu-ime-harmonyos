use crate::error::ImeErrorCode;
use crate::escape_json;

pub const INTERFACE_VERSION_STAGE8: u32 = 2;
pub const ABI_VERSION_STAGE8: u32 = 2;
pub const ENGINE_VERSION_STAGE8: &str = "0.0.1-stage8";
pub const INTERFACE_VERSION_STAGE9: u32 = INTERFACE_VERSION_STAGE8;
pub const ABI_VERSION_STAGE9: u32 = ABI_VERSION_STAGE8;
pub const ENGINE_VERSION_STAGE9: &str = "0.0.1-stage9";
pub const INTERFACE_VERSION_STAGE1165: u32 = 3;
pub const ABI_VERSION_STAGE1165: u32 = 3;
pub const ENGINE_VERSION_STAGE1165: &str = "0.0.1-stage11.6.5";
pub const INTERFACE_VERSION_STAGE1166: u32 = 4;
pub const ABI_VERSION_STAGE1166: u32 = 4;
pub const ENGINE_VERSION_STAGE1166: &str = "0.0.1-stage11.6.6";
pub const INTERFACE_VERSION_STAGE1167: u32 = INTERFACE_VERSION_STAGE1166;
pub const ABI_VERSION_STAGE1167: u32 = ABI_VERSION_STAGE1166;
pub const ENGINE_VERSION_STAGE1167: &str = "0.0.1-stage11.6.7";
pub const INTERFACE_VERSION_STAGE12: u32 = 5;
pub const ABI_VERSION_STAGE12: u32 = 5;
pub const ENGINE_VERSION_STAGE12: &str = "0.0.1-stage12";
pub const INTERFACE_VERSION_PINYIN_STAGE1: u32 = 6;
pub const ABI_VERSION_PINYIN_STAGE1: u32 = 6;
pub const ENGINE_VERSION_PINYIN_STAGE1: &str = "0.0.1-pinyin-stage1";
pub const ENGINE_VERSION_PINYIN_STAGE2: &str = "0.0.1-pinyin-stage2-quality4";
pub const INTERFACE_VERSION_PINYIN_STAGE3: u32 = 7;
pub const ABI_VERSION_PINYIN_STAGE3: u32 = 7;
pub const ENGINE_VERSION_PINYIN_STAGE3: &str = "0.0.1-pinyin-stage3";
pub const INTERFACE_VERSION_DIRECT_ACTIONS: u32 = 9;
pub const ABI_VERSION_DIRECT_ACTIONS: u32 = 9;
pub const ENGINE_VERSION_DIRECT_ACTIONS: &str = "0.0.1-quanpin-features";
pub const INTERFACE_VERSION_STAGE7: u32 = INTERFACE_VERSION_STAGE8;
pub const ABI_VERSION_STAGE7: u32 = ABI_VERSION_STAGE8;
pub const ENGINE_VERSION_STAGE7: &str = ENGINE_VERSION_STAGE8;
pub const INTERFACE_VERSION_STAGE5: u32 = INTERFACE_VERSION_STAGE7;
pub const ABI_VERSION_STAGE5: u32 = ABI_VERSION_STAGE7;
pub const ENGINE_VERSION_STAGE5: &str = ENGINE_VERSION_STAGE7;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ParserState {
    Empty,
    Incomplete,
    Complete,
    Invalid,
    Ambiguous,
}

impl ParserState {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Empty => "empty",
            Self::Incomplete => "incomplete",
            Self::Complete => "complete",
            Self::Invalid => "invalid",
            Self::Ambiguous => "ambiguous",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FormalCandidate {
    pub id: String,
    pub text: String,
    pub reading: String,
    pub source: String,
    /// Number of raw composition letters consumed when this candidate is
    /// selected. A retained stable-prefix candidate may intentionally cover
    /// less than the current composition and leave the pending tail editable.
    pub consumed_raw_len: u32,
}

/// A single, closed, cross-layer action. Ordinary text and symbols continue to
/// use `commit_text`; only behavior that cannot be represented by a plain text
/// commit belongs here.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ProtocolAction {
    DateTimeText {
        format_id: DateTimeFormatId,
    },
    InsertPair {
        text: String,
        cursor_offset_utf16: u32,
    },
    RepeatCommit,
    UndoCommit,
    MoveLineEnd,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DateTimeFormatId {
    DateIso,
    DateLocal,
    TimeHm,
    DateTimeLocal,
}

impl DateTimeFormatId {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::DateIso => "DATE_ISO",
            Self::DateLocal => "DATE_LOCAL",
            Self::TimeHm => "TIME_HM",
            Self::DateTimeLocal => "DATETIME_LOCAL",
        }
    }
}

impl ProtocolAction {
    pub fn to_json(&self) -> String {
        match self {
            Self::DateTimeText { format_id } => format!(
                "{{\"type\":\"DATE_TIME_TEXT\",\"formatId\":\"{}\",\"text\":\"\",\"cursorOffsetUtf16\":0}}",
                format_id.as_str()
            ),
            Self::InsertPair {
                text,
                cursor_offset_utf16,
            } => format!(
                "{{\"type\":\"INSERT_PAIR\",\"formatId\":\"\",\"text\":\"{}\",\"cursorOffsetUtf16\":{}}}",
                escape_json(text),
                cursor_offset_utf16
            ),
            Self::RepeatCommit =>
                "{\"type\":\"REPEAT_COMMIT\",\"formatId\":\"\",\"text\":\"\",\"cursorOffsetUtf16\":0}".to_owned(),
            Self::UndoCommit =>
                "{\"type\":\"UNDO_COMMIT\",\"formatId\":\"\",\"text\":\"\",\"cursorOffsetUtf16\":0}".to_owned(),
            Self::MoveLineEnd =>
                "{\"type\":\"MOVE_LINE_END\",\"formatId\":\"\",\"text\":\"\",\"cursorOffsetUtf16\":0}".to_owned(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CompositionResult {
    pub success: bool,
    pub error_code: ImeErrorCode,
    pub error_message: String,
    pub raw_input: String,
    pub preedit_text: String,
    pub parsed_syllables: Vec<String>,
    pub pending_code: String,
    pub display_segments: Vec<String>,
    pub segment_boundaries: Vec<u32>,
    pub current_pinyin: String,
    pub pinyin_combinations: Vec<String>,
    pub parser_state: ParserState,
    pub candidates: Vec<FormalCandidate>,
    pub highlighted_index: i32,
    pub has_next_page: bool,
    pub has_previous_page: bool,
    pub candidate_page: u32,
    pub commit_text: String,
    pub action: Option<ProtocolAction>,
    pub composition_finished: bool,
}

impl CompositionResult {
    pub fn success(
        raw_input: &str,
        preedit_text: &str,
        parsed_syllables: Vec<String>,
        pending_code: &str,
        parser_state: ParserState,
    ) -> Self {
        Self {
            success: true,
            error_code: ImeErrorCode::Success,
            error_message: String::new(),
            raw_input: raw_input.to_owned(),
            preedit_text: preedit_text.to_owned(),
            parsed_syllables,
            pending_code: pending_code.to_owned(),
            display_segments: Vec::new(),
            segment_boundaries: Vec::new(),
            current_pinyin: String::new(),
            pinyin_combinations: Vec::new(),
            parser_state,
            candidates: Vec::new(),
            highlighted_index: -1,
            has_next_page: false,
            has_previous_page: false,
            candidate_page: 0,
            commit_text: String::new(),
            action: None,
            composition_finished: false,
        }
    }

    pub fn interface_error(error_code: ImeErrorCode) -> Self {
        Self {
            success: false,
            error_code,
            error_message: error_code.message().to_owned(),
            raw_input: String::new(),
            preedit_text: String::new(),
            parsed_syllables: Vec::new(),
            pending_code: String::new(),
            display_segments: Vec::new(),
            segment_boundaries: Vec::new(),
            current_pinyin: String::new(),
            pinyin_combinations: Vec::new(),
            parser_state: ParserState::Empty,
            candidates: Vec::new(),
            highlighted_index: -1,
            has_next_page: false,
            has_previous_page: false,
            candidate_page: 0,
            commit_text: String::new(),
            action: None,
            composition_finished: false,
        }
    }

    pub fn with_candidates(
        mut self,
        candidates: Vec<FormalCandidate>,
        candidate_page: u32,
        has_previous_page: bool,
        has_next_page: bool,
    ) -> Self {
        self.highlighted_index = if candidates.is_empty() { -1 } else { 0 };
        self.candidates = candidates;
        self.candidate_page = candidate_page;
        self.has_previous_page = has_previous_page;
        self.has_next_page = has_next_page;
        self
    }

    pub fn with_segment_boundaries(mut self, segment_boundaries: Vec<u32>) -> Self {
        self.segment_boundaries = segment_boundaries;
        self
    }

    pub fn with_phonetic_metadata(
        mut self,
        display_segments: Vec<String>,
        current_pinyin: &str,
        pinyin_combinations: Vec<String>,
    ) -> Self {
        self.display_segments = display_segments;
        self.current_pinyin = current_pinyin.to_owned();
        self.pinyin_combinations = pinyin_combinations;
        self
    }

    pub fn committed(commit_text: &str) -> Self {
        let mut result = Self::success("", "", Vec::new(), "", ParserState::Empty);
        result.commit_text = commit_text.to_owned();
        result.composition_finished = true;
        result
    }

    pub fn with_action(mut self, action: ProtocolAction) -> Self {
        debug_assert!(self.commit_text.is_empty());
        self.action = Some(action);
        self
    }

    pub fn to_json(&self) -> String {
        let parsed_syllables = self
            .parsed_syllables
            .iter()
            .map(|value| format!("\"{}\"", escape_json(value)))
            .collect::<Vec<_>>()
            .join(",");
        let candidates = self
            .candidates
            .iter()
            .map(|candidate| {
                format!(
                    "{{\"id\":\"{}\",\"text\":\"{}\",\"reading\":\"{}\",\"source\":\"{}\",\"consumedRawLen\":{}}}",
                    escape_json(&candidate.id),
                    escape_json(&candidate.text),
                    escape_json(&candidate.reading),
                    escape_json(&candidate.source),
                    candidate.consumed_raw_len
                )
            })
            .collect::<Vec<_>>()
            .join(",");
        let segment_boundaries = self
            .segment_boundaries
            .iter()
            .map(u32::to_string)
            .collect::<Vec<_>>()
            .join(",");
        let display_segments = self
            .display_segments
            .iter()
            .map(|value| format!("\"{}\"", escape_json(value)))
            .collect::<Vec<_>>()
            .join(",");
        let pinyin_combinations = self
            .pinyin_combinations
            .iter()
            .map(|value| format!("\"{}\"", escape_json(value)))
            .collect::<Vec<_>>()
            .join(",");
        let action = self
            .action
            .as_ref()
            .map(ProtocolAction::to_json)
            .unwrap_or_else(|| "null".to_owned());

        format!(
            "{{\"success\":{},\"errorCode\":{},\"errorMessage\":\"{}\",\"rawInput\":\"{}\",\"preeditText\":\"{}\",\"parsedSyllables\":[{}],\"pendingCode\":\"{}\",\"displaySegments\":[{}],\"segmentBoundaries\":[{}],\"currentPinyin\":\"{}\",\"pinyinCombinations\":[{}],\"parserState\":\"{}\",\"candidates\":[{}],\"highlightedIndex\":{},\"hasNextPage\":{},\"hasPreviousPage\":{},\"candidatePage\":{},\"commitText\":\"{}\",\"action\":{},\"compositionFinished\":{}}}",
            if self.success { "true" } else { "false" },
            self.error_code.as_i32(),
            escape_json(&self.error_message),
            escape_json(&self.raw_input),
            escape_json(&self.preedit_text),
            parsed_syllables,
            escape_json(&self.pending_code),
            display_segments,
            segment_boundaries,
            escape_json(&self.current_pinyin),
            pinyin_combinations,
            self.parser_state.as_str(),
            candidates,
            self.highlighted_index,
            if self.has_next_page { "true" } else { "false" },
            if self.has_previous_page { "true" } else { "false" },
            self.candidate_page,
            escape_json(&self.commit_text),
            action,
            if self.composition_finished { "true" } else { "false" }
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serializes_stage5_empty_candidate_contract() {
        let result = CompositionResult::success(
            "ni",
            "ni",
            vec!["ni".to_owned()],
            "",
            ParserState::Complete,
        );
        let json = result.to_json();

        assert!(json.contains("\"success\":true"));
        assert!(json.contains("\"parserState\":\"complete\""));
        assert!(json.contains("\"candidates\":[]"));
        assert!(json.contains("\"highlightedIndex\":-1"));
        assert!(json.contains("\"hasPreviousPage\":false"));
        assert!(json.contains("\"displaySegments\":[]"));
        assert!(json.contains("\"currentPinyin\":\"\""));
        assert!(json.contains("\"pinyinCombinations\":[]"));
        assert!(json.contains("\"segmentBoundaries\":[]"));
        assert!(json.contains("\"candidatePage\":0"));
        assert!(json.contains("\"compositionFinished\":false"));
        assert!(json.contains("\"action\":null"));
    }

    #[test]
    fn serializes_exactly_one_typed_action() {
        let result = CompositionResult::success("", "", Vec::new(), "", ParserState::Empty)
            .with_action(ProtocolAction::InsertPair {
                text: "()".to_owned(),
                cursor_offset_utf16: 1,
            });
        let json = result.to_json();
        assert!(json.contains("\"type\":\"INSERT_PAIR\""));
        assert!(json.contains("\"cursorOffsetUtf16\":1"));
        assert!(json.contains("\"commitText\":\"\""));
    }

    #[test]
    fn serializes_closed_editor_control_actions_without_parameters() {
        for (action, kind) in [
            (ProtocolAction::RepeatCommit, "REPEAT_COMMIT"),
            (ProtocolAction::UndoCommit, "UNDO_COMMIT"),
            (ProtocolAction::MoveLineEnd, "MOVE_LINE_END"),
        ] {
            let json = CompositionResult::success("", "", Vec::new(), "", ParserState::Empty)
                .with_action(action)
                .to_json();
            assert!(json.contains(&format!("\"type\":\"{kind}\"")));
            assert!(json.contains("\"cursorOffsetUtf16\":0"));
            assert!(json.contains("\"commitText\":\"\""));
        }
    }

    #[test]
    fn serializes_two_code_display_segments_without_changing_raw_input() {
        let result = CompositionResult::success(
            "vegewtyijkjj",
            "zhe'ge'wen'ti'yi'jing'jie'jue",
            Vec::new(),
            "",
            ParserState::Complete,
        )
        .with_phonetic_metadata(
            vec!["ve", "ge", "wt", "yi", "jk", "jj"]
                .into_iter()
                .map(str::to_owned)
                .collect(),
            "zhe'ge'wen'ti'yi'jing'jie'jue",
            Vec::new(),
        );
        let json = result.to_json();
        assert!(json.contains("\"rawInput\":\"vegewtyijkjj\""));
        assert!(json.contains("\"displaySegments\":[\"ve\",\"ge\",\"wt\",\"yi\",\"jk\",\"jj\"]"));

        let explicit = CompositionResult::success(
            "ve'gew",
            "zhe'ge",
            Vec::new(),
            "w",
            ParserState::Incomplete,
        )
        .with_phonetic_metadata(
            vec!["ve".to_owned(), "ge".to_owned(), "w".to_owned()],
            "",
            Vec::new(),
        );
        assert_eq!(explicit.display_segments, vec!["ve", "ge", "w"]);

        let guided =
            CompositionResult::success(";rqab", ";rqab", Vec::new(), "", ParserState::Complete)
                .with_phonetic_metadata(vec![";rq".to_owned(), "ab".to_owned()], "", Vec::new());
        assert_eq!(guided.display_segments, vec![";rq", "ab"]);
    }
}
