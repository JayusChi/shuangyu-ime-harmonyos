# Stage 3.8 最终验收记录

日期：2026-07-22

## 验收结论

阶段 3.8 按能力验证后的路线 C 验收完成。HarmonyOS API 24 虽声明
`PanelFlag.FLAG_CANDIDATE`，但目标 Pad 模拟器中的第三方输入法在有效输入会话和
有效光标坐标下创建候选面板仍返回错误码 `1`。工程没有用 Popup 或 Overlay 冒充
跨应用浮动窗，而是采用可交付降级：手机顶部横向候选栏，Pad 输入法内部固定右侧
候选条；设置中的“跟随光标（实验）”真实禁用并解释原因。

## 修正与合同

- `FloatingCandidateCapabilityProbe` 只有在真实生命周期验证通过时才报告面板可用；
  当前平台固定为不可用，避免每次组合重复触发已知失败。
- `KeyboardRootStage3` 在 Pad `AUTO`（以及遗留不可用 `FLOATING` 值）下选择固定右侧
  候选条；手机与显式 `BAR` 保持顶部栏。
- `PadSideCandidateStrip` 与顶部栏读取同一 `InputSessionStore.candidates/rawInput`，
  点击复用 `KeyboardController.commitCandidate(index)`，没有第二套查询、排序或组合态。
- 侧栏显示阶段 4.1 的原始编码下划线，并复用阶段 4.2 的候选文字展示合同。
- 设置选项同时具有 `enabled=false` 语义和禁用透明度，不只是视觉置灰。

## 验证结果

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| 光标绝对坐标回调 | PASS | `device/stage38_floating_live2_pass.log/json` |
| 候选面板真实创建 | 系统拒绝（错误码 1），路线 C 判定成立 | 同上 |
| Pad 深色固定侧栏 | PASS | `device/stage38_side_dark_candidates.png/json` |
| 候选点击提交并清除侧栏 | PASS | `device/stage38_side_dark_committed.png/json` |
| 设置说明与禁用语义 | PASS | `device/stage38_settings_disabled_final.png/json` |
| 手机顶部候选回归 | PASS | `../stage10/device/stage10_normal_candidates.png/json` |
| HDC 外部按键路由 | PASS | `device/stage38_floating_live2_pass.log` |
| Stage 3.8 自动化合同 | PASS | 2026-07-22 ArkTS 全量 284/284 |

## 平台边界

设置 Ability 与 `:inputMethod` Extension 使用隔离存储沙箱。运行中的两个进程通过
受控 CommonEvent 同步并各自在本进程持久化；无 AppGroup/Data Group 配置时，不能
保证“输入法服务从未启动、只在设置进程改非默认值、随后冷启动服务”的跨沙箱恢复。
默认 `AUTO` 路线不受影响。真实 USB/蓝牙键盘、ARM64 物理真机、第三方浏览器和 Pad
分屏未执行，不计入本阶段路线 C 的模拟器验收结论。

完整能力分析见 `docs/STAGE_3_8_FLOATING_CANDIDATE_CAPABILITY.md`。
