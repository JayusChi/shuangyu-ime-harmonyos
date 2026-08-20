# Host gate results

权威运行：`runs/20260727-121537-fe53c474` 与
`runs/20260727-122431-a293a812`。

| 门禁 | 结果 |
| --- | --- |
| Rust workspace | PASS，387/387 |
| FFI | PASS，26/26 |
| ArkTS | PASS，323/323 |
| fmt | PASS |
| Clippy | PASS |
| x86_64 Native | PASS |
| arm64-v8a Native | PASS |
| internalDebug HAP | PASS |
| unsigned Release HAP | PASS |
| signed Release HAP | PASS |
| unsigned/signed Release 正向门禁 | PASS |
| 通用 Release 负向门禁 | PASS |
| 音形 Release 负向门禁 | PASS |
| signed HAP 签名验证 | PASS |
| 正式来源不可变 | PASS，28/28 |
| 生产输出双构建 | PASS，15/15 路径、大小、哈希一致 |

接口版本 4、ABI 版本 4、设置 schema 2，默认方案 `xiaohe`，均与冻结合同一致。
