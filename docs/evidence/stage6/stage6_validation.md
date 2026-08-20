# Stage 6 Validation Evidence

## Execution

- Date: 2026-07-08
- OS: Microsoft Windows NT 10.0.26200.0
- PowerShell: 5.1.26100.8737
- DevEco Studio root: `C:\Program Files\Huawei\DevEco Studio`
- Harmony SDK root: `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony`
- CMake: 3.28.2
- ohpm: 6.1.2.285
- hvigorw: 6.24.3
- Node.js: v22.19.0
- Rust: `rustc 1.96.1 (31fca3adb 2026-06-26)`
- Cargo: `cargo 1.96.1 (356927216 2026-06-26)`

## Commands

```powershell
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo run -p lexicon-builder -- --input ..\dictionaries\source\stage6_test.tsv --output ..\dictionaries\generated\stage6_test.lex --lexicon-version 1 --strict
cargo run -p lexicon-builder -- --verify ..\dictionaries\generated\stage6_test.lex
cargo run -p lexicon-builder -- --input ..\dictionaries\source\stage6_test.tsv --output C:\Users\CX-03\DevEcoStudioProjects\HarmonyOS_Input\engine-rust\target\stage6-verify\temporary-a.lex --lexicon-version 1 --strict
cargo run -p lexicon-builder -- --input ..\dictionaries\source\stage6_test.tsv --output C:\Users\CX-03\DevEcoStudioProjects\HarmonyOS_Input\engine-rust\target\stage6-verify\temporary-b.lex --lexicon-version 1 --strict
cargo test -p ime-ffi
cargo test -p shuangpin-parser --test stage4_cases
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust
powershell -ExecutionPolicy Bypass -File scripts\verify-stage6.ps1
```

## Results

| Item | Result |
| --- | --- |
| Stage 6 verification script | PASS |
| Rust fmt | PASS |
| Rust clippy | PASS |
| Rust workspace tests | PASS, 66 explicit Rust tests passed |
| CLI integration tests | PASS, 4 tests passed |
| Deterministic build tests | PASS, covered same input, row order, duplicate order, LF/CRLF, pinyin normalization |
| Corrupted binary tests | PASS |
| Stage 5 FFI regression | PASS, 11 tests passed |
| Stage 4 parser regression | PASS, 8 tests passed |
| Native x86_64 OHOS artifact | PASS, 22,676,986 bytes |
| Native arm64-v8a OHOS artifact | PASS, 23,293,962 bytes |
| ArkTS unit tests | PASS, hvigor unit test build successful |
| HAP build | PASS, `entry-default-unsigned.hap`, 6,222,603 bytes |
| Source boundary checks | PASS |

## Lexicon Artifact

- Source: `dictionaries/source/stage6_test.tsv`
- Generated binary: `dictionaries/generated/stage6_test.lex`
- Input rows: 48
- Accepted rows: 48
- Merged duplicates: 2
- Entries written: 46
- Pinyin keys: 45
- Output bytes: 3,076
- Magic: `HSPLEX01`
- Format version: 1.0
- Builder version: 1
- Lexicon version: 1
- Payload checksum algorithm: IEEE CRC32
- Payload checksum: `1be78f33`
- File SHA-256: `E7B84B676C3F40D2FD2DAE0E1017FEE4C665432E88DFE2A6B0C575AC8B5A83E3`

## Determinism

```text
第一次构建哈希：E7B84B676C3F40D2FD2DAE0E1017FEE4C665432E88DFE2A6B0C575AC8B5A83E3
第二次构建哈希：E7B84B676C3F40D2FD2DAE0E1017FEE4C665432E88DFE2A6B0C575AC8B5A83E3
文件字节是否完全一致：true
```

The verification script cleaned `target\stage6-verify` after comparison.

## Unexecuted Items

- Device install and real IME typing validation were not part of `verify-stage6.ps1`.
- Dedicated Valgrind/ASan-style native memory tooling was not executed.
- HAP signing remains debug/unsigned; release signing was not configured.

## Notes and Risks

- The test lexicon is hand-authored and intentionally small. It is not a
  production Chinese dictionary.
- The binary reader validates offsets, lengths, UTF-8, index ranges, and CRC32,
  but stage 7 still needs runtime query APIs and broader corpus coverage.
- The builder is under `engine-rust/tools/lexicon-builder` to satisfy Cargo
  workspace rules; the repository-level `tools/lexicon-builder` directory points
  to that package.
