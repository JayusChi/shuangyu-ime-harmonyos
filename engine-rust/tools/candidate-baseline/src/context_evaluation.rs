use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::Instant;

use context_reranker::{
    RerankStats, MAX_BIGRAM_QUERIES, MAX_CANDIDATE_POOL, MAX_MODEL_FILE_BYTES,
    MAX_MODEL_LOAD_MICROS, MAX_MODEL_MEMORY_BYTES, MAX_RERANK_MICROS, MAX_TRIGRAM_QUERIES,
};
use engine_protocol::{CompositionResult, FormalCandidate};
use ime_engine::{
    EngineConfig, ImeEngine, QuanpinContextRerankingConfig, QuanpinContextRerankingStatus,
};
use lexicon_core::load_binary_lexicon;

use crate::eval_json::{parse, serialize, serialize_line, JsonValue};
use crate::eval_sha256;

const REQUIRED_CATEGORIES: [&str; 5] = [
    "clean",
    "modern_colloquial",
    "proper_name",
    "long_sentence",
    "ambiguous",
];

/// Offline diagnostic only. It scans the audited finite model to find
/// production candidates whose rank changes, proving the binary is effective
/// without adding any runtime rule or generating a candidate.
pub fn discover_quanpin_context_improvements(
    lexicon_path: &Path,
    model_path: &Path,
    model_sha256: &str,
    audit_path: &Path,
    limit: usize,
) -> Result<String, String> {
    let lexicon_bytes = fs::read(lexicon_path).map_err(|error| error.to_string())?;
    let lexicon = load_binary_lexicon(&lexicon_bytes).map_err(|error| error.to_string())?;
    let mut readings = BTreeMap::<String, Vec<(u64, String)>>::new();
    for entry in &lexicon.entries {
        if entry.syllables.len() >= 2 {
            readings
                .entry(entry.word.clone())
                .or_default()
                .push((entry.frequency, entry.syllables.concat()));
        }
    }
    for values in readings.values_mut() {
        values.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
        values.dedup_by(|left, right| left.1 == right.1);
    }
    let mut base = ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        candidate_page_size: 50,
        ..EngineConfig::default()
    })
    .map_err(|error| error.to_string())?;
    let mut reranked = ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        candidate_page_size: 50,
        quanpin_context_reranking: QuanpinContextRerankingConfig::new(
            true,
            Some(model_path.to_string_lossy().into_owned()),
            Some(model_sha256.to_owned()),
        ),
        ..EngineConfig::default()
    })
    .map_err(|error| error.to_string())?;
    if !reranked.quanpin_context_reranking_status().enabled {
        return Err("model failed to load for discovery".to_owned());
    }
    base.set_user_learning_enabled(false);
    reranked.set_user_learning_enabled(false);
    reranked.set_session_learning_allowed(true);

    let audit = fs::read_to_string(audit_path).map_err(|error| error.to_string())?;
    let mut rows = String::from(
        "kind\tleft\tleftRaw\tmiddle\tmiddleRaw\tright\trightRaw\tbaseRank\trerankedRank\n",
    );
    let mut audited_bigrams = 0usize;
    let mut comparable = 0usize;
    let mut improved = 0usize;
    let mut unchanged = 0usize;
    let mut worsened = 0usize;
    let mut lower_than_top1 = 0usize;
    let mut emitted = 0usize;
    for line in audit.lines().skip(1) {
        let fields = line.split('\t').collect::<Vec<_>>();
        if fields.len() != 5 || fields[0] != "bigram" {
            continue;
        }
        audited_bigrams += 1;
        let left = fields[1];
        let right = fields[3];
        let Some(left_raw) = readings
            .get(left)
            .and_then(|values| values.first())
            .map(|value| value.1.as_str())
        else {
            continue;
        };
        let Some(right_raw) = readings
            .get(right)
            .and_then(|values| values.first())
            .map(|value| value.1.as_str())
        else {
            continue;
        };

        base.reset();
        let base_state = type_raw_simple(&mut base, right_raw);
        let Some(base_rank) = candidate_rank(&mut base, base_state, right)? else {
            continue;
        };
        lower_than_top1 += usize::from(base_rank > 1);

        reranked.reset();
        let left_state = type_raw_simple(&mut reranked, left_raw);
        if !select_context_candidate(&mut reranked, left_state, left)?.0 {
            continue;
        }
        let reranked_state = type_raw_simple(&mut reranked, right_raw);
        let Some(reranked_rank) = candidate_rank(&mut reranked, reranked_state, right)? else {
            continue;
        };
        comparable += 1;
        match reranked_rank.cmp(&base_rank) {
            std::cmp::Ordering::Less => {
                if emitted < limit {
                    rows.push_str(&format!(
                        "bigram\t{left}\t{left_raw}\t\t\t{right}\t{right_raw}\t{base_rank}\t{reranked_rank}\n"
                    ));
                    emitted += 1;
                }
                improved += 1;
            }
            std::cmp::Ordering::Equal => unchanged += 1,
            std::cmp::Ordering::Greater => worsened += 1,
        }
    }

    let mut audited_trigrams = 0usize;
    let mut comparable_trigrams = 0usize;
    let mut improved_trigrams = 0usize;
    let mut unchanged_trigrams = 0usize;
    let mut worsened_trigrams = 0usize;
    for line in audit.lines().skip(1) {
        let fields = line.split('\t').collect::<Vec<_>>();
        if fields.len() != 5 || fields[0] != "trigram" {
            continue;
        }
        audited_trigrams += 1;
        let left = fields[1];
        let middle = fields[2];
        let right = fields[3];
        let Some(left_raw) = readings
            .get(left)
            .and_then(|values| values.first())
            .map(|value| value.1.as_str())
        else {
            continue;
        };
        let Some(middle_raw) = readings
            .get(middle)
            .and_then(|values| values.first())
            .map(|value| value.1.as_str())
        else {
            continue;
        };
        let Some(right_raw) = readings
            .get(right)
            .and_then(|values| values.first())
            .map(|value| value.1.as_str())
        else {
            continue;
        };
        base.reset();
        let base_state = type_raw_simple(&mut base, right_raw);
        let Some(base_rank) = candidate_rank(&mut base, base_state, right)? else {
            continue;
        };
        reranked.reset();
        let left_state = type_raw_simple(&mut reranked, left_raw);
        if !select_context_candidate(&mut reranked, left_state, left)?.0 {
            continue;
        }
        let middle_state = type_raw_simple(&mut reranked, middle_raw);
        if !select_context_candidate(&mut reranked, middle_state, middle)?.0 {
            continue;
        }
        let reranked_state = type_raw_simple(&mut reranked, right_raw);
        let Some(reranked_rank) = candidate_rank(&mut reranked, reranked_state, right)? else {
            continue;
        };
        comparable_trigrams += 1;
        match reranked_rank.cmp(&base_rank) {
            std::cmp::Ordering::Less => {
                if emitted < limit {
                    rows.push_str(&format!(
                        "trigram\t{left}\t{left_raw}\t{middle}\t{middle_raw}\t{right}\t{right_raw}\t{base_rank}\t{reranked_rank}\n"
                    ));
                    emitted += 1;
                }
                improved_trigrams += 1;
            }
            std::cmp::Ordering::Equal => unchanged_trigrams += 1,
            std::cmp::Ordering::Greater => worsened_trigrams += 1,
        }
    }
    Ok(format!(
        "# schemaVersion=quanpin-context-model-effectiveness-audit/1\n# auditedBigrams={audited_bigrams}\n# comparableBigramPairs={comparable}\n# baseLowerThanTop1={lower_than_top1}\n# improvedBigramPairs={improved}\n# unchangedBigramPairs={unchanged}\n# worsenedBigramPairs={worsened}\n# auditedTrigrams={audited_trigrams}\n# comparableTrigramPairs={comparable_trigrams}\n# improvedTrigramPairs={improved_trigrams}\n# unchangedTrigramPairs={unchanged_trigrams}\n# worsenedTrigramPairs={worsened_trigrams}\n# note=Model-derived offline diagnostic; not an independent dev or blind quality set.\n{rows}"
    ))
}

fn type_raw_simple(engine: &mut ImeEngine, raw: &str) -> CompositionResult {
    let mut state = engine.current_state();
    for key in raw.chars() {
        state = engine.process_key(key);
    }
    state
}

fn candidate_rank(
    engine: &mut ImeEngine,
    state: CompositionResult,
    expected: &str,
) -> Result<Option<usize>, String> {
    let (candidates, _) = collect_candidates(engine, state)?;
    Ok(candidates
        .iter()
        .position(|candidate| candidate == expected)
        .map(|index| index + 1))
}

#[derive(Clone, Debug)]
struct ContextCase {
    id: String,
    category: String,
    raw_input: String,
    expected_text: String,
    context_raw_inputs: Vec<String>,
    context_expected_texts: Vec<String>,
    source: String,
}

#[derive(Clone, Debug)]
struct Outcome {
    case: ContextCase,
    rank: Option<usize>,
    candidates: Vec<String>,
    fingerprint: String,
    context_setup_failed: bool,
    no_candidates: bool,
    automatic_commit: bool,
    ascii_leak: bool,
    state_loss: bool,
    engine_error: bool,
    rerank: RerankStats,
}

#[derive(Clone, Debug, Default)]
struct Metrics {
    count: usize,
    top1: usize,
    top3: usize,
    top5: usize,
    reciprocal_rank: f64,
    recalled_rank_sum: usize,
    recalled_count: usize,
    no_candidates: usize,
    unrecalled: usize,
    recalled_outside_top5: usize,
    ranking_errors: usize,
    extra_selection_sum: usize,
}

#[derive(Clone, Debug, Default)]
struct Safety {
    automatic_commits: usize,
    ascii_leaks: usize,
    state_losses: usize,
    engine_errors: usize,
    context_setup_failures: usize,
}

pub struct QuanpinContextEvaluationRequest<'a> {
    pub dataset_path: &'a Path,
    pub manifest_path: &'a Path,
    pub lexicon_path: &'a Path,
    pub model_path: Option<&'a Path>,
    pub model_sha256: Option<&'a str>,
    pub results_path: &'a Path,
    pub failures_path: &'a Path,
    pub runs: usize,
}

pub fn freeze_quanpin_context_dataset(
    dataset_path: &Path,
    manifest_path: &Path,
    dataset_id: &str,
    frozen_at: &str,
) -> Result<String, String> {
    if manifest_path.exists() {
        return Err(format!(
            "manifest already exists: {}",
            manifest_path.display()
        ));
    }
    if dataset_id.trim().is_empty() || frozen_at.trim().is_empty() {
        return Err("dataset id and frozen time are required".to_owned());
    }
    let bytes = fs::read(dataset_path).map_err(|error| error.to_string())?;
    let cases = load_cases(&bytes)?;
    validate_cases(&cases)?;
    let hash = eval_sha256::hex(&bytes);
    let manifest = JsonValue::object([
        (
            "schemaVersion",
            JsonValue::string("quanpin-context-reranking-dataset-freeze/1"),
        ),
        ("datasetId", JsonValue::string(dataset_id)),
        ("frozenAt", JsonValue::string(frozen_at)),
        (
            "path",
            JsonValue::string(
                dataset_path
                    .file_name()
                    .and_then(|value| value.to_str())
                    .unwrap_or("dataset.jsonl"),
            ),
        ),
        ("bytes", JsonValue::number(bytes.len() as f64)),
        ("sha256", JsonValue::string(&hash)),
        ("sampleCount", JsonValue::number(cases.len() as f64)),
        (
            "categoryDistribution",
            count_map_json(category_counts(&cases)),
        ),
        (
            "mutationPolicy",
            JsonValue::string("Any byte change requires a new dataset id and manifest path."),
        ),
    ]);
    write_file(manifest_path, &serialize(&manifest))?;
    Ok(format!(
        "frozen {} context cases as {dataset_id}: {hash}",
        cases.len()
    ))
}

pub fn evaluate_quanpin_context_dataset(
    request: &QuanpinContextEvaluationRequest<'_>,
) -> Result<String, String> {
    if cfg!(debug_assertions) {
        return Err("context evaluation must run in Cargo release mode".to_owned());
    }
    if request.runs < 3 {
        return Err("at least three runs are required".to_owned());
    }
    if request.model_path.is_some() != request.model_sha256.is_some() {
        return Err("model path and SHA-256 must be supplied together".to_owned());
    }
    if request.results_path.exists() || request.failures_path.exists() {
        return Err("evaluation outputs already exist; refusing to overwrite evidence".to_owned());
    }
    let dataset_bytes = fs::read(request.dataset_path).map_err(|error| error.to_string())?;
    let cases = load_cases(&dataset_bytes)?;
    validate_cases(&cases)?;
    verify_manifest(request.manifest_path, &dataset_bytes, cases.len())?;
    let lexicon_bytes = fs::read(request.lexicon_path).map_err(|error| error.to_string())?;
    let manifest_bytes = fs::read(request.manifest_path).map_err(|error| error.to_string())?;
    let model_bytes = request
        .model_path
        .map(fs::read)
        .transpose()
        .map_err(|error| error.to_string())?;

    let mut all_runs = Vec::new();
    let mut all_latencies = Vec::new();
    let mut target_latencies = Vec::new();
    let mut engine_load_latencies = Vec::new();
    let mut first_outcomes = Vec::new();
    let mut expected_fingerprints: Option<Vec<String>> = None;
    let mut deterministic = true;
    let mut total_safety = Safety::default();
    let mut status: Option<QuanpinContextRerankingStatus> = None;

    for run in 1..=request.runs {
        let load_started = Instant::now();
        let mut engine = ImeEngine::new(EngineConfig {
            scheme_id: "quanpin".to_owned(),
            lexicon_path: Some(request.lexicon_path.to_string_lossy().into_owned()),
            candidate_page_size: 50,
            quanpin_context_reranking: QuanpinContextRerankingConfig::new(
                request.model_path.is_some(),
                request
                    .model_path
                    .map(|path| path.to_string_lossy().into_owned()),
                request.model_sha256.map(str::to_owned),
            ),
            ..EngineConfig::default()
        })
        .map_err(|error| error.to_string())?;
        engine_load_latencies.push(load_started.elapsed().as_micros() as u64);
        engine.set_user_learning_enabled(false);
        engine.set_session_learning_allowed(true);
        let current_status = engine.quanpin_context_reranking_status();
        if request.model_path.is_some() && !current_status.enabled {
            return Err(format!(
                "configured model failed to load: {}",
                current_status.last_error_code
            ));
        }
        status = Some(current_status);

        let mut outcomes = Vec::new();
        let mut run_latencies = Vec::new();
        let mut run_target_latencies = Vec::new();
        for case in &cases {
            outcomes.push(run_case(
                &mut engine,
                case,
                &mut run_latencies,
                &mut run_target_latencies,
            )?);
        }
        let fingerprints = outcomes
            .iter()
            .map(|outcome| outcome.fingerprint.clone())
            .collect::<Vec<_>>();
        deterministic &= expected_fingerprints
            .as_ref()
            .is_none_or(|expected| *expected == fingerprints);
        if expected_fingerprints.is_none() {
            expected_fingerprints = Some(fingerprints);
        }
        let safety = safety(&outcomes);
        add_safety(&mut total_safety, &safety);
        all_runs.push(run_json(run, &outcomes, &run_latencies));
        all_latencies.extend(run_latencies);
        target_latencies.extend(run_target_latencies);
        if run == 1 {
            first_outcomes = outcomes;
        }
    }

    let status = status.expect("at least one run");
    let metrics = metrics(&first_outcomes);
    let report = JsonValue::object([
        (
            "schemaVersion",
            JsonValue::string("quanpin-context-reranking-results/2"),
        ),
        (
            "measurementKind",
            JsonValue::string("host-release-ImeEngine-explicit-context-per-key"),
        ),
        (
            "datasetManifestSha256",
            JsonValue::string(eval_sha256::hex(&manifest_bytes)),
        ),
        (
            "datasetSha256",
            JsonValue::string(eval_sha256::hex(&dataset_bytes)),
        ),
        (
            "productionLexiconSha256",
            JsonValue::string(eval_sha256::hex(&lexicon_bytes)),
        ),
        (
            "modelSha256",
            model_bytes.as_ref().map_or(JsonValue::Null, |bytes| {
                JsonValue::string(eval_sha256::hex(bytes))
            }),
        ),
        ("modelEnabled", JsonValue::Bool(status.enabled)),
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
        (
            "modelLastErrorCode",
            JsonValue::string(&status.last_error_code),
        ),
        (
            "sampleCount",
            JsonValue::number(first_outcomes.len() as f64),
        ),
        ("runCount", JsonValue::number(request.runs as f64)),
        (
            "deterministicCandidateOutputs",
            JsonValue::Bool(deterministic),
        ),
        ("metrics", metrics_json(&metrics)),
        ("groups", grouped_json(&first_outcomes)),
        ("ngram", ngram_json(&first_outcomes)),
        ("allKeyLatencyMicros", latency_json(&all_latencies)),
        ("targetKeyLatencyMicros", latency_json(&target_latencies)),
        (
            "engineLoadLatencyMicros",
            latency_json(&engine_load_latencies),
        ),
        ("hardLimits", hard_limits_json()),
        ("runs", JsonValue::array(all_runs)),
        ("safetyContract", safety_json(&total_safety)),
        ("environment", environment_json()),
        (
            "interpretation",
            JsonValue::object([
                ("hostDataOnly", JsonValue::Bool(true)),
                ("deviceDataIncluded", JsonValue::Bool(false)),
                (
                    "contextSource",
                    JsonValue::string(
                        "Only formal candidates explicitly selected within each case.",
                    ),
                ),
            ]),
        ),
    ]);
    write_file(request.results_path, &serialize(&report))?;
    write_failures(request.failures_path, &first_outcomes)?;

    if !deterministic
        || total_safety.automatic_commits > 0
        || total_safety.ascii_leaks > 0
        || total_safety.state_losses > 0
        || total_safety.engine_errors > 0
        || total_safety.context_setup_failures > 0
    {
        return Err(
            "context evaluation determinism/safety gate failed after writing evidence".to_owned(),
        );
    }
    Ok(format!(
        "evaluated {} cases x {} runs: Top1 {:.3}%, Top3 {:.3}%, Top5 {:.3}%",
        metrics.count,
        request.runs,
        rate(metrics.top1, metrics.count) * 100.0,
        rate(metrics.top3, metrics.count) * 100.0,
        rate(metrics.top5, metrics.count) * 100.0
    ))
}

fn run_case(
    engine: &mut ImeEngine,
    case: &ContextCase,
    all_latencies: &mut Vec<u64>,
    target_latencies: &mut Vec<u64>,
) -> Result<Outcome, String> {
    engine.reset();
    engine.set_session_learning_allowed(true);
    let mut automatic_commit = false;
    let mut ascii_leak = false;
    let mut state_loss = false;
    let mut engine_error = false;
    let mut context_setup_failed = false;
    let mut context_fingerprints = Vec::new();

    for (raw, expected) in case
        .context_raw_inputs
        .iter()
        .zip(&case.context_expected_texts)
    {
        let state = type_raw(
            engine,
            raw,
            all_latencies,
            None,
            &mut automatic_commit,
            &mut ascii_leak,
            &mut state_loss,
            &mut engine_error,
        );
        let (found, fingerprint) = select_context_candidate(engine, state, expected)?;
        context_fingerprints.push(fingerprint);
        if !found {
            context_setup_failed = true;
            engine.reset();
            break;
        }
    }

    let last = type_raw(
        engine,
        &case.raw_input,
        all_latencies,
        Some(target_latencies),
        &mut automatic_commit,
        &mut ascii_leak,
        &mut state_loss,
        &mut engine_error,
    );
    let rerank = engine.last_quanpin_reranking_stats();
    let (candidates, details) = collect_candidates(engine, last)?;
    let rank = candidates
        .iter()
        .position(|candidate| candidate == &case.expected_text)
        .map(|index| index + 1);
    let fingerprint = format!(
        "{}|{}|{}|{}",
        case.id,
        context_fingerprints.join("\u{1d}"),
        context_setup_failed,
        details.join("\u{1f}")
    );
    Ok(Outcome {
        case: case.clone(),
        rank,
        no_candidates: candidates.is_empty(),
        candidates,
        fingerprint,
        context_setup_failed,
        automatic_commit,
        ascii_leak,
        state_loss,
        engine_error,
        rerank,
    })
}

#[allow(clippy::too_many_arguments)]
fn type_raw(
    engine: &mut ImeEngine,
    raw: &str,
    all_latencies: &mut Vec<u64>,
    mut target_latencies: Option<&mut Vec<u64>>,
    automatic_commit: &mut bool,
    ascii_leak: &mut bool,
    state_loss: &mut bool,
    engine_error: &mut bool,
) -> CompositionResult {
    let mut prefix = String::new();
    let mut last = engine.current_state();
    for key in raw.chars() {
        prefix.push(key);
        let started = Instant::now();
        last = engine.process_key(key);
        let elapsed = started.elapsed().as_nanos().div_ceil(1_000) as u64;
        all_latencies.push(elapsed);
        if let Some(values) = target_latencies.as_deref_mut() {
            values.push(elapsed);
        }
        *engine_error |= !last.success;
        *automatic_commit |= !last.commit_text.is_empty();
        *ascii_leak |= last
            .commit_text
            .chars()
            .any(|value| value.is_ascii_alphabetic());
        *state_loss |= last.raw_input != prefix || last.composition_finished;
    }
    last
}

fn select_context_candidate(
    engine: &mut ImeEngine,
    mut state: CompositionResult,
    expected: &str,
) -> Result<(bool, String), String> {
    let mut details = Vec::new();
    loop {
        details.extend(state.candidates.iter().map(candidate_fingerprint));
        if let Some(index) = state
            .candidates
            .iter()
            .position(|candidate| candidate.text == expected)
        {
            let selected = engine
                .select_candidate(index)
                .map_err(|error| format!("context selection failed: {error:?}"))?;
            let valid = selected.commit_text == expected && selected.composition_finished;
            return Ok((valid, details.join("\u{1f}")));
        }
        if !state.has_next_page {
            return Ok((false, details.join("\u{1f}")));
        }
        state = engine
            .next_candidate_page()
            .map_err(|error| format!("context paging failed: {error:?}"))?;
    }
}

fn collect_candidates(
    engine: &mut ImeEngine,
    mut state: CompositionResult,
) -> Result<(Vec<String>, Vec<String>), String> {
    let mut candidates = Vec::new();
    let mut details = Vec::new();
    loop {
        candidates.extend(
            state
                .candidates
                .iter()
                .map(|candidate| candidate.text.clone()),
        );
        details.extend(state.candidates.iter().map(candidate_fingerprint));
        if !state.has_next_page {
            break;
        }
        state = engine
            .next_candidate_page()
            .map_err(|error| format!("target paging failed: {error:?}"))?;
    }
    Ok((candidates, details))
}

fn candidate_fingerprint(candidate: &FormalCandidate) -> String {
    format!(
        "{}\u{1e}{}\u{1e}{}\u{1e}{}\u{1e}{}",
        candidate.id,
        candidate.text,
        candidate.reading,
        candidate.source,
        candidate.consumed_raw_len
    )
}

fn metrics(outcomes: &[Outcome]) -> Metrics {
    let mut output = Metrics::default();
    for outcome in outcomes {
        output.count += 1;
        output.no_candidates += usize::from(outcome.no_candidates);
        match outcome.rank {
            Some(rank) => {
                output.top1 += usize::from(rank <= 1);
                output.top3 += usize::from(rank <= 3);
                output.top5 += usize::from(rank <= 5);
                output.recalled_outside_top5 += usize::from(rank > 5);
                output.ranking_errors += usize::from((2..=5).contains(&rank));
                output.reciprocal_rank += 1.0 / rank as f64;
                output.recalled_rank_sum += rank;
                output.recalled_count += 1;
                output.extra_selection_sum += rank.saturating_sub(1);
            }
            None => output.unrecalled += 1,
        }
    }
    output
}

fn metrics_json(value: &Metrics) -> JsonValue {
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
            "averageFirstCandidateRankWhenRecalled",
            nullable_average(value.recalled_rank_sum, value.recalled_count),
        ),
        (
            "averageExtraSelectionsWhenRecalled",
            nullable_average(value.extra_selection_sum, value.recalled_count),
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
    ])
}

fn grouped_json(outcomes: &[Outcome]) -> JsonValue {
    let mut categories = BTreeMap::<String, Vec<Outcome>>::new();
    let mut hit = BTreeMap::<String, Vec<Outcome>>::new();
    for outcome in outcomes {
        categories
            .entry(outcome.case.category.clone())
            .or_default()
            .push(outcome.clone());
        hit.entry(
            if outcome.rerank.candidates_with_ngram_hit > 0 {
                "ngram_hit"
            } else {
                "no_ngram_hit"
            }
            .to_owned(),
        )
        .or_default()
        .push(outcome.clone());
    }
    JsonValue::object([
        ("byCategory", outcome_map(categories)),
        ("byActualNgramHit", outcome_map(hit)),
    ])
}

fn outcome_map(values: BTreeMap<String, Vec<Outcome>>) -> JsonValue {
    JsonValue::Object(
        values
            .into_iter()
            .map(|(key, outcomes)| (key, metrics_json(&metrics(&outcomes))))
            .collect(),
    )
}

fn ngram_json(outcomes: &[Outcome]) -> JsonValue {
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
    let max_u64 = |select: fn(&RerankStats) -> u64| {
        outcomes
            .iter()
            .map(|outcome| select(&outcome.rerank))
            .max()
            .unwrap_or(0)
    };
    let bigram_queries = sum(|stats| stats.bigram_queries);
    let trigram_queries = sum(|stats| stats.trigram_queries);
    JsonValue::object([
        (
            "casesWithHitRate",
            JsonValue::number(rate(
                outcomes
                    .iter()
                    .filter(|outcome| outcome.rerank.candidates_with_ngram_hit > 0)
                    .count(),
                outcomes.len(),
            )),
        ),
        ("bigramQueries", JsonValue::number(bigram_queries as f64)),
        (
            "bigramHits",
            JsonValue::number(sum(|stats| stats.bigram_hits) as f64),
        ),
        (
            "bigramHitRate",
            JsonValue::number(rate(sum(|stats| stats.bigram_hits), bigram_queries)),
        ),
        ("trigramQueries", JsonValue::number(trigram_queries as f64)),
        (
            "trigramHits",
            JsonValue::number(sum(|stats| stats.trigram_hits) as f64),
        ),
        (
            "trigramHitRate",
            JsonValue::number(rate(sum(|stats| stats.trigram_hits), trigram_queries)),
        ),
        (
            "trigramBackoffs",
            JsonValue::number(sum(|stats| stats.trigram_backoffs) as f64),
        ),
        (
            "trigramBackoffRate",
            JsonValue::number(rate(sum(|stats| stats.trigram_backoffs), trigram_queries)),
        ),
        (
            "maxCandidatePool",
            JsonValue::number(max(|stats| stats.candidate_pool_size) as f64),
        ),
        (
            "maxCandidatesScored",
            JsonValue::number(max(|stats| stats.candidates_scored) as f64),
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
            JsonValue::number(max_u64(|stats| stats.rerank_micros) as f64),
        ),
        (
            "timeoutFallbacks",
            JsonValue::number(sum(|stats| stats.timeout_fallbacks) as f64),
        ),
        (
            "skippedRerankCalls",
            JsonValue::number(sum(|stats| stats.skipped_rerank_calls) as f64),
        ),
        (
            "queryCacheCapacity",
            JsonValue::number(
                outcomes
                    .iter()
                    .map(|outcome| outcome.rerank.query_cache_capacity)
                    .max()
                    .unwrap_or(0) as f64,
            ),
        ),
    ])
}

fn hard_limits_json() -> JsonValue {
    JsonValue::object([
        (
            "candidatePool",
            JsonValue::number(MAX_CANDIDATE_POOL as f64),
        ),
        (
            "bigramQueriesPerKey",
            JsonValue::number(MAX_BIGRAM_QUERIES as f64),
        ),
        (
            "trigramQueriesPerKey",
            JsonValue::number(MAX_TRIGRAM_QUERIES as f64),
        ),
        (
            "modelFileBytes",
            JsonValue::number(MAX_MODEL_FILE_BYTES as f64),
        ),
        (
            "modelMemoryBytes",
            JsonValue::number(MAX_MODEL_MEMORY_BYTES as f64),
        ),
        (
            "modelLoadMicros",
            JsonValue::number(MAX_MODEL_LOAD_MICROS as f64),
        ),
        (
            "rerankMicrosPerKey",
            JsonValue::number(MAX_RERANK_MICROS as f64),
        ),
    ])
}

fn safety(outcomes: &[Outcome]) -> Safety {
    Safety {
        automatic_commits: outcomes
            .iter()
            .filter(|outcome| outcome.automatic_commit)
            .count(),
        ascii_leaks: outcomes.iter().filter(|outcome| outcome.ascii_leak).count(),
        state_losses: outcomes.iter().filter(|outcome| outcome.state_loss).count(),
        engine_errors: outcomes
            .iter()
            .filter(|outcome| outcome.engine_error)
            .count(),
        context_setup_failures: outcomes
            .iter()
            .filter(|outcome| outcome.context_setup_failed)
            .count(),
    }
}

fn add_safety(total: &mut Safety, value: &Safety) {
    total.automatic_commits += value.automatic_commits;
    total.ascii_leaks += value.ascii_leaks;
    total.state_losses += value.state_losses;
    total.engine_errors += value.engine_errors;
    total.context_setup_failures += value.context_setup_failures;
}

fn safety_json(value: &Safety) -> JsonValue {
    JsonValue::object([
        (
            "nonExplicitAutomaticCommitCount",
            JsonValue::number(value.automatic_commits as f64),
        ),
        (
            "asciiLeakCount",
            JsonValue::number(value.ascii_leaks as f64),
        ),
        (
            "rawInputStateLossCount",
            JsonValue::number(value.state_losses as f64),
        ),
        (
            "engineErrorCount",
            JsonValue::number(value.engine_errors as f64),
        ),
        (
            "contextSetupFailureCount",
            JsonValue::number(value.context_setup_failures as f64),
        ),
    ])
}

fn run_json(run: usize, outcomes: &[Outcome], latencies: &[u64]) -> JsonValue {
    JsonValue::object([
        ("run", JsonValue::number(run as f64)),
        ("metrics", metrics_json(&metrics(outcomes))),
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
    let percentile = |percent: usize| sorted[((sorted.len() - 1) * percent).div_ceil(100)];
    JsonValue::object([
        ("samples", JsonValue::number(sorted.len() as f64)),
        ("p50", JsonValue::number(percentile(50) as f64)),
        ("p95", JsonValue::number(percentile(95) as f64)),
        ("p99", JsonValue::number(percentile(99) as f64)),
        (
            "mean",
            JsonValue::number(
                sorted.iter().map(|value| *value as f64).sum::<f64>() / sorted.len() as f64,
            ),
        ),
        (
            "max",
            JsonValue::number(*sorted.last().expect("nonempty") as f64),
        ),
    ])
}

fn load_cases(bytes: &[u8]) -> Result<Vec<ContextCase>, String> {
    let text = std::str::from_utf8(bytes).map_err(|_| "dataset is not UTF-8".to_owned())?;
    text.lines()
        .enumerate()
        .filter(|(_, line)| !line.trim().is_empty())
        .map(|(index, line)| parse_case(line.as_bytes(), index + 1))
        .collect()
}

fn parse_case(bytes: &[u8], line: usize) -> Result<ContextCase, String> {
    let value = parse(bytes).map_err(|error| format!("line {line}: {error}"))?;
    let object = value
        .as_object()
        .ok_or_else(|| format!("line {line}: expected object"))?;
    let string = |name: &str| {
        object
            .get(name)
            .and_then(JsonValue::as_str)
            .map(str::to_owned)
            .ok_or_else(|| format!("line {line}: missing string {name}"))
    };
    let strings = |name: &str| -> Result<Vec<String>, String> {
        object
            .get(name)
            .and_then(JsonValue::as_array)
            .ok_or_else(|| format!("line {line}: missing array {name}"))?
            .iter()
            .map(|value| {
                value
                    .as_str()
                    .map(str::to_owned)
                    .ok_or_else(|| format!("line {line}: non-string in {name}"))
            })
            .collect()
    };
    Ok(ContextCase {
        id: string("id")?,
        category: string("category")?,
        raw_input: string("rawInput")?,
        expected_text: string("expectedText")?,
        context_raw_inputs: strings("contextRawInputs")?,
        context_expected_texts: strings("contextExpectedTexts")?,
        source: string("source")?,
    })
}

fn validate_cases(cases: &[ContextCase]) -> Result<(), String> {
    if cases.len() < 40 {
        return Err(format!("dataset has {}; minimum is 40", cases.len()));
    }
    let mut ids = BTreeSet::new();
    for case in cases {
        if !ids.insert(case.id.clone()) {
            return Err(format!("duplicate id {}", case.id));
        }
        if !REQUIRED_CATEGORIES.contains(&case.category.as_str()) {
            return Err(format!("{} has invalid category", case.id));
        }
        if case.context_raw_inputs.len() != case.context_expected_texts.len()
            || case.context_raw_inputs.len() > 2
        {
            return Err(format!("{} has invalid context pair count", case.id));
        }
        if !valid_raw(&case.raw_input) || case.context_raw_inputs.iter().any(|raw| !valid_raw(raw))
        {
            return Err(format!("{} has invalid pinyin input", case.id));
        }
        if case.expected_text.trim().is_empty()
            || case
                .context_expected_texts
                .iter()
                .any(|value| value.trim().is_empty())
            || case.source.trim().is_empty()
        {
            return Err(format!("{} has blank required value", case.id));
        }
    }
    let counts = category_counts(cases);
    for category in REQUIRED_CATEGORIES {
        if counts.get(category).copied().unwrap_or(0) < 8 {
            return Err(format!("category {category} requires at least 8 cases"));
        }
    }
    Ok(())
}

fn valid_raw(raw: &str) -> bool {
    !raw.is_empty()
        && raw
            .chars()
            .all(|value| value.is_ascii_lowercase() || value == '\'')
}

fn category_counts(cases: &[ContextCase]) -> BTreeMap<String, usize> {
    let mut output = BTreeMap::new();
    for case in cases {
        *output.entry(case.category.clone()).or_default() += 1;
    }
    output
}

fn count_map_json(values: BTreeMap<String, usize>) -> JsonValue {
    JsonValue::Object(
        values
            .into_iter()
            .map(|(key, value)| (key, JsonValue::number(value as f64)))
            .collect(),
    )
}

fn verify_manifest(manifest_path: &Path, dataset: &[u8], cases: usize) -> Result<(), String> {
    let bytes = fs::read(manifest_path).map_err(|error| error.to_string())?;
    let value = parse(&bytes)?;
    let object = value
        .as_object()
        .ok_or_else(|| "manifest must be object".to_owned())?;
    let expected_hash = object
        .get("sha256")
        .and_then(JsonValue::as_str)
        .unwrap_or("");
    let expected_bytes = object
        .get("bytes")
        .and_then(JsonValue::as_u64)
        .unwrap_or(u64::MAX);
    let expected_cases = object
        .get("sampleCount")
        .and_then(JsonValue::as_u64)
        .unwrap_or(u64::MAX);
    if expected_hash != eval_sha256::hex(dataset)
        || expected_bytes != dataset.len() as u64
        || expected_cases != cases as u64
    {
        return Err("FROZEN_CONTEXT_DATASET_HASH_MISMATCH".to_owned());
    }
    Ok(())
}

fn write_failures(path: &Path, outcomes: &[Outcome]) -> Result<(), String> {
    let mut bytes = Vec::new();
    for outcome in outcomes.iter().filter(|outcome| outcome.rank != Some(1)) {
        let failure_type = if outcome.engine_error {
            "engine_error"
        } else if outcome.state_loss {
            "state_loss"
        } else if outcome.automatic_commit {
            "automatic_commit"
        } else if outcome.context_setup_failed {
            "context_setup_failed"
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
            ("category", JsonValue::string(&outcome.case.category)),
            ("rawInput", JsonValue::string(&outcome.case.raw_input)),
            (
                "expectedText",
                JsonValue::string(&outcome.case.expected_text),
            ),
            (
                "targetRank",
                outcome
                    .rank
                    .map_or(JsonValue::Null, |rank| JsonValue::number(rank as f64)),
            ),
            ("failureType", JsonValue::string(failure_type)),
            (
                "topFiveCandidates",
                JsonValue::array(outcome.candidates.iter().take(5).map(JsonValue::string)),
            ),
            (
                "actualNgramHit",
                JsonValue::Bool(outcome.rerank.candidates_with_ngram_hit > 0),
            ),
            (
                "contextSetupFailed",
                JsonValue::Bool(outcome.context_setup_failed),
            ),
        ])));
    }
    write_file(path, &bytes)
}

fn write_file(path: &Path, bytes: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(path, bytes).map_err(|error| error.to_string())
}

fn nullable_average(sum: usize, count: usize) -> JsonValue {
    if count == 0 {
        JsonValue::Null
    } else {
        JsonValue::number(sum as f64 / count as f64)
    }
}

fn rate(value: usize, count: usize) -> f64 {
    value as f64 / count.max(1) as f64
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
        ("cargoProfile", JsonValue::string("release")),
    ])
}
