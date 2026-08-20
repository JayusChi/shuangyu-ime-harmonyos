# 移动端候选位置阶段 1 验收报告

验证日期：2026-08-06  
结论：`COMPLETED / TOUCH_CURSOR_CANDIDATE_CLOSED_LOOP_WITH_HARDWARE_LIMITATIONS`

## 实现结论

- 设置页“候选窗位置”对 Phone/Tablet 提供 `候选栏 / 输入框下方` 两项。已有 `AUTO` 持久化值在触屏端按候选栏处理并在 UI 中选中“候选栏”，因此升级和恢复默认设置不会无意改变移动端布局。
- `TOUCH + FLOATING` 使用 `PanelType.STATUS_BAR` 创建独立候选窗。该面板不参与 `SOFT_KEYBOARD` 唯一所有权队列，可与底部 `FLG_FIXED` 键盘同时存在；`HARDWARE` 仍使用电脑端已验收的 `SOFT_KEYBOARD + FLAG_CANDIDATE`。
- 位置继续使用宿主 `cursorContextChange` 的物理屏幕绝对坐标，下方优先、上方回退、左右安全区夹紧；触屏模式额外把固定键盘高度计入底部安全区，候选不会落到键盘背后。
- 窗口复用 `FloatingCandidateRoot`、实际可见候选过滤、字号/主题、分页状态、精准匹配后缀和 `commitCandidate(index)`。窗口显示成功后才通过共享 Store 隐藏候选栏内容；失败、无锚点或能力不足时保留候选栏。
- 旧 Pad 侧面候选条不再由 `FLOATING` 触发，避免“输入框下方”设置同时产生侧栏。没有新增设置字段、权限、Native ABI、词库、召回或排序变化。

## 自动验证

| 项目 | 结果 |
| --- | --- |
| ArkTS 全量单元测试 | `383/383 PASS` |
| 触屏显式 FLOATING 的 Phone/Pad policy | `PASS` |
| TOUCH 使用 STATUS_BAR、切回 BAR 隐藏、销毁清理 | `PASS` |
| HARDWARE 继续使用 FLAG_CANDIDATE | `PASS` |
| internalDebug HAP | `PASS` |
| unsigned Release HAP | `PASS` |

产物：

- `entry-debug-unsigned.hap`：41,262,403 bytes，SHA-256 `f06ea913c00f6d1ad2d77f207dadc80630da0c3cf58ccca72d4e22b8e9f2c75d`
- `entry-release-unsigned.hap`：37,852,688 bytes，SHA-256 `aedbe6803ed16b8fbcea171eaea5807694a2c3b86a22c36d74d9c6e969ea8ccf`

## Phone 模拟器验证

环境：HarmonyOS 6.1 / API 24 / x86_64 / `1320×2856`，internalDebug，17 键布局。

- 设置页成功选择“输入框下方”；运行日志记录 `inputMode=TOUCH, preference=floating, effective=floating, formFactor=phone`。
- 正式控制器创建 `kind=STATUS_BAR`，候选根为 `[168,868][1135,1064]`，宿主光标锚点约为 `x=168, y=782, height=65`，定位结果为 `placement=below`。
- 固定键盘根同时保持 `[0,1670][1320,2699]`；候选窗与键盘在同一 UI 树中并存。
- 点击首选后普通文本框得到 `符号★000046`，候选根数量由 1 变为 0，提交和收起闭环 PASS。
- 截图：`artifacts/touch-candidate/phone_touch_candidate.png`，293,089 bytes，SHA-256 `b1e2f09f62eda3badde059cb980fd78b9f1657651e0dec867f19f56c77062d29`。

## Tablet 模拟器验证

环境：HarmonyOS 6.1 / API 24 / x86_64 / `2880×1920`，internalDebug，26 键布局。

- 设置页成功选择“输入框下方”；运行日志记录 `inputMode=TOUCH, preference=floating, effective=floating, formFactor=tablet, physical=false`。
- 正式控制器创建 `kind=STATUS_BAR`，候选根为 `[96,464][1216,576]`，光标锚点约为 `x=96, y=415, height=37`，定位结果为 `placement=below`。
- 固定键盘根同时保持 `[0,868][2880,1920]`；历史 Pad 侧面条未出现。
- 点击首选后普通文本框得到 `符号★000046`，候选根数量由 1 变为 0，提交和收起闭环 PASS。
- 截图：`artifacts/touch-candidate/tablet_touch_candidate.png`，248,668 bytes，SHA-256 `f947bf4d68637c0baafb2f15670de51f651b3bc358085d2921ae9221444df983`。

internalDebug 使用合成码表，以上候选文字仅用于稳定验证 UI、定位和提交链，不代表 Release 正式词库候选内容。

## 回退与未执行范围

- 宿主未发送有效 `cursorContextChange`、会话不允许候选、SDK 门禁不满足或面板创建/显示失败时，不创建/不显示输入框下方窗口，顶部候选栏继续可用。
- 光标下方空间不足时按既有位置算法改放上方；配置变化先废弃旧锚点，等待宿主新锚点后再显示。
- ARM64 Phone/Tablet 实体设备、第三方应用输入框矩阵、浏览器/Web 自绘输入框、旋转、分屏、悬浮窗、多显示器和无障碍专项：`NOT_RUN`。
- 2in1 本阶段设备专项重跑：`NOT_RUN`；既有 HARDWARE 路线由全量单元测试和本轮 Debug/Release 编译覆盖，不将其表述为本阶段设备 PASS。
