use std::path::PathBuf;

use lexicon_core::{
    build_binary_lexicon, build_binary_lexicon_with_source_order, load_binary_lexicon,
    BinaryLexicon,
};

use crate::args::InputFormat;
use crate::error::BuildError;
use crate::flypy_table::FlypyTableImporter;
use crate::parser::{parse_source_files, ParseStats};

pub const BUILDER_VERSION: u32 = 1;

#[derive(Clone, Debug)]
pub struct BuildResult {
    pub bytes: Vec<u8>,
    pub loaded: BinaryLexicon,
    pub stats: ParseStats,
}

pub fn build_from_sources(
    inputs: &[PathBuf],
    lexicon_version: u32,
    builder_version: u32,
    input_format: InputFormat,
) -> Result<BuildResult, BuildError> {
    let parsed = match input_format {
        InputFormat::PinyinTsv => parse_source_files(inputs)?,
        InputFormat::FlypyTable => FlypyTableImporter::new().import_files(inputs)?,
    };
    let bytes = match input_format {
        InputFormat::PinyinTsv => {
            build_binary_lexicon(&parsed.entries, lexicon_version, builder_version)?
        }
        InputFormat::FlypyTable => build_binary_lexicon_with_source_order(
            &parsed.entries,
            lexicon_version,
            builder_version,
        )?,
    };
    let loaded = load_binary_lexicon(&bytes)?;
    Ok(BuildResult {
        bytes,
        loaded,
        stats: parsed.stats,
    })
}
