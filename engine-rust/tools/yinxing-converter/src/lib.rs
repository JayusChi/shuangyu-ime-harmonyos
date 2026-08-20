pub mod bundle;
pub mod classification;
pub mod contract;
pub mod deterministic;
pub mod error;
pub mod input;
pub mod json;
pub mod model;
pub mod parser;
pub mod report;
pub mod sha256;
pub mod unicode_validation;
pub mod version;

use std::path::{Path, PathBuf};

use code_table_runtime::CodeTableBundle;

use crate::error::{ConverterError, ErrorCode, Result};
use crate::model::BuildResult;

#[derive(Clone, Debug)]
pub struct BuildOptions {
    pub contract_path: PathBuf,
    pub source_manifest_path: PathBuf,
    pub command_policy_path: PathBuf,
    pub sanitized_configuration_path: PathBuf,
    pub source_root: PathBuf,
    pub output_directory: PathBuf,
}

pub fn build(options: &BuildOptions) -> Result<BuildResult> {
    let contract = contract::load_and_validate(
        &options.contract_path,
        &options.source_manifest_path,
        &options.command_policy_path,
        &options.sanitized_configuration_path,
    )?;
    let before = input::preflight_all(&options.source_root, &contract)?;
    let mut categories = parser::parse_all(&before, &contract)?;
    classification::account_conflicts(&mut categories);
    let artifacts = bundle::build_artifacts(&categories, &contract)?;
    deterministic::install_output(
        &options.output_directory,
        &options.source_root,
        &artifacts.files,
    )?;
    let after = input::preflight_all(&options.source_root, &contract)?;
    if before
        .iter()
        .zip(after.iter())
        .any(|(left, right)| left.spec != right.spec || left.bytes != right.bytes)
    {
        return Err(ConverterError::new(
            ErrorCode::Integrity,
            "authoritative sources changed during build",
        ));
    }
    Ok(artifacts.result)
}

pub fn verify_bundle(path: &Path) -> Result<CodeTableBundle> {
    CodeTableBundle::load_file(path).map_err(|error| {
        ConverterError::new(ErrorCode::Integrity, format!("bundle_verify:{error}"))
    })
}
