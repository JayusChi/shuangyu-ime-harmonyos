# 阶段 11.6.6 主机验证

| 命令 | 结果 |
| --- | --- |
| `cargo fmt --all --check` | PASS |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` | PASS |
| `cargo test --workspace` | 357 项 PASS |
| `hvigorw --no-daemon --mode module -p module=entry@default test` | 296/296 PASS |
| `scripts/build-native.ps1 -Abi all` | 两个 ABI PASS |
| `scripts/build-hap.ps1 -SkipRust -BuildMode debug` | PASS |
| `scripts/build-hap.ps1 -SkipRust -BuildMode release` | PASS |
| `scripts/verify-release-hap.ps1` | PASS |
| `scripts/test-release-resource-gate.ps1` | PASS |
| `scripts/test-xiaohe-yinxing-stage11_6_3-release-gate.ps1` | 6/6 负例 PASS |
| `scripts/audit-xiaohe-yinxing.ps1 -AllowBlocked` | 28/28 不可变 |
| `scripts/device-accept-xiaohe-yinxing-stage11_6_6.ps1` | 两轮 A-G PASS |
| `scripts/device-accept-xiaohe-yinxing-stage11_6_6-editor.ps1` | 日期提交、成对符号单次插入、UTF-16 光标探针 PASS |

冻结审计：

```text
source file count = 28
source manifest sha256 = ef93b39e05a0e11c818f8dd837b3f5b2e87777ab02aaba374765a846be7dce55
conversion contract sha256 = 2353a4b41bd9b1e9aeb1e309cb6ae657078de0d133f624921086f68d82ad8692
action fixture bytes = 2171
action fixture sha256 = 05a7653e44fe72c45b1b5b0dc1dc245baaafbc1f4becd5c2ec6c657687c59b63
```

Release 扫描确认：

- rawfile 仅 `resources/rawfile/production.lex`，大小仍为 3,734,484 bytes。
- 无 `.hsyx`、`.bundle`、动作 fixture、原始 `.txt/.ini`、trace、build report、source audit 或凭据命名资源。
- 无 `DebugCodeTable`/`DebugStage10` 编译标识。
- 无 `Stage1166EditorDebug`、`code-table-fixture` 或动作 fixture 标记。
- `module.json` 为 release、`debug=false`，无 `ohos.permission.INTERNET`。

编辑器设备证据：

```text
date committed = 2026-07-23
pair inserted = 2026-07-23🧑‍💻🧑‍💻
caret probe = 2026-07-23🧑‍💻x🧑‍💻
cursor after insert = 20 UTF-16 code units
target cursor = 15 UTF-16 code units
pair offset = 5 UTF-16 code units
result = PASS
```
