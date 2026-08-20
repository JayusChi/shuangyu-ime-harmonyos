# 26 键全拼候选质量冻结基线

冻结时间：2026-08-13T17:35:20+08:00  
基线 ID：`quanpin-quality-v1-20260813`  
数据身份 SHA-256：`f68c3006ee1c714eb9f1c543439785fd1164e61b6ef21a4d8da851d2b1e2ba22`

## 结论

本基线测量了当前正式 `ImeEngine` 和正式 `production.lex` 的主机候选质量，没有修改解析器、召回、排序、整句解码、用户模型或生产词库，也没有根据结果改写 blind 样本或 expectedTexts。

1070 条冻结样本的首次 Release 主机测量为：Top1 `56.168%`、Top3 `62.150%`、Top5 `63.551%`、MRR `0.593924`。这些数值不支持“达到成熟商业输入法水平”的结论。

## 数据身份与来源

数据全部为本项目在 2026-08-13 独立编写的词语、句式和确定性错拼变换，不含商业输入法数据、网页抓取语料、来源不明数据或从当前引擎候选反向产生的 expectedText。来源版本和许可写在 `dataset/sources.json`，方法写在 `dataset/DATASET_PROVENANCE.md`；两者与 JSONL 一起受冻结清单哈希保护。

| 文件 | 字节 | SHA-256 | 样本 |
| --- | ---: | --- | ---: |
| `dataset/dev.jsonl` | 65,468 | `0d7826d450756f9da5b78123c98686fa0665572154b2cfcbd9840b3db030eddf` | 300 |
| `dataset/blind.jsonl` | 170,919 | `e95641396a0e898f4e7d3478608e88286d18dfd191e47b1639b789c7294bd2db` | 770 |
| `dataset/sources.json` | 585 | `755477bdd51e1bb25941e29d036cea60cbda697886bdd5d5475225f9d7b958d8` | 0 |
| `dataset/DATASET_PROVENANCE.md` | 764 | `3816bc822b10ef998bcbc936ebdb4476634d050e4b8560b2cd990443a8bf23b0` | 0 |

冻结身份不使用 Git commit。普通评测会先核对文件集合、字节数和 SHA-256；任一变化都会以 `FROZEN_DATASET_HASH_MISMATCH` 或 `FROZEN_DATASET_FILE_SET_CHANGED` 失败。已有 manifest 不允许覆盖。创建新版本必须使用新的基线 ID 和新的 manifest 路径，并经过人工复核，不能用来改写本版本的 blind 结果。

## 样本分布

| 类别 | 总数 | dev | blind |
| --- | ---: | ---: | ---: |
| 常用单字和单词 | 160 | 45 | 115 |
| 二至四字常用词/短语 | 220 | 60 | 160 |
| 现代口语和聊天短句 | 220 | 60 | 160 |
| 长句、切分歧义和多义表达 | 110 | 30 | 80 |
| 人名、地名、机构名、专业词 | 110 | 30 | 80 |
| 多音字与同音候选 | 80 | 25 | 55 |
| 简拼、混输、未完成尾音 | 70 | 20 | 50 |
| 漏字、多字、邻键、错序 | 60 | 18 | 42 |
| 模糊音 | 40 | 12 | 28 |
| 合计 | 1,070 | 300 | 770 |

静态门禁检查重复 ID、重复 rawInput/expectedTexts、字段类型、split、来源、字符范围、clean 全拼的合法音节切分、fuzzy 字段使用范围和类别最低数量。本数据没有从现有单元测试批量导出；少量日常示例可能自然重合，但远低于 10%。

## 已测量事实

运行方式为 Windows x86_64 主机、Cargo Release、`schemeId=quanpin`、正式 `ImeEngine` 逐键输入、关闭用户学习、候选遍历到正式引擎可达末页。引擎版本为 `0.0.1-direct-actions`；`production.lex` 为 3,741,328 字节，SHA-256 `6a5f0567ca52c3e0ae539c9753109652c3c98218a0bfba1ad492d4ec494d6ff4`。

| 指标 | 结果 |
| --- | ---: |
| Top1 | 56.168% |
| Top3 | 62.150% |
| Top5 | 63.551% |
| MRR | 0.593924 |
| 无候选率 | 0.000% |
| 目标完全未召回率 | 34.486% |
| 已召回目标首次出现平均名次 | 1.793 |

三次运行对候选 ID、文本、reading、source、消耗长度和顺序计算的完整输出 SHA-256 均为 `37cbae20ff240bae34e129dabae5cc0253744655ae8648d6cb1871488656277a`，因此本次候选输出完全确定。三轮共 53,316 次完整引擎按键：P50 `2.195 ms`、P95 `63.565 ms`、P99 `101.811 ms`、平均 `10.860 ms`、最大 `162.631 ms`。

非显式自动上屏、ASCII 泄漏、状态丢失和引擎错误均为 `0`。这里的延迟和安全数据都是主机数据，不是 HarmonyOS 设备数据。

## clean、typo、fuzzy

| 分组 | 数量 | Top1 | Top3 | Top5 | 未召回 |
| --- | ---: | ---: | ---: | ---: | ---: |
| clean（含简拼/混输/尾音） | 970 | 61.753% | 68.247% | 69.794% | 28.041% |
| typo | 60 | 0.000% | 0.000% | 0.000% | 100.000% |
| fuzzy | 40 | 5.000% | 7.500% | 7.500% | 92.500% |

当前正式 `ImeEngine` 没有模糊音选项 API。评测工具校验并记录 `enabledFuzzyOptions`，但不会在评测层改写 rawInput 或模拟解析器；模糊音结果是原始按键直接进入当前正式引擎的事实，不能解释为“已启用模糊音”的效果。

## 类别结果与主要失败

| 类别 | Top1 | Top3 | Top5 | 未召回 |
| --- | ---: | ---: | ---: | ---: |
| 常用单字和单词 | 91.875% | 94.375% | 95.000% | 3.750% |
| 二至四字常用词/短语 | 80.000% | 80.909% | 80.909% | 15.000% |
| 现代口语和聊天短句 | 44.545% | 56.818% | 60.455% | 37.727% |
| 长句、歧义和多义表达 | 47.273% | 56.364% | 56.364% | 43.636% |
| 人名、地名、机构名、专业词 | 73.636% | 80.909% | 83.636% | 12.727% |
| 多音字与同音候选 | 56.250% | 71.250% | 75.000% | 22.500% |
| 简拼、混输、未完成尾音 | 0.000% | 0.000% | 0.000% | 100.000% |
| 拼写错误 | 0.000% | 0.000% | 0.000% | 100.000% |
| 模糊音 | 5.000% | 7.500% | 7.500% | 92.500% |

469 条 Top1 失败写入 `failure-cases.jsonl`：369 条目标完全未召回、79 条已召回但首选错误、21 条目标在第 6 名以后。未召回最多的类别依次为现代聊天 83、简拼/混输/尾音 70、typo 60、长句 48、fuzzy 37。低分没有改变进程成功语义，也没有触发数据删除或词库补丁。

## 未达到与尚未覆盖

未达到的指标包括总体 Top1/Top3/Top5、typo、fuzzy、简拼/混输/未完成尾音和长句召回；本任务没有设置“通过分数”，这些是测量结果而非发布判定。

尚未覆盖：HarmonyOS 设备候选质量和设备延迟、真实第三方编辑器链路、设备内存/RSS/soak、启用用户学习后的个性化、尚不存在 API 的正式模糊音开关、声调输入、语音或手写。项目刻意没有引入外部现代聊天语料；因此本数据的语言分布代表本项目编写的固定评测集，不代表全体用户分布。

## 验证状态

- `cargo test -p candidate-baseline`：10/10 PASS。
- `cargo fmt --all --check`：PASS。
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`：PASS。
- 全拼质量脚本：PASS，1070×3 完成。
- `cargo test --workspace`：本任务相关套件均 PASS；workspace 最终有 1 个既有、非本任务范围的音形工具失败。`yinxing-converter::contract::expected_category_order_is_unique_and_exact` 断言索引 7 为 `full-code-character`，而同一源码常量和正式 manifest 的索引 7 均为 `symbol`，`full-code-character` 位于索引 10。严格边界下没有修改该非评测工具或正式音形数据。

## 使用

普通复测：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\evaluate-quanpin-quality.ps1 -Runs 3
```

脚本先校验数据，再运行 Release 评测，输出：

- `artifacts/quanpin-evaluation/baseline-results.json`
- `artifacts/quanpin-evaluation/failure-cases.jsonl`

显式创建新基线版本只写新的 manifest，不覆盖当前版本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\evaluate-quanpin-quality.ps1 `
  -CreateNewBaseline `
  -BaselineId quanpin-quality-v2-YYYYMMDD `
  -FrozenAt 2026-08-13T00:00:00+08:00 `
  -NewManifestPath artifacts/quanpin-evaluation/freeze-manifest-v2.json
```

必须先独立审查新数据和来源授权，再选择是否使用新 manifest。不能因为 v1 分数低而修改 v1 blind 数据或 expectedTexts。
