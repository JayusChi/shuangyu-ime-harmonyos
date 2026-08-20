# 全拼候选质量提升 V3

## 状态与结论

状态：`IMPLEMENTED / HOST_VALIDATED / REAL_ANONYMOUS_DATA_NOT_PROVIDED / DEVICE_NOT_RUN`。

本轮把投入集中到候选质量，不增加新的输入形态或 UI 功能：正式随包词库从 V2 `default` 提升到已审计的 `all_domains`，补齐口语、专名、应用/品牌、科技、软件、教育、医疗、金融、法律和有效热词；正式全拼链增加长词精确召回保护；评测把失败拆成互斥三类，并增加用户学习效果探针和匿名真实分布加权入口。

不能把不同数据集的百分比直接相减。旧 1,070 条冻结集 Top1 `56.168%`、目标未召回 `34.486%` 仍是历史全量基线；本轮没有重跑或改写它的 blind。当前正式实现只在旧公开 dev 300 条和独立 V2 dev 48 条上复测。全新 blind、真实匿名聚合文件和设备数据均未提供，因此不宣称成熟商业输入法质量。

## 正式词库与召回链

正式 `production.lex` 现在选用 V2 `all_domains` profile：

- 65,324 个词条，39,236 个拼音键；
- V2 实际新增 131 个文本/读音对；
- 3,751,923 bytes；
- SHA-256 `e4dead906109136470691d0e463c2ada34c8e5bb9b3fc62bb2de552ed751d365`；
- 相对 V2 首次默认层 3,746,486 bytes 只增加 5,437 bytes；
- 构建清单显式记录 `packagedProductionProfile=all_domains`，八个 profile 仍各自双构建并比较字节身份。

此前句子 decoder 只保留 4 条全拼切分路径、16 个输出候选，导致正确的长词即使已存在于正式词库，也可能被同音短词拼接路径截掉。本轮在 `CandidateQueryEngine` 构建只读紧凑索引：只索引五音节及以上的已有正式词条，运行时按去除分音符后的完整全拼做精确命中，每次最多发布 8 项，再进入既有去重、用户学习、用户词库和分页链。它不能创建词库外文本，也不改变 `rawInput`、`consumedRawLen` 或自动上屏合同。

专项覆盖：

- `yuegangaodawanqu → 粤港澳大湾区`；
- `nizhouqitiaojie → 逆周期调节`；
- `jiansuozengqiangshengcheng → 检索增强生成`。

只保护五音节以上的精确正式词，因此两三音节的上下文 bigram/trigram 重排仍可正常工作。上下文专项 8/8 和纠错/模糊音专项 9/9 均通过。

## 三类互斥失败指标

每条样本只能属于以下一种结果：

1. Top1 正确；
2. `ranking_error`：目标已在 Top5，但不是 Top1；
3. `recalled_outside_top5`：目标已召回，但首次名次大于 5；
4. `target_unrecalled`：完整候选快照中没有目标。

`metrics.failureBreakdown` 在总体、分类、输入长度和输入类型分组中同时输出三类 count/rate；failures JSONL 使用相同名称。单测断言 `Top1 + 三类失败 = sampleCount`，避免重复计数或漏计。

旧公开 dev 300 条在当前正式词库、纠错关、模糊音关下为：

| 指标 | 结果 |
| --- | ---: |
| Top1 / Top3 / Top5 | 62.000% / 66.000% / 67.000% |
| 未召回 | 94 / 300（31.333%） |
| 已召回但 Top5 外 | 5 / 300（1.667%） |
| Top5 内排序错误 | 15 / 300（5.000%） |
| 三轮候选确定 | PASS |
| 自动上屏 / ASCII 泄漏 / 状态丢失 / 引擎错误 | 0 / 0 / 0 / 0 |

该集合包含 20 条简拼/混拼、18 条 typo 和 12 条 fuzzy，而本次口径关闭纠错与模糊音，所以不能把 31.333% 全部解释为词库缺失。后续词库投入应先筛除输入能力未开启导致的未召回，再处理真正 `target_unrecalled`。

## 当前质量结果

独立 V2 dev 48 条在正式随包词库、纠错关、模糊音关下：

| 版本 | Top1 | Top3 | Top5 | 未召回 | Top5 外 | 排序错误 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 长词精确保护前 | 95.833% | 95.833% | 95.833% | 1 | 1 | 0 |
| 当前正式实现 | 97.917% | 97.917% | 97.917% | 1 | 0 | 0 |

提升项是原第 17 名的“粤港澳大湾区”进入 Top1。唯一未召回项 `nizhouqidiaojie → 逆周期调节` 的冻结输入把规范 `tiao` 写成了 `diao`；本轮不改冻结数据，也不把错拼伪装成词库缺失。三轮完整候选 SHA-256 均为 `983f1c899906b21505479b775e4e1fd1e41c1c9e6dd3ad2641e4f9575b8a4c83`，安全计数全 0。

结果文件：

- `artifacts/quanpin-quality-improvement/current-production-dev-results.json`；
- `artifacts/quanpin-quality-improvement/current-production-dev-failures.jsonl`；
- `artifacts/quanpin-quality-improvement/v2-production-exact-dev-results.json`；
- `artifacts/quanpin-quality-improvement/v2-production-exact-dev-failures.jsonl`。

## 上下文重排和用户学习

词级 backoff 上下文重排器仍使用既有已审计模型，模型只重排正式 decoder 已召回的候选。它在独立 context dev 上尚未证明净 Top1 提升，因此本轮不扩大权重、不把离线模型命中当成真实质量收益。模型缺失、损坏、SHA/版本不符或超时仍只关闭重排并回退基础顺序。

评测器新增隔离用户学习探针：只选取“已召回但非 Top1”的目标；每例先清空内存模型，记录初始名次，再显式选择目标 1～5 次并复测；不设置持久化路径，不写用户输入或候选文字到用户模型。旧公开 dev 以每目标 3 次选择复测：

- 可学习目标 20；
- 名次提升 17；
- 升到 Top1 16；
- 不变 3；
- 退化 0；
- 选择失败 0。

这说明当前用户学习对可召回的排序错误有效；未召回目标无法靠排序学习解决，必须由词库、解析或纠错召回处理。

## 真实匿名输入分布入口

仓库没有收到真实匿名数据，不能制造“真实分布结果”。本轮完成的是可执行且隐私收敛的接入门槛：

- schema：`quanpin-anonymous-input-distribution/1`；
- 来源必须声明 `opt-in-local-aggregate`；
- 只允许 `01-04`、`05-08`、`09-12`、`13-20`、`21+` 五个长度桶；
- 总事件至少 100，每个非空桶至少 20；
- 明确禁止 raw input、候选/编辑器文字、应用标识和用户标识；
- schema 为闭合白名单，任何额外字段整文件拒绝；
- 绑定聚合文件 SHA-256，输出每个桶的人工样本数、事件数、未覆盖桶和覆盖率；
- 只新增 `anonymousDistribution.weightedMetricsOverCoveredEvents`，不改变未加权冻结指标。

`examples/quanpin-anonymous-distribution.example.json` 只是均匀分布格式样例，不是真实数据。smoke 运行正确暴露 V2 dev 没有 `01-04` 样本、示例事件覆盖率只有 80%；这证明工具不会把未覆盖的真实质量区间静默算成通过。

使用方式：

```powershell
cargo run --release -p candidate-baseline -- quanpin-distribution-validate <aggregate.json>
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/evaluate-quanpin-quality.ps1 `
  -AnonymousDistributionPath <aggregate.json> -LearningRepetitions 3 `
  -ResultsPath <new-results.json> -FailuresPath <new-failures.jsonl>
```

## 验证与边界

已通过：

- `cargo fmt --all --check`；
- `cargo test -p candidate-baseline`（24/24）；
- `cargo test -p candidate-query`（16/16）；
- `cargo test -p ime-engine`（153/153）；
- `cargo test -p ime-engine --test quanpin_lexicon_v2`（6/6）；
- `cargo test -p ime-engine --test quanpin_features`（9/9）；
- `cargo test -p ime-engine --test quanpin_context_reranking_v2`（8/8）；
- `cargo test -p ime-engine --test quanpin_quality`（8/8）；
- 相关包 Clippy `-D warnings`；
- V2 构建、过期热词、领域隔离、双构建、篡改拒绝和资源上限门禁；
- ArkTS 单测与编译；
- x86_64、arm64-v8a OHOS Release 原生库；
- unsigned Release HAP 构建与实包内容门禁：40,502,445 bytes，SHA-256 `1FEA7059263B8ADE7201BA74634E967FCCCAA6FA9465F87A7A10508D1C1429A1`。

全量 `ime-ffi` 回归仍有一项与本轮全拼改动无关的既有九宫格断言失败：测试硬编码期待 `64` 的旧组合列表 `ng,ni`，当前引擎实际发布 `currentPinyin=ni`、备选 `mi,ng`；本轮没有借候选质量任务改写九宫格合同或基线。

仍需完成：真实匿名聚合输入、基于新实现身份的全新 blind、HarmonyOS 真机冷启动/内存/逐键延迟、真实聊天/浏览器/办公输入、长时稳定性和 Release HAP 真机安装验证。匿名分布接入和设备验证完成前，不把当前主机结果外推到真实用户总体。
