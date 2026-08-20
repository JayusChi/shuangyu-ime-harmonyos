# 小鹤音形改进阶段 1 验收报告

日期：2026-07-27  
结论：主机与 x86_64 HarmonyOS 6.1 Phone 模拟器运行时页范围 `COMPLETED`；真实输入框与 ARM64 真机仍待验收。

## 1. 原因定位

旧实现位于 `engine-rust/crates/code-table-runtime/src/query.rs`：

1. `query_exact_or_prefix_with_snapshot` 先全局判断是否存在精确编码。
2. 只要任一启用分类存在精确候选，整个查询只走 `Exact` 分支。
3. `ni` 等二简存在时，`ni*` 的三码、四码候选不会进入候选合并和分页。

`engine-rust/crates/code-table-runtime/src/state.rs` 的状态机此前固定调用该通用函数，`engine-rust/crates/ime-engine/src/formal.rs` 在正式方案注册时也没有查询策略字段。这是二码通常只有一两个候选的直接原因。

## 2. 实现方案

- 新增 `CodeTableQueryStrategy`：
  - `ExactOnly`：只取完整精确编码。
  - `ExactOrPrefixFallback`：有精确只取精确，无精确才取前缀。
  - `ProgressiveXiaoheYinxing`：一至三码取精确＋严格更长前缀，四码只取精确。
- 保留 `query_exact_or_prefix` 作为旧语义入口；默认状态机构造器和 `code-table-fixture` 仍用旧策略。
- 仅 `ime-engine` 的正式 `xiaohe-yinxing` 注册边界选择渐进策略。`xiaohe` 仍使用双拼 parser、句子解码、用户模型和原分页链路。
- 系统候选先按“所有精确分类 → 所有前缀分类”收集，候选保留完整编码、分类、`source_order`、稳定 ID 和匹配类型；同文字保留优先路径记录。
- 同一次按键捕获一份分类与用户词库不可变快照。用户 `#固/#删/#N` 在分页前按完整编码处理，规则后再次稳定去重，再按正式方案 512 上限截断和分页。
- 展示列表与精确唯一性分离；四码自动提交仍要求过滤和删除后的精确候选唯一且无有效后续码。
- FFI、C++、ArkTS 正式模型和 bundle schema 均无需修改。

## 3. 修改文件

- `engine-rust/crates/code-table-runtime/src/query.rs`：显式策略和精确＋严格前缀的分阶段查询。
- `engine-rust/crates/code-table-runtime/src/state.rs`：状态机策略、有限源读取和按策略选择用户规则合并。
- `engine-rust/crates/code-table-runtime/src/lib.rs`：导出新策略和查询入口。
- `engine-rust/crates/user-lexicon/src/snapshot.rs`：稳定的精确＋更长前缀规则视图。
- `engine-rust/crates/user-lexicon/src/merge.rs`、`src/lib.rs`：渐进候选用户规则合并。
- `engine-rust/crates/ime-engine/src/formal.rs`：仅正式方案注册渐进策略和 512 候选快照上限。
- `engine-rust/crates/code-table-runtime/tests/runtime.rs`：三策略、一至四码、去重、用户规则、分页和四码提交测试。
- `engine-rust/crates/ime-engine/tests/xiaohe_yinxing_production.rs`：正式数据数量/首页、过滤、退格、分页稳定和删除语义测试。
- `entry/src/internalDebug/ets/pages/DebugCodeTable.ets`：阶段 1 `ni` 96 项跨层分页探针及分类来源断言；不进入 Release。
- `PROJECT_STATE.md`、`CHANGELOG.md`、ADR 0020 和本报告：同步项目状态与证据。

## 4. 核心代码变化

- 查询结果继续使用 `QuerySnapshot`；每个 `CodeTableCandidate.match_type` 独立标记 `Exact` 或 `Prefix`，混合列表不丢失路径语义。
- 渐进分支只在输入长度 1～3 启用，且前缀记录必须满足 `complete_code.len() > raw_code.len()`。
- 四码分支只查询和合并完整码规则；唯一性与后续码仍由 `exact_candidates_for_snapshots` 和 `has_valid_continuation_for_snapshots` 独立计算。
- 渐进查询源上限为 `min(max_candidates + 当前用户规则数, 4096)`，供删除规则回填并禁止无界返回；旧通用回退策略不改变原有无界源读取语义。规则、去重完成后截断为 512，再由现有页大小切片。
- 分类开关和用户规则在一次操作内只使用已捕获快照，没有新增跨层读取。

## 5. 测试结果

| 命令/门禁 | 结果 |
| --- | --- |
| `cargo fmt --all -- --check` | PASS |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` | PASS |
| `cargo test --workspace --quiet` | PASS，395/395 |
| `cargo test -p ime-ffi`（workspace 内） | PASS，26/26 |
| Hvigor `entry@default test` | PASS，ArkTS 323/323；首次因无效 `DEVECO_SDK_HOME` 失败，按项目脚本设为 DevEco SDK 后通过 |
| `scripts/build-native.ps1 -Abi all` | PASS，x86_64 与 arm64-v8a |
| x86_64 Native | 25,691,990 bytes，SHA-256 `A64A20394D0C876FA3B16E7A3EAF02057E2C1DF52564CAEFCE2D4111E371E7C2` |
| arm64-v8a Native | 26,228,300 bytes，SHA-256 `871FBFBD8A58CC123A1C63D1A59C5F5328464F432368F10D29924E7BF9AC81F5` |
| `scripts/build-hap.ps1 -SkipRust -BuildMode debug` | PASS，40,834,840 bytes，SHA-256 `8D15C81D8CEC11843D8B311F5838682A6A9319956166B7554FB3B7A3D4579782` |
| `scripts/build-hap.ps1 -SkipRust -BuildMode release` | PASS |
| unsigned Release | 37,605,896 bytes，SHA-256 `6B9B622EBC7C983770FD50E5FB71D2417A782F41AD4F698492D782AEB653F926` |
| signed Release | 37,755,796 bytes，SHA-256 `5867032EA63C0CB8F77FC12AEFD6804F0AE447ECE30C561EEB8C4DADB7767DD0` |
| 当前 `verify-release-hap` signed/unsigned | PASS |
| `test-release-resource-gate.ps1` | PASS |
| `test-xiaohe-yinxing-stage11_6_8-release-gate.ps1` | PASS：fixture/raw source/trace/build report/等长篡改/network 六类负例均被拒绝 |
| 正式 bundle 两个独立目录重建 | PASS，15/15 文件路径、大小、SHA-256 一致 |

旧 `test-xiaohe-yinxing-stage11_6_3-release-gate.ps1` 预期正式 `.hsyx` 必须被 Release 拒绝；该规则已被 11.6.8 正式产品白名单取代，因此它会报告“formal-hsyx 负例意外通过”。本阶段不把该历史脚本计作当前门禁，也未修改它来伪造通过。

诊断性重试记录：

- 第一次 `cargo test --workspace` 在 180 秒工具上限处被终止，终止前无失败；使用 360 秒上限重跑后 395/395、退出码 0。
- 第一次 ArkTS 命令因 shell 中无效的 `DEVECO_SDK_HOME` 失败；按项目脚本设置为 DevEco Studio 自带 SDK 后 323/323、退出码 0。
- 正式双构建第一次使用 `C:\tmp` 时 converter staging 目录权限拒绝；改用仓库内两个唯一临时目录后 15/15 一致，比较完成后只删除这两个已校验临时目录。
- 模拟器第一次运行时页复验发现旧分类用例按“文字消失”断言，在渐进模式下同文字可由其他启用分类合法提供；改为断言候选来源分类后，最终 force-stop/restart 两轮均 10/10 PASS。
- 最终源码恢复旧通用回退策略的无界源读取语义后重新生成全部二进制；设备页完整回归耗时超过原脚本 8 秒固定等待，前两次采样时仍显示“执行中”，但后续布局中的 A～J 已全部 PASS。将采样等待调整为 30 秒后，用最终 HAP 从 force-stop/restart 连续两轮复跑，均取得总 PASS 与 A～J 10/10 PASS。

## 6. 正式候选验收

| 编码 | 阶段 0 | 阶段 1 | 阶段 1 首页 |
| --- | ---: | ---: | --- |
| `aa` | 1 | 41 | 阿、腌、嗄、吖、锕、啊、阿爸、阿伯、傲岸不群 |
| `ai` | 1 | 115 | 爱、埃、艾、碍、癌、哀、挨、矮、隘 |
| `an` | 3 | 165 | 按时、按到、安、按、案、岸、暗、鞍、氨 |
| `ni` | 1 | 94 | 你、尼、呢、拟、逆、倪、妮、腻、匿 |
| `hc` | 1 | 209 | 好、号、毫、豪、耗、浩、郝、皓、昊 |
| `ui` | 4 | 343 | 时间、试试、事、室、时、十、市、实、使 |
| `vi` | 6 | 353 | 知道、只能、只是、只会、只、支持、之、制、治 |
| `wo` | 1 | 68 | 我、窝、沃、卧、握、涡、斡、渥、幄 |
| `xm` | 3 | 264 | 现金、先、下面、现、县、线、限、显、险 |
| `xq` | 2 | 135 | 修正、修、秀、休、袖、绣、朽、锈、羞 |

完整列表没有重复文字；`ni` 页大小 3 与 9 的合并结果一致；重复查询一致。`nia` 数量小于 `ni`，且候选文字均属于 `ni` 的过滤集合。

## 7. 回归结果

- 四码唯一：`nibc` fixture 和正式 `aaba` 均只提交一次并清空组合。
- 多重四码：保留候选供选择，不自动提交。
- 第五键顶屏、正反向空码切分、删除影响唯一性：既有状态机和 FFI 回归通过。
- 用户规则：渐进列表内 `#固/#删/#N`、同位稳定顺序、删除后回填和分页前应用通过。
- 分类：禁用分类不再提供候选记录；同文字可以由其他启用分类合法保留；候选、后续码和唯一性共享快照。
- 分页：`ni` 94 项及设备端加两条规则后的 96 项无重复、无丢失；页大小变化不改变全局顺序。
- 小鹤双拼：`nihc → 你好`、`uurufa → 输入法`，切换前后状态清空且不应用渐进策略。

## 8. 设备验收

- 设备：HarmonyOS 6.1 Phone x86_64 模拟器，版本 `6.1.0.125(SP9DEVC00E120R4P11)`，分辨率 `1320x2856`。
- ABI：x86_64。
- 路径：internalDebug ArkTS → C++ → Rust 正式 bundle 运行时页。
- 结果：force-stop/restart 两轮，各 10/10 PASS；最终标记 `XIAOHE_YINXING_STAGE1_X86_64_RUNTIME_RESULT=PASS`。
- 证据：`device-runtime/device-acceptance.log`、`device-acceptance.json`、两轮布局 JSON 和截图。

## 9. 未完成项

- ARM64 物理真机与真机性能：`NOT_RUN`。
- Pad 本阶段专项复验：`NOT_RUN`。
- 中文输入框、多行文本框、搜索框和独立第三方 TextInput：`NOT_RUN`；当前模拟器未安装 `com.example.nexttest`。
- 快速连续真实触键、候选栏左右翻页手势和隐藏/重新显示键盘的阶段 1 专项人工验收：`NOT_RUN`。
- 阶段 1 专项 Release 性能基线：`NOT_RUN`；现有历史 benchmark 仍测通用回退查询，不能伪装为渐进查询性能。

## 10. 风险和后续建议

- 512 上限覆盖当前规定正式二码（最大 `vi=353`），但一码或未来扩展数据可能被截断；后续展开面板应设计游标/分段读取，而不是扩大 ArkUI 单次节点数。
- 渐进查询扩大二码候选源，主机功能测试和模拟器运行时通过，但仍应在 ARM64 真机记录逐键 P50/P95、峰值内存和快速触键稳定性。
- 历史 11.6.3 Release 负向脚本与当前产品白名单冲突，后续应标记 deprecated 或按阶段参数化，避免统一门禁误调用。
