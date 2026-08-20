# 阶段 11.6.7 验收摘要

结论：

```text
11.6.7 PARTIALLY COMPLETED
EMPTY-CODE SPLIT CONTRACT BLOCKED
```

准入审计确认四码唯一自动提交、有效更长编码保护、第五键顶屏、当前键单次重放和空码清屏不依赖阶段 11.6.6 延期的正式动作数据。正向/反向空码切分缺少权威扫描顺序、切分点裁决、提交段和剩余段合同，因此没有实现，也没有从 Android INI 推导。

主机门禁：

- test-first：新增 11.6.7 定向测试在旧实现上为 1 PASS / 3 FAIL；实现后全数通过。
- Rust fmt、workspace Clippy（all-targets/all-features/-D warnings）：PASS。
- Rust workspace：373/373 PASS；其中 FFI 25/25 PASS、码表运行时 60/60 PASS。
- ArkTS：299/299 PASS。
- x86_64 / arm64-v8a Native：PASS。
- internalDebug / Release HAP：PASS。
- Release 资源正向门禁、6 类负向门禁及最终 HAP 扫描：PASS。
- 正式来源不可变：28/28 PASS。

产物：

| 产物 | Bytes | SHA-256 |
| --- | ---: | --- |
| `entry/build/artifacts/entry-debug-unsigned.hap` | 40,715,012 | `E8B161FD39E8BBFA7D87FF2CB2AB98328951AFA794E4935B539352CFEF34287D` |
| `entry/build/artifacts/entry-release-unsigned.hap` | 12,155,244 | `42FFD26AC543430C9F41309F492ED30F38095AA52BD65DF8EF9901692A1D8890` |
| `engine-rust/target/ohos/x86_64/libime_ffi.a` | 25,652,724 | `BC28CDC3D00F8104AA43171C7979C354EA2C091CF9A862805B2BF5AB034C2CF9` |
| `engine-rust/target/ohos/arm64-v8a/libime_ffi.a` | 26,194,360 | `18CD8541BA6A0BA004A8B51ABC7FBBF67C17E24E76745A6DE2EE3C0AD0DCDE59` |

设备：

- `127.0.0.1:5555`
- HarmonyOS `emulator 6.1.0.125(SP9DEVC00E16R1P1)`
- x86_64，`2880x1920`
- 两轮 force-stop/restart，冻结范围 A-I、L-N 共 12 个 internalDebug 运行时页用例均 PASS。

上述设备结果使用真实 ArkTS → Node-API C++ → Rust 链路，但页面直接驱动 `EngineCoordinator`，不等于独立 ArkUI `TextInput` 最终文本验收。J/K 因空码切分合同阻塞未执行；11.6.7 独立编辑框 A-N 验收和 ARM64 物理真机均不得写成通过。

设备 JSON、布局、截图和脱敏日志位于 `device/`。
