use std::time::Instant;

use shuangpin_parser::{PhoneticParser, QuanpinParser};

fn main() {
    const CASES: [&str; 8] = [
        "ni",
        "nihao",
        "zhongguo",
        "zhon",
        "xian",
        "xi'an",
        "shurufa",
        "xianxianxianxianxianxian",
    ];
    const ROUNDS: usize = 20_000;

    let started = Instant::now();
    let mut parsed = 0usize;
    let mut parser = QuanpinParser::new();
    for _ in 0..ROUNDS {
        for input in CASES {
            parser.reset();
            parser.process_str(input);
            parsed += 1;
        }
    }
    let elapsed = started.elapsed();
    let micros_per_parse = elapsed.as_secs_f64() * 1_000_000.0 / parsed as f64;
    println!(
        "quanpin_stage2 parses={parsed} elapsed_ms={} us_per_parse={micros_per_parse:.3}",
        elapsed.as_millis()
    );
}
