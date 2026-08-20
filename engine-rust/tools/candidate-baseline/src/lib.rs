use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use candidate_query::{
    CandidateQueryEngine, PrefixRecallStrategy, QueryConfig, QueryMode, QueryRequest,
};
use candidate_ranking::{
    deduplicate_candidates, rank_candidates, rank_prefix_candidates,
    rank_prefix_candidates_with_user_scores, CandidateMatchType, RankingCandidate,
};
use code_table_runtime::{
    CodeTableBundle, CodeTableCandidate, CodeTableMatch, CodeTableQueryStrategy,
    CodeTableStateMachine, PRODUCTION_SCHEME_ID,
};
use engine_protocol::{CompositionResult, FormalCandidate};
use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::{load_binary_lexicon, runtime_index, BinaryLexicon, LexiconEntry};

mod anonymous_distribution;
mod context_evaluation;
mod eval_json;
mod eval_sha256;
mod pinyin9_dataset;
mod pinyin9_evaluation;
mod quanpin_dataset;
mod quanpin_evaluation;

pub use anonymous_distribution::validate as validate_quanpin_anonymous_distribution;
pub use context_evaluation::{
    discover_quanpin_context_improvements, evaluate_quanpin_context_dataset,
    freeze_quanpin_context_dataset, QuanpinContextEvaluationRequest,
};
pub use pinyin9_dataset::create_pinyin9_dataset;
pub use pinyin9_evaluation::{
    evaluate_pinyin9_dataset, freeze_pinyin9_dataset, freeze_pinyin9_implementation,
    validate_pinyin9_dataset, Pinyin9EvaluationRequest,
};
pub use quanpin_dataset::create_quanpin_dataset;
pub use quanpin_evaluation::{
    evaluate_quanpin_dataset, freeze_quanpin_dataset, validate_quanpin_dataset,
    QuanpinEvaluationRequest,
};

pub const PAGE_SIZE_REQUESTED_BY_ARKTS: usize = 50;
pub const EFFECTIVE_PAGE_SIZE: usize = 9;
pub const SHUANGPIN_CANDIDATE_LIMIT: usize = 64;
pub const YINXING_CANDIDATE_LIMIT: usize = 512;

fn stage_zero_query_config() -> QueryConfig {
    QueryConfig {
        default_page_size: 5,
        max_page_size: EFFECTIVE_PAGE_SIZE,
        max_candidates: SHUANGPIN_CANDIDATE_LIMIT,
        prefix_recall_limit: SHUANGPIN_CANDIDATE_LIMIT,
        prefix_snapshot_limit: SHUANGPIN_CANDIDATE_LIMIT,
        prefix_recall_strategy: PrefixRecallStrategy::LexicalEarlyStop,
        max_prefix_index_records: 128,
        ..QueryConfig::default()
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum Json {
    Null,
    Bool(bool),
    Number(u128),
    String(String),
    Array(Vec<Json>),
    Object(Vec<(String, Json)>),
}

impl Json {
    fn render(&self) -> String {
        let mut output = String::new();
        self.write(&mut output, 0);
        output.push('\n');
        output
    }

    fn write(&self, output: &mut String, indent: usize) {
        match self {
            Self::Null => output.push_str("null"),
            Self::Bool(value) => output.push_str(if *value { "true" } else { "false" }),
            Self::Number(value) => output.push_str(&value.to_string()),
            Self::String(value) => write_quoted(output, value),
            Self::Array(values) => {
                if values.is_empty() {
                    output.push_str("[]");
                    return;
                }
                output.push_str("[\n");
                for (index, value) in values.iter().enumerate() {
                    write_indent(output, indent + 1);
                    value.write(output, indent + 1);
                    if index + 1 != values.len() {
                        output.push(',');
                    }
                    output.push('\n');
                }
                write_indent(output, indent);
                output.push(']');
            }
            Self::Object(fields) => {
                if fields.is_empty() {
                    output.push_str("{}");
                    return;
                }
                output.push_str("{\n");
                for (index, (name, value)) in fields.iter().enumerate() {
                    write_indent(output, indent + 1);
                    write_quoted(output, name);
                    output.push_str(": ");
                    value.write(output, indent + 1);
                    if index + 1 != fields.len() {
                        output.push(',');
                    }
                    output.push('\n');
                }
                write_indent(output, indent);
                output.push('}');
            }
        }
    }
}

fn object(fields: impl IntoIterator<Item = (&'static str, Json)>) -> Json {
    Json::Object(
        fields
            .into_iter()
            .map(|(name, value)| (name.to_owned(), value))
            .collect(),
    )
}

fn string(value: impl Into<String>) -> Json {
    Json::String(value.into())
}

fn number(value: usize) -> Json {
    Json::Number(value as u128)
}

fn bool_value(value: bool) -> Json {
    Json::Bool(value)
}

fn optional_number(value: Option<usize>) -> Json {
    value.map(number).unwrap_or(Json::Null)
}

fn strings<'a>(values: impl IntoIterator<Item = &'a str>) -> Json {
    Json::Array(values.into_iter().map(string).collect())
}

fn write_indent(output: &mut String, indent: usize) {
    for _ in 0..indent {
        output.push_str("  ");
    }
}

fn write_quoted(output: &mut String, value: &str) {
    output.push('"');
    for ch in value.chars() {
        match ch {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            '\u{08}' => output.push_str("\\b"),
            '\u{0c}' => output.push_str("\\f"),
            ch if ch < '\u{20}' => {
                output.push_str(&format!("\\u{:04x}", ch as u32));
            }
            ch => output.push(ch),
        }
    }
    output.push('"');
}

pub fn render_stable_files(
    lexicon_path: &Path,
    bundle_path: &Path,
) -> Result<BTreeMap<&'static str, String>, String> {
    let lexicon_bytes = fs::read(lexicon_path).map_err(|error| error.to_string())?;
    let lexicon = load_binary_lexicon(&lexicon_bytes).map_err(|error| error.to_string())?;
    let bundle = Arc::new(
        CodeTableBundle::load_frozen_production_file(bundle_path)
            .map_err(|error| error.to_string())?,
    );
    bundle
        .validate_scheme_identity(PRODUCTION_SCHEME_ID)
        .map_err(|error| error.to_string())?;

    let shape_h = render_shape_h(&bundle)?;
    let double_pinyin_h = render_double_pinyin_h(&lexicon)?;
    let regressions = render_regressions(lexicon_path, bundle_path)?;

    let mut files = BTreeMap::new();
    files.insert("flypy-shape-h.json", shape_h.render());
    files.insert("flypy-double-pinyin-h.json", double_pinyin_h.render());
    files.insert("single-key-baseline.json", regressions.single_key.render());
    files.insert("double-key-baseline.json", regressions.double_key.render());
    files.insert("sentence-baseline.json", regressions.sentence.render());
    files.insert(
        "interaction-baseline.json",
        regressions.interaction.render(),
    );
    Ok(files)
}

pub fn write_stable_files(
    lexicon_path: &Path,
    bundle_path: &Path,
    output_dir: &Path,
) -> Result<(), String> {
    fs::create_dir_all(output_dir).map_err(|error| error.to_string())?;
    for (name, contents) in render_stable_files(lexicon_path, bundle_path)? {
        fs::write(output_dir.join(name), contents).map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn render_shape_h(bundle: &Arc<CodeTableBundle>) -> Result<Json, String> {
    let rules = Arc::new(
        bundle
            .user_rules
            .clone()
            .ok_or_else(|| "production bundle has no embedded user rules".to_owned())?,
    );
    let mut state = CodeTableStateMachine::new_with_query_strategy(
        Arc::clone(bundle),
        EFFECTIVE_PAGE_SIZE,
        YINXING_CANDIDATE_LIMIT,
        rules,
        CodeTableQueryStrategy::ProgressiveXiaoheYinxing,
    )
    .map_err(|error| error.to_string())?;
    state.process_key('h').map_err(|error| error.to_string())?;
    let candidates = state.all_candidates();
    let exact_count = candidates
        .iter()
        .take_while(|candidate| candidate.match_type == CodeTableMatch::Exact)
        .count();
    let first_prefix_index = candidates
        .iter()
        .position(|candidate| candidate.match_type == CodeTableMatch::Prefix);
    let unique_text_count = candidates
        .iter()
        .map(|candidate| candidate.text.as_str())
        .collect::<BTreeSet<_>>()
        .len();

    Ok(object([
        (
            "schema_version",
            string("candidate-baseline/flypy-shape-h/1"),
        ),
        ("scheme_id", string(PRODUCTION_SCHEME_ID)),
        ("raw_input", string("h")),
        ("query_strategy", string("ProgressiveXiaoheYinxing")),
        ("candidate_limit", number(YINXING_CANDIDATE_LIMIT)),
        ("page_size", number(EFFECTIVE_PAGE_SIZE)),
        ("candidate_page", number(state.current_page())),
        ("has_previous_page", bool_value(state.has_previous_page())),
        ("has_next_page", bool_value(state.has_next_page())),
        ("total_candidate_count", number(candidates.len())),
        ("unique_text_count", number(unique_text_count)),
        ("exact_one_key_count", number(exact_count)),
        (
            "first_prefix_candidate_index",
            first_prefix_index.map_or(Json::Null, number),
        ),
        (
            "exact_prefix_boundary",
            object([
                (
                    "last_exact_candidate",
                    candidates
                        .get(exact_count.saturating_sub(1))
                        .map_or(Json::Null, shape_candidate),
                ),
                (
                    "first_longer_prefix_candidate",
                    candidates
                        .get(exact_count)
                        .map_or(Json::Null, shape_candidate),
                ),
            ]),
        ),
        (
            "first_9",
            Json::Array(candidates.iter().take(9).map(shape_candidate).collect()),
        ),
        (
            "first_50",
            Json::Array(candidates.iter().take(50).map(shape_candidate).collect()),
        ),
        (
            "first_100",
            Json::Array(candidates.iter().take(100).map(shape_candidate).collect()),
        ),
        (
            "all_candidates_after_user_rules_before_paging",
            Json::Array(candidates.iter().map(shape_candidate).collect()),
        ),
    ]))
}

fn shape_candidate(candidate: &CodeTableCandidate) -> Json {
    object([
        ("text", string(&candidate.text)),
        ("complete_code", string(&candidate.code)),
        ("category", string(&candidate.category_id)),
        ("source_order", Json::Number(candidate.source_order as u128)),
        (
            "match_type",
            string(match candidate.match_type {
                CodeTableMatch::Exact => "exact",
                CodeTableMatch::Prefix => "prefix",
            }),
        ),
        (
            "is_user_rule",
            bool_value(candidate.category_id == "user-lexicon"),
        ),
        ("stable_id", string(&candidate.id)),
    ])
}

fn render_double_pinyin_h(lexicon: &BinaryLexicon) -> Result<Json, String> {
    let all_indexes = runtime_index::find_prefix_indexes(lexicon, "h", usize::MAX);
    let all_entries = all_indexes
        .iter()
        .flat_map(|index| entries_for_index(lexicon, index.start, index.len))
        .collect::<Vec<_>>();
    let all_unique_text = all_entries
        .iter()
        .map(|entry| entry.word.as_str())
        .collect::<BTreeSet<_>>()
        .len();
    let all_unique_text_reading = all_entries
        .iter()
        .map(|entry| (entry.word.as_str(), entry.pinyin_key.as_str()))
        .collect::<BTreeSet<_>>()
        .len();

    let mut recalled_entries = Vec::new();
    let mut scanned_indexes = Vec::new();
    for index in runtime_index::find_prefix_indexes(
        lexicon,
        "h",
        stage_zero_query_config().max_prefix_index_records,
    ) {
        scanned_indexes.push(index.pinyin_key.clone());
        recalled_entries.extend(entries_for_index(lexicon, index.start, index.len));
        if recalled_entries.len() >= SHUANGPIN_CANDIDATE_LIMIT {
            break;
        }
    }
    recalled_entries.truncate(SHUANGPIN_CANDIDATE_LIMIT);
    let pre_rank = recalled_entries
        .iter()
        .map(|entry| ranking_candidate(lexicon.header.lexicon_version, entry))
        .collect::<Vec<_>>();
    let mut ranked = rank_candidates(pre_rank.clone());
    ranked.truncate(SHUANGPIN_CANDIDATE_LIMIT);

    let mut engine = CandidateQueryEngine::new(lexicon.clone(), stage_zero_query_config());
    let runtime = engine
        .query(QueryRequest::new(
            "xiaohe",
            "h",
            QueryMode::Prefix,
            PAGE_SIZE_REQUESTED_BY_ARKTS,
        ))
        .map_err(|error| error.to_string())?;
    if runtime.candidates != ranked {
        return Err("diagnostic recall does not match CandidateQueryEngine".to_owned());
    }

    let branch_counts = branch_counts(&pre_rank);
    let ha_count = *branch_counts.get("ha").unwrap_or(&0);
    let hai_count = *branch_counts.get("hai").unwrap_or(&0);
    let ha_hai_count = ha_count + hai_count;
    let all_branch_counts = entry_branch_counts(&all_entries);

    Ok(object([
        (
            "schema_version",
            string("candidate-baseline/flypy-double-pinyin-h/1"),
        ),
        ("scheme_id", string("xiaohe")),
        ("raw_input", string("h")),
        ("normalized_reading", string("h")),
        ("query_mode", string("Prefix")),
        ("production_h_prefix_index_count", number(all_indexes.len())),
        ("production_h_record_count", number(all_entries.len())),
        ("production_h_unique_text_count", number(all_unique_text)),
        (
            "production_h_unique_text_reading_count",
            number(all_unique_text_reading),
        ),
        (
            "all_h_first_syllable_branch_counts",
            count_map_json(&all_branch_counts),
        ),
        (
            "max_prefix_index_records",
            number(stage_zero_query_config().max_prefix_index_records),
        ),
        (
            "max_candidates",
            number(stage_zero_query_config().max_candidates),
        ),
        ("requested_page_size", number(PAGE_SIZE_REQUESTED_BY_ARKTS)),
        ("effective_page_size", number(runtime.page_size)),
        (
            "early_stop_confirmed",
            bool_value(
                recalled_entries.len() == SHUANGPIN_CANDIDATE_LIMIT
                    && scanned_indexes.len() < all_indexes.len(),
            ),
        ),
        (
            "scanned_index_count_before_stop",
            number(scanned_indexes.len()),
        ),
        (
            "scanned_pinyin_range",
            object([
                ("first", scanned_indexes.first().map_or(Json::Null, string)),
                ("last", scanned_indexes.last().map_or(Json::Null, string)),
            ]),
        ),
        (
            "scanned_pinyin_indexes",
            strings(scanned_indexes.iter().map(String::as_str)),
        ),
        ("pre_rank_recall_count", number(recalled_entries.len())),
        ("pre_rank_branch_counts", count_map_json(&branch_counts)),
        ("ha_count", number(ha_count)),
        ("hai_count", number(hai_count)),
        ("ha_hai_count", number(ha_hai_count)),
        (
            "ha_hai_ratio_basis_points",
            number(ha_hai_count * 10_000 / recalled_entries.len().max(1)),
        ),
        (
            "ha_hai_ratio_percent",
            string(format!(
                "{:.4}",
                ha_hai_count as f64 * 100.0 / recalled_entries.len() as f64
            )),
        ),
        (
            "pre_rank_recall",
            Json::Array(pre_rank.iter().map(ranking_json).collect()),
        ),
        (
            "ranked_first_9",
            Json::Array(ranked.iter().take(9).map(ranking_json).collect()),
        ),
        (
            "ranked_all_64",
            Json::Array(ranked.iter().map(ranking_json).collect()),
        ),
        ("candidate_page", number(0)),
        ("has_previous_page", bool_value(false)),
        (
            "has_next_page",
            bool_value(ranked.len() > runtime.page_size),
        ),
    ]))
}

fn entries_for_index(lexicon: &BinaryLexicon, start: u32, len: u32) -> &[LexiconEntry] {
    let start = start as usize;
    let end = start
        .saturating_add(len as usize)
        .min(lexicon.entries.len());
    &lexicon.entries[start..end]
}

fn ranking_candidate(lexicon_version: u32, entry: &LexiconEntry) -> RankingCandidate {
    RankingCandidate::new(
        format!(
            "lex-v{}-{}-{}",
            lexicon_version,
            entry.pinyin_key.replace(' ', "_"),
            entry.word
        ),
        entry.word.clone(),
        entry.pinyin_key.clone(),
        entry.source_key(),
        entry.frequency,
        CandidateMatchType::Prefix,
    )
    .with_source_order(entry.source_order)
}

fn ranking_json(candidate: &RankingCandidate) -> Json {
    object([
        ("text", string(&candidate.text)),
        ("reading", string(&candidate.reading)),
        ("source", string(&candidate.source)),
        ("frequency", Json::Number(candidate.frequency as u128)),
        (
            "match_type",
            string(match candidate.match_type {
                CandidateMatchType::Exact => "exact",
                CandidateMatchType::Prefix => "prefix",
            }),
        ),
        ("stable_id", string(&candidate.id)),
    ])
}

fn first_syllable(reading: &str) -> &str {
    reading.split_whitespace().next().unwrap_or(reading)
}

fn branch_counts(candidates: &[RankingCandidate]) -> BTreeMap<String, usize> {
    let mut counts = BTreeMap::new();
    for candidate in candidates {
        *counts
            .entry(first_syllable(&candidate.reading).to_owned())
            .or_insert(0) += 1;
    }
    counts
}

fn entry_branch_counts(entries: &[&LexiconEntry]) -> BTreeMap<String, usize> {
    let mut counts = BTreeMap::new();
    for entry in entries {
        *counts
            .entry(first_syllable(&entry.pinyin_key).to_owned())
            .or_insert(0) += 1;
    }
    counts
}

fn count_map_json(counts: &BTreeMap<String, usize>) -> Json {
    Json::Object(
        counts
            .iter()
            .map(|(key, count)| (key.clone(), number(*count)))
            .collect(),
    )
}

struct RegressionFiles {
    single_key: Json,
    double_key: Json,
    sentence: Json,
    interaction: Json,
}

fn render_regressions(lexicon_path: &Path, bundle_path: &Path) -> Result<RegressionFiles, String> {
    let single_inputs = ["a", "h", "n", "s", "z"];
    let double_inputs = ["hc", "ni", "ui", "vi"];
    let mut engine = new_engine(lexicon_path, bundle_path, PRODUCTION_SCHEME_ID)?;
    engine.set_session_learning_allowed(false);
    let single_key = object([
        ("schema_version", string("candidate-baseline/single-key/1")),
        ("page_size", number(EFFECTIVE_PAGE_SIZE)),
        (
            "cases",
            Json::Array(
                ["xiaohe", PRODUCTION_SCHEME_ID]
                    .into_iter()
                    .flat_map(|scheme| single_inputs.into_iter().map(move |input| (scheme, input)))
                    .map(|(scheme, input)| engine_case(&mut engine, scheme, input))
                    .collect::<Result<Vec<_>, _>>()?,
            ),
        ),
    ]);
    let double_key = object([
        ("schema_version", string("candidate-baseline/double-key/1")),
        ("page_size", number(EFFECTIVE_PAGE_SIZE)),
        (
            "cases",
            Json::Array(
                ["xiaohe", PRODUCTION_SCHEME_ID]
                    .into_iter()
                    .flat_map(|scheme| double_inputs.into_iter().map(move |input| (scheme, input)))
                    .map(|(scheme, input)| engine_case(&mut engine, scheme, input))
                    .collect::<Result<Vec<_>, _>>()?,
            ),
        ),
    ]);
    let sentence = object([
        (
            "schema_version",
            string("candidate-baseline/sentence-and-partial-commit/1"),
        ),
        (
            "sentence_cases",
            Json::Array(
                ["nihc", "uurufa"]
                    .into_iter()
                    .map(|input| engine_case(&mut engine, "xiaohe", input))
                    .collect::<Result<Vec<_>, _>>()?,
            ),
        ),
        ("partial_commit", render_partial_commit(&mut engine)?),
    ]);
    let interaction = object([
        (
            "schema_version",
            string("candidate-baseline/interactions/1"),
        ),
        (
            "shape_four_code_unique",
            engine_trace(&mut engine, PRODUCTION_SCHEME_ID, "aaba")?,
        ),
        (
            "shape_four_code_multiple",
            engine_trace(&mut engine, PRODUCTION_SCHEME_ID, "ahqi")?,
        ),
        (
            "shape_h_paging",
            paging_case(&mut engine, PRODUCTION_SCHEME_ID, "h")?,
        ),
        (
            "double_pinyin_h_paging",
            paging_case(&mut engine, "xiaohe", "h")?,
        ),
        (
            "shape_h_first_candidate_commit",
            commit_case(&mut engine, PRODUCTION_SCHEME_ID, "h", 0)?,
        ),
        (
            "double_pinyin_h_first_candidate_commit",
            commit_case(&mut engine, "xiaohe", "h", 0)?,
        ),
    ]);
    Ok(RegressionFiles {
        single_key,
        double_key,
        sentence,
        interaction,
    })
}

fn new_engine(lexicon_path: &Path, bundle_path: &Path, scheme: &str) -> Result<ImeEngine, String> {
    new_engine_with_page_size(lexicon_path, bundle_path, scheme, EFFECTIVE_PAGE_SIZE)
}

fn new_engine_with_page_size(
    lexicon_path: &Path,
    bundle_path: &Path,
    scheme: &str,
    page_size: usize,
) -> Result<ImeEngine, String> {
    ImeEngine::new_with_query_config(
        EngineConfig {
            scheme_id: scheme.to_owned(),
            lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
            code_table_bundle_path: if scheme == PRODUCTION_SCHEME_ID {
                Some(bundle_path.to_string_lossy().into_owned())
            } else {
                None
            },
            user_lexicon_path: None,
            code_table_action_fixture_path: None,
            code_table_action_fixture_sha256: None,
            candidate_page_size: page_size,
            quanpin_features: Default::default(),
            quanpin_context_reranking: Default::default(),
        },
        stage_zero_query_config(),
    )
    .map_err(|error| error.to_string())
}

fn new_production_engine_with_page_size(
    lexicon_path: &Path,
    bundle_path: &Path,
    scheme: &str,
    page_size: usize,
) -> Result<ImeEngine, String> {
    ImeEngine::new(EngineConfig {
        scheme_id: scheme.to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        code_table_bundle_path: if scheme == PRODUCTION_SCHEME_ID {
            Some(bundle_path.to_string_lossy().into_owned())
        } else {
            None
        },
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .map_err(|error| error.to_string())
}

fn process_input(engine: &mut ImeEngine, input: &str) -> CompositionResult {
    let mut result = engine.current_state();
    for key in input.chars() {
        result = engine.process_key(key);
    }
    result
}

fn prepare_engine(engine: &mut ImeEngine, scheme: &str) -> Result<(), String> {
    engine.reset();
    if engine.scheme_id() != scheme {
        engine
            .change_scheme(scheme)
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn engine_case(engine: &mut ImeEngine, scheme: &str, input: &str) -> Result<Json, String> {
    prepare_engine(engine, scheme)?;
    let result = process_input(engine, input);
    Ok(object([
        ("scheme_id", string(scheme)),
        ("input", string(input)),
        ("result", composition_json(&result)),
    ]))
}

fn engine_trace(engine: &mut ImeEngine, scheme: &str, input: &str) -> Result<Json, String> {
    prepare_engine(engine, scheme)?;
    let mut steps = Vec::new();
    for key in input.chars() {
        let result = engine.process_key(key);
        steps.push(object([
            ("key", string(key.to_string())),
            ("result", composition_json(&result)),
        ]));
    }
    Ok(object([
        ("scheme_id", string(scheme)),
        ("input", string(input)),
        ("steps", Json::Array(steps)),
    ]))
}

fn paging_case(engine: &mut ImeEngine, scheme: &str, input: &str) -> Result<Json, String> {
    prepare_engine(engine, scheme)?;
    let first = process_input(engine, input);
    let (next, previous) = if first.has_next_page {
        let next = engine
            .next_candidate_page()
            .map_err(|error| format!("{error:?}"))?;
        let previous = engine
            .previous_candidate_page()
            .map_err(|error| format!("{error:?}"))?;
        (composition_json(&next), composition_json(&previous))
    } else {
        (Json::Null, Json::Null)
    };
    Ok(object([
        ("scheme_id", string(scheme)),
        ("input", string(input)),
        ("first_page", composition_json(&first)),
        ("next_page", next),
        ("previous_page", previous),
    ]))
}

fn commit_case(
    engine: &mut ImeEngine,
    scheme: &str,
    input: &str,
    page_index: usize,
) -> Result<Json, String> {
    prepare_engine(engine, scheme)?;
    let before = process_input(engine, input);
    let selected = before
        .candidates
        .get(page_index)
        .map(|candidate| candidate.text.clone())
        .ok_or_else(|| "candidate missing for commit case".to_owned())?;
    let after = engine
        .select_candidate(page_index)
        .map_err(|error| format!("{error:?}"))?;
    Ok(object([
        ("scheme_id", string(scheme)),
        ("input", string(input)),
        ("selected_page_index", number(page_index)),
        ("selected_text", string(selected)),
        ("before", composition_json(&before)),
        ("after", composition_json(&after)),
    ]))
}

fn render_partial_commit(engine: &mut ImeEngine) -> Result<Json, String> {
    prepare_engine(engine, "xiaohe")?;
    let before = process_input(engine, "uurufa");
    let index = before
        .candidates
        .iter()
        .position(|candidate| candidate.text == "输入")
        .ok_or_else(|| "partial candidate 输入 is not on current page".to_owned())?;
    let after = engine
        .select_candidate(index)
        .map_err(|error| format!("{error:?}"))?;
    Ok(object([
        ("input", string("uurufa")),
        ("selected_page_index", number(index)),
        ("selected_text", string("输入")),
        ("before", composition_json(&before)),
        ("after", composition_json(&after)),
    ]))
}

fn composition_json(result: &CompositionResult) -> Json {
    object([
        ("success", bool_value(result.success)),
        ("raw_input", string(&result.raw_input)),
        ("preedit_text", string(&result.preedit_text)),
        (
            "parsed_syllables",
            strings(result.parsed_syllables.iter().map(String::as_str)),
        ),
        ("pending_code", string(&result.pending_code)),
        ("parser_state", string(result.parser_state.as_str())),
        ("candidate_count", number(result.candidates.len())),
        (
            "candidates",
            Json::Array(
                result
                    .candidates
                    .iter()
                    .map(formal_candidate_json)
                    .collect(),
            ),
        ),
        (
            "candidate_page",
            Json::Number(result.candidate_page as u128),
        ),
        ("has_previous_page", bool_value(result.has_previous_page)),
        ("has_next_page", bool_value(result.has_next_page)),
        ("commit_text", string(&result.commit_text)),
        (
            "composition_finished",
            bool_value(result.composition_finished),
        ),
        ("json_utf8_bytes", number(result.to_json().len())),
    ])
}

fn formal_candidate_json(candidate: &FormalCandidate) -> Json {
    object([
        ("text", string(&candidate.text)),
        ("reading", string(&candidate.reading)),
        ("source", string(&candidate.source)),
        ("stable_id", string(&candidate.id)),
    ])
}

pub fn render_stage3_report(
    lexicon_path: &Path,
    warmups: usize,
    samples: usize,
) -> Result<String, String> {
    if samples == 0 {
        return Err("samples must be positive".to_owned());
    }
    let process_start = memory_snapshot();
    let lexicon_bytes = fs::read(lexicon_path).map_err(|error| error.to_string())?;
    let lexicon = load_binary_lexicon(&lexicon_bytes).map_err(|error| error.to_string())?;
    let after_load = memory_snapshot();
    let current_config = QueryConfig::default();

    let mut current_engine = CandidateQueryEngine::new(lexicon.clone(), current_config.clone());
    let current_h = current_engine
        .query(QueryRequest::new("xiaohe", "h", QueryMode::Prefix, 50))
        .map_err(|error| error.to_string())?;
    let current_h_cached = current_engine
        .query(QueryRequest::new("xiaohe", "h", QueryMode::Prefix, 50))
        .map_err(|error| error.to_string())?;
    if !current_h_cached.cache_hit || current_h_cached.candidates != current_h.candidates {
        return Err("stage 3 h cache hit differs from cold result".to_owned());
    }
    let after_current_h_query = memory_snapshot();
    let mut legacy_engine = CandidateQueryEngine::new(lexicon.clone(), stage_zero_query_config());
    let legacy_h = legacy_engine
        .query(QueryRequest::new("xiaohe", "h", QueryMode::Prefix, 50))
        .map_err(|error| error.to_string())?;

    let final_h = collect_current_snapshot(lexicon_path, "h", 50)?;
    let page_sizes = [9usize, 20, 30, 50];
    let page_snapshots = page_sizes
        .into_iter()
        .map(|page_size| {
            collect_current_snapshot(lexicon_path, "h", page_size)
                .map(|candidates| (page_size, candidates))
        })
        .collect::<Result<Vec<_>, _>>()?;
    let pagination_consistent = page_snapshots
        .iter()
        .all(|(_, candidates)| candidates == &final_h);
    if !pagination_consistent {
        return Err("stage 3 page-size concatenation differs".to_owned());
    }

    let mut cold_all = Vec::new();
    let mut hot_all = Vec::new();
    let mut single_key_reports = Vec::new();
    for letter in 'a'..='z' {
        let reading = letter.to_string();
        let indexes = runtime_index::find_prefix_indexes(&lexicon, &reading, usize::MAX);
        let scanned_candidates = indexes
            .iter()
            .map(|index| index.len as usize)
            .sum::<usize>();
        let all_entries = indexes
            .iter()
            .flat_map(|index| entries_for_index(&lexicon, index.start, index.len))
            .collect::<Vec<_>>();
        let matched_branch_counts = entry_branch_counts(&all_entries);

        for _ in 0..warmups {
            let mut engine = CandidateQueryEngine::new(lexicon.clone(), current_config.clone());
            let _ = engine
                .query(QueryRequest::new("xiaohe", &reading, QueryMode::Prefix, 50))
                .map_err(|error| error.to_string())?;
        }

        let mut cold = Vec::with_capacity(samples);
        let mut hot = Vec::with_capacity(samples);
        let mut result_for_report = None;
        for _ in 0..samples {
            let mut engine = CandidateQueryEngine::new(lexicon.clone(), current_config.clone());
            let started = Instant::now();
            let result = engine
                .query(QueryRequest::new("xiaohe", &reading, QueryMode::Prefix, 50))
                .map_err(|error| error.to_string())?;
            cold.push(started.elapsed());
            let started = Instant::now();
            let cached = engine
                .query(QueryRequest::new("xiaohe", &reading, QueryMode::Prefix, 50))
                .map_err(|error| error.to_string())?;
            hot.push(started.elapsed());
            if !cached.cache_hit || cached.candidates != result.candidates {
                return Err(format!("{reading} cache result differs"));
            }
            result_for_report = Some(result);
        }
        cold_all.extend(cold.iter().copied());
        hot_all.extend(hot.iter().copied());
        let result = result_for_report.expect("positive samples");
        let snapshot = result
            .candidates
            .iter()
            .take(current_config.prefix_snapshot_limit)
            .cloned()
            .collect::<Vec<_>>();
        let top_twenty = snapshot.iter().take(20).cloned().collect::<Vec<_>>();
        single_key_reports.push(object([
            ("input", string(&reading)),
            ("matched_index_count", number(indexes.len())),
            ("scanned_raw_candidate_count", number(scanned_candidates)),
            (
                "matched_first_syllable_branch_count",
                number(matched_branch_counts.len()),
            ),
            (
                "matched_first_syllable_branch_counts",
                count_map_json(&matched_branch_counts),
            ),
            ("recall_pool_size", number(result.candidates.len())),
            ("candidate_snapshot_size", number(snapshot.len())),
            (
                "top_20_first_syllable_branch_counts",
                count_map_json(&branch_counts(&top_twenty)),
            ),
            (
                "top_20",
                Json::Array(top_twenty.iter().map(ranking_json).collect()),
            ),
            (
                "cold_query",
                timing_summary_json("complete_scan_top_k_rank", &cold),
            ),
            ("hot_query", timing_summary_json("cache_hit", &hot)),
            ("cache_consistent", bool_value(true)),
        ]));
    }

    let exact_regressions = ["hc", "ni", "ui", "vi"]
        .into_iter()
        .map(|input| current_first_page_case(lexicon_path, input, 9))
        .collect::<Result<Vec<_>, _>>()?;
    let sentence_regressions = ["nihc", "uurufa"]
        .into_iter()
        .map(|input| current_first_page_case(lexicon_path, input, 9))
        .collect::<Result<Vec<_>, _>>()?;
    let partial_commit_regression = current_partial_commit_case(lexicon_path)?;
    let second_page_commit = current_second_page_commit(lexicon_path, "h", 50)?;
    let after_snapshots = memory_snapshot();

    let h_indexes = runtime_index::find_prefix_indexes(&lexicon, "h", usize::MAX);
    let h_scanned = h_indexes
        .iter()
        .map(|index| index.len as usize)
        .sum::<usize>();
    let h_final_ranking = final_h.iter().map(formal_to_ranking).collect::<Vec<_>>();
    let report = object([
        (
            "schema_version",
            string("candidate-improvement/stage3-host-report/1"),
        ),
        ("profile", string("release")),
        (
            "configuration",
            object([
                ("page_size", number(current_config.default_page_size)),
                ("max_page_size", number(current_config.max_page_size)),
                (
                    "exact_snapshot_limit",
                    number(current_config.max_candidates),
                ),
                (
                    "prefix_recall_pool_limit",
                    number(current_config.prefix_recall_limit),
                ),
                (
                    "prefix_snapshot_limit",
                    number(current_config.prefix_snapshot_limit),
                ),
            ]),
        ),
        (
            "h_comparison",
            object([
                ("matched_index_count", number(h_indexes.len())),
                ("scanned_raw_candidate_count", number(h_scanned)),
                ("legacy_recall_pool_size", number(legacy_h.candidates.len())),
                (
                    "legacy_branch_counts",
                    count_map_json(&branch_counts(&legacy_h.candidates)),
                ),
                (
                    "legacy_first_20",
                    Json::Array(
                        legacy_h
                            .candidates
                            .iter()
                            .take(20)
                            .map(ranking_json)
                            .collect(),
                    ),
                ),
                (
                    "legacy_first_50",
                    Json::Array(
                        legacy_h
                            .candidates
                            .iter()
                            .take(50)
                            .map(ranking_json)
                            .collect(),
                    ),
                ),
                (
                    "current_recall_pool_size",
                    number(current_h.candidates.len()),
                ),
                (
                    "current_recall_pool_branch_counts",
                    count_map_json(&branch_counts(&current_h.candidates)),
                ),
                ("current_snapshot_size", number(final_h.len())),
                (
                    "current_snapshot_branch_counts",
                    count_map_json(&branch_counts(&h_final_ranking)),
                ),
                (
                    "current_first_20",
                    Json::Array(final_h.iter().take(20).map(formal_candidate_json).collect()),
                ),
                (
                    "current_first_50",
                    Json::Array(final_h.iter().take(50).map(formal_candidate_json).collect()),
                ),
                ("cache_consistent", bool_value(true)),
            ]),
        ),
        ("single_key_a_to_z", Json::Array(single_key_reports)),
        (
            "pagination",
            object([
                (
                    "page_sizes",
                    Json::Array(page_sizes.into_iter().map(number).collect()),
                ),
                (
                    "snapshot_sizes",
                    Json::Array(
                        page_snapshots
                            .iter()
                            .map(|(page_size, candidates)| {
                                object([
                                    ("page_size", number(*page_size)),
                                    ("candidate_count", number(candidates.len())),
                                ])
                            })
                            .collect(),
                    ),
                ),
                ("concatenated_order_identical", bool_value(true)),
                ("second_page_commit", second_page_commit),
            ]),
        ),
        (
            "regressions",
            object([
                ("exact_double_key", Json::Array(exact_regressions)),
                (
                    "sentence_and_partial_inputs",
                    Json::Array(sentence_regressions),
                ),
                ("partial_commit", partial_commit_regression),
            ]),
        ),
        (
            "performance",
            object([
                ("warmup_count_per_key", number(warmups)),
                ("sample_count_per_key", number(samples)),
                (
                    "cold_a_to_z",
                    timing_summary_json("complete_scan_top_k_rank", &cold_all),
                ),
                ("hot_a_to_z", timing_summary_json("cache_hit", &hot_all)),
            ]),
        ),
        (
            "memory",
            object([
                (
                    "process_start_working_set_bytes",
                    Json::Number(process_start.working as u128),
                ),
                (
                    "after_lexicon_load_working_set_bytes",
                    Json::Number(after_load.working as u128),
                ),
                (
                    "after_current_h_query_working_set_bytes",
                    Json::Number(after_current_h_query.working as u128),
                ),
                (
                    "current_h_query_working_set_delta_bytes",
                    Json::Number(
                        after_current_h_query
                            .working
                            .saturating_sub(after_load.working) as u128,
                    ),
                ),
                (
                    "after_reports_working_set_bytes",
                    Json::Number(after_snapshots.working as u128),
                ),
                (
                    "report_working_set_delta_bytes",
                    Json::Number(after_snapshots.working.saturating_sub(after_load.working) as u128),
                ),
                (
                    "peak_working_set_bytes",
                    Json::Number(after_snapshots.peak as u128),
                ),
            ]),
        ),
    ]);
    Ok(format!("{}\n", report.render()))
}

/// Produces a deterministic stage 5 learning lifecycle report against the
/// production lexicon. The temporary model is removed by `clear_user_model`.
pub fn render_stage5_learning_report(lexicon_path: &Path) -> Result<String, String> {
    const INPUT: &str = "h";
    const TARGET_TEXT: &str = "会议";
    const SELECTIONS: usize = 4;

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    let model_path = std::env::temp_dir().join(format!("candidate-stage5-{nanos}.dat"));
    let mut engine = production_engine(lexicon_path, 50)?;
    engine
        .set_user_model_path(&model_path.to_string_lossy())
        .map_err(|error| format!("{error:?}"))?;
    let load_started = Instant::now();
    engine
        .load_user_model()
        .map_err(|error| format!("{error:?}"))?;
    let model_load_elapsed = load_started.elapsed();

    let baseline = collect_snapshot_from_engine(&mut engine, INPUT)?;
    let target_id = baseline
        .iter()
        .find(|candidate| candidate.text == TARGET_TEXT)
        .map(|candidate| candidate.id.clone())
        .ok_or_else(|| format!("stage 5 target is missing: {TARGET_TEXT}"))?;
    let baseline_rank = candidate_rank(&baseline, &target_id)?;
    let mut trajectory = vec![number(baseline_rank)];
    for _ in 0..SELECTIONS {
        select_candidate_by_id(&mut engine, INPUT, &target_id)?;
        let snapshot = collect_snapshot_from_engine(&mut engine, INPUT)?;
        trajectory.push(number(candidate_rank(&snapshot, &target_id)?));
    }
    let flush_started = Instant::now();
    engine
        .flush_user_model()
        .map_err(|error| format!("{error:?}"))?;
    let model_flush_elapsed = flush_started.elapsed();
    let learned_rank = *trajectory
        .last()
        .and_then(|value| match value {
            Json::Number(value) => Some(value),
            _ => None,
        })
        .expect("rank trajectory contains numbers");

    let mut reloaded = production_engine(lexicon_path, 50)?;
    reloaded
        .set_user_model_path(&model_path.to_string_lossy())
        .map_err(|error| format!("{error:?}"))?;
    reloaded
        .load_user_model()
        .map_err(|error| format!("{error:?}"))?;
    let persisted_rank = candidate_rank(
        &collect_snapshot_from_engine(&mut reloaded, INPUT)?,
        &target_id,
    )?;
    reloaded
        .clear_user_model()
        .map_err(|error| format!("{error:?}"))?;
    let cleared_rank = candidate_rank(
        &collect_snapshot_from_engine(&mut reloaded, INPUT)?,
        &target_id,
    )?;

    reloaded.set_session_learning_allowed(false);
    for _ in 0..SELECTIONS {
        select_candidate_by_id(&mut reloaded, INPUT, &target_id)?;
    }
    let disabled_rank = candidate_rank(
        &collect_snapshot_from_engine(&mut reloaded, INPUT)?,
        &target_id,
    )?;
    let _ = reloaded.clear_user_model();

    let lexicon_bytes = fs::read(lexicon_path).map_err(|error| error.to_string())?;
    let lexicon = load_binary_lexicon(&lexicon_bytes).map_err(|error| error.to_string())?;
    let mut query_engine = CandidateQueryEngine::new(lexicon, QueryConfig::default());
    let pool = query_engine
        .query(QueryRequest::new("xiaohe", INPUT, QueryMode::Prefix, 50))
        .map_err(|error| error.to_string())?
        .candidates;
    let mut dedup_samples = Vec::with_capacity(200);
    let mut system_sort_samples = Vec::with_capacity(200);
    let mut user_rerank_samples = Vec::with_capacity(200);
    for _ in 0..200 {
        let started = Instant::now();
        let _ = deduplicate_candidates(pool.clone());
        dedup_samples.push(started.elapsed());

        let started = Instant::now();
        let _ = rank_prefix_candidates(pool.clone());
        system_sort_samples.push(started.elapsed());

        let started = Instant::now();
        let _ = rank_prefix_candidates_with_user_scores(pool.clone(), |candidate| {
            if candidate.id == target_id {
                5_000
            } else {
                0
            }
        });
        user_rerank_samples.push(started.elapsed());
    }

    let report = object([
        (
            "schema_version",
            string("candidate-improvement/stage5-learning/1"),
        ),
        ("input", string(INPUT)),
        ("target_text", string(TARGET_TEXT)),
        ("target_stable_id", string(target_id)),
        ("selection_count", number(SELECTIONS)),
        ("rank_base_one_based", number(baseline_rank)),
        ("rank_trajectory_one_based", Json::Array(trajectory)),
        ("rank_after_learning_one_based", Json::Number(learned_rank)),
        ("rank_after_reload_one_based", number(persisted_rank)),
        ("rank_after_clear_one_based", number(cleared_rank)),
        (
            "rank_after_disabled_session_one_based",
            number(disabled_rank),
        ),
        (
            "persisted",
            bool_value(persisted_rank as u128 == learned_rank),
        ),
        (
            "clear_restored_baseline",
            bool_value(cleared_rank == baseline_rank),
        ),
        (
            "disabled_session_unchanged",
            bool_value(disabled_rank == baseline_rank),
        ),
        (
            "model_file_removed_after_clear",
            bool_value(!model_path.exists()),
        ),
        (
            "performance",
            object([
                ("ranking_pool_size", number(pool.len())),
                (
                    "deduplicate",
                    timing_summary_json("deduplicate_256_candidates", &dedup_samples),
                ),
                (
                    "system_prefix_sort",
                    timing_summary_json("prefix_quality_sort_256_candidates", &system_sort_samples),
                ),
                (
                    "user_rerank",
                    timing_summary_json("prefix_user_rerank_256_candidates", &user_rerank_samples),
                ),
                (
                    "empty_model_load_ns",
                    Json::Number(model_load_elapsed.as_nanos()),
                ),
                (
                    "four_selection_model_flush_ns",
                    Json::Number(model_flush_elapsed.as_nanos()),
                ),
            ]),
        ),
    ]);
    Ok(format!("{}\n", report.render()))
}

fn production_engine(lexicon_path: &Path, page_size: usize) -> Result<ImeEngine, String> {
    ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .map_err(|error| error.to_string())
}

fn collect_snapshot_from_engine(
    engine: &mut ImeEngine,
    input: &str,
) -> Result<Vec<FormalCandidate>, String> {
    engine.reset();
    let mut result = process_input(engine, input);
    let mut candidates = Vec::new();
    loop {
        candidates.extend(result.candidates);
        if !result.has_next_page {
            break;
        }
        result = engine
            .next_candidate_page()
            .map_err(|error| format!("{error:?}"))?;
    }
    Ok(candidates)
}

fn candidate_rank(candidates: &[FormalCandidate], stable_id: &str) -> Result<usize, String> {
    candidates
        .iter()
        .position(|candidate| candidate.id == stable_id)
        .map(|rank| rank + 1)
        .ok_or_else(|| format!("candidate disappeared from snapshot: {stable_id}"))
}

fn select_candidate_by_id(
    engine: &mut ImeEngine,
    input: &str,
    stable_id: &str,
) -> Result<(), String> {
    engine.reset();
    let mut result = process_input(engine, input);
    loop {
        if let Some(index) = result
            .candidates
            .iter()
            .position(|candidate| candidate.id == stable_id)
        {
            engine
                .select_candidate(index)
                .map_err(|error| format!("{error:?}"))?;
            return Ok(());
        }
        if !result.has_next_page {
            return Err(format!("candidate cannot be selected: {stable_id}"));
        }
        result = engine
            .next_candidate_page()
            .map_err(|error| format!("{error:?}"))?;
    }
}

fn collect_current_snapshot(
    lexicon_path: &Path,
    input: &str,
    page_size: usize,
) -> Result<Vec<FormalCandidate>, String> {
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .map_err(|error| error.to_string())?;
    engine.set_session_learning_allowed(false);
    let mut result = process_input(&mut engine, input);
    let mut candidates = Vec::new();
    loop {
        candidates.extend(result.candidates);
        if !result.has_next_page {
            break;
        }
        result = engine
            .next_candidate_page()
            .map_err(|error| format!("{error:?}"))?;
    }
    Ok(candidates)
}

fn current_first_page_case(
    lexicon_path: &Path,
    input: &str,
    page_size: usize,
) -> Result<Json, String> {
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .map_err(|error| error.to_string())?;
    engine.set_session_learning_allowed(false);
    let result = process_input(&mut engine, input);
    Ok(object([
        ("input", string(input)),
        ("result", composition_json(&result)),
    ]))
}

fn current_second_page_commit(
    lexicon_path: &Path,
    input: &str,
    page_size: usize,
) -> Result<Json, String> {
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .map_err(|error| error.to_string())?;
    engine.set_session_learning_allowed(false);
    let first = process_input(&mut engine, input);
    if !first.has_next_page {
        return Err("stage 3 h has no second page".to_owned());
    }
    let second = engine
        .next_candidate_page()
        .map_err(|error| format!("{error:?}"))?;
    let selected = second
        .candidates
        .first()
        .cloned()
        .ok_or_else(|| "stage 3 second page is empty".to_owned())?;
    let committed = engine
        .select_candidate(0)
        .map_err(|error| format!("{error:?}"))?;
    Ok(object([
        ("first_page_json_utf8_bytes", number(first.to_json().len())),
        ("selected_text", string(&selected.text)),
        ("commit_text", string(&committed.commit_text)),
        (
            "commit_matches_selected",
            bool_value(committed.commit_text == selected.text),
        ),
        (
            "composition_finished",
            bool_value(committed.composition_finished),
        ),
    ]))
}

fn current_partial_commit_case(lexicon_path: &Path) -> Result<Json, String> {
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "xiaohe".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 9,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .map_err(|error| error.to_string())?;
    engine.set_session_learning_allowed(false);
    let before = process_input(&mut engine, "uurufa");
    let selected_page_index = before
        .candidates
        .iter()
        .position(|candidate| candidate.text == "输入")
        .ok_or_else(|| "stage 3 partial candidate 输入 is missing".to_owned())?;
    let after = engine
        .select_candidate(selected_page_index)
        .map_err(|error| format!("{error:?}"))?;
    Ok(object([
        ("input", string("uurufa")),
        ("selected_page_index", number(selected_page_index)),
        ("selected_text", string("输入")),
        ("before", composition_json(&before)),
        ("after", composition_json(&after)),
    ]))
}

fn formal_to_ranking(candidate: &FormalCandidate) -> RankingCandidate {
    RankingCandidate::new(
        &candidate.id,
        &candidate.text,
        &candidate.reading,
        &candidate.source,
        0,
        CandidateMatchType::Prefix,
    )
}

fn timing_summary_json(phase: &'static str, samples: &[Duration]) -> Json {
    object([
        ("phase", string(phase)),
        ("unit", string("ns")),
        ("p50", Json::Number(percentile(samples, 50))),
        ("p95", Json::Number(percentile(samples, 95))),
        (
            "max",
            Json::Number(
                samples
                    .iter()
                    .max()
                    .expect("non-empty performance samples")
                    .as_nanos(),
            ),
        ),
    ])
}

const STAGE6_MISSING_IN_LEXICON: &str = "MISSING_IN_LEXICON";
const STAGE6_PRESENT_NOT_RECALLED: &str = "PRESENT_NOT_RECALLED";
const STAGE6_PRESENT_RANKED_TOO_LOW: &str = "PRESENT_RANKED_TOO_LOW";
const STAGE6_PRESENT_NOT_ACCESSIBLE: &str = "PRESENT_NOT_ACCESSIBLE";
const STAGE6_INVALID_ENCODING: &str = "INVALID_ENCODING";
const STAGE6_UNSUPPORTED_BY_CONTRACT: &str = "UNSUPPORTED_BY_CONTRACT";

#[derive(Clone, Debug)]
struct Stage6Case {
    case_id: String,
    scheme: String,
    category: String,
    input: String,
    expected: String,
    word: String,
    max_expected_rank: usize,
    supported: bool,
    notes: String,
}

#[derive(Clone, Debug)]
struct Stage6Observation {
    lexicon_present: bool,
    encoding_matches_lexicon: bool,
    recalled: bool,
    final_rank: Option<usize>,
    page_accessible: bool,
    parser_state: String,
    source: String,
    reason: Option<&'static str>,
}

#[derive(Default)]
struct Stage6CoverageCount {
    total: usize,
    lexicon_present: usize,
    recalled: usize,
    accessible: usize,
    accepted_rank: usize,
}

pub fn render_stage6_coverage_report(
    lexicon_path: &Path,
    bundle_path: &Path,
    cases_path: &Path,
) -> Result<String, String> {
    let cases = parse_stage6_cases(cases_path)?;
    let lexicon_bytes = fs::read(lexicon_path).map_err(|error| error.to_string())?;
    let lexicon = load_binary_lexicon(&lexicon_bytes).map_err(|error| error.to_string())?;
    let bundle = CodeTableBundle::load_frozen_production_file(bundle_path)
        .map_err(|error| error.to_string())?;
    bundle
        .validate_scheme_identity(PRODUCTION_SCHEME_ID)
        .map_err(|error| error.to_string())?;

    let mut shuangpin = stage6_engine("xiaohe", lexicon_path, None)?;
    let mut yinxing = stage6_engine(PRODUCTION_SCHEME_ID, lexicon_path, Some(bundle_path))?;
    let mut rows = Vec::with_capacity(cases.len());
    let mut reason_counts = BTreeMap::<String, usize>::new();
    let mut category_counts = BTreeMap::<(String, String), Stage6CoverageCount>::new();
    let mut code_counts = BTreeMap::<(String, String), Stage6CoverageCount>::new();

    for case in &cases {
        let (present, encoding_matches_lexicon, source) =
            stage6_lexicon_presence(case, &lexicon, &bundle);
        let encoding_valid = stage6_encoding_valid(case);
        let engine = match case.scheme.as_str() {
            "xiaohe" => &mut shuangpin,
            PRODUCTION_SCHEME_ID => &mut yinxing,
            _ => {
                return Err(format!(
                    "{}: unsupported scheme {}",
                    case.case_id, case.scheme
                ))
            }
        };
        let (rank, accessible, parser_state) = if case.supported && encoding_valid {
            stage6_query(engine, &case.input, &case.word)?
        } else {
            (None, false, "not_queried".to_owned())
        };
        let recalled = rank.is_some();
        let reason = if !case.supported {
            Some(STAGE6_UNSUPPORTED_BY_CONTRACT)
        } else if !encoding_valid {
            Some(STAGE6_INVALID_ENCODING)
        } else if !present {
            Some(STAGE6_MISSING_IN_LEXICON)
        } else if !encoding_matches_lexicon {
            Some(STAGE6_INVALID_ENCODING)
        } else if !recalled {
            Some(STAGE6_PRESENT_NOT_RECALLED)
        } else if !accessible {
            Some(STAGE6_PRESENT_NOT_ACCESSIBLE)
        } else if rank.is_some_and(|value| value > case.max_expected_rank) {
            Some(STAGE6_PRESENT_RANKED_TOO_LOW)
        } else {
            None
        };
        if let Some(value) = reason {
            *reason_counts.entry(value.to_owned()).or_default() += 1;
        }
        let observation = Stage6Observation {
            lexicon_present: present,
            encoding_matches_lexicon,
            recalled,
            final_rank: rank,
            page_accessible: accessible,
            parser_state,
            source,
            reason,
        };
        update_stage6_count(
            category_counts
                .entry((case.scheme.clone(), case.category.clone()))
                .or_default(),
            &observation,
            case.max_expected_rank,
        );
        update_stage6_count(
            code_counts
                .entry((case.scheme.clone(), stage6_code_bucket(case.input.len())))
                .or_default(),
            &observation,
            case.max_expected_rank,
        );
        rows.push(stage6_row_json(case, &observation));
    }

    for reason in [
        STAGE6_MISSING_IN_LEXICON,
        STAGE6_PRESENT_NOT_RECALLED,
        STAGE6_PRESENT_RANKED_TOO_LOW,
        STAGE6_PRESENT_NOT_ACCESSIBLE,
        STAGE6_INVALID_ENCODING,
        "DATA_CONFLICT",
        STAGE6_UNSUPPORTED_BY_CONTRACT,
    ] {
        reason_counts.entry(reason.to_owned()).or_default();
    }

    let report = object([
        (
            "schema_version",
            string("candidate-improvement/stage6-coverage-report/1"),
        ),
        (
            "contract",
            object([
                (
                    "page_size",
                    number(QueryConfig::default().default_page_size),
                ),
                (
                    "shuangpin_snapshot_limit",
                    number(QueryConfig::default().prefix_snapshot_limit),
                ),
                ("yinxing_snapshot_limit", number(YINXING_CANDIDATE_LIMIT)),
                (
                    "failure_taxonomy",
                    strings([
                        STAGE6_MISSING_IN_LEXICON,
                        STAGE6_PRESENT_NOT_RECALLED,
                        STAGE6_PRESENT_RANKED_TOO_LOW,
                        STAGE6_PRESENT_NOT_ACCESSIBLE,
                        STAGE6_INVALID_ENCODING,
                        "DATA_CONFLICT",
                        STAGE6_UNSUPPORTED_BY_CONTRACT,
                    ]),
                ),
            ]),
        ),
        ("case_count", number(cases.len())),
        ("cases", Json::Array(rows)),
        (
            "coverage_by_code_length",
            stage6_coverage_json(code_counts, "code_length"),
        ),
        (
            "coverage_by_category",
            stage6_coverage_json(category_counts, "category"),
        ),
        (
            "failure_counts",
            Json::Array(
                reason_counts
                    .into_iter()
                    .map(|(reason, count)| {
                        object([("reason", string(reason)), ("count", number(count))])
                    })
                    .collect(),
            ),
        ),
    ]);
    Ok(report.render())
}

fn parse_stage6_cases(path: &Path) -> Result<Vec<Stage6Case>, String> {
    let text = fs::read_to_string(path).map_err(|error| error.to_string())?;
    if text.starts_with('\u{feff}') {
        return Err(format!("{}: UTF-8 BOM is not allowed", path.display()));
    }
    let mut cases = Vec::new();
    let mut seen = BTreeSet::new();
    for (index, raw_line) in text.lines().enumerate() {
        let physical_line = index + 1;
        if physical_line == 1 {
            if raw_line
                != "case_id\tscheme\tcategory\tinput\texpected_encoding_or_pinyin\tword\tmax_expected_rank\tcontract\tnotes"
            {
                return Err(format!("{}:1: invalid stage 6 header", path.display()));
            }
            continue;
        }
        if raw_line.trim().is_empty() || raw_line.starts_with('#') {
            continue;
        }
        let fields = raw_line.split('\t').collect::<Vec<_>>();
        if fields.len() != 9 {
            return Err(format!(
                "{}:{physical_line}: expected 9 tab-separated fields, found {}",
                path.display(),
                fields.len()
            ));
        }
        if fields[..8].iter().any(|value| value.trim().is_empty()) {
            return Err(format!(
                "{}:{physical_line}: required field is empty",
                path.display()
            ));
        }
        if !seen.insert(fields[0].to_owned()) {
            return Err(format!(
                "{}:{physical_line}: duplicate case_id {}",
                path.display(),
                fields[0]
            ));
        }
        let max_expected_rank = fields[6].parse::<usize>().map_err(|_| {
            format!(
                "{}:{physical_line}: max_expected_rank is not a positive integer",
                path.display()
            )
        })?;
        if max_expected_rank == 0 {
            return Err(format!(
                "{}:{physical_line}: max_expected_rank must be positive",
                path.display()
            ));
        }
        let supported = match fields[7] {
            "SUPPORTED" => true,
            "UNSUPPORTED" => false,
            value => {
                return Err(format!(
                    "{}:{physical_line}: unknown contract value {value}",
                    path.display()
                ))
            }
        };
        cases.push(Stage6Case {
            case_id: fields[0].to_owned(),
            scheme: fields[1].to_owned(),
            category: fields[2].to_owned(),
            input: fields[3].to_owned(),
            expected: fields[4].to_owned(),
            word: fields[5].to_owned(),
            max_expected_rank,
            supported,
            notes: fields[8].to_owned(),
        });
    }
    if cases.is_empty() {
        return Err(format!("{}: no stage 6 cases", path.display()));
    }
    Ok(cases)
}

fn stage6_engine(
    scheme_id: &str,
    lexicon_path: &Path,
    bundle_path: Option<&Path>,
) -> Result<ImeEngine, String> {
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: scheme_id.to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        code_table_bundle_path: bundle_path.map(|path| path.to_string_lossy().into_owned()),
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: QueryConfig::default().default_page_size,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .map_err(|error| error.to_string())?;
    engine.set_session_learning_allowed(false);
    Ok(engine)
}

fn stage6_lexicon_presence(
    case: &Stage6Case,
    lexicon: &BinaryLexicon,
    bundle: &CodeTableBundle,
) -> (bool, bool, String) {
    if case.scheme == "xiaohe" {
        let matching_word = lexicon
            .entries
            .iter()
            .filter(|entry| entry.word == case.word)
            .collect::<Vec<_>>();
        let encoding_matches = matching_word
            .iter()
            .any(|entry| entry.pinyin_key == case.expected);
        let source = matching_word
            .iter()
            .flat_map(|entry| entry.sources.iter().map(String::as_str))
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>()
            .join(",");
        (!matching_word.is_empty(), encoding_matches, source)
    } else {
        let categories_with_word = bundle
            .categories
            .iter()
            .filter(|category| {
                category
                    .lexicon
                    .entries
                    .iter()
                    .any(|entry| entry.word == case.word)
            })
            .map(|category| category.id.as_str())
            .collect::<Vec<_>>();
        let encoding_matches = bundle.categories.iter().any(|category| {
            category.lexicon.entries.iter().any(|entry| {
                entry.word == case.word
                    && if case.expected.len() < 4 {
                        entry.pinyin_key.starts_with(&case.expected)
                    } else {
                        entry.pinyin_key == case.expected
                    }
            })
        });
        (
            !categories_with_word.is_empty(),
            encoding_matches,
            categories_with_word.join(","),
        )
    }
}

fn stage6_encoding_valid(case: &Stage6Case) -> bool {
    !case.input.is_empty()
        && case.input.bytes().all(|byte| byte.is_ascii_lowercase())
        && (case.scheme != PRODUCTION_SCHEME_ID || case.input.len() <= 4)
}

fn stage6_query(
    engine: &mut ImeEngine,
    input: &str,
    target: &str,
) -> Result<(Option<usize>, bool, String), String> {
    engine.reset();
    let mut result = engine.current_state();
    let mut committed = false;
    for key in input.chars() {
        result = engine.process_key(key);
        if result.commit_text == target {
            committed = true;
        }
        if !result.success {
            break;
        }
    }
    if committed {
        return Ok((Some(1), true, result.parser_state.as_str().to_owned()));
    }
    let parser_state = result.parser_state.as_str().to_owned();
    let mut rank = None;
    let mut offset = 0usize;
    for _ in 0..32 {
        if rank.is_none() {
            rank = result
                .candidates
                .iter()
                .position(|candidate| candidate.text == target)
                .map(|index| offset + index + 1);
        }
        offset += result.candidates.len();
        if !result.has_next_page {
            break;
        }
        result = engine
            .next_candidate_page()
            .map_err(|error| format!("{error:?}"))?;
    }
    Ok((rank, rank.is_some(), parser_state))
}

fn update_stage6_count(
    count: &mut Stage6CoverageCount,
    observation: &Stage6Observation,
    max_expected_rank: usize,
) {
    count.total += 1;
    count.lexicon_present += usize::from(observation.lexicon_present);
    count.recalled += usize::from(observation.recalled);
    count.accessible += usize::from(observation.page_accessible);
    count.accepted_rank += usize::from(
        observation
            .final_rank
            .is_some_and(|rank| rank <= max_expected_rank),
    );
}

fn stage6_code_bucket(length: usize) -> String {
    match length {
        0..=4 => length.to_string(),
        _ => "5+".to_owned(),
    }
}

fn stage6_percentage(numerator: usize, denominator: usize) -> String {
    if denominator == 0 {
        return "0.00%".to_owned();
    }
    format!(
        "{}.{:02}%",
        numerator * 100 / denominator,
        numerator * 10_000 / denominator % 100
    )
}

fn stage6_coverage_json(
    counts: BTreeMap<(String, String), Stage6CoverageCount>,
    dimension: &'static str,
) -> Json {
    Json::Array(
        counts
            .into_iter()
            .map(|((scheme, value), count)| {
                object([
                    ("scheme", string(scheme)),
                    (dimension, string(value)),
                    ("total", number(count.total)),
                    ("lexicon_present", number(count.lexicon_present)),
                    (
                        "lexicon_coverage",
                        string(stage6_percentage(count.lexicon_present, count.total)),
                    ),
                    ("recalled", number(count.recalled)),
                    (
                        "recall_coverage",
                        string(stage6_percentage(count.recalled, count.total)),
                    ),
                    ("page_accessible", number(count.accessible)),
                    (
                        "page_access_coverage",
                        string(stage6_percentage(count.accessible, count.total)),
                    ),
                    ("within_expected_rank", number(count.accepted_rank)),
                ])
            })
            .collect(),
    )
}

fn stage6_row_json(case: &Stage6Case, observation: &Stage6Observation) -> Json {
    object([
        ("case_id", string(&case.case_id)),
        ("scheme", string(&case.scheme)),
        ("category", string(&case.category)),
        ("test_entry", string(&case.word)),
        ("input", string(&case.input)),
        ("expected_encoding_or_pinyin", string(&case.expected)),
        ("lexicon_present", bool_value(observation.lexicon_present)),
        (
            "encoding_matches_lexicon",
            bool_value(observation.encoding_matches_lexicon),
        ),
        ("recalled", bool_value(observation.recalled)),
        ("final_rank", optional_number(observation.final_rank)),
        ("page_accessible", bool_value(observation.page_accessible)),
        ("max_expected_rank", number(case.max_expected_rank)),
        (
            "missing_reason",
            observation.reason.map(string).unwrap_or(Json::Null),
        ),
        ("lexicon_source", string(&observation.source)),
        ("parser_state", string(&observation.parser_state)),
        ("contract_supported", bool_value(case.supported)),
        ("notes", string(&case.notes)),
    ])
}

pub fn render_performance(
    lexicon_path: &Path,
    bundle_path: &Path,
    warmups: usize,
    samples: usize,
) -> Result<String, String> {
    render_performance_for_page_size(
        lexicon_path,
        bundle_path,
        EFFECTIVE_PAGE_SIZE,
        warmups,
        samples,
    )
}

pub fn render_performance_for_page_size(
    lexicon_path: &Path,
    bundle_path: &Path,
    requested_page_size: usize,
    warmups: usize,
    samples: usize,
) -> Result<String, String> {
    if samples == 0 {
        return Err("samples must be positive".to_owned());
    }
    let query_config = QueryConfig::default();
    let effective_page_size = query_config
        .normalize_page_size(requested_page_size)
        .map_err(|error| error.to_string())?;
    let process_start = memory_snapshot();
    let lexicon_bytes = fs::read(lexicon_path).map_err(|error| error.to_string())?;
    let lexicon = load_binary_lexicon(&lexicon_bytes).map_err(|error| error.to_string())?;
    let bundle = Arc::new(
        CodeTableBundle::load_frozen_production_file(bundle_path)
            .map_err(|error| error.to_string())?,
    );
    let after_load = memory_snapshot();
    let rules = Arc::new(
        bundle
            .user_rules
            .clone()
            .ok_or_else(|| "production bundle has no embedded user rules".to_owned())?,
    );

    for _ in 0..warmups {
        let mut query_engine = CandidateQueryEngine::new(lexicon.clone(), query_config.clone());
        let _ = query_engine
            .query(QueryRequest::new(
                "xiaohe",
                "h",
                QueryMode::Prefix,
                requested_page_size,
            ))
            .map_err(|error| error.to_string())?;
        let mut shape = CodeTableStateMachine::new_with_query_strategy(
            Arc::clone(&bundle),
            effective_page_size,
            YINXING_CANDIDATE_LIMIT,
            Arc::clone(&rules),
            CodeTableQueryStrategy::ProgressiveXiaoheYinxing,
        )
        .map_err(|error| error.to_string())?;
        shape.process_key('h').map_err(|error| error.to_string())?;
    }

    let mut cold_double = Vec::with_capacity(samples);
    let mut hot_double = Vec::with_capacity(samples);
    let mut cold_shape = Vec::with_capacity(samples);
    let mut hot_shape = Vec::with_capacity(samples);
    let mut double_count = 0;
    let mut shape_count = 0;
    for _ in 0..samples {
        let mut query_engine = CandidateQueryEngine::new(lexicon.clone(), query_config.clone());
        let started = Instant::now();
        let cold = query_engine
            .query(QueryRequest::new(
                "xiaohe",
                "h",
                QueryMode::Prefix,
                requested_page_size,
            ))
            .map_err(|error| error.to_string())?;
        cold_double.push(started.elapsed());
        double_count = cold.candidates.len();
        let started = Instant::now();
        let hot = query_engine
            .query(QueryRequest::new(
                "xiaohe",
                "h",
                QueryMode::Prefix,
                requested_page_size,
            ))
            .map_err(|error| error.to_string())?;
        hot_double.push(started.elapsed());
        if !hot.cache_hit || hot.candidates != cold.candidates {
            return Err("hot double-pinyin result differs from cold result".to_owned());
        }

        let started = Instant::now();
        let mut shape = CodeTableStateMachine::new_with_query_strategy(
            Arc::clone(&bundle),
            effective_page_size,
            YINXING_CANDIDATE_LIMIT,
            Arc::clone(&rules),
            CodeTableQueryStrategy::ProgressiveXiaoheYinxing,
        )
        .map_err(|error| error.to_string())?;
        shape.process_key('h').map_err(|error| error.to_string())?;
        cold_shape.push(started.elapsed());
        shape_count = shape.all_candidates().len();
        shape.reset();
        let started = Instant::now();
        shape.process_key('h').map_err(|error| error.to_string())?;
        hot_shape.push(started.elapsed());
    }
    let after_snapshots = memory_snapshot();

    let mut double_engine = new_production_engine_with_page_size(
        lexicon_path,
        bundle_path,
        "xiaohe",
        requested_page_size,
    )?;
    let double_result = process_input(&mut double_engine, "h");
    let mut shape_engine = new_production_engine_with_page_size(
        lexicon_path,
        bundle_path,
        PRODUCTION_SCHEME_ID,
        requested_page_size,
    )?;
    let shape_result = process_input(&mut shape_engine, "h");

    let json = object([
        (
            "schema_version",
            string("candidate-baseline/performance-host-release/1"),
        ),
        ("profile", string("release")),
        ("requested_page_size", number(requested_page_size)),
        ("effective_page_size", number(effective_page_size)),
        ("warmup_count", number(warmups)),
        ("sample_count", number(samples)),
        (
            "filesystem_cache",
            string("not controlled; explicit warmup performed"),
        ),
        (
            "metrics",
            Json::Array(vec![
                timing_metric("double_pinyin_h_cold_query", &cold_double),
                timing_metric("double_pinyin_h_hot_query", &hot_double),
                timing_metric("flypy_shape_h_cold_state_query", &cold_shape),
                timing_metric("flypy_shape_h_hot_state_query", &hot_shape),
            ]),
        ),
        (
            "candidate_counts",
            object([
                ("double_pinyin_h", number(double_count)),
                ("flypy_shape_h", number(shape_count)),
            ]),
        ),
        (
            "cross_language_current_page_json_bytes",
            object([
                ("double_pinyin_h", number(double_result.to_json().len())),
                ("flypy_shape_h", number(shape_result.to_json().len())),
            ]),
        ),
        (
            "memory",
            object([
                (
                    "process_start_working_set_bytes",
                    Json::Number(process_start.working as u128),
                ),
                (
                    "after_resource_load_working_set_bytes",
                    Json::Number(after_load.working as u128),
                ),
                (
                    "after_candidate_snapshots_working_set_bytes",
                    Json::Number(after_snapshots.working as u128),
                ),
                (
                    "candidate_snapshot_working_set_delta_bytes",
                    Json::Number(after_snapshots.working.saturating_sub(after_load.working) as u128),
                ),
                (
                    "peak_working_set_bytes",
                    Json::Number(after_snapshots.peak.max(after_load.peak) as u128),
                ),
            ]),
        ),
        (
            "not_run",
            Json::Array(vec![
                object([
                    ("metric", string("Phone UI-visible latency and memory")),
                    ("status", string("NOT_RUN")),
                    ("reason", string("requires Phone simulator or device")),
                ]),
                object([
                    ("metric", string("Pad UI-visible latency and memory")),
                    ("status", string("NOT_RUN")),
                    ("reason", string("requires Pad simulator or device")),
                ]),
                object([
                    ("metric", string("ARM64 physical-device performance")),
                    ("status", string("NOT_RUN")),
                    ("reason", string("requires an attached ARM64 device")),
                ]),
            ]),
        ),
    ]);
    Ok(json.render())
}

fn timing_metric(id: &'static str, samples: &[Duration]) -> Json {
    object([
        ("id", string(id)),
        ("unit", string("ns")),
        ("p50", Json::Number(percentile(samples, 50))),
        ("p95", Json::Number(percentile(samples, 95))),
        (
            "max",
            Json::Number(
                samples
                    .iter()
                    .max()
                    .expect("non-empty performance samples")
                    .as_nanos(),
            ),
        ),
    ])
}

fn percentile(samples: &[Duration], percentile: usize) -> u128 {
    let mut sorted = samples.to_vec();
    sorted.sort_unstable();
    sorted[((sorted.len() - 1) * percentile) / 100].as_nanos()
}

#[derive(Clone, Copy)]
struct MemorySnapshot {
    working: u64,
    peak: u64,
}

#[cfg(windows)]
fn memory_snapshot() -> MemorySnapshot {
    #[repr(C)]
    struct ProcessMemoryCounters {
        cb: u32,
        page_fault_count: u32,
        peak_working_set_size: usize,
        working_set_size: usize,
        quota_peak_paged_pool_usage: usize,
        quota_paged_pool_usage: usize,
        quota_peak_non_paged_pool_usage: usize,
        quota_non_paged_pool_usage: usize,
        pagefile_usage: usize,
        peak_pagefile_usage: usize,
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentProcess() -> *mut core::ffi::c_void;
    }
    #[link(name = "psapi")]
    unsafe extern "system" {
        fn GetProcessMemoryInfo(
            process: *mut core::ffi::c_void,
            counters: *mut ProcessMemoryCounters,
            size: u32,
        ) -> i32;
    }
    let mut counters = ProcessMemoryCounters {
        cb: size_of::<ProcessMemoryCounters>() as u32,
        page_fault_count: 0,
        peak_working_set_size: 0,
        working_set_size: 0,
        quota_peak_paged_pool_usage: 0,
        quota_paged_pool_usage: 0,
        quota_peak_non_paged_pool_usage: 0,
        quota_non_paged_pool_usage: 0,
        pagefile_usage: 0,
        peak_pagefile_usage: 0,
    };
    // SAFETY: both APIs are read-only for the current process and receive a
    // correctly sized writable PROCESS_MEMORY_COUNTERS buffer.
    let succeeded = unsafe {
        GetProcessMemoryInfo(
            GetCurrentProcess(),
            &mut counters,
            size_of::<ProcessMemoryCounters>() as u32,
        )
    };
    if succeeded == 0 {
        MemorySnapshot {
            working: 0,
            peak: 0,
        }
    } else {
        MemorySnapshot {
            working: counters.working_set_size as u64,
            peak: counters.peak_working_set_size as u64,
        }
    }
}

#[cfg(not(windows))]
fn memory_snapshot() -> MemorySnapshot {
    let status = fs::read_to_string("/proc/self/status").unwrap_or_default();
    let value = |field: &str| {
        status
            .lines()
            .find_map(|line| {
                line.strip_prefix(field)
                    .and_then(|value| value.split_whitespace().next())
                    .and_then(|value| value.parse::<u64>().ok())
                    .map(|kilobytes| kilobytes * 1024)
            })
            .unwrap_or(0)
    };
    MemorySnapshot {
        working: value("VmRSS:"),
        peak: value("VmHWM:"),
    }
}

pub fn default_repo_paths() -> (PathBuf, PathBuf) {
    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    (
        repo_root.join("entry/src/main/resources/rawfile/production.lex"),
        repo_root.join(
            "dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
        ),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_renderer_is_byte_deterministic() {
        let value = object([
            ("schema_version", string("candidate-baseline/test/1")),
            ("count", number(2)),
            ("values", strings(["和", "好"])),
        ]);
        assert_eq!(value.render(), value.render());
        assert!(value.render().ends_with('\n'));
    }

    #[test]
    fn stage_zero_limits_remain_explicit_and_frozen() {
        let config = stage_zero_query_config();
        assert_eq!(config.default_page_size, 5);
        assert_eq!(config.max_page_size, 9);
        assert_eq!(config.max_candidates, 64);
        assert_eq!(PAGE_SIZE_REQUESTED_BY_ARKTS, 50);
        assert_eq!(EFFECTIVE_PAGE_SIZE, 9);
        assert_eq!(YINXING_CANDIDATE_LIMIT, 512);
    }

    #[test]
    fn stage6_fixture_is_stable_and_covers_required_schemes_and_categories() {
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
        let cases = parse_stage6_cases(
            &repo_root.join("engine-rust/tests/fixtures/candidate_stage6_coverage.tsv"),
        )
        .expect("stage 6 fixture");
        assert_eq!(cases.len(), 112);
        assert!(cases.iter().any(|case| case.scheme == "xiaohe"));
        assert!(cases.iter().any(|case| case.scheme == PRODUCTION_SCHEME_ID));
        for category in [
            "common_single",
            "common_double",
            "common_multi",
            "idiom",
            "colloquial",
            "internet",
            "place",
            "name",
            "professional",
            "polyphonic",
            "rare_extended",
        ] {
            assert!(
                cases.iter().any(|case| case.category == category),
                "{category}"
            );
        }
        for length in 1..=4 {
            assert!(cases
                .iter()
                .any(|case| case.scheme == "xiaohe" && case.input.len() == length));
            assert!(cases
                .iter()
                .any(|case| case.scheme == PRODUCTION_SCHEME_ID && case.input.len() == length));
        }
    }

    #[test]
    fn committed_candidate_snapshots_match_current_production_behavior() {
        let (_, bundle) = default_repo_paths();
        // These immutable snapshots belong to the pre-V2 lexicon identity.
        // Keep exercising that archived binary instead of silently rewriting
        // historical expectations when the HAP production resource advances.
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
        let lexicon = repo_root.join("dictionaries/generated/production.lex");
        let actual = render_stable_files(&lexicon, &bundle).expect("render current behavior");
        let snapshot_dir = repo_root.join("artifacts/candidate-baseline");
        for (name, contents) in actual {
            let expected =
                fs::read_to_string(snapshot_dir.join(name)).expect("committed baseline snapshot");
            assert_eq!(contents, expected, "{name}");
        }
    }
}
