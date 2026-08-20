use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::Instant;

use context_reranker::RerankStats;
use engine_protocol::ProtocolParserState;
use ime_engine::{
    EngineConfig, FuzzyOption, ImeEngine, QuanpinContextRerankingConfig,
    QuanpinContextRerankingStatus, QuanpinExpansionStats, QuanpinFeatureConfig,
};

use crate::anonymous_distribution::{self, AnonymousInputDistribution, RAW_INPUT_LENGTH_BANDS};
use crate::eval_json::{parse, serialize, serialize_line, JsonValue};
use crate::eval_sha256;

const MIN_COUNTS: [(&str, usize); 9] = [
    ("common_character_word", 150),
    ("common_phrase_2_4", 200),
    ("modern_chat", 200),
    ("long_ambiguous", 100),
    ("proper_name_domain", 100),
    ("polyphone_homophone", 80),
    ("abbrev_mixed_incomplete", 70),
    ("typo", 60),
    ("fuzzy", 40),
];

const V2_MIN_COUNTS: [(&str, usize); 12] = [
    ("clean", 8),
    ("modern_colloquial", 8),
    ("proper_person", 8),
    ("proper_place", 8),
    ("proper_org_brand", 8),
    ("domain_technology", 8),
    ("domain_software", 8),
    ("domain_education", 8),
    ("domain_medical", 8),
    ("domain_finance", 8),
    ("domain_legal", 8),
    ("hotword", 8),
];

#[derive(Clone, Debug)]
struct DatasetCase {
    id: String,
    raw_input: String,
    expected_texts: Vec<String>,
    category: String,
    tags: Vec<String>,
    source: String,
    split: String,
    fuzzy: Vec<String>,
    notes: Option<String>,
}

#[derive(Clone, Debug, Default)]
struct Counters {
    count: usize,
    top1: usize,
    top3: usize,
    top5: usize,
    reciprocal_rank: f64,
    no_candidates: usize,
    unrecalled: usize,
    recalled_outside_top5: usize,
    ranking_errors: usize,
    recalled_rank_sum: usize,
    recalled_count: usize,
}

#[derive(Clone, Debug)]
struct CaseOutcome {
    case: DatasetCase,
    rank: Option<usize>,
    candidates: Vec<String>,
    no_candidates: bool,
    automatic_commit: bool,
    ascii_leak: bool,
    state_loss: bool,
    engine_error: bool,
    fingerprint: String,
    expansion: QuanpinExpansionStats,
    rerank: RerankStats,
}

#[derive(Default)]
struct Safety {
    automatic_commits: usize,
    ascii_leaks: usize,
    state_losses: usize,
    engine_errors: usize,
}

pub fn validate_quanpin_dataset(dataset_dir: &Path) -> Result<String, String> {
    let cases = load_cases(dataset_dir)?;
    let summary = validate_cases(&cases)?;
    Ok(
        String::from_utf8(serialize(&validation_json(&cases, &summary)))
            .expect("JSON serializer emits UTF-8"),
    )
}

pub fn freeze_quanpin_dataset(
    dataset_dir: &Path,
    manifest_path: &Path,
    baseline_id: &str,
    frozen_at: &str,
) -> Result<String, String> {
    if baseline_id.trim().is_empty() || frozen_at.trim().is_empty() {
        return Err("baseline id and frozen time must be explicit".to_owned());
    }
    if manifest_path.exists() {
        return Err(format!(
            "freeze manifest already exists: {}; creating a new baseline requires a new manifest path and baseline id",
            manifest_path.display()
        ));
    }
    let cases = load_cases(dataset_dir)?;
    let counts = validate_cases(&cases)?;
    let files = dataset_files(dataset_dir)?;
    let identity_material = files
        .iter()
        .map(|file| format!("{}\0{}\0{}\n", file.path, file.bytes, file.sha256))
        .collect::<String>();
    let identity = eval_sha256::hex(identity_material.as_bytes());
    let manifest = JsonValue::object([
        ("schemaVersion", JsonValue::string("quanpin-evaluation-freeze/1")),
        ("baselineId", JsonValue::string(baseline_id)),
        ("baselineIdentitySha256", JsonValue::string(&identity)),
        ("frozenAt", JsonValue::string(frozen_at)),
        ("gitIdentityUsed", JsonValue::Bool(false)),
        ("sampleCount", JsonValue::number(cases.len() as f64)),
        ("splitDistribution", count_map_json(split_counts(&cases))),
        ("categoryDistribution", count_map_json(counts)),
        (
            "files",
            JsonValue::array(files.iter().map(|file| {
                JsonValue::object([
                    ("path", JsonValue::string(&file.path)),
                    ("bytes", JsonValue::number(file.bytes as f64)),
                    ("sha256", JsonValue::string(&file.sha256)),
                    ("sampleCount", JsonValue::number(file.sample_count as f64)),
                    ("categoryDistribution", count_map_json(file.category_counts.clone())),
                ])
            })),
        ),
        (
            "mutationPolicy",
            JsonValue::string("Any byte change is a hard error. A new baseline requires an explicit freeze command with a new baseline id and manifest path."),
        ),
    ]);
    if let Some(parent) = manifest_path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(manifest_path, serialize(&manifest)).map_err(|error| error.to_string())?;
    Ok(format!(
        "frozen baseline {baseline_id}: {} samples, identity {identity}",
        cases.len()
    ))
}

pub struct QuanpinEvaluationRequest<'a> {
    pub dataset_dir: &'a Path,
    pub manifest_path: &'a Path,
    pub lexicon_path: &'a Path,
    pub results_path: &'a Path,
    pub failures_path: &'a Path,
    pub runs: usize,
    pub split: &'a str,
    pub spelling_correction_enabled: bool,
    pub fuzzy_options_enabled: bool,
    pub context_model_path: Option<&'a Path>,
    pub context_model_sha256: Option<&'a str>,
    pub anonymous_distribution_path: Option<&'a Path>,
    pub learning_probe_repetitions: usize,
}

pub fn evaluate_quanpin_dataset(request: &QuanpinEvaluationRequest<'_>) -> Result<String, String> {
    let dataset_dir = request.dataset_dir;
    let manifest_path = request.manifest_path;
    let lexicon_path = request.lexicon_path;
    let results_path = request.results_path;
    let failures_path = request.failures_path;
    let runs = request.runs;
    let split = request.split;
    let spelling_correction_enabled = request.spelling_correction_enabled;
    let fuzzy_options_enabled = request.fuzzy_options_enabled;
    if request.context_model_path.is_some() != request.context_model_sha256.is_some() {
        return Err("context model path and SHA-256 must be supplied together".to_owned());
    }
    if cfg!(debug_assertions) {
        return Err("quanpin evaluation must be compiled and run in Cargo release mode".to_owned());
    }
    if runs < 3 {
        return Err("at least three runs are required".to_owned());
    }
    if request.learning_probe_repetitions > 5 {
        return Err("learning probe repetitions must be between 0 and 5".to_owned());
    }
    if !matches!(split, "dev" | "blind" | "all") {
        return Err(format!(
            "invalid split {split:?}; expected dev, blind, or all"
        ));
    }
    reject_protected_output(results_path)?;
    reject_protected_output(failures_path)?;
    verify_manifest(dataset_dir, manifest_path)?;
    let all_cases = load_cases(dataset_dir)?;
    validate_cases(&all_cases)?;
    let cases = all_cases
        .into_iter()
        .filter(|case| split == "all" || case.split == split)
        .collect::<Vec<_>>();
    if cases.is_empty() {
        return Err(format!("split {split:?} selected no cases"));
    }
    let lexicon_bytes = fs::read(lexicon_path).map_err(|error| {
        format!(
            "cannot read production lexicon {}: {error}",
            lexicon_path.display()
        )
    })?;
    let lexicon_hash = eval_sha256::hex(&lexicon_bytes);
    let manifest_bytes = fs::read(manifest_path).map_err(|error| error.to_string())?;
    let manifest_hash = eval_sha256::hex(&manifest_bytes);
    let anonymous_distribution = request
        .anonymous_distribution_path
        .map(anonymous_distribution::load)
        .transpose()?;

    let mut all_runs = Vec::new();
    let mut all_latencies = Vec::new();
    let mut engine_load_latencies = Vec::new();
    let mut reference_fingerprints: Option<Vec<String>> = None;
    let mut deterministic = true;
    let mut safety = Safety::default();
    let mut first_outcomes = Vec::new();
    let mut engine_version = String::new();
    let mut context_status: Option<QuanpinContextRerankingStatus> = None;

    for run_index in 0..runs {
        let engine_load_started = Instant::now();
        let mut engine = ImeEngine::new(EngineConfig {
            scheme_id: "quanpin".to_owned(),
            lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
            candidate_page_size: 50,
            quanpin_features: QuanpinFeatureConfig::new(spelling_correction_enabled, []),
            quanpin_context_reranking: QuanpinContextRerankingConfig::new(
                request.context_model_path.is_some(),
                request
                    .context_model_path
                    .map(|path| path.to_string_lossy().into_owned()),
                request.context_model_sha256.map(str::to_owned),
            ),
            ..EngineConfig::default()
        })
        .map_err(|error| format!("engine creation failed: {error}"))?;
        engine_load_latencies.push(engine_load_started.elapsed().as_micros() as u64);
        engine.set_user_learning_enabled(false);
        engine.set_session_learning_allowed(false);
        let status = engine.quanpin_context_reranking_status();
        if request.context_model_path.is_some() && !status.enabled {
            return Err(format!(
                "context model failed to load: {}",
                status.last_error_code
            ));
        }
        context_status = Some(status);
        engine_version = engine.version().to_owned();
        let mut run_latencies = Vec::new();
        let mut outcomes = Vec::new();
        for case in &cases {
            outcomes.push(run_case(
                &mut engine,
                case,
                spelling_correction_enabled,
                fuzzy_options_enabled,
                &mut run_latencies,
            )?);
        }
        let fingerprints = outcomes
            .iter()
            .map(|outcome| outcome.fingerprint.clone())
            .collect::<Vec<_>>();
        if let Some(reference) = &reference_fingerprints {
            deterministic &= *reference == fingerprints;
        } else {
            reference_fingerprints = Some(fingerprints);
        }
        let run_safety = safety_from_outcomes(&outcomes);
        safety.automatic_commits += run_safety.automatic_commits;
        safety.ascii_leaks += run_safety.ascii_leaks;
        safety.state_losses += run_safety.state_losses;
        safety.engine_errors += run_safety.engine_errors;
        all_runs.push(run_json(run_index + 1, &outcomes, &run_latencies));
        all_latencies.extend(run_latencies);
        if run_index == 0 {
            first_outcomes = outcomes;
        }
    }

    let first_metrics = counters(&first_outcomes);
    let grouped = grouped_metrics(&first_outcomes);
    let learning_probe = evaluate_user_learning_probe(request, &cases)?;
    let report = JsonValue::object([
        (
            "schemaVersion",
            JsonValue::string("quanpin-quality-baseline-results/1"),
        ),
        (
            "measurementKind",
            JsonValue::string("host-release-ImeEngine-per-key"),
        ),
        ("datasetManifestSha256", JsonValue::string(manifest_hash)),
        ("productionLexiconSha256", JsonValue::string(lexicon_hash)),
        (
            "productionLexiconBytes",
            JsonValue::number(lexicon_bytes.len() as f64),
        ),
        ("engineVersion", JsonValue::string(engine_version)),
        ("schemeId", JsonValue::string("quanpin")),
        ("split", JsonValue::string(split)),
        (
            "spellingCorrectionEnabled",
            JsonValue::Bool(spelling_correction_enabled),
        ),
        (
            "fuzzyOptionsEnabled",
            JsonValue::Bool(fuzzy_options_enabled),
        ),
        ("releaseModeRequired", JsonValue::Bool(true)),
        ("runCount", JsonValue::number(runs as f64)),
        (
            "deterministicCandidateOutputs",
            JsonValue::Bool(deterministic),
        ),
        (
            "sampleCount",
            JsonValue::number(first_outcomes.len() as f64),
        ),
        ("metrics", metrics_json(&first_metrics)),
        ("groups", grouped),
        (
            "anonymousDistribution",
            anonymous_distribution_json(anonymous_distribution.as_ref(), &first_outcomes),
        ),
        ("userLearningProbe", learning_probe),
        ("aggregateKeyLatencyMicros", latency_json(&all_latencies)),
        (
            "engineLoadLatencyMicros",
            latency_json(&engine_load_latencies),
        ),
        (
            "processPeakWorkingSetBytes",
            process_peak_working_set_bytes()
                .map(|value| JsonValue::number(value as f64))
                .unwrap_or(JsonValue::Null),
        ),
        ("featureExpansion", expansion_json(&first_outcomes)),
        (
            "contextReranking",
            context_reranking_json(
                &first_outcomes,
                context_status.as_ref().expect("evaluation run"),
            ),
        ),
        ("runs", JsonValue::array(all_runs)),
        (
            "safetyContract",
            JsonValue::object([
                (
                    "nonExplicitAutomaticCommitCount",
                    JsonValue::number(safety.automatic_commits as f64),
                ),
                (
                    "asciiLeakCount",
                    JsonValue::number(safety.ascii_leaks as f64),
                ),
                (
                    "stateLossCount",
                    JsonValue::number(safety.state_losses as f64),
                ),
                (
                    "engineErrorCount",
                    JsonValue::number(safety.engine_errors as f64),
                ),
            ]),
        ),
        (
            "fuzzyOptionExecution",
            JsonValue::string(if fuzzy_options_enabled {
                "FORMAL_IME_ENGINE_PER_CASE: only enabledFuzzyOptions declared by each frozen fuzzy sample are enabled; all other options remain disabled."
            } else {
                "DISABLED_FOR_PERFORMANCE_COMPARISON: no fuzzy option is enabled."
            }),
        ),
        ("environment", environment_json()),
        (
            "interpretation",
            JsonValue::object([
                ("lowScoresCauseProcessFailure", JsonValue::Bool(false)),
                ("hostDataOnly", JsonValue::Bool(true)),
                ("deviceDataIncluded", JsonValue::Bool(false)),
            ]),
        ),
    ]);
    write_json(results_path, &serialize(&report))?;
    write_failures(failures_path, &first_outcomes)?;

    if !deterministic
        || safety.automatic_commits > 0
        || safety.ascii_leaks > 0
        || safety.state_losses > 0
        || safety.engine_errors > 0
    {
        return Err(format!(
            "safety/determinism gate failed after artifacts were written: deterministic={deterministic}, auto_commit={}, ascii_leak={}, state_loss={}, engine_error={}",
            safety.automatic_commits, safety.ascii_leaks, safety.state_losses, safety.engine_errors
        ));
    }
    Ok(format!(
        "evaluated {} samples x {runs} runs; Top1 {:.3}%, Top3 {:.3}%, Top5 {:.3}%",
        first_metrics.count,
        rate(first_metrics.top1, first_metrics.count) * 100.0,
        rate(first_metrics.top3, first_metrics.count) * 100.0,
        rate(first_metrics.top5, first_metrics.count) * 100.0
    ))
}

fn evaluate_user_learning_probe(
    request: &QuanpinEvaluationRequest<'_>,
    cases: &[DatasetCase],
) -> Result<JsonValue, String> {
    if request.learning_probe_repetitions == 0 {
        return Ok(JsonValue::object([
            ("enabled", JsonValue::Bool(false)),
            (
                "reason",
                JsonValue::string("set --learning-repetitions 1..5 to run the isolated probe"),
            ),
        ]));
    }

    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        lexicon_path: Some(request.lexicon_path.to_string_lossy().into_owned()),
        candidate_page_size: 50,
        quanpin_features: QuanpinFeatureConfig::new(request.spelling_correction_enabled, []),
        quanpin_context_reranking: QuanpinContextRerankingConfig::new(
            request.context_model_path.is_some(),
            request
                .context_model_path
                .map(|path| path.to_string_lossy().into_owned()),
            request.context_model_sha256.map(str::to_owned),
        ),
        ..EngineConfig::default()
    })
    .map_err(|error| format!("learning probe engine creation failed: {error}"))?;
    engine.set_user_learning_enabled(true);
    engine.set_session_learning_allowed(true);

    let mut eligible = 0_usize;
    let mut improved = 0_usize;
    let mut unchanged = 0_usize;
    let mut worsened = 0_usize;
    let mut became_top1 = 0_usize;
    let mut before_rank_sum = 0_usize;
    let mut after_rank_sum = 0_usize;
    let mut selection_failures = 0_usize;
    for case in cases {
        engine
            .clear_user_model()
            .map_err(|error| format!("learning probe reset failed for {}: {error:?}", case.id))?;
        let before = run_case(
            &mut engine,
            case,
            request.spelling_correction_enabled,
            request.fuzzy_options_enabled,
            &mut Vec::new(),
        )?;
        let Some(before_rank) = before.rank.filter(|rank| *rank > 1) else {
            continue;
        };
        eligible += 1;
        before_rank_sum = before_rank_sum.saturating_add(before_rank);
        let mut all_selected = true;
        for _ in 0..request.learning_probe_repetitions {
            if !select_expected_candidate(
                &mut engine,
                case,
                request.spelling_correction_enabled,
                request.fuzzy_options_enabled,
            )? {
                all_selected = false;
                selection_failures += 1;
                break;
            }
        }
        if !all_selected {
            after_rank_sum = after_rank_sum.saturating_add(before_rank);
            unchanged += 1;
            continue;
        }
        let after = run_case(
            &mut engine,
            case,
            request.spelling_correction_enabled,
            request.fuzzy_options_enabled,
            &mut Vec::new(),
        )?;
        let after_rank = after.rank.unwrap_or(before_rank);
        after_rank_sum = after_rank_sum.saturating_add(after_rank);
        match after_rank.cmp(&before_rank) {
            std::cmp::Ordering::Less => improved += 1,
            std::cmp::Ordering::Equal => unchanged += 1,
            std::cmp::Ordering::Greater => worsened += 1,
        }
        became_top1 += usize::from(after_rank == 1);
    }

    Ok(JsonValue::object([
        ("enabled", JsonValue::Bool(true)),
        (
            "scope",
            JsonValue::string(
                "isolated in-memory probe over recalled non-Top1 targets; no user model file is written",
            ),
        ),
        (
            "repetitionsPerTarget",
            JsonValue::number(request.learning_probe_repetitions as f64),
        ),
        ("eligibleTargetCount", JsonValue::number(eligible as f64)),
        ("improvedRankCount", JsonValue::number(improved as f64)),
        ("becameTop1Count", JsonValue::number(became_top1 as f64)),
        ("unchangedRankCount", JsonValue::number(unchanged as f64)),
        ("worsenedRankCount", JsonValue::number(worsened as f64)),
        (
            "selectionFailureCount",
            JsonValue::number(selection_failures as f64),
        ),
        (
            "averageRankBefore",
            if eligible == 0 {
                JsonValue::Null
            } else {
                JsonValue::number(before_rank_sum as f64 / eligible as f64)
            },
        ),
        (
            "averageRankAfter",
            if eligible == 0 {
                JsonValue::Null
            } else {
                JsonValue::number(after_rank_sum as f64 / eligible as f64)
            },
        ),
    ]))
}

fn select_expected_candidate(
    engine: &mut ImeEngine,
    case: &DatasetCase,
    spelling_correction_enabled: bool,
    fuzzy_options_enabled: bool,
) -> Result<bool, String> {
    let fuzzy_options = if fuzzy_options_enabled {
        case.fuzzy
            .iter()
            .map(|value| {
                FuzzyOption::parse(value)
                    .ok_or_else(|| format!("unsupported fuzzy option {value:?} in {}", case.id))
            })
            .collect::<Result<Vec<_>, _>>()?
    } else {
        Vec::new()
    };
    engine
        .set_quanpin_feature_config(QuanpinFeatureConfig::new(
            spelling_correction_enabled,
            fuzzy_options,
        ))
        .map_err(|error| format!("learning probe config failed for {}: {error:?}", case.id))?;
    engine.reset();
    let mut state = engine.current_state();
    for key in case.raw_input.chars() {
        state = engine.process_key(key);
    }
    loop {
        if let Some(index) = state
            .candidates
            .iter()
            .position(|candidate| case.expected_texts.contains(&candidate.text))
        {
            engine.select_candidate(index).map_err(|error| {
                format!("learning probe selection failed for {}: {error:?}", case.id)
            })?;
            return Ok(true);
        }
        if !state.has_next_page {
            return Ok(false);
        }
        state = engine
            .next_candidate_page()
            .map_err(|error| format!("learning probe paging failed for {}: {error:?}", case.id))?;
    }
}

fn reject_protected_output(path: &Path) -> Result<(), String> {
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("");
    if matches!(name, "baseline-results.json" | "failure-cases.jsonl") {
        return Err(format!(
            "refusing to overwrite protected pre-improvement artifact {}",
            path.display()
        ));
    }
    Ok(())
}

fn run_case(
    engine: &mut ImeEngine,
    case: &DatasetCase,
    spelling_correction_enabled: bool,
    fuzzy_options_enabled: bool,
    latencies: &mut Vec<u64>,
) -> Result<CaseOutcome, String> {
    let fuzzy_options = if fuzzy_options_enabled {
        case.fuzzy
            .iter()
            .map(|value| {
                FuzzyOption::parse(value)
                    .ok_or_else(|| format!("unsupported fuzzy option {value:?} in {}", case.id))
            })
            .collect::<Result<Vec<_>, _>>()?
    } else {
        Vec::new()
    };
    engine
        .set_quanpin_feature_config(QuanpinFeatureConfig::new(
            spelling_correction_enabled,
            fuzzy_options,
        ))
        .map_err(|error| format!("quanpin feature config failed for {}: {error:?}", case.id))?;
    engine.reset();
    let mut prefix = String::new();
    let mut last = engine.current_state();
    let mut automatic_commit = false;
    let mut ascii_leak = false;
    let mut state_loss = false;
    let mut engine_error = false;
    for key in case.raw_input.chars() {
        prefix.push(key);
        let started = Instant::now();
        last = engine.process_key(key);
        latencies.push(started.elapsed().as_nanos().div_ceil(1_000) as u64);
        if !last.success {
            engine_error = true;
        }
        if !last.commit_text.is_empty() {
            automatic_commit = true;
            ascii_leak |= last
                .commit_text
                .chars()
                .any(|value| value.is_ascii_alphabetic());
        }
        state_loss |= last.raw_input != prefix || last.composition_finished;
    }
    let mut candidates = last
        .candidates
        .iter()
        .map(|candidate| candidate.text.clone())
        .collect::<Vec<_>>();
    let mut candidate_details = last
        .candidates
        .iter()
        .map(candidate_fingerprint)
        .collect::<Vec<_>>();
    while last.has_next_page {
        last = engine
            .next_candidate_page()
            .map_err(|error| format!("candidate paging failed for {}: {error:?}", case.id))?;
        candidates.extend(
            last.candidates
                .iter()
                .map(|candidate| candidate.text.clone()),
        );
        candidate_details.extend(last.candidates.iter().map(candidate_fingerprint));
    }
    let rank = candidates
        .iter()
        .position(|candidate| case.expected_texts.contains(candidate))
        .map(|index| index + 1);
    let fingerprint = format!(
        "{}|{}|{}|{}|{}|{}",
        case.id,
        last.raw_input,
        parser_state(last.parser_state),
        automatic_commit,
        state_loss,
        candidate_details.join("\u{1f}")
    );
    Ok(CaseOutcome {
        case: case.clone(),
        rank,
        no_candidates: candidates.is_empty(),
        candidates,
        automatic_commit,
        ascii_leak,
        state_loss,
        engine_error,
        fingerprint,
        expansion: engine.last_quanpin_expansion_stats(),
        rerank: engine.last_quanpin_reranking_stats(),
    })
}

fn context_reranking_json(
    outcomes: &[CaseOutcome],
    status: &QuanpinContextRerankingStatus,
) -> JsonValue {
    let sum = |select: fn(&RerankStats) -> usize| {
        outcomes
            .iter()
            .map(|outcome| select(&outcome.rerank))
            .sum::<usize>()
    };
    let max = |select: fn(&RerankStats) -> usize| {
        outcomes
            .iter()
            .map(|outcome| select(&outcome.rerank))
            .max()
            .unwrap_or(0)
    };
    JsonValue::object([
        ("enabled", JsonValue::Bool(status.enabled)),
        (
            "modelVersion",
            JsonValue::number(status.model_version as f64),
        ),
        (
            "modelFileBytes",
            JsonValue::number(status.model_file_bytes as f64),
        ),
        (
            "modelMemoryBytes",
            JsonValue::number(status.model_memory_bytes as f64),
        ),
        (
            "modelLoadMicros",
            JsonValue::number(status.model_load_micros as f64),
        ),
        ("lastErrorCode", JsonValue::string(&status.last_error_code)),
        (
            "casesWithHit",
            JsonValue::number(
                outcomes
                    .iter()
                    .filter(|outcome| outcome.rerank.candidates_with_ngram_hit > 0)
                    .count() as f64,
            ),
        ),
        (
            "bigramQueries",
            JsonValue::number(sum(|stats| stats.bigram_queries) as f64),
        ),
        (
            "bigramHits",
            JsonValue::number(sum(|stats| stats.bigram_hits) as f64),
        ),
        (
            "trigramQueries",
            JsonValue::number(sum(|stats| stats.trigram_queries) as f64),
        ),
        (
            "trigramHits",
            JsonValue::number(sum(|stats| stats.trigram_hits) as f64),
        ),
        (
            "trigramBackoffs",
            JsonValue::number(sum(|stats| stats.trigram_backoffs) as f64),
        ),
        (
            "maxCandidatePool",
            JsonValue::number(max(|stats| stats.candidate_pool_size) as f64),
        ),
        (
            "maxBigramQueriesPerKey",
            JsonValue::number(max(|stats| stats.bigram_queries) as f64),
        ),
        (
            "maxTrigramQueriesPerKey",
            JsonValue::number(max(|stats| stats.trigram_queries) as f64),
        ),
        (
            "maxRerankMicros",
            JsonValue::number(
                outcomes
                    .iter()
                    .map(|outcome| outcome.rerank.rerank_micros)
                    .max()
                    .unwrap_or(0) as f64,
            ),
        ),
        (
            "timeoutFallbacks",
            JsonValue::number(sum(|stats| stats.timeout_fallbacks) as f64),
        ),
    ])
}

fn expansion_json(outcomes: &[CaseOutcome]) -> JsonValue {
    let count = outcomes.len().max(1) as f64;
    let sum = |select: fn(&QuanpinExpansionStats) -> usize| -> usize {
        outcomes
            .iter()
            .map(|outcome| select(&outcome.expansion))
            .sum()
    };
    let max = |select: fn(&QuanpinExpansionStats) -> usize| -> usize {
        outcomes
            .iter()
            .map(|outcome| select(&outcome.expansion))
            .max()
            .unwrap_or(0)
    };
    JsonValue::object([
        (
            "spellingVariantsGeneratedMean",
            JsonValue::number(sum(|value| value.spelling_variants_generated) as f64 / count),
        ),
        (
            "spellingVariantsGeneratedMax",
            JsonValue::number(max(|value| value.spelling_variants_generated) as f64),
        ),
        (
            "correctionQueryPathsMean",
            JsonValue::number(sum(|value| value.correction_query_paths) as f64 / count),
        ),
        (
            "correctionQueryPathsMax",
            JsonValue::number(max(|value| value.correction_query_paths) as f64),
        ),
        (
            "fuzzyQueryPathsMean",
            JsonValue::number(sum(|value| value.fuzzy_query_paths) as f64 / count),
        ),
        (
            "fuzzyQueryPathsMax",
            JsonValue::number(max(|value| value.fuzzy_query_paths) as f64),
        ),
        (
            "candidateExpansionsMean",
            JsonValue::number(sum(|value| value.candidate_expansions) as f64 / count),
        ),
        (
            "candidateExpansionsMax",
            JsonValue::number(max(|value| value.candidate_expansions) as f64),
        ),
        (
            "sentenceDecoderPathsMean",
            JsonValue::number(sum(|value| value.sentence_decoder_paths) as f64 / count),
        ),
        (
            "sentenceDecoderPathsMax",
            JsonValue::number(max(|value| value.sentence_decoder_paths) as f64),
        ),
        (
            "truncatedSampleCount",
            JsonValue::number(
                outcomes
                    .iter()
                    .filter(|outcome| outcome.expansion.truncated_by_limit)
                    .count() as f64,
            ),
        ),
        (
            "inputTooLongSampleCount",
            JsonValue::number(
                outcomes
                    .iter()
                    .filter(|outcome| outcome.expansion.input_too_long)
                    .count() as f64,
            ),
        ),
    ])
}

fn candidate_fingerprint(candidate: &engine_protocol::FormalCandidate) -> String {
    format!(
        "{}\u{1e}{}\u{1e}{}\u{1e}{}\u{1e}{}",
        candidate.id,
        candidate.text,
        candidate.reading,
        candidate.source,
        candidate.consumed_raw_len
    )
}

fn parser_state(value: ProtocolParserState) -> &'static str {
    value.as_str()
}

fn counters(outcomes: &[CaseOutcome]) -> Counters {
    let mut result = Counters::default();
    for outcome in outcomes {
        result.count += 1;
        result.no_candidates += usize::from(outcome.no_candidates);
        match outcome.rank {
            Some(rank) => {
                result.top1 += usize::from(rank <= 1);
                result.top3 += usize::from(rank <= 3);
                result.top5 += usize::from(rank <= 5);
                result.recalled_outside_top5 += usize::from(rank > 5);
                result.ranking_errors += usize::from((2..=5).contains(&rank));
                result.reciprocal_rank += 1.0 / rank as f64;
                result.recalled_rank_sum += rank;
                result.recalled_count += 1;
            }
            None => result.unrecalled += 1,
        }
    }
    result
}

fn safety_from_outcomes(outcomes: &[CaseOutcome]) -> Safety {
    Safety {
        automatic_commits: outcomes
            .iter()
            .filter(|value| value.automatic_commit)
            .count(),
        ascii_leaks: outcomes.iter().filter(|value| value.ascii_leak).count(),
        state_losses: outcomes.iter().filter(|value| value.state_loss).count(),
        engine_errors: outcomes.iter().filter(|value| value.engine_error).count(),
    }
}

fn grouped_metrics(outcomes: &[CaseOutcome]) -> JsonValue {
    let mut category = BTreeMap::<String, Vec<CaseOutcome>>::new();
    let mut length = BTreeMap::<String, Vec<CaseOutcome>>::new();
    let mut kind = BTreeMap::<String, Vec<CaseOutcome>>::new();
    for outcome in outcomes {
        category
            .entry(outcome.case.category.clone())
            .or_default()
            .push(outcome.clone());
        let band = raw_input_length_band(outcome.case.raw_input.chars().count());
        length
            .entry(band.to_owned())
            .or_default()
            .push(outcome.clone());
        let group = if outcome.case.tags.iter().any(|value| value == "typo") {
            "typo"
        } else if outcome.case.tags.iter().any(|value| value == "fuzzy") {
            "fuzzy"
        } else {
            "clean"
        };
        kind.entry(group.to_owned())
            .or_default()
            .push(outcome.clone());
    }
    JsonValue::object([
        ("byCategory", outcome_map_json(category)),
        ("byRawInputLength", outcome_map_json(length)),
        ("byInputKind", outcome_map_json(kind)),
    ])
}

fn raw_input_length_band(raw_len: usize) -> &'static str {
    match raw_len {
        0..=4 => "01-04",
        5..=8 => "05-08",
        9..=12 => "09-12",
        13..=20 => "13-20",
        _ => "21+",
    }
}

fn anonymous_distribution_json(
    distribution: Option<&AnonymousInputDistribution>,
    outcomes: &[CaseOutcome],
) -> JsonValue {
    let Some(distribution) = distribution else {
        return JsonValue::object([("provided", JsonValue::Bool(false))]);
    };

    let mut covered_events = 0_u64;
    let mut weighted_top1 = 0.0;
    let mut weighted_top3 = 0.0;
    let mut weighted_top5 = 0.0;
    let mut weighted_mrr = 0.0;
    let mut weighted_unrecalled = 0.0;
    let mut weighted_outside_top5 = 0.0;
    let mut weighted_ranking_errors = 0.0;
    let mut uncovered_bands = Vec::new();
    let mut coverage = Vec::new();

    for band in RAW_INPUT_LENGTH_BANDS {
        let event_count = distribution.length_bands.get(band).copied().unwrap_or(0);
        let band_outcomes = outcomes
            .iter()
            .filter(|outcome| raw_input_length_band(outcome.case.raw_input.chars().count()) == band)
            .cloned()
            .collect::<Vec<_>>();
        let band_metrics = counters(&band_outcomes);
        let covered = event_count == 0 || band_metrics.count > 0;
        if event_count > 0 && !covered {
            uncovered_bands.push(JsonValue::string(band));
        }
        if event_count > 0 && covered {
            covered_events = covered_events.saturating_add(event_count);
            let events = event_count as f64;
            weighted_top1 += rate(band_metrics.top1, band_metrics.count) * events;
            weighted_top3 += rate(band_metrics.top3, band_metrics.count) * events;
            weighted_top5 += rate(band_metrics.top5, band_metrics.count) * events;
            weighted_mrr +=
                band_metrics.reciprocal_rank / band_metrics.count.max(1) as f64 * events;
            weighted_unrecalled += rate(band_metrics.unrecalled, band_metrics.count) * events;
            weighted_outside_top5 +=
                rate(band_metrics.recalled_outside_top5, band_metrics.count) * events;
            weighted_ranking_errors +=
                rate(band_metrics.ranking_errors, band_metrics.count) * events;
        }
        coverage.push((
            band,
            JsonValue::object([
                ("eventCount", JsonValue::number(event_count as f64)),
                (
                    "evaluationCaseCount",
                    JsonValue::number(band_metrics.count as f64),
                ),
                ("covered", JsonValue::Bool(covered)),
            ]),
        ));
    }

    let divisor = covered_events.max(1) as f64;
    let weighted_metrics = if covered_events == 0 {
        JsonValue::Null
    } else {
        JsonValue::object([
            ("top1Rate", JsonValue::number(weighted_top1 / divisor)),
            ("top3Rate", JsonValue::number(weighted_top3 / divisor)),
            ("top5Rate", JsonValue::number(weighted_top5 / divisor)),
            ("mrr", JsonValue::number(weighted_mrr / divisor)),
            (
                "targetUnrecalledRate",
                JsonValue::number(weighted_unrecalled / divisor),
            ),
            (
                "failureBreakdown",
                JsonValue::object([
                    (
                        "targetUnrecalledRate",
                        JsonValue::number(weighted_unrecalled / divisor),
                    ),
                    (
                        "recalledOutsideTop5Rate",
                        JsonValue::number(weighted_outside_top5 / divisor),
                    ),
                    (
                        "rankingErrorRate",
                        JsonValue::number(weighted_ranking_errors / divisor),
                    ),
                ]),
            ),
        ])
    };

    JsonValue::object([
        ("provided", JsonValue::Bool(true)),
        (
            "schemaVersion",
            JsonValue::string("quanpin-distribution-weighted-evaluation/1"),
        ),
        (
            "distributionSha256",
            JsonValue::string(&distribution.sha256),
        ),
        (
            "sourceKind",
            JsonValue::string("opt-in-local-aggregate"),
        ),
        (
            "collectionWindow",
            JsonValue::object([
                ("startDate", JsonValue::string(&distribution.start_date)),
                ("endDate", JsonValue::string(&distribution.end_date)),
            ]),
        ),
        (
            "privacyContract",
            JsonValue::string(
                "aggregate only; raw input, candidate/editor text, application identity, and user identifier are forbidden",
            ),
        ),
        (
            "minimumBucketCount",
            JsonValue::number(distribution.minimum_bucket_count as f64),
        ),
        (
            "totalEvents",
            JsonValue::number(distribution.total_events as f64),
        ),
        (
            "coveredEvents",
            JsonValue::number(covered_events as f64),
        ),
        (
            "coveredEventRate",
            JsonValue::number(rate_u64(covered_events, distribution.total_events)),
        ),
        ("uncoveredBands", JsonValue::array(uncovered_bands)),
        ("lengthBandCoverage", JsonValue::object(coverage)),
        ("weightedMetricsOverCoveredEvents", weighted_metrics),
    ])
}

fn rate_u64(value: u64, count: u64) -> f64 {
    value as f64 / count.max(1) as f64
}

fn outcome_map_json(values: BTreeMap<String, Vec<CaseOutcome>>) -> JsonValue {
    JsonValue::Object(
        values
            .into_iter()
            .map(|(key, outcomes)| (key, metrics_json(&counters(&outcomes))))
            .collect(),
    )
}

fn metrics_json(value: &Counters) -> JsonValue {
    JsonValue::object([
        ("count", JsonValue::number(value.count as f64)),
        ("top1Rate", JsonValue::number(rate(value.top1, value.count))),
        ("top3Rate", JsonValue::number(rate(value.top3, value.count))),
        ("top5Rate", JsonValue::number(rate(value.top5, value.count))),
        (
            "mrr",
            JsonValue::number(value.reciprocal_rank / value.count.max(1) as f64),
        ),
        (
            "noCandidateRate",
            JsonValue::number(rate(value.no_candidates, value.count)),
        ),
        (
            "targetUnrecalledRate",
            JsonValue::number(rate(value.unrecalled, value.count)),
        ),
        (
            "failureBreakdown",
            JsonValue::object([
                (
                    "targetUnrecalledCount",
                    JsonValue::number(value.unrecalled as f64),
                ),
                (
                    "targetUnrecalledRate",
                    JsonValue::number(rate(value.unrecalled, value.count)),
                ),
                (
                    "recalledOutsideTop5Count",
                    JsonValue::number(value.recalled_outside_top5 as f64),
                ),
                (
                    "recalledOutsideTop5Rate",
                    JsonValue::number(rate(value.recalled_outside_top5, value.count)),
                ),
                (
                    "rankingErrorCount",
                    JsonValue::number(value.ranking_errors as f64),
                ),
                (
                    "rankingErrorRate",
                    JsonValue::number(rate(value.ranking_errors, value.count)),
                ),
            ]),
        ),
        (
            "averageFirstRankWhenRecalled",
            if value.recalled_count == 0 {
                JsonValue::Null
            } else {
                JsonValue::number(value.recalled_rank_sum as f64 / value.recalled_count as f64)
            },
        ),
    ])
}

fn run_json(index: usize, outcomes: &[CaseOutcome], latencies: &[u64]) -> JsonValue {
    JsonValue::object([
        ("run", JsonValue::number(index as f64)),
        ("metrics", metrics_json(&counters(outcomes))),
        ("keyLatencyMicros", latency_json(latencies)),
        (
            "candidateOutputSha256",
            JsonValue::string(eval_sha256::hex(
                outcomes
                    .iter()
                    .map(|outcome| outcome.fingerprint.as_str())
                    .collect::<Vec<_>>()
                    .join("\n")
                    .as_bytes(),
            )),
        ),
    ])
}

fn latency_json(values: &[u64]) -> JsonValue {
    if values.is_empty() {
        return JsonValue::Null;
    }
    let mut sorted = values.to_vec();
    sorted.sort_unstable();
    let percentile =
        |percent: usize| -> u64 { sorted[((sorted.len() - 1) * percent).div_ceil(100)] };
    JsonValue::object([
        ("samples", JsonValue::number(sorted.len() as f64)),
        ("p50", JsonValue::number(percentile(50) as f64)),
        ("p95", JsonValue::number(percentile(95) as f64)),
        ("p99", JsonValue::number(percentile(99) as f64)),
        (
            "max",
            JsonValue::number(*sorted.last().expect("nonempty") as f64),
        ),
        (
            "mean",
            JsonValue::number(
                sorted.iter().map(|value| *value as f64).sum::<f64>() / sorted.len() as f64,
            ),
        ),
    ])
}

fn write_failures(path: &Path, outcomes: &[CaseOutcome]) -> Result<(), String> {
    let mut bytes = Vec::new();
    for outcome in outcomes.iter().filter(|outcome| outcome.rank != Some(1)) {
        let failure_type = if outcome.engine_error {
            "engine_error"
        } else if outcome.state_loss {
            "state_loss"
        } else if outcome.automatic_commit {
            "automatic_commit"
        } else if outcome.no_candidates {
            "no_candidates"
        } else if outcome.rank.is_none() {
            "target_unrecalled"
        } else if outcome.rank.is_some_and(|rank| rank > 5) {
            "recalled_outside_top5"
        } else {
            "ranking_error"
        };
        bytes.extend_from_slice(&serialize_line(&JsonValue::object([
            ("id", JsonValue::string(&outcome.case.id)),
            ("rawInput", JsonValue::string(&outcome.case.raw_input)),
            (
                "expectedTexts",
                JsonValue::array(outcome.case.expected_texts.iter().map(JsonValue::string)),
            ),
            ("category", JsonValue::string(&outcome.case.category)),
            ("split", JsonValue::string(&outcome.case.split)),
            (
                "topFiveCandidates",
                JsonValue::array(outcome.candidates.iter().take(5).map(JsonValue::string)),
            ),
            (
                "targetRank",
                outcome
                    .rank
                    .map_or(JsonValue::Null, |rank| JsonValue::number(rank as f64)),
            ),
            ("failureType", JsonValue::string(failure_type)),
            (
                "expansion",
                JsonValue::object([
                    (
                        "spellingVariantsGenerated",
                        JsonValue::number(outcome.expansion.spelling_variants_generated as f64),
                    ),
                    (
                        "correctionQueryPaths",
                        JsonValue::number(outcome.expansion.correction_query_paths as f64),
                    ),
                    (
                        "fuzzyQueryPaths",
                        JsonValue::number(outcome.expansion.fuzzy_query_paths as f64),
                    ),
                    (
                        "candidateExpansions",
                        JsonValue::number(outcome.expansion.candidate_expansions as f64),
                    ),
                    (
                        "sentenceDecoderPaths",
                        JsonValue::number(outcome.expansion.sentence_decoder_paths as f64),
                    ),
                    (
                        "truncatedByLimit",
                        JsonValue::Bool(outcome.expansion.truncated_by_limit),
                    ),
                ]),
            ),
        ])));
    }
    write_json(path, &bytes)
}

fn load_cases(dataset_dir: &Path) -> Result<Vec<DatasetCase>, String> {
    let mut cases = Vec::new();
    for name in ["dev.jsonl", "blind.jsonl"] {
        let path = dataset_dir.join(name);
        let bytes = fs::read(&path).map_err(|error| format!("{}: {error}", path.display()))?;
        let text =
            std::str::from_utf8(&bytes).map_err(|_| format!("{} is not UTF-8", path.display()))?;
        for (line_index, line) in text.lines().enumerate() {
            if line.trim().is_empty() {
                continue;
            }
            let value = parse(line.as_bytes())
                .map_err(|error| format!("{}:{}: {error}", path.display(), line_index + 1))?;
            cases.push(parse_case(value, name, line_index + 1)?);
        }
    }
    Ok(cases)
}

fn parse_case(value: JsonValue, file: &str, line: usize) -> Result<DatasetCase, String> {
    let object = value
        .as_object()
        .ok_or_else(|| format!("{file}:{line}: case must be an object"))?;
    let strings = |name: &str| -> Result<Vec<String>, String> {
        object
            .get(name)
            .and_then(JsonValue::as_array)
            .ok_or_else(|| format!("{file}:{line}: missing array {name}"))?
            .iter()
            .map(|value| {
                value
                    .as_str()
                    .map(str::to_owned)
                    .ok_or_else(|| format!("{file}:{line}: non-string in {name}"))
            })
            .collect()
    };
    let string = |name: &str| -> Result<String, String> {
        object
            .get(name)
            .and_then(JsonValue::as_str)
            .map(str::to_owned)
            .ok_or_else(|| format!("{file}:{line}: missing string {name}"))
    };
    Ok(DatasetCase {
        id: string("id")?,
        raw_input: string("rawInput")?,
        expected_texts: strings("expectedTexts")?,
        category: string("category")?,
        tags: strings("tags")?,
        source: string("source")?,
        split: string("split")?,
        fuzzy: object
            .get("enabledFuzzyOptions")
            .map(|_| strings("enabledFuzzyOptions"))
            .transpose()?
            .unwrap_or_default(),
        notes: object
            .get("notes")
            .and_then(JsonValue::as_str)
            .map(str::to_owned),
    })
}

fn validate_cases(cases: &[DatasetCase]) -> Result<BTreeMap<String, usize>, String> {
    let is_v2 = !cases.is_empty() && cases.iter().all(|case| case.id.starts_with("qpv2-"));
    let minimum_cases = if is_v2 { 120 } else { 1000 };
    if cases.len() < minimum_cases {
        return Err(format!(
            "dataset has {} cases; minimum is {minimum_cases}",
            cases.len()
        ));
    }
    let mut ids = BTreeSet::new();
    let mut pairs = BTreeSet::new();
    let mut counts = BTreeMap::<String, usize>::new();
    let mut split = BTreeMap::<String, usize>::new();
    for case in cases {
        if !ids.insert(case.id.clone()) {
            return Err(format!("duplicate id {}", case.id));
        }
        let pair = format!("{}\0{}", case.raw_input, case.expected_texts.join("\u{1f}"));
        if !pairs.insert(pair) {
            return Err(format!("duplicate rawInput/expectedTexts at {}", case.id));
        }
        if case.raw_input.is_empty()
            || !case
                .raw_input
                .chars()
                .all(|value| value.is_ascii_lowercase() || value == '\'')
        {
            return Err(format!(
                "{} has illegal rawInput {:?}",
                case.id, case.raw_input
            ));
        }
        if case.expected_texts.is_empty()
            || case
                .expected_texts
                .iter()
                .any(|value| value.trim().is_empty())
        {
            return Err(format!("{} has empty expectedTexts", case.id));
        }
        if !matches!(case.split.as_str(), "dev" | "blind") {
            return Err(format!("{} has invalid split {}", case.id, case.split));
        }
        if case.source.trim().is_empty() {
            return Err(format!("{} has empty source", case.id));
        }
        let fuzzy_tag = case.tags.iter().any(|value| value == "fuzzy");
        if fuzzy_tag == case.fuzzy.is_empty() {
            return Err(format!(
                "{} must use enabledFuzzyOptions only for fuzzy cases",
                case.id
            ));
        }
        if !fuzzy_tag
            && !case.tags.iter().any(|value| value == "typo")
            && case.category != "abbrev_mixed_incomplete"
            && !is_segmentable_pinyin(&case.raw_input)
        {
            return Err(format!(
                "{} has illegal clean pinyin {}",
                case.id, case.raw_input
            ));
        }
        if case
            .notes
            .as_deref()
            .is_some_and(|value| value.trim().is_empty())
        {
            return Err(format!("{} has blank notes", case.id));
        }
        *counts.entry(case.category.clone()).or_default() += 1;
        *split.entry(case.split.clone()).or_default() += 1;
    }
    let required_counts: &[(&str, usize)] = if is_v2 { &V2_MIN_COUNTS } else { &MIN_COUNTS };
    for &(category, minimum) in required_counts {
        let actual = *counts.get(category).unwrap_or(&0);
        if actual < minimum {
            return Err(format!(
                "category {category} has {actual}; minimum is {minimum}"
            ));
        }
    }
    let split_valid = if is_v2 {
        split.get("dev").copied().unwrap_or(0) >= 48
            && split.get("blind").copied().unwrap_or(0) >= 72
    } else {
        split.get("dev") == Some(&300) && split.get("blind").copied().unwrap_or(0) >= 700
    };
    if !split_valid {
        return Err(format!(
            "invalid dev/blind distribution for {} dataset: {split:?}",
            if is_v2 { "V2" } else { "V1" }
        ));
    }
    Ok(counts)
}

fn is_segmentable_pinyin(raw: &str) -> bool {
    fn walk(raw: &str, offset: usize, memo: &mut BTreeMap<usize, bool>) -> bool {
        if offset == raw.len() {
            return true;
        }
        if let Some(value) = memo.get(&offset) {
            return *value;
        }
        let valid = pinyin_syllable::all_syllables().any(|syllable| {
            raw[offset..].starts_with(syllable) && walk(raw, offset + syllable.len(), memo)
        });
        memo.insert(offset, valid);
        valid
    }
    raw.split('\'')
        .all(|part| !part.is_empty() && walk(part, 0, &mut BTreeMap::new()))
}

#[derive(Clone)]
struct DatasetFile {
    path: String,
    bytes: usize,
    sha256: String,
    sample_count: usize,
    category_counts: BTreeMap<String, usize>,
}

fn dataset_files(dataset_dir: &Path) -> Result<Vec<DatasetFile>, String> {
    let mut paths = fs::read_dir(dataset_dir)
        .map_err(|error| error.to_string())?
        .map(|entry| {
            entry
                .map(|entry| entry.path())
                .map_err(|error| error.to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    paths.retain(|path| path.is_file());
    paths.sort();
    let mut result = Vec::new();
    for path in paths {
        let bytes = fs::read(&path).map_err(|error| error.to_string())?;
        let name = path
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or_else(|| "non-UTF8 dataset filename".to_owned())?
            .to_owned();
        let cases = if name.ends_with(".jsonl") {
            parse_cases_from_bytes(&bytes, &name)?
        } else {
            Vec::new()
        };
        let mut category_counts = BTreeMap::new();
        for case in &cases {
            *category_counts.entry(case.category.clone()).or_default() += 1;
        }
        result.push(DatasetFile {
            path: name,
            bytes: bytes.len(),
            sha256: eval_sha256::hex(&bytes),
            sample_count: cases.len(),
            category_counts,
        });
    }
    Ok(result)
}

fn parse_cases_from_bytes(bytes: &[u8], file: &str) -> Result<Vec<DatasetCase>, String> {
    let text = std::str::from_utf8(bytes).map_err(|_| format!("{file} is not UTF-8"))?;
    text.lines()
        .enumerate()
        .filter(|(_, line)| !line.trim().is_empty())
        .map(|(index, line)| {
            parse(line.as_bytes())
                .map_err(|error| format!("{file}:{}: {error}", index + 1))
                .and_then(|value| parse_case(value, file, index + 1))
        })
        .collect()
}

fn verify_manifest(dataset_dir: &Path, manifest_path: &Path) -> Result<(), String> {
    let manifest_bytes = fs::read(manifest_path).map_err(|error| error.to_string())?;
    let manifest = parse(&manifest_bytes)?;
    let object = manifest
        .as_object()
        .ok_or_else(|| "manifest must be object".to_owned())?;
    let expected_files = object
        .get("files")
        .and_then(JsonValue::as_array)
        .ok_or_else(|| "manifest missing files".to_owned())?;
    let actual = dataset_files(dataset_dir)?;
    if actual.len() != expected_files.len() {
        return Err("FROZEN_DATASET_FILE_SET_CHANGED".to_owned());
    }
    for (expected, actual) in expected_files.iter().zip(actual.iter()) {
        let expected = expected
            .as_object()
            .ok_or_else(|| "bad manifest file".to_owned())?;
        let path = expected
            .get("path")
            .and_then(JsonValue::as_str)
            .unwrap_or("");
        let bytes = expected
            .get("bytes")
            .and_then(JsonValue::as_u64)
            .unwrap_or(u64::MAX);
        let hash = expected
            .get("sha256")
            .and_then(JsonValue::as_str)
            .unwrap_or("");
        if path != actual.path || bytes != actual.bytes as u64 || hash != actual.sha256 {
            return Err(format!(
                "FROZEN_DATASET_HASH_MISMATCH: {} expected {hash}/{bytes}, actual {}/{}; use an explicit new baseline version instead of editing frozen data",
                actual.path, actual.sha256, actual.bytes
            ));
        }
    }
    Ok(())
}

fn validation_json(cases: &[DatasetCase], counts: &BTreeMap<String, usize>) -> JsonValue {
    JsonValue::object([
        ("valid", JsonValue::Bool(true)),
        ("sampleCount", JsonValue::number(cases.len() as f64)),
        ("splitDistribution", count_map_json(split_counts(cases))),
        ("categoryDistribution", count_map_json(counts.clone())),
    ])
}

fn split_counts(cases: &[DatasetCase]) -> BTreeMap<String, usize> {
    let mut counts = BTreeMap::new();
    for case in cases {
        *counts.entry(case.split.clone()).or_default() += 1;
    }
    counts
}

fn count_map_json(values: BTreeMap<String, usize>) -> JsonValue {
    JsonValue::Object(
        values
            .into_iter()
            .map(|(key, value)| (key, JsonValue::number(value as f64)))
            .collect(),
    )
}

fn environment_json() -> JsonValue {
    let rustc = Command::new("rustc")
        .arg("--version")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned())
        .unwrap_or_else(|| "unknown".to_owned());
    JsonValue::object([
        ("os", JsonValue::string(std::env::consts::OS)),
        ("arch", JsonValue::string(std::env::consts::ARCH)),
        ("rustc", JsonValue::string(rustc)),
        (
            "processorIdentifier",
            JsonValue::string(
                std::env::var("PROCESSOR_IDENTIFIER").unwrap_or_else(|_| "unknown".to_owned()),
            ),
        ),
        ("cargoProfile", JsonValue::string("release")),
    ])
}

#[cfg(windows)]
fn process_peak_working_set_bytes() -> Option<u64> {
    use std::ffi::c_void;

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
        fn GetCurrentProcess() -> *mut c_void;
    }
    #[link(name = "psapi")]
    unsafe extern "system" {
        fn GetProcessMemoryInfo(
            process: *mut c_void,
            counters: *mut ProcessMemoryCounters,
            size: u32,
        ) -> i32;
    }

    let mut counters = ProcessMemoryCounters {
        cb: std::mem::size_of::<ProcessMemoryCounters>() as u32,
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
    let ok = unsafe {
        GetProcessMemoryInfo(
            GetCurrentProcess(),
            &mut counters,
            std::mem::size_of::<ProcessMemoryCounters>() as u32,
        )
    };
    (ok != 0).then_some(counters.peak_working_set_size as u64)
}

#[cfg(not(windows))]
fn process_peak_working_set_bytes() -> Option<u64> {
    None
}

fn write_json(path: &Path, bytes: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(path, bytes).map_err(|error| error.to_string())
}

fn rate(value: usize, count: usize) -> f64 {
    value as f64 / count.max(1) as f64
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn pinyin_validation_accepts_segments_and_rejects_noise() {
        assert!(is_segmentable_pinyin("nihao"));
        assert!(is_segmentable_pinyin("xi'an"));
        assert!(!is_segmentable_pinyin("abcxyz"));
    }

    #[test]
    fn metrics_do_not_turn_low_quality_into_an_error() {
        let value = Counters {
            count: 10,
            unrecalled: 10,
            ..Counters::default()
        };
        let json = metrics_json(&value);
        assert_eq!(
            json.as_object()
                .and_then(|value| value.get("top1Rate"))
                .and_then(JsonValue::as_u64),
            Some(0)
        );
    }

    #[test]
    fn failure_breakdown_is_mutually_exclusive_and_complete() {
        let case = |id: &str| DatasetCase {
            id: id.to_owned(),
            raw_input: "ni".to_owned(),
            expected_texts: vec!["你".to_owned()],
            category: "clean".to_owned(),
            tags: vec!["clean".to_owned()],
            source: "unit-test".to_owned(),
            split: "dev".to_owned(),
            fuzzy: Vec::new(),
            notes: None,
        };
        let outcome = |id: &str, rank: Option<usize>| CaseOutcome {
            case: case(id),
            rank,
            candidates: Vec::new(),
            no_candidates: rank.is_none(),
            automatic_commit: false,
            ascii_leak: false,
            state_loss: false,
            engine_error: false,
            fingerprint: String::new(),
            expansion: QuanpinExpansionStats::default(),
            rerank: RerankStats::default(),
        };
        let values = [
            outcome("top1", Some(1)),
            outcome("ranking", Some(3)),
            outcome("outside", Some(9)),
            outcome("missing", None),
        ];

        let counts = counters(&values);
        assert_eq!(counts.top1, 1);
        assert_eq!(counts.ranking_errors, 1);
        assert_eq!(counts.recalled_outside_top5, 1);
        assert_eq!(counts.unrecalled, 1);
        assert_eq!(
            counts.top1 + counts.ranking_errors + counts.recalled_outside_top5 + counts.unrecalled,
            counts.count
        );

        let json = metrics_json(&counts);
        let breakdown = json
            .as_object()
            .and_then(|value| value.get("failureBreakdown"))
            .and_then(JsonValue::as_object)
            .expect("failure breakdown");
        assert_eq!(
            breakdown
                .get("targetUnrecalledCount")
                .and_then(JsonValue::as_u64),
            Some(1)
        );
        assert_eq!(
            breakdown
                .get("recalledOutsideTop5Count")
                .and_then(JsonValue::as_u64),
            Some(1)
        );
        assert_eq!(
            breakdown
                .get("rankingErrorCount")
                .and_then(JsonValue::as_u64),
            Some(1)
        );
    }

    #[test]
    fn frozen_hash_change_is_a_hard_error() {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "candidate-baseline-freeze-test-{}-{nonce}",
            std::process::id()
        ));
        let dataset = root.join("dataset");
        let manifest = root.join("freeze-manifest.json");
        crate::create_quanpin_dataset(&dataset).expect("create authored dataset");
        freeze_quanpin_dataset(
            &dataset,
            &manifest,
            "unit-test-baseline",
            "2026-08-13T00:00:00+08:00",
        )
        .expect("freeze");
        let dev = dataset.join("dev.jsonl");
        let mut bytes = fs::read(&dev).expect("dev bytes");
        bytes.push(b' ');
        fs::write(&dev, bytes).expect("mutate fixture");
        let error = verify_manifest(&dataset, &manifest).expect_err("hash mismatch");
        assert!(error.contains("FROZEN_DATASET_HASH_MISMATCH"));
        fs::remove_dir_all(&root).expect("remove isolated temp test directory");
    }
}
