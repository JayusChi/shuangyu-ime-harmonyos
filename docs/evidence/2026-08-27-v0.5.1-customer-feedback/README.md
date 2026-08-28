# 0.5.1 客户反馈闭环证据

日期：2026-08-27

结论：客户在 0.5.0 上标记为未通过或未完全通过的万能键、复制粘贴、删行/恢复及输入码展示问题均已修正，并在最终 0.5.1 Release 上完成主机、发布包和三设备复验。

## 发布包

| 包 | 大小 | SHA-256 | 审计 |
| --- | ---: | --- | --- |
| `entry/build/artifacts/entry-release-unsigned.hap` | 71,296,141 bytes | `EA94F3F1776CCC7BE991A506EB672C4473370C0B411D0A4FD70BEAE1957E8A83` | PASS |
| `entry/build/default/outputs/default/entry-default-signed.hap` | 71,450,631 bytes | `230536B8189C9BA7F3D7255BD1734D3743A61953FD0CE1828616C68A36E8A840` | PASS |

两包均为 `versionName=0.5.1`、`versionCode=5001000`、`debug=false`。发布资源输入门禁、逐项负向夹具和实际 HAP 内容审计均 PASS。

## 主机门禁

- `scripts/test-rust.ps1`：完整 Rust workspace PASS；正式小鹤音形 FFI `39/39 PASS`，包括 `ju\`` 万能键正式 bundle 跨 FFI 回归。
- `scripts/test-release-resource-gate.ps1`：`RELEASE_RESOURCE_GATE_TEST_RESULT=PASS`。
- ArkTS：最新 `567` 项测试源码经 `UnitTestArkTS` 编译完成，Release 应用也完整编译、打包和签名。随后 Windows Previewer 在开始执行测试前崩溃于 AMD `atio6axx` OpenGL 驱动，未生成最新 Hypium 结果；最近一次完整结果为新增万能键 UI 与缓存粘贴回归前的 `565/565 PASS`。本记录不把宿主崩溃伪报为测试通过，新增路径由下述实机证据补充覆盖。

## 2in1

目标 `127.0.0.1:5555` 在清除旧方案设置并安装最终 unsigned Release 后，`scripts/accept-computer-stage4.ps1` 全项 PASS。覆盖物理键 `ni`、浮动候选、鼠标/数字选词、Esc、窗口移动/缩放跟随、应用切换、系统浏览器网页输入和固定软键盘不误弹。详细产物位于 `docs/evidence/2026-08-27-v0.5.1-computer-stage4/device-clean/`。

## Pad

目标 `127.0.0.1:5557` 安装最终 unsigned Release 后：

- `ju\`` 显示“居、局、具、举、剧、巨、聚”等 Rust 返回候选，不再被 UI 二次过滤；证据 `artifacts/customer-feedback-fix-20260827/pad/universal_pass.json`。
- 输入 `ni` 时宿主 TextInput 保持空白，候选区显示带实线下划线的 `ni`；证据 `artifacts/customer-feedback-fix-20260827/pad/ni.json`。
- `abc → 全选 → 复制 → 粘贴` 得到 `abcabc`，选区为 `selected=false`；宿主日志包含 `On copy`，输入法日志包含 `editor cached paste: success=true, length=3`。证据 `artifacts/customer-feedback-fix-20260827/pad/clipboard_final_pass.json`。
- 多行 `a\nb` 上执行回删下滑后得到 `a\n`，回车下滑后恢复 `a\nb`；证据 `delete_line_before_ab.json`、`delete_line_after.json`、`delete_line_restored.json`。

## ARM64 Phone

目标 BLK-AL00（HarmonyOS 6.1.0.135）安装最终 signed Release，并确认 `versionName=0.5.1`、`versionCode=5001000`、`debug=false`。在系统浏览器“搜索或输入网址”中输入 `ni` 后，宿主 TextArea 的 `text/originalText` 均为空，原始码只出现在输入法候选区；布局证据为 `artifacts/customer-feedback-fix-20260827/phone/ni.json`。布局保存后 USB 设备断连，因此截图文件未成功拉取；该断连不影响已经落盘的结构化输入框/候选区证据。

## 最终状态

功能和发布包达到 `IMPLEMENTED / HOST_RELEASE_VALIDATED / THREE_DEVICE_REGRESSION_PASS`。唯一未闭合项是当前 Windows 机器的 Hypium Previewer GPU 执行器，属于外部测试宿主故障，不是应用编译、打包或设备运行失败；后续在可用 Previewer 主机上补跑 `567/567` 即可补齐这条报告性证据。
