use std::env;
use std::time::Instant;

use ime_engine::{EngineConfig, ImeEngine};

fn main() {
    let mut args = env::args().skip(1);
    let lexicon_path = args
        .next()
        .expect("usage: quanpin_runtime_baseline <production.lex> [rounds]");
    let rounds = args
        .next()
        .map(|value| value.parse::<usize>().expect("rounds must be an integer"))
        .unwrap_or(100);
    let inputs = [
        "nihao",
        "zhongguo",
        "jinwantiantianqihenhao",
        "womenshiyongshitiannaojixingshuruxingnengceshi",
    ];
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "quanpin".to_owned(),
        lexicon_path: Some(lexicon_path),
        candidate_page_size: 50,
        ..EngineConfig::default()
    })
    .expect("quanpin engine");

    let started = Instant::now();
    let mut keys = 0usize;
    let mut failures = 0usize;
    let mut automatic_commits = 0usize;
    let mut ascii_commits = 0usize;
    let mut key_latencies_micros = Vec::<u128>::new();
    for input in inputs {
        let input_started = Instant::now();
        let mut input_keys = 0usize;
        for _ in 0..rounds {
            engine.reset();
            for key in input.chars() {
                let key_started = Instant::now();
                let result = engine.process_key(key);
                key_latencies_micros.push(key_started.elapsed().as_micros());
                keys += 1;
                input_keys += 1;
                if !result.success {
                    failures += 1;
                }
                if !result.commit_text.is_empty() {
                    automatic_commits += 1;
                    if result.commit_text.is_ascii() {
                        ascii_commits += 1;
                    }
                }
            }
        }
        let input_elapsed = input_started.elapsed();
        println!(
            "input_len={} keys={input_keys} elapsed_ms={} us_per_key={:.3}",
            input.len(),
            input_elapsed.as_millis(),
            input_elapsed.as_secs_f64() * 1_000_000.0 / input_keys as f64
        );
    }
    let elapsed = started.elapsed();
    let micros_per_key = elapsed.as_secs_f64() * 1_000_000.0 / keys as f64;
    key_latencies_micros.sort_unstable();
    let percentile = |percent: usize| -> u128 {
        let index = ((key_latencies_micros.len() - 1) * percent).div_ceil(100);
        key_latencies_micros[index]
    };
    println!(
        "quanpin_runtime keys={keys} failures={failures} automatic_commits={automatic_commits} \
         ascii_commits={ascii_commits} elapsed_ms={} us_per_key={micros_per_key:.3} \
         p50_us={} p95_us={}",
        elapsed.as_millis(),
        percentile(50),
        percentile(95)
    );
}
