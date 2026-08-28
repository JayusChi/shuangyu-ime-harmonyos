use std::collections::{BTreeMap, BTreeSet};
use std::hint::black_box;
use std::mem::size_of;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use code_table_runtime::{
    query_with_strategy, CodeTableBundle, CodeTableCandidate, CodeTableMatch,
    CodeTableQueryStrategy, CodeTableStateMachine,
};
use user_lexicon::{
    merge_code_table_exact_candidates, merge_code_table_progressive_candidates,
    merge_user_lexicon_snapshots, UserLexiconAction, UserLexiconEntry, UserLexiconSnapshot,
};

const CANDIDATE_LIMIT: usize = 512;
const PAGE_SIZE: usize = 9;

fn main() {
    if let Err(error) = run() {
        eprintln!("precise-match-stage4-audit: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let workspace = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let mut args = std::env::args().skip(1);
    let mode = args.next().unwrap_or_else(|| "audit".to_owned());
    let bundle_path = args.next().map(PathBuf::from).unwrap_or_else(|| {
        workspace
            .join("dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx")
    });
    let bundle = Arc::new(
        CodeTableBundle::load_frozen_production_file(&bundle_path)
            .map_err(|error| error.to_string())?,
    );
    let rules = Arc::new(
        bundle
            .user_rules
            .clone()
            .ok_or_else(|| "formal bundle has no embedded rules".to_owned())?,
    );
    match mode.as_str() {
        "audit" => println!("{}", render_audit(bundle, rules)?),
        "performance-progressive" => println!(
            "{}",
            render_performance(
                bundle,
                rules,
                CodeTableQueryStrategy::ProgressiveXiaoheYinxing,
            )?
        ),
        "performance-deterministic" => println!(
            "{}",
            render_performance(
                bundle,
                rules,
                CodeTableQueryStrategy::DeterministicXiaoheYinxing,
            )?
        ),
        _ => {
            return Err(
                "usage: precise_match_stage4_audit [audit|performance-progressive|performance-deterministic] [bundle]"
                    .to_owned(),
            )
        }
    }
    Ok(())
}

fn render_audit(
    bundle: Arc<CodeTableBundle>,
    rules: Arc<UserLexiconSnapshot>,
) -> Result<String, String> {
    let enabled = bundle.default_enabled_category_ids();
    let mut by_code = BTreeMap::<String, Vec<CodeTableCandidate>>::new();
    let mut distribution = BTreeMap::<usize, usize>::new();
    let mut exact_path_violations = Vec::new();
    let mut repeated_query_mismatches = Vec::new();
    let mut maximum_collision = 0usize;

    for code in four_code_space() {
        let first = effective_candidates(
            &bundle,
            &enabled,
            &rules,
            &code,
            CodeTableQueryStrategy::DeterministicXiaoheYinxing,
            CANDIDATE_LIMIT,
        );
        let second = effective_candidates(
            &bundle,
            &enabled,
            &rules,
            &code,
            CodeTableQueryStrategy::DeterministicXiaoheYinxing,
            CANDIDATE_LIMIT,
        );
        if first != second && repeated_query_mismatches.len() < 20 {
            repeated_query_mismatches.push(code.clone());
        }
        if first.iter().any(|candidate| {
            candidate.code != code || candidate.match_type != CodeTableMatch::Exact
        }) && exact_path_violations.len() < 20
        {
            exact_path_violations.push(code.clone());
        }
        maximum_collision = maximum_collision.max(first.len());
        *distribution.entry(first.len()).or_default() += 1;
        if !first.is_empty() {
            by_code.insert(code, first);
        }
    }

    let mut unique_auto_commit_failures = Vec::new();
    let mut collision_runtime_failures = Vec::new();
    let mut unique_verified = 0usize;
    let mut collision_verified = 0usize;
    for (code, expected) in &by_code {
        let mut machine = CodeTableStateMachine::new_with_query_strategy(
            Arc::clone(&bundle),
            PAGE_SIZE,
            CANDIDATE_LIMIT,
            Arc::clone(&rules),
            CodeTableQueryStrategy::DeterministicXiaoheYinxing,
        )
        .map_err(|error| error.to_string())?;
        let mut outcome = None;
        for key in code.chars() {
            outcome = Some(
                machine
                    .process_key(key)
                    .map_err(|error| error.to_string())?,
            );
        }
        let outcome = outcome.expect("four-code input is non-empty");
        if expected.len() == 1 {
            unique_verified += 1;
            if outcome.commit_text.as_deref() != Some(expected[0].text.as_str())
                || !machine.raw_code().is_empty()
                || !machine.all_candidates().is_empty()
            {
                push_limited(&mut unique_auto_commit_failures, code);
            }
        } else {
            collision_verified += 1;
            if outcome.commit_text.is_some()
                || machine.raw_code() != code
                || machine.all_candidates() != expected.as_slice()
                || machine.all_candidates().iter().any(|candidate| {
                    candidate.code != *code || candidate.match_type != CodeTableMatch::Exact
                })
            {
                push_limited(&mut collision_runtime_failures, code);
            }
        }
    }

    let source_audit = audit_source_entries(&bundle, &enabled, &rules);
    let category_audit = audit_category_changes(&bundle, &enabled, &rules, &by_code);
    let deletion_audit = audit_user_deletions(&bundle, &enabled, &rules, &by_code);

    let zero_count = distribution.get(&0).copied().unwrap_or(0);
    let unique_count = distribution.get(&1).copied().unwrap_or(0);
    let collision_code_count = by_code.len().saturating_sub(unique_count);
    let all_passed = exact_path_violations.is_empty()
        && repeated_query_mismatches.is_empty()
        && unique_auto_commit_failures.is_empty()
        && collision_runtime_failures.is_empty()
        && source_audit.missing_short_codes.is_empty()
        && source_audit.missing_phrases.is_empty()
        && category_audit.failures.is_empty()
        && deletion_audit.failures.is_empty();

    let mut json = String::from("{\n");
    field_string(
        &mut json,
        1,
        "schema_version",
        "xiaohe-yinxing-precise-match-stage4-audit/1",
        true,
    );
    field_string(&mut json, 1, "scheme_id", "xiaohe-yinxing", true);
    field_string(
        &mut json,
        1,
        "query_strategy",
        "DeterministicXiaoheYinxing",
        true,
    );
    field_number(&mut json, 1, "four_code_space", 26usize.pow(4), true);
    field_number(&mut json, 1, "non_empty_four_codes", by_code.len(), true);
    field_number(&mut json, 1, "zero_candidate_codes", zero_count, true);
    field_number(&mut json, 1, "unique_four_codes", unique_count, true);
    field_number(
        &mut json,
        1,
        "collision_four_codes",
        collision_code_count,
        true,
    );
    field_number(
        &mut json,
        1,
        "maximum_candidates_per_four_code",
        maximum_collision,
        true,
    );
    line(&mut json, 1, "\"candidate_count_distribution\": {");
    for (index, (count, codes)) in distribution.iter().enumerate() {
        field_number(
            &mut json,
            2,
            &count.to_string(),
            *codes,
            index + 1 != distribution.len(),
        );
    }
    line(&mut json, 1, "},");
    line(&mut json, 1, "\"exact_query_contract\": {");
    field_number(&mut json, 2, "codes_checked", 26usize.pow(4), true);
    field_string_array(
        &mut json,
        2,
        "prefix_mix_violations",
        &exact_path_violations,
        true,
    );
    field_string_array(
        &mut json,
        2,
        "repeat_order_mismatches",
        &repeated_query_mismatches,
        false,
    );
    line(&mut json, 1, "},");
    line(&mut json, 1, "\"runtime_contract\": {");
    field_number(&mut json, 2, "unique_codes_verified", unique_verified, true);
    field_string_array(
        &mut json,
        2,
        "unique_auto_commit_failures",
        &unique_auto_commit_failures,
        true,
    );
    field_number(
        &mut json,
        2,
        "collision_codes_verified",
        collision_verified,
        true,
    );
    field_string_array(
        &mut json,
        2,
        "collision_wait_or_reachability_failures",
        &collision_runtime_failures,
        false,
    );
    line(&mut json, 1, "},");
    source_audit.write_json(&mut json, true);
    category_audit.write_json(&mut json, true);
    deletion_audit.write_json(&mut json, true);
    field_bool(&mut json, 1, "all_checks_passed", all_passed, false);
    json.push_str("}\n");
    Ok(json)
}

struct SourceAudit {
    short_code_pairs_checked: usize,
    phrase_pairs_checked: usize,
    approved_deleted_pairs: usize,
    missing_short_codes: Vec<String>,
    missing_phrases: Vec<String>,
}

impl SourceAudit {
    fn write_json(&self, json: &mut String, comma: bool) {
        line(json, 1, "\"source_entry_audit\": {");
        field_number(
            json,
            2,
            "short_code_pairs_checked",
            self.short_code_pairs_checked,
            true,
        );
        field_number(
            json,
            2,
            "phrase_pairs_checked",
            self.phrase_pairs_checked,
            true,
        );
        field_number(
            json,
            2,
            "approved_embedded_deletions",
            self.approved_deleted_pairs,
            true,
        );
        field_string_array(
            json,
            2,
            "missing_short_code_pairs",
            &self.missing_short_codes,
            true,
        );
        field_string_array(
            json,
            2,
            "missing_phrase_pairs",
            &self.missing_phrases,
            false,
        );
        write_indent(json, 1);
        json.push('}');
        if comma {
            json.push(',');
        }
        json.push('\n');
    }
}

fn audit_source_entries(
    bundle: &CodeTableBundle,
    enabled: &[String],
    rules: &UserLexiconSnapshot,
) -> SourceAudit {
    let mut pairs = BTreeSet::<(String, String)>::new();
    for category in &bundle.categories {
        if !enabled.contains(&category.id) {
            continue;
        }
        for entry in &category.lexicon.entries {
            pairs.insert((entry.pinyin_key.clone(), entry.word.clone()));
        }
    }
    let mut cache = BTreeMap::<String, BTreeSet<String>>::new();
    let mut short_code_pairs_checked = 0;
    let mut phrase_pairs_checked = 0;
    let mut approved_deleted_pairs = 0;
    let mut missing_short_codes = Vec::new();
    let mut missing_phrases = Vec::new();
    for (code, text) in pairs {
        let is_short = code.len() < 4;
        let is_phrase = text.chars().count() > 1;
        if !is_short && !is_phrase {
            continue;
        }
        if is_short {
            short_code_pairs_checked += 1;
        }
        if is_phrase {
            phrase_pairs_checked += 1;
        }
        if rules.deletes(&code, &text) {
            approved_deleted_pairs += 1;
            continue;
        }
        let visible = cache.entry(code.clone()).or_insert_with(|| {
            effective_candidates(
                bundle,
                enabled,
                rules,
                &code,
                CodeTableQueryStrategy::DeterministicXiaoheYinxing,
                usize::MAX,
            )
            .into_iter()
            .map(|candidate| candidate.text)
            .collect()
        });
        if !visible.contains(&text) {
            let pair = format!("{code}\t{text}");
            if is_short {
                push_limited(&mut missing_short_codes, &pair);
            }
            if is_phrase {
                push_limited(&mut missing_phrases, &pair);
            }
        }
    }
    SourceAudit {
        short_code_pairs_checked,
        phrase_pairs_checked,
        approved_deleted_pairs,
        missing_short_codes,
        missing_phrases,
    }
}

struct CategoryAudit {
    categories_checked: usize,
    affected_codes_checked: usize,
    uniqueness_changes: usize,
    failures: Vec<String>,
}

impl CategoryAudit {
    fn write_json(&self, json: &mut String, comma: bool) {
        line(json, 1, "\"category_disable_audit\": {");
        field_number(
            json,
            2,
            "optional_categories_checked",
            self.categories_checked,
            true,
        );
        field_number(
            json,
            2,
            "affected_four_codes_checked",
            self.affected_codes_checked,
            true,
        );
        field_number(json, 2, "uniqueness_changes", self.uniqueness_changes, true);
        field_string_array(json, 2, "failures", &self.failures, false);
        write_indent(json, 1);
        json.push('}');
        if comma {
            json.push(',');
        }
        json.push('\n');
    }
}

fn audit_category_changes(
    bundle: &CodeTableBundle,
    enabled: &[String],
    rules: &UserLexiconSnapshot,
    baseline: &BTreeMap<String, Vec<CodeTableCandidate>>,
) -> CategoryAudit {
    let mut categories_checked = 0;
    let mut affected_codes_checked = 0;
    let mut uniqueness_changes = 0;
    let mut failures = Vec::new();
    for category in &bundle.categories {
        if category.id == "core" || !enabled.contains(&category.id) {
            continue;
        }
        categories_checked += 1;
        let selected = enabled
            .iter()
            .filter(|id| *id != &category.id)
            .cloned()
            .collect::<Vec<_>>();
        let affected = category
            .lexicon
            .entries
            .iter()
            .filter(|entry| entry.pinyin_key.len() == 4)
            .map(|entry| entry.pinyin_key.clone())
            .collect::<BTreeSet<_>>();
        for code in affected {
            affected_codes_checked += 1;
            let next = effective_candidates(
                bundle,
                &selected,
                rules,
                &code,
                CodeTableQueryStrategy::DeterministicXiaoheYinxing,
                CANDIDATE_LIMIT,
            );
            if next
                .iter()
                .any(|candidate| candidate.category_id == category.id)
            {
                push_limited(
                    &mut failures,
                    &format!("{}:{code}:disabled-candidate-visible", category.id),
                );
            }
            let before = baseline.get(&code).map(Vec::len).unwrap_or(0);
            if (before == 1) != (next.len() == 1) {
                uniqueness_changes += 1;
            }
        }
    }
    CategoryAudit {
        categories_checked,
        affected_codes_checked,
        uniqueness_changes,
        failures,
    }
}

struct DeletionAudit {
    codes_checked: usize,
    unique_to_zero: usize,
    collision_to_unique: usize,
    collision_still_collision: usize,
    failures: Vec<String>,
}

impl DeletionAudit {
    fn write_json(&self, json: &mut String, comma: bool) {
        line(json, 1, "\"user_delete_audit\": {");
        field_number(
            json,
            2,
            "non_empty_four_codes_checked",
            self.codes_checked,
            true,
        );
        field_number(json, 2, "unique_to_zero", self.unique_to_zero, true);
        field_number(
            json,
            2,
            "collision_to_unique",
            self.collision_to_unique,
            true,
        );
        field_number(
            json,
            2,
            "collision_still_collision",
            self.collision_still_collision,
            true,
        );
        field_string_array(json, 2, "failures", &self.failures, false);
        write_indent(json, 1);
        json.push('}');
        if comma {
            json.push(',');
        }
        json.push('\n');
    }
}

fn audit_user_deletions(
    bundle: &CodeTableBundle,
    enabled: &[String],
    rules: &UserLexiconSnapshot,
    baseline: &BTreeMap<String, Vec<CodeTableCandidate>>,
) -> DeletionAudit {
    let mut unique_to_zero = 0;
    let mut collision_to_unique = 0;
    let mut collision_still_collision = 0;
    let mut failures = Vec::new();
    for (index, (code, candidates)) in baseline.iter().enumerate() {
        let deleted = &candidates[0].text;
        let overlay = UserLexiconSnapshot::from_entries(
            vec![UserLexiconEntry {
                text: deleted.clone(),
                display_text: None,
                code: code.clone(),
                action: UserLexiconAction::Delete,
                source_order: index as u32,
                category_id: None,
            }],
            1,
        );
        let layered = merge_user_lexicon_snapshots(rules, &overlay);
        let next = effective_candidates(
            bundle,
            enabled,
            &layered,
            code,
            CodeTableQueryStrategy::DeterministicXiaoheYinxing,
            CANDIDATE_LIMIT,
        );
        if next.iter().any(|candidate| candidate.text == *deleted) {
            push_limited(&mut failures, &format!("{code}\t{deleted}"));
        }
        match (candidates.len(), next.len()) {
            (1, 0) => unique_to_zero += 1,
            (n, 1) if n > 1 => collision_to_unique += 1,
            (n, m) if n > 1 && m > 1 => collision_still_collision += 1,
            _ => push_limited(
                &mut failures,
                &format!("{code}:{}->{}", candidates.len(), next.len()),
            ),
        }
    }
    DeletionAudit {
        codes_checked: baseline.len(),
        unique_to_zero,
        collision_to_unique,
        collision_still_collision,
        failures,
    }
}

fn render_performance(
    bundle: Arc<CodeTableBundle>,
    rules: Arc<UserLexiconSnapshot>,
    strategy: CodeTableQueryStrategy,
) -> Result<String, String> {
    let process_start = memory_snapshot();
    let enabled = bundle.default_enabled_category_ids();
    let prefixes = production_prefixes(&bundle, &rules);
    let after_load = memory_snapshot();
    for _ in 0..3 {
        for code in &prefixes {
            black_box(effective_candidates(
                &bundle,
                &enabled,
                &rules,
                code,
                strategy,
                CANDIDATE_LIMIT,
            ));
        }
    }
    let mut timings = Vec::with_capacity(prefixes.len());
    let mut snapshots = Vec::with_capacity(prefixes.len());
    let mut total_candidates = 0usize;
    let mut total_json_bytes = 0usize;
    for code in &prefixes {
        let started = Instant::now();
        let candidates =
            effective_candidates(&bundle, &enabled, &rules, code, strategy, CANDIDATE_LIMIT);
        timings.push(started.elapsed());
        total_candidates += candidates.len();
        total_json_bytes += candidate_json_bytes(code, &candidates);
        snapshots.push(candidates);
    }
    black_box(&snapshots);
    let after_snapshots = memory_snapshot();
    let strategy_name = match strategy {
        CodeTableQueryStrategy::ProgressiveXiaoheYinxing => "ProgressiveXiaoheYinxing",
        CodeTableQueryStrategy::DeterministicXiaoheYinxing => "DeterministicXiaoheYinxing",
        _ => unreachable!(),
    };
    let mut json = String::from("{\n");
    field_string(
        &mut json,
        1,
        "schema_version",
        "xiaohe-yinxing-precise-match-stage4-performance/1",
        true,
    );
    field_string(&mut json, 1, "profile", "release", true);
    field_string(&mut json, 1, "strategy", strategy_name, true);
    field_number(&mut json, 1, "warmup_rounds", 3, true);
    field_number(
        &mut json,
        1,
        "distinct_one_to_three_code_prefixes",
        prefixes.len(),
        true,
    );
    field_number(&mut json, 1, "candidate_limit", CANDIDATE_LIMIT, true);
    line(&mut json, 1, "\"query_time_ns\": {");
    field_u128(&mut json, 2, "p50", percentile(&timings, 50), true);
    field_u128(&mut json, 2, "p95", percentile(&timings, 95), true);
    field_u128(&mut json, 2, "max", percentile(&timings, 100), false);
    line(&mut json, 1, "},");
    field_number(
        &mut json,
        1,
        "total_candidates_transferred",
        total_candidates,
        true,
    );
    field_number(
        &mut json,
        1,
        "candidate_snapshot_json_bytes",
        total_json_bytes,
        true,
    );
    line(&mut json, 1, "\"memory\": {");
    field_u64(
        &mut json,
        2,
        "process_start_working_set_bytes",
        process_start.working,
        true,
    );
    field_u64(
        &mut json,
        2,
        "after_resource_load_working_set_bytes",
        after_load.working,
        true,
    );
    field_u64(
        &mut json,
        2,
        "after_candidate_snapshots_working_set_bytes",
        after_snapshots.working,
        true,
    );
    field_u64(
        &mut json,
        2,
        "candidate_snapshot_working_set_delta_bytes",
        after_snapshots.working.saturating_sub(after_load.working),
        true,
    );
    field_u64(
        &mut json,
        2,
        "peak_working_set_bytes",
        after_snapshots.peak.max(after_load.peak),
        false,
    );
    line(&mut json, 1, "}");
    json.push_str("}\n");
    Ok(json)
}

fn production_prefixes(bundle: &CodeTableBundle, rules: &UserLexiconSnapshot) -> Vec<String> {
    let mut prefixes = BTreeSet::new();
    for code in bundle
        .categories
        .iter()
        .flat_map(|category| {
            category
                .lexicon
                .entries
                .iter()
                .map(|entry| entry.pinyin_key.as_str())
        })
        .chain(rules.entries().iter().map(|entry| entry.code.as_str()))
    {
        for length in 1..=3.min(code.len()) {
            prefixes.insert(code[..length].to_owned());
        }
    }
    prefixes.into_iter().collect()
}

fn effective_candidates(
    bundle: &CodeTableBundle,
    enabled: &[String],
    rules: &UserLexiconSnapshot,
    code: &str,
    strategy: CodeTableQueryStrategy,
    limit: usize,
) -> Vec<CodeTableCandidate> {
    let query = query_with_strategy(
        bundle,
        enabled,
        code,
        limit.saturating_add(rules.entries().len()),
        strategy,
    );
    let make_user = |entry: &UserLexiconEntry| CodeTableCandidate {
        id: entry.stable_id(),
        text: entry.text.clone(),
        display_text: entry.display_text.clone(),
        code: entry.code.clone(),
        category_id: "user-lexicon".to_owned(),
        source_order: entry.source_order,
        match_type: if entry.code == code {
            CodeTableMatch::Exact
        } else {
            CodeTableMatch::Prefix
        },
    };
    let mut candidates = if strategy == CodeTableQueryStrategy::ProgressiveXiaoheYinxing
        && (1..=3).contains(&code.len())
    {
        merge_code_table_progressive_candidates(
            rules,
            code,
            query.candidates,
            |candidate| candidate.text.as_str(),
            |candidate| candidate.code.as_str(),
            make_user,
        )
    } else {
        merge_code_table_exact_candidates(
            rules,
            code,
            query.candidates,
            |candidate| candidate.text.as_str(),
            |candidate| candidate.code.as_str(),
            make_user,
        )
    };
    candidates.truncate(limit);
    candidates
}

fn four_code_space() -> impl Iterator<Item = String> {
    (b'a'..=b'z').flat_map(|a| {
        (b'a'..=b'z').flat_map(move |b| {
            (b'a'..=b'z').flat_map(move |c| {
                (b'a'..=b'z').map(move |d| String::from_utf8(vec![a, b, c, d]).expect("ASCII code"))
            })
        })
    })
}

fn candidate_json_bytes(code: &str, candidates: &[CodeTableCandidate]) -> usize {
    let mut json = format!("{{\"rawInput\":{},\"candidates\":[", quote(code));
    for (index, candidate) in candidates.iter().enumerate() {
        if index > 0 {
            json.push(',');
        }
        json.push_str("{\"id\":");
        json.push_str(&quote(&candidate.id));
        json.push_str(",\"text\":");
        json.push_str(&quote(&candidate.text));
        json.push_str(",\"reading\":");
        json.push_str(&quote(&candidate.code));
        json.push_str(",\"source\":");
        json.push_str(&quote(&candidate.category_id));
        json.push('}');
    }
    json.push_str("]}");
    json.len()
}

fn percentile(samples: &[Duration], percentile: usize) -> u128 {
    let mut sorted = samples.to_vec();
    sorted.sort_unstable();
    let index = ((sorted.len() - 1) * percentile) / 100;
    sorted[index].as_nanos()
}

fn push_limited(values: &mut Vec<String>, value: &str) {
    if values.len() < 20 {
        values.push(value.to_owned());
    }
}

#[derive(Clone, Copy)]
struct MemorySnapshot {
    working: u64,
    peak: u64,
}

#[cfg(windows)]
fn memory_snapshot() -> MemorySnapshot {
    #[repr(C)]
    struct ProcessMemoryCounters {
        cb: u32,
        page_fault_count: u32,
        peak_working_set_size: usize,
        working_set_size: usize,
        quota_peak_paged_pool_usage: usize,
        quota_paged_pool_usage: usize,
        quota_peak_non_paged_pool_usage: usize,
        quota_non_paged_pool_usage: usize,
        pagefile_usage: usize,
        peak_pagefile_usage: usize,
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentProcess() -> *mut core::ffi::c_void;
    }
    #[link(name = "psapi")]
    unsafe extern "system" {
        fn GetProcessMemoryInfo(
            process: *mut core::ffi::c_void,
            counters: *mut ProcessMemoryCounters,
            size: u32,
        ) -> i32;
    }
    let mut counters = ProcessMemoryCounters {
        cb: size_of::<ProcessMemoryCounters>() as u32,
        page_fault_count: 0,
        peak_working_set_size: 0,
        working_set_size: 0,
        quota_peak_paged_pool_usage: 0,
        quota_paged_pool_usage: 0,
        quota_peak_non_paged_pool_usage: 0,
        quota_non_paged_pool_usage: 0,
        pagefile_usage: 0,
        peak_pagefile_usage: 0,
    };
    // SAFETY: read-only query for the current process with a correctly sized output buffer.
    let ok = unsafe {
        GetProcessMemoryInfo(
            GetCurrentProcess(),
            &mut counters,
            size_of::<ProcessMemoryCounters>() as u32,
        )
    };
    if ok == 0 {
        MemorySnapshot {
            working: 0,
            peak: 0,
        }
    } else {
        MemorySnapshot {
            working: counters.working_set_size as u64,
            peak: counters.peak_working_set_size as u64,
        }
    }
}

#[cfg(not(windows))]
fn memory_snapshot() -> MemorySnapshot {
    let status = std::fs::read_to_string("/proc/self/status").unwrap_or_default();
    let value = |field: &str| {
        status
            .lines()
            .find_map(|line| {
                line.strip_prefix(field)?
                    .split_whitespace()
                    .next()?
                    .parse::<u64>()
                    .ok()
            })
            .unwrap_or(0)
            * 1024
    };
    MemorySnapshot {
        working: value("VmRSS:"),
        peak: value("VmHWM:"),
    }
}

fn field_string(json: &mut String, indent: usize, name: &str, value: &str, comma: bool) {
    write_indent(json, indent);
    json.push_str(&quote(name));
    json.push_str(": ");
    json.push_str(&quote(value));
    if comma {
        json.push(',');
    }
    json.push('\n');
}
fn field_number(json: &mut String, indent: usize, name: &str, value: usize, comma: bool) {
    write_indent(json, indent);
    json.push_str(&quote(name));
    json.push_str(": ");
    json.push_str(&value.to_string());
    if comma {
        json.push(',');
    }
    json.push('\n');
}
fn field_u64(json: &mut String, indent: usize, name: &str, value: u64, comma: bool) {
    write_indent(json, indent);
    json.push_str(&quote(name));
    json.push_str(": ");
    json.push_str(&value.to_string());
    if comma {
        json.push(',');
    }
    json.push('\n');
}
fn field_u128(json: &mut String, indent: usize, name: &str, value: u128, comma: bool) {
    write_indent(json, indent);
    json.push_str(&quote(name));
    json.push_str(": ");
    json.push_str(&value.to_string());
    if comma {
        json.push(',');
    }
    json.push('\n');
}
fn field_bool(json: &mut String, indent: usize, name: &str, value: bool, comma: bool) {
    write_indent(json, indent);
    json.push_str(&quote(name));
    json.push_str(": ");
    json.push_str(if value { "true" } else { "false" });
    if comma {
        json.push(',');
    }
    json.push('\n');
}
fn field_string_array(
    json: &mut String,
    indent: usize,
    name: &str,
    values: &[String],
    comma: bool,
) {
    write_indent(json, indent);
    json.push_str(&quote(name));
    json.push_str(": [");
    for (index, value) in values.iter().enumerate() {
        if index > 0 {
            json.push_str(", ");
        }
        json.push_str(&quote(value));
    }
    json.push(']');
    if comma {
        json.push(',');
    }
    json.push('\n');
}
fn line(json: &mut String, indent: usize, value: &str) {
    write_indent(json, indent);
    json.push_str(value);
    json.push('\n');
}
fn write_indent(json: &mut String, indent: usize) {
    for _ in 0..indent {
        json.push_str("  ");
    }
}
fn quote(value: &str) -> String {
    let mut output = String::from("\"");
    for character in value.chars() {
        match character {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            c if c.is_control() => output.push_str(&format!("\\u{:04x}", c as u32)),
            c => output.push(c),
        }
    }
    output.push('"');
    output
}
