use std::time::Instant;

use shuangpin_parser::{PhoneticParser, QuanpinParser};

const SAMPLES: usize = 1_000;

fn percentile(values: &mut [u128], percentile: usize) -> u128 {
    values.sort_unstable();
    let index = (values.len().saturating_sub(1) * percentile) / 100;
    values[index]
}

fn input_of_len(len: usize) -> String {
    let base = "nihaozhongguotianqishijie";
    base.repeat(len.div_ceil(base.len()))[..len].to_owned()
}

fn main() {
    println!(
        "length,samples,p50_us,p95_us,p99_us,max_retained_states,max_cached_states,max_backspace_generated_states"
    );
    for len in [32usize, 64, 128] {
        let input = input_of_len(len);
        let mut durations = Vec::with_capacity(SAMPLES);
        let mut max_retained = 0usize;
        let mut max_cached = 0usize;
        let mut max_backspace_generated = 0usize;
        for _ in 0..SAMPLES {
            let mut parser = QuanpinParser::new();
            let started = Instant::now();
            for key in input.chars() {
                parser.process_key(key);
                max_retained = max_retained.max(parser.lattice_stats().retained_states);
            }
            durations.push(started.elapsed().as_nanos());
            let stats = parser.lattice_stats();
            max_cached = max_cached.max(stats.reused_prefix_states);
            for _ in 0..(len / 4) {
                parser.backspace();
                max_backspace_generated =
                    max_backspace_generated.max(parser.lattice_stats().generated_states);
            }
        }
        let mut p50_values = durations.clone();
        let mut p95_values = durations.clone();
        let p50 = percentile(&mut p50_values, 50) / 1_000;
        let p95 = percentile(&mut p95_values, 95) / 1_000;
        let p99 = percentile(&mut durations, 99) / 1_000;
        println!(
            "{len},{SAMPLES},{p50},{p95},{p99},{max_retained},{max_cached},{max_backspace_generated}"
        );
    }
}
