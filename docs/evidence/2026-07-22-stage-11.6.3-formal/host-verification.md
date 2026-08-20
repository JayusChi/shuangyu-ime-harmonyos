# 主机验证记录

执行日期：2026-07-22；工作区：`HarmonyOS_Input`。

| 验证 | 结果 |
|---|---|
| `cargo fmt --all --check` | PASS |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` | PASS |
| `cargo test --workspace` | PASS |
| ArkTS `entry@default test` | PASS / BUILD SUCCESSFUL |
| `scripts/build-native.ps1 -Abi x86_64` | PASS |
| `scripts/build-native.ps1 -Abi arm64-v8a` | PASS |
| 正式 bundle verify-only | PASS |
| Debug HAP 构建与临时资源清理 | PASS |
| 两轮设备 A～J（轮间 force-stop/restart） | PASS |
| Release HAP 构建与内容扫描 | PASS |
| 正式 `.hsyx` 负向注入 | PASS（按预期拒绝） |
| fixture 负向注入 | PASS（按预期拒绝） |
| 原始 txt 负向注入 | PASS（按预期拒绝） |
| trace 负向注入 | PASS（按预期拒绝） |
| build/audit report 负向注入 | PASS（按预期拒绝） |
| `INTERNET` 权限负向注入 | PASS（按预期拒绝） |

关键产物：

- x86_64 静态库：25,422,640 bytes，SHA-256 `1E2EAF4DE35F7F2A56E3B175035028DAB36AA218E9941D51888E89D14C199B82`。
- arm64-v8a 静态库：25,968,256 bytes，SHA-256 `0251CA32C8C0541B389828DE64DEF1FF7E89A380738466063E458009BE17F1D9`。
- Debug HAP：40,387,851 bytes，SHA-256 `712DD5051B70D181BD178CD75755F38104F0DD5F03C0D6359EDAE0E028FB2CB9`。
- Release HAP：11,952,684 bytes，SHA-256 `4034F1EFEF559BC3A004119410966684B88FD0AA2BFF45DB00857C4612CC7A77`。

设备运行的逐项实际候选、错误码、候选 ID 与两轮 passLabels 以 `device/device-acceptance.json` 为准；性能每进程原始值以 `performance-release.json` 为准。
