# 候选词改进阶段 1 验证报告

状态：`COMPLETED`（主机、构建及 x86_64 Phone/Pad 模拟器基本运行时范围）。

## 结论

- ArkTS 正式默认请求 50；Node-API 缺省值、Rust `EngineConfig` 缺省值和 `QueryConfig` 缺省值统一为 50。
- Rust 最大允许页大小为 64。请求 3、5、8、9、50 均原样接受；0 被拒绝；超过 64 的值安全钳制为 64。
- 小鹤音形和小鹤双拼在正式引擎创建时使用同一个 `QueryConfig::normalize_page_size` 结果。音形状态机、双拼查询结果和 `CandidateSession` 不再各自决定正式页大小。
- FFI 自动测试确认 `candidatePageSize=50` 时，小鹤音形 `h` 当前页 JSON 实际包含 50 个候选；显式请求 9 时仍为 9 个。
- 阶段 0 快照没有改写。`candidate-baseline` 测试继续逐字节验证原音形 512 项和双拼 64 项快照。
- 未修改双拼前缀召回、64 项召回池、词频排序、音形排序、用户规则、正式词库、候选展开 UI 或收起键盘行为。

## 调用链

```text
EngineCoordinator DEFAULT_CANDIDATE_PAGE_SIZE=50
→ NativeEngineGateway
→ engine_napi.cpp（缺省 50，显式值透传）
→ ime-ffi parse_engine_config（缺省 EngineConfig=50，0 拒绝）
→ ImeEngine::new
→ QueryConfig::normalize_page_size（1..64）
├─ xiaohe-yinxing CodeTableStateMachine
└─ xiaohe CandidateQueryEngine → CandidateSession
```

默认页大小与最大允许页大小分别为 50 和 64；双拼排序后快照/召回池仍为 64，音形正式快照仍为 512。

## 阶段 0 对比

- 音形 `h`：完整列表仍为 512 项；页大小 9 与 50 拼接后的列表完全相同。前 9 项仍为“和、忽略、化、会、行、合、后、好、海”，第二页从全局第 51 项开始。
- 双拼 `h`：完整列表仍为 64 项；页大小 9 与 50 拼接后的列表完全相同。前 9 项仍为“还、哈哈、哈、哈哈哈、海、哈哈哈哈、害、哈尔滨、海边”；50 项首页之后的末页为 14 项。
- 阶段 0 文件 SHA-256：
  - `flypy-shape-h.json`：`d4a4ec852647c9bfcf2482959b0fee13dafcf7d6aa064c44d3a2cc6d1db3c708`
  - `flypy-double-pinyin-h.json`：`6e9a3b51003243e60cb5dbaf409765a3c621eb51ab0de482956ffa1f39f5aaaa`
  - `determinism.json`：`a333f4e933db8d621166d945350eb61ce82cf02d16b4ad7d47076f5740edd52d`

## 性能

同一台 Windows x64 主机、Release、预热 10 次、采样 100 次：

| 指标 | 阶段 0（页 9）P50/P95 | 阶段 1（页 50）P50/P95 |
| --- | ---: | ---: |
| 双拼 `h` 冷查询 | 92.9/142.2 µs | 97.0/155.9 µs |
| 双拼 `h` 热查询 | 9.3/26.5 µs | 9.9/19.5 µs |
| 音形 `h` 冷状态查询 | 1376.6/2003.0 µs | 1442.7/2181.4 µs |
| 音形 `h` 热状态查询 | 1154.1/1843.4 µs | 1192.3/2108.9 µs |

当前页 JSON：双拼 `1176→5145` bytes，音形 `1186→5033` bytes。候选快照工作集增量观测为 `8,310,784→15,822,848` bytes，进程峰值为 `149,012,480→149,217,280` bytes。查询耗时基本持平，跨语言当前页数据按候选数有界增长。

ArkTS Candidate Store 独立更新时间、Phone/Pad UI 可见延迟与内存、ARM64 物理真机性能未单独插桩，状态为 `NOT_RUN`。

## 测试与构建

- `cargo fmt --all --check`：PASS。
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`：PASS。
- `cargo test --workspace --all-targets`：403/403 PASS（含 FFI 28/28）。
- ArkTS 单元测试：324/324 PASS。
- x86_64 与 arm64-v8a Native：PASS。
- internalDebug HAP：40,834,888 bytes，SHA-256 `5ff2447778d869036ff12a3c9948405258bac5b5fedb09cf2278a20be6c72f2c`。
- unsigned Release HAP：37,605,928 bytes，SHA-256 `11ca2cf545d4a9b91a8a5f753bdd19f6be84acc8ca53068220218b80388cf4d2`。
- Phone 模拟器：x86_64、1320×2856，internalDebug 运行时页整体 PASS；长矩阵首轮 14/14 PASS，第二轮因本地主机 240 秒命令上限中止，因此不声明双轮完成。
- Pad 模拟器：x86_64、2880×1920，internalDebug 运行时页整体 PASS。

设备基本布局证据位于 `phone/basic-*.json` 与 `pad/basic-*.json`。ARM64 物理真机、signed Release 独立第三方输入框、旋转/分屏、快速触键及设备性能为 `NOT_RUN`。

## 修改文件

- `engine-rust/crates/candidate-query/src/model.rs`
- `engine-rust/crates/candidate-query/src/query_engine.rs`
- `engine-rust/crates/ime-engine/src/formal.rs`
- `engine-rust/crates/ime-engine/tests/xiaohe_yinxing_production.rs`
- `engine-rust/crates/ime-ffi/src/lib.rs`
- `engine-rust/tools/candidate-baseline/src/lib.rs`
- `engine-rust/tools/candidate-baseline/src/main.rs`
- `entry/src/main/cpp/napi/engine_napi.cpp`
- `entry/src/test/Stage2Controller.test.ets`
- `CHANGELOG.md`
- `PROJECT_STATE.md`
- 本证据目录。

