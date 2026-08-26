# Candidate improvement stage 0 baseline

Status: host-runnable scope completed. Phone, Pad, installed Debug/Release, and ARM64 device measurements were not run.

## Generation command

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate-candidate-baseline.ps1
```

Deterministic candidate snapshots are generated twice and compared file-by-file with SHA-256. Performance data is excluded from the byte gate because latency and process memory naturally vary.

## Key results

- Flypy shape h: 512 complete candidates, 2 exact one-key candidates, page size 9, hasNextPage=True.
- Flypy shape first 9: 和, 忽略, 化, 会, 行, 合, 后, 好, 海.
- Xiaohe double-pinyin production h*: 3237 records and 3221 unique texts.
- Double-pinyin pre-ranking recall: 64, scanned from ha through hai bian.
- ha/hai: 64/64, or 100.0000%.
- Double-pinyin ranked first 9: 还, 哈哈, 哈, 哈哈哈, 海, 哈哈哈哈, 害, 哈尔滨, 海边.
- ArkTS requests 50; Rust defaults to 5 and caps at 9; the current production effective page size is 9.

## Performance summary

- double_pinyin_h_cold_query: P50 92900 ns, P95 142200 ns, max 204900 ns
- double_pinyin_h_hot_query: P50 9300 ns, P95 26500 ns, max 43900 ns
- flypy_shape_h_cold_state_query: P50 1376600 ns, P95 2003000 ns, max 2511500 ns
- flypy_shape_h_hot_state_query: P50 1154100 ns, P95 1843400 ns, max 2380500 ns

## Environment limitations

- Actual Phone and Pad package page size, UI-visible latency, and memory: `NOT_RUN`; corresponding simulators or devices are required.
- Installed Debug and Release package page size: `NOT_RUN`; the shared-source contract implies 9.
- ARM64 physical-device performance: `NOT_RUN`.
- Git metadata was unavailable in this execution environment, so a separate stage 0 commit was not created or verified.

## Stage 1 regression focus

- Raising the page cap must not alter the global order of the 512-item shape snapshot.
- Requests for both 50 and 9 must remain testable; concatenated pages must not repeat or lose candidates.
- Stage 1 must not also fix double-pinyin recall; the current 100% `ha/hai` bias in the 64-item pool is the stage 3 control.
- Unique four-code auto-commit, multiple four-code candidates, double-pinyin sentences, and partial commit must match these snapshots.

This stage adds only diagnostics, scripts, tests, and evidence. It does not change production dictionaries, ranking, paging parameters, recall logic, or UI.
