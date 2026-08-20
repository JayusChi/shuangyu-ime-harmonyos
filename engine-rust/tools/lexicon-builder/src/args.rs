use std::path::PathBuf;

use crate::error::BuildError;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Command {
    Build(BuildConfig),
    Verify(PathBuf),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BuildConfig {
    pub inputs: Vec<PathBuf>,
    pub output: PathBuf,
    pub lexicon_version: u32,
    pub input_format: InputFormat,
    pub strict: bool,
    pub verify: bool,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum InputFormat {
    #[default]
    PinyinTsv,
    FlypyTable,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Options {
    pub command: Command,
}

impl Options {
    pub fn parse<I>(args: I) -> Result<Self, BuildError>
    where
        I: IntoIterator<Item = String>,
    {
        let mut inputs = Vec::new();
        let mut output = None;
        let mut lexicon_version = None;
        let mut input_format = InputFormat::default();
        let mut strict = true;
        let mut verify = false;
        let mut verify_path = None;

        let mut iter = args.into_iter();
        while let Some(arg) = iter.next() {
            match arg.as_str() {
                "--input" => inputs.push(PathBuf::from(next_value(&mut iter, "--input")?)),
                "--output" => output = Some(PathBuf::from(next_value(&mut iter, "--output")?)),
                "--lexicon-version" => {
                    let raw = next_value(&mut iter, "--lexicon-version")?;
                    let parsed = raw.parse::<u32>().map_err(|_| {
                        BuildError::Argument(format!("invalid lexicon version: {raw}"))
                    })?;
                    lexicon_version = Some(parsed);
                }
                "--input-format" => {
                    let raw = next_value(&mut iter, "--input-format")?;
                    input_format = match raw.as_str() {
                        "pinyin-tsv" => InputFormat::PinyinTsv,
                        "flypy-table" => InputFormat::FlypyTable,
                        _ => {
                            return Err(BuildError::Argument(format!(
                                "invalid input format: {raw}; expected pinyin-tsv or flypy-table"
                            )))
                        }
                    };
                }
                "--strict" => strict = true,
                "--no-strict" => strict = false,
                "--verify" => {
                    if let Some(next) = iter.next() {
                        if next.starts_with("--") {
                            return Err(BuildError::Argument(format!(
                                "--verify expected a path or no following option, got {next}"
                            )));
                        }
                        verify_path = Some(PathBuf::from(next));
                    } else {
                        verify = true;
                    }
                }
                "--help" | "-h" => return Err(BuildError::Argument(usage())),
                other => return Err(BuildError::Argument(format!("unknown argument: {other}"))),
            }
        }

        if let Some(path) = verify_path {
            if !inputs.is_empty() || output.is_some() || lexicon_version.is_some() {
                return Err(BuildError::Argument(
                    "--verify <path> cannot be combined with build arguments".to_owned(),
                ));
            }
            return Ok(Self {
                command: Command::Verify(path),
            });
        }

        if inputs.is_empty() {
            return Err(BuildError::Argument("missing --input".to_owned()));
        }
        let output = output.ok_or_else(|| BuildError::Argument("missing --output".to_owned()))?;
        let lexicon_version = lexicon_version
            .ok_or_else(|| BuildError::Argument("missing --lexicon-version".to_owned()))?;
        if !strict {
            return Err(BuildError::Argument(
                "--no-strict is reserved; stage 6 builder always runs in strict mode".to_owned(),
            ));
        }

        Ok(Self {
            command: Command::Build(BuildConfig {
                inputs,
                output,
                lexicon_version,
                input_format,
                strict,
                verify,
            }),
        })
    }
}

fn next_value<I>(iter: &mut I, name: &str) -> Result<String, BuildError>
where
    I: Iterator<Item = String>,
{
    iter.next()
        .ok_or_else(|| BuildError::Argument(format!("missing value for {name}")))
}

fn usage() -> String {
    "usage: lexicon-builder --input <source> [--input <source> ...] --output <lex> --lexicon-version <n> [--input-format pinyin-tsv|flypy-table] [--strict] [--verify]\n       lexicon-builder --verify <lex>".to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_build_arguments() {
        let options = Options::parse([
            "--input".to_owned(),
            "a.tsv".to_owned(),
            "--output".to_owned(),
            "a.lex".to_owned(),
            "--lexicon-version".to_owned(),
            "1".to_owned(),
            "--strict".to_owned(),
        ])
        .unwrap();

        assert_eq!(
            options,
            Options {
                command: Command::Build(BuildConfig {
                    inputs: vec![PathBuf::from("a.tsv")],
                    output: PathBuf::from("a.lex"),
                    lexicon_version: 1,
                    input_format: InputFormat::PinyinTsv,
                    strict: true,
                    verify: false,
                })
            }
        );
    }

    #[test]
    fn parses_flypy_table_input_format() {
        let options = Options::parse([
            "--input".to_owned(),
            "table.txt".to_owned(),
            "--input-format".to_owned(),
            "flypy-table".to_owned(),
            "--output".to_owned(),
            "table.lex".to_owned(),
            "--lexicon-version".to_owned(),
            "1".to_owned(),
        ])
        .unwrap();

        assert!(matches!(
            options.command,
            Command::Build(BuildConfig {
                input_format: InputFormat::FlypyTable,
                ..
            })
        ));
    }

    #[test]
    fn parses_verify_arguments() {
        assert_eq!(
            Options::parse(["--verify".to_owned(), "a.lex".to_owned()]).unwrap(),
            Options {
                command: Command::Verify(PathBuf::from("a.lex"))
            }
        );
    }
}
