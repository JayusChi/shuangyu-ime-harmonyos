use std::fs;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use candidate_query::{CandidateQueryEngine, QueryConfig, QueryMode, QueryRequest};
use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::load_binary_lexicon;

fn percentile(samples: &mut [Duration], percentile: usize) -> u128 {
    samples.sort_unstable();
    let index = ((samples.len() - 1) * percentile) / 100;
    samples[index].as_nanos()
}

fn main() {
    let workspace = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let lexicon_path = workspace.join("../dictionaries/generated/production.lex");
    let corpus_path = workspace.join("tests/fixtures/production_corpus/auto_generated.tsv");

    let cold_start = Instant::now();
    let bytes = fs::read(&lexicon_path).expect("read production lexicon");
    let cold_lexicon = load_binary_lexicon(&bytes).expect("load production lexicon");
    let cold_load = cold_start.elapsed();
    let warm_start = Instant::now();
    let warm_lexicon = load_binary_lexicon(&bytes).expect("reload production lexicon");
    let warm_load = warm_start.elapsed();

    let cases = fs::read_to_string(corpus_path)
        .expect("read production corpus")
        .lines()
        .skip(1)
        .take(5_000)
        .map(|line| {
            let fields = line.split('\t').collect::<Vec<_>>();
            (fields[2].to_owned(), fields[3].to_owned())
        })
        .collect::<Vec<_>>();
    let mut query_engine = CandidateQueryEngine::new(warm_lexicon, QueryConfig::default());
    let mut query_samples = Vec::with_capacity(cases.len());
    let mut slowest = (Duration::ZERO, String::new());
    for (_, reading) in &cases {
        let started = Instant::now();
        let result = query_engine
            .query(QueryRequest::new("xiaohe", reading, QueryMode::Exact, 9))
            .expect("benchmark query");
        assert!(!result.candidates.is_empty());
        let elapsed = started.elapsed();
        if elapsed > slowest.0 {
            slowest = (elapsed, reading.clone());
        }
        query_samples.push(elapsed);
    }

    let mut sentence_engine = ImeEngine::new(EngineConfig {
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
    .expect("sentence benchmark engine");
    let mut sentence_samples = Vec::new();
    for (raw, _) in cases
        .iter()
        .filter(|(_, reading)| reading.contains(' '))
        .take(500)
    {
        sentence_engine.reset();
        let started = Instant::now();
        for key in raw.chars() {
            sentence_engine.process_key(key);
        }
        sentence_samples.push(started.elapsed());
    }

    let query_p50 = percentile(&mut query_samples.clone(), 50);
    let query_p95 = percentile(&mut query_samples.clone(), 95);
    let query_p99 = percentile(&mut query_samples, 99);
    let sentence_p50 = percentile(&mut sentence_samples.clone(), 50);
    let sentence_p95 = percentile(&mut sentence_samples, 95);
    println!(
        "{{\"entries\":{},\"bytes\":{},\"coldLoadNs\":{},\"warmLoadNs\":{},\"queryCount\":{},\"queryP50Ns\":{},\"queryP95Ns\":{},\"queryP99Ns\":{},\"sentenceCount\":500,\"sentenceP50Ns\":{},\"sentenceP95Ns\":{},\"slowestQueryNs\":{},\"slowestReading\":\"{}\"}}",
        cold_lexicon.entries.len(),
        bytes.len(),
        cold_load.as_nanos(),
        warm_load.as_nanos(),
        cases.len(),
        query_p50,
        query_p95,
        query_p99,
        sentence_p50,
        sentence_p95,
        slowest.0.as_nanos(),
        slowest.1
    );
}
