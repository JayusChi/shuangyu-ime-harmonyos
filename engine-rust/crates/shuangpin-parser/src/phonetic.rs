use crate::{
    ParseError, ParseResult, QuanpinParser, ShuangpinParser, T9LatticeStats, T9PinyinParser,
};

/// Common parser boundary consumed by the input engine. Future quanpin and T9
/// implementations must produce the same parser-owned metadata rather than
/// asking C++ or ArkTS to infer syllable boundaries.
pub trait PhoneticParser {
    type Error;

    fn raw_input(&self) -> &str;
    fn process_key(&mut self, key: char) -> ParseResult;
    fn process_str(&mut self, input: &str) -> ParseResult;
    fn insert_segment_boundary(&mut self) -> Result<ParseResult, Self::Error>;
    fn backspace(&mut self) -> ParseResult;
    fn reset(&mut self) -> ParseResult;
    fn current_state(&self) -> ParseResult;
}

/// Stage-1 adapter that exposes the existing Xiaohe parser through the common
/// phonetic boundary without changing Xiaohe parsing semantics.
#[derive(Clone, Debug)]
pub struct XiaoheShuangpinParserAdapter {
    inner: ShuangpinParser,
}

impl XiaoheShuangpinParserAdapter {
    pub fn new(inner: ShuangpinParser) -> Self {
        Self { inner }
    }

    pub fn xiaohe() -> Result<Self, ParseError> {
        ShuangpinParser::xiaohe().map(Self::new)
    }

    pub fn inner(&self) -> &ShuangpinParser {
        &self.inner
    }

    pub fn inner_mut(&mut self) -> &mut ShuangpinParser {
        &mut self.inner
    }

    pub fn raw_code(&self) -> &str {
        self.inner.raw_code()
    }

    pub fn process_str(&mut self, input: &str) -> ParseResult {
        self.inner.process_str(input)
    }
}

impl PhoneticParser for XiaoheShuangpinParserAdapter {
    type Error = ParseError;

    fn raw_input(&self) -> &str {
        self.inner.raw_code()
    }

    fn process_key(&mut self, key: char) -> ParseResult {
        self.inner.process_key(key)
    }

    fn process_str(&mut self, input: &str) -> ParseResult {
        self.inner.process_str(input)
    }

    fn insert_segment_boundary(&mut self) -> Result<ParseResult, Self::Error> {
        self.inner.insert_segment_boundary()
    }

    fn backspace(&mut self) -> ParseResult {
        self.inner.backspace()
    }

    fn reset(&mut self) -> ParseResult {
        self.inner.reset()
    }

    fn current_state(&self) -> ParseResult {
        self.inner.current_state()
    }
}

/// Concrete parser dispatch kept inside Rust so callers can switch schemes
/// without teaching C++ or ArkTS any phonetic parsing rules.
#[derive(Clone, Debug)]
pub enum PhoneticParserKind {
    Xiaohe(Box<XiaoheShuangpinParserAdapter>),
    Quanpin(Box<QuanpinParser>),
    T9Pinyin(Box<T9PinyinParser>),
}

impl PhoneticParserKind {
    pub fn xiaohe() -> Result<Self, ParseError> {
        XiaoheShuangpinParserAdapter::xiaohe().map(|parser| Self::Xiaohe(Box::new(parser)))
    }

    pub fn quanpin() -> Self {
        Self::Quanpin(Box::default())
    }

    pub fn t9_pinyin() -> Self {
        Self::T9Pinyin(Box::default())
    }

    pub fn select_pinyin_combination(&mut self, index: usize) -> Result<ParseResult, ParseError> {
        match self {
            Self::T9Pinyin(parser) => parser.select_pinyin_combination(index),
            Self::Xiaohe(_) | Self::Quanpin(_) => Err(ParseError::InvalidCode {
                code: format!("pinyin-combination-{index}"),
            }),
        }
    }

    pub fn has_explicit_pinyin_selection(&self) -> bool {
        matches!(self, Self::T9Pinyin(parser) if parser.has_explicit_selection())
    }

    pub fn t9_internal_combinations(&self) -> Vec<String> {
        match self {
            Self::T9Pinyin(parser) => parser.internal_combinations(),
            Self::Xiaohe(_) | Self::Quanpin(_) => Vec::new(),
        }
    }

    pub fn publish_t9_joint_order(&mut self, ranked: &[String]) -> ParseResult {
        match self {
            Self::T9Pinyin(parser) => parser.publish_joint_order(ranked),
            Self::Xiaohe(_) | Self::Quanpin(_) => self.current_state(),
        }
    }

    pub fn t9_lattice_stats(&self) -> Option<T9LatticeStats> {
        match self {
            Self::T9Pinyin(parser) => Some(parser.lattice_stats()),
            Self::Xiaohe(_) | Self::Quanpin(_) => None,
        }
    }
}

impl PhoneticParser for PhoneticParserKind {
    type Error = ParseError;

    fn raw_input(&self) -> &str {
        match self {
            Self::Xiaohe(parser) => parser.raw_input(),
            Self::Quanpin(parser) => parser.raw_input(),
            Self::T9Pinyin(parser) => parser.raw_input(),
        }
    }

    fn process_key(&mut self, key: char) -> ParseResult {
        match self {
            Self::Xiaohe(parser) => parser.process_key(key),
            Self::Quanpin(parser) => parser.process_key(key),
            Self::T9Pinyin(parser) => parser.process_key(key),
        }
    }

    fn process_str(&mut self, input: &str) -> ParseResult {
        match self {
            Self::Xiaohe(parser) => parser.process_str(input),
            Self::Quanpin(parser) => parser.process_str(input),
            Self::T9Pinyin(parser) => parser.process_str(input),
        }
    }

    fn insert_segment_boundary(&mut self) -> Result<ParseResult, Self::Error> {
        match self {
            Self::Xiaohe(parser) => parser.insert_segment_boundary(),
            Self::Quanpin(parser) => parser.insert_segment_boundary(),
            Self::T9Pinyin(parser) => parser.insert_segment_boundary(),
        }
    }

    fn backspace(&mut self) -> ParseResult {
        match self {
            Self::Xiaohe(parser) => parser.backspace(),
            Self::Quanpin(parser) => parser.backspace(),
            Self::T9Pinyin(parser) => parser.backspace(),
        }
    }

    fn reset(&mut self) -> ParseResult {
        match self {
            Self::Xiaohe(parser) => parser.reset(),
            Self::Quanpin(parser) => parser.reset(),
            Self::T9Pinyin(parser) => parser.reset(),
        }
    }

    fn current_state(&self) -> ParseResult {
        match self {
            Self::Xiaohe(parser) => parser.current_state(),
            Self::Quanpin(parser) => parser.current_state(),
            Self::T9Pinyin(parser) => parser.current_state(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xiaohe_adapter_returns_common_metadata_without_alternatives() {
        let mut parser = XiaoheShuangpinParserAdapter::xiaohe().unwrap();
        parser.process_key('n');
        let result = parser.process_key('i');

        assert_eq!(result.raw_input, "ni");
        assert_eq!(result.display_segments, ["ni"]);
        assert_eq!(result.current_pinyin, "ni");
        assert!(result.pinyin_combinations.is_empty());
    }
}
