# 阶段 11.6.3 正式系统码表查询回归证据

状态：`COMPLETED`（2026-07-22）。

## 冻结输入

| 项目 | 值 |
|---|---|
| scheme | `xiaohe-yinxing` |
| bundle | `xiaohe-yinxing-production` |
| 格式 | `HSPYXP01` 1.0 |
| 文件大小 | 25,397,952 bytes |
| SHA-256 | `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30` |
| 内容 SHA-256 | `a2b2a8500c68e7e904fbc6bdefa89e4e9cc821182a0c6cbe409e0ec045229f68` |
| 来源 manifest SHA-256 | `ef93b39e05a0e11c818f8dd837b3f5b2e87777ab02aaba374765a846be7dce55` |
| 转换合同 SHA-256 | `2353a4b41bd9b1e9aeb1e309cb6ae657078de0d133f624921086f68d82ad8692` |
| 系统记录 | 73,263 |

分类画像：`core=68505`、`category-secondary=1690`、`one-key-secondary=26`、`two-key-secondary=66`、`out-of-table-character=362`、`full-code-word=464`、`rare-character=498`、`full-code-character=1652`。包内 36 条固定规则完成解析与画像校验，但在 11.6.3 仅作转换审计材料，不进入正式系统候选基线。

## 主机回归

- `cargo fmt --all --check`、`cargo clippy --workspace --all-targets --all-features -- -D warnings`、`cargo test --workspace` 全部通过。
- ArkTS 单元测试、x86_64/arm64-v8a Native 构建通过，interface/ABI version 保持 2。
- 23 个独立参考快照覆盖 1～4 码、精确优先、前缀回退、分类/`source_order`、跨类去重、空/无结果和大重码；逐项比较文本、编码、分类、来源顺序与候选 ID。
- 损坏矩阵覆盖缺失/空文件、magic/header/版本、截断/尾随字节、内容/记录摘要、manifest 元数据、分类缺失/重复/乱序、嵌套词库、`source_order`、用户规则和不安全路径，均返回结构化错误。
- 正式方案不读取外部用户规则，不受 `user-model` 影响；显式 `xiaohe` 忽略无关的正式包路径，损坏正式包失败后可显式重建双拼句柄。

详细命令与结果见 [host-verification.md](host-verification.md)，参考快照位于 `engine-rust/crates/code-table-runtime/tests/data/xiaohe_yinxing_stage11_6_3.tsv`。

## Release 性能

Release profile 使用 5 个独立新进程，每进程预热 20 轮、固定查询 18,000 次。OS 文件缓存未控制，因此结果不标记为冷启动。

| 指标 | 结果 |
|---|---:|
| 加载 P50 | 631.64 ms |
| 加载 P95 | 658.1578 ms |
| 查询 P50 | 2.14 μs |
| 查询 P95 | 16.16 μs |
| 查询最大值 | 403.5 μs |
| 峰值工作集 | 114,237,440 bytes |
| 最终驻留最大值 | 63,836,160 bytes |

原始数据见 [performance-release.json](performance-release.json)，摘要见 [performance-release.md](performance-release.md)。

## 设备验收

设备：x86_64 HarmonyOS `6.1.0.125(SP9DEVC00E120R4P11)` 模拟器，分辨率 1320×2856。Debug HAP 经 ArkTS → Node-API C++ → Rust 真链路执行；第一次完整 A～J 后由外部脚本强停应用并重新启动，再执行第二次完整 A～J，两轮均 PASS。

- A：正式 scheme/bundle/hash/八分类身份。
- B～E：1～4 码、精确优先、前缀回退、跨分类顺序与稳定去重。
- F：`un` 39 个候选，8 项/页，末页 4 项，无遗漏/重复并可回上一页。
- G～H：退格/reset/无结果、非法键、64-byte 上限和进程存活。
- I：损坏正式包明确失败；显式双拼 `nihc -> 你好`、`uurufa -> 输入法`。
- J：独立句柄与进程重启后文本、候选 ID、顺序和分页确定一致。

Debug HAP：40,387,851 bytes，SHA-256 `712dd5051b70d181bd178cd75755f38104f0dd5f03c0d6359edae0e028fb2cb9`。完整记录、布局树和截图见 [device/device-acceptance.json](device/device-acceptance.json) 与 `device/run1-*`、`device/run2-*`。

## Release 边界

最终 Release HAP 为 11,952,684 bytes，SHA-256 `4034f1efef559bc3a004119410966684b88fd0aa2bff45db00857c4612cc7a77`。源码与包内容门禁通过，包内 rawfile 仅有 `resources/rawfile/production.lex`；不含正式 `.hsyx`、fixture、Debug 页面/文案、原始 txt/ini、trace、构建报告、审计产物或网络权限。

负向门禁分别注入正式 `.hsyx`、fixture、原始 txt、trace、报告和 `INTERNET` 权限，六类均被拒绝。构建结束后，Debug 临时正式包、fixture 和负向测试目录均已清理。

本阶段不开放产品设置入口，不实现 11.6.4 正式用户规则，也不提前实现 11.6.5～11.6.8 的分类 UI、引导、自动提交或发布接入。
