# Stage 4 Validation Evidence

Date: 2026-07-08

## Conclusion

阶段 4 已完成。核心解析器本地验收不依赖设备在线；设备安装和 IME 状态验证本轮未请求。

## Key Artifacts

- Xiaohe schema: `engine-rust/schemas/xiaohe.json`
- Pinyin validator crate: `engine-rust/crates/pinyin-syllable`
- Schema crate: `engine-rust/crates/shuangpin-schema`
- Parser crate: `engine-rust/crates/shuangpin-parser`
- Fixture data: `engine-rust/tests/fixtures/stage4_parser_cases.tsv`
- Verification script: `scripts/verify-stage4.ps1`
- HAP: `entry/build/default/outputs/default/entry-default-unsigned.hap`
- x86_64 native artifact: `engine-rust/target/ohos/x86_64/libime_ffi.a`
- arm64-v8a native artifact: `engine-rust/target/ohos/arm64-v8a/libime_ffi.a`

## Sources Used For Scheme Rules

- [Wikipedia: 双拼](https://zh.wikipedia.org/wiki/%E5%8F%8C%E6%8B%BC), especially the general two-key shuangpin principle, zero-initial behavior, and Xiaohe/FlyPY scheme notes.
- [Wikipedia: 汉语拼音](https://zh.wikipedia.org/wiki/%E6%B1%89%E8%AF%AD%E6%8B%BC%E9%9F%B3), for Mandarin final categories and pinyin normalization context.

The concrete Xiaohe key table is encoded in `engine-rust/schemas/xiaohe.json` and locked by parser fixtures.

## Commands Executed

```powershell
cargo test --workspace
cargo fmt --check
cargo fmt
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo test -p shuangpin-parser --test stage4_cases
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust
powershell -ExecutionPolicy Bypass -File scripts\verify-stage4.ps1
```

## Verification Matrix

| Item | Result | Evidence |
| --- | --- | --- |
| Rust format | PASS | `cargo fmt --check` |
| Rust clippy | PASS | `cargo clippy --workspace --all-targets -- -D warnings` |
| Rust workspace tests | PASS | 34 tests passed |
| Stage 4 parser tests | PASS | `cargo test -p shuangpin-parser --test stage4_cases`, 8 tests passed |
| x86_64 Native build | PASS | `libime_ffi.a`, 22,532,694 bytes, SHA-256 `967867E291092389C4B6F21AEAC9F623B86A189E7F645B862997338AF2A208E8` |
| arm64-v8a Native build | PASS | `libime_ffi.a`, 23,155,206 bytes, SHA-256 `4998CF0A50CDC25F3F7819F5F2F87196187CE48CC7FCFFDCB16FDE4A4ADE83B1` |
| ArkTS unit tests | PASS | `hvigorw --no-daemon --mode module -p module=entry@default test` |
| HAP build | PASS | `entry-default-unsigned.hap`, 5,915,084 bytes |
| Stage 4 source boundary checks | PASS | `scripts/verify-stage4.ps1` |
| Stage 3 regression | PASS | ArkTS tests, HAP build, fixed candidate route and Stage3 entry source checks |
| Device validation | SKIP | `-DeviceValidation` not requested |

## Rust Test Count

- `engine-protocol`: 1
- `ime-engine`: 2
- `ime-ffi`: 7
- `pinyin-syllable`: 4
- `shuangpin-parser` unit tests: 2
- `shuangpin-parser` fixture tests: 8
- `shuangpin-schema`: 10

Total: 34 tests.

## Boundary Check Summary

- No Xiaohe/shuangpin/pinyin rules were added under `entry/src/main/cpp`.
- No shuangpin parser implementation was added under `entry/src/main/ets`.
- `shuangpin-parser` contains no HarmonyOS API imports or Node-API code.
- Existing C ABI and ArkTS native declarations were not changed.
- `KeyboardRootStage3` page registration and fixed candidate regression route remain present.

## Unverified Or Deferred

- Device install, IME enablement, and runtime panel popup were not rerun in this stage.
- Stage 4 parser is not exposed through formal C ABI yet.
- No dictionary, candidate lookup, candidate ranking, user model, or settings UI was implemented.
- HAP signing remains unsigned/debug.
