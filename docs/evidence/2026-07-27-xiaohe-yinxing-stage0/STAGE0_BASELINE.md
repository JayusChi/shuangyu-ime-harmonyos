# 小鹤音形改进：阶段 0 基线报告

日期：2026-07-27  
结论：`阶段 0：PASS`

## 完成范围

本轮只新增基线生成、候选/双拼快照、性能证据、CI 测试和 ADR。没有实现一至三码渐进候选，没有修改 `query_exact_or_prefix`、正式来源、正式 bundle、用户词库格式、小鹤双拼、分页、四码提交、第五键顶屏或空码切分语义。

## 正式资源

| 字段 | 冻结值 |
| --- | --- |
| scheme ID | `xiaohe-yinxing` |
| bundle | `xiaohe-yinxing-production.hsyx` |
| 大小 | `25,397,952` bytes（`24.221375 MiB`） |
| SHA-256 | `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30` |
| 格式 | `HSPYXP01 1.0`；嵌套 `HSPLEX01 1.1` |
| 数据版本 | `source-receipt-1` |
| 转换器 | `yinxing-converter/1.0.0` |
| 普通记录 | `73,263` |
| 内置规则 | `36` 条，全部 `#固` |
| core | 必选 |
| 默认分类 | 八类全部启用 |
| archive 白名单 | `13/13`，严格加载器验证 |
| 原始 TXT/INI、审计、调试、绝对路径、敏感配置 | 均未进入 bundle |

分类计数：

| 分类 | 记录数 |
| --- | ---: |
| `core` | 68,505 |
| `category-secondary` | 1,690 |
| `one-key-secondary` | 26 |
| `two-key-secondary` | 66 |
| `out-of-table-character` | 362 |
| `full-code-word` | 464 |
| `rare-character` | 498 |
| `full-code-character` | 1,652 |

## 候选旧行为

分页大小是 Rust 正式引擎实际上限 `9`；以下十项均存在系统精确候选，因此系统查询仍走 `Exact`，但内置 `#固` 的更长完整编码可按当前既有用户规则合同排到前面。

| 编码 | 完整候选数 | 当前首选 |
| --- | ---: | --- |
| `aa` | 1 | 阿 |
| `ai` | 1 | 爱 |
| `an` | 3 | 按时 |
| `ni` | 1 | 你 |
| `hc` | 1 | 好 |
| `ui` | 4 | 时间 |
| `vi` | 6 | 知道 |
| `wo` | 1 | 我 |
| `xm` | 3 | 现金 |
| `xq` | 2 | 修正 |

完整候选字段、分页前列表和第一页见 `dictionaries/audit/xiaohe-yinxing/baseline/candidate_behavior_baseline.json`。

专项快照还冻结：

- 四码唯一：`aaba → 阿爸`、`aabo → 阿伯`、`aabq → 傲岸不群`，均提交一次并清空组合。
- 四码多候选：`ahqi`、`aifu`、`aiku`，均保持组合且不自动提交。
- 无结果/非法/超长路径，包括当前 `aaaa` 会按既有反向空码切分提交“阿”并保留 `aa` 的事实；这不是阶段 0 新行为。
- 用户 `#删`、多个 `#固`、`#1/#2/#99`、同位置、越界、分页前应用、稳定去重和规范化后重载一致。
- 分类默认、关闭一个可选分类、关闭多个分类、尝试关闭 `core`；`ahqi` 从 2 候选变 1 候选时唯一性同步变化。

## 小鹤双拼隔离

机器快照覆盖：

| 文本 | 真实按键 |
| --- | --- |
| 你好 | `nihc` |
| 输入法 | `uurufa` |
| 小鹤 | `xnhe` |
| 双拼 | `ulpb` |

记录了逐键组合、第一页、首选、选择提交、翻页探针、退格、reset、重建会话和从音形切回双拼。四项首选与最终提交均等于目标文本；切回 `xiaohe` 后“你好”恢复为首选。

## 性能基线

环境：Windows x86_64 主机、Rust Release、5 个独立进程样本、2 次预热，OS 文件缓存未控制。主机数据不是 ARM64 真机数据。

| 指标 | 样本 | P50 | P95 | 最大值 | 状态 |
| --- | ---: | ---: | ---: | ---: | --- |
| bundle 文件读取 | 5 | 7,394,600 ns | 9,542,900 ns | 18,441,200 ns | PASS |
| 大小与 SHA-256 | 5 | 35,359,600 ns | 36,626,500 ns | 40,049,500 ns | PASS |
| 反序列化、验证与索引构建（融合） | 5 | 633,962,300 ns | 634,190,700 ns | 637,314,700 ns | PASS |
| 完整主机加载估算 | 5 | 641,356,900 ns | 643,733,600 ns | 655,755,900 ns | PASS |
| 已读字节严格热重载 | 5 | 636,181,300 ns | 642,055,300 ns | 647,370,900 ns | PASS |
| 首键到 Rust 候选可用 | 5 | 329,100 ns | 361,100 ns | 372,900 ns | PASS |
| 逐查询 | 90,000/进程 | 4,880 ns | 19,740 ns | 274,500 ns | PASS |
| 状态机循环 | 500/进程 | 812,000 ns | 1,355,960 ns | 2,067,900 ns | PASS |
| 峰值进程内存 | 5 | 147,386,368 bytes | 147,402,752 bytes | 147,406,848 bytes | PASS |
| 稳态进程内存 | 5 | 97,636,352 bytes | 97,636,352 bytes | 97,640,448 bytes | PASS |
| 500 次会话循环后内存增量 | 5 | 163,840 bytes | 163,840 bytes | 188,416 bytes | PASS |

当前严格加载函数把 archive/content SHA、manifest/白名单、嵌套词典反序列化和索引恢复融合在一起，无法在不改生产加载器的前提下可靠拆分。ArkTS 安装缓存复用、UI 可见首键延迟和跨进程方案切换延迟为 `NOT_RUN`，详见 `PERFORMANCE_BASELINE.md`。

## 门禁

| 命令 | 状态 | 耗时/结果 |
| --- | --- | --- |
| `cargo fmt --all -- --check`（修改前） | PASS | 0.702 s |
| `cargo test --workspace`（修改前首次） | BLOCKED | 工具 120 s 上限超时；超时前无失败 |
| `cargo test --workspace --quiet`（修改前重跑） | PASS | 184.768 s，387/387 |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings`（修改前） | PASS | 0.392 s |
| 阶段 0 统一生成，候选/双拼各运行两次 | PASS | 确定性哈希稳定 |
| `cargo test -p code-table-runtime --test stage0_baseline` | PASS | 2/2 |
| ArkTS `hvigor ... test` | PASS | 25.720 s；项目既有警告仍存在 |
| `scripts/build-native.ps1 -Abi all` | PASS | 2.643 s；x86_64/arm64-v8a |
| `scripts/build-hap.ps1 -SkipRust -BuildMode debug` | PASS | 21.118 s；40,801,306 bytes |
| `scripts/build-hap.ps1 -SkipRust -BuildMode release` | PASS | 28.983 s；37,572,616 bytes |
| `scripts/verify-release-hap.ps1` | PASS | 3.420 s；SHA-256 `0cb2a34d...1c0628` |
| 11.6.8 Release 六项负向门禁 | PASS | 4.363 s |
| 两个独立正式输出目录构建与比较 | PASS | 65.014 s；15/15 文件一致且 bundle 与正式版一致 |
| `cargo fmt --all -- --check`（修改后最终） | PASS | 最终无格式差异 |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings`（修改后最终） | PASS | 0.413 s |
| `cargo test --workspace --quiet`（修改后最终） | PASS | 213.607 s，389/389 |

修改后全量回归包含新增阶段 0 的 2 项专项测试；既有 387 项继续通过。

## NOT_RUN 与 BLOCKED

- `NOT_RUN`：ARM64 物理真机、真机性能、ArkTS UI 可见首键延迟、跨进程方案切换延迟、signed Release 独立第三方 TextInput 本轮重跑。
- `BLOCKED`：x86_64 模拟器密码场景不向 `uitest` 暴露键帽；该限制属于既有 11.6.9 设备自动化缺口，不影响阶段 0 的主机语义冻结。

## 发现

1. 提示词背景写“分页大小”但没有给冻结值；当前 Rust `QueryConfig` 实际把请求页大小限制到 `9`，ArkTS 请求 `50` 最终仍被限制为 `9`。
2. 内置 `#固` 规则可使更长完整编码候选排在二码系统精确项之前，例如 `an → 按时`、`ui → 时间`；这是真实旧行为。
3. `aaaa` 不是简单空列表：当前状态机会执行反向空码切分，提交“阿”并保留 `aa`。阶段 1 必须防止把新增前缀候选误当完整可提交段。
4. `conversion_contract.json` 的 `converter_version` 仍是历史占位值 `yinxing-converter/0-not-implemented`，而正式 manifest、bundle 元数据和实际工具均为 `yinxing-converter/1.0.0`。本阶段没有修改已冻结合同文件，只记录差异。
5. `.git` 目录在当前工作区不可被 Git 识别，无法使用 `git status/diff` 完成标准工作树审计；本轮改用明确文件清单、正式哈希、双构建比较和临时目录清理检查。

## 工作区与隔离结论

- 正式来源：未修改；转换器按冻结 source manifest 验证输入。
- 正式 bundle：未修改；当前哈希仍为 `00c7...1e30`，两个独立构建与其逐字节一致。
- 临时双构建目录：已清理。
- HAP/构建缓存：只作为本地构建产物，不纳入阶段 0 基线目录。
- 权限：未修改；Release 网络权限负例按预期拒绝。
- 生产代码：没有修改候选、提交、切分、分类、用户规则或方案切换实现；仅扩展既有 Release benchmark 的观测字段。

```text
阶段 0：PASS
```
