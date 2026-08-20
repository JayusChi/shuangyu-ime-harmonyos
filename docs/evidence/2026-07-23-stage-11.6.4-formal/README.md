# 阶段 11.6.4 正式用户规则分层验收

结论：`COMPLETED`（2026-07-23）。冻结正式包内 36 条规则和可选外部用户词库已按确定性两层组成接入真实码表候选链路；host 门禁与 x86_64 HarmonyOS 6.1 模拟器两轮 A～J 全部通过。

## 冻结输入

| 项目 | Bytes | SHA-256 |
| --- | ---: | --- |
| `xiaohe-yinxing-production.hsyx` | 25,397,952 | `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30` |
| `user-rules.txt` | 582 | `6167a97066c38cd19ba3d3ac88085da0f52fc635a98b0b8144889f148897d3ab` |

规则画像：accepted/effective/fixed = 36/36/36；ordinary/delete/position/compound = 0；36 个唯一完整编码＋词条键。系统分类记录仍为 73,263，八类计数保持 68,505/1,690/26/66/362/464/498/1,652。

## 实现结论

- 层 1：正式包内已严格校验的 `UserLexiconSnapshot`。
- 层 2：外部 `userLexiconPath` 加载结果。
- 合并：内置在前、外部在后；同完整编码＋词条由外部规则覆盖；稳定重建 `source_order`、索引与统计。
- 执行：只调用既有 `merge_code_table_candidates`；完整候选执行硬规则后再 limit/分页。
- 隔离：fixture、纯系统 bundle 查询和 `xiaohe` 双拼链路不变；interface/ABI version 均为 2，C++ 未修改。

## Host 验收摘要

- `cargo fmt --all --check`：PASS。
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`：PASS。
- `cargo test --workspace`：PASS，零失败。
- ArkTS：288/288 PASS，零失败/错误/忽略；报告 SHA-256 `08d643154b0103cf2986b881803e5b2b36eafd8c193d9e22cc3220a5d9ba7ada`。
- 双 ABI Native：x86_64 25,429,952 bytes/SHA-256 `f16a7c4adf901e7254a0b4d8a1dd40d803bd1f70bddebafe874f95f44511036b`；arm64-v8a 25,975,974 bytes/SHA-256 `83c9255aa815b979e87fc1861d89c7bc1812057605250d329d63b3b7ed62b0af`。
- fixture 确定性与 Release 资源正负门禁：PASS。
- 正式来源审计：28/28 文件不变，manifest/contract SHA-256 分别为 `ef93b39e05a0e11c818f8dd837b3f5b2e87777ab02aaba374765a846be7dce55` / `2353a4b41bd9b1e9aeb1e309cb6ae657078de0d133f624921086f68d82ad8692`。

test-first 证据：正式引擎专项测试在接入前失败，首候选仍为系统“休整”而不是包内规则“修正”；实现两层快照后同一测试通过。

完整 host 命令与机器结论见 [`host-verification.md`](host-verification.md)。

## 设备验收

设备：`127.0.0.1:5555`，x86_64，HarmonyOS emulator `6.1.0.125(SP9DEVC00E16R1P1)`，`2880x1920`。Debug HAP 40,392,164 bytes/SHA-256 `04222cd447734de05b8b76c2acd5a4c663210e3f4cfcb30be7e3c97e371e83b9`。

两轮均从 force-stop/restart 开始，A～J 全 PASS，且两轮标签集合完全一致。机器报告、转录、布局树和截图位于 [`device/`](device/)。

## Release

Release HAP：11,956,076 bytes/SHA-256 `30b0f2742a5aabc6ed7fa65c77c35aa03b520af38908d1f62288766e0967eaf3`。包内 native 仅双 ABI `libc++_shared.so`/`libime_bridge.so`，rawfile 仅 `resources/rawfile/production.lex`（3,734,484 bytes）；不含 `.hsyx`、fixture、Debug 页面、用户词库、原始 txt/ini、网络权限或审计报告。

旧 `scripts/verify-stage11.ps1` 仍要求 Debug 临时注入文件永久存在，与 `build-hap.ps1` 构建后清理策略冲突，因此该汇总入口在 required-files 步骤失败；本阶段直接执行了它内部相同的 ArkTS 命令并解析机器报告。该历史脚本缺陷不影响 11.6.4 功能或其他已通过门禁。
