use std::{env, path::PathBuf, process::ExitCode};

fn main() -> ExitCode {
    match execute() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("AUDIT_ERROR={error}");
            ExitCode::from(1)
        }
    }
}

fn execute() -> Result<ExitCode, String> {
    let mut repo_root = None;
    let mut output = None;
    let mut reports = None;
    let mut allow_blocked = false;
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--repo-root" => repo_root = args.next().map(PathBuf::from),
            "--output" => output = args.next().map(PathBuf::from),
            "--reports" => reports = args.next().map(PathBuf::from),
            "--allow-blocked" => allow_blocked = true,
            "--help" => {
                println!("Usage: yinxing-source-auditor --repo-root <path> --output <path> --reports <path> [--allow-blocked]");
                return Ok(ExitCode::SUCCESS);
            }
            _ => return Err(format!("unknown argument: {arg}")),
        }
    }
    let repo_root = repo_root.ok_or("--repo-root is required")?;
    let output = output.ok_or("--output is required")?;
    let reports = reports.ok_or("--reports is required")?;
    let summary = yinxing_source_auditor::audit_and_write(&repo_root, &output, &reports)?;
    println!("AUDIT_FILE_COUNT={}", summary.file_count);
    println!("AUDIT_MANIFEST_SHA256={}", summary.manifest_sha256);
    println!("AUDIT_CONTRACT_SHA256={}", summary.contract_sha256);
    println!(
        "AUDIT_BLOCKING_REASONS={}",
        summary.blocking_reasons.join(",")
    );
    if !summary.blocking_reasons.is_empty() && !allow_blocked {
        Ok(ExitCode::from(2))
    } else {
        Ok(ExitCode::SUCCESS)
    }
}
