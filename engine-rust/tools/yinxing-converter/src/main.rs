mod cli;

use yinxing_converter::version::CONVERTER_VERSION;

fn main() {
    let result = run();
    if let Err(error) = result {
        eprintln!("{error}");
        std::process::exit(error.code.exit_code());
    }
}

fn run() -> yinxing_converter::error::Result<()> {
    match cli::parse(std::env::args())? {
        cli::Command::Version => println!("{CONVERTER_VERSION}"),
        cli::Command::Build(options) => {
            let output = options.output_directory.clone();
            let result = yinxing_converter::build(&options)?;
            println!("CONVERTER_VERSION={CONVERTER_VERSION}");
            println!("OUTPUT_DIRECTORY={}", output.display());
            println!("BUNDLE_FILE={}", cli::bundle_path(output).display());
            println!("BUNDLE_BYTES={}", result.bundle_bytes);
            println!("BUNDLE_CONTENT_SHA256={}", result.bundle_content_sha256);
            println!("BUNDLE_SHA256={}", result.bundle_sha256);
            println!("ACCEPTED_RECORDS={}", result.statistics.accepted);
            println!("REJECTED_RECORDS={}", result.statistics.rejected);
            println!("DEFERRED_RECORDS={}", result.statistics.deferred);
        }
        cli::Command::Verify(path) => {
            let bundle = yinxing_converter::verify_bundle(&path)?;
            let metadata = bundle.production_metadata.ok_or_else(|| {
                yinxing_converter::error::ConverterError::new(
                    yinxing_converter::error::ErrorCode::Integrity,
                    "verified bundle is not production format",
                )
            })?;
            println!("BUNDLE_ID={}", bundle.bundle_id);
            println!("CONVERTER_VERSION={}", metadata.converter_version);
            println!("CATEGORY_COUNT={}", bundle.categories.len());
            println!("USER_RULES_PARSED={}", bundle.user_rules.is_some());
        }
        cli::Command::Compare(left, right) => {
            let files = yinxing_converter::deterministic::compare_directories(&left, &right)?;
            println!("DETERMINISTIC_FILES={}", files.len());
            for (path, bytes, hash) in files {
                println!("FILE={path} BYTES={bytes} SHA256={hash}");
            }
        }
    }
    Ok(())
}
