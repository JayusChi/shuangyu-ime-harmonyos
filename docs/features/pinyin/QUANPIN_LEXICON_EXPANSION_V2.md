# 全拼词库覆盖扩充 V2

> 2026-08-18 产品提升：`all_domains` 已被提升为正式随包 profile，基础、有效热词和六类专业领域共 131 个新增文本/读音对全部进入 `entry/src/main/resources/rawfile/production.lex`。下文“默认层/领域默认关闭”保留 2026-08-14 首次冻结时的实验口径；生成的 `default.lex` 仍用于隔离回归，但不再是当前随包文件。当前正式词库为 3,751,923 bytes、SHA-256 `e4dead906109136470691d0e463c2ada34c8e5bb9b3fc62bb2de552ed751d365`。

## 结论与边界

本阶段只扩充“正确词不在候选中”的召回覆盖。没有新增 bigram/trigram、神经重排、用户新词学习、云候选、滑行输入或语音，也没有修改候选排序权重。旧 V1 冻结数据、manifest、baseline/dev/blind 结果和上一阶段实现清单均未改动；公开的旧 blind 只作为历史回归数据。

V2 从文本源构建，不直接编辑二进制。首次冻结的默认 profile 只包含基础层和截至构建日期仍有效的热词层，六个专业领域词包默认关闭；2026-08-18 的产品提升基于该阶段已经完成的全领域 clean 回归和资源审计，显式把 `all_domains` 选为随包 profile。构建清单用 `packagedProductionProfile` 区分“生成默认层”和“实际随包层”。

## 数据与分层

统一 TSV 字段为：`text`、`pinyin`、`frequencyTier`、`category`、`sourceId`、`updatedAt`、`expiresAt`、`domain`、`layer`、`processingRule`。V2 原始输入 145 行；13 行与继承词库的相同文本/读音重复而被丢弃，1 个跨源冲突被确定性合并，最终实际新增 131 个文本/读音对。

| 层/分类 | 实际新增 |
| --- | ---: |
| 基础：现代口语 | 24 |
| 基础：人名 | 8 |
| 基础：地名 | 10 |
| 基础：机构/品牌 | 9 |
| 基础：产品/应用 | 2 |
| 可选领域：科技 | 12 |
| 可选领域：软件 | 12 |
| 可选领域：教育 | 11 |
| 可选领域：医疗 | 11 |
| 可选领域：金融 | 12 |
| 可选领域：法律 | 8 |
| 热词 | 12 |
| 合计 | 131 |

基础层 53 条、领域层 66 条、热词层 12 条。默认词库实际加入 65 条（基础 53 + 当前有效热词 12）；单领域包加入默认层再加对应领域；`all_domains` 加入全部 131 条。

V2 数据是项目独立整理的词汇事实与读音，采用 Apache-2.0，统一登记日期为 2026-08-14。外部页面只用于验证公开专名和时效性，不作为复制语料：华为 2026-06-12 HDC 页面用于“鸿蒙空间计算/智能体框架”，2026-02-28 MWC 页面用于“超节点/灵衢”，2026-05-21 页面用于“具身智能”。完整来源、逐文件哈希、许可证、日期和处理规则见 `dictionaries/source/quanpin-v2/source-catalog.json` 与 `artifacts/quanpin-lexicon-v2/source-manifest.json`。

热词逐条带 `expiresAt`，构建规则为 `expiresAt >= asOfDate` 才启用；本次日期 2026-08-14 时 12 条有效，2030-01-01 的自动测试确认 12 条全部过期。处理规则要求按月或季度复核，而不是永久提升为基础词。

## 规范化、校验与合并

- 文本与字段做 Unicode NFC、首尾空白清理；拼音转小写并把任意空白折叠为单空格。生产文本只允许 U+4E00–U+9FFF 汉字，因此空白、标点、控制/格式字符、替换字符和异常 Unicode 均不能进入二进制。
- 拼音逐音节对照 Rust 正式音节清单；汉字数必须等于拼音音节数。相同文本的不同合法读音以不同键保留。
- 去重键是 NFC `text + pinyin`。继承词库优先，不累加新频率；V2 冲突依次按基础层、有效热词层、领域层、较高层级频率、字典序较小的 `sourceId` 决定，并按拼音/文本/来源稳定输出。
- 字面安全策略拒绝敏感、违法和低质量项；乱码、不可见控制符和异常字段直接使构建失败，不静默吞掉。
- 硬上限：10,000 行、文本 16 字、拼音 16 音节、字段 256 字符、新增频率 6,000；Rust 通用 builder 另拒绝超过 1,000,000 的异常频率。

频率是可解释的层级映射，不改引擎权重：基础 `core/high/normal/low = 6000/4000/1600/600`；领域为 `1600/1400/1000/400`；热词为 `1000/800/650/500`。领域和热词的上限显著低于基础常用核心词。继承词库的同文本/读音始终优先，避免新增数据无条件挤掉已有常用词。

每个 profile 在一次构建中生成两份临时二进制并比较 SHA-256，八个 profile 均字节一致后才发布。二进制仍由正式 Rust `lexicon-builder` 产生并校验 CRC。

## 独立评测协议

V2 评测集由项目独立编写，不从生产 TSV 复制或生成。共 144 个样本：dev 48、全新 blind 96；12 个分类各 12 条，按分类固定为 dev 4 + blind 8。评测集在实现调试前冻结，identity 为 `1536445c...0347`。开发阶段只运行 dev；源码、源数据、频率规则、生产词库和测试冻结后，blind 只执行了一次命令，命令内部运行三轮。回执时间为 2026-08-14T07:09:46Z。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/create-quanpin-v2-dataset-utf8.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-quanpin-lexicon-v2.ps1 -AsOfDate 2026-08-14
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-quanpin-lexicon-v2.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/evaluate-quanpin-lexicon-v2.ps1 -Split dev -Profile all_domains -Runs 3
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/freeze-quanpin-lexicon-v2.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/evaluate-quanpin-lexicon-v2.ps1 -Split blind -Profile all_domains -Runs 3
```

最后两条命令是冻结/一次性盲测门禁；仓库已有正式 manifest 和 blind 回执，脚本会拒绝覆盖，不能再次运行。UTF-8 wrapper 用于兼容 Windows PowerShell 5.1 对无 BOM `.ps1` 的系统代码页解释。

## 评测结果

| 数据/词库 | Top1 | Top3 | Top5 | MRR | 未召回率 | 已召回平均首次名次 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V2 dev，扩词前 v115 | 45.833% | 60.417% | 60.417% | 0.526910 | 37.500% | 1.533 |
| V2 dev，V2 默认层 | 68.750% | 77.083% | 77.083% | 0.729524 | 18.750% | 1.718 |
| V2 dev，V2 全领域 | 95.833% | 95.833% | 95.833% | 0.959559 | 2.083% | 1.340 |
| V2 新 blind，V2 全领域 | 97.917% | 98.958% | 98.958% | 0.984375 | 1.042% | 1.011 |

V2 dev 的 clean 为 100%/100%/100%，前后不变。旧 V1 公开回归集的 270 个 clean 样本 Top1 保持 68.519%，Top3 从 71.852% 到 72.593%，Top5 从 73.333% 到 73.704%；没有 clean 回退。旧 V1 全体 300 例 Top1 保持 62.000%，Top3 从 65.333% 到 66.000%，Top5 从 66.667% 到 70.000%。

新 blind 分项如下。百分比依次为 Top1/Top3/Top5；括号是未召回率。

| 分类 | blind 结果 |
| --- | --- |
| clean | 100% / 100% / 100%（0%） |
| 现代口语 | 100% / 100% / 100%（0%） |
| 人名 | 100% / 100% / 100%（0%） |
| 地名 | 100% / 100% / 100%（0%） |
| 机构/品牌 | 100% / 100% / 100%（0%） |
| 科技 | 100% / 100% / 100%（0%） |
| 软件 | 87.5% / 87.5% / 87.5%（12.5%） |
| 教育 | 100% / 100% / 100%（0%） |
| 医疗 | 100% / 100% / 100%（0%） |
| 金融 | 100% / 100% / 100%（0%） |
| 法律 | 100% / 100% / 100%（0%） |
| 热词 | 87.5% / 100% / 100%（0%） |

输入长度分组的 blind Top1/Top3/Top5 为：5–8 键 80%/100%/100%，9–12 键 100%/100%/100%，13–20 键 97.297%/97.297%/97.297%，21+ 键 100%/100%/100%。

blind 保留两个失败记录且没有据此调词或加规则：`竞态条件` 的冻结输入为 `jingtatiaojian`，与规范拼写 `jingtaitiaojian` 相比疑似少一个 `i`，按冻结合同仍计为未召回；`灵衢` 位于第 2 名，Top1 为“领取”。两者都原样保存在 `post-change-blind-failures.jsonl`，不回写评测集。

## 资源、确定性与安全合同

| 指标 | 扩词前 dev | V2 默认 dev | V2 全领域 dev |
| --- | ---: | ---: | ---: |
| 词库字节 | 3,741,328 | 3,746,486（+0.138%） | 3,751,923（+0.283%） |
| 加载平均 / P95 | 213.020 / 216.746 ms | 183.259 / 186.232 ms | 183.603 / 194.148 ms |
| 进程峰值工作集 | 77,000,704 B | 76,902,400 B | 76,853,248 B |
| 逐键 P50 / P95 / P99 | 1.505 / 8.671 / 13.459 ms | 1.336 / 7.591 / 12.186 ms | 1.201 / 7.339 / 12.320 ms |
| 逐键平均 / 最大 | 2.497 / 21.898 ms | 2.147 / 16.531 ms | 2.088 / 16.354 ms |

新 blind 全领域逐键 P50/P95/P99 为 1.271/7.401/12.101 ms，平均 2.092 ms、最大 20.036 ms；加载平均/P95 为 188.313/200.626 ms，进程峰值工作集 78,389,248 B。以上都是同一 Windows x86_64 主机的 Release 测量，峰值工作集是进程级而非纯词库内存，不能替代真机数据。

Release HAP 从 39,514,683 B 到 39,864,517 B，增加 349,834 B（0.885%）；新 HAP SHA-256 为 `acdb8173...98b4`。HAP 中只打包默认 `production.lex`，不自动打包/启用全部专业领域。

所有 dev、公开回归和新 blind 的三轮完整候选 SHA-256 都分别一致；blind 候选哈希为 `60225f95...d093`。自动上屏、ASCII 泄漏、状态丢失和引擎错误计数全部为 0。正式 `ImeEngine` 测试同时断言逐键无自动 commit、`rawInput` 不丢失、默认领域关闭、分页候选完整确定、篡改词库拒绝；编辑器密码/数字/电话/URL 策略未被词库层绕过或修改。

## 冻结哈希

| 对象 | SHA-256 / identity |
| --- | --- |
| 源目录 catalog | `ebe08e0b0fe19530a73ea00f058361531a1a09082d63b0528056daf0e2121f24` |
| source manifest | `2e4ff523df467cd88c08382646a036feb9ecfd27aa9ef640c7f0e31a462bc5a0` |
| build manifest | `91019fdfd1ae60f5f4ffeee24d72570f59edea57bdb5fa3b0800a88f5090558a` |
| 默认 production.lex | `5096f142117bb399f63a918a3c10802ec35aa1f356305b62586a1c1f9e33a201` |
| all_domains.lex | `e4dead906109136470691d0e463c2ada34c8e5bb9b3fc62bb2de552ed751d365` |
| V2 评测 freeze manifest | `165cbe7aa81491603feb508ac2a08a86beabfdc868ab94cd98ec1dab31e0e809` |
| V2 评测 identity | `1536445c0d2faca9ad2785b13b0b54cd5df735b8b2642efd4f7619a5af680347` |
| 实现 freeze manifest | `3196484824a6bbc527efe8843ef85ec76fcbcc2c2c5d129fbcd76d8fe2b3744a` |
| 实现 identity | `794f864a4c25affcd658c7f5f2a06f08c83ec7b1618007c22ab7851a6cf4c0b7` |
| blind 结果 / failures | `3e855b3aac18911a2b0f1a7d097c8c2f8a5e265f4d5801cc32b858318f3050c8` / `01407bd25079017e685d20a24a252caf3d9d4b2a7614fc94c0736607d443e8d4` |
| 未改动的 V1 评测 identity | `f68c3006ee1c714eb9f1c543439785fd1164e61b6ef21a4d8da851d2b1e2ba22` |

## 测试与未覆盖项

`test-quanpin-lexicon-v2.ps1` 通过，覆盖非法拼音、音节数不匹配、异常 Unicode、异常频率、多音字、重复与跨源冲突、频率分层、旧常用 Top5 保护、热词过期、领域启停、双构建确定性、篡改拒绝、5 MiB/10 秒资源硬门槛、正式引擎召回、三引擎完整候选确定性和安全状态合同。`cargo fmt --all --check`、全 workspace clippy `-D warnings`、Release HAP 构建和 HAP 内容/哈希校验通过。

全 workspace `cargo test` 中，V2 及其他已运行套件通过，但仓库既有 `yinxing-converter` 的 `expected_category_order_is_unique_and_exact` 仍失败（期望 `full-code-character`，实际 `symbol`）；该模块不在本次范围，未修改。未覆盖 HarmonyOS 真机冷启动、低内存机型、不同 SoC、长期输入法生命周期、安装后 HAP 体积和真机 P50/P95/P99，因此本结果不声称达到成熟商业输入法水平。

## 文件清单

修改：

- `engine-rust/tools/candidate-baseline/src/lib.rs`
- `engine-rust/tools/candidate-baseline/src/quanpin_evaluation.rs`
- `engine-rust/tools/lexicon-builder/src/parser.rs`
- `entry/src/main/ets/infrastructure/resource/LexiconResourceInstaller.ets`
- `entry/src/internalDebug/ets/infrastructure/resource/CodeTableFixtureInstaller.ets`
- `entry/src/main/resources/rawfile/production.lex`
- `scripts/verify-release-hap.ps1`

新增实现与源数据：

- `engine-rust/crates/ime-engine/tests/quanpin_lexicon_v2.rs`
- `dictionaries/source/quanpin-v2/{base.tsv,domains.tsv,hotwords-2026-08.tsv,filter-policy.txt,source-catalog.json}`
- `dictionaries/generated/quanpin-v2/{default,all_domains,education,finance,legal,medical,software,technology}.lex`
- `scripts/{build-quanpin-lexicon-v2,create-quanpin-v2-dataset,create-quanpin-v2-dataset-utf8,evaluate-quanpin-lexicon-v2,freeze-quanpin-lexicon-v2,test-quanpin-lexicon-v2}.ps1`
- `docs/features/pinyin/QUANPIN_LEXICON_EXPANSION_V2.md`

新增审计产物：

- `artifacts/quanpin-lexicon-v2/{source-manifest,build-manifest,freeze-manifest,implementation-freeze-manifest,resource-metrics,blind-run-receipt}.json`
- `artifacts/quanpin-lexicon-v2/dataset/{dev,blind}.jsonl`
- `artifacts/quanpin-lexicon-v2/dataset/{sources.json,DATASET_PROVENANCE.md}`
- `artifacts/quanpin-lexicon-v2/{pre-change-dev,post-change-default-dev,post-change-dev,post-change-all_domains-dev,v1-public-regression-dev}-results.json`
- 上述评测各自的 `-failures.jsonl`，以及 `post-change-blind-results.json`、`post-change-blind-failures.jsonl`
- `artifacts/quanpin-lexicon-v2/{production-v2-additions,evaluation-all-domains}.normalized.tsv`

`.quanpin_v2_tmp/` 是双构建和 UTF-8 smoke 检查的可丢弃中间目录，不属于生产、评测或冻结输入；清理操作被当前安全策略拒绝后原样保留。
