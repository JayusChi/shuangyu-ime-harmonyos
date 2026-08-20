# 电脑端整改阶段 4 验收报告

日期：2026-08-05  
结论：`COMPLETED / FLOATING_CANDIDATE_CLOSED_LOOP`

## 实现结论

- 2in1 的 `HARDWARE_READY` 正式启用路线 A：`SOFT_KEYBOARD + FLAG_CANDIDATE`。仅中文、有组合且候选非空时显示；固定 `FLAG_FIXED` 键盘保持缺席。
- 候选窗显示组合编码、编号候选、选中状态、分页状态和精准匹配后缀；内容变化会在 `280～560 vp` 范围内重算宽度。
- 光标锚点采用下方优先、上方回退和安全区夹紧。光标、候选内容、宿主窗口移动或缩放后重新定位；配置变化先使旧锚点失效，没有新锚点时隐藏。
- 鼠标候选提交复用正式 `commitCandidate(index)` 链路，并防止重复点击；数字键提交、Esc、清空、会话切换和应用切换均经过同一状态/隐藏边界，候选窗不抢宿主焦点。
- Phone/Tablet 继续走 `TOUCH_READY` 和既有固定键盘/候选栏，不启用电脑端浮动候选窗。

## 自动验证

| 门禁 | 结果 |
| --- | --- |
| ArkTS 全量单元测试 | `378/378 PASS` |
| default unsigned Release 构建与内容门禁 | `PASS` |
| internalDebug 构建 | `PASS` |
| Phone / Tablet / 2in1 展示模式矩阵 | `PASS / PASS / PASS` |
| 2in1 ArkUI 候选窗闭环 | `PASS` |
| 2in1 系统浏览器本地 HTTP 输入框闭环 | `PASS` |
| 鼠标/数字键同候选、Esc、焦点保持 | `PASS` |
| 宿主窗口移动、缩放、应用切换清理 | `PASS` |
| 固定键盘缺席及 fatal/fallback 扫描 | `PASS` |

设备矩阵使用 HarmonyOS 6.1 / API 24 / x86_64 模拟器：Phone 与 Tablet 为 `TOUCH`，2in1 为 `HARDWARE`。浏览器用例通过 `hdc rport` 访问仓库内的 `tools/ime-acceptance-client/stage4-browser-input.html`，不依赖外网。模拟器 `uitest keyEvent` 在浏览器中会额外回显拉丁原始键，因此门禁先验证空字段，再精确断言中文候选仅出现一次、位于文本末尾且候选窗关闭；ArkUI 宿主的严格文本等值断言为“你”。

系统可能跨安装复用输入法扩展进程，因此一次性 `panel created/content ready` 日志在重复运行中记录为 `REUSED_SYSTEM_PROCESS`；可重复硬门禁以正式路线决策、候选 UI、`shown/hidden`、提交、焦点及固定键盘缺席为准。自动测试另覆盖 create/content/resize/move/show/hide 与失败回退生命周期。

## 产物

- `entry-release-unsigned.hap`：37,857,196 bytes，SHA-256 `7f8ce1bdd168033640b15a8eea8b9f12ea32707a4bcc5fd279e840198b89d7eb`
- `entry-debug-unsigned.hap`：41,270,408 bytes，SHA-256 `fbb29fdba9d01add815da1fb7d0352de6db7dbc4b2312c410469cb1151021d06`

## 复现入口

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\accept-computer-stage4.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\accept-computer-stage2.ps1 -EvidenceDir docs\evidence\2026-08-05-computer-stage4\device-matrix -SkipBuild
```

2in1 原始布局、截图、日志、环境和汇总位于 `device/`；三设备矩阵位于 `device-matrix/`。

## 未执行范围

- 真实 USB/蓝牙实体键盘：`NOT_RUN`
- ARM64 2in1：`NOT_RUN`
- signed Release 电脑端专项：`NOT_RUN`

以上项目进入阶段 5，不影响阶段 4 在 x86_64 模拟器、独立 ArkUI 宿主和系统浏览器范围内关闭。
