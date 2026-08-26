# 9 键拼音运行时性能第二轮优化

日期：2026-08-24  
状态：`IMPLEMENTED / HOST_RELEASE_VALIDATED / DEVICE_NOT_RUN`  
范围：`schemeId=pinyin-9` 的 Rust 解码热路径；未修改候选质量策略、C ABI、Node-API 或 ArkTS 协议

## 结论

本轮消除了方案切换带来的搜索上限不确定性，并降低联合搜索与最多 32 路兼容解码的复制、排序和重复计算成本。正式 `production.lex` 的冻结 dev、public-regression 完整候选指纹均与优化前一致。

同一 Windows x86_64 主机、Release `ImeEngine`、dev 155 条、每组 3 轮的即时 A/B：

| 每键延迟 | 优化前 | 优化后 | 降幅 |
|---|---:|---:|---:|
| P50 | 17.859 ms | 5.258 ms | 70.6% |
| P95 | 92.176 ms | 16.078 ms | 82.6% |
| P99 | 132.113 ms | 23.717 ms | 82.0% |
| Mean | 27.943 ms | 6.004 ms | 78.5% |

public-regression 900 条 × 3 轮的优化后主机结果为 P50/P95/P99 `5.041/16.164/22.744 ms`。该组没有在本轮代码修改前重新采集即时 A/B，因此只将其用于候选冻结与优化后绝对延迟验证，不把它表述成严格同批对照。

## 实现

1. `DecodeLimits` 由统一的方案函数生成；引擎创建和每次 `change_scheme` 都更新同一个 `SentenceDecoder`。从任何方案切入 9 键都会使用固定的 `128 edges / beam 4 / Top-4` 兼容解码上限，切回全拼或小鹤也恢复各自限制。
2. T9 联合 beam 状态只保存父节点、边索引、累计分数和计数。扩展状态只新增一个小节点，最终输出候选时才回溯并生成完整 `SentencePath`，不再为每条假设复制完整边数组。
3. 联合 beam 的排序字段每个状态只生成一次，比较器不再反复调用 `as_path()`；通用句子 beam 比较也直接借用现有边切片，文本与读音按字节流比较，不再临时拼接完整字符串。
4. 兼容句子解码使用容量 128 的 LRU，键为公开拼音组合及当前是否未完成。缓存只覆盖至少两段的句子解码；单音节查询继续使用既有查询缓存。
5. 缓存包含用户分数参与后的候选顺序，因此在候选提交、用户模型路径/加载/清空、学习开关、会话隐私开关、重置和方案切换时全部失效。

## 候选一致性

| 数据集 | 规模 | 轮数 | 完整候选 SHA-256 | 质量结果 |
|---|---:|---:|---|---|
| dev | 155 | 3 | `6b68e9b8bcb89a64ca81f4f5bb5f2c5aa0284f24650f12ed367061106cd8fae7` | Top1/Top3/Top5 `16.129%/16.129%/16.129%`，与优化前一致 |
| public-regression | 900 | 3 | `10de0fcd5c092f31f7e3c89605699954bf983c78102e16a4d64244d52ed0bda6` | Top1/Top3/Top5 `34.889%/43.889%/46.333%`，与冻结结果一致 |

两组每轮 SHA 均相同；自动上屏、ASCII 泄漏、状态丢失和引擎错误均未增加。联合解码的 `peakEstimatedBytes` 统计现在显式计入父节点 arena 和共享边存储，旧实现没有计入 `JointState.edges` 背后的堆内存，因此该诊断数值不能直接做新旧内存 A/B；真实设备 RSS 仍需单独采集。

## 验证

- `cargo fmt --all -- --check`：PASS
- `cargo clippy -p sentence-decoder -p ime-engine --all-targets -- -D warnings`：PASS
- `cargo test --workspace --all-targets --no-fail-fast`：PASS
- `sentence-decoder`：33/33 PASS
- `ime-engine`：57/57 PASS
- T9 引擎集成：11/11 PASS
- 增量追加、退格、显式边界与全量重算候选等价：PASS
- 方案切换搜索限制确定性与非法限制原子拒绝：PASS
- 兼容缓存容量及用户模型变更失效：PASS

## 剩余边界

本轮没有改变 32 条公开拼音路径、联合 beam 宽度或候选质量策略，也没有重跑 blind。上述延迟是 Windows x86_64 主机 Release 结果；ARM64 真机、真实聊天/浏览器宿主、设备 P95/P99、RSS、低内存和长时输入仍为 `NOT_RUN`。
