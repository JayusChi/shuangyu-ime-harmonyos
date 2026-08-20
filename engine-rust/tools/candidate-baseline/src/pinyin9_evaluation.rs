use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::Instant;

use engine_protocol::{FormalCandidate, ProtocolParserState};
use ime_engine::{EngineConfig, ImeEngine, T9JointDecoderStats};
use shuangpin_parser::{t9_signature, T9_MAX_PINYIN_COMBINATIONS, T9_MAX_RAW_DIGITS};

use crate::eval_json::{parse, serialize, serialize_line, JsonValue};
use crate::eval_sha256;

const DATASET_FILES: [&str; 5] = [
    "DATASET_PROVENANCE.md",
    "blind.jsonl",
    "dev.jsonl",
    "public-regression.jsonl",
    "sources.json",
];
const SPECIALIZED_CATEGORIES: [&str; 20] = [
    "common_character_word",
    "common_phrase_2_4",
    "modern_chat",
    "long_continuous",
    "segmentation_ambiguity",
    "person_name",
    "place_name",
    "organization_name",
    "brand_domain",
    "polyphone_homophone",
    "high_digit_collision",
    "multiple_pinyin_paths",
    "abbreviation",
    "incomplete_tail",
    "explicit_boundary",
    "missing_digit",
    "extra_digit",
    "adjacent_key",
    "transposition",
    "fuzzy_dialect",
];
const INPUT_KINDS: [&str; 9] = [
    "clean",
    "explicit_boundary",
    "abbreviated",
    "incomplete_tail",
    "missing_digit",
    "extra_digit",
    "adjacent_key",
    "transposition",
    "fuzzy_dialect",
];
const IMPLEMENTATION_FILES: [&str; 28] = [
    "engine-rust/Cargo.lock",
    "engine-rust/crates/engine-protocol/src/composition.rs",
    "engine-rust/crates/ime-engine/Cargo.toml",
    "engine-rust/crates/ime-engine/src/candidate_session.rs",
    "engine-rust/crates/ime-engine/src/formal.rs",
    "engine-rust/crates/ime-engine/src/lib.rs",
    "engine-rust/crates/ime-engine/src/t9_joint.rs",
    "engine-rust/crates/ime-engine/tests/t9_stage3.rs",
    "engine-rust/crates/sentence-decoder/src/context.rs",
    "engine-rust/crates/sentence-decoder/src/decoder.rs",
    "engine-rust/crates/sentence-decoder/src/graph.rs",
    "engine-rust/crates/sentence-decoder/src/lib.rs",
    "engine-rust/crates/sentence-decoder/src/limits.rs",
    "engine-rust/crates/sentence-decoder/src/path.rs",
    "engine-rust/crates/sentence-decoder/src/scorer.rs",
    "engine-rust/crates/sentence-decoder/src/t9_joint.rs",
    "engine-rust/crates/shuangpin-parser/src/lib.rs",
    "engine-rust/crates/shuangpin-parser/src/phonetic.rs",
    "engine-rust/crates/shuangpin-parser/src/t9.rs",
    "engine-rust/tools/candidate-baseline/Cargo.toml",
    "engine-rust/tools/candidate-baseline/src/eval_json.rs",
    "engine-rust/tools/candidate-baseline/src/eval_sha256.rs",
    "engine-rust/tools/candidate-baseline/src/lib.rs",
    "engine-rust/tools/candidate-baseline/src/main.rs",
    "engine-rust/tools/candidate-baseline/src/pinyin9_dataset.rs",
    "engine-rust/tools/candidate-baseline/src/pinyin9_evaluation.rs",
    "scripts/evaluate-pinyin9-quality.ps1",
    "scripts/evaluate-pinyin9-joint-decoder.ps1",
];

#[derive(Clone, Debug)]
struct DatasetCase {
    id: String,
    split: String,
    category: String,
    input_kind: String,
    raw_digits: String,
    canonical_pinyin: String,
    expected_texts: Vec<String>,
    boundaries: Vec<usize>,
    source_id: String,
    source_sample_ids: Vec<String>,
    notes: String,
    layer: String,
}

#[derive(Clone, Debug)]
struct CaseOutcome {
    case: DatasetCase,
    target_rank: Option<usize>,
    canonical_path_rank: Option<usize>,
    pinyin_paths: Vec<String>,
    candidates: Vec<FormalCandidate>,
    pinyin_path_count: usize,
    candidate_count: usize,
    key_latencies: Vec<u64>,
    sample_total_micros: u64,
    automatic_commit: bool,
    ascii_leak: bool,
    input_limit_hit: bool,
    state_loss: bool,
    engine_error: bool,
    joint_stats: T9JointDecoderStats,
    canonical_entered_internal_search: bool,
    canonical_elimination_stage: String,
    fingerprint: String,
}

#[derive(Clone, Copy, Debug, Default)]
struct Safety {
    automatic_commits: usize,
    ascii_leaks: usize,
    input_limit_hits: usize,
    state_losses: usize,
    engine_errors: usize,
}

#[derive(Clone, Debug)]
struct DatasetFile {
    path: String,
    bytes: usize,
    sha256: String,
    sample_count: usize,
}

pub fn validate_pinyin9_dataset(dataset_dir: &Path) -> Result<String, String> {
    let cases = load_cases(dataset_dir)?;
    let sources = load_source_ids(dataset_dir)?;
    validate_cases(&cases, &sources)?;
    Ok(
        String::from_utf8(serialize(&validation_json(&cases)))
            .expect("JSON serializer emits UTF-8"),
    )
}

pub fn freeze_pinyin9_dataset(
    dataset_dir: &Path,
    manifest_path: &Path,
    baseline_id: &str,
    frozen_at: &str,
) -> Result<String, String> {
    if manifest_path.exists() {
        return Err(format!(
            "freeze manifest already exists: {}; refusing to overwrite it",
            manifest_path.display()
        ));
    }
    if baseline_id.trim().is_empty() || frozen_at.trim().is_empty() {
        return Err("baseline ID and frozen time must be explicit".to_owned());
    }
    let cases = load_cases(dataset_dir)?;
    let sources = load_source_ids(dataset_dir)?;
    validate_cases(&cases, &sources)?;
    let files = dataset_files(dataset_dir)?;
    let identity_material = files
        .iter()
        .map(|file| format!("{}\0{}\0{}\n", file.path, file.bytes, file.sha256))
        .collect::<String>();
    let identity = eval_sha256::hex(identity_material.as_bytes());
    let manifest = JsonValue::object([
        ("schemaVersion", JsonValue::string("pinyin9-evaluation-freeze/1")),
        ("baselineId", JsonValue::string(baseline_id)),
        ("baselineIdentitySha256", JsonValue::string(&identity)),
        ("frozenAt", JsonValue::string(frozen_at)),
        ("gitIdentityUsed", JsonValue::Bool(false)),
        ("sampleCount", JsonValue::number(cases.len() as f64)),
        ("splitDistribution", count_json(count_by(&cases, |case| &case.split))),
        (
            "categoryDistribution",
            count_json(count_by(&cases, |case| &case.category)),
        ),
        (
            "inputKindDistribution",
            count_json(count_by(&cases, |case| &case.input_kind)),
        ),
        (
            "files",
            JsonValue::array(files.iter().map(|file| {
                JsonValue::object([
                    ("path", JsonValue::string(&file.path)),
                    ("bytes", JsonValue::number(file.bytes as f64)),
                    ("sha256", JsonValue::string(&file.sha256)),
                    ("sampleCount", JsonValue::number(file.sample_count as f64)),
                ])
            })),
        ),
        (
            "mutationPolicy",
            JsonValue::string("Any byte change is a hard error. The blind partition may be evaluated by exactly one command, internally repeated three times, only after the implementation manifest is frozen."),
        ),
    ]);
    write_new_file(manifest_path, &serialize(&manifest))?;
    Ok(format!(
        "frozen pinyin9 baseline {baseline_id}: {} cases, identity {identity}",
        cases.len()
    ))
}

pub fn freeze_pinyin9_implementation(
    repo_root: &Path,
    dataset_manifest_path: &Path,
    lexicon_path: &Path,
    output_path: &Path,
    frozen_at: &str,
) -> Result<String, String> {
    if output_path.exists() {
        return Err(format!(
            "implementation manifest already exists: {}; refusing to overwrite it",
            output_path.display()
        ));
    }
    if frozen_at.trim().is_empty() {
        return Err("implementation frozen time must be explicit".to_owned());
    }
    let dataset_dir = dataset_manifest_path
        .parent()
        .ok_or_else(|| "dataset manifest has no parent".to_owned())?
        .join("dataset");
    verify_dataset_manifest(&dataset_dir, dataset_manifest_path)?;
    let dataset_manifest = fs::read(dataset_manifest_path).map_err(|error| error.to_string())?;
    let lexicon = fs::read(lexicon_path).map_err(|error| {
        format!(
            "cannot read production lexicon {}: {error}",
            lexicon_path.display()
        )
    })?;
    let mut files = Vec::new();
    for relative in IMPLEMENTATION_FILES {
        let path = repo_root.join(relative);
        let bytes =
            fs::read(&path).map_err(|error| format!("implementation file {relative}: {error}"))?;
        files.push(JsonValue::object([
            ("path", JsonValue::string(relative)),
            ("bytes", JsonValue::number(bytes.len() as f64)),
            ("sha256", JsonValue::string(eval_sha256::hex(&bytes))),
        ]));
    }
    let manifest = JsonValue::object([
        (
            "schemaVersion",
            JsonValue::string("pinyin9-joint-decoder-implementation/2"),
        ),
        ("frozenAt", JsonValue::string(frozen_at)),
        ("gitIdentityUsed", JsonValue::Bool(false)),
        (
            "datasetManifestSha256",
            JsonValue::string(eval_sha256::hex(&dataset_manifest)),
        ),
        (
            "productionLexiconSha256",
            JsonValue::string(eval_sha256::hex(&lexicon)),
        ),
        (
            "productionLexiconBytes",
            JsonValue::number(lexicon.len() as f64),
        ),
        ("schemeId", JsonValue::string("pinyin-9")),
        ("userLearningEnabled", JsonValue::Bool(false)),
        (
            "hardLimits",
            JsonValue::object([
                ("maximumPublicPinyinPaths", JsonValue::number(32.0)),
                ("maximumParserPathsPerOffset", JsonValue::number(64.0)),
                ("maximumInternalPinyinHypotheses", JsonValue::number(128.0)),
                ("jointBeamWidth", JsonValue::number(16.0)),
                ("maximumStatesPerDigitPosition", JsonValue::number(16.0)),
                ("maximumLexiconEntriesPerReading", JsonValue::number(16.0)),
                (
                    "maximumDirectEntriesPerReading",
                    JsonValue::number(64.0),
                ),
                ("maximumDirectPaths", JsonValue::number(256.0)),
                ("maximumLexiconEdgesPerDigitPosition", JsonValue::number(64.0)),
                ("maximumGraphEdges", JsonValue::number(1024.0)),
                ("maximumSentenceWords", JsonValue::number(32.0)),
                ("maximumCandidateSnapshot", JsonValue::number(256.0)),
                ("maximumDiagnosticPaths", JsonValue::number(512.0)),
                ("maximumJointPublicPromotions", JsonValue::number(4.0)),
                (
                    "maximumCompatibilityDecodePaths",
                    JsonValue::number(32.0),
                ),
                (
                    "maximumCompatibilityDecodeDigits",
                    JsonValue::number(32.0),
                ),
            ]),
        ),
        ("files", JsonValue::array(files)),
        (
            "checklist",
            JsonValue::object([
                ("datasetValidated", JsonValue::Bool(true)),
                ("datasetFrozen", JsonValue::Bool(true)),
                ("evaluatorFrozen", JsonValue::Bool(true)),
                ("engineAndParserFrozen", JsonValue::Bool(true)),
                ("productionLexiconFrozen", JsonValue::Bool(true)),
            ]),
        ),
        (
            "mutationPolicy",
            JsonValue::string("The blind receipt can be created once. Any implementation, configuration, lexicon, or dataset byte change requires a new baseline identity."),
        ),
    ]);
    write_new_file(output_path, &serialize(&manifest))?;
    Ok(format!(
        "frozen pinyin9 implementation: {} files, lexicon {} bytes",
        IMPLEMENTATION_FILES.len(),
        lexicon.len()
    ))
}

pub struct Pinyin9EvaluationRequest<'a> {
    pub dataset_dir: &'a Path,
    pub manifest_path: &'a Path,
    pub implementation_manifest_path: Option<&'a Path>,
    pub repo_root: Option<&'a Path>,
    pub lexicon_path: &'a Path,
    pub results_path: &'a Path,
    pub failures_path: &'a Path,
    pub receipt_path: Option<&'a Path>,
    pub runs: usize,
    pub split: &'a str,
}

pub fn evaluate_pinyin9_dataset(request: &Pinyin9EvaluationRequest<'_>) -> Result<String, String> {
    if cfg!(debug_assertions) {
        return Err("pinyin9 evaluation must run in Cargo release mode".to_owned());
    }
    if request.runs < 3 {
        return Err("at least three deterministic repetitions are required".to_owned());
    }
    if !matches!(request.split, "dev" | "blind" | "public-regression") {
        return Err(format!("invalid pinyin9 split {:?}", request.split));
    }
    validate_blind_guard(request)?;
    verify_dataset_manifest(request.dataset_dir, request.manifest_path)?;
    let all_cases = load_cases(request.dataset_dir)?;
    let sources = load_source_ids(request.dataset_dir)?;
    validate_cases(&all_cases, &sources)?;
    let cases = all_cases
        .into_iter()
        .filter(|case| case.split == request.split)
        .collect::<Vec<_>>();
    if cases.is_empty() {
        return Err(format!("split {} has no cases", request.split));
    }
    let implementation_hash = match (request.implementation_manifest_path, request.repo_root) {
        (Some(path), Some(root)) => Some(verify_implementation_manifest(
            root,
            request.manifest_path,
            request.lexicon_path,
            path,
        )?),
        (None, None) if request.split != "blind" => None,
        _ => {
            return Err(
                "implementation manifest and repository root must be supplied together".to_owned(),
            )
        }
    };
    let lexicon = fs::read(request.lexicon_path).map_err(|error| {
        format!(
            "cannot read production lexicon {}: {error}",
            request.lexicon_path.display()
        )
    })?;
    let lexicon_hash = eval_sha256::hex(&lexicon);
    let dataset_manifest = fs::read(request.manifest_path).map_err(|error| error.to_string())?;
    let dataset_manifest_hash = eval_sha256::hex(&dataset_manifest);

    let mut run_json_values = Vec::new();
    let mut first_sample_count = 0usize;
    let mut first_metrics = None;
    let mut first_groups = None;
    let mut first_diagnostics = None;
    let mut first_failure_bytes = None;
    let mut first_counters = None;
    let mut reference_fingerprints: Option<Vec<String>> = None;
    let mut deterministic = true;
    let mut aggregate_safety = Safety::default();
    let mut engine_version = String::new();
    let mut engine_load_latencies = Vec::new();

    for run_index in 0..request.runs {
        let load_started = Instant::now();
        let mut engine = ImeEngine::new(EngineConfig {
            scheme_id: "pinyin-9".to_owned(),
            lexicon_path: Some(request.lexicon_path.to_string_lossy().into_owned()),
            user_lexicon_path: None,
            candidate_page_size: 9,
            ..EngineConfig::default()
        })
        .map_err(|error| format!("pinyin9 engine creation failed: {error}"))?;
        engine_load_latencies.push(load_started.elapsed().as_micros() as u64);
        engine.set_user_learning_enabled(false);
        engine.set_session_learning_allowed(false);
        engine_version = engine.version().to_owned();
        let mut outcomes = Vec::with_capacity(cases.len());
        for case in &cases {
            let mut outcome = run_case(&mut engine, case);
            if run_index > 0 {
                outcome.pinyin_paths.clear();
                outcome.candidates.clear();
            }
            outcomes.push(outcome);
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
        let safety = safety(&outcomes);
        eprintln!(
            "pinyin9 {} run {}/{} complete ({} samples)",
            request.split,
            run_index + 1,
            request.runs,
            outcomes.len()
        );
        aggregate_safety.automatic_commits += safety.automatic_commits;
        aggregate_safety.ascii_leaks += safety.ascii_leaks;
        aggregate_safety.input_limit_hits += safety.input_limit_hits;
        aggregate_safety.state_losses += safety.state_losses;
        aggregate_safety.engine_errors += safety.engine_errors;
        run_json_values.push(run_json(run_index + 1, &outcomes));
        if run_index == 0 {
            first_sample_count = outcomes.len();
            first_metrics = Some(metrics_json(&outcomes));
            first_groups = Some(grouped_metrics(&outcomes));
            first_diagnostics = Some(JsonValue::array(
                outcomes.iter().map(sample_diagnostics_json),
            ));
            first_failure_bytes = Some(failures_bytes(&outcomes));
            first_counters = Some(counters(&outcomes));
        }
    }

    let first_metrics = first_metrics.ok_or_else(|| "missing first-run metrics".to_owned())?;
    let first_groups = first_groups.ok_or_else(|| "missing first-run groups".to_owned())?;
    let first_diagnostics =
        first_diagnostics.ok_or_else(|| "missing first-run diagnostics".to_owned())?;
    let first_failure_bytes =
        first_failure_bytes.ok_or_else(|| "missing first-run failures".to_owned())?;
    let first_counters = first_counters.ok_or_else(|| "missing first-run counters".to_owned())?;

    let candidate_hashes = run_json_values
        .iter()
        .filter_map(|run| {
            run.as_object()
                .and_then(|object| object.get("candidateOutputSha256"))
                .and_then(JsonValue::as_str)
                .map(str::to_owned)
        })
        .collect::<Vec<_>>();
    let report = JsonValue::object([
        (
            "schemaVersion",
            JsonValue::string("pinyin9-joint-decoder-results/2"),
        ),
        (
            "measurementKind",
            JsonValue::string("Windows-host-release-formal-ImeEngine-per-key"),
        ),
        (
            "datasetManifestSha256",
            JsonValue::string(&dataset_manifest_hash),
        ),
        (
            "implementationManifestSha256",
            implementation_hash
                .as_ref()
                .map(JsonValue::string)
                .unwrap_or(JsonValue::Null),
        ),
        ("productionLexiconSha256", JsonValue::string(&lexicon_hash)),
        (
            "productionLexiconBytes",
            JsonValue::number(lexicon.len() as f64),
        ),
        ("engineVersion", JsonValue::string(&engine_version)),
        ("schemeId", JsonValue::string("pinyin-9")),
        ("split", JsonValue::string(request.split)),
        ("runCount", JsonValue::number(request.runs as f64)),
        ("sampleCount", JsonValue::number(first_sample_count as f64)),
        (
            "deterministicCandidateOutputs",
            JsonValue::Bool(deterministic),
        ),
        (
            "candidateOutputSha256ByRun",
            JsonValue::array(candidate_hashes.iter().map(JsonValue::string)),
        ),
        ("metrics", first_metrics),
        ("groups", first_groups),
        ("sampleDiagnostics", first_diagnostics),
        (
            "engineLoadLatencyMicros",
            latency_json(&engine_load_latencies),
        ),
        ("runs", JsonValue::array(run_json_values)),
        ("safetyContract", safety_json(aggregate_safety)),
        ("environment", environment_json()),
        (
            "interpretation",
            JsonValue::object([
                ("lowScoresCauseProcessFailure", JsonValue::Bool(false)),
                ("safetyCountersCauseProcessFailure", JsonValue::Bool(false)),
                ("qualityPassThresholdDefined", JsonValue::Bool(false)),
                ("hostDataOnly", JsonValue::Bool(true)),
                ("harmonyOsDeviceDataIncluded", JsonValue::Bool(false)),
                ("commercialImeComparisonIncluded", JsonValue::Bool(false)),
            ]),
        ),
    ]);
    write_file(request.results_path, &serialize(&report))?;
    write_file(request.failures_path, &first_failure_bytes)?;

    if let Some(receipt_path) = request.receipt_path {
        let results = fs::read(request.results_path).map_err(|error| error.to_string())?;
        let failures = fs::read(request.failures_path).map_err(|error| error.to_string())?;
        let receipt = JsonValue::object([
            (
                "schemaVersion",
                JsonValue::string("pinyin9-blind-run-receipt/1"),
            ),
            ("split", JsonValue::string(request.split)),
            ("runCount", JsonValue::number(request.runs as f64)),
            ("datasetManifestSha256", JsonValue::string(&dataset_manifest_hash)),
            (
                "implementationManifestSha256",
                implementation_hash
                    .as_ref()
                    .map(JsonValue::string)
                    .unwrap_or(JsonValue::Null),
            ),
            ("productionLexiconSha256", JsonValue::string(&lexicon_hash)),
            ("resultsSha256", JsonValue::string(eval_sha256::hex(&results))),
            ("failuresSha256", JsonValue::string(eval_sha256::hex(&failures))),
            ("deterministic", JsonValue::Bool(deterministic)),
            ("safetyContract", safety_json(aggregate_safety)),
            (
                "candidateOutputSha256ByRun",
                JsonValue::array(candidate_hashes.iter().map(JsonValue::string)),
            ),
            (
                "mutationPolicy",
                JsonValue::string("This receipt is single-use evidence. It must never be overwritten or regenerated for this frozen baseline."),
            ),
        ]);
        write_new_file(receipt_path, &serialize(&receipt))?;
    }

    if !deterministic {
        return Err(format!(
            "candidate output determinism failure after writing evidence: autoCommit={}, asciiLeak={}, inputLimit={}, stateLoss={}, engineError={}",
            aggregate_safety.automatic_commits,
            aggregate_safety.ascii_leaks,
            aggregate_safety.input_limit_hits,
            aggregate_safety.state_losses,
            aggregate_safety.engine_errors
        ));
    }
    Ok(format!(
        "evaluated {} pinyin9 {} cases x {} runs; Top1 {:.3}%, Top3 {:.3}%, Top5 {:.3}%",
        first_sample_count,
        request.split,
        request.runs,
        rate(first_counters.top1, first_counters.count) * 100.0,
        rate(first_counters.top3, first_counters.count) * 100.0,
        rate(first_counters.top5, first_counters.count) * 100.0
    ))
}

fn validate_blind_guard(request: &Pinyin9EvaluationRequest<'_>) -> Result<(), String> {
    if request.split != "blind" {
        if request.receipt_path.is_some() {
            return Err("a blind receipt may only be requested for split=blind".to_owned());
        }
        return Ok(());
    }
    if request.runs != 3 {
        return Err("blind evaluation requires exactly three internal runs".to_owned());
    }
    if request.implementation_manifest_path.is_none() || request.repo_root.is_none() {
        return Err("blind evaluation requires the frozen implementation manifest".to_owned());
    }
    let receipt = request
        .receipt_path
        .ok_or_else(|| "blind evaluation requires a receipt path".to_owned())?;
    for path in [receipt, request.results_path, request.failures_path] {
        if path.exists() {
            return Err(format!(
                "BLIND_RUN_ALREADY_EXISTS: {}; refusing repeated blind generation",
                path.display()
            ));
        }
    }
    Ok(())
}

fn run_case(engine: &mut ImeEngine, case: &DatasetCase) -> CaseOutcome {
    engine.reset();
    let total_started = Instant::now();
    let mut last = engine.current_state();
    let mut key_latencies = Vec::new();
    let mut automatic_commit = false;
    let mut ascii_leak = false;
    let mut input_limit_hit = false;
    let mut state_loss = false;
    let mut engine_error = false;
    let mut joint_stats = T9JointDecoderStats::default();
    let mut prefix = String::new();
    for digit in case.raw_digits.chars() {
        prefix.push(digit);
        let started = Instant::now();
        last = engine.process_key(digit);
        key_latencies.push(started.elapsed().as_nanos().div_ceil(1_000) as u64);
        inspect_state(
            &last,
            &prefix,
            &mut automatic_commit,
            &mut ascii_leak,
            &mut input_limit_hit,
            &mut state_loss,
            &mut engine_error,
        );
        accumulate_joint_stats(&mut joint_stats, engine.last_t9_joint_stats());
        if case.boundaries.contains(&prefix.len()) {
            match engine.insert_segment_boundary() {
                Ok(value) => {
                    last = value;
                    inspect_state(
                        &last,
                        &prefix,
                        &mut automatic_commit,
                        &mut ascii_leak,
                        &mut input_limit_hit,
                        &mut state_loss,
                        &mut engine_error,
                    );
                    accumulate_joint_stats(&mut joint_stats, engine.last_t9_joint_stats());
                }
                Err(_) => engine_error = true,
            }
        }
    }
    let mut pinyin_paths = Vec::new();
    if !last.current_pinyin.is_empty() {
        pinyin_paths.push(last.current_pinyin.clone());
    }
    pinyin_paths.extend(last.pinyin_combinations.iter().cloned());
    let canonical_path_rank = pinyin_paths
        .iter()
        .position(|path| path == &case.canonical_pinyin)
        .map(|index| index + 1);
    let mut candidates = last.candidates.clone();
    while last.has_next_page {
        match engine.next_candidate_page() {
            Ok(value) => {
                last = value;
                candidates.extend(last.candidates.iter().cloned());
            }
            Err(_) => {
                engine_error = true;
                break;
            }
        }
    }
    let target_rank = candidates
        .iter()
        .position(|candidate| case.expected_texts.contains(&candidate.text))
        .map(|index| index + 1);
    input_limit_hit |= joint_stats.input_limit_hit;
    let canonical_entered_internal_search = joint_stats
        .parser_generated_paths
        .contains(&case.canonical_pinyin)
        || joint_stats
            .lexicon_reachable_paths
            .contains(&case.canonical_pinyin)
        || joint_stats
            .ranked_internal_paths
            .contains(&case.canonical_pinyin);
    let canonical_elimination_stage = canonical_elimination_stage(
        case,
        &joint_stats,
        canonical_path_rank,
        target_rank,
        engine_error,
        input_limit_hit,
        state_loss,
    )
    .to_owned();
    // Attribution above is the only consumer of the bounded diagnostic path
    // strings. Retaining four path pools for every outcome makes the 900-case
    // public run hold hundreds of megabytes without adding result evidence.
    joint_stats.parser_generated_paths.clear();
    joint_stats.lexicon_reachable_paths.clear();
    joint_stats.joint_beam_pruned_paths.clear();
    joint_stats.ranked_internal_paths.clear();
    let sample_total_micros = total_started.elapsed().as_nanos().div_ceil(1_000) as u64;
    let pinyin_path_count = pinyin_paths.len();
    let candidate_count = candidates.len();
    let reset = engine.reset();
    state_loss |= !reset.raw_input.is_empty()
        || !reset.candidates.is_empty()
        || !reset.current_pinyin.is_empty()
        || !reset.pinyin_combinations.is_empty();
    let fingerprint = fingerprint(
        case,
        &last,
        &pinyin_paths,
        &candidates,
        (automatic_commit, input_limit_hit, state_loss, engine_error),
    );
    CaseOutcome {
        case: case.clone(),
        target_rank,
        canonical_path_rank,
        pinyin_paths,
        candidates,
        pinyin_path_count,
        candidate_count,
        key_latencies,
        sample_total_micros,
        automatic_commit,
        ascii_leak,
        input_limit_hit,
        state_loss,
        engine_error,
        joint_stats,
        canonical_entered_internal_search,
        canonical_elimination_stage,
        fingerprint,
    }
}

fn accumulate_joint_stats(total: &mut T9JointDecoderStats, current: T9JointDecoderStats) {
    total.explored_pinyin_hypotheses = total
        .explored_pinyin_hypotheses
        .saturating_add(current.explored_pinyin_hypotheses);
    total.max_beam_states = total.max_beam_states.max(current.max_beam_states);
    total.lexicon_prefix_unreachable_prunes = total
        .lexicon_prefix_unreachable_prunes
        .saturating_add(current.lexicon_prefix_unreachable_prunes);
    total.pinyin_invalid_prunes = total
        .pinyin_invalid_prunes
        .saturating_add(current.pinyin_invalid_prunes);
    total.joint_score_prunes = total
        .joint_score_prunes
        .saturating_add(current.joint_score_prunes);
    total.beam_capacity_prunes = total
        .beam_capacity_prunes
        .saturating_add(current.beam_capacity_prunes);
    total.candidate_output_limit_prunes = total
        .candidate_output_limit_prunes
        .saturating_add(current.candidate_output_limit_prunes);
    total.parser_internal_hypotheses = total
        .parser_internal_hypotheses
        .max(current.parser_internal_hypotheses);
    total.graph_edges = total.graph_edges.saturating_add(current.graph_edges);
    total.peak_estimated_bytes = total.peak_estimated_bytes.max(current.peak_estimated_bytes);
    total.input_limit_hit |= current.input_limit_hit;
    total.parser_generated_paths = current.parser_generated_paths;
    total.lexicon_reachable_paths = current.lexicon_reachable_paths;
    total.joint_beam_pruned_paths = current.joint_beam_pruned_paths;
    total.ranked_internal_paths = current.ranked_internal_paths;
}

fn canonical_elimination_stage(
    case: &DatasetCase,
    stats: &T9JointDecoderStats,
    public_rank: Option<usize>,
    target_rank: Option<usize>,
    engine_error: bool,
    input_limit_hit: bool,
    state_loss: bool,
) -> &'static str {
    if engine_error {
        return "engine_error";
    }
    if state_loss {
        return "state_loss";
    }
    if input_limit_hit {
        return "input_limit_hit";
    }
    let parser_generated = stats
        .parser_generated_paths
        .contains(&case.canonical_pinyin);
    let lexicon_reachable = stats
        .lexicon_reachable_paths
        .contains(&case.canonical_pinyin);
    let beam_pruned = stats
        .joint_beam_pruned_paths
        .contains(&case.canonical_pinyin);
    if !parser_generated && !lexicon_reachable {
        "parser_not_generated"
    } else if beam_pruned && public_rank.is_none() {
        "joint_beam_pruned"
    } else if parser_generated && !lexicon_reachable && public_rank.is_none() {
        "lexicon_prefix_unreachable"
    } else if public_rank.is_none() {
        "public_path_limit_only"
    } else if target_rank.is_none() {
        "path_present_target_unrecalled"
    } else if target_rank != Some(1) {
        "candidate_recalled_ranking_error"
    } else {
        "none"
    }
}

fn inspect_state(
    state: &engine_protocol::CompositionResult,
    expected_raw: &str,
    automatic_commit: &mut bool,
    ascii_leak: &mut bool,
    input_limit_hit: &mut bool,
    state_loss: &mut bool,
    engine_error: &mut bool,
) {
    // A bounded input rejection is an expected, detectable validation event,
    // not an internal engine failure. Its preserved 64-digit composition is
    // accounted for separately from genuine state loss.
    *engine_error |=
        !state.success && state.error_code != engine_protocol::error::ImeErrorCode::InvalidArgument;
    *automatic_commit |= !state.commit_text.is_empty() || state.composition_finished;
    *ascii_leak |= state
        .commit_text
        .chars()
        .any(|value| value.is_ascii_alphabetic());
    let (current_input_limit_hit, current_state_loss) = raw_input_contract(state, expected_raw);
    *input_limit_hit |= current_input_limit_hit;
    *state_loss |= current_state_loss;
}

fn raw_input_contract(
    state: &engine_protocol::CompositionResult,
    expected_raw: &str,
) -> (bool, bool) {
    let preserved_len = expected_raw.len().min(T9_MAX_RAW_DIGITS);
    let preserved_raw = &expected_raw[..preserved_len];
    let input_limit_hit = expected_raw.len() > T9_MAX_RAW_DIGITS
        && !state.success
        && state.error_code == engine_protocol::error::ImeErrorCode::InvalidArgument
        && state.raw_input == preserved_raw;
    (input_limit_hit, state.raw_input != preserved_raw)
}

fn fingerprint(
    case: &DatasetCase,
    last: &engine_protocol::CompositionResult,
    paths: &[String],
    candidates: &[FormalCandidate],
    safety: (bool, bool, bool, bool),
) -> String {
    let (automatic_commit, input_limit_hit, state_loss, engine_error) = safety;
    let candidate_details = candidates
        .iter()
        .map(|candidate| {
            format!(
                "{}\u{1e}{}\u{1e}{}\u{1e}{}\u{1e}{}",
                candidate.id,
                candidate.text,
                candidate.reading,
                candidate.source,
                candidate.consumed_raw_len
            )
        })
        .collect::<Vec<_>>()
        .join("\u{1f}");
    let structure = format!(
        "{}|{}|{}|{}|{}|{}|{}|{}|{}|{}",
        case.id,
        last.raw_input,
        parser_state(last.parser_state),
        paths.join("\u{1f}"),
        candidate_details,
        automatic_commit,
        input_limit_hit,
        state_loss,
        engine_error,
        last.candidate_page
    );
    eval_sha256::hex(structure.as_bytes())
}

fn parser_state(value: ProtocolParserState) -> &'static str {
    value.as_str()
}

#[derive(Default)]
struct Counters {
    count: usize,
    top1: usize,
    top3: usize,
    top5: usize,
    reciprocal_rank: f64,
    no_candidates: usize,
    unrecalled: usize,
    rank_sum: usize,
    recalled: usize,
    path_top1: usize,
    path_top3: usize,
    path_top5: usize,
    path_missing: usize,
    path_pruned: usize,
    path_exists_target_missing: usize,
    candidate_recalled_wrong_top1: usize,
    corrections: usize,
    expected_chars: usize,
    combination_sum: usize,
    combination_max: usize,
    combination_limit_hits: usize,
    canonical_entered_internal_search: usize,
    canonical_joint_beam_pruned: usize,
    parser_not_generated: usize,
    lexicon_prefix_unreachable: usize,
    public_path_limit_only: usize,
    explored_hypotheses_sum: usize,
    max_beam_states: usize,
    lexicon_prunes: usize,
    pinyin_invalid_prunes: usize,
    joint_score_prunes: usize,
    beam_capacity_prunes: usize,
    output_limit_prunes: usize,
    graph_edges_sum: usize,
    peak_estimated_bytes: usize,
    input_limit_hits: usize,
}

fn counters(outcomes: &[CaseOutcome]) -> Counters {
    let mut value = Counters::default();
    for outcome in outcomes {
        value.count += 1;
        value.no_candidates += usize::from(outcome.candidate_count == 0);
        value.expected_chars += outcome
            .case
            .expected_texts
            .first()
            .map(|text| text.chars().count())
            .unwrap_or(0);
        let combinations = outcome.pinyin_path_count;
        value.combination_sum += combinations;
        value.combination_max = value.combination_max.max(combinations);
        value.combination_limit_hits += usize::from(combinations >= T9_MAX_PINYIN_COMBINATIONS);
        value.canonical_entered_internal_search +=
            usize::from(outcome.canonical_entered_internal_search);
        value.canonical_joint_beam_pruned +=
            usize::from(outcome.canonical_elimination_stage == "joint_beam_pruned");
        value.parser_not_generated +=
            usize::from(outcome.canonical_elimination_stage == "parser_not_generated");
        value.lexicon_prefix_unreachable +=
            usize::from(outcome.canonical_elimination_stage == "lexicon_prefix_unreachable");
        value.public_path_limit_only +=
            usize::from(outcome.canonical_elimination_stage == "public_path_limit_only");
        value.explored_hypotheses_sum = value
            .explored_hypotheses_sum
            .saturating_add(outcome.joint_stats.explored_pinyin_hypotheses);
        value.max_beam_states = value
            .max_beam_states
            .max(outcome.joint_stats.max_beam_states);
        value.lexicon_prunes = value
            .lexicon_prunes
            .saturating_add(outcome.joint_stats.lexicon_prefix_unreachable_prunes);
        value.pinyin_invalid_prunes = value
            .pinyin_invalid_prunes
            .saturating_add(outcome.joint_stats.pinyin_invalid_prunes);
        value.joint_score_prunes = value
            .joint_score_prunes
            .saturating_add(outcome.joint_stats.joint_score_prunes);
        value.beam_capacity_prunes = value
            .beam_capacity_prunes
            .saturating_add(outcome.joint_stats.beam_capacity_prunes);
        value.output_limit_prunes = value
            .output_limit_prunes
            .saturating_add(outcome.joint_stats.candidate_output_limit_prunes);
        value.graph_edges_sum = value
            .graph_edges_sum
            .saturating_add(outcome.joint_stats.graph_edges);
        value.peak_estimated_bytes = value
            .peak_estimated_bytes
            .max(outcome.joint_stats.peak_estimated_bytes);
        value.input_limit_hits += usize::from(outcome.joint_stats.input_limit_hit);
        match outcome.target_rank {
            Some(rank) => {
                value.top1 += usize::from(rank == 1);
                value.top3 += usize::from(rank <= 3);
                value.top5 += usize::from(rank <= 5);
                value.reciprocal_rank += 1.0 / rank as f64;
                value.rank_sum += rank;
                value.recalled += 1;
                value.candidate_recalled_wrong_top1 += usize::from(rank > 1);
                value.corrections += usize::from(rank > 1);
            }
            None => value.unrecalled += 1,
        }
        match outcome.canonical_path_rank {
            Some(rank) => {
                value.path_top1 += usize::from(rank == 1);
                value.path_top3 += usize::from(rank <= 3);
                value.path_top5 += usize::from(rank <= 5);
                value.path_exists_target_missing += usize::from(outcome.target_rank.is_none());
            }
            None => {
                value.path_missing += 1;
                value.path_pruned += usize::from(combinations >= T9_MAX_PINYIN_COMBINATIONS);
            }
        }
    }
    value
}

fn metrics_json(outcomes: &[CaseOutcome]) -> JsonValue {
    let value = counters(outcomes);
    let key_latencies = outcomes
        .iter()
        .flat_map(|outcome| outcome.key_latencies.iter().copied())
        .collect::<Vec<_>>();
    let sample_latencies = outcomes
        .iter()
        .map(|outcome| outcome.sample_total_micros)
        .collect::<Vec<_>>();
    let safety = safety(outcomes);
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
            "averageFirstRankWhenRecalled",
            optional_average(value.rank_sum, value.recalled),
        ),
        (
            "canonicalPinyinPathTop1Rate",
            JsonValue::number(rate(value.path_top1, value.count)),
        ),
        (
            "canonicalPinyinPathTop3Rate",
            JsonValue::number(rate(value.path_top3, value.count)),
        ),
        (
            "canonicalPinyinPathTop5Rate",
            JsonValue::number(rate(value.path_top5, value.count)),
        ),
        (
            "canonicalPinyinNotIn32PathsRate",
            JsonValue::number(rate(value.path_missing, value.count)),
        ),
        (
            "canonicalPinyinEnteredInternalSearchRate",
            JsonValue::number(rate(value.canonical_entered_internal_search, value.count)),
        ),
        (
            "canonicalPinyinJointBeamPrunedRate",
            JsonValue::number(rate(value.canonical_joint_beam_pruned, value.count)),
        ),
        (
            "canonicalPinyinEnteredPublic32Rate",
            JsonValue::number(rate(value.count - value.path_missing, value.count)),
        ),
        (
            "canonicalPathPrunedAt32Rate",
            JsonValue::number(rate(value.path_pruned, value.count)),
        ),
        (
            "canonicalPathPresentButTargetUnrecalledRate",
            JsonValue::number(rate(value.path_exists_target_missing, value.count)),
        ),
        (
            "candidateRecalledButWrongTop1Rate",
            JsonValue::number(rate(value.candidate_recalled_wrong_top1, value.count)),
        ),
        (
            "top1CorrectionEventsPer100ChineseCharacters",
            JsonValue::number(rate(value.corrections * 100, value.expected_chars)),
        ),
        (
            "averageCandidateSelectionRank",
            optional_average(value.rank_sum, value.recalled),
        ),
        ("keyLatencyMicros", latency_json(&key_latencies)),
        ("sampleTotalLatencyMicros", latency_json(&sample_latencies)),
        (
            "pinyinCombinationCount",
            JsonValue::object([
                (
                    "mean",
                    JsonValue::number(value.combination_sum as f64 / value.count.max(1) as f64),
                ),
                ("max", JsonValue::number(value.combination_max as f64)),
                (
                    "samplesAt32PathLimit",
                    JsonValue::number(value.combination_limit_hits as f64),
                ),
            ]),
        ),
        ("safety", safety_json(safety)),
        (
            "jointDecoder",
            JsonValue::object([
                (
                    "meanExploredPinyinHypothesesPerSample",
                    JsonValue::number(
                        value.explored_hypotheses_sum as f64 / value.count.max(1) as f64,
                    ),
                ),
                (
                    "maxBeamStates",
                    JsonValue::number(value.max_beam_states as f64),
                ),
                (
                    "lexiconPrefixUnreachablePrunes",
                    JsonValue::number(value.lexicon_prunes as f64),
                ),
                (
                    "pinyinInvalidPrunes",
                    JsonValue::number(value.pinyin_invalid_prunes as f64),
                ),
                (
                    "jointScorePrunes",
                    JsonValue::number(value.joint_score_prunes as f64),
                ),
                (
                    "beamCapacityPrunes",
                    JsonValue::number(value.beam_capacity_prunes as f64),
                ),
                (
                    "candidateOutputLimitPrunes",
                    JsonValue::number(value.output_limit_prunes as f64),
                ),
                (
                    "meanGraphEdgesPerSample",
                    JsonValue::number(value.graph_edges_sum as f64 / value.count.max(1) as f64),
                ),
                (
                    "peakEstimatedBytes",
                    JsonValue::number(value.peak_estimated_bytes as f64),
                ),
                (
                    "inputLimitHitCount",
                    JsonValue::number(value.input_limit_hits as f64),
                ),
            ]),
        ),
        (
            "failureAttribution",
            JsonValue::object([
                (
                    "parserNotGeneratedCount",
                    JsonValue::number(value.parser_not_generated as f64),
                ),
                (
                    "lexiconPrefixUnreachableCount",
                    JsonValue::number(value.lexicon_prefix_unreachable as f64),
                ),
                (
                    "jointBeamPrunedCount",
                    JsonValue::number(value.canonical_joint_beam_pruned as f64),
                ),
                (
                    "publicPathLimitOnlyCount",
                    JsonValue::number(value.public_path_limit_only as f64),
                ),
                (
                    "pathPrunedCount",
                    JsonValue::number(value.path_pruned as f64),
                ),
                (
                    "pathPrunedRate",
                    JsonValue::number(rate(value.path_pruned, value.count)),
                ),
                (
                    "pathPresentCandidateMissingCount",
                    JsonValue::number(value.path_exists_target_missing as f64),
                ),
                (
                    "pathPresentCandidateMissingRate",
                    JsonValue::number(rate(value.path_exists_target_missing, value.count)),
                ),
                (
                    "candidateRecalledRankingErrorCount",
                    JsonValue::number(value.candidate_recalled_wrong_top1 as f64),
                ),
                (
                    "candidateRecalledRankingErrorRate",
                    JsonValue::number(rate(value.candidate_recalled_wrong_top1, value.count)),
                ),
            ]),
        ),
    ])
}

fn optional_average(sum: usize, count: usize) -> JsonValue {
    if count == 0 {
        JsonValue::Null
    } else {
        JsonValue::number(sum as f64 / count as f64)
    }
}

fn grouped_metrics(outcomes: &[CaseOutcome]) -> JsonValue {
    let mut category = BTreeMap::<String, Vec<CaseOutcome>>::new();
    let mut input_kind = BTreeMap::<String, Vec<CaseOutcome>>::new();
    let mut digit_length = BTreeMap::<String, Vec<CaseOutcome>>::new();
    for outcome in outcomes {
        category
            .entry(outcome.case.category.clone())
            .or_default()
            .push(outcome.clone());
        input_kind
            .entry(outcome.case.input_kind.clone())
            .or_default()
            .push(outcome.clone());
        let band = match outcome.case.raw_digits.len() {
            0..=4 => "01-04",
            5..=8 => "05-08",
            9..=12 => "09-12",
            13..=20 => "13-20",
            21..=32 => "21-32",
            _ => "33-64",
        };
        digit_length
            .entry(band.to_owned())
            .or_default()
            .push(outcome.clone());
    }
    JsonValue::object([
        ("byCategory", outcome_map(category)),
        ("byInputKind", outcome_map(input_kind)),
        ("byDigitLength", outcome_map(digit_length)),
    ])
}

fn outcome_map(values: BTreeMap<String, Vec<CaseOutcome>>) -> JsonValue {
    JsonValue::Object(
        values
            .into_iter()
            .map(|(name, outcomes)| (name, metrics_json(&outcomes)))
            .collect(),
    )
}

fn run_json(index: usize, outcomes: &[CaseOutcome]) -> JsonValue {
    let joined = outcomes
        .iter()
        .map(|outcome| outcome.fingerprint.as_str())
        .collect::<Vec<_>>()
        .join("\n");
    JsonValue::object([
        ("run", JsonValue::number(index as f64)),
        ("metrics", metrics_json(outcomes)),
        (
            "candidateOutputSha256",
            JsonValue::string(eval_sha256::hex(joined.as_bytes())),
        ),
    ])
}

fn safety(outcomes: &[CaseOutcome]) -> Safety {
    Safety {
        automatic_commits: outcomes
            .iter()
            .filter(|outcome| outcome.automatic_commit)
            .count(),
        ascii_leaks: outcomes.iter().filter(|outcome| outcome.ascii_leak).count(),
        input_limit_hits: outcomes
            .iter()
            .filter(|outcome| outcome.input_limit_hit)
            .count(),
        state_losses: outcomes.iter().filter(|outcome| outcome.state_loss).count(),
        engine_errors: outcomes
            .iter()
            .filter(|outcome| outcome.engine_error)
            .count(),
    }
}

fn safety_json(value: Safety) -> JsonValue {
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
            "inputLimitHitCount",
            JsonValue::number(value.input_limit_hits as f64),
        ),
        (
            "stateLossCount",
            JsonValue::number(value.state_losses as f64),
        ),
        (
            "engineErrorCount",
            JsonValue::number(value.engine_errors as f64),
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

fn failures_bytes(outcomes: &[CaseOutcome]) -> Vec<u8> {
    let mut bytes = Vec::new();
    for outcome in outcomes.iter().filter(|outcome| {
        outcome.target_rank != Some(1)
            || outcome.automatic_commit
            || outcome.ascii_leak
            || outcome.input_limit_hit
            || outcome.state_loss
            || outcome.engine_error
    }) {
        let failure_type = failure_type(outcome);
        bytes.extend_from_slice(&serialize_line(&JsonValue::object([
            ("id", JsonValue::string(&outcome.case.id)),
            ("split", JsonValue::string(&outcome.case.split)),
            ("category", JsonValue::string(&outcome.case.category)),
            ("inputKind", JsonValue::string(&outcome.case.input_kind)),
            ("rawDigits", JsonValue::string(&outcome.case.raw_digits)),
            (
                "canonicalPinyin",
                JsonValue::string(&outcome.case.canonical_pinyin),
            ),
            (
                "expectedTexts",
                JsonValue::array(outcome.case.expected_texts.iter().map(JsonValue::string)),
            ),
            (
                "explicitBoundaryPositions",
                JsonValue::array(
                    outcome
                        .case
                        .boundaries
                        .iter()
                        .map(|value| JsonValue::number(*value as f64)),
                ),
            ),
            ("sourceId", JsonValue::string(&outcome.case.source_id)),
            (
                "sourceSampleIds",
                JsonValue::array(outcome.case.source_sample_ids.iter().map(JsonValue::string)),
            ),
            ("notes", JsonValue::string(&outcome.case.notes)),
            ("failureType", JsonValue::string(failure_type)),
            (
                "targetRank",
                outcome
                    .target_rank
                    .map(|rank| JsonValue::number(rank as f64))
                    .unwrap_or(JsonValue::Null),
            ),
            (
                "canonicalPathRank",
                outcome
                    .canonical_path_rank
                    .map(|rank| JsonValue::number(rank as f64))
                    .unwrap_or(JsonValue::Null),
            ),
            (
                "currentPinyin",
                outcome
                    .pinyin_paths
                    .first()
                    .map(JsonValue::string)
                    .unwrap_or_else(|| JsonValue::string("")),
            ),
            (
                "allPublishedPinyinPaths",
                JsonValue::array(outcome.pinyin_paths.iter().map(JsonValue::string)),
            ),
            (
                "allCandidates",
                JsonValue::array(outcome.candidates.iter().map(candidate_json)),
            ),
            (
                "sampleTotalMicros",
                JsonValue::number(outcome.sample_total_micros as f64),
            ),
            ("jointDecoderDiagnostics", sample_diagnostics_json(outcome)),
        ])));
    }
    bytes
}

fn failure_type(outcome: &CaseOutcome) -> &str {
    if outcome.engine_error {
        "engine_error"
    } else if outcome.state_loss {
        "state_loss"
    } else if outcome.input_limit_hit {
        "input_limit_hit"
    } else if outcome.automatic_commit {
        "automatic_commit"
    } else {
        &outcome.canonical_elimination_stage
    }
}

fn sample_diagnostics_json(outcome: &CaseOutcome) -> JsonValue {
    JsonValue::object([
        ("id", JsonValue::string(&outcome.case.id)),
        (
            "internalExploredPinyinHypotheses",
            JsonValue::number(outcome.joint_stats.explored_pinyin_hypotheses as f64),
        ),
        (
            "maxBeamStates",
            JsonValue::number(outcome.joint_stats.max_beam_states as f64),
        ),
        (
            "lexiconPrefixUnreachablePrunes",
            JsonValue::number(outcome.joint_stats.lexicon_prefix_unreachable_prunes as f64),
        ),
        (
            "pinyinInvalidPrunes",
            JsonValue::number(outcome.joint_stats.pinyin_invalid_prunes as f64),
        ),
        (
            "jointScorePrunes",
            JsonValue::number(outcome.joint_stats.joint_score_prunes as f64),
        ),
        (
            "beamCapacityPrunes",
            JsonValue::number(outcome.joint_stats.beam_capacity_prunes as f64),
        ),
        (
            "candidateOutputLimitPrunes",
            JsonValue::number(outcome.joint_stats.candidate_output_limit_prunes as f64),
        ),
        (
            "canonicalPinyinEnteredInternalSearch",
            JsonValue::Bool(outcome.canonical_entered_internal_search),
        ),
        (
            "canonicalPinyinEliminationStage",
            JsonValue::string(&outcome.canonical_elimination_stage),
        ),
        (
            "canonicalPinyinEnteredPublic32",
            JsonValue::Bool(outcome.canonical_path_rank.is_some()),
        ),
        (
            "canonicalPinyinPublicRank",
            outcome
                .canonical_path_rank
                .map(|rank| JsonValue::number(rank as f64))
                .unwrap_or(JsonValue::Null),
        ),
        (
            "targetRecalled",
            JsonValue::Bool(outcome.target_rank.is_some()),
        ),
        (
            "targetFirstRank",
            outcome
                .target_rank
                .map(|rank| JsonValue::number(rank as f64))
                .unwrap_or(JsonValue::Null),
        ),
        ("inputLimitHit", JsonValue::Bool(outcome.input_limit_hit)),
        (
            "keyLatencyMicros",
            JsonValue::array(
                outcome
                    .key_latencies
                    .iter()
                    .map(|value| JsonValue::number(*value as f64)),
            ),
        ),
        (
            "sampleTotalMicros",
            JsonValue::number(outcome.sample_total_micros as f64),
        ),
        (
            "graphEdges",
            JsonValue::number(outcome.joint_stats.graph_edges as f64),
        ),
        (
            "peakEstimatedBytes",
            JsonValue::number(outcome.joint_stats.peak_estimated_bytes as f64),
        ),
    ])
}

fn candidate_json(candidate: &FormalCandidate) -> JsonValue {
    JsonValue::object([
        ("id", JsonValue::string(&candidate.id)),
        ("text", JsonValue::string(&candidate.text)),
        ("reading", JsonValue::string(&candidate.reading)),
        ("source", JsonValue::string(&candidate.source)),
        (
            "consumedRawLen",
            JsonValue::number(candidate.consumed_raw_len as f64),
        ),
    ])
}

fn load_cases(dataset_dir: &Path) -> Result<Vec<DatasetCase>, String> {
    let mut result = Vec::new();
    for (name, expected_split) in [
        ("dev.jsonl", "dev"),
        ("blind.jsonl", "blind"),
        ("public-regression.jsonl", "public-regression"),
    ] {
        let path = dataset_dir.join(name);
        let bytes = fs::read(&path).map_err(|error| format!("{}: {error}", path.display()))?;
        let text =
            std::str::from_utf8(&bytes).map_err(|_| format!("{} is not UTF-8", path.display()))?;
        for (line_index, line) in text
            .lines()
            .enumerate()
            .filter(|(_, line)| !line.is_empty())
        {
            result.push(parse_case(
                parse(line.as_bytes())?,
                name,
                line_index + 1,
                expected_split,
            )?);
        }
    }
    Ok(result)
}

fn parse_case(
    value: JsonValue,
    file: &str,
    line: usize,
    expected_split: &str,
) -> Result<DatasetCase, String> {
    let object = value
        .as_object()
        .ok_or_else(|| format!("{file}:{line}: case must be object"))?;
    let string = |name: &str| -> Result<String, String> {
        object
            .get(name)
            .and_then(JsonValue::as_str)
            .map(str::to_owned)
            .ok_or_else(|| format!("{file}:{line}: missing string {name}"))
    };
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
                    .ok_or_else(|| format!("{file}:{line}: invalid string in {name}"))
            })
            .collect()
    };
    let numbers = |name: &str| -> Result<Vec<usize>, String> {
        object
            .get(name)
            .and_then(JsonValue::as_array)
            .ok_or_else(|| format!("{file}:{line}: missing array {name}"))?
            .iter()
            .map(|value| {
                value
                    .as_u64()
                    .and_then(|value| usize::try_from(value).ok())
                    .ok_or_else(|| format!("{file}:{line}: invalid integer in {name}"))
            })
            .collect()
    };
    let case = DatasetCase {
        id: string("id")?,
        split: string("split")?,
        category: string("category")?,
        input_kind: string("inputKind")?,
        raw_digits: string("rawDigits")?,
        canonical_pinyin: string("canonicalPinyin")?,
        expected_texts: strings("expectedTexts")?,
        boundaries: numbers("explicitBoundaryPositions")?,
        source_id: string("sourceId")?,
        source_sample_ids: strings("sourceSampleIds")?,
        notes: string("notes")?,
        layer: string("layer")?,
    };
    if case.split != expected_split {
        return Err(format!(
            "{} split {} does not match file {file}",
            case.id, case.split
        ));
    }
    Ok(case)
}

fn validate_cases(cases: &[DatasetCase], source_ids: &BTreeSet<String>) -> Result<(), String> {
    validate_uniqueness(cases)?;
    let specialized = cases
        .iter()
        .filter(|case| case.layer == "t9_specialized")
        .collect::<Vec<_>>();
    if specialized.len() < 600 {
        return Err(format!(
            "T9 specialized dataset has {} cases; minimum is 600",
            specialized.len()
        ));
    }
    let dev = specialized
        .iter()
        .filter(|case| case.split == "dev")
        .count();
    let blind = specialized
        .iter()
        .filter(|case| case.split == "blind")
        .count();
    if dev * 3 != blind {
        return Err(format!(
            "dev/blind must be exactly 25/75, got {dev}/{blind}"
        ));
    }
    let mut category_split = BTreeMap::<String, (usize, usize)>::new();
    for case in cases {
        validate_case_shape(case, source_ids)?;
        if case.layer == "t9_specialized" {
            let entry = category_split.entry(case.category.clone()).or_default();
            if case.split == "dev" {
                entry.0 += 1;
            } else if case.split == "blind" {
                entry.1 += 1;
            }
        }
    }
    for category in SPECIALIZED_CATEGORIES {
        let (category_dev, category_blind) = category_split
            .get(category)
            .copied()
            .ok_or_else(|| format!("missing specialized category {category}"))?;
        if category_dev == 0 || category_dev * 3 != category_blind {
            return Err(format!(
                "category {category} must have exact 25/75 dev/blind, got {category_dev}/{category_blind}"
            ));
        }
    }
    if category_split.len() != SPECIALIZED_CATEGORIES.len() {
        return Err(format!(
            "unexpected specialized categories: {:?}",
            category_split.keys().collect::<Vec<_>>()
        ));
    }
    Ok(())
}

fn validate_uniqueness(cases: &[DatasetCase]) -> Result<(), String> {
    let mut ids = BTreeSet::new();
    let mut pairs = BTreeSet::new();
    for case in cases {
        if !ids.insert(case.id.clone()) {
            return Err(format!("duplicate id {}", case.id));
        }
        let pair = format!(
            "{}\0{}",
            case.raw_digits,
            case.expected_texts.join("\u{1f}")
        );
        if !pairs.insert(pair) {
            return Err(format!(
                "duplicate rawDigits/expectedTexts combination at {}",
                case.id
            ));
        }
    }
    Ok(())
}

fn validate_case_shape(case: &DatasetCase, source_ids: &BTreeSet<String>) -> Result<(), String> {
    if case.raw_digits.is_empty()
        || !case
            .raw_digits
            .chars()
            .all(|value| ('2'..='9').contains(&value))
    {
        return Err(format!(
            "{} has non-2..9 rawDigits {:?}",
            case.id, case.raw_digits
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
    if !matches!(case.split.as_str(), "dev" | "blind" | "public-regression") {
        return Err(format!("{} has invalid split {}", case.id, case.split));
    }
    if case.layer == "t9_specialized" {
        if !SPECIALIZED_CATEGORIES.contains(&case.category.as_str()) {
            return Err(format!(
                "{} has invalid category {}",
                case.id, case.category
            ));
        }
    } else if case.layer != "converted_public_regression" || case.split != "public-regression" {
        return Err(format!("{} has invalid layer {}", case.id, case.layer));
    }
    if !INPUT_KINDS.contains(&case.input_kind.as_str()) {
        return Err(format!(
            "{} has invalid inputKind {}",
            case.id, case.input_kind
        ));
    }
    if !source_ids.contains(&case.source_id) {
        return Err(format!(
            "{} has unknown sourceId {}",
            case.id, case.source_id
        ));
    }
    if case.source_sample_ids.is_empty()
        || case
            .source_sample_ids
            .iter()
            .any(|value| value.trim().is_empty())
        || case.notes.trim().is_empty()
    {
        return Err(format!("{} is missing provenance", case.id));
    }
    let canonical_digits = canonical_signature(&case.canonical_pinyin)
        .ok_or_else(|| format!("{} has invalid canonicalPinyin", case.id))?;
    let mut previous = 0;
    for &position in &case.boundaries {
        if position == 0 || position >= case.raw_digits.len() || position <= previous {
            return Err(format!(
                "{} has invalid boundary position {position}",
                case.id
            ));
        }
        previous = position;
    }
    if case.input_kind == "explicit_boundary" {
        if case.boundaries.is_empty() || case.raw_digits != canonical_digits {
            return Err(format!("{} has invalid explicit boundary sample", case.id));
        }
    } else if !case.boundaries.is_empty() {
        return Err(format!("{} has undeclared boundary inputKind", case.id));
    }
    match case.input_kind.as_str() {
        "clean" => {
            if case.raw_digits != canonical_digits {
                return Err(format!("{} clean T9 signature mismatch", case.id));
            }
        }
        "explicit_boundary" => {}
        "abbreviated" => {
            let initials = case
                .canonical_pinyin
                .split('\'')
                .filter_map(|syllable| {
                    t9_signature(syllable).and_then(|value| value.chars().next())
                })
                .collect::<String>();
            if case.raw_digits != initials {
                return Err(format!("{} is not a canonical abbreviation", case.id));
            }
        }
        "incomplete_tail" => {
            if case.raw_digits.len() >= canonical_digits.len()
                || !canonical_digits.starts_with(&case.raw_digits)
            {
                return Err(format!("{} is not an incomplete canonical prefix", case.id));
            }
        }
        "missing_digit" => {
            if canonical_digits.len() != case.raw_digits.len() + 1
                || !one_deletion(&canonical_digits, &case.raw_digits)
            {
                return Err(format!("{} is not exactly one missing digit", case.id));
            }
        }
        "extra_digit" => {
            if case.raw_digits.len() != canonical_digits.len() + 1
                || !one_deletion(&case.raw_digits, &canonical_digits)
            {
                return Err(format!("{} is not exactly one extra digit", case.id));
            }
        }
        "adjacent_key" => {
            if !one_adjacent_substitution(&canonical_digits, &case.raw_digits) {
                return Err(format!("{} is not one adjacent-key substitution", case.id));
            }
        }
        "transposition" => {
            if !one_transposition(&canonical_digits, &case.raw_digits) {
                return Err(format!("{} is not one adjacent transposition", case.id));
            }
        }
        "fuzzy_dialect" => {
            if edit_distance(&canonical_digits, &case.raw_digits) != 1 {
                return Err(format!("{} is not one fuzzy/dialect edit", case.id));
            }
        }
        _ => unreachable!("checked input kind"),
    }
    if case.layer == "converted_public_regression"
        && (!case.id.starts_with("p9-public-qp-v1-") || case.input_kind != "clean")
    {
        return Err(format!("{} is not traceable public conversion", case.id));
    }
    Ok(())
}

fn canonical_signature(value: &str) -> Option<String> {
    if value.is_empty() || value.starts_with('\'') || value.ends_with('\'') || value.contains("''")
    {
        return None;
    }
    let inventory = pinyin_syllable::all_syllables().collect::<BTreeSet<_>>();
    let mut result = String::new();
    for syllable in value.split('\'') {
        if !inventory.contains(syllable) {
            return None;
        }
        result.push_str(&t9_signature(syllable)?);
    }
    Some(result)
}

fn one_deletion(longer: &str, shorter: &str) -> bool {
    (0..longer.len())
        .any(|index| format!("{}{}", &longer[..index], &longer[index + 1..]) == shorter)
}

fn one_adjacent_substitution(expected: &str, actual: &str) -> bool {
    if expected.len() != actual.len() {
        return false;
    }
    let differences = expected
        .chars()
        .zip(actual.chars())
        .filter(|(left, right)| left != right)
        .collect::<Vec<_>>();
    differences.len() == 1 && keypad_adjacent(differences[0].0, differences[0].1)
}

fn keypad_adjacent(left: char, right: char) -> bool {
    let position = |value: char| match value {
        '2' => Some((0_i32, 1_i32)),
        '3' => Some((0, 2)),
        '4' => Some((1, 0)),
        '5' => Some((1, 1)),
        '6' => Some((1, 2)),
        '7' => Some((2, 0)),
        '8' => Some((2, 1)),
        '9' => Some((2, 2)),
        _ => None,
    };
    match (position(left), position(right)) {
        (Some(left), Some(right)) => {
            let row = (left.0 - right.0).abs();
            let column = (left.1 - right.1).abs();
            row <= 1 && column <= 1 && row + column > 0
        }
        _ => false,
    }
}

fn one_transposition(expected: &str, actual: &str) -> bool {
    if expected.len() != actual.len() || expected == actual {
        return false;
    }
    let expected = expected.as_bytes();
    let actual = actual.as_bytes();
    (0..expected.len().saturating_sub(1)).any(|index| {
        expected[index] != expected[index + 1]
            && expected[index] == actual[index + 1]
            && expected[index + 1] == actual[index]
            && expected[..index] == actual[..index]
            && expected[index + 2..] == actual[index + 2..]
    })
}

fn edit_distance(left: &str, right: &str) -> usize {
    let mut row = (0..=right.len()).collect::<Vec<_>>();
    for (left_index, left_byte) in left.bytes().enumerate() {
        let mut previous = row[0];
        row[0] = left_index + 1;
        for (right_index, right_byte) in right.bytes().enumerate() {
            let old = row[right_index + 1];
            row[right_index + 1] = (row[right_index + 1] + 1)
                .min(row[right_index] + 1)
                .min(previous + usize::from(left_byte != right_byte));
            previous = old;
        }
    }
    row[right.len()]
}

fn load_source_ids(dataset_dir: &Path) -> Result<BTreeSet<String>, String> {
    let bytes = fs::read(dataset_dir.join("sources.json")).map_err(|error| error.to_string())?;
    let value = parse(&bytes)?;
    value
        .as_object()
        .and_then(|object| object.get("sources"))
        .and_then(JsonValue::as_array)
        .ok_or_else(|| "sources.json is missing sources".to_owned())?
        .iter()
        .map(|source| {
            source
                .as_object()
                .and_then(|object| object.get("id"))
                .and_then(JsonValue::as_str)
                .map(str::to_owned)
                .ok_or_else(|| "source entry is missing id".to_owned())
        })
        .collect()
}

fn dataset_files(dataset_dir: &Path) -> Result<Vec<DatasetFile>, String> {
    let actual_names = fs::read_dir(dataset_dir)
        .map_err(|error| error.to_string())?
        .map(|entry| {
            entry.map_err(|error| error.to_string()).and_then(|entry| {
                entry
                    .file_name()
                    .into_string()
                    .map_err(|_| "non-UTF8 dataset filename".to_owned())
            })
        })
        .collect::<Result<BTreeSet<_>, _>>()?;
    let expected_names = DATASET_FILES
        .iter()
        .map(|value| (*value).to_owned())
        .collect::<BTreeSet<_>>();
    if actual_names != expected_names {
        return Err(format!(
            "dataset file set mismatch: expected {expected_names:?}, actual {actual_names:?}"
        ));
    }
    DATASET_FILES
        .iter()
        .map(|name| {
            let bytes = fs::read(dataset_dir.join(name)).map_err(|error| error.to_string())?;
            let sample_count = if name.ends_with(".jsonl") {
                std::str::from_utf8(&bytes)
                    .map_err(|_| format!("{name} is not UTF-8"))?
                    .lines()
                    .filter(|line| !line.is_empty())
                    .count()
            } else {
                0
            };
            Ok(DatasetFile {
                path: (*name).to_owned(),
                bytes: bytes.len(),
                sha256: eval_sha256::hex(&bytes),
                sample_count,
            })
        })
        .collect()
}

fn verify_dataset_manifest(dataset_dir: &Path, manifest_path: &Path) -> Result<(), String> {
    let manifest_bytes = fs::read(manifest_path).map_err(|error| error.to_string())?;
    let manifest = parse(&manifest_bytes)?;
    let expected_files = manifest
        .as_object()
        .and_then(|object| object.get("files"))
        .and_then(JsonValue::as_array)
        .ok_or_else(|| "pinyin9 manifest is missing files".to_owned())?;
    let actual_files = dataset_files(dataset_dir)?;
    if expected_files.len() != actual_files.len() {
        return Err("FROZEN_DATASET_FILE_SET_CHANGED".to_owned());
    }
    for (expected, actual) in expected_files.iter().zip(actual_files.iter()) {
        let object = expected
            .as_object()
            .ok_or_else(|| "invalid manifest file entry".to_owned())?;
        let path = object.get("path").and_then(JsonValue::as_str).unwrap_or("");
        let bytes = object
            .get("bytes")
            .and_then(JsonValue::as_u64)
            .unwrap_or(u64::MAX);
        let hash = object
            .get("sha256")
            .and_then(JsonValue::as_str)
            .unwrap_or("");
        if path != actual.path || bytes != actual.bytes as u64 || hash != actual.sha256 {
            return Err(format!(
                "FROZEN_DATASET_HASH_MISMATCH: {} expected {hash}/{bytes}, actual {}/{}",
                actual.path, actual.sha256, actual.bytes
            ));
        }
    }
    Ok(())
}

fn verify_implementation_manifest(
    repo_root: &Path,
    dataset_manifest_path: &Path,
    lexicon_path: &Path,
    implementation_path: &Path,
) -> Result<String, String> {
    let bytes = fs::read(implementation_path).map_err(|error| error.to_string())?;
    let value = parse(&bytes)?;
    let object = value
        .as_object()
        .ok_or_else(|| "implementation manifest must be object".to_owned())?;
    let dataset_manifest = fs::read(dataset_manifest_path).map_err(|error| error.to_string())?;
    let lexicon = fs::read(lexicon_path).map_err(|error| error.to_string())?;
    let dataset_hash = eval_sha256::hex(&dataset_manifest);
    let lexicon_hash = eval_sha256::hex(&lexicon);
    if object
        .get("datasetManifestSha256")
        .and_then(JsonValue::as_str)
        != Some(dataset_hash.as_str())
    {
        return Err("IMPLEMENTATION_FREEZE_DATASET_MISMATCH".to_owned());
    }
    if object
        .get("productionLexiconSha256")
        .and_then(JsonValue::as_str)
        != Some(lexicon_hash.as_str())
    {
        return Err("IMPLEMENTATION_FREEZE_LEXICON_MISMATCH".to_owned());
    }
    let files = object
        .get("files")
        .and_then(JsonValue::as_array)
        .ok_or_else(|| "implementation manifest is missing files".to_owned())?;
    for file in files {
        let object = file
            .as_object()
            .ok_or_else(|| "invalid implementation file entry".to_owned())?;
        let relative = object
            .get("path")
            .and_then(JsonValue::as_str)
            .ok_or_else(|| "implementation file is missing path".to_owned())?;
        let expected_bytes = object
            .get("bytes")
            .and_then(JsonValue::as_u64)
            .ok_or_else(|| "implementation file is missing bytes".to_owned())?;
        let expected_hash = object
            .get("sha256")
            .and_then(JsonValue::as_str)
            .ok_or_else(|| "implementation file is missing hash".to_owned())?;
        let actual = fs::read(repo_root.join(relative))
            .map_err(|error| format!("implementation file {relative}: {error}"))?;
        if actual.len() as u64 != expected_bytes || eval_sha256::hex(&actual) != expected_hash {
            return Err(format!("IMPLEMENTATION_FREEZE_HASH_MISMATCH: {relative}"));
        }
    }
    Ok(eval_sha256::hex(&bytes))
}

fn validation_json(cases: &[DatasetCase]) -> JsonValue {
    JsonValue::object([
        ("valid", JsonValue::Bool(true)),
        ("sampleCount", JsonValue::number(cases.len() as f64)),
        (
            "splitDistribution",
            count_json(count_by(cases, |case| &case.split)),
        ),
        (
            "categoryDistribution",
            count_json(count_by(cases, |case| &case.category)),
        ),
        (
            "inputKindDistribution",
            count_json(count_by(cases, |case| &case.input_kind)),
        ),
    ])
}

fn count_by<'a>(
    cases: &'a [DatasetCase],
    select: impl Fn(&'a DatasetCase) -> &'a String,
) -> BTreeMap<String, usize> {
    let mut counts = BTreeMap::new();
    for case in cases {
        *counts.entry(select(case).clone()).or_default() += 1;
    }
    counts
}

fn count_json(counts: BTreeMap<String, usize>) -> JsonValue {
    JsonValue::Object(
        counts
            .into_iter()
            .map(|(name, count)| (name, JsonValue::number(count as f64)))
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

fn write_file(path: &Path, bytes: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(path, bytes).map_err(|error| error.to_string())
}

fn write_new_file(path: &Path, bytes: &[u8]) -> Result<(), String> {
    if path.exists() {
        return Err(format!(
            "refusing to overwrite existing file {}",
            path.display()
        ));
    }
    write_file(path, bytes)
}

fn rate(value: usize, count: usize) -> f64 {
    value as f64 / count.max(1) as f64
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn valid_case() -> DatasetCase {
        DatasetCase {
            id: "p9-v1-test".to_owned(),
            split: "dev".to_owned(),
            category: "common_character_word".to_owned(),
            input_kind: "clean".to_owned(),
            raw_digits: "64".to_owned(),
            canonical_pinyin: "ni".to_owned(),
            expected_texts: vec!["你".to_owned()],
            boundaries: Vec::new(),
            source_id: "source".to_owned(),
            source_sample_ids: vec!["authored-1".to_owned()],
            notes: "authored".to_owned(),
            layer: "t9_specialized".to_owned(),
        }
    }

    fn sources() -> BTreeSet<String> {
        BTreeSet::from(["source".to_owned()])
    }

    #[test]
    fn validation_rejects_illegal_digit_empty_target_and_missing_source() {
        let mut case = valid_case();
        case.raw_digits = "60".to_owned();
        assert!(validate_case_shape(&case, &sources()).is_err());
        let mut case = valid_case();
        case.expected_texts.clear();
        assert!(validate_case_shape(&case, &sources()).is_err());
        let mut case = valid_case();
        case.source_id = "missing".to_owned();
        assert!(validate_case_shape(&case, &sources()).is_err());
    }

    #[test]
    fn validation_rejects_bad_canonical_boundary_and_clean_signature() {
        let mut case = valid_case();
        case.canonical_pinyin = "notpinyin".to_owned();
        assert!(validate_case_shape(&case, &sources()).is_err());
        let mut case = valid_case();
        case.boundaries = vec![0];
        assert!(validate_case_shape(&case, &sources()).is_err());
        let mut case = valid_case();
        case.raw_digits = "65".to_owned();
        assert!(validate_case_shape(&case, &sources()).is_err());

        let mut case = valid_case();
        case.split = "holdout".to_owned();
        assert!(validate_case_shape(&case, &sources()).is_err());
        let mut case = valid_case();
        case.category = "unknown".to_owned();
        assert!(validate_case_shape(&case, &sources()).is_err());
        let mut case = valid_case();
        case.input_kind = "unknown".to_owned();
        assert!(validate_case_shape(&case, &sources()).is_err());
    }

    #[test]
    fn declared_single_edits_are_checked_exactly() {
        let mut case = valid_case();
        case.input_kind = "missing_digit".to_owned();
        case.raw_digits = "6".to_owned();
        assert!(validate_case_shape(&case, &sources()).is_ok());
        case.raw_digits = "7".to_owned();
        assert!(validate_case_shape(&case, &sources()).is_err());

        let mut case = valid_case();
        case.input_kind = "adjacent_key".to_owned();
        case.raw_digits = "65".to_owned();
        assert!(validate_case_shape(&case, &sources()).is_ok());
        case.raw_digits = "69".to_owned();
        assert!(validate_case_shape(&case, &sources()).is_err());
    }

    #[test]
    fn duplicate_id_and_pair_are_rejected_before_distribution() {
        let case = valid_case();
        let error = validate_uniqueness(&[case.clone(), case.clone()]).expect_err("duplicate ID");
        assert!(error.contains("duplicate id"));
        let mut second = case.clone();
        second.id = "different".to_owned();
        let error = validate_uniqueness(&[case, second]).expect_err("duplicate pair");
        assert!(error.contains("duplicate rawDigits"));
    }

    #[test]
    fn existing_manifest_is_never_overwritten() {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "pinyin9-existing-manifest-{}-{nonce}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("temp root");
        let manifest = root.join("freeze-manifest.json");
        fs::write(&manifest, b"protected").expect("fixture");
        let error = freeze_pinyin9_dataset(&root, &manifest, "id", "time")
            .expect_err("must reject existing manifest");
        assert!(error.contains("already exists"));
        fs::remove_dir_all(root).expect("cleanup");
    }

    #[test]
    fn frozen_dataset_hash_change_is_rejected() {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let root =
            std::env::temp_dir().join(format!("pinyin9-hash-gate-{}-{nonce}", std::process::id()));
        let dataset = root.join("dataset");
        fs::create_dir_all(&dataset).expect("dataset root");
        for name in DATASET_FILES {
            fs::write(dataset.join(name), b"fixture\n").expect("fixture file");
        }
        let files = dataset_files(&dataset).expect("dataset identity");
        let manifest = JsonValue::object([(
            "files",
            JsonValue::array(files.iter().map(|file| {
                JsonValue::object([
                    ("path", JsonValue::string(&file.path)),
                    ("bytes", JsonValue::number(file.bytes as f64)),
                    ("sha256", JsonValue::string(&file.sha256)),
                ])
            })),
        )]);
        let manifest_path = root.join("freeze-manifest.json");
        fs::write(&manifest_path, serialize(&manifest)).expect("manifest");
        verify_dataset_manifest(&dataset, &manifest_path).expect("initial identity");
        fs::write(dataset.join("dev.jsonl"), b"changed\n").expect("mutation");
        let error = verify_dataset_manifest(&dataset, &manifest_path).expect_err("hash mismatch");
        assert!(error.contains("FROZEN_DATASET_HASH_MISMATCH"));
        fs::remove_dir_all(root).expect("cleanup");
    }

    #[test]
    fn blind_guard_rejects_repeat_receipt_and_wrong_run_count() {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let receipt = std::env::temp_dir().join(format!("pinyin9-receipt-{nonce}.json"));
        let dummy = PathBuf::from("dummy");
        let mut request = Pinyin9EvaluationRequest {
            dataset_dir: &dummy,
            manifest_path: &dummy,
            implementation_manifest_path: Some(&dummy),
            repo_root: Some(&dummy),
            lexicon_path: &dummy,
            results_path: &dummy,
            failures_path: &dummy,
            receipt_path: Some(&receipt),
            runs: 4,
            split: "blind",
        };
        assert!(validate_blind_guard(&request).is_err());
        request.runs = 3;
        fs::write(&receipt, b"receipt").expect("receipt fixture");
        assert!(validate_blind_guard(&request).is_err());
        fs::remove_file(receipt).expect("cleanup");
    }

    #[test]
    fn bounded_t9_input_rejection_is_not_reported_as_state_loss() {
        let expected = "6".repeat(T9_MAX_RAW_DIGITS + 1);
        let mut preserved = engine_protocol::CompositionResult::interface_error(
            engine_protocol::error::ImeErrorCode::InvalidArgument,
        );
        preserved.raw_input = "6".repeat(T9_MAX_RAW_DIGITS);
        assert_eq!(raw_input_contract(&preserved, &expected), (true, false));

        preserved.raw_input.pop();
        assert_eq!(raw_input_contract(&preserved, &expected), (false, true));
    }
}
