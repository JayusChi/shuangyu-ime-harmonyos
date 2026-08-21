# Stage 0 Feasibility

## Goal

Verify the real chain:

```text
InputMethodExtensionAbility -> test keyboard -> ArkTS gateway -> C++ Node-API -> Rust C ABI -> fixed Rust candidates -> C++ object conversion -> ArkTS display -> IME Kit commit
```

## Implemented Chain

- ArkTS input method extension: `entry/src/main/ets/inputmethod/Stage0InputMethodAbility.ets`
- Test keyboard UI: `entry/src/main/ets/stage0/Stage0Keyboard.ets`
- Controller: `entry/src/main/ets/stage0/Stage0DemoController.ets`
- IME wrapper: `entry/src/main/ets/infrastructure/ime/ImeConnectionService.ets`
- Native gateway: `entry/src/main/ets/infrastructure/native/NativeEngineGateway.ets`
- Node-API target: `ime_bridge`
- Native module import: `libime_bridge.so`
- Rust crate: `engine-rust/crates/ime-ffi`

## Rust Artifact

Artifact type: static library, `libime_ffi.a`.

Expected copied locations:

- `engine-rust/target/ohos/arm64-v8a/libime_ffi.a`
- `engine-rust/target/ohos/x86_64/libime_ffi.a`

## Verification Results

| Area | Result | Notes |
| --- | --- | --- |
| Rust code written | 通过 | FFI functions, fixed JSON, error codes, panic capture implemented |
| Rust fmt/clippy/test | 通过 | `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace` |
| Rust cross compile | 通过 | Generated non-empty `libime_ffi.a` for `arm64-v8a` and `x86_64` |
| C++ syntax/check through build | 通过 | `BuildNativeWithCmake` and `BuildNativeWithNinja` passed in HAP build |
| C++ CMake configuration | 通过 | CMake consumed `engine-rust/target/ohos/{abi}/libime_ffi.a` for both ABI filters |
| HAP build | 通过 | `entry/build/default/outputs/default/entry-default-unsigned.hap`, 5,251,502 bytes |
| Emulator install/listing | 通过 | Stage 0 当时使用旧包名 `com.example.harmonyos_input` 完成验证；当前正式工程身份已变更为 `com.corrosion.shuangyuime` |
| Emulator runtime verification | 通过 | Keyboard page loads, panel rect is `[0, 2279, 1320, 420]`, `A/B` insert text, Rust returns 3 candidates, candidate commit inserts text, delete/space/enter/hide all have successful hilog evidence. |
| Real device verification | 待人工验证 | `hdc list targets` returned `[Empty]` |

## Known Issues

- `%USERPROFILE%\.cargo\bin` is not present in the current Codex PowerShell PATH, although Rust is installed there. Scripts prepend it for the current process when needed.
- `DEVECO_SDK_HOME` must point to `C:\Program Files\Huawei\DevEco Studio\sdk` for hvigor on this machine.
- `arm64-v8a` and `x86_64` are both configured, so both Rust artifacts are required for the current build profile; both are now generated.
- The input method extension registration uses `type: "inputMethod"` without the original `ohos.extension.input_method` metadata profile, which made the current emulator list and switch to this input method.
- HAP build warns that no signingConfigs profile is configured and sign `hos_hap` is skipped.
- The initial `ohos.extension.input_method` metadata profile made the current emulator skip the input method in `ime -l`; removing that metadata made it visible and switchable.
- Runtime hilog before the panel fix showed `Stage0ImeConnection: IME session bound`, followed by system keyboard panel rectangles with height `1`, which explains why the input field had focus but no visible keyboard.
- `stage0/Stage0Keyboard` must be listed in `resources/base/profile/main_pages.json`; otherwise `setUiContent` fails with `path should be a path to specific page`.
- ArkUI dimensions are vp while `Panel.resize` uses physical pixels on this emulator; the stage 0 keyboard uses compact controls so every verification button fits inside the `420px` keyboard content area.

## Next Required Work Before Stage 1

1. Connect an ARM64 HarmonyOS NEXT device and repeat the same runtime verification.
2. Configure signing if the target device rejects unsigned debug HAPs.
3. Use the verified Stage 0 chain as the baseline for Stage 1 real shuangpin input logic.
