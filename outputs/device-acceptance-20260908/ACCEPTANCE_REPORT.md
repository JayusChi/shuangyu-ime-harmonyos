# 三码空码逆切分验收报告

日期：2026-09-08

## 实现规则

- 切分模式开启时，三码没有精确候选且不存在有效长码后续，立即按 `2+1` 生成逆切分候选。
- `jda` 显示为 `jd'a`；首项显示并提交“简单啊”，第二项显示“安装”、提交“简单安装”。
- 三码本身有精确候选或仍存在有效长码后续时，不触发 `2+1`。
- 三码 `2+1` 是没有第四码时的候选状态。第四码到来后，完整四码重新按原有四码词、长码后续、`2+2` 或空码规则处理，避免破坏原来的四码行为。
- 传统模式保持原有行为，不触发三码或四码逆切分。

## 自动化验证

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 新增运行时切分测试 | PASS；12 个 `reverse_split_*` 测试全部通过 | `rust-tests-full.log` |
| 正式小鹤音形词库测试 | PASS；包含 `jda`、候选显示/提交、页大小、符号二简和原四码回归 | `rust-tests-full.log` |
| Rust 全工作区 | PASS；fmt、Clippy `-D warnings`、workspace tests、doc tests 全通过 | `rust-tests-full.log` |
| ArkTS/Hvigor | PASS；22 tasks | `arkts-tests-full.log` |
| 逆切分网关 | PASS | `reverse-split-gateway.log` |
| Release HAP 校验 | PASS | `verify-release-hap.log` |

## 模拟器验收

| 场景 | 2in1 `127.0.0.1:5555` | Phone `127.0.0.1:5557` |
| --- | --- | --- |
| 设备规格 | 3120×2080 | 1320×2856 |
| `oit2` 后输入 `jda` | PASS：`jd'a / 1.简单啊 / 2.安装` | PASS：`jd'a / 1.简单啊 / 2.安装` |
| 选择第二项 | PASS：提交“简单安装” | PASS：提交“简单安装” |
| 原四码 `hfoi` | PASS：自动提交“很😊” | PASS：自动提交“很😊” |
| `oit1` 传统模式输入 `jda` | PASS：只显示原始 `jda`，不切分 | PASS：只显示原始 `jda`，不切分 |
| 验收后恢复切分模式 | PASS | PASS |

设备证据分别位于 `computer/` 和 `phone/`：

- `three-code-jda.png/json`
- `three-code-second-selected.png/json`
- `four-code-hfoi.png/json`
- `traditional-jda.png/json`

## 安装包

- 签名 HAP：`entry/build/default/outputs/default/entry-default-signed.hap`
- 大小：`92,884,250` bytes
- SHA-256：`EB3AA6D6E33C052309E6DC0F210F9FCDB5CF5336BD4EE6205D565DDD4D1E810C`
- 构建时间：`2026-09-08T10:14:07+08:00`
