use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use code_table_runtime::{
    query_exact_or_prefix, CodeTableBundle, CodeTableStateMachine, PRODUCTION_SCHEME_ID,
};

const CASES: [(&str, usize, &str); 9] = [
    ("a", 2, "啊"),
    ("aa", 1, "阿"),
    ("aae", 1, "阿"),
    ("aaba", 1, "阿爸"),
    ("aab", 4, "阿爸"),
    ("aaaa", 0, ""),
    ("bcbn", 3, "报表"),
    ("jumk", 5, "驹"),
    ("un", 39, "熟能生巧"),
];

#[derive(Clone, Copy)]
struct MemorySnapshot {
    working: u64,
    peak: u64,
}

fn main() {
    let bundle_path = std::env::args_os().nth(1).map(PathBuf::from).unwrap_or_else(|| {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(
            "../../../dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx",
        )
    });
    let process_start = memory_snapshot();
    let bundle_bytes = fs::metadata(&bundle_path)
        .expect("frozen bundle metadata")
        .len();
    let load_started = Instant::now();
    let bundle = CodeTableBundle::load_frozen_production_file_shared(&bundle_path)
        .expect("map and load frozen bundle");
    let load_ns = load_started.elapsed().as_nanos();
    bundle
        .validate_scheme_identity(PRODUCTION_SCHEME_ID)
        .expect("formal identity");
    let after_load = memory_snapshot();
    let enabled = bundle.default_enabled_category_ids();
    let shared_reload_started = Instant::now();
    let shared_reload = CodeTableBundle::load_frozen_production_file_shared(&bundle_path)
        .expect("reuse frozen bundle");
    let shared_reload_ns = shared_reload_started.elapsed().as_nanos();
    assert!(Arc::ptr_eq(&shared_reload, &bundle));

    let first_key_started = Instant::now();
    let mut first_key_state =
        CodeTableStateMachine::new(Arc::clone(&bundle), 9, 256).expect("first-key state");
    first_key_state.process_key('a').expect("first key");
    let first_key_ns = first_key_started.elapsed().as_nanos();
    assert!(!first_key_state.current_candidates().is_empty());

    let sessions_before = memory_snapshot();
    for _ in 0..500 {
        let mut session =
            CodeTableStateMachine::new(Arc::clone(&bundle), 9, 256).expect("session cycle");
        session.process_key('a').expect("session first key");
        assert!(!session.current_candidates().is_empty());
    }
    let sessions_after = memory_snapshot();
    let session_cycle_memory_delta_bytes = sessions_after
        .working
        .saturating_sub(sessions_before.working);

    let mut checksum = 0_u64;
    for (code, count, first) in CASES {
        let result = query_exact_or_prefix(&bundle, &enabled, code, usize::MAX);
        assert_eq!(result.candidates.len(), count, "{code}");
        assert_eq!(
            result
                .candidates
                .first()
                .map(|candidate| candidate.text.as_str())
                .unwrap_or(""),
            first,
            "{code}"
        );
        checksum ^= result.candidates.iter().fold(0_u64, |value, candidate| {
            value
                .wrapping_add(candidate.text.len() as u64)
                .wrapping_add(candidate.source_order as u64)
        });
    }

    for _ in 0..20 {
        for (code, _, _) in CASES {
            checksum ^= query_exact_or_prefix(&bundle, &enabled, code, usize::MAX)
                .candidates
                .len() as u64;
        }
    }
    let mut query_samples = Vec::with_capacity(2_000 * CASES.len());
    for _ in 0..2_000 {
        for (code, _, _) in CASES {
            let started = Instant::now();
            let result = query_exact_or_prefix(&bundle, &enabled, code, usize::MAX);
            query_samples.push(started.elapsed());
            checksum = checksum.wrapping_add(result.candidates.len() as u64);
        }
    }

    let mut state = CodeTableStateMachine::new(Arc::clone(&bundle), 2, 256).expect("state machine");
    let mut state_samples = Vec::with_capacity(500);
    for _ in 0..500 {
        let started = Instant::now();
        state.reset();
        for key in "jumk".chars() {
            state.process_key(key).expect("key");
        }
        state.next_page().expect("next page");
        checksum = checksum.wrapping_add(state.current_candidates().len() as u64);
        state.previous_page().expect("previous page");
        state.backspace();
        state.reset();
        state_samples.push(started.elapsed());
    }
    let final_memory = memory_snapshot();

    println!(
        concat!(
            "{{\"profile\":\"release\",\"bundleBytes\":{},\"entries\":{},",
            "\"loadNs\":{},\"sharedReloadNs\":{},\"sharedCacheHit\":true,\"firstKeyNs\":{},",
            "\"sessionCycleCount\":500,\"sessionCycleMemoryDeltaBytes\":{},",
            "\"warmupCount\":20,\"querySampleCount\":{},\"queryP50Ns\":{},",
            "\"queryP95Ns\":{},\"queryP99Ns\":{},\"queryMaxNs\":{},",
            "\"stateSampleCount\":{},\"stateP50Ns\":{},\"stateP95Ns\":{},",
            "\"stateP99Ns\":{},\"stateMaxNs\":{},\"processStartBytes\":{},",
            "\"afterLoadBytes\":{},\"finalMemoryBytes\":{},\"peakMemoryBytes\":{},\"memoryDeltaBytes\":{},",
            "\"checksum\":{}}}"
        ),
        bundle_bytes,
        bundle
            .categories
            .iter()
            .map(|category| category.lexicon.entries.len())
            .sum::<usize>(),
        load_ns,
        shared_reload_ns,
        first_key_ns,
        session_cycle_memory_delta_bytes,
        query_samples.len(),
        percentile(&query_samples, 50),
        percentile(&query_samples, 95),
        percentile(&query_samples, 99),
        maximum(&query_samples),
        state_samples.len(),
        percentile(&state_samples, 50),
        percentile(&state_samples, 95),
        percentile(&state_samples, 99),
        maximum(&state_samples),
        process_start.working,
        after_load.working,
        final_memory.working,
        final_memory.peak.max(after_load.peak),
        after_load.working.saturating_sub(process_start.working),
        checksum,
    );
}

fn percentile(samples: &[Duration], percentile: usize) -> u128 {
    let mut sorted = samples.to_vec();
    sorted.sort_unstable();
    sorted[((sorted.len() - 1) * percentile) / 100].as_nanos()
}

fn maximum(samples: &[Duration]) -> u128 {
    samples.iter().max().expect("samples").as_nanos()
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
    // SAFETY: both APIs are read-only for the current process and receive a
    // correctly sized writable PROCESS_MEMORY_COUNTERS buffer.
    let succeeded = unsafe {
        GetProcessMemoryInfo(
            GetCurrentProcess(),
            &mut counters,
            size_of::<ProcessMemoryCounters>() as u32,
        )
    };
    if succeeded == 0 {
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
    let status = fs::read_to_string("/proc/self/status").unwrap_or_default();
    let value = |field: &str| {
        status
            .lines()
            .find_map(|line| {
                line.strip_prefix(field)
                    .and_then(|value| value.split_whitespace().next())
                    .and_then(|value| value.parse::<u64>().ok())
                    .map(|kilobytes| kilobytes * 1024)
            })
            .unwrap_or(0)
    };
    MemorySnapshot {
        working: value("VmRSS:"),
        peak: value("VmHWM:"),
    }
}
