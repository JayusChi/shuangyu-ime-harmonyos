# Stage 2 Validation

## 2026-07-08 Layout Order Fix

Environment:

- Windows host with DevEco Studio SDK
- x86_64 emulator target: `127.0.0.1:5555`
- Bundle: `com.example.harmonyos_input`
- Current IME mode reported by device: `FULL_EXPERIENCE_MODE`

Automated command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage2.ps1
powershell -ExecutionPolicy Bypass -File scripts\verify-stage2.ps1 -DeviceValidation
```

Result: passed.

Covered steps:

- environment check
- Rust format, clippy, and tests
- x86_64 and arm64-v8a native artifact build
- ArkTS unit tests, including QWERTY natural row order
- HAP build
- source-level guards for QWERTY natural rendering, panel height, stage 2 keyboard/session code, and stage 1 delete fallback
- final device install and IME status check with `-DeviceValidation`

Device commands:

```powershell
& "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" list targets
& "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" install -r entry\build\default\outputs\default\entry-default-unsigned.hap
& "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" shell ime -e com.example.harmonyos_input -f
& "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" shell ime -g
```

Device result:

- `list targets`: `127.0.0.1:5555`
- install: `install bundle successfully`
- enable IME: `Succeeded in enabling IME. status:FULL_EXPERIENCE_MODE`
- IME status: `The current input method is: com.example.harmonyos_input, status: FULL_EXPERIENCE_MODE`

Runtime layout evidence:

`stage2_keyboard_order_fix_layout.json`:

- Q W E R T Y U I O P visible at Y=1939..2086
- A S D F G H J K L visible at Y=2114..2261
- Z X C V B N M visible at Y=2289..2436
- `英`, `空格`, `删除`, `回车`, `隐藏` visible at Y=2464..2611

`stage2_keyboard_order_fix_input_layout.json`:

- tapped Q, W, delete, space, and language toggle
- focused TextInput contained `q ` with length 2
- mode label changed to `中文占位`
- status showed `OK`

`stage2_keyboard_order_fix_after_hide_layout.json`:

- tapped `隐藏`
- keyboard button count became 0
- focused TextInput retained `q ` with length 2

`stage2_visual_key_fix_layout.json` and `stage2_visual_key_fix.jpeg`:

- replaced `Button(this.keyLabel(spec))` key rendering with an explicit key surface plus centered `Text`
- Q W E R T Y U I O P are visible in the first row
- A S D F G H J K L are visible in the second row
- Z X C V B N M are visible in the third row
- `英`, `空格`, `删除`, `回车`, `隐藏` are visible in the fourth row
- visual screenshot no longer shows blank first-row keys, clipped second-row glyphs, or `...` for function keys

Root cause note:

The visible "missing letters" symptom has two forms. Missing rows can come from keyboard content being clipped when the soft keyboard panel height is too small or the lower rows are pushed under the system keyboard auxiliary area. Blank or partial glyphs inside visible keys came from using `Button(label)` for very narrow keyboard keys; the layout tree still had the correct labels, but the real Button text renderer clipped or ellipsized them visually. The "reversed rows" symptom comes from applying `.reverse()` during `KeyboardRoot` rendering instead of keeping `QWERTY_KEY_ROWS` in natural top-to-bottom order. The current fix keeps natural row order, renders key labels with explicit `Text`, and adds source guards for row order, Button-label regression, and panel height.

ARM64 real-device runtime verification is still pending.

---

Date: 2026-07-07

Environment:

- Windows host with DevEco Studio SDK
- x86_64 emulator target: `127.0.0.1:5555`
- Bundle: `com.example.harmonyos_input`
- Current IME mode reported by device: `FULL_EXPERIENCE_MODE`

## Automated Checks

Command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage2.ps1 -DeviceValidation
```

Result: passed.

Covered steps:

- environment check
- Rust format, clippy, and tests
- x86_64 and arm64-v8a native artifact build
- ArkTS unit tests
- HAP build
- source-level guards for stage 2 keyboard/session code and stage 1 delete fallback
- HAP install
- IME enable
- IME status query

## Runtime Layout Evidence

`stage2_keyboard_visible_full_layout.json`:

- Q/W/A/B keys visible
- `英`, `空格`, `删除`, `回车`, `隐藏` visible
- session status shows `会话 active`
- keyboard status shows `visible`
- native regression status shows `Rust 0.0.1-stage0` and `success`

`stage2_after_input_delete_layout.json`:

- tapped Q, W, space, A, delete
- focused TextInput contained `qw` after delete removed the last letter

`stage2_space_input_layout.json`:

- tapped space and A again
- focused TextInput contained `qw  a`, confirming visible internal space insertion

`stage2_after_hide_layout.json`:

- tapped `隐藏`
- keyboard nodes disappeared from the layout tree
- TextInput remained with `qw  a`

## Notes

`回车` is routed through `InputClient.sendKeyFunction(ENTER_KEY_TYPE_NEWLINE)` and covered by ArkTS controller tests. The current single-line TextInput is not used as a visual newline assertion.

ARM64 real-device runtime verification is still pending.
