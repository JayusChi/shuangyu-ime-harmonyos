# Stage 5 Validation Evidence

Date: 2026-07-08

## Scope

Stage 5 implements the formal ArkTS -> C++ -> Rust interface for the Stage 4 shuangpin parser. It does not implement dictionaries, Chinese candidates, candidate commit, pagination, ranking, settings, or additional schemes.

## Executed Commands

| Step | Command | Result | Notes |
| --- | --- | --- | --- |
| Rust format | `cargo fmt --check` | PASS | Executed under `engine-rust` |
| Rust clippy | `cargo clippy --workspace --all-targets -- -D warnings` | PASS | Unsafe C ABI entries document their safety contracts |
| Rust workspace tests | `cargo test --workspace` | PASS | 45 explicit Rust tests passed |
| Rust native artifacts | `powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all` | PASS | x86_64 and arm64-v8a static libraries generated |
| HAP build | `powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust` | PASS | C++/ArkTS/HAP build generated unsigned HAP |
| ArkTS unit tests | `$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'; hvigorw --no-daemon --mode module -p module=entry@default test` | PASS | Hvigor unit test build successful |
| Full Stage 5 verification | `powershell -ExecutionPolicy Bypass -File scripts\verify-stage5.ps1` | PASS | Device validation skipped because it was not requested |

## Rust Test Coverage

- Formal `ImeEngine` create, version, process key, incomplete state, complete state, invalid parser state, continuous input, backspace, reset, and failed scheme switch preservation.
- Rust C ABI create/destroy, empty config, invalid config, invalid scheme, null output, null handle, invalid UTF-8, empty/multiple/digit/symbol keys, process/backspace/reset/changeScheme JSON, buffer free, repeated free after clearing, destroy clearing, panic capture, ABI version, engine version.
- Stability loops: 1000 create/destroy cycles, 10000 input/delete operations, 1000 resets, repeated valid/invalid scheme changes, repeated buffer allocation/free.
- Stage 4 parser fixture regression remains registered and passing.

## Artifact Summary

| Artifact | Path | Size |
| --- | --- | --- |
| x86_64 Rust static library | `engine-rust/target/ohos/x86_64/libime_ffi.a` | 22,676,986 bytes |
| arm64-v8a Rust static library | `engine-rust/target/ohos/arm64-v8a/libime_ffi.a` | 23,293,962 bytes |
| x86_64 native module | `entry/build/default/intermediates/stripped_native_libs/default/x86_64/libime_bridge.so` | 1,639,144 bytes |
| arm64-v8a native module | `entry/build/default/intermediates/stripped_native_libs/default/arm64-v8a/libime_bridge.so` | 1,561,592 bytes |
| HAP | `entry/build/default/outputs/default/entry-default-unsigned.hap` | 6,222,603 bytes |
| ArkTS test report | `entry/.test/default/outputs/test/reports/index.html` | 9,157 bytes |
| Stage 5 evidence | `docs/evidence/stage5/stage5_validation.md` | this file |

## Device Validation

Not executed. `scripts\verify-stage5.ps1` was run without `-DeviceValidation`, so no device install, IME enable, keyboard display, or runtime screenshot result is claimed.

## Notes

- HAP signing remains debug/unsigned; hvigor emitted the existing warning that no signingConfigs profile is configured.
- The verification script is local build/test evidence only. It does not prove Valgrind/ASan leak freedom or real-device behavior.
