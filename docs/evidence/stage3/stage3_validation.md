# Stage 3 Validation

## 2026-07-08 Local Acceptance

Environment:

- Windows host with DevEco Studio SDK
- DevEco Studio root: `C:\Program Files\Huawei\DevEco Studio`
- Harmony SDK root: `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony`
- Rust: `rustc 1.96.1`
- hvigor: `6.24.3`

Automated command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage3.ps1
```

Result: passed.

Covered steps:

- environment check
- Rust format, clippy, and tests
- x86_64 and arm64-v8a native artifact build
- ArkTS unit tests
- HAP build
- source-level guards for Stage 3 keyboard UI engineering
- artifact summary
- device install and IME status skipped by request

Artifacts:

- `engine-rust/target/ohos/x86_64/libime_ffi.a`: 21,935,504 bytes
- `engine-rust/target/ohos/arm64-v8a/libime_ffi.a`: 22,580,292 bytes
- `entry/build/default/outputs/default/entry-default-unsigned.hap`: 5,365,631 bytes

ArkTS test coverage:

- Stage 2 controller tests: 9 registered cases
- Stage 3 keyboard UI engineering tests: 24 registered cases

Source guards:

- Stage 3 design constants, layout model, candidate bar, key components, and `KeyboardRootStage3` exist.
- `InputPanelController` loads `KeyboardRootStage3`.
- `InputPanelController` stops when panel creation fails and does not mark the keyboard visible.
- `KeyboardLayoutSpec` does not reverse QWERTY row order.
- `KeyboardRootStage3` does not directly import IME Kit or `libime_bridge.so`.
- `DeleteRepeatController` exposes destroy/clear-timer behavior.
- Stage 2 session state, keyboard action routing, and delete fallback are preserved.

Device note:

This validation intentionally did not require real phone or online device runtime acceptance. A prior optional device attempt installed and enabled the HAP, but the system refused panel creation when focusing the test field:

```text
InputPanelController: createPanel failed: {"code":1,"message":"error is out of definition. "}
JsInputMethodEngineSetting CreatePanel failed
current is not default ime
```

The code now keeps the session state honest when that environment-level failure happens. Full runtime clicking, long-press delete, and candidate-bar visual acceptance should be repeated later with a stable device/input-method environment by running:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage3.ps1 -DeviceValidation
```

## 2026-07-08 Runtime Fix Verification

Problem fixed:

- The Stage 3 panel was loaded with `setUiContent('presentation/keyboard/KeyboardRootStage3')`, but `main_pages.json` did not register `KeyboardRootStage3`.
- After registering the page, HAP compilation exposed strict ArkTS issues in the Stage 3 page and components. These were fixed by renaming custom component callback/color props away from ArkUI built-in attribute names and by using typed `KeyboardAction` constants.

Automated command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage3.ps1 -DeviceValidation
```

Result: passed.

Runtime device:

- Target: `127.0.0.1:5555`
- `ime -g`: `com.example.harmonyos_input`, `FULL_EXPERIENCE_MODE`

Manual runtime steps:

- Started `EntryAbility`.
- Clicked the demo `TextInput`.
- Confirmed Stage 3 keyboard panel appeared.
- Clicked a letter key and confirmed the `TextInput` content changed to `a`.

Runtime evidence:

- `docs/evidence/stage3/stage3_after_input_click_layout.json`
- `docs/evidence/stage3/stage3_after_input_click.jpeg`
- `docs/evidence/stage3/stage3_after_letter_input_layout.json`
