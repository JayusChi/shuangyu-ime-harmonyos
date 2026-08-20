# Xiaohe Yinxing stage 0 performance baseline

Status: host Release metrics are `PASS`; device and cross-process metrics are explicitly `NOT_RUN`.

- Samples: 5
- Warmups: 2
- Environment: Microsoft Windows 10.0.26200 , X64, x86_64 host
- Filesystem cache: not controlled; warmup was performed.
- `deserialize_validate_and_index_build_fused` cannot be split further because the strict loader performs archive hashing, manifest/allowlist validation, nested lexicon deserialization, and runtime-index restoration in one function.
- These results are not ARM64 physical-device conclusions and are not used as flaky unit-test thresholds.

| Metric | Unit | P50 | P95 | Maximum | Status |
| --- | --- | ---: | ---: | ---: | --- |
| bundle_file_read | ns | 7394600 | 9542900 | 18441200 | PASS |
| bundle_size_and_sha256_check | ns | 35359600 | 36626500 | 40049500 | PASS |
| deserialize_validate_and_index_build_fused | ns | 633962300 | 634190700 | 637314700 | PASS |
| full_host_load_estimate | ns | 641356900 | 643733600 | 655755900 | PASS |
| verified_bytes_warm_reload | ns | 636181300 | 642055300 | 647370900 | PASS |
| first_key_to_runtime_candidates | ns | 329100 | 361100 | 372900 | PASS |
| query | ns | 4880 | 19740 | 274500 | PASS |
| state_cycle | ns | 812000 | 1355960 | 2067900 | PASS |
| peak_process_memory | bytes | 147386368 | 147402752 | 147406848 | PASS |
| steady_process_memory | bytes | 97636352 | 97636352 | 97640448 | PASS |
| memory_delta_after_500_session_cycles | bytes | 163840 | 163840 | 188416 | PASS |

## Metrics not run

- $(System.Collections.Specialized.OrderedDictionary.id): NOT_RUN - host benchmark does not execute the ArkTS installer cache path
- $(System.Collections.Specialized.OrderedDictionary.id): NOT_RUN - runtime first-key latency is measured; UI-visible latency requires simulator or physical-device instrumentation
- $(System.Collections.Specialized.OrderedDictionary.id): NOT_RUN - requires HarmonyOS process and Preferences/DataProxy instrumentation
