# 阶段 11.6.6 验收摘要

结论：

```text
11.6.6 RUNTIME COMPLETED
11.6.6 PRODUCTION DATA PARTIALLY DEFERRED
11.6.6 EDITOR-SIDE DEVICE ACTION ACCEPTANCE COMPLETED
```

主机门禁：

- Rust fmt：PASS
- Rust Clippy（workspace/all-targets/all-features/-D warnings）：PASS
- Rust workspace tests：357 项 PASS
- ArkTS：296/296 PASS
- FFI：24/24 PASS
- x86_64 / arm64-v8a Native：PASS
- internalDebug / Release HAP：PASS
- Release 源资源正向门禁、6 类负向门禁及最终 HAP 扫描：PASS
- 正式来源不可变：28/28 PASS

产物：

| 产物 | Bytes | SHA-256 |
| --- | ---: | --- |
| `entry/build/artifacts/entry-debug-unsigned.hap` | 40,689,541 | `45A06A265CCEEB4A5AB444073BF99CB7278F018253DB775621622C2C9C671C01` |
| `entry/build/artifacts/entry-release-unsigned.hap` | 12,147,016 | `25533514709552DBE196194215CC0F44815CE518E4EC24AD05D5110A14926A35` |
| `engine-rust/target/ohos/x86_64/libime_ffi.a` | 25,644,656 | `933D31D0B3287C0653123188812D5813E9DF4697EC93F28F2329BC188863BF18` |
| `engine-rust/target/ohos/arm64-v8a/libime_ffi.a` | 26,185,676 | `5C5D9249D13867F8EB61A537695C2E53CD542ACC3E8034A49B656575BCF6006F` |

设备：

- `127.0.0.1:5555`
- HarmonyOS `emulator 6.1.0.125(SP9DEVC00E16R1P1)`
- x86_64，`2880x1920`
- 两轮 force-stop/restart，internalDebug fixture A-G 均 PASS。
- MainAbility 的独立 ArkUI `TextInput` 外部编辑器动作验收 PASS。

外部编辑器实际提交 `2026-07-23`；成对 emoji 一次插入为 `2026-07-23🧑‍💻🧑‍💻`，插入探针后的文本为 `2026-07-23🧑‍💻x🧑‍💻`。IME 日志记录 `cursorAfterInsert=20, target=15, offsetUtf16=5, textUtf16Length=10`，确认本次 HarmonyOS 6.1 ArkUI `TextInput`/`InputClient` 路径使用 UTF-16 code unit 光标索引。

通用 fixture 证据位于 `device/`；外部编辑器 JSON、布局、截图和日志位于 `editor-device/`。
