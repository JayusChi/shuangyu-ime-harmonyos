# `pinyin-9` 数字—拼音—词句联合解码

> 2026-08-19 后续优化已经完成正式 public-regression/dev 三轮评测，质量与延迟数据及实现变更见 [9 键候选召回、排序与延迟优化](PINYIN9_OPTIMIZATION_20260819.md)。下文保留 2026-08-18 阶段冻结记录，其中“未生成”只描述当时状态。

实现冻结日期：2026-08-18  
scheme：`pinyin-9`  
实现 manifest SHA-256：`c21ddafb622443b992bbf416722d5fd4bf4a8a68db3069882d49be201a8934e3`  
正式评测状态：**按用户指示停止；未形成第二阶段正式三轮结果**

## 结论与结果边界

本阶段已经完成 `pinyin-9` 专用联合搜索、增量状态、诊断、测试和评测入口。搜索不再要求所有候选都先经过公开 32 条拼音路径：内部解析池最多保留 128 个拼音假设，词典数字索引在数字位置上直接建立词边，已有词频、词长、整词覆盖和上下文分数参与 beam 排序后，才决定联合候选及少量可公开提升的拼音路径。

代码与测试没有发现需要继续阻塞交付的问题。正式 public-regression/dev 三轮评测因运行时间很长，按用户明确指示终止。第三次正式尝试只在进程内完成了 public-regression 第一轮；评测器规定三轮全部完成后才写结果，因此没有发布可误认成正式数据的单轮或半成品文件。第二阶段 Top1/Top3/Top5、MRR、召回、归因、延迟、内存及确定性数字在本文中一律标为“未生成”，不能以开发试跑替代。

第一阶段 `artifacts/pinyin9-evaluation/`、数据、manifest、结果、失败文件和 blind 回执保持冻结；本阶段没有复跑 blind，也不把原 blind 宣称为新 blind。完整停止状态见 `artifacts/pinyin9-joint-decoder-evaluation/evaluation-status.json`。

## 改造前后数据流

改造前：

```text
数字串
  -> T9 拼音解析器独立枚举和排序
  -> 固定裁剪到公开 32 路
  -> 每条拼音路径分别查词和整句解码
  -> 合并、排序候选
```

这个结构使排在第 33 条及以后的正确拼音在接触词典、词频和上下文之前永久丢失。

改造后：

```text
数字串与显式边界
  +-> 兼容公开解析 lattice（最多 32 路，保持协议与既有顺序）
  |
  +-> 内部解析 lattice（最多 128 个完整拼音假设）
  |
  +-> production.lex 数字签名索引
        -> 数字位置上的词边
        -> 显式边界硬约束过滤
        -> 词典可达的句子 beam
        -> 词频/词长/整词覆盖/上下文/碎片化联合评分
        -> 稳定剪枝与候选排序
        -> 联合候选 + 置信度受控的公开路径提升
        -> 与既有兼容候选合并（总快照最多 256）
```

联合索引只引用正式 `production.lex` 的词条下标；没有增加补丁词典、样本派生词条、用户学习数据或评测层候选重排。全拼、双拼、音形不进入这条 `pinyin-9` 分支。

## 实现结构

### T9 解析器

`shuangpin-parser/src/t9.rs` 使用音节数字 trie 和按数字前缀持有的动态规划 lattice：

- 兼容 lattice 每个 offset 保留 32 路，以维持第一阶段公开路径的顺序语义；
- 内部 lattice 每个 offset 最多 64 个状态，并公开最多 128 个内部完整假设给联合诊断；
- append 只计算新的末尾行，backspace 弹出一行，reset 清空全部缓存；
- 显式选择仍是稳定的硬选择；
- 联合解码仅可在置信度门控内提升已经验证为完整词典路径的公开顺序；
- 对外 `pinyinCombinations` 仍严格不超过 32 条。

解析器分别统计非法音节/无法扩展、生成状态、内部假设和容量裁剪，不再把所有缺失都归为同一种“路径不存在”。

### 词典索引与词图

`sentence-decoder/src/t9_joint.rs` 在正式词库加载时构建确定性的 `数字签名 -> 词条下标` 索引。解码时从每个数字起点查找可结束的正式词条，形成按数字位置连接的 `WordEdge`。词边保留文本、拼音、位置、音节数、词频和来源，随后复用已有 `SentenceScorer` 与 `CharacterBigramModel`。

显式分音位置必须与词条内部音节边界相容；跨越而不匹配的词边直接拒绝，因此分音是硬约束，不是一个可被高分覆盖的软惩罚。

### 联合 beam 状态与稳定排序

实际 beam 状态以一串 `WordEdge` 和累计分数保存，并可确定性还原：

- 当前数字位置由末尾词边 `end` 表达；
- 音节边界和拼音路径由各词边 reading 及位置表达；
- 词典可达状态由能够连接到当前位置的正式词边表达；
- 已生成文本由词边文本串联；
- 词数用于最大句长和碎片化惩罚；
- 显式边界在建边时已作为硬约束；
- 稳定决胜使用分数、路径、文本、reading、词条标识等全序比较，并使用 `BTreeMap`/`BTreeSet` 汇总。

简拼、未完成尾音和错误输入恢复仍由现有兼容解析/解码回退承担，尚未成为联合 beam 的一等状态。这是本阶段已知缺口，不能宣称已经完成这些输入类型的联合纠错。

### 评分

联合路径复用现有句子评分：

- 正式词条频次经过封顶的数量级和桶映射计分；
- 多音节词获得与音节数平方相关的整词奖励；
- 字符 bigram 上下文分数加入相邻词边转移；
- 完整覆盖获得终止奖励；
- 多词切分按额外词数惩罚，抑制碎片化；
- fallback 边和 pending tail 在现有句子解码器中分别受罚。

此外，兼容候选保留固定兼容排序加成，联合候选作为额外召回层合并，避免高歧义数字串破坏已冻结的基础行为。没有针对样本 ID、expectedTexts、具体词或具体数字串的特殊加分。

## 集中的硬上限

| 上限 | 值 | 作用 |
| --- | ---: | --- |
| 原始数字长度 | 64 | 第 65 位返回可检测的 `InvalidArgument`，保留已有 64 位状态 |
| 单音节数字长度 | 6 | 限制解析 trie 回看范围 |
| 公开拼音组合 | 32 | 协议上限 |
| 解析器每 offset 路径 | 64 | 内部 lattice 容量 |
| 每 offset 生成状态 | 1,024 | 防止解析组合爆炸 |
| 内部完整拼音假设 | 128 | 联合诊断/召回池 |
| 数字前缀缓存 | 65 行 | 空前缀加 64 个数字 |
| 联合 beam 宽度 | 16 | 全局句子状态容量 |
| 每数字位置状态 | 16 | 局部句子状态容量 |
| 每 reading 搜索词条 | 16 | 常规词边扩展限制 |
| 每 reading 直接词条 | 64 | 完整读音同音候选池 |
| 直接完整路径 | 256 | 完整词条候选池 |
| 每数字位置词边 | 64 | 局部图扩展限制 |
| 总图边 | 1,024 | 单次联合图上限 |
| 最大句子词数 | 32 | 防止极端碎片路径 |
| 输出候选 | 256 | 候选快照上限 |
| 诊断路径 | 512 | 失败归因路径集合上限 |
| 联合公开路径提升 | 4 | 仅低歧义结果允许提升 |
| 兼容解码路径 | 32 | 既有候选回退上限 |
| 兼容解码数字长度 | 32 | 长串不再做 32 路全展开 |
| 分数剪枝差 | 12,000 | 相对当前最佳状态的下限 |

达到分数阈值、beam 容量、图边、直接候选或最终输出上限时分别计数。`T9JointStats` 还记录探索拼音假设数、最大 beam、词典不可达、图边数和估算峰值内存。

## 增量计算与状态安全

`T9JointSession` 持有当前数字、显式边界、每个前缀的 beam、直接路径和最近被裁剪路径。纯追加数字时只扩展以新末尾为终点的词边；退格、边界插入/删除或非前缀变化会安全重建；reset 和 scheme 切换完整清空解析与联合状态。

64 位是明确输入上限。第 65 位不会静默截断后继续成功，不会自动提交，不会输出 ASCII，也不会清空已有 composition/candidates；调用返回 `InvalidArgument`，评测器将其记为 input-limit 命中而不是引擎内部错误。微型和集成测试覆盖连续输入、退格、边界删除、reset、scheme 切换、长重码、分页和重复运行。

## 诊断与失败归因

`candidate-baseline` 的第二阶段 schema 为 `pinyin9-joint-decoder-results/2`。每条样本可记录：

- 内部探索的拼音假设数、最大 beam、图边和估算峰值内存；
- 词典前缀不可达、拼音非法、联合分数、beam 容量及候选上限剪枝数；
- canonical 是否进入内部搜索、是否进入公开 32 路和淘汰阶段；
- 目标是否召回、首次名次、每键和每样本时延；
- composition、候选、自动提交、ASCII、状态丢失、输入上限和引擎错误安全计数。

主归因明确区分 `parser_not_generated`、`lexicon_prefix_unreachable`、`joint_beam_pruned`、`public_path_limit_only`、`path_present_target_unrecalled`、`candidate_recalled_ranking_error`、`state_loss` 和 `engine_error`。

## 第一阶段与第二阶段指标

下表中的第一阶段值来自冻结正式结果。第二阶段三轮正式结果因用户终止评测而没有生成，不能据此宣布准确率、性能或路径裁剪已经改善。

| 指标 | 第一阶段 public（900） | 第二阶段 public | 第一阶段 dev（155） | 第二阶段 dev |
| --- | ---: | ---: | ---: | ---: |
| Top1 | 14.889% | 未生成 | 9.032% | 未生成 |
| Top3 | 17.444% | 未生成 | 9.677% | 未生成 |
| Top5 | 18.444% | 未生成 | 10.323% | 未生成 |
| MRR | 0.173717 | 未生成 | 0.096936 | 未生成 |
| 目标完全未召回 | 41.333% | 未生成 | 81.290% | 未生成 |
| canonical 进入内部搜索 | 不适用 | 未生成 | 不适用 | 未生成 |
| canonical 被联合 beam 裁剪 | 不适用 | 未生成 | 不适用 | 未生成 |
| canonical 进入公开 32 路 | 67.444% | 未生成 | 31.613% | 未生成 |
| canonical 被 32 路裁剪 | 32.556% | 未生成 | 54.194% | 未生成 |
| 路径存在但目标未召回 | 8.778% | 未生成 | 12.903% | 未生成 |
| 已召回但 Top1 排序错误 | 43.778% | 未生成 | 9.677% | 未生成 |

用户最初引用的 blind 第一阶段值仍仅作冻结背景：Top1/3/5 为 `8.602%/12.688%/13.548%`，MRR `0.109757`，未召回 `78.710%`，32 路裁剪 `60.000%`，路径存在但目标未召回 `9.247%`，排序错误 `12.688%`。本阶段没有进行 blind 复测，所以“60% 变为多少”没有第二阶段正式答案。

### 分类、性能、内存和安全

| 项目 | 第一阶段 | 第二阶段正式值 |
| --- | --- | --- |
| blind 长句 Top1/3/5 | 0% / 0% / 0% | 未复测 |
| blind 现代聊天 Top1/3/5 | 0% / 4.167% / 4.167% | 未复测 |
| blind 高重码 Top1/3/5 | 20.833% / 37.500% / 37.500% | 未复测 |
| blind 四种一次编辑错误 Top1/3/5 | 0% / 0% / 0% | 未复测 |
| public 每键 P50/P95/P99 | 35.805 / 541.164 / 738.442 ms | 未生成 |
| dev 每键 P50/P95/P99 | 32.949 / 629.015 / 828.166 ms | 未生成 |
| blind 每键 P50/P95/P99 | 36.224 / 634.066 / 820.455 ms | 未复测 |
| 联合探索数/图边/估算内存 | 第一阶段无此诊断 | 未生成正式汇总 |
| public 自动提交/ASCII/状态丢失/引擎错误 | 0 / 0 / 0 / 0 | 未生成 |
| dev 三轮状态丢失 | 3（同一 65 位样本每轮一次） | 未生成 |
| blind 三轮状态丢失 | 45（15 个超长样本） | 未复测 |

测试已经验证第 65 位为显式输入上限错误且原状态保留，但这不等于正式数据集安全计数。正式确定性 SHA-256、P95/P99 和内存比较也必须保持“未生成”。

## 实际完成的验证

停止正式评测之前完成：

- `cargo fmt --all --check`：通过；
- `cargo clippy -p shuangpin-parser -p sentence-decoder -p ime-engine -p candidate-baseline --all-targets -- -D warnings`：通过；最终评测器内存整理后又单独执行 candidate-baseline Clippy，通过；
- shuangpin-parser：23 个 crate 单元测试加 11 个 stage4 测试，共 34 个通过；
- sentence-decoder：28 个测试通过，其中 5 个联合 T9 定向测试；
- ime-engine：单元、全拼、双拼、音形、production corpus、stage7/8/9、T9 和用户词库回归共 153 个通过；
- `ime-engine/tests/t9_stage3.rs`：9 个通过；
- candidate-baseline：20 个通过，最终评测器内存整理后再次全量通过；
- 微型测试覆盖内部池超过 32、词典评分提升原公开 32 之外路径、显式边界、增量与 fresh search 一致、beam 确定性和独立归因、64/65 位状态、三轮等价重复、分页无丢失/重复/乱序；
- 用户学习保持关闭，正式词库 SHA-256 仍为 `5096f142117bb399f63a918a3c10802ec35aa1f356305b62586a1c1f9e33a201`。

未完成的是 public-regression 三轮、dev 三轮以及由其生成的正式 SHA-256、指标和性能比较，不是单元或回归测试失败。

## 文件

本阶段新增或行为性修改的主要文件：

- `engine-rust/crates/shuangpin-parser/src/t9.rs`
- `engine-rust/crates/shuangpin-parser/src/lib.rs`
- `engine-rust/crates/shuangpin-parser/src/phonetic.rs`
- `engine-rust/crates/sentence-decoder/src/t9_joint.rs`
- `engine-rust/crates/sentence-decoder/src/decoder.rs`
- `engine-rust/crates/sentence-decoder/src/lib.rs`
- `engine-rust/crates/ime-engine/src/t9_joint.rs`
- `engine-rust/crates/ime-engine/src/formal.rs`
- `engine-rust/crates/ime-engine/src/lib.rs`
- `engine-rust/crates/ime-engine/tests/t9_stage3.rs`
- `engine-rust/tools/candidate-baseline/src/pinyin9_evaluation.rs`
- `scripts/evaluate-pinyin9-joint-decoder.ps1`
- `docs/features/pinyin/PINYIN9_JOINT_DECODER.md`
- `artifacts/pinyin9-joint-decoder-evaluation/implementation-manifest.json`
- `artifacts/pinyin9-joint-decoder-evaluation/evaluation-status.json`

两个早期异常退出的尝试只保留不可覆盖的实现清单，位于 `pinyin9-joint-decoder-evaluation-v1-aborted` 和 `pinyin9-joint-decoder-evaluation-v2-aborted`。它们不是结果目录。

## 已知问题和未覆盖范围

- 正式 public/dev 指标、确定性回执和性能/内存比较未完成，因此不能宣布第二阶段质量提升或性能达标；
- 简拼、未完成尾音、邻键/漏按/多按/错序等恢复尚未统一进入联合状态；
- beam 宽度 16 和每位置 16 状态仍可能过早裁剪组合词路径，需要用正式归因数据验证；
- 高歧义输入通过最多 4 条公开提升的置信度门控保持保守，可能限制路径改善幅度；
- 32 位以内仍保留兼容 32 路候选展开，CPU 成本需要正式性能数据确认；
- 没有启用或评估用户学习，也没有修改正式词库、词频或上下文模型；
- 没有 HarmonyOS 真机时延、RSS、功耗、输入法框架或第三方编辑器端到端结果；Windows x86_64 结果不代表 HarmonyOS 真机；
- 没有商业输入法在相同冻结数据上的对照，不能声称达到、接近或超过商业输入法。

## 后续优先级

如果以后恢复正式工作，最值得优先处理：

1. 用新的版本化目录完成 public/dev 三轮，先获得 canonical 内部进入率、beam 淘汰率、公开 32 进入率及候选结构 SHA-256，再决定是否调整任何上限；
2. 把未完成尾音、简拼和有限编辑恢复纳入联合状态与独立惩罚，同时维持显式边界硬约束和可解释归因；
3. 根据正式 profile 优化词边生成、beam 拷贝和 32 路兼容解码，目标是降低 P95/P99 与峰值内存，而不是只追 Top1。

若恢复评测，应冻结新的实现 manifest 并使用新的版本化产物目录；不能覆盖当前停止状态、第一阶段文件或两个异常退出尝试。建议命令入口仍为：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\evaluate-pinyin9-joint-decoder.ps1 -Action PublicRegression -Runs 3
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\evaluate-pinyin9-joint-decoder.ps1 -Action Dev -Runs 3
```
