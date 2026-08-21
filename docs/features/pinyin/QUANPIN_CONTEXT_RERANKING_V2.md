# 全拼候选上下文重排 V2

## 结论与适用范围

本版本实现的是一个本地、只读、可解释的词级 backoff 重排器：优先查询 trigram，未命中时回退 bigram；只有一个上下文词时直接查询 bigram；所有 n-gram 都未命中时保持既有基础顺序。模型没有候选生成接口，只能重排 `ImeEngine` 已正式召回的全拼句子候选。

本阶段没有修改 `production.lex`，没有增加生产词条或词频，没有实现用户新词/短句学习、云候选、滑行输入、语音、编辑器策略或自动上屏。历史 dev/blind、manifest、baseline 和冻结清单均未覆盖。历史数据只作为公开回归。

独立 V2 dev 的同版本前后对照为 Top1/Top3/Top5 `90%/90%/90%`，MRR `0.9`，平均首次候选名次 `1.0`，平均额外选词次数 `0`；clean Top1/Top3 均为 `87.5%/87.5%`，没有回退，也没有净提升。因此当前结果证明了功能、安全合同、确定性和低开销，但尚未证明独立集上的 Top1/Top3 改善，不能宣称排序能力成熟。仓库没有收到全新的 blind 集，本版本未运行 blind，也没有用已公开 blind 代替。

## 现状审计

### 正式候选链路

全拼按键由 `PhoneticParser` 产生合法音节/待定尾部，随后进入正式查询链路。完整句子由 `SentenceDecoder` 在有界 beam/edge/output 限额内解码；拼写修正和模糊音扩展分别形成有限路径。每条路径先由 decoder 生成 `SentenceCandidate`，再转换为 `EngineCandidate`。多路径候选以文本确定性去重并截断，固定用户词典规则随后合并。`CandidateSession` 对最终快照分配稳定候选 ID，并承担分页、按 ID/索引选择和部分选词后的剩余 rawInput 管理。

V2 插入点位于正式 sentence decoder 召回之后、`EngineCandidate` 转换和固定用户规则合并之前。单键出现多个合法全拼切分路径时，只重排首个正式优先路径，防止把“每路径上限”误当成“每键上限”。模型无法创建文本、改变 `rawInput`、改变 `consumedRawLen` 或绕过正式召回。

### 既有 decoder 能力

`SentenceDecoder` 已将词频、路径覆盖、回退边数量、词数/长度等基础质量纳入句子分数，并已有从生产词典派生的字符级 `CharacterBigramModel`，用于跨词边界的字符衔接。本版本没有重复字符级能力；新增的是词级相邻词 bigram，以及仅在两个可靠已提交词都存在时使用的词级 trigram。

### user model 边界

既有 `UserModel` 只保存稳定候选 key 的哈希、计数和时间衰减信息，用于显式选择后的候选偏好；它不保存 rawInput、候选文本或编辑器全文。本版本不把 n-gram 上下文写入该模型，不导出真实用户输入，也不做运行时训练。

### 会话与安全合同

- 候选 ID 来源和 `CandidateSession` 快照逻辑未变；重排只改变已有候选的顺序。
- `consumedRawLen` 由正式 decoder/候选转换产生，V2 不写该字段。
- 完整显式选择后，仅把正式 decoder 已分词的末尾最多两个词保存在内存上下文中。
- 部分选词会保留未消费 rawInput，并清空上下文，防止把不完整组合误当成可靠提交。
- `backspace`、`reset`、`hide`/输入会话结束、scheme 切换以及隐私门禁关闭都会清空上下文。
- 密码、数字、电话、URL 等编辑器通过既有 `setSessionLearningAllowed(false)` 隐私门禁隔离；V2 不读取任意编辑器全文、其他应用内容或敏感字段。
- 不增加非显式自动上屏；评测中自动上屏、ASCII 泄漏、rawInput 丢失和引擎错误均为 0。

### 评测器口径

TopK 判断目标文本是否在前 K 个候选；MRR 对已召回目标使用 `1/rank`，未召回记 0；平均首次候选名次只统计已召回目标。平均额外选词次数为已召回样本的 `rank - 1`。逐键延迟对每次按键的正式 `ImeEngine` 调用采样，并报告 P50/P95/P99、均值和最大值。每轮还序列化完整候选结构、顺序和 ID 并计算 SHA-256；三轮哈希相同才标记确定性通过。

## 模型和排序

### 数据与模型

唯一训练输入是冻结的 `entry/src/main/resources/rawfile/production.lex`，版本 `200`，3,746,486 字节，SHA-256 `5096f142117bb399f63a918a3c10802ec35aa1f356305b62586a1c1f9e33a201`。许可证继承项目源清单中的 Apache-2.0。构建器只接受同时满足“拼音音节切分一致”和“汉字文本为源词条精确子串”的 2–3 音节生产词作为分词，拒绝仅同音但文本不同的替换；按源词频聚合相邻词，单源贡献封顶 100,000，总计数封顶 1,000,000，并按计数和词面确定性截取。

输出模型格式版本 1、模型版本 2，显式绑定 production lexicon 版本 200；包含 2,048 个 bigram 和 27 个 trigram，37,659 字节，SHA-256 `91b2beda854209b9476ef70689bd76ac8b229692c761f14a1aa8f7d83ffc3c7c`。重复构建两次字节一致。归一化构建审计 SHA-256 为 `49cf8fa5566ab536970535e8147ea430ca93c6be7adb761589a351af94c6aa0b`。来源、许可证、算法和构建身份分别记录在 `model-source-manifest.json` 与 `model-build-manifest.json`。

### 可解释得分

现有 `SentenceCandidate.score` 保留既有词频、字符上下文、覆盖和长度/回退质量。V2 的比较分为：

`finalScore = existingBaseScore + sum(bigramBonus) + optionalTrigramBonus`

- `bigramBonus(count) = min(96, 12 * (floor(log2(count)) + 1))`
- `trigramBonus(count) = min(144, 18 * (floor(log2(count)) + 1))`
- 候选内部相邻词查询 bigram；显式提交上下文与候选首词查询跨提交 bigram。
- 只有两个可靠上下文词时查询 `(context[-2], context[-1], candidate[0])` trigram；未命中才查询 `(context[-1], candidate[0])` bigram。
- 无命中增加 0 分，不扣减任何候选。
- 最终分相同，以原始位置为 tie-breaker。

### 候选保护与回退

只允许完整覆盖、`fallback_count == 0`、非固定规则且基础分不低于当前 Top1 350 分以内的连续候选段参与比较。每段最多比较前 12 个候选；低置信、不完整覆盖、fallback 候选和段外候选不动。固定用户规则在重排之后按既有流程合并，继续形成优先屏障。已有正式候选集合不变，尾部候选不丢失。

模型缺失、文件超限、损坏、SHA 不符、格式/模型版本错误、production lexicon 版本不符、内存或加载时间超限时，仅禁用 V2，完整使用既有排序。单次重排超过时限时返回传入顺序。配置版本不是 2 时在引擎创建前拒绝，避免错误模型 I/O。

## 硬上限

| 资源/工作量 | 硬上限 | 独立 dev 观测最大值 |
| --- | ---: | ---: |
| 单次候选池 | 16 | 16 |
| 参与 n-gram 的候选 | 12 | 8 |
| 单候选词数 | 8 | 受测试覆盖 |
| 上下文词数 | 2 | 2 |
| bigram 查询/键 | 96 | 16 |
| trigram 查询/键 | 12 | 1 |
| 模型 bigram/trigram 条目 | 4,096 / 2,048 | 2,048 / 27 |
| 模型文件 | 256 KiB | 37,659 B |
| 估算模型内存 | 512 KiB | 253,268 B |
| 模型加载 | 250 ms | 1.109 ms |
| 单键重排 | 5 ms | 6 µs |
| 查询缓存 | 0 | 0 |

加载使用 `take(MAX+1)` 有界读取；运行时使用嵌套哈希索引查表，不扫描完整模型或词库。失败路径在同一文件、内存和时间上限内回退。

## 评测结果

### 独立 V2 dev（40 例，Release，三轮）

| 指标 | 模型关闭 | 模型开启 |
| --- | ---: | ---: |
| Top1 / Top3 / Top5 | 90% / 90% / 90% | 90% / 90% / 90% |
| MRR | 0.9000 | 0.9000 |
| 已召回平均首次名次 | 1.0000 | 1.0000 |
| 已召回平均额外选词次数 | 0 | 0 |
| 无候选率 | 0% | 0% |
| 目标未召回率 | 10% | 10% |
| clean Top1 / Top3 | 87.5% / 87.5% | 87.5% / 87.5% |

五类各 8 例：ambiguous 100%，clean 87.5%，long_sentence 100%，modern_colloquial 75%，proper_name 87.5%；前后完全一致，所以没有需要解释的 clean 下降。11/40 样本出现实际 n-gram 命中（27.5%）；命中组 Top1/Top3/Top5 均为 100%，但这些目标在基础排序中已经是 Top1，不能记为净提升。bigram 查询命中率 11/122（9.016%）；trigram 0/2 命中，2/2 回退 bigram（100% backoff）。

模型关闭的全键延迟 P50/P95/P99/均值/最大值为 `1522/7041/15110/2073.34/25696 µs`；模型开启为 `1247/5987/13294/1763.25/17052 µs`。目标按键分别为 `1601/9384/15925/2453.69/25696 µs` 与 `1426/8503/14010/2084.66/17052 µs`。这是同一主机的短基准，观测到没有性能回退，但不把运行噪声导致的下降归因于模型优化。

三轮完整候选输出 SHA-256 均为 `637637c5266243644a34142d0ba7d453b0d18537a84e3b4a275b4fef0a6a330c`。安全计数均为 0。

### 模型派生效果审计

离线审计遍历的是模型条目，不是运行时查询方式，也不是独立质量集：2,048 个 bigram 中 1,824 个在正式候选池可比较，156 个目标基础名次低于 Top1，120 个被前移，1,704 个不变，0 个变差。27 个 trigram 均可比较，0 个前移、27 个不变、0 个变差。该结果证明模型有可解释的“已有候选前移”能力，但不能证明真实分布上的质量提升。

### 历史公开回归

同版本模型开关对照中，公开 V2 dev 均为 Top1/Top3/Top5 `68.75%/77.083%/77.083%`、MRR `0.729524`；公开 V1 dev 均为 `62%/66%/70%`、MRR `0.650272`。两组模型均为 0 次 n-gram 命中，开关候选结构哈希完全相同，证明无命中回退没有改变结果。旧 V1 基线文件记录的 Top5 67% 与当前代码的 70% 是引擎/评测版本差异，不能归因于 V2。

### blind 与设备

全新 blind 数据集和冻结 manifest 未提供，因此 `post-change-blind-results.json` 明确为 `not_run`，没有执行、重跑或调参。真机/模拟器端的逐键、模型加载、进程峰值内存和安装验证也未执行；本文延迟和内存均为 Windows x86_64 Release host 数据。

## 构建、测试与发布体积

- `cargo fmt --all --check` 通过。
- 新增/受影响 Rust 单测、集成测试和 FFI 测试通过；clippy `-D warnings` 通过。
- ArkTS 单元测试通过，Release HAP 构建成功。
- 完整 `cargo test --workspace` 只有一个与本任务无关的既有失败：`yinxing-converter` 的类别顺序断言实际 `symbol`、期望 `full-code-character`；本版本未修改相关代码或数据。
- 完整 `verify-release-hap.ps1` 通过，确认包内 `production.lex` 和 V2 模型大小/SHA 精确匹配且无网络权限/调试资源。
- Release HAP 为 40,107,920 字节，SHA-256 `2b8ee79b312f21562e0511aa782fdbb4f97f2a6ede61fb566e49855883a5176f`。相对上一阶段记录的 39,864,517 字节增加 243,403 字节（约 0.611%）；增加量包含模型、两 ABI 原生实现及 ArkTS 安装代码，不能仅按模型文件大小解释。

## 复现命令

从 `engine-rust` 目录构建模型：

```text
cargo run --release -p quanpin-context-model-builder -- derive ../entry/src/main/resources/rawfile/production.lex ../entry/src/main/resources/rawfile/quanpin-context-v2.qng
cargo run --release -p quanpin-context-model-builder -- derive-audit ../entry/src/main/resources/rawfile/production.lex ../artifacts/quanpin-reranking-v2/model.normalized.tsv
```

独立 dev 的前后命令只差 `--model <path> <sha256>`。评测器拒绝覆盖已有结果，三轮候选哈希必须一致。最终 blind 必须在代码、模型、参数、来源、测试与上限全部冻结后，用全新 blind manifest 执行一次包含至少三轮的命令；在提供该数据前不得运行。

