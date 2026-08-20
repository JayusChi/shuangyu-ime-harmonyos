use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process;
use std::time::Instant;

use code_table_fixture_generator::{
    build_bundle, generate_fixture, verify_bundle, BundleBuild, FixtureError, DEFAULT_BUNDLE_NAME,
};

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        process::exit(1);
    }
}

fn run() -> Result<(), FixtureError> {
    let arguments = env::args().skip(1).collect::<Vec<_>>();
    match arguments.as_slice() {
        [command, output] if command == "generate" => {
            let start = Instant::now();
            let report = generate_fixture(Path::new(output))?;
            println!("FIXTURE_GENERATE_RESULT=PASS");
            println!("MANIFEST={}", report.manifest_path.display());
            println!("MANIFEST_SHA256={}", report.manifest_sha256);
            println!(
                "NORMAL_ENTRIES={}",
                report
                    .category_counts
                    .iter()
                    .map(|value| value.1)
                    .sum::<usize>()
            );
            println!("GUIDE_ENTRIES={}", report.guide_count);
            println!("GENERATE_MILLIS={}", start.elapsed().as_millis());
        }
        [command, manifest, output] if command == "build" => {
            ensure_fixture_name(Path::new(output))?;
            let start = Instant::now();
            let build = build_bundle(Path::new(manifest))?;
            write_build(Path::new(output), &build)?;
            print_build(&build, start.elapsed().as_millis());
        }
        [command, bundle] if command == "verify" => {
            let path = Path::new(bundle);
            let bytes = fs::read(path).map_err(|source| FixtureError::io(path, source))?;
            let metadata = verify_bundle(&bytes)?;
            println!("FIXTURE_BUNDLE_VERIFY_RESULT=PASS");
            println!("BUNDLE_SHA256={}", metadata.bundle_sha256);
            println!("NORMAL_ENTRIES={}", metadata.normal_entry_count);
            println!("GUIDE_ENTRIES={}", metadata.guide_entry_count);
        }
        [command, output] if command == "all" => {
            let output = PathBuf::from(output);
            let generate_start = Instant::now();
            let report = generate_fixture(&output)?;
            let generate_millis = generate_start.elapsed().as_millis();
            let bundle_path = output.join("binary").join(DEFAULT_BUNDLE_NAME);
            let build_start = Instant::now();
            let build = build_bundle(&report.manifest_path)?;
            write_build(&bundle_path, &build)?;
            verify_bundle(&build.bytes)?;
            println!("FIXTURE_ALL_RESULT=PASS");
            println!("MANIFEST={}", report.manifest_path.display());
            println!("MANIFEST_SHA256={}", report.manifest_sha256);
            println!("GENERATE_MILLIS={generate_millis}");
            print_build(&build, build_start.elapsed().as_millis());
        }
        _ => {
            return Err(FixtureError::Builder(
                "usage: code-table-fixture-generator generate <dir> | build <manifest> <fixture.bundle> | verify <fixture.bundle> | all <dir>".into(),
            ));
        }
    }
    Ok(())
}

fn ensure_fixture_name(path: &Path) -> Result<(), FixtureError> {
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    if !["fixture", "test", "synthetic"]
        .iter()
        .any(|marker| name.contains(marker))
    {
        return Err(FixtureError::diagnostic(
            "CTF_OUTPUT_NAME_UNSAFE",
            path.to_string_lossy(),
            0,
            "output",
            "test bundle filename must contain fixture, test, or synthetic",
        ));
    }
    Ok(())
}

fn write_build(path: &Path, build: &BundleBuild) -> Result<(), FixtureError> {
    ensure_fixture_name(path)?;
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent).map_err(|source| FixtureError::io(parent, source))?;
    fs::write(path, &build.bytes).map_err(|source| FixtureError::io(path, source))?;
    let table_root = parent.join("tables");
    fs::create_dir_all(&table_root).map_err(|source| FixtureError::io(&table_root, source))?;
    for table in &build.tables {
        let table_path = table_root.join(format!("{}.fixture.lex", table.id));
        fs::write(&table_path, &table.bytes)
            .map_err(|source| FixtureError::io(&table_path, source))?;
    }
    Ok(())
}

fn print_build(build: &BundleBuild, elapsed_millis: u128) {
    println!("FIXTURE_BUNDLE_BUILD_RESULT=PASS");
    println!("FORMAT_VERSION={}", build.metadata.format_version);
    println!("BUNDLE_ID={}", build.metadata.bundle_id);
    println!("CATEGORY_ORDER={}", build.metadata.category_order.join(","));
    println!("NORMAL_ENTRIES={}", build.metadata.normal_entry_count);
    println!("GUIDE_ENTRIES={}", build.metadata.guide_entry_count);
    println!("BUILD_INPUT_SHA256={}", build.metadata.build_input_sha256);
    println!("CONTENT_SHA256={}", build.metadata.content_sha256);
    println!("BUNDLE_SHA256={}", build.metadata.bundle_sha256);
    println!("BUNDLE_BYTES={}", build.metadata.bundle_bytes);
    println!("BUILD_MILLIS={elapsed_millis}");
}
