use std::fs;
use std::hint::black_box;
use std::path::PathBuf;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use ime_engine::{EngineConfig, ImeEngine};
use lexicon_core::{build_binary_lexicon, LexiconEntry};
use shuangpin_parser::{PhoneticParser, T9PinyinParser, T9SyllableIndex};

const ITERATIONS: usize = 5_000;
const LONG_INPUT_ITERATIONS: usize = 200;

fn percentile(samples: &mut [u64], percentile: usize) -> u64 {
    samples.sort_unstable();
    let index = samples.len().saturating_sub(1).saturating_mul(percentile) / 100;
    samples[index]
}

fn measure(iterations: usize, mut operation: impl FnMut()) -> (u64, u64, u64) {
    let mut samples = Vec::with_capacity(iterations);
    for _ in 0..iterations {
        let started = Instant::now();
        operation();
        samples.push(started.elapsed().as_nanos().min(u128::from(u64::MAX)) as u64);
    }
    let average = samples.iter().copied().sum::<u64>() / samples.len() as u64;
    let mut p50_samples = samples.clone();
    let p50 = percentile(&mut p50_samples, 50);
    let p95 = percentile(&mut samples, 95);
    (average, p50, p95)
}

fn entry(text: &str, reading: &str, frequency: u64) -> LexiconEntry {
    LexiconEntry::new(
        text.to_owned(),
        reading.to_owned(),
        reading.split_whitespace().map(str::to_owned).collect(),
        frequency,
        vec!["t9-benchmark".to_owned()],
    )
}

fn benchmark_lexicon() -> PathBuf {
    let entries = vec![
        entry("你", "ni", 100_000),
        entry("米", "mi", 60_000),
        entry("嗯", "ng", 30_000),
        entry("好", "hao", 99_000),
        entry("干", "gan", 40_000),
        entry("高", "gao", 70_000),
        entry("汉", "han", 50_000),
        entry("你好", "ni hao", 150_000),
    ];
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "pinyin9-stage3-benchmark-{}-{nanos}.lex",
        std::process::id()
    ));
    fs::write(
        &path,
        build_binary_lexicon(&entries, 3, 1).expect("benchmark lexicon"),
    )
    .expect("write benchmark lexicon");
    path
}

fn main() {
    let index_iterations = 100usize;
    let index_started = Instant::now();
    let mut index_nodes = 0usize;
    for _ in 0..index_iterations {
        let index = black_box(T9SyllableIndex::build());
        index_nodes = index.node_count();
        black_box(index);
    }
    let index_average_ns = index_started.elapsed().as_nanos() / index_iterations as u128;

    let mut parser = T9PinyinParser::new();
    let (single_average, single_p50, single_p95) = measure(ITERATIONS, || {
        parser.reset();
        black_box(parser.process_str("64"));
    });
    let (collision_average, collision_p50, collision_p95) = measure(ITERATIONS, || {
        parser.reset();
        black_box(parser.process_str("64426"));
    });
    let long_digits = "6".repeat(64);
    let (long_average, long_p50, long_p95) = measure(LONG_INPUT_ITERATIONS, || {
        parser.reset();
        black_box(parser.process_str(&long_digits));
    });
    let (delete_average, delete_p50, delete_p95) = measure(ITERATIONS, || {
        parser.reset();
        parser.process_str("64426");
        for _ in 0..5 {
            black_box(parser.backspace());
        }
    });
    let (switch_average, switch_p50, switch_p95) = measure(ITERATIONS, || {
        parser.reset();
        let result = parser.process_str("64");
        let mut combinations = vec![result.current_pinyin];
        combinations.extend(result.pinyin_combinations);
        let index = combinations
            .iter()
            .position(|value| value == "ni")
            .expect("ni combination");
        black_box(parser.select_pinyin_combination(index).expect("selection"));
    });

    let lexicon_path = benchmark_lexicon();
    let mut engine = ImeEngine::new(EngineConfig {
        scheme_id: "pinyin-9".to_owned(),
        lexicon_path: Some(lexicon_path.to_string_lossy().into_owned()),
        code_table_bundle_path: None,
        user_lexicon_path: None,
        code_table_action_fixture_path: None,
        code_table_action_fixture_sha256: None,
        candidate_page_size: 20,
        quanpin_features: Default::default(),
        quanpin_context_reranking: Default::default(),
    })
    .expect("benchmark engine");
    let (candidate_average, candidate_p50, candidate_p95) = measure(ITERATIONS, || {
        engine.reset();
        for digit in "64426".chars() {
            black_box(engine.process_key(digit));
        }
    });
    let candidate = engine.current_state();
    assert!(candidate.candidates.iter().any(|item| item.text == "你好"));
    let _ = fs::remove_file(&lexicon_path);

    println!(
        "{{\"iterations\":{ITERATIONS},\"longInputIterations\":{LONG_INPUT_ITERATIONS},\"indexBuildAverageNs\":{index_average_ns},\"indexNodes\":{index_nodes},\"singleInput\":{{\"averageNs\":{single_average},\"p50Ns\":{single_p50},\"p95Ns\":{single_p95}}},\"collisionInput\":{{\"averageNs\":{collision_average},\"p50Ns\":{collision_p50},\"p95Ns\":{collision_p95}}},\"longInput64\":{{\"averageNs\":{long_average},\"p50Ns\":{long_p50},\"p95Ns\":{long_p95}}},\"deleteRecovery\":{{\"averageNs\":{delete_average},\"p50Ns\":{delete_p50},\"p95Ns\":{delete_p95}}},\"combinationSwitch\":{{\"averageNs\":{switch_average},\"p50Ns\":{switch_p50},\"p95Ns\":{switch_p95}}},\"candidateRefresh64426\":{{\"averageNs\":{candidate_average},\"p50Ns\":{candidate_p50},\"p95Ns\":{candidate_p95}}}}}"
    );
}
