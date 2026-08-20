use std::collections::BTreeMap;
use std::path::PathBuf;

use yinxing_converter::bundle::BUNDLE_FILE_NAME;
use yinxing_converter::error::{ConverterError, ErrorCode, Result};
use yinxing_converter::BuildOptions;

pub enum Command {
    Version,
    Build(BuildOptions),
    Verify(PathBuf),
    Compare(PathBuf, PathBuf),
}

pub fn parse(arguments: impl IntoIterator<Item = String>) -> Result<Command> {
    let mut values = arguments.into_iter();
    let _program = values.next();
    let Some(command) = values.next() else {
        return Err(usage());
    };
    if command == "--version" || command == "version" {
        if values.next().is_some() {
            return Err(usage());
        }
        return Ok(Command::Version);
    }
    let tail = values.collect::<Vec<_>>();
    match command.as_str() {
        "build" => {
            let options = flags(tail)?;
            Ok(Command::Build(BuildOptions {
                contract_path: required_path(&options, "--contract")?,
                source_manifest_path: required_path(&options, "--source-manifest")?,
                command_policy_path: required_path(&options, "--command-policy")?,
                sanitized_configuration_path: required_path(&options, "--sanitized-configuration")?,
                source_root: required_path(&options, "--source-root")?,
                output_directory: required_path(&options, "--output")?,
            }))
        }
        "verify" => {
            let options = flags(tail)?;
            Ok(Command::Verify(required_path(&options, "--bundle")?))
        }
        "compare" => {
            let options = flags(tail)?;
            Ok(Command::Compare(
                required_path(&options, "--left")?,
                required_path(&options, "--right")?,
            ))
        }
        _ => Err(usage()),
    }
}

pub fn bundle_path(output: PathBuf) -> PathBuf {
    output.join(BUNDLE_FILE_NAME)
}

fn flags(values: Vec<String>) -> Result<BTreeMap<String, String>> {
    if !values.len().is_multiple_of(2) {
        return Err(usage());
    }
    let mut output = BTreeMap::new();
    for pair in values.chunks_exact(2) {
        if !pair[0].starts_with("--") || output.insert(pair[0].clone(), pair[1].clone()).is_some() {
            return Err(usage());
        }
    }
    Ok(output)
}

fn required_path(values: &BTreeMap<String, String>, flag: &str) -> Result<PathBuf> {
    values
        .get(flag)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .ok_or_else(usage)
}

fn usage() -> ConverterError {
    ConverterError::new(
        ErrorCode::Cli,
        "usage: yinxing-converter build --contract PATH --source-manifest PATH --command-policy PATH --sanitized-configuration PATH --source-root PATH --output DIR | verify --bundle FILE | compare --left DIR --right DIR | --version",
    )
}
