# 复制反查 ofi 验证记录

实现与行为说明：[复制反查直通](../../features/direct-control/CLIPBOARD_REVERSE_LOOKUP.md)。

2026-09-11 本机验证：

| 检查 | 结果 |
| --- | --- |
| 客户 `$CC`、旧 `querycode` 导入及非支持表达式拒绝 | 通过 |
| 直通导入 | 68 条来源，接受 56 条、隔离 12 条；只有一个 `ofi` 动作 |
| Rust 复制反查专项 | 3 项通过（运行时、正式引擎、FFI） |
| 码表运行时回归 | 98 项通过 |
| 正式音形引擎回归 | 34 项通过 |
| 直通动作回归 | 5 项通过 |
| ArkTS 完整回归 | 714 项通过，Failure 0、Error 0 |
| Release 模式 default 产品、arm64-v8a 与 x86_64 | 签名 HAP 构建通过 |
| 安装包资源门禁 | 通过 |

日志保存在 `outputs/clipboard-reverse-*.log`。ArkTS 的 `test_result.txt` 在最终 HAP clean 前读取确认，清理后保留编译测试日志与本摘要。安装包中两个 `libime_bridge.so` 均检查到 `reverseLookup`、`ime_engine_reverse_lookup`、`clipboard.reverse`；独立检查输出为 `outputs/clipboard-reverse-package-check.json`。

安装包：`entry/build/default/outputs/default/entry-default-signed.hap`。沿用项目现有版本和开发签名。尚未安装到设备，固定／浮动候选中的系统粘贴授权和真实宿主上屏流程待真机验收。
