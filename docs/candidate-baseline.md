# Candidate regression baseline

Status: host-runnable scope completed. Phone, Pad, installed Debug/Release, and ARM64 device measurements were not run.

## Generation command

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate-candidate-baseline.ps1
```

Deterministic candidate snapshots are generated twice and compared file-by-file with SHA-256. Performance data is excluded from the byte gate because latency and process memory naturally vary.

## Key results

- Flypy shape h: 512 complete candidates, 2 exact one-key candidates, page size 9, hasNextPage=True.
- Flypy shape first 9: 和, 忽略, 化, 会, 行, 合, 后, 好, 海.
- Xiaohe double-pinyin production h*: 19459 records and 19433 unique texts.
- Double-pinyin pre-ranking recall: 64, scanned from ha through ha er ba.
- ha/hai: 64/64, or 100.0000%.
- Double-pinyin ranked first 9: 哈, 蛤, 哈尔, 哈达, 哈布斯堡, 哈勃, 虾, 奤, 哈丁.
- ArkTS and Rust default to 50 candidates per page; Rust accepts explicit page sizes up to 500.

## Performance summary

- double_pinyin_h_cold_query: P50 15108100 ns, P95 17683000 ns, max 21489800 ns
- double_pinyin_h_hot_query: P50 80900 ns, P95 107300 ns, max 195600 ns
- flypy_shape_h_cold_state_query: P50 1267500 ns, P95 1898500 ns, max 2186600 ns
- flypy_shape_h_hot_state_query: P50 1084700 ns, P95 1733400 ns, max 1919100 ns

## Environment limitations

- Actual Phone and Pad package page size, UI-visible latency, and memory: `NOT_RUN`; corresponding simulators or devices are required.
- Installed Debug and Release package page size: `NOT_RUN`; the shared-source contract implies 50.
- ARM64 physical-device performance: `NOT_RUN`.
- Git metadata was unavailable in this execution environment, so a separate stage 0 commit was not created or verified.

## Regression focus

- The global order of the 512-item shape snapshot must remain deterministic.
- Requests for both 50 and 9 must remain testable; concatenated pages must not repeat or lose candidates.
- Double-pinyin recall remains covered independently from the full-pinyin production lexicon.
- Unique four-code auto-commit, multiple four-code candidates, double-pinyin sentences, and partial commit must match these snapshots.

These snapshots describe the current V300 production resources and paging contract.
