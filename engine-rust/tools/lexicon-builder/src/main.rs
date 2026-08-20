use std::process;

use lexicon_builder::args::{self, Command, Options};
use lexicon_builder::build::{self, build_from_sources, BUILDER_VERSION};
use lexicon_builder::error::BuildError;
use lexicon_builder::writer::write_atomically;
use lexicon_core::load_binary_lexicon;

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        process::exit(1);
    }
}

fn run() -> Result<(), BuildError> {
    let options = Options::parse(std::env::args().skip(1))?;
    match options.command {
        Command::Build(config) => {
            let result = build_from_sources(
                &config.inputs,
                config.lexicon_version,
                BUILDER_VERSION,
                config.input_format,
            )?;
            if let Some(parent) = config.output.parent() {
                std::fs::create_dir_all(parent).map_err(|source| BuildError::OutputIo {
                    path: parent.to_path_buf(),
                    source,
                })?;
            }
            write_atomically(&config.output, &result.bytes)?;
            print_build_summary(&config, &result);
            if config.verify {
                let bytes =
                    std::fs::read(&config.output).map_err(|source| BuildError::InputIo {
                        path: config.output.clone(),
                        source,
                    })?;
                let loaded = load_binary_lexicon(&bytes)?;
                println!(
                    "Verification succeeded: entries={}, pinyinKeys={}, checksum={:08x}",
                    loaded.entries.len(),
                    loaded.index.len(),
                    loaded.header.payload_checksum
                );
            }
        }
        Command::Verify(path) => {
            let bytes = std::fs::read(&path).map_err(|source| BuildError::InputIo {
                path: path.clone(),
                source,
            })?;
            let loaded = load_binary_lexicon(&bytes)?;
            println!("Lexicon verification succeeded");
            println!("Input: {}", path.display());
            println!("Entries: {}", loaded.entries.len());
            println!("Pinyin keys: {}", loaded.index.len());
            println!(
                "Format version: {}.{}",
                loaded.header.format_major, loaded.header.format_minor
            );
            println!("Lexicon version: {}", loaded.header.lexicon_version);
            println!("Checksum: {:08x}", loaded.header.payload_checksum);
        }
    }
    Ok(())
}

fn print_build_summary(config: &args::BuildConfig, result: &build::BuildResult) {
    println!("Lexicon build succeeded");
    println!("Input rows: {}", result.stats.input_rows);
    println!("Accepted rows: {}", result.stats.accepted_rows);
    println!("Merged duplicates: {}", result.stats.merged_duplicates);
    println!("Entries written: {}", result.loaded.entries.len());
    println!("Pinyin keys: {}", result.loaded.index.len());
    println!("Output bytes: {}", result.bytes.len());
    println!(
        "Format version: {}.{}",
        result.loaded.header.format_major, result.loaded.header.format_minor
    );
    println!("Lexicon version: {}", config.lexicon_version);
    println!("Checksum: {:08x}", result.loaded.header.payload_checksum);
    println!("Output: {}", config.output.display());
}
