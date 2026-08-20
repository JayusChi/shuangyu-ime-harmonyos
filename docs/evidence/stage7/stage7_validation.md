# Stage 7 Validation Evidence

## Execution

- Date: 2026-07-09
- OS: Microsoft Windows NT 10.0.26200.0
- DevEco Studio root: `C:\Program Files\Huawei\DevEco Studio`
- Rust: toolchain from `engine-rust/rust-toolchain.toml`
- Stage 7 device install and real text-field validation: not executed

## Commands Executed

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage7.ps1
cargo test -p candidate-ranking -p candidate-query -p ime-engine
cargo test -p ime-ffi
cargo fmt --check
cargo test --workspace
cargo fmt
cargo clippy --workspace --all-targets -- -D warnings
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'; & 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust
cargo test -p ime-engine
```

The final `scripts\verify-stage7.ps1` run passed all steps, including source
boundary checks and artifact summary.

The first ArkTS attempt failed because `rawfile` was placed under
`resources/base/rawfile`. The file was moved to `entry/src/main/resources/rawfile`,
which is the valid project layout, and the subsequent ArkTS test passed.

The second ArkTS attempt failed because `BaseContext` was too narrow for
`filesDir` and `resourceManager`. The installer was changed to use
`InputMethodExtensionContext`, and the subsequent ArkTS test passed.

Two early full-script attempts also exposed script-only guard issues:
PowerShell 5.1 misread a Chinese regex literal in a boundary check, and the
runtime-code scan accidentally included the Stage 7 TSV fixture test. The final
script uses ASCII Unicode escapes and scans `ime-engine/src` for runtime TSV
guarding; the corrected script passed.

## Rust Results

| Item | Result |
| --- | --- |
| `cargo fmt --check` | PASS after `cargo fmt` |
| `cargo clippy --workspace --all-targets -- -D warnings` | PASS |
| `cargo test --workspace` | PASS |
| Explicit Rust tests | 98 passed, 0 failed |
| Stage 4 parser regression | PASS, 8 tests |
| Stage 5/7 FFI tests | PASS, 13 tests |
| Stage 7 query tests | PASS, 9 tests |
| Stage 7 ranking tests | PASS, 7 tests |
| Stage 7 ime-engine unit tests | PASS, 18 tests |
| Stage 7 fixed candidate fixture | PASS, 1 integration test |

## Stage 7 Functional Coverage

- Runtime lexicon loading from explicit binary path.
- Invalid lexicon path returns `LEXICON_NOT_FOUND`.
- Missing lexicon returns `ENGINE_NOT_INITIALIZED` when query is required.
- Exact query for single syllable and multi-syllable words.
- Bounded prefix query.
- Empty input does not enumerate the lexicon.
- Deterministic ranking and source merge deduplication.
- Candidate pagination state in Rust.
- Cache hit, miss, capacity eviction, and order stability.
- `selectCandidate` returns `commitText` and clears composition.
- Invalid candidate index and invalid page return structured errors.
- Rust panic remains caught at FFI boundary.

## Lexicon Artifact

- Source: `dictionaries/source/stage6_test.tsv`
- Source data rows: 48
- Generated binary: `dictionaries/generated/stage6_test.lex`
- Stage 7 packaged rawfile: `entry/src/main/resources/rawfile/stage7_test.lex`
- Entries: 46
- Pinyin keys: 45
- Binary size: 3,076 bytes
- Rawfile size: 3,076 bytes
- SHA-256: `E7B84B676C3F40D2FD2DAE0E1017FEE4C665432E88DFE2A6B0C575AC8B5A83E3`

The lexicon is hand-authored for Stage 7 validation only and is not a
production Chinese dictionary.

## Native and HAP Artifacts

| Artifact | Path | Size | SHA-256 |
| --- | --- | ---: | --- |
| x86_64 Rust static library | `engine-rust/target/ohos/x86_64/libime_ffi.a` | 23,100,026 bytes | `63998AF171D0793656FA52A2BDB368423ABE2A529BB2D011DE2BAB91CE9BA194` |
| arm64-v8a Rust static library | `engine-rust/target/ohos/arm64-v8a/libime_ffi.a` | 23,706,582 bytes | `850812C5EFE5EA5A7E747D9F5E61867C8365D50A2FFD92ADDE724044EA4EBBFC` |
| HAP | `entry/build/default/outputs/default/entry-default-unsigned.hap` | 6,543,537 bytes | `E835B8818AF12858EDBA06F186F7E7EA14E5EBB35C7F4CF8B45635EE422B50EC` |

HAP signing remains unsigned/debug because no signingConfigs profile is
configured.

## ArkTS and C++ Results

| Item | Result |
| --- | --- |
| C++ BuildNativeWithCmake in hvigor test | PASS |
| C++ BuildNativeWithNinja in HAP build | PASS |
| ArkTS unit test build | PASS |
| HAP build | PASS |

ArkTS coverage includes updated fakes for `selectCandidate`,
`nextCandidatePage`, `previousCandidatePage`, new pagination fields, and the
Stage 7 interface version.

## Architecture Boundary Checks

- ArkTS does not implement lexicon query, ranking, pagination slicing, or
  formal Chinese candidate hardcoding.
- ArkTS `LexiconResourceInstaller` only copies rawfile bytes to sandbox and
  provides the resulting path.
- CandidateBar does not import Native or IME Kit.
- C++ only validates parameters, converts UTF-8, forwards calls, maps errors,
  and converts Rust JSON to ArkTS objects.
- C++ does not implement pinyin index lookup, sorting, pagination, or cache.
- Rust query/engine crates do not depend on HarmonyOS APIs.
- Runtime query reads only binary `.lex` files, not TSV.

## Device Validation

Device installation and real input-field verification were not executed.

```text
设备安装和真实输入框验证未执行，不能声称阶段 7 已通过设备验收。
```

Not executed:

- install HAP on device or emulator;
- enable input method in system settings;
- open a real text field;
- type Stage 7 candidate cases on device;
- click candidates on device;
- verify paging/deletion/landscape/dark mode on device.

## Known Limits

- The packaged lexicon is a small validation lexicon, not a production corpus.
- Space selects the first candidate only when current Chinese composition has
  candidates; otherwise it keeps the existing raw space fallback.
- No sentence decoding, dynamic word-path search, user frequency, user lexicon,
  cloud lexicon, fuzzy pinyin, or AI ranking is implemented.
- Dedicated Valgrind/ASan-style native memory tooling was not executed.

## Conclusion

Stage 7 local build and automated test validation passed. Device validation was
not executed.
