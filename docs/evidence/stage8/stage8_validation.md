# Stage 8 Validation Evidence

Date: 2026-07-09

Environment:

- OS: Microsoft Windows NT 10.0.26200.0
- PowerShell: 5.1.26100.8737
- DevEco Studio root: `C:\Program Files\Huawei\DevEco Studio`
- Harmony SDK: `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony`
- hvigorw: 6.24.3
- ohpm: 6.1.2.285
- Node.js: v22.19.0
- rustc: 1.96.1
- cargo: 1.96.1

## Commands Run

```powershell
cargo fmt
cargo test -p sentence-decoder
cargo test -p ime-engine
cargo test -p ime-ffi
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo run -p lexicon-builder -- --input ..\dictionaries\source\stage8_sentence_test.tsv --output ..\dictionaries\generated\stage8_sentence_test.lex --lexicon-version 8 --strict
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'; & 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust
powershell -ExecutionPolicy Bypass -File scripts\verify-stage8.ps1
```

## Results

| Item | Result | Count / Artifact |
| --- | --- | --- |
| Rust format | Passed | `cargo fmt --check` inside `verify-stage8.ps1` |
| Rust clippy | Passed | workspace all targets, `-D warnings` |
| sentence-decoder tests | Passed | 19 tests |
| ime-engine unit tests | Passed | 25 tests |
| Stage 7 fixture | Passed | 1 fixture test |
| Stage 8 fixture | Passed | 1 fixture test, 5 cases |
| ime-ffi tests | Passed | 14 tests |
| Rust workspace tests | Passed | 126 explicit Rust tests |
| Stage 4 parser regression | Passed | 8 tests |
| Stage 6 lexicon build/verify | Passed | 46 entries, 3,076 bytes |
| Stage 8 lexicon build/verify | Passed | 16 entries, 1,049 bytes |
| Native x86_64 build | Passed | `engine-rust/target/ohos/x86_64/libime_ffi.a` |
| Native arm64-v8a build | Passed | `engine-rust/target/ohos/arm64-v8a/libime_ffi.a` |
| ArkTS unit tests | Passed | hvigor unit test build successful |
| HAP build | Passed | `entry/build/default/outputs/default/entry-default-unsigned.hap` |
| Architecture boundary checks | Passed | `scripts/verify-stage8.ps1` |

## Artifacts

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `dictionaries/generated/stage8_sentence_test.lex` | 1,049 bytes | `9C54A2CD65A3C19C9ECC13EFE5F2A351957C791A15C30AA96B357E2B65AFDDEE` |
| `entry/src/main/resources/rawfile/stage8_sentence_test.lex` | 1,049 bytes | `9C54A2CD65A3C19C9ECC13EFE5F2A351957C791A15C30AA96B357E2B65AFDDEE` |
| `engine-rust/target/ohos/x86_64/libime_ffi.a` | 23,488,744 bytes | `B0A487924BD7A2C48759C3341221F5BBE2119B3A54B853BC01FBAB7C4D810380` |
| `engine-rust/target/ohos/arm64-v8a/libime_ffi.a` | 24,084,858 bytes | `D079F7696D0049FD3146DC94FA6749CD132A00327682F2CF4630E7081327303D` |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 6,808,306 bytes | `840C5B6DFC1C6B47047CAE4C64225EE4CD3CBAA386E57D81681FE3CF5388AB80` |

## Stage 8 Test Lexicon

- Source: `dictionaries/source/stage8_sentence_test.tsv`
- Build command: `cargo run -p lexicon-builder -- --input ..\dictionaries\source\stage8_sentence_test.tsv --output ..\dictionaries\generated\stage8_sentence_test.lex --lexicon-version 8 --strict`
- Input rows: 17
- Accepted rows: 17
- Merged duplicates: 1
- Entries written: 16
- Pinyin keys: 10
- Binary checksum: `e220942f`

## Device Evidence

Date: 2026-07-09

Device:

- Target: `127.0.0.1:5557`
- Type: HarmonyOS emulator
- Version: `emulator 6.1.0.125(SP9DEVC00E120R4P11)`
- ABI: `x86_64`
- Bundle: `com.example.harmonyos_input`
- HAP SHA-256: `D02D5E52F3F459B7C9708EE3B277BA53C04F3E2E8E6E5FB1493B8A16D2757C98`

Results:

| Item | Result | Evidence |
| --- | --- | --- |
| HAP install and IME enable | Passed | `docs/evidence/stage9/device/final_acceptance_2026-07-09.log` |
| `nihc` candidate `你好` | Passed | `docs/evidence/stage9/device/final_stage8_nihc_candidates.png` |
| `nihc` commit | Passed | `docs/evidence/stage9/device/final_stage8_nihc_committed.json` |
| `uurufa` full candidate `输入法` | Passed | `docs/evidence/stage9/device/final_stage8_uurufa_candidates.png` |
| `uurufa` partial candidate `输入` | Passed | `docs/evidence/stage9/device/final_stage8_uurufa_partial_committed.json` |
| remaining `fa` candidate `法` | Passed | `docs/evidence/stage9/device/final_stage8_uurufa_full_committed.json` |

During device acceptance, `CandidateBar.ets` was adjusted so the page-control overlay is transparent to hit testing; candidate clicks now reach the candidate row on device.

## Not Executed

- Real deletion rollback on simulator/device.
- Physical-device validation.
- Valgrind, ASan, or dedicated leak tooling.

Stage 8 has satisfied local build, automated test acceptance, and emulator
device validation.
