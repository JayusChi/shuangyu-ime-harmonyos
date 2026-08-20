use ime_engine::{expansion_paths, FuzzyOption, QuanpinFeatureConfig};
use shuangpin_parser::QuanpinParser;

fn main() {
    let mut args = std::env::args().skip(1);
    let raw = args
        .next()
        .expect("usage: quanpin_feature_inspect <raw> [fuzzy-option ...]");
    let fuzzy = args
        .map(|value| FuzzyOption::parse(&value).expect("known fuzzy option"))
        .collect::<Vec<_>>();
    let parsed = QuanpinParser::new().process_str(&raw);
    println!(
        "parse={:?} intent={:?} pending={:?} current={}",
        parsed.status, parsed.query_intent, parsed.pending_code, parsed.current_pinyin
    );
    let (paths, stats) = expansion_paths(&raw, &QuanpinFeatureConfig::new(true, fuzzy));
    println!("stats={stats:?}");
    for (index, path) in paths.iter().enumerate() {
        println!(
            "{index}\t{:?}\t{}\t{}",
            path.kind,
            path.raw,
            path.syllables.join("'")
        );
    }
}
