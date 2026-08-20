use std::fs;
use std::path::PathBuf;

fn main() {
    if let Err(error) = run() {
        eprintln!("candidate-baseline: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut args = std::env::args_os().skip(1);
    let command = args
        .next()
        .and_then(|value| value.into_string().ok())
        .ok_or_else(usage)?;
    match command.as_str() {
        "stable" => {
            let lexicon = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let bundle = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let output = args.next().map(PathBuf::from).ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            candidate_baseline::write_stable_files(&lexicon, &bundle, &output)
        }
        "performance" => {
            let lexicon = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let bundle = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let warmups = parse_usize(args.next(), "warmups")?;
            let samples = parse_usize(args.next(), "samples")?;
            if args.next().is_some() {
                return Err(usage());
            }
            print!(
                "{}",
                candidate_baseline::render_performance(&lexicon, &bundle, warmups, samples)?
            );
            Ok(())
        }
        "performance-page-size" => {
            let lexicon = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let bundle = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let page_size = parse_usize(args.next(), "page-size")?;
            let warmups = parse_usize(args.next(), "warmups")?;
            let samples = parse_usize(args.next(), "samples")?;
            if args.next().is_some() {
                return Err(usage());
            }
            print!(
                "{}",
                candidate_baseline::render_performance_for_page_size(
                    &lexicon, &bundle, page_size, warmups, samples
                )?
            );
            Ok(())
        }
        "stage3" => {
            let lexicon = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let warmups = parse_usize(args.next(), "warmups")?;
            let samples = parse_usize(args.next(), "samples")?;
            if args.next().is_some() {
                return Err(usage());
            }
            print!(
                "{}",
                candidate_baseline::render_stage3_report(&lexicon, warmups, samples)?
            );
            Ok(())
        }
        "stage5-learning" => {
            let lexicon = args.next().map(PathBuf::from).ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            print!(
                "{}",
                candidate_baseline::render_stage5_learning_report(&lexicon)?
            );
            Ok(())
        }
        "stage6-audit" => {
            let lexicon = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let bundle = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let cases = args.next().map(PathBuf::from).ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            print!(
                "{}",
                candidate_baseline::render_stage6_coverage_report(&lexicon, &bundle, &cases)?
            );
            Ok(())
        }
        "quanpin-create-dataset" => {
            let output = args.next().map(PathBuf::from).ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            println!("{}", candidate_baseline::create_quanpin_dataset(&output)?);
            Ok(())
        }
        "pinyin9-create-dataset" => {
            let quanpin_dataset = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let output = args.next().map(PathBuf::from).ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            println!(
                "{}",
                candidate_baseline::create_pinyin9_dataset(&quanpin_dataset, &output)?
            );
            Ok(())
        }
        "pinyin9-validate" => {
            let dataset = args.next().map(PathBuf::from).ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            print!(
                "{}",
                candidate_baseline::validate_pinyin9_dataset(&dataset)?
            );
            Ok(())
        }
        "pinyin9-freeze" => {
            let dataset = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let manifest = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let baseline_id = args
                .next()
                .and_then(|value| value.into_string().ok())
                .ok_or_else(usage)?;
            let frozen_at = args
                .next()
                .and_then(|value| value.into_string().ok())
                .ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            println!(
                "{}",
                candidate_baseline::freeze_pinyin9_dataset(
                    &dataset,
                    &manifest,
                    &baseline_id,
                    &frozen_at,
                )?
            );
            Ok(())
        }
        "pinyin9-implementation-freeze" => {
            let repo_root = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let dataset_manifest = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let lexicon = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let output = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let frozen_at = args
                .next()
                .and_then(|value| value.into_string().ok())
                .ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            println!(
                "{}",
                candidate_baseline::freeze_pinyin9_implementation(
                    &repo_root,
                    &dataset_manifest,
                    &lexicon,
                    &output,
                    &frozen_at,
                )?
            );
            Ok(())
        }
        "pinyin9-evaluate" => {
            let dataset = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let manifest = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let lexicon = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let results = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let failures = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let runs = parse_usize(args.next(), "runs")?;
            let mut split = None;
            let mut implementation_manifest = None;
            let mut repo_root = None;
            let mut receipt = None;
            while let Some(flag) = args.next().and_then(|value| value.into_string().ok()) {
                match flag.as_str() {
                    "--split" => {
                        split = Some(
                            args.next()
                                .and_then(|value| value.into_string().ok())
                                .ok_or_else(usage)?,
                        );
                    }
                    "--implementation-manifest" => {
                        implementation_manifest =
                            Some(args.next().map(PathBuf::from).ok_or_else(usage)?);
                    }
                    "--repo-root" => {
                        repo_root = Some(args.next().map(PathBuf::from).ok_or_else(usage)?);
                    }
                    "--receipt" => {
                        receipt = Some(args.next().map(PathBuf::from).ok_or_else(usage)?);
                    }
                    _ => return Err(format!("unknown pinyin9 evaluation option {flag:?}")),
                }
            }
            let split = split.ok_or_else(usage)?;
            println!(
                "{}",
                candidate_baseline::evaluate_pinyin9_dataset(
                    &candidate_baseline::Pinyin9EvaluationRequest {
                        dataset_dir: &dataset,
                        manifest_path: &manifest,
                        implementation_manifest_path: implementation_manifest.as_deref(),
                        repo_root: repo_root.as_deref(),
                        lexicon_path: &lexicon,
                        results_path: &results,
                        failures_path: &failures,
                        receipt_path: receipt.as_deref(),
                        runs,
                        split: &split,
                    },
                )?
            );
            Ok(())
        }
        "quanpin-validate" => {
            let dataset = args.next().map(PathBuf::from).ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            print!(
                "{}",
                candidate_baseline::validate_quanpin_dataset(&dataset)?
            );
            Ok(())
        }
        "quanpin-freeze" => {
            let dataset = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let manifest = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let baseline_id = args
                .next()
                .and_then(|value| value.into_string().ok())
                .ok_or_else(usage)?;
            let frozen_at = args
                .next()
                .and_then(|value| value.into_string().ok())
                .ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            println!(
                "{}",
                candidate_baseline::freeze_quanpin_dataset(
                    &dataset,
                    &manifest,
                    &baseline_id,
                    &frozen_at,
                )?
            );
            Ok(())
        }
        "quanpin-evaluate" => {
            let dataset = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let manifest = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let lexicon = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let results = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let failures = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let runs = parse_usize(args.next(), "runs")?;
            let mut split = "dev".to_owned();
            let mut spelling_correction_enabled = false;
            let mut fuzzy_options_enabled = true;
            let mut context_model_path = None;
            let mut context_model_sha256 = None;
            let mut anonymous_distribution_path = None;
            let mut learning_probe_repetitions = 0;
            while let Some(flag) = args.next().and_then(|value| value.into_string().ok()) {
                match flag.as_str() {
                    "--split" => {
                        split = args
                            .next()
                            .and_then(|value| value.into_string().ok())
                            .ok_or_else(usage)?;
                    }
                    "--spelling-correction" => {
                        let value = args
                            .next()
                            .and_then(|value| value.into_string().ok())
                            .ok_or_else(usage)?;
                        spelling_correction_enabled = match value.as_str() {
                            "true" => true,
                            "false" => false,
                            _ => return Err(format!("invalid spelling correction flag {value:?}")),
                        };
                    }
                    "--fuzzy-options" => {
                        let value = args
                            .next()
                            .and_then(|value| value.into_string().ok())
                            .ok_or_else(usage)?;
                        fuzzy_options_enabled = match value.as_str() {
                            "true" => true,
                            "false" => false,
                            _ => return Err(format!("invalid fuzzy options flag {value:?}")),
                        };
                    }
                    "--context-model" => {
                        context_model_path =
                            Some(args.next().map(PathBuf::from).ok_or_else(usage)?);
                        context_model_sha256 = Some(
                            args.next()
                                .and_then(|value| value.into_string().ok())
                                .ok_or_else(usage)?,
                        );
                    }
                    "--anonymous-distribution" => {
                        anonymous_distribution_path =
                            Some(args.next().map(PathBuf::from).ok_or_else(usage)?);
                    }
                    "--learning-repetitions" => {
                        learning_probe_repetitions =
                            parse_usize(args.next(), "learning repetitions")?;
                    }
                    _ => return Err(format!("unknown quanpin evaluation option {flag:?}")),
                }
            }
            println!(
                "{}",
                candidate_baseline::evaluate_quanpin_dataset(
                    &candidate_baseline::QuanpinEvaluationRequest {
                        dataset_dir: &dataset,
                        manifest_path: &manifest,
                        lexicon_path: &lexicon,
                        results_path: &results,
                        failures_path: &failures,
                        runs,
                        split: &split,
                        spelling_correction_enabled,
                        fuzzy_options_enabled,
                        context_model_path: context_model_path.as_deref(),
                        context_model_sha256: context_model_sha256.as_deref(),
                        anonymous_distribution_path: anonymous_distribution_path.as_deref(),
                        learning_probe_repetitions,
                    },
                )?
            );
            Ok(())
        }
        "quanpin-distribution-validate" => {
            let distribution = args.next().map(PathBuf::from).ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            println!(
                "{}",
                candidate_baseline::validate_quanpin_anonymous_distribution(&distribution)?
            );
            Ok(())
        }
        "quanpin-context-freeze" => {
            let dataset = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let manifest = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let dataset_id = args
                .next()
                .and_then(|value| value.into_string().ok())
                .ok_or_else(usage)?;
            let frozen_at = args
                .next()
                .and_then(|value| value.into_string().ok())
                .ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            println!(
                "{}",
                candidate_baseline::freeze_quanpin_context_dataset(
                    &dataset,
                    &manifest,
                    &dataset_id,
                    &frozen_at,
                )?
            );
            Ok(())
        }
        "quanpin-context-evaluate" => {
            let dataset = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let manifest = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let lexicon = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let results = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let failures = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let runs = parse_usize(args.next(), "runs")?;
            let mut model_path = None;
            let mut model_sha256 = None;
            while let Some(flag) = args.next().and_then(|value| value.into_string().ok()) {
                match flag.as_str() {
                    "--model" => {
                        model_path = Some(args.next().map(PathBuf::from).ok_or_else(usage)?);
                        model_sha256 = Some(
                            args.next()
                                .and_then(|value| value.into_string().ok())
                                .ok_or_else(usage)?,
                        );
                    }
                    _ => return Err(format!("unknown context evaluation option {flag:?}")),
                }
            }
            println!(
                "{}",
                candidate_baseline::evaluate_quanpin_context_dataset(
                    &candidate_baseline::QuanpinContextEvaluationRequest {
                        dataset_path: &dataset,
                        manifest_path: &manifest,
                        lexicon_path: &lexicon,
                        model_path: model_path.as_deref(),
                        model_sha256: model_sha256.as_deref(),
                        results_path: &results,
                        failures_path: &failures,
                        runs,
                    },
                )?
            );
            Ok(())
        }
        "quanpin-context-discover" => {
            let lexicon = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let model = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let model_hash = args
                .next()
                .and_then(|value| value.into_string().ok())
                .ok_or_else(usage)?;
            let audit = args.next().map(PathBuf::from).ok_or_else(usage)?;
            let limit = parse_usize(args.next(), "limit")?;
            let output = args.next().map(PathBuf::from).ok_or_else(usage)?;
            if args.next().is_some() {
                return Err(usage());
            }
            let report = candidate_baseline::discover_quanpin_context_improvements(
                &lexicon,
                &model,
                &model_hash,
                &audit,
                limit,
            )?;
            if let Some(parent) = output.parent() {
                fs::create_dir_all(parent).map_err(|error| error.to_string())?;
            }
            fs::write(&output, report.as_bytes()).map_err(|error| error.to_string())?;
            println!("wrote {}", output.display());
            Ok(())
        }
        _ => Err(usage()),
    }
}

fn parse_usize(value: Option<std::ffi::OsString>, name: &str) -> Result<usize, String> {
    value
        .and_then(|value| value.into_string().ok())
        .and_then(|value| value.parse().ok())
        .ok_or_else(|| format!("invalid {name}; {}", usage()))
}

fn usage() -> String {
    "usage: candidate-baseline stable <production.lex> <production.hsyx> <output-dir> | performance <production.lex> <production.hsyx> <warmups> <samples> | performance-page-size <production.lex> <production.hsyx> <page-size> <warmups> <samples> | stage3 <production.lex> <warmups> <samples> | stage5-learning <production.lex> | stage6-audit <production.lex> <production.hsyx> <cases.tsv> | quanpin-create-dataset <dataset-dir> | quanpin-validate <dataset-dir> | quanpin-freeze <dataset-dir> <manifest> <baseline-id> <frozen-at> | quanpin-evaluate <dataset-dir> <manifest> <production.lex> <results.json> <failures.jsonl> <runs> [--anonymous-distribution <aggregate.json>] [--learning-repetitions <0..5>] [options] | quanpin-distribution-validate <aggregate.json> | pinyin9-create-dataset <frozen-quanpin-dataset-dir> <dataset-dir> | pinyin9-validate <dataset-dir> | pinyin9-freeze <dataset-dir> <manifest> <baseline-id> <frozen-at> | pinyin9-implementation-freeze <repo-root> <dataset-manifest> <production.lex> <output> <frozen-at> | pinyin9-evaluate <dataset-dir> <manifest> <production.lex> <results.json> <failures.jsonl> <runs> --split dev|blind|public-regression [--implementation-manifest <path> --repo-root <path>] [--receipt <path>] | quanpin-context-freeze <dataset.jsonl> <manifest.json> <dataset-id> <frozen-at> | quanpin-context-evaluate <dataset.jsonl> <manifest.json> <production.lex> <results.json> <failures.jsonl> <runs> [--model <model.qng> <sha256>] | quanpin-context-discover <production.lex> <model.qng> <sha256> <audit> <limit> <output>".to_owned()
}
