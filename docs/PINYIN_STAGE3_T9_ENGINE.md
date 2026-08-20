# 26 键全拼和 9 键计划阶段 3：9 键拼音引擎与消歧

更新时间：2026-08-12

状态：`IMPLEMENTED / HOST_VALIDATION_PARTIAL`

本阶段已实现 Rust 9 键拼音引擎、数字音节索引、候选复用链和跨语言组合选择接口，并通过专项自动化、ArkTS、双 ABI Native、Release HAP 与内容门禁。由于仓库当前冻结的 `artifacts/candidate-baseline/sentence-baseline.json` 与现有 `production.lex` 在既有小鹤候选排序上不一致，全 Rust workspace 总门禁仍有 1 项失败，因此本阶段不得标记为 `COMPLETED`。9 键 UI 属于阶段 4，本阶段没有启用 `pinyin-9` 键盘档案。

## 1. 范围与边界

已交付：

- 标准 T9 映射：`2 ABC`、`3 DEF`、`4 GHI`、`5 JKL`、`6 MNO`、`7 PQRS`、`8 TUV`、`9 WXYZ`。
- 合法拼音音节到数字签名的初始化索引和数字 Trie。
- 直接在数字 Trie 上运行的有界动态规划；运行时不枚举 `3^n`/`4^n` 字母串，也不扫描完整音节表。
- 数字串到标准拼音的多路径解析、未完成音节、显式分音、逐位删除、重置和方案切换。
- 复用现有正式词库查询、整句解码、候选去重/排序、分页、部分提交、提交和用户学习。
- `pinyin-9` 独立学习命名空间；学习键使用最终候选稳定 ID 与标准拼音，不存储临时字母展开路径。
- ArkTS → C++ → Rust 的拼音组合选择接口。

明确不在本阶段：

- 九宫格软键盘、按键文案、候选栏交互、设置页启用和视觉适配。
- UI 层 T9 字母展开、音节切分、路径选择、候选排序或评分。
- 更改现有小鹤双拼、全拼、音形方案语义。

`KeyboardProfile` 中的 `pinyin-9` 继续保持 `enabled=false`；Rust/FFI 已可创建和切换 `schemeId=pinyin-9`，供阶段 4 接入。

## 2. 数据流与职责

```text
ArkTS EngineCoordinator.selectPinyinCombination(index)
  -> NativeEngineGateway
  -> C++ Node-API / EngineRegistry / RustEngineHandle（只校验和转发）
  -> Rust C ABI ime_engine_select_pinyin_combination
  -> ImeEngine::select_pinyin_combination
  -> T9PinyinParser（唯一切分和选择状态）
  -> CandidateQuery / SentenceDecoder / CandidateSession / UserModel
  -> CompositionResult
  -> C++ 结构转换
  -> ArkTS 状态保存
```

普通数字输入使用同一条 `processKey` 链。`rawInput` 始终是 `2`～`9` 数字；显式分音边界作为 Rust 解析器状态保存，不把伪字符混入 raw input。`currentPinyin` 是当前稳定路径，`pinyinCombinations` 是除当前路径外的有界可选标准拼音路径。

组合索引的统一语义为：索引 `0` 选择 `currentPinyin`，索引 `1..N` 依次选择 `pinyinCombinations[0..N-1]`。越界选择失败且不修改组合。

## 3. 索引与有界动态规划

`T9SyllableIndex` 从 `pinyin-syllable` 的合法音节集合构建。每个音节只转换一次数字签名并插入数字 Trie；进程内正式解析器通过 `OnceLock<Arc<_>>` 共享索引。Trie 终点保存完整音节，节点保存有界合法前缀，因此运行时只沿当前数字边推进。

动态规划状态由输入偏移、已完成标准音节和数字分段组成。每个起点只沿 Trie 向前最多 6 位；生成状态立即按稳定顺序排序、去重和截断。未完成尾段只从对应 Trie 节点读取合法前缀。显式边界把输入拆成独立区间，禁止跨边界合并。

稳定顺序不依赖哈希迭代顺序；相同数字串反复解析、删除后恢复、重置后重输均得到同样的路径序列。候选聚合先按各条有界标准拼音路径查询，再由 Rust 统一评分、稳定排序和按可见文字去重。用户显式选择路径后，候选会话立即清空并只按所选路径重查。

## 4. 集中上限

解析器上限集中定义在 `shuangpin-parser/src/t9.rs`：

| 上限 | 值 | 作用 |
| --- | ---: | --- |
| `T9_MAX_RAW_DIGITS` | 64 | 最大 raw 数字长度；超限保持原状态 |
| `T9_MAX_SYLLABLE_DIGITS` | 6 | 单音节 Trie 最大推进深度 |
| `T9_MAX_PATHS_PER_OFFSET` | 32 | 每个 DP 偏移保留的稳定路径数 |
| `T9_MAX_GENERATED_STATES_PER_OFFSET` | 512 | 每个起点最多生成状态数 |
| `T9_MAX_PINYIN_COMBINATIONS` | 32 | 当前与可选拼音路径总展示上限 |
| `T9_PREFIX_CACHE_CAPACITY` | 65 | 输入前缀状态容量 |

引擎层 `T9_MAX_CANDIDATE_SNAPSHOT=256`；分页大小仍由现有 `CandidateSession` 配置决定。词库查询、句子 beam、用户模型和缓存继续使用各自既有集中限制。

最坏情况下，搜索规模受输入长度、Trie 深度、每偏移路径数和每起点生成数乘积约束；它不随每个数字对应的字母数做指数增长。

## 5. 候选与学习复用

- 完整单音节走现有 exact 查询；未完成音节走 prefix 查询。
- 多音节路径走现有 `SentenceDecoder`，并保留可部分提交候选。
- `64426` 的 `ni'hao` 候选按其数字签名计算 `consumedRawLen=5`。
- 初始歧义状态聚合最多 32 条拼音路径；显式选择后只保留所选路径的候选。
- 候选选择、下一页、上一页、退格和 reset 继续使用现有会话规则。
- 自动用户模型的键含 `scheme_id=pinyin-9`；测试确认相同稳定候选在 `pinyin-9` 与 `quanpin` 产生不同学习键，且在 9 键候选中选择非首项后会复用既有学习评分提升该候选。
- 人工用户词库查询使用 `p9` 加规范化标准拼音作为 raw-code 命名空间，与双拼和 `qp` 全拼规则隔离。

## 6. 协议与 ABI

当前版本：

- ArkTS interface version：`7`
- Rust ABI version：`7`
- engine version：`0.0.1-pinyin-stage3`

新增 C ABI：

```c
int32_t ime_engine_select_pinyin_combination(
    ImeEngineHandle handle,
    size_t combination_index,
    ImeBuffer* out_buffer);
```

对应 Node-API/ArkTS：

```typescript
selectPinyinCombination(handle: number, combinationIndex: number): CompositionResult
```

没有新增 T9 专用结果结构；继续使用 `CompositionResult.currentPinyin`、`pinyinCombinations`、`displaySegments`、`candidates` 和分页字段。候选结构声明补齐既有 `consumedRawLen`，保证部分提交跨层类型一致。

## 7. 关键验收

专项自动测试覆盖：

- `64` 的拼音组合包含 `ni`，候选包含“你”；选择 `ni` 后不再混入 `mi` 的候选，反向选择同样成立。
- `64426` 包含 `ni'hao`，候选包含“你好”，整句候选消费 5 位数字。
- 同串多路径顺序稳定且可选择；选择后拼音与候选同步刷新。
- 显式分音、删除数字、删除边界、reset、分页和方案往返恢复。
- 单位未完成输入可返回合法 prefix 候选。
- 非 `2`～`9` 键拒绝且状态不变；第 65 位输入拒绝且保留 64 位组合。
- 连续 64 个高碰撞数字 `6` 的路径数、生成状态和缓存容量均不超过硬上限，无 panic 或无界内存增长。
- C ABI 真实跨层创建 `pinyin-9`、输入 `64426`、获取“你好”、输入 `64` 并选择组合。
- ArkTS coordinator 对组合选择只转发索引并保存成功结果。

## 8. Release 性能基线

命令：

```powershell
cargo run --release -p ime-engine --example t9_stage3_benchmark
```

环境：Windows 主机、Rust Release、2026-08-12。本次常规项目 5,000 次采样；64 位高碰撞输入 200 次采样。

| 场景 | 平均 | P50 | P95 |
| --- | ---: | ---: | ---: |
| `64` 解析 | 6.173 µs | 5.800 µs | 7.300 µs |
| `64426` 碰撞解析 | 52.789 µs | 47.800 µs | 81.700 µs |
| 64 个连续 `6`，逐键完整输入 | 412.241 ms | 411.041 ms | 444.066 ms |
| `64426` 输入后连续删除 | 82.445 µs | 69.800 µs | 133.900 µs |
| `64` 组合切换 | 8.685 µs | 7.900 µs | 13.500 µs |
| `64426` 完整候选刷新 | 319.610 µs | 282.200 µs | 534.600 µs |

64 位结果包含 64 次逐键重算，P50/P95 摊销约 6.42/6.94 ms 每键；它用于最坏碰撞稳定性门禁，不代表常用短输入延迟。索引 250 个节点，独立构建平均 241.342 µs；正式进程共享一次构建结果。

## 9. 验证结果

通过：

- T9 parser、engine 专项、学习命名空间、FFI 单元/集成测试。
- Rust `fmt` 与 workspace `clippy`。
- ArkTS 全量单元测试与 CMake/NAPI 编译。
- `x86_64`、`arm64-v8a` OHOS Rust 静态库。
- unsigned Release HAP 构建、Release 资源负门禁和 HAP 内容门禁。

当前独立失败：

- `candidate-baseline::tests::committed_candidate_snapshots_match_current_production_behavior`。
- 差异在既有 `xiaohe` 的 `nihc`、`uurufa` 冻结候选；当前生产词库返回“你浩/你耗/你豪…”和“输入罚/输入阀/输入發…”，冻结快照期待“你嚎/你嗥…”和“输入垡/输入珐/输入沷…”。本阶段未修改冻结快照，T9 专项和非基线回归不依赖该差异。
- 当前工作目录没有可用 Git 元数据，无法从提交历史进一步归因，因此只能记录为独立基线漂移阻塞，不能宣称全量门禁通过。

`NOT_RUN`：

- HarmonyOS Phone/Tablet/2in1 模拟器上的 9 键专项。
- ARM64 真机、真实 USB/蓝牙键盘、第三方应用、旋转/分屏和小时级压力。
- 阶段 4 九宫格 UI 与交互（尚未实现，非本阶段范围）。

## 10. 产物

- `x86_64` `libime_ffi.a`：26,839,064 bytes，SHA-256 `AD87B4A1B9DD4E2841D5BFD8927AD02FFC3F0580247156D8F17BC59A6674D561`
- `arm64-v8a` `libime_ffi.a`：27,338,314 bytes，SHA-256 `4478CAB42751796E1C81EFD247E8C8450B298EA3F809740165ECB82A98D08302`
- unsigned Release HAP：38,719,780 bytes，SHA-256 `BE630BCBAB7234B936933E93ACF12C1C754B1D30AEAE71F920C86E3785C70CCA`

## 11. 完成判定

本阶段代码与主机/构建范围已经实现，但总体状态保持 `IMPLEMENTED / HOST_VALIDATION_PARTIAL`。只有冻结候选基线经产品/数据负责人确认并恢复全 Rust workspace 绿色，同时阶段要求的设备项按计划完成或明确豁免后，才允许改为 `COMPLETED`。
