# 9 键候选召回、排序与延迟优化

日期：2026-08-19  
状态：`IMPLEMENTED / HOST_RELEASE_VALIDATED / DEVICE_NOT_RUN`  
范围：`schemeId=pinyin-9` 的 Rust 候选链；未修改 C ABI、Node-API 或 ArkTS 协议

## 结论

本轮在前一版联合搜索优化上继续改善了候选排序，没有扩大 beam、图边上限、公开拼音路径或候选快照。900 条 public-regression 和 155 条 dev 均使用正式 `production.lex`、Release `ImeEngine` 完成三轮确定性评测；本轮没有读取或重跑 blind。

| 数据集 | 指标 | 本轮前 | 本轮后 |
|---|---|---:|---:|
| public-regression（900） | Top1 | 34.333% | 34.889% |
|  | Top3 | 42.667% | 43.889% |
|  | Top5 | 45.222% | 46.333% |
|  | MRR | 0.401960 | 0.410830 |
|  | 目标未召回 | 34.667% | 34.444% |
|  | 已召回平均名次 | 9.62 | 6.67 |
|  | 每键 P50 / P95 / P99 | 14.418 / 71.588 / 109.433 ms | 12.987 / 62.349 / 92.795 ms |
| dev（155） | Top1 / Top3 / Top5 | 15.484% | 16.129% |
|  | MRR | 0.161341 | 0.167618 |
|  | 目标未召回 | 72.258% | 72.258% |
|  | 已召回平均名次 | 15.30 | 12.63 |
|  | 每键 P50 / P95 / P99 | 13.084 / 65.560 / 96.904 ms | 12.318 / 61.034 / 92.350 ms |

public-regression 逐样本对比中，Top1 修复 5 条、退化 0 条；Top3 修复 13 条、退化 2 条；Top5 修复 13 条、退化 3 条。其中 `你好`、`尽快处理`、`按时联系`、`按时工作`、`确定性测试` 升到首选；临时方案出现的 `离了解决` 错误提升已被消除，`立刻解决` 恢复到第 2 名。

两组数据各三轮完整候选 SHA-256 均一致；自动上屏、ASCII 泄漏、状态丢失和引擎错误均为 0。dev 中有一条冻结的 65 位输入按合同命中 64 位上限，不计为状态丢失。

## 实现

1. 数字签名索引同时保存全局频率顺序和读音优先顺序。联合图先为不同拼音读法保留边，再补同读音汉字，避免少数高频同音字占满每位置 64 条边。
2. T9 排序使用专用歧义代价：惩罚单字母音节、过多音节和过多词边，抑制 `a'a'ni'zhu` 一类碎片路径；全拼和双拼分数不受影响。
3. 候选使用可解释的信任分层：整词数字直达最高；平均每词至少覆盖 2 个音节的紧凑 joint 句子与兼容解析候选进入同一可比较分层；过度切分的推测句子留在低层供召回。
4. T9 joint 的跨词字符 bigram 上限设为 64 分，低于词频一个数量级档位的 70 分。它仍可解决接近分平局，但不能再把 `离了|解决` 的跨词边界错当成高频词内 `了解` 证据。
5. 继续覆盖全部 32 条公开拼音路径，但为 `pinyin-9` 使用独立的 Top-4 兼容句子预算和更小的 `128 edges / beam 4` 图，不再执行历史上的 `32 × 16` 候选扇出。
6. 联合搜索稳定提升最多 4 条词典支持的拼音路径；beam 仍为每位置 16 状态，候选快照仍为 256，没有通过无限扩大搜索换质量。

## 验证

- `scripts/test-rust.ps1`：PASS
- `cargo fmt --all -- --check`：PASS
- `cargo clippy --workspace --all-targets -- -D warnings`：PASS
- `cargo test --workspace`：PASS
- sentence-decoder：32/32 PASS
- T9 引擎专项：11/11 PASS
- `ime-ffi`：36/36 PASS
- public-regression：900 条 × 3 轮，确定性 PASS
- dev：155 条 × 3 轮，确定性 PASS

最终证据：

- `artifacts/pinyin9-optimization-20260819-round4/implementation-manifest.json`（28 个实现文件；文件 SHA-256 `4fdbbee4f2713184502b022a61e3542452d0188e6f3b83032cf59b313d14d702`）
- `artifacts/pinyin9-optimization-20260819-round4/public-regression-results.json`
- `artifacts/pinyin9-optimization-20260819-round4/public-regression-failures.jsonl`
- `artifacts/pinyin9-optimization-20260819-round4/dev-results.json`
- `artifacts/pinyin9-optimization-20260819-round4/dev-failures.jsonl`

## 剩余边界

public-regression 仍有 34.444% 目标未召回，剩余失败主要是 parser 没有生成标准路径、标准路径已进入但正文未召回，以及长输入在有界 beam 中被剪枝。Top1 34.889% 仍不代表商业输入法水平。ARM64 真机、真实聊天/浏览器应用、设备 P95/P99、RSS 和长时压力均未运行。本轮未重跑 blind，不能把 public/dev 结果外推为新的 blind 结论。
