# 候选词改进阶段 6 证据

状态：`COMPLETED`（覆盖审计、稳定语料、确定性门禁、主机性能探针与现有 unsigned Release HAP 资源审计范围）

## 结论

本阶段没有修改正式词库。原因不是“未发现缺口”，而是 112 项验收语料确认了 11 项 `MISSING_IN_LEXICON`，但本阶段没有新增经过独立版本和许可证审查的数据源。所有真实缺失均写入 `missing-entries.json` 并标记为 `DEFERRED`；禁止用重复词条掩盖的 6 项 `PRESENT_NOT_RECALLED` 也保持原状，没有改动阶段 3～5 的召回、排序和学习合同。

正式资源保持冻结：

- `production.lex`：3,734,484 bytes，SHA-256 `765e2b0bd90244192a4c1bb6b2ec501ed28e0dbd731cbab4c326534f091eca10`。
- `xiaohe-yinxing-production.hsyx`：25,397,952 bytes，SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`。
- 新增、删除、重排正式词条均为 0；覆盖率修改前后相同。

## 验收语料与覆盖

稳定 TSV 共 112 项，覆盖常用单字、双字词、多字词、成语、日常口语、网络表达、地名、人名、项目专业词、多音字、音形/双拼一至四码、生僻字、扩展字符与非法编码。测试数据与生产词库分离。

| 方案 | 码长 | 用例 | 词库覆盖 | 正常召回 | 分页可达 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 小鹤双拼 | 1 | 4 | 100.00% | 100.00% | 100.00% |
| 小鹤双拼 | 2 | 15 | 93.33% | 86.66% | 86.66% |
| 小鹤双拼 | 3 | 5 | 80.00% | 80.00% | 80.00% |
| 小鹤双拼 | 4 | 31 | 83.87% | 83.87% | 83.87% |
| 小鹤音形 | 1 | 8 | 100.00% | 100.00% | 100.00% |
| 小鹤音形 | 2 | 12 | 91.66% | 83.33% | 83.33% |
| 小鹤音形 | 3 | 7 | 85.71% | 85.71% | 85.71% |
| 小鹤音形 | 4 | 16 | 93.75% | 93.75% | 93.75% |

双拼另有 14 项五键以上词句用例，机器报告保留其独立 `5+` 桶。分类覆盖和逐条排名见 `coverage-report.json`。

失败分类：

- `MISSING_IN_LEXICON = 11`
- `PRESENT_NOT_RECALLED = 6`
- `PRESENT_RANKED_TOO_LOW = 0`
- `PRESENT_NOT_ACCESSIBLE = 0`
- `INVALID_ENCODING = 2`
- `DATA_CONFLICT = 0`
- `UNSUPPORTED_BY_CONTRACT = 2`

11 项真实词库缺失为：音形“网络安全、开发者”；双拼“没问题、太好了、内卷、躺平、摆烂、陈晨、鸿蒙、候选词、双拼”。其中“太好了、双拼”虽无独立词条，仍可由句子组合路径召回；报告同时保存“词库存在”和“实际召回”两个维度，未把二者混为一谈。

6 项已有词条但未通过当前正常路径召回的是双拼“网络、不用客气、哈哈哈、十全十美、网络安全、人工智能”。它们属于召回/句子解码问题，不进入新增词库清单。

## 来源、许可证与频率

- `rime-pinyin-simp` 固定在提交 `0c6861ef7420ee780270ca6d993d18d4101049d0`，Apache-2.0，允许商业使用、修改和随 HAP 再分发，保留许可证与作者记录。
- 项目原创短句源为 Apache-2.0，可修改和分发。
- 小鹤音形客户交付数据按项目审批允许清理、转换、产品使用和 HAP 交付；正式 bundle 本阶段继续冻结。
- 未加入新来源，许可证不明确的数据没有进入 Release。

双拼仍使用 `clamp(original_weight + 1, 1, 1000000)` 的统一内部尺度；相同词条与 reading 使用频率饱和相加、来源排序去重的确定性合并。音形不混入双拼词频，继续以分类和物理 `source_order` 为主。

## 确定性、Release 与性能

覆盖审计连续运行两次均为 76,291 bytes，SHA-256 均为 `8ac272fc24fffb3793850d904f63431ddd1e5b7b283482539e88148c9fc94105`。

现有 unsigned Release HAP 资源门禁通过：37,750,936 bytes，SHA-256 `1b2a815b4b52f7982d7e6921aab4a5922c6e53aff2fb78071f8dcb91ca628ead`；仅批准 `production.lex` 和正式音形 bundle，没有原始客户码表、测试语料、审计材料、调试日志、凭据或模拟词库。

本阶段没有修改运行时或正式数据，因此阶段 5 的 a～z 冷/热基线、资源大小和包体积直接保持。附加 2 次预热、5 样本主机探针测得：

- 双拼 `h` 冷/热 P50：2.8591 ms / 55.3 µs。
- 音形 `h` 冷/热 P50：1.5086 ms / 1.2630 ms。
- 候选快照后工作集增量 8,179,712 bytes，进程峰值 149,012,480 bytes。
- 当前页 JSON：双拼 1,176 bytes，音形 1,186 bytes。

Phone/Pad 候选刷新、ARM64 物理真机、signed Release 第三方输入框和设备压力矩阵为 `NOT_RUN`，继续属于阶段 7。

## 机器证据

- `coverage-report.json`：逐条存在性、召回、排名、分页可达性、分类和来源。
- `missing-entries.json`：仅含真实词库缺失及延期接入决策。
- `source-audit.json`：来源与许可证结论。
- `frequency-normalization.json`：频率尺度和冲突合并规则。
- `lexicon-manifest.json`：工具、输入哈希与正式资源冻结状态。
- `build-hashes.json`：两次确定性运行和全部报告哈希。
- `release-resource-audit.json`：Release HAP 资源审计。
- `coverage-before-after.json`：修改前后覆盖对比。
- `performance-comparison.json`：阶段 5 基线继承和阶段 6 主机探针。

## 执行命令

```powershell
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
powershell -ExecutionPolicy Bypass -File scripts\generate-candidate-stage6-evidence.ps1 -PerformanceWarmups 2 -PerformanceSamples 5
powershell -ExecutionPolicy Bypass -File scripts\verify-release-hap.ps1 -HapPath entry\build\artifacts\entry-release-unsigned.hap
```

明确确认：本阶段没有通过扩充词库掩盖召回、排序或分页问题，没有修改阶段 3 的召回、阶段 4 的输入语义、阶段 5 的排序/学习、候选 UI、ABI 或冻结音形 bundle。
