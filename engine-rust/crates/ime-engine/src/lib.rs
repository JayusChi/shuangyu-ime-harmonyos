mod candidate_session;
mod convenience_input;
mod engine_error;
mod formal;
mod quanpin_context_reranking;
mod quanpin_features;
mod t9_joint;

pub use engine_error::{EngineCreateError, EngineOperationError};
use engine_protocol::{Candidate, EngineResult, ENGINE_VERSION_STAGE0};
pub use formal::{EngineConfig, ImeEngine};
pub use quanpin_context_reranking::{
    QuanpinContextRerankingConfig, QuanpinContextRerankingStatus,
    QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION,
};
pub use quanpin_features::{
    expansion_paths, ExpansionPath, FuzzyOption, QuanpinExpansionStats, QuanpinFeatureConfig,
    MAX_SPELLING_EDIT_DISTANCE, QUANPIN_FEATURE_CONFIG_VERSION,
};
pub use sentence_decoder::T9JointLimits;
pub use shuangpin_parser::{
    ParseResult, ParseStatus, ParserState, PhoneticParser, QueryIntent, ShuangpinParser,
    XiaoheShuangpinParserAdapter,
};
pub use t9_joint::T9JointDecoderStats;

pub trait FixedCandidateEngine {
    fn version(&self) -> &str;
    fn reset(&mut self);
    fn get_test_candidates(&self, input: &str) -> EngineResult;
}

#[derive(Default)]
pub struct Stage0ImeEngine;

/// Creates a standalone Xiaohe shuangpin parser for the Rust engine layer.
///
/// The returned parser is not exposed through the current stage 0/3 FFI. Stage
/// 5 can wrap this API with a stable engine handle and C ABI.
pub fn create_xiaohe_shuangpin_parser() -> Result<ShuangpinParser, shuangpin_parser::ParseError> {
    ShuangpinParser::xiaohe()
}

impl FixedCandidateEngine for Stage0ImeEngine {
    fn version(&self) -> &str {
        ENGINE_VERSION_STAGE0
    }

    fn reset(&mut self) {}

    fn get_test_candidates(&self, input: &str) -> EngineResult {
        EngineResult::success(
            input,
            "测试",
            self.version(),
            vec![
                Candidate {
                    id: "test-1".to_owned(),
                    text: "测试".to_owned(),
                    reading: "ce shi".to_owned(),
                },
                Candidate {
                    id: "test-2".to_owned(),
                    text: "候选".to_owned(),
                    reading: "hou xuan".to_owned(),
                },
                Candidate {
                    id: "test-3".to_owned(),
                    text: "鸿蒙".to_owned(),
                    reading: "hong meng".to_owned(),
                },
            ],
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stage0_engine_returns_fixed_candidates() {
        let engine = Stage0ImeEngine;
        let result = engine.get_test_candidates("test");

        assert!(result.success);
        assert_eq!(result.raw_input, "test");
        assert_eq!(result.engine_version, "0.0.1-stage0");
        assert_eq!(result.candidates.len(), 3);
    }

    #[test]
    fn stage4_parser_is_available_without_changing_fixed_candidates() {
        let mut parser = create_xiaohe_shuangpin_parser().unwrap();
        let parsed = parser.process_str("xm");

        assert_eq!(parsed.status, ParseStatus::Complete);
        assert_eq!(parsed.syllables[0].syllable, "xian");

        let engine = Stage0ImeEngine;
        assert_eq!(engine.get_test_candidates("test").candidates.len(), 3);
    }
}
