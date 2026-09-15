# 逆切分验证记录

日期：2026-09-07。范围为当前工作区的新增逆切分功能，未改动应用版本号。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| ArkTS 全量 | 636 通过，0 失败/错误 | `outputs/reverse-split-arkts-result.txt`、`outputs/reverse-split-arkts-tests.log` |
| Rust：code-table-runtime / ime-engine / ime-ffi | 318 通过，0 失败/忽略，23 组 | `outputs/reverse-split-rust-tests.log` |
| 最终 Rust 切分专项 | 运行时 10、正式词库 2、FFI 1 全通过；另有 `oit` 专项包含在运行时全量中 | `outputs/reverse-split-final-focused.log` |
| 原生适配器主机测试 | 策略字段、两个模式动作、非法目标拒绝、显示/提交分离、第五码保留均通过；Native bridge 为模拟 | `outputs/reverse-split-gateway-tests.log` |
| Rust fmt / 严格 Clippy | 通过 | `outputs/reverse-split-clippy.log` |
| x86_64 / arm64-v8a Native | 两种架构均编译通过 | `outputs/reverse-split-native-build.log` |
| Release HAP | clean Release 构建及 signed HAP 内容门禁通过；包内两种 ABI 均包含新模式策略和动作 | `outputs/reverse-split-hap-build.log`、`outputs/reverse-split-hap-verify.log` |
| 设备安装、触屏及实体键盘 | NOT_RUN | 本轮只完成主机验证 |

最终 signed HAP：`entry/build/default/outputs/default/entry-default-signed.hap`，92,881,758 字节；SHA-256 `54E9F91183C35C19047C5EB25E6D6687F6BCE26310104EE9E4A02EBDA232F486`。

正式词库验证客户四组连续编码：`alyghfry`、`gmycxnta`、`xtupjdma`、`nivtsmne`，结果分别为“按理应该很容易”“干嘛要笑她”“学双拼简单吗”“你折腾什么呢”。`hfkn` 第二候选显示“困难”，提交“很困难”；继续输入 `n` 提交“很可能”并保留新组合 `n`。

正式词库已有 `oit` 同码符号 `🤭`，新增模式动作排在前两位，原符号继续可选。既有长码、OK 拼字和直通续码路径继续优先；功能仅处理 `2+2` 精确二简，不执行手动切分或任意分词。

初次全量检查中的旧“直通动作数 31”断言已随新增两项更新为 33；初次正式词库用例也已修正为验证前两项模式动作，同时保留原有符号。此处只记录修正后的通过结果。
