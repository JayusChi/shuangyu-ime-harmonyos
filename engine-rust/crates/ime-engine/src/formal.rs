use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::fs;
use std::io::ErrorKind;
use std::sync::Arc;

use candidate_query::{
    CandidateQueryEngine, PrefixRecallStrategy, QueryConfig, QueryMode, QueryRequest,
};
use candidate_ranking::{
    deduplicate_candidates, rank_candidates_with_user_scores,
    rank_prefix_candidates_with_user_scores, CandidateMatchType, RankingCandidate,
};
use code_table_runtime::{
    CategorySelectionSnapshot, CodeTableBundle, CodeTableErrorKind, CodeTableInputState,
    CodeTableQueryStrategy, CodeTableSelection, CodeTableStateMachine,
    DateTimeFormatId as RuntimeDateTimeFormatId, FunctionalAction, FunctionalActionTable,
    FIXTURE_SCHEME_ID, PRODUCTION_SCHEME_ID,
};
use engine_protocol::error::ImeErrorCode;
use engine_protocol::{
    CompositionResult, DateTimeFormatId, FormalCandidate, ProtocolAction, ProtocolParserState,
    ENGINE_VERSION_DIRECT_ACTIONS,
};
use lexicon_core::{load_binary_lexicon, BinaryLexicon};
use pinyin_syllable::all_syllables;
use sentence_decoder::{
    t9_sentence_candidate_penalty, DecodeLimits, SentenceCandidate, SentenceDecoder,
    T9JointDecodeResult, T9JointLimits, T9JointSession,
};
use shuangpin_parser::{
    t9_signature, ParseResult, ParseStatus, PhoneticParser, PhoneticParserKind, QueryIntent,
    T9_MAX_PINYIN_COMBINATIONS, T9_MAX_RAW_DIGITS,
};
use user_lexicon::{
    load_snapshot_recovering, merge_candidates, merge_candidates_exact_or_prefix,
    merge_user_lexicon_snapshots, UserLexiconEntry, UserLexiconError, UserLexiconField,
    UserLexiconLoadAction, UserLexiconReason, UserLexiconSnapshot,
};
use user_model::{CandidateSourceKind, UserCandidateKey, UserModel, UserModelStatus};

use crate::candidate_session::{CandidateSession, EngineCandidate};
use crate::engine_error::{EngineCreateError, EngineOperationError};
use crate::quanpin_context_reranking::{
    QuanpinContextReranker, QuanpinContextRerankingConfig, QuanpinContextRerankingStatus,
};
use crate::quanpin_features::{
    expansion_paths, ExpansionKind, QuanpinExpansionStats, QuanpinFeatureConfig,
    MAX_CANDIDATES_PER_EXPANSION_PATH, MAX_COMBINED_SENTENCE_DECODE_PATHS,
    MAX_FUZZY_SENTENCE_DECODE_PATHS, MAX_MERGED_CANDIDATES,
    MAX_SENTENCE_DECODE_PATHS_BY_SPELLING_KIND, QUANPIN_EXPANSION_CACHE_CAPACITY,
};
use crate::t9_joint::{merge_ranked_paths, T9JointDecoderStats};
use context_reranker::RerankStats;

const PROGRESSIVE_CODE_TABLE_MAX_CANDIDATES: usize = 512;
const SHUANGPIN_MAX_AMBIGUOUS_READING_PATHS: usize = 8;
const QUANPIN_MAX_DECODE_PATHS: usize = 4;
const QUANPIN_MAX_EXACT_PHRASE_CANDIDATES: usize = 8;
const T9_MAX_CANDIDATE_SNAPSHOT: usize = 256;
const T9_COMPLETE_COVERAGE_SCORE_BONUS: i64 = 2_000_000;
const T9_COMPATIBILITY_TIER: u8 = 2;
// Joint and compatibility sentences use the same calibrated decoder score.
// Keeping joint sentences in a lower tier made a parser-first, over-segmented
// reading outrank a better lexicon-backed sentence regardless of its score.
const T9_JOINT_SENTENCE_TIER: u8 = T9_COMPATIBILITY_TIER;
const T9_JOINT_SPECULATIVE_SENTENCE_TIER: u8 = 1;
const T9_JOINT_WHOLE_WORD_TIER: u8 = 3;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EngineConfig {
    pub scheme_id: String,
    pub lexicon_path: Option<String>,
    pub code_table_bundle_path: Option<String>,
    pub user_lexicon_path: Option<String>,
    pub code_table_action_fixture_path: Option<String>,
    pub code_table_action_fixture_sha256: Option<String>,
    pub candidate_page_size: usize,
    pub quanpin_features: QuanpinFeatureConfig,
    pub quanpin_context_reranking: QuanpinContextRerankingConfig,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            scheme_id: "xiaohe".to_owned(),
            lexicon_path: None,
            code_table_bundle_path: None,
            user_lexicon_path: None,
            code_table_action_fixture_path: None,
            code_table_action_fixture_sha256: None,
            candidate_page_size: QueryConfig::default().default_page_size,
            quanpin_features: QuanpinFeatureConfig::default(),
            quanpin_context_reranking: QuanpinContextRerankingConfig::default(),
        }
    }
}

#[derive(Clone, Debug)]
enum EngineBackend {
    Shuangpin,
    CodeTable(CodeTableStateMachine),
}

#[derive(Clone, Debug)]
pub struct ImeEngine {
    parser: Option<PhoneticParserKind>,
    scheme_id: String,
    backend: EngineBackend,
    code_table_bundle: Option<Arc<CodeTableBundle>>,
    code_table_action_table: Option<Arc<FunctionalActionTable>>,
    code_table_category_ids: Vec<String>,
    query_engine: Option<CandidateQueryEngine>,
    sentence_decoder: Option<SentenceDecoder>,
    user_model: UserModel,
    quanpin_context_reranker: QuanpinContextReranker,
    user_lexicon_path: Option<String>,
    user_lexicon: Arc<UserLexiconSnapshot>,
    session: CandidateSession,
    query_config: QueryConfig,
    quanpin_features: QuanpinFeatureConfig,
    quanpin_expansion_cache: VecDeque<(
        String,
        QuanpinFeatureConfig,
        Vec<crate::quanpin_features::ExpansionPath>,
        QuanpinExpansionStats,
    )>,
    last_quanpin_expansion_stats: QuanpinExpansionStats,
    last_quanpin_reranking_stats: RerankStats,
    t9_joint_limits: T9JointLimits,
    t9_joint_session: T9JointSession,
    last_t9_joint_stats: T9JointDecoderStats,
}

// Keep the public module stable while each responsibility lives in a focused fragment.
include!("formal/scheme_backend.rs");
include!("formal/composition_state.rs");
include!("formal/commit.rs");
include!("formal/user_learning.rs");
include!("formal/action_protocol.rs");
include!("formal/tests.rs");
