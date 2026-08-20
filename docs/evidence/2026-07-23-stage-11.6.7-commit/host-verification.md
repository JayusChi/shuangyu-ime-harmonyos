# 阶段 11.6.7 主机验证

| 命令 | 结果 |
| --- | --- |
| `cargo fmt --all --check` | PASS |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` | PASS |
| `cargo test --workspace` | 373/373 PASS |
| `cargo test -p code-table-runtime stage11_6_7 -- --nocapture`（实现前） | 1 PASS / 3 FAIL，证明测试可捕获旧行为 |
| `hvigorw --no-daemon --mode module -p module=entry@default test` | 299/299 PASS |
| `scripts/build-native.ps1 -Abi all` | x86_64、arm64-v8a PASS |
| `scripts/build-hap.ps1 -SkipRust -BuildMode debug` | PASS |
| `scripts/build-hap.ps1 -SkipRust -BuildMode release` | PASS |
| `scripts/verify-release-hap.ps1` | PASS |
| `scripts/test-release-resource-gate.ps1` | PASS |
| `scripts/test-xiaohe-yinxing-stage11_6_3-release-gate.ps1` | 6/6 负例 PASS |
| `scripts/audit-xiaohe-yinxing.ps1 -AllowBlocked` | 28/28 不可变 |
| `scripts/verify-code-table-fixture.ps1` | PASS；两次 bundle SHA-256 相同 |
| `scripts/device-accept-xiaohe-yinxing-stage11_6_7.ps1 -Target 127.0.0.1:5555` | 两轮 A-I/L-N 共 12 项运行时页 PASS |

冻结审计：

```text
source file count = 28
source manifest sha256 = ef93b39e05a0e11c818f8dd837b3f5b2e87777ab02aaba374765a846be7dce55
conversion contract sha256 = 2353a4b41bd9b1e9aeb1e309cb6ae657078de0d133f624921086f68d82ad8692
fixture bundle bytes = 2024260
fixture bundle sha256 = 345887c1f6052514758a1d3f53b4f280e6ff04086ab1736582c9a8ccd42df71c
```

Release 扫描确认正常包通过，正式 bundle、internalDebug fixture、动作 fixture、原始 `.txt/.ini`、trace、构建报告、审计资料、凭据命名资源和网络权限均未进入最终 Release HAP。Debug 临时生成目录在构建结束后不存在。

未执行/未通过声明：

- J/K 正向、反向空码切分：合同阻塞，未实现、未测试。
- 11.6.7 独立 ArkUI `TextInput` 最终文本 A-N：未执行；调试页结果不可替代该项。
- ARM64 物理真机、Pad 分屏、外接物理键盘：未执行。
- `.git` 目录为空，`git status` / `git diff` 报“not a git repository”；无法提供 Git 级初末差异或 clean-worktree 证明。
