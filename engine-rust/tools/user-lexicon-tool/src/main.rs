use std::path::{Path, PathBuf};
use std::process;

use user_lexicon::{parse_user_lexicon_file, save_snapshot_atomic, UserLexiconSnapshot};

enum Command {
    Validate(PathBuf),
    Import(PathBuf, PathBuf),
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    match parse_args(std::env::args().skip(1).collect())? {
        Command::Validate(source) => {
            let parsed = parse_user_lexicon_file(&source)?;
            let snapshot = parsed.into_snapshot();
            print_summary("Validation succeeded", &source, None, &snapshot);
        }
        Command::Import(source, destination) => {
            let parsed = parse_user_lexicon_file(&source)?;
            let snapshot = parsed.into_snapshot();
            save_snapshot_atomic(&destination, &snapshot)?;
            print_summary("Import succeeded", &source, Some(&destination), &snapshot);
        }
    }
    Ok(())
}

fn parse_args(args: Vec<String>) -> Result<Command, String> {
    match args.as_slice() {
        [command, source] if command == "validate" => {
            Ok(Command::Validate(PathBuf::from(source)))
        }
        [command, source, destination] if command == "import" => Ok(Command::Import(
            PathBuf::from(source),
            PathBuf::from(destination),
        )),
        _ => Err(
            "usage: user-lexicon-tool validate <source-file>\n       user-lexicon-tool import <source-file> <destination-file>"
                .to_owned(),
        ),
    }
}

fn print_summary(
    title: &str,
    source: &Path,
    destination: Option<&Path>,
    snapshot: &UserLexiconSnapshot,
) {
    let stats = snapshot.stats();
    println!("{title}");
    println!("Source: {}", source.display());
    if let Some(destination) = destination {
        println!("Destination: {}", destination.display());
    }
    println!("Accepted rules: {}", stats.accepted);
    println!("Effective rules: {}", stats.effective);
    println!("Added: {}", stats.added);
    println!("Deleted: {}", stats.deleted);
    println!("Fixed: {}", stats.fixed);
    println!("Positioned: {}", stats.positioned);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_validate_and_import_commands() {
        assert!(matches!(
            parse_args(vec!["validate".to_owned(), "a.txt".to_owned()]),
            Ok(Command::Validate(_))
        ));
        assert!(matches!(
            parse_args(vec![
                "import".to_owned(),
                "a.txt".to_owned(),
                "b.txt".to_owned()
            ]),
            Ok(Command::Import(_, _))
        ));
        assert!(parse_args(Vec::new()).is_err());
    }
}
