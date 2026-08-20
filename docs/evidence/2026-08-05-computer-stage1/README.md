# 电脑端整改阶段 1：2in1 能力报告与路线冻结

日期：2026-08-05  
结论：`COMPLETED`  
冻结路线：`路线 A（SOFT_KEYBOARD + FLAG_CANDIDATE）`

## 结论

HarmonyOS 6.1 / API 24 的 x86_64 `2in1` 模拟器在**没有创建固定 `FLAG_FIXED` 面板**的输入会话中，能够单独创建并完整操作第三方输入法的 `SOFT_KEYBOARD + FLAG_CANDIDATE` 面板。`setUiContent`、`resize`、`moveTo`、首次 `show`、`hide`、再次 `show`、鼠标点击和 `destroyPanel` 全部通过。

因此，2026-07-22 在 Pad 上“固定键盘已存在时创建第二个候选型软键盘返回错误码 1”的结果只能证明两个软键盘面板发生所有权竞争，不能再作为平台不支持候选面板的结论。电脑端后续正式实现冻结为路线 A；`STATUS_BAR` 仅保留为候选面板失败时的二级探针，本轮因路线 A 已通过而标记 `NOT_RUN`。

阶段 1 没有启用正式浮动候选路径。`FloatingCandidateCapabilityProbe` 仍保留正式路径关闭门禁，等待阶段 2 完成输入会话/面板生命周期解耦和唯一面板所有权后再启用。

## 环境

| 项目 | 结果 |
| --- | --- |
| HDC 目标 | `127.0.0.1:5559` |
| 设备类型 | `2in1` |
| 系统/API | HarmonyOS 6.1 / API 24 |
| 模型/ABI | emulator / x86_64 |
| 屏幕 | `3120×2080` |
| 字母键盘检测 | `alphabeticCount=1`，模拟器输入设备列表 6 项 |
| HAP | internalDebug，41,235,447 bytes |
| HAP SHA-256 | `50253da5e804a22f3608ecfadb3cfe502ee9bcb965b8dc283e65cb1dfc4b2375` |
| 真实 USB/蓝牙键盘 | `NOT_RUN`；模拟器键盘检测不得替代物理配件结论 |

机器环境快照见 [environment.json](device/environment.json)，汇总结论见 [summary.json](device/summary.json)。

## 隔离探针

internalDebug 在 `deviceInfo.deviceType === "2in1"` 时进入专用探针分支，不创建 `InputPanelController`，不初始化固定键盘，也不进入正式组合输入路径。Phone/Tablet 的 internalDebug 入口保持原状。

每次 `inputStart` 执行：

1. 记录设备类型、API 和实体键盘枚举，明确 `fixedPanelCreateCount=0`；
2. 单独创建 `SOFT_KEYBOARD + FLAG_CANDIDATE`；
3. 加载 `ComputerCandidateProbeRoot`；
4. 执行 `resize → moveTo → show → hide → show`；
5. 保持面板可见，等待鼠标点击；
6. 点击后注入字母键，验证输入法仍收到 DOWN/UP，宿主输入框仍获得文本；
7. 光标变化时再次 `moveTo`；
8. `inputStop` 时销毁面板。

若候选面板任一步失败，探针会先销毁残留面板，再独立创建 `STATUS_BAR` 并执行同一套生命周期。本轮候选面板通过，未触发该分支。

## 能力矩阵

| 能力 | ArkUI TextInput | ArkUI TextArea | 系统浏览器 | 结论 |
| --- | --- | --- | --- | --- |
| 固定面板未创建 | PASS | PASS | PASS | 日志无 `InputPanelController`，均为 `fixedPanelCreateCount=0` |
| 候选面板创建 | PASS | PASS | PASS | `createPanel panel=CANDIDATE result=PASS` |
| `setUiContent` | PASS | PASS | PASS | 独立探针页成功加载 |
| `resize` | PASS | PASS | PASS | `988×122 px` |
| `moveTo` | PASS | PASS | PASS | 首次和光标更新均成功 |
| `show/hide/show` | PASS | PASS | PASS | 无错误码、无固定键盘弹出 |
| 光标绝对坐标 | `651,438,35` 起 | `651,965,35` 起 | `968,386,40` 起 | 三种宿主均提供有效 `x/y/height` |
| 鼠标点击 | PASS | 未重复 | 未重复 | 候选 1 点击事件可达 |
| 点击后焦点保持 | PASS | 继承验证 | 继承验证 | 点击后 A/B 仍到达 IME，宿主保持 focused 且文本为 `ab` |
| 连续实体键事件 | PASS | PASS（C） | PASS（D） | DOWN/UP 均到达探针，宿主同时更新光标 |
| `destroyPanel` | PASS | PASS（切换时） | PASS（`inputStop`） | 无残留候选面板 |
| `STATUS_BAR` | `NOT_RUN` | `NOT_RUN` | `NOT_RUN` | 路线 A 已通过，无需触发失败回退 |

## 坐标与焦点证据

- `TextInput`：初始锚点 `x=651, y=438, height=35`；输入 A/B 后依次更新到 `x=666`、`x=684`。点击候选后首个 A 键日志含 `afterPanelClick=true`，宿主节点仍为 `focused=true` 且文本为 `ab`。
- `TextArea`：锚点 `x=651, y=965, height=35`；输入 C 后更新到 `x=664`。
- 系统浏览器地址栏：锚点 `x=968, y=386, height=40`；输入 D 后继续更新，面板移动到 `x=968, y=437`。

浏览器跨应用效果见 [browser_candidate.jpeg](device/browser_candidate.jpeg)，TextInput 的面板与焦点证据见 [textinput_candidate.jpeg](device/textinput_candidate.jpeg)。原始 UI 树和分宿主 hilog 均保存在 `device/`。

## 自动化与复现

策略单元测试覆盖：仅 2in1 启用探针、完整生命周期判定、A/B/C 路线优先级、清理完成前不冻结路线。ArkTS 全量单元测试通过。正式 default Release HAP 构建也通过，`debug=false`，37,832,144 bytes/SHA-256 `dcf16e73dd9acbe2da429d338c0e581e69977fa2e1327e61303ea01084b25ebe`；探针文件未进入主源码页面清单，正式 Phone/Tablet 路径未启用候选面板能力。

完整复现：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\accept-computer-stage1.ps1
```

脚本自动选择已连接的 2in1，也可用 `-Target 127.0.0.1:5559` 固定目标。它会构建 internalDebug、安装输入法和独立验收宿主、执行三种宿主矩阵、保存截图/UI 树/hilog，并以 `COMPUTER_STAGE1_RESULT=PASS route=A` 结束。已有构建和安装可加 `-SkipBuild -SkipInstall`。

## 路线冻结与阶段 2 约束

- 正式路线冻结为 A：电脑端候选窗使用 `SOFT_KEYBOARD + FLAG_CANDIDATE`，坐标来自宿主 `cursorContextChange` 的物理屏幕绝对坐标。
- 宿主未推送可靠锚点时不得沿用过期坐标；阶段 4 必须安全隐藏或走固定小候选条降级。
- 阶段 2 必须先建立 `HARDWARE_READY`，确保固定面板不创建或已销毁，并由统一所有权协调器保证任意时刻最多一个 `SOFT_KEYBOARD` 面板。
- 在阶段 2 完成前，正式 `sdkSupportsPanel` 仍保持关闭，避免现有固定键盘路径再次制造两个软键盘面板竞争。
- 真实 USB/蓝牙键盘、ARM64 2in1、窗口移动/缩放后的全量锚点刷新继续为后续阶段 `NOT_RUN`，不由本次模拟器结果代替。
