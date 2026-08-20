use std::collections::BTreeSet;

use pinyin_syllable::normalize_syllable;
use shuangpin_schema::{
    load_builtin_schema, validate_schema, RuntimeSchema, RuntimeSyllable, ShuangpinSchema,
};

use crate::error::ParseError;
use crate::result::{ParseResult, ParseStatus, ParsedSyllable, QueryIntent};
use crate::state::ParserState;

/// Stateful shuangpin parser.
///
/// The parser owns raw key history and a validated runtime schema. Processing a
/// key appends it to raw history, backspace removes one key, reset clears all
/// history, and schema changes validate the target schema before replacing the
/// current runtime index.
#[derive(Clone, Debug)]
pub struct ShuangpinParser {
    schema: RuntimeSchema,
    raw_code: String,
    current: ParseResult,
}

impl ShuangpinParser {
    /// Creates a parser from an already validated runtime schema.
    pub fn new(schema: RuntimeSchema) -> Self {
        Self {
            schema,
            raw_code: String::new(),
            current: ParseResult::empty(),
        }
    }

    /// Creates a parser using the built-in Xiaohe schema.
    pub fn xiaohe() -> Result<Self, ParseError> {
        Ok(Self::new(load_builtin_schema("xiaohe")?))
    }

    /// Returns the active schema id.
    pub fn schema_id(&self) -> &str {
        &self.schema.schema().id
    }

    /// Returns the raw key history currently owned by the parser.
    pub fn raw_code(&self) -> &str {
        &self.raw_code
    }

    /// Processes one key and returns the updated parse state.
    ///
    /// Invalid keys are retained in raw history so that `backspace` can recover
    /// the exact previous state without hidden side effects.
    pub fn process_key(&mut self, key: char) -> ParseResult {
        self.raw_code.push(key);
        self.reparse()
    }

    /// Processes all characters from `input` in order and returns the final
    /// parse state.
    pub fn process_str(&mut self, input: &str) -> ParseResult {
        for key in input.chars() {
            self.raw_code.push(key);
        }
        self.reparse()
    }

    /// Inserts a parser-owned explicit segment boundary. The operation is
    /// transactional: an empty, consecutive, or incomplete trailing segment
    /// is rejected without changing the previous composition.
    pub fn insert_segment_boundary(&mut self) -> Result<ParseResult, ParseError> {
        if self.raw_code.is_empty()
            || self.raw_code.ends_with('\'')
            || !matches!(
                self.current.status,
                ParseStatus::Complete | ParseStatus::Ambiguous
            )
        {
            return Err(ParseError::InvalidSegmentBoundary);
        }
        self.raw_code.push('\'');
        Ok(self.reparse())
    }

    /// Removes one raw key, if any, and reparses the remaining history.
    pub fn backspace(&mut self) -> ParseResult {
        self.raw_code.pop();
        self.reparse()
    }

    /// Clears raw history and returns the empty state.
    pub fn reset(&mut self) -> ParseResult {
        self.raw_code.clear();
        self.current = ParseResult::empty();
        self.current.clone()
    }

    /// Replaces the current schema after validating `schema`.
    ///
    /// On failure the existing schema and parser state are left untouched.
    pub fn change_schema(&mut self, schema: ShuangpinSchema) -> Result<ParseResult, ParseError> {
        let runtime = validate_schema(schema)?;
        self.schema = runtime;
        self.raw_code.clear();
        self.current = ParseResult::empty();
        Ok(self.current.clone())
    }

    /// Returns the latest parse result without modifying parser state.
    pub fn current_state(&self) -> ParseResult {
        self.current.clone()
    }

    /// Returns a coarse state-machine label for the latest parse result.
    pub fn state(&self) -> ParserState {
        if self.raw_code.is_empty() {
            return ParserState::Empty;
        }

        match self.current.status {
            ParseStatus::Empty => ParserState::Empty,
            ParseStatus::Incomplete => ParserState::Incomplete,
            ParseStatus::Complete | ParseStatus::Ambiguous => ParserState::CompleteSequence,
            ParseStatus::Invalid => ParserState::Invalid,
        }
    }

    fn reparse(&mut self) -> ParseResult {
        self.current = parse_raw(&self.schema, &self.raw_code);
        self.current.clone()
    }
}

fn parse_raw(schema: &RuntimeSchema, raw_code: &str) -> ParseResult {
    let mut result = parse_raw_syntax(schema, raw_code);
    result.query_intent = classify_query_intent(&result);
    result.raw_input = raw_code.to_owned();
    result.display_segments = build_xiaohe_display_segments(raw_code);
    result.current_pinyin = build_current_pinyin(&result);
    result
}

fn parse_raw_syntax(schema: &RuntimeSchema, raw_code: &str) -> ParseResult {
    if raw_code.is_empty() {
        return ParseResult::empty();
    }

    let mut raw_letter_offset = 0usize;
    let mut segment_boundaries = Vec::new();
    for ch in raw_code.chars() {
        if ch == '\'' {
            segment_boundaries.push(raw_letter_offset);
        } else {
            raw_letter_offset += 1;
        }
    }
    let segments = raw_code.split('\'').collect::<Vec<_>>();
    let trailing_boundary = segments.last().is_some_and(|segment| segment.is_empty());
    let mut combined_syllables = Vec::new();
    let mut combined_logical_count = 0usize;
    let mut combined_status = ParseStatus::Complete;

    for (index, segment) in segments.iter().enumerate() {
        if segment.is_empty() {
            if trailing_boundary && index + 1 == segments.len() {
                continue;
            }
            return invalid_with_boundaries(
                ParseError::InvalidSegmentBoundary,
                combined_syllables,
                segment_boundaries,
            );
        }

        let mut parsed = parse_segment(schema, segment);
        let is_final = index + 1 == segments.len();
        if !is_final
            && !matches!(
                parsed.status,
                ParseStatus::Complete | ParseStatus::Ambiguous
            )
        {
            return invalid_with_boundaries(
                ParseError::InvalidSegmentBoundary,
                combined_syllables,
                segment_boundaries,
            );
        }
        for syllable in &mut parsed.syllables {
            syllable.logical_index += combined_logical_count;
        }
        combined_logical_count += parsed.logical_syllable_count;
        combined_syllables.append(&mut parsed.syllables);
        if parsed.status == ParseStatus::Invalid {
            return ParseResult {
                raw_input: String::new(),
                query_intent: QueryIntent::Invalid,
                status: ParseStatus::Invalid,
                syllables: combined_syllables,
                logical_syllable_count: combined_logical_count,
                pending_code: String::new(),
                display_segments: Vec::new(),
                segment_boundaries,
                current_pinyin: String::new(),
                pinyin_combinations: Vec::new(),
                error: parsed.error,
            };
        }
        if parsed.status == ParseStatus::Ambiguous {
            combined_status = ParseStatus::Ambiguous;
        }
        if is_final && parsed.status == ParseStatus::Incomplete {
            return ParseResult {
                raw_input: String::new(),
                query_intent: QueryIntent::IncompleteSyllable,
                status: ParseStatus::Incomplete,
                syllables: combined_syllables,
                logical_syllable_count: combined_logical_count,
                pending_code: parsed.pending_code,
                display_segments: Vec::new(),
                segment_boundaries,
                current_pinyin: String::new(),
                pinyin_combinations: Vec::new(),
                error: None,
            };
        }
    }

    ParseResult {
        raw_input: String::new(),
        query_intent: QueryIntent::CompleteSyllable,
        status: combined_status,
        syllables: combined_syllables,
        logical_syllable_count: combined_logical_count,
        pending_code: String::new(),
        display_segments: Vec::new(),
        segment_boundaries,
        current_pinyin: String::new(),
        pinyin_combinations: Vec::new(),
        error: None,
    }
}

fn parse_segment(schema: &RuntimeSchema, raw_code: &str) -> ParseResult {
    let mut syllables = Vec::new();
    let mut logical_syllable_count = 0usize;
    let mut ambiguous = false;
    let mut chars = raw_code.chars();

    while let Some(first) = chars.next() {
        if !schema.is_allowed_key(first) {
            return invalid(ParseError::InvalidKey { key: first }, syllables);
        }

        let Some(second) = chars.next() else {
            return ParseResult {
                raw_input: String::new(),
                query_intent: QueryIntent::IncompleteSyllable,
                status: ParseStatus::Incomplete,
                syllables,
                logical_syllable_count,
                pending_code: first.to_string(),
                display_segments: Vec::new(),
                segment_boundaries: Vec::new(),
                current_pinyin: String::new(),
                pinyin_combinations: Vec::new(),
                error: None,
            };
        };

        if !schema.is_allowed_key(second) {
            return invalid(ParseError::InvalidKey { key: second }, syllables);
        }

        let code = format!("{first}{second}");
        match parse_two_key_code(schema, &code) {
            Ok(candidates) if candidates.is_empty() => {
                return invalid(ParseError::InvalidCode { code }, syllables);
            }
            Ok(mut candidates) => {
                if candidates.len() > 1 {
                    ambiguous = true;
                }
                for candidate in &mut candidates {
                    candidate.logical_index = logical_syllable_count;
                }
                syllables.extend(candidates);
                logical_syllable_count += 1;
            }
            Err(error) => return invalid(error, syllables),
        }
    }

    ParseResult {
        raw_input: String::new(),
        query_intent: QueryIntent::CompleteSyllable,
        status: if ambiguous {
            ParseStatus::Ambiguous
        } else {
            ParseStatus::Complete
        },
        syllables,
        logical_syllable_count,
        pending_code: String::new(),
        display_segments: Vec::new(),
        segment_boundaries: Vec::new(),
        current_pinyin: String::new(),
        pinyin_combinations: Vec::new(),
        error: None,
    }
}

fn parse_two_key_code(
    schema: &RuntimeSchema,
    code: &str,
) -> Result<Vec<ParsedSyllable>, ParseError> {
    if let Some(rule) = schema.special_syllable_for_code(code) {
        return Ok(vec![from_runtime(rule)]);
    }

    if let Some(rule) = schema.zero_syllable_for_code(code) {
        return Ok(vec![from_runtime(rule)]);
    }

    let mut chars = code.chars();
    let first = chars.next().ok_or_else(|| ParseError::InvalidCode {
        code: code.to_owned(),
    })?;
    let second = chars.next().ok_or_else(|| ParseError::InvalidCode {
        code: code.to_owned(),
    })?;
    if chars.next().is_some() {
        return Err(ParseError::InvalidCode {
            code: code.to_owned(),
        });
    }

    let Some(initial) = schema.initial_for_key(first) else {
        return Ok(Vec::new());
    };
    let Some(finals) = schema.finals_for_key(second) else {
        return Ok(Vec::new());
    };

    let mut seen = BTreeSet::new();
    let mut parsed = Vec::new();
    for final_part in finals {
        let raw_syllable = format!("{initial}{final_part}");
        if let Ok(syllable) = normalize_syllable(&raw_syllable) {
            if seen.insert(syllable.clone()) {
                parsed.push(ParsedSyllable {
                    logical_index: 0,
                    raw_code: code.to_owned(),
                    syllable,
                    initial: initial.to_owned(),
                    final_part: final_part.clone(),
                    special_rule: false,
                });
            }
        }
    }

    Ok(parsed)
}

fn invalid(error: ParseError, syllables: Vec<ParsedSyllable>) -> ParseResult {
    let logical_syllable_count = logical_count(&syllables);
    ParseResult {
        raw_input: String::new(),
        query_intent: QueryIntent::Invalid,
        status: ParseStatus::Invalid,
        syllables,
        logical_syllable_count,
        pending_code: String::new(),
        display_segments: Vec::new(),
        segment_boundaries: Vec::new(),
        current_pinyin: String::new(),
        pinyin_combinations: Vec::new(),
        error: Some(error),
    }
}

fn invalid_with_boundaries(
    error: ParseError,
    syllables: Vec<ParsedSyllable>,
    segment_boundaries: Vec<usize>,
) -> ParseResult {
    let logical_syllable_count = logical_count(&syllables);
    ParseResult {
        raw_input: String::new(),
        query_intent: QueryIntent::Invalid,
        status: ParseStatus::Invalid,
        syllables,
        logical_syllable_count,
        pending_code: String::new(),
        display_segments: Vec::new(),
        segment_boundaries,
        current_pinyin: String::new(),
        pinyin_combinations: Vec::new(),
        error: Some(error),
    }
}

fn build_current_pinyin(result: &ParseResult) -> String {
    let mut values = Vec::with_capacity(result.logical_syllable_count + 1);
    let mut next_logical_index = 0usize;
    for syllable in &result.syllables {
        if syllable.logical_index == next_logical_index {
            values.push(syllable.syllable.clone());
            next_logical_index += 1;
        }
    }
    if !result.pending_code.is_empty() {
        values.push(result.pending_code.clone());
    }
    values.join("'")
}

fn build_xiaohe_display_segments(raw_input: &str) -> Vec<String> {
    let mut segments = Vec::new();
    let mut current = String::new();
    let mut letters_in_segment = 0usize;

    for character in raw_input.chars() {
        if character == '\'' {
            if !current.is_empty() {
                segments.push(std::mem::take(&mut current));
            }
            letters_in_segment = 0;
        } else if character.is_ascii_alphabetic() {
            if letters_in_segment == 2 {
                segments.push(std::mem::take(&mut current));
                letters_in_segment = 0;
            }
            current.push(character);
            letters_in_segment += 1;
        } else {
            if letters_in_segment > 0 {
                segments.push(std::mem::take(&mut current));
                letters_in_segment = 0;
            }
            current.push(character);
        }
    }

    if !current.is_empty() {
        segments.push(current);
    }
    segments
}

fn classify_query_intent(result: &ParseResult) -> QueryIntent {
    match result.status {
        ParseStatus::Empty => QueryIntent::Empty,
        ParseStatus::Invalid => QueryIntent::Invalid,
        ParseStatus::Incomplete if result.logical_syllable_count == 0 => {
            QueryIntent::SingleKeyPrefix
        }
        ParseStatus::Incomplete if result.logical_syllable_count >= 2 => QueryIntent::MultiSyllable,
        ParseStatus::Incomplete => QueryIntent::IncompleteSyllable,
        ParseStatus::Complete | ParseStatus::Ambiguous if result.logical_syllable_count <= 1 => {
            QueryIntent::CompleteSyllable
        }
        ParseStatus::Complete | ParseStatus::Ambiguous => QueryIntent::MultiSyllable,
    }
}

fn logical_count(syllables: &[ParsedSyllable]) -> usize {
    syllables
        .iter()
        .map(|syllable| syllable.logical_index + 1)
        .max()
        .unwrap_or(0)
}

fn from_runtime(rule: &RuntimeSyllable) -> ParsedSyllable {
    ParsedSyllable {
        logical_index: 0,
        raw_code: rule.code.clone(),
        syllable: rule.syllable.clone(),
        initial: rule.initial.clone(),
        final_part: rule.final_part.clone(),
        special_rule: rule.special_rule,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_single_xiaohe_code() {
        let mut parser = ShuangpinParser::xiaohe().unwrap();
        let result = parser.process_str("vh");
        assert_eq!(result.status, ParseStatus::Complete);
        assert_eq!(result.syllables[0].syllable, "zhang");
    }

    #[test]
    fn backspace_recovers_from_invalid_key() {
        let mut parser = ShuangpinParser::xiaohe().unwrap();
        parser.process_str("ni1");
        assert_eq!(parser.state(), ParserState::Invalid);
        let result = parser.backspace();
        assert_eq!(result.status, ParseStatus::Complete);
        assert_eq!(result.syllables[0].syllable, "ni");
    }

    #[test]
    fn explicit_boundary_is_structured_and_backspace_removes_it() {
        let mut parser = ShuangpinParser::xiaohe().unwrap();
        parser.process_str("ni");
        let segmented = parser.insert_segment_boundary().unwrap();
        assert_eq!(parser.raw_code(), "ni'");
        assert_eq!(segmented.segment_boundaries, vec![2]);
        assert_eq!(segmented.status, ParseStatus::Complete);

        let restored = parser.backspace();
        assert_eq!(parser.raw_code(), "ni");
        assert!(restored.segment_boundaries.is_empty());
    }

    #[test]
    fn invalid_boundary_keeps_previous_parser_state() {
        let mut parser = ShuangpinParser::xiaohe().unwrap();
        assert_eq!(
            parser.insert_segment_boundary(),
            Err(ParseError::InvalidSegmentBoundary)
        );
        parser.process_key('n');
        assert_eq!(
            parser.insert_segment_boundary(),
            Err(ParseError::InvalidSegmentBoundary)
        );
        assert_eq!(parser.raw_code(), "n");
    }
}
