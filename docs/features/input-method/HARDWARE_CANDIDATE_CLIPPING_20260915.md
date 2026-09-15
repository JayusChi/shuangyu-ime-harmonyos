# 手机实体键盘候选裁切修复（2026-09-15）

## 问题与修复

上一轮模拟器验收的 D1：手机实体键盘模式、浮动字号 17、每页 5 项时，输入 `ui` 并按 `]`，第三项被裁切，第四、第五项不可见。数字键 5 虽然能选中“室”，用户却无法看全当前页。

原因是浮动窗口受屏幕宽度限制，触屏翻页组件仍占用 108 vp，候选又沿用较大的横向内边距。

- 实体键盘模式移除触屏翻页组件及其宽度预留，继续通过 `[`、`]` 翻页。
- 屏幕宽度小于 600 vp 的实体键盘模式，普通候选左右内边距改为 3 vp，选中项为 7 vp；宽屏与触屏候选保留原有间距。
- 编码区左右内边距保持 10 vp，候选继续左对齐、单行显示。
- 宽度估算与实际渲染共用相同的间距和翻页组件规则，避免首次显示与测量后不一致。
- 每页候选数、引擎分页及数字选词映射保持原有行为。

修改涉及 `FloatingCandidateLayout.ets`、`FloatingCandidateRoot.ets`、`FloatingCandidateWindowController.ets`，并在 `ComputerStage5.test.ets` 增加窄屏宽度与触屏/电脑布局回归测试。

## 验证与证据

- ArkTS：**766/766 通过**，Failure 0 / Error 0 / Ignore 0。
- Release clean build、签名及安装包资源门禁通过。
- 手机 Pura 90（1320×2856，3.5 px/vp）及电脑 MateBook Pro（3120×2080，1.9 px/vp）模拟器，HarmonyOS 6.1.1 / API 24。
- 两端逐页检查 `ui` 的前 11 页：每页五项完整可见，候选实际边界等于未裁切边界，保持水平排列。
- 第 1、2 页往返、数字键 5 选“室”、第 10、11 页跨引擎批次往返，以及返回第 10 页后选“虱”均通过。
- 两端设备验收各 71 条操作检查通过；保存后的截图/布局证据复核 **146/146 通过**。触屏模式翻页按钮仍可见。
- 使用独立验收宿主 `com.example.shuangyuime.acceptance` 和模拟器按键注入。

[手机修复后第 2 页](../../../outputs/hardware-candidate-clipping-fix-20260915/phone/page-2.png)、[电脑第 2 页](../../../outputs/hardware-candidate-clipping-fix-20260915/computer/page-2.png)、[证据断言结果](../../../outputs/hardware-candidate-clipping-fix-20260915/verification.json)。

验收后已恢复手机自动识别、电脑虚拟键盘，两端固定候选栏、每页 5 项。原有自定义皮肤和词库保留，未清理学习记录；两端保留新版安装包。

本次验收针对已复现的默认五项、字号 17 场景；更长候选、更多候选或更大字号超出屏幕时，仍保留原有横向滚动及高亮自动显露行为。本次按用户要求未继续验收 QQ。

详细日志、截图、布局树、可重跑的设备验收脚本与证据复核脚本见 [本轮验收目录](https://github.com/JayusChi/shuangyu-ime-harmonyos/tree/f343416795303a3e844bcc80463191d122856c32/outputs/hardware-candidate-clipping-fix-20260915)。

## 安装包

两端覆盖安装 0.12.0，`SIGNATURE_RESET=false`，保留用户数据。

- [本次已验收的开发签名 Release 包](../../../outputs/hardware-candidate-clipping-fix-20260915/accepted-device-signed.hap)
- 大小：93,355,094 bytes
- SHA-256：`90B12F3BCDC7CEFB0A66586CE775FC8F7180F810C33969FAED732379CCC9E199`

初次测试发现保守宽度估算仍超限，调整窄屏内边距后完整重跑单测通过。电脑设备脚本初次把后台设置窗口的箭头误判为候选翻页控件，随后限定到候选窗口重新验收；这些初始日志保留在验收目录，没有作为产品通过证据。
