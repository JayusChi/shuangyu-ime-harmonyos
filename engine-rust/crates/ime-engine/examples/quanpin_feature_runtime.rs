use std::time::Instant;

use ime_engine::{EngineConfig, ImeEngine, QuanpinFeatureConfig};

fn main() {
    let mut args = std::env::args().skip(1);
    let lexicon = args
        .next()
        .expect("usage: quanpin_feature_runtime <production.lex> <raw>");
    let raw = args
        .next()
        .expect("usage: quanpin_feature_runtime <production.lex> <raw>");
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
    let started = Instant::now();
    let mut result = engine.current_state();
    for key in raw.chars() {
        result = engine.process_key(key);
    }
    let mut candidates = result.candidates;
    while result.has_next_page {
        result = engine.next_candidate_page().expect("page");
        candidates.extend(result.candidates.clone());
    }
    println!("elapsedMicros={}", started.elapsed().as_micros());
    println!("stats={:?}", engine.last_quanpin_expansion_stats());
    for (index, candidate) in candidates.iter().enumerate() {
        println!(
            "{index}\t{}\t{}\t{}\t{}\t{}",
            candidate.text,
            candidate.reading,
            candidate.source,
            candidate.consumed_raw_len,
            candidate.id
        );
    }
}
