use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use candidate_query::{CandidateOrder, CandidateQueryEngine, QueryConfig, QueryMode, QueryRequest};
use lexicon_core::load_binary_lexicon;

#[test]
fn cli_builds_and_verifies_lexicon() {
    let dir = temp_dir("builds_and_verifies");
    fs::create_dir_all(&dir).unwrap();
    let input = dir.join("source.tsv");
    let output = dir.join("out.lex");
    fs::write(
        &input,
        "# test\n你\tni\t100\tcli\n你好\tNI   HAO\t200\tcli\n你好\tni hao\t50\textra\n",
    )
    .unwrap();

    let build = run_builder([
        "--input",
        input.to_str().unwrap(),
        "--output",
        output.to_str().unwrap(),
        "--lexicon-version",
        "1",
        "--strict",
    ]);
    assert!(
        build.status.success(),
        "stdout={}\nstderr={}",
        String::from_utf8_lossy(&build.stdout),
        String::from_utf8_lossy(&build.stderr)
    );
    let stdout = String::from_utf8_lossy(&build.stdout);
    assert!(stdout.contains("Lexicon build succeeded"));
    assert!(stdout.contains("Merged duplicates: 1"));
    assert!(output.exists());

    let verify = run_builder(["--verify", output.to_str().unwrap()]);
    assert!(verify.status.success());
    assert!(String::from_utf8_lossy(&verify.stdout).contains("Lexicon verification succeeded"));
}

#[test]
fn cli_reports_line_error_with_file_and_line() {
    let dir = temp_dir("reports_line_error");
    fs::create_dir_all(&dir).unwrap();
    let input = dir.join("invalid.tsv");
    let output = dir.join("out.lex");
    fs::write(&input, "输入法\tshu ru invalid\t1\tcli\n").unwrap();

    let result = run_builder([
        "--input",
        input.to_str().unwrap(),
        "--output",
        output.to_str().unwrap(),
        "--lexicon-version",
        "1",
    ]);
    assert!(!result.status.success());
    let stderr = String::from_utf8_lossy(&result.stderr);
    assert!(stderr.contains("invalid.tsv:1:"), "{stderr}");
    assert!(stderr.contains("word=\"输入法\""), "{stderr}");
    assert!(stderr.contains("pinyin=\"shu ru invalid\""), "{stderr}");
    assert!(stderr.contains("syllable index 3"), "{stderr}");
    assert!(!output.exists());
}

#[test]
fn cli_verify_rejects_corrupted_file() {
    let dir = temp_dir("rejects_corrupted");
    fs::create_dir_all(&dir).unwrap();
    let input = dir.join("source.tsv");
    let output = dir.join("out.lex");
    fs::write(&input, "你\tni\t1\tcli\n").unwrap();

    let build = run_builder([
        "--input",
        input.to_str().unwrap(),
        "--output",
        output.to_str().unwrap(),
        "--lexicon-version",
        "1",
    ]);
    assert!(build.status.success());

    let mut bytes = fs::read(&output).unwrap();
    let last = bytes.len() - 1;
    bytes[last] ^= 0x01;
    fs::write(&output, bytes).unwrap();

    let verify = run_builder(["--verify", output.to_str().unwrap()]);
    assert!(!verify.status.success());
    assert!(String::from_utf8_lossy(&verify.stderr).contains("checksum mismatch"));
}

#[test]
fn cli_build_is_byte_deterministic_for_equivalent_inputs() {
    let dir = temp_dir("deterministic");
    fs::create_dir_all(&dir).unwrap();

    let base = "你\tni\t100\tdet\n你好\tni hao\t200\tdet\n输入\tshu ru\t300\tdet\n";
    let reordered = "输入\tshu ru\t300\tdet\n你好\tni hao\t200\tdet\n你\tni\t100\tdet\n";
    let duplicates_a = "你好\tni hao\t10\tb\n你好\tNI   HAO\t20\ta\n";
    let duplicates_b = "你好\tNI   HAO\t20\ta\n你好\tni hao\t10\tb\n";
    let crlf = "你\tni\t100\tdet\r\n你好\tni hao\t200\tdet\r\n";
    let lf = "你\tni\t100\tdet\n你好\tni hao\t200\tdet\n";
    let normalized = "你好\t NI   HAO \t200\tdet\n";
    let canonical = "你好\tni hao\t200\tdet\n";

    assert_same_bytes(&dir, "same", base, base);
    assert_same_bytes(&dir, "reordered", base, reordered);
    assert_same_bytes(&dir, "duplicates", duplicates_a, duplicates_b);
    assert_same_bytes(&dir, "newlines", lf, crlf);
    assert_same_bytes(&dir, "normalized", canonical, normalized);
}

#[test]
fn cli_flypy_table_build_preserves_order_and_is_byte_deterministic() {
    let left_dir = temp_dir("flypy-left");
    let right_dir = temp_dir("flypy-right");
    fs::create_dir_all(&left_dir).unwrap();
    fs::create_dir_all(&right_dir).unwrap();
    let fixture = "第一词\tabz\n第二词\taba\n第三词\tabz\n第四词\tabc\n";

    let left = build_flypy_table(&left_dir, fixture);
    let right = build_flypy_table(&right_dir, fixture);
    let left_bytes = fs::read(&left).unwrap();
    let right_bytes = fs::read(&right).unwrap();
    assert_eq!(left_bytes.len(), right_bytes.len());
    assert_eq!(left_bytes, right_bytes);

    let loaded = load_binary_lexicon(&left_bytes).unwrap();
    assert_eq!(loaded.header.format_minor, 1);
    assert_eq!(
        source_order_words(&left_bytes, "abz"),
        vec!["第一词", "第三词"]
    );
    assert_eq!(
        source_order_words(&left_bytes, "ab"),
        vec!["第一词", "第二词", "第三词", "第四词"]
    );
    assert!(source_order_words(&left_bytes, "").is_empty());

    let reordered = build_flypy_table(
        &temp_dir("flypy-reordered"),
        "第二词\taba\n第一词\tabz\n第三词\tabz\n第四词\tabc\n",
    );
    let reordered_bytes = fs::read(reordered).unwrap();
    assert_ne!(left_bytes, reordered_bytes);
    assert_eq!(
        source_order_words(&reordered_bytes, "ab"),
        vec!["第二词", "第一词", "第三词", "第四词"]
    );
}

#[test]
fn cli_flypy_table_reports_path_line_and_invalid_code() {
    let dir = temp_dir("flypy-error");
    fs::create_dir_all(&dir).unwrap();
    let input = dir.join("invalid-table.txt");
    let output = dir.join("out.lex");
    fs::write(&input, "第一词\tabz\n第二词\tabz#固\n").unwrap();

    let result = run_builder([
        "--input",
        input.to_str().unwrap(),
        "--input-format",
        "flypy-table",
        "--output",
        output.to_str().unwrap(),
        "--lexicon-version",
        "1",
    ]);
    assert!(!result.status.success());
    let stderr = String::from_utf8_lossy(&result.stderr);
    assert!(stderr.contains("invalid-table.txt:2:"), "{stderr}");
    assert!(stderr.contains("invalid code"), "{stderr}");
    assert!(!output.exists());
}

#[test]
fn cli_flypy_table_uses_explicit_multi_source_order() {
    let dir = temp_dir("flypy-multi-source");
    fs::create_dir_all(&dir).unwrap();
    let first = dir.join("first.txt");
    let second = dir.join("second.txt");
    let output = dir.join("out.lex");
    fs::write(&first, "第一词\tabz\n第二词\taba\n").unwrap();
    fs::write(&second, "第三词\tabz\n第四词\tabc\n").unwrap();

    let result = run_builder([
        "--input",
        first.to_str().unwrap(),
        "--input",
        second.to_str().unwrap(),
        "--input-format",
        "flypy-table",
        "--output",
        output.to_str().unwrap(),
        "--lexicon-version",
        "1",
    ]);
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    assert_eq!(
        source_order_words(&fs::read(output).unwrap(), "ab"),
        vec!["第一词", "第二词", "第三词", "第四词"]
    );
}

fn run_builder<const N: usize>(args: [&str; N]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_lexicon-builder"))
        .args(args)
        .output()
        .unwrap()
}

fn assert_same_bytes(dir: &Path, name: &str, left: &str, right: &str) {
    let left_input = dir.join(format!("{name}-left.tsv"));
    let right_input = dir.join(format!("{name}-right.tsv"));
    let left_output = dir.join(format!("{name}-left.lex"));
    let right_output = dir.join(format!("{name}-right.lex"));
    fs::write(&left_input, left).unwrap();
    fs::write(&right_input, right).unwrap();

    let left_result = build_lexicon(&left_input, &left_output);
    assert!(
        left_result.status.success(),
        "{}",
        String::from_utf8_lossy(&left_result.stderr)
    );
    let right_result = build_lexicon(&right_input, &right_output);
    assert!(
        right_result.status.success(),
        "{}",
        String::from_utf8_lossy(&right_result.stderr)
    );

    assert_eq!(
        fs::read(&left_output).unwrap(),
        fs::read(&right_output).unwrap(),
        "{name} should build identical bytes"
    );
}

fn build_lexicon(input: &Path, output: &Path) -> std::process::Output {
    run_builder([
        "--input",
        input.to_str().unwrap(),
        "--output",
        output.to_str().unwrap(),
        "--lexicon-version",
        "1",
        "--strict",
    ])
}

fn build_flypy_table(dir: &Path, fixture: &str) -> PathBuf {
    fs::create_dir_all(dir).unwrap();
    let input = dir.join("source.txt");
    let output = dir.join("out.lex");
    fs::write(&input, fixture).unwrap();
    let result = run_builder([
        "--input",
        input.to_str().unwrap(),
        "--input-format",
        "flypy-table",
        "--output",
        output.to_str().unwrap(),
        "--lexicon-version",
        "1",
    ]);
    assert!(
        result.status.success(),
        "stdout={}\nstderr={}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );
    output
}

fn source_order_words(bytes: &[u8], code: &str) -> Vec<String> {
    let mut engine = CandidateQueryEngine::new(
        load_binary_lexicon(bytes).unwrap(),
        QueryConfig {
            default_page_size: 2,
            max_page_size: 2,
            max_candidates: 64,
            prefix_recall_limit: 128,
            prefix_snapshot_limit: 100,
            prefix_recall_strategy: candidate_query::PrefixRecallStrategy::GlobalTopK,
            max_prefix_index_records: 1,
            cache_capacity: 2,
        },
    );
    engine
        .query(
            QueryRequest::new("flypy-table", code, QueryMode::ExactOrPrefix, 2)
                .with_candidate_order(CandidateOrder::SourceOrder),
        )
        .unwrap()
        .candidates
        .into_iter()
        .map(|candidate| candidate.text)
        .collect()
}

fn temp_dir(name: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    std::env::temp_dir().join(format!(
        "lexicon-builder-{name}-{}-{nanos}",
        std::process::id()
    ))
}
