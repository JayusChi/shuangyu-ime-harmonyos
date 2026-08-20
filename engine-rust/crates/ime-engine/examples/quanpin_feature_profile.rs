use std::cmp::Reverse;
use std::fs;
use std::time::Instant;

use ime_engine::{EngineConfig, ImeEngine, QuanpinExpansionStats, QuanpinFeatureConfig};

#[derive(Debug)]
struct KeySample {
    case_id: String,
    prefix: String,
    latency_micros: u128,
    expansion: QuanpinExpansionStats,
}

fn main() {
    let mut args = std::env::args().skip(1);
    let lexicon = args
        .next()
        .expect("usage: quanpin_feature_profile <production.lex> <dataset.jsonl>");
    let dataset = args
        .next()
        .expect("usage: quanpin_feature_profile <production.lex> <dataset.jsonl>");
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        lexicon_path: Some(lexicon),
        candidate_page_size: 50,
        quanpin_features: QuanpinFeatureConfig::new(true, []),
        ..EngineConfig::default()
    })
    .expect("engine");
    engine.set_user_learning_enabled(false);
    engine.set_session_learning_allowed(false);

    let text = fs::read_to_string(dataset).expect("UTF-8 dataset");
    let mut samples = Vec::new();
    for line in text.lines().filter(|line| !line.trim().is_empty()) {
        let case_id = string_field(line, "id").expect("dataset id");
        let raw_input = string_field(line, "rawInput").expect("dataset rawInput");
        engine.reset();
        let mut prefix = String::new();
        for key in raw_input.chars() {
            prefix.push(key);
            let started = Instant::now();
            let _ = engine.process_key(key);
            samples.push(KeySample {
                case_id: case_id.clone(),
                prefix: prefix.clone(),
                latency_micros: started.elapsed().as_micros(),
                expansion: engine.last_quanpin_expansion_stats(),
            });
        }
    }

    samples.sort_by_key(|sample| Reverse(sample.latency_micros));
    let mut latencies = samples
        .iter()
        .map(|sample| sample.latency_micros)
        .collect::<Vec<_>>();
    latencies.sort_unstable();
    let percentile = |percent: usize| latencies[((latencies.len() - 1) * percent).div_ceil(100)];
    println!(
        "keys={} p50={} p95={} p99={} max={}",
        latencies.len(),
        percentile(50),
        percentile(95),
        percentile(99),
        latencies.last().expect("nonempty")
    );
    println!(
        "latencyMicros\tcaseId\tprefix\tvariants\tqueries\tdecodes\texpansions\ttruncated\tcacheHit"
    );
    for sample in samples.iter().take(80) {
        println!(
            "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            sample.latency_micros,
            sample.case_id,
            sample.prefix,
            sample.expansion.spelling_variants_generated,
            sample.expansion.correction_query_paths,
            sample.expansion.sentence_decoder_paths,
            sample.expansion.candidate_expansions,
            sample.expansion.truncated_by_limit,
            sample.expansion.expansion_cache_hit,
        );
    }
}

fn string_field(line: &str, name: &str) -> Option<String> {
    let marker = format!("\"{name}\":\"");
    let value = line.get(line.find(&marker)? + marker.len()..)?;
    Some(value.get(..value.find('"')?)?.to_owned())
}
