# 2026-09-07 修复与双设备验收报告

## 结论

本轮在已连接的 Phone 模拟器（`127.0.0.1:5555`）和 2in1/Computer 模拟器（`127.0.0.1:5557`）上完成修复回归。代码门禁、签名包校验、切分模式核心行为、独立开关、`oit` 直通切换、成对符号插入、`oui` 删行及输入法进程重启后的方案保持均通过。

客户指定的 QQ、备忘录、头条和真实实体键盘场景未安装或未连接，因此这些特定宿主/硬件组合为 `NOT_RUN`，不纳入“已通过”范围。可用模拟器范围内没有遗留失败项。

## 本轮修复

1. 中文符号键盘将分离的 `〔`、`〕` 改为一个成对键；点击一次插入 `〔〕`，光标停在中间。
2. 新增设置方案到 HarmonyOS 输入法子类型的同步，设置为“小鹤音形”后，输入法会同步选择 `shuangyu_yinxing_zh_cn`，防止输入法进程重启时被系统当前子类型覆盖回全拼。
3. 输入法创建和设置变化时都会执行子类型同步；列表查询或系统切换失败时安全返回，并记录日志，不阻断输入会话。
4. 更新对应 ArkTS 单元测试，并按当前正式词库重新生成候选基线；候选文字和顺序没有变化，基线中的稳定来源序号随正式包新增记录顺移。

## 自动化门禁

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| ArkTS/Hvigor 全量单元测试 | PASS，`BUILD SUCCESSFUL`，22 tasks | `repair-pass/arkts-tests-final.log` |
| Rust 工作区全量门禁 | PASS；fmt、Clippy `-D warnings`、workspace tests、doc tests 全通过 | `repair-pass/rust-tests-final.log` |
| 逆切分网关 | PASS；策略、`oit1/oit2`、候选显示/选择、五码顶屏 | `repair-pass/reverse-split-gateway-final.log` |
| 六项负向发布门禁 | PASS | `repair-pass/release-negative-gate-final.log` |
| 发布 HAP 校验 | PASS | `repair-pass/verify-release-hap-final.log` |
| 双设备安装/启用状态 | PASS；均为 0.8.0、当前输入法、完整体验模式 | `repair-pass/installed-state-final.txt` |
| Git 空白错误检查 | PASS；仅现有 LF/CRLF 提示 | `git diff --check` |

## 设备回归

| 场景 | Phone | Computer | 结果/证据摘要 |
| --- | --- | --- | --- |
| 最终签名包安装后 `oit` 菜单 | PASS | PASS | `final-installed-after-ime-restart.*`：显示 `1 [传统]`、`2 [切分]` |
| `hfkn` 切分候选 | PASS | PASS | `repair-split-hfkn.*`：编码显示 `hf'kn`；首选“很可能”，次选“困难” |
| 选择第二候选 | PASS | PASS | `final-installed-split-second.*`：编辑框为“很困难” |
| 第五码顶首选并接续编码 | PASS | PASS | `repair-split-fifth-key.*`：提交“很可能”，第五码作为新段保留 |
| 唯一二简组合自动上屏 | PASS | PASS | `repair-split-unique-auto.*`：`alyg` 自动提交“按理应该” |
| 设置关闭切分模式 | PASS | PASS | `repair-settings-toggle-off-hfkn-final.*` / `repair-computer-settings-toggle-off-hfkn.*`：`hfkn` 不触发切分 |
| 设置重新开启切分模式 | PASS | PASS | `repair-settings-toggle-on-endtoend.*` / `repair-computer-settings-toggle-on-hfkn.*`：切分候选恢复 |
| `oui` 删当前行并继续输入 | PASS | PASS | `repair-oui-before.*`、`repair-oui-after-delete.*`、`repair-oui-after-retype.*` |
| 中文 `〔〕` 成对键 | PASS | PASS | `repair-symbol-layout.*`：只有一个成对键，不再显示两个半边键 |
| 成对插入后的光标位置 | PASS | PASS | `repair-symbol-pair-result.*`；Phone 最终包证据 `final-installed-symbol-pair.*`：结果为 `〔＆〕` |
| 输入法进程重启后保持小鹤音形 | PASS | PASS | `repair-pass/*/final-hilog.txt`：加载 `xiaohe-yinxing-26`，系统子类型为 `shuangyu_yinxing_zh_cn` |
| 自动识别显示方式保持 | PASS | PASS | 同一最终日志：`inputPresentationPreference=AUTO` |

## 安装包

- 最终签名 HAP：`entry/build/default/outputs/default/entry-default-signed.hap`
- 大小：`92,885,548` bytes
- SHA-256：`0A62FADCDE6A93919903CF6AC4BE366AA0E18C341921AC906A8B4534A047853D`
- 构建时间：`2026-09-07T17:27:05+08:00`
- 发布校验生成的未签名 HAP：`entry/build/artifacts/entry-release-unsigned.hap`
- 未签名 HAP SHA-256：`99246397152CEB1B4F7D7595F023386511BF077173D296CE0771C5DE8814BA86`

## 环境未覆盖项

以下项目需要安装对应应用或连接真实键盘后再做宿主兼容性验收：

- QQ 中的实体键盘字母误上屏。
- 系统备忘录中的实体/虚拟键盘嵌入编码表现。
- 头条中 `oui` 删行后继续输入的字母误上屏。
- USB/Bluetooth 实体键盘的完整按键事件链路。

代码层和独立验收应用已经覆盖不提交预编辑字母、`oui` 删行后继续输入、候选窗口与切分状态恢复，但这些结果不能替代上述具体宿主应用实测。
