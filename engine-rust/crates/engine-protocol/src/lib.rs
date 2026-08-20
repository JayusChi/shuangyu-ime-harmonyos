pub mod composition;
pub mod error;

pub use composition::{
    CompositionResult, DateTimeFormatId, FormalCandidate, ParserState as ProtocolParserState,
    ProtocolAction, ABI_VERSION_DIRECT_ACTIONS, ABI_VERSION_PINYIN_STAGE1,
    ABI_VERSION_PINYIN_STAGE3, ABI_VERSION_STAGE1165, ABI_VERSION_STAGE1166, ABI_VERSION_STAGE1167,
    ABI_VERSION_STAGE12, ABI_VERSION_STAGE5, ABI_VERSION_STAGE7, ABI_VERSION_STAGE8,
    ABI_VERSION_STAGE9, ENGINE_VERSION_DIRECT_ACTIONS, ENGINE_VERSION_PINYIN_STAGE1,
    ENGINE_VERSION_PINYIN_STAGE2, ENGINE_VERSION_PINYIN_STAGE3, ENGINE_VERSION_STAGE1165,
    ENGINE_VERSION_STAGE1166, ENGINE_VERSION_STAGE1167, ENGINE_VERSION_STAGE12,
    ENGINE_VERSION_STAGE5, ENGINE_VERSION_STAGE7, ENGINE_VERSION_STAGE8, ENGINE_VERSION_STAGE9,
    INTERFACE_VERSION_DIRECT_ACTIONS, INTERFACE_VERSION_PINYIN_STAGE1,
    INTERFACE_VERSION_PINYIN_STAGE3, INTERFACE_VERSION_STAGE1165, INTERFACE_VERSION_STAGE1166,
    INTERFACE_VERSION_STAGE1167, INTERFACE_VERSION_STAGE12, INTERFACE_VERSION_STAGE5,
    INTERFACE_VERSION_STAGE7, INTERFACE_VERSION_STAGE8, INTERFACE_VERSION_STAGE9,
};
use error::ImeErrorCode;

pub const ENGINE_VERSION_STAGE0: &str = "0.0.1-stage0";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Candidate {
    pub id: String,
    pub text: String,
    pub reading: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EngineResult {
    pub success: bool,
    pub error_code: ImeErrorCode,
    pub error_message: String,
    pub raw_input: String,
    pub preedit_text: String,
    pub engine_version: String,
    pub candidates: Vec<Candidate>,
}

impl EngineResult {
    pub fn success(
        raw_input: &str,
        preedit_text: &str,
        engine_version: &str,
        candidates: Vec<Candidate>,
    ) -> Self {
        Self {
            success: true,
            error_code: ImeErrorCode::Success,
            error_message: String::new(),
            raw_input: raw_input.to_owned(),
            preedit_text: preedit_text.to_owned(),
            engine_version: engine_version.to_owned(),
            candidates,
        }
    }

    pub fn to_stage0_json(&self) -> String {
        let candidates = self
            .candidates
            .iter()
            .map(|candidate| {
                format!(
                    "{{\"id\":\"{}\",\"text\":\"{}\",\"reading\":\"{}\"}}",
                    escape_json(&candidate.id),
                    escape_json(&candidate.text),
                    escape_json(&candidate.reading)
                )
            })
            .collect::<Vec<_>>()
            .join(",");

        format!(
            "{{\"success\":{},\"errorCode\":{},\"errorMessage\":\"{}\",\"rawInput\":\"{}\",\"preeditText\":\"{}\",\"engineVersion\":\"{}\",\"candidates\":[{}]}}",
            if self.success { "true" } else { "false" },
            self.error_code.as_i32(),
            escape_json(&self.error_message),
            escape_json(&self.raw_input),
            escape_json(&self.preedit_text),
            escape_json(&self.engine_version),
            candidates
        )
    }
}

pub fn escape_json(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '\\' => escaped.push_str("\\\\"),
            '"' => escaped.push_str("\\\""),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            c if c.is_control() => escaped.push_str(&format!("\\u{:04x}", c as u32)),
            c => escaped.push(c),
        }
    }
    escaped
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serializes_stage0_result() {
        let result = EngineResult::success(
            "test",
            "测试",
            ENGINE_VERSION_STAGE0,
            vec![Candidate {
                id: "test-1".to_owned(),
                text: "测试".to_owned(),
                reading: "ce shi".to_owned(),
            }],
        );

        let json = result.to_stage0_json();
        assert!(json.contains("\"success\":true"));
        assert!(json.contains("\"errorCode\":0"));
        assert!(json.contains("\"text\":\"测试\""));
    }
}
