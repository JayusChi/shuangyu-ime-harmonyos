# 电脑端整改阶段 2 验收报告

日期：2026-08-05  
结论：`COMPLETED / HARDWARE_READY`  
阶段范围：输入会话与固定/候选面板生命周期解耦，不包含阶段 3 完整实体按键合同和阶段 4 正式候选窗。

## 实现结论

- 有效展示模式独立为 `TOUCH / HARDWARE`，持久化决策入口预留为 `AUTO / TOUCH / HARDWARE`。
- 当前 AUTO 只把 `deviceType=2in1` 解析为 `HARDWARE`；Phone、Tablet 保持 `TOUCH`。
- 2in1 `inputStart` 先建立输入会话和编辑器连接，再进入 `HARDWARE_READY`，不创建固定软键盘。
- 固定面板隐藏只更新面板可见性。会清预览、重置引擎和清组合的完整 `keyboardHide` 仅在触屏模式执行；实体模式的系统 show/hide 不改变组合与会话。
- `FIXED_KEYBOARD` 与 `CANDIDATE_WINDOW` 共用一个串行所有权协调器。切换所有者时先销毁并撤销旧面板，任意时刻最多一个 `SOFT_KEYBOARD` 面板。
- internalDebug 的阶段 1 隔离探针已退出自动激活，2in1 使用正式生命周期；候选窗正式门禁仍保持关闭。

## 自动化验证

| 项目 | 结果 |
| --- | --- |
| ArkTS 全量单元测试 | PASS |
| 展示模式 AUTO/显式决策 | PASS |
| HARDWARE inputStart 固定面板零创建 | PASS |
| HARDWARE keyboardHide 不触发破坏性清理 | PASS |
| TOUCH → HARDWARE 释放既有固定面板 | PASS |
| FIXED/CANDIDATE 串行所有权切换 | PASS |
| internalDebug HAP 构建 | PASS |
| default unsigned Release HAP 构建 | PASS |
| Release HAP 内容门禁 | PASS |

ArkTS 入口为 `entry/src/test/ComputerStage2Lifecycle.test.ets`，并已加入全量 `List.test.ets`。设备入口为：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\accept-computer-stage2.ps1
```

## 设备矩阵

三台设备均为 HarmonyOS 6.1 / API 24 / x86_64 模拟器，使用同一 internalDebug HAP 和独立宿主 `com.example.shuangyuime.acceptance`。

| 设备 | 分辨率/场景 | 有效状态 | 会话/编辑器 | 固定键盘 | 结果 |
| --- | --- | --- | --- | --- | --- |
| Phone | ArkUI TextInput | `TOUCH_READY` | active/connected | 可见 | PASS |
| Tablet | ArkUI TextInput | `TOUCH_READY` | active/connected | 可见 | PASS |
| 2in1 | ArkUI TextInput、TextArea、系统浏览器连续切换 | `HARDWARE_READY` | `true/true` | 未创建、未显示 | PASS |

2in1 三次正式 `inputStart` 均记录：

```text
mode=HARDWARE, state=HARDWARE_READY, sessionActive=true, editorConnected=true, keyboardVisible=false
```

同一日志还记录系统 `keyboardShow/keyboardHide` 在 `HARDWARE_READY` 被忽略，以及 `keyboard panel hidden; input session preserved`。日志中不存在 `keyboard panel created` 或 `keyboard panel visible`。Phone/Tablet 日志则同时包含 `TOUCH_READY` 和 `keyboard panel visible`。

三端阶段日志的 `fatal / panic / crash / ENGINE_INTERNAL_ERROR` 扫描为空。

原始环境、UI 树、截图、日志和机器可读汇总位于 `device/`：

- `device/summary.json`
- `device/phone/`
- `device/tablet/`
- `device/2in1/`

## 构建产物

| 产物 | 字节数 | SHA-256 |
| --- | ---: | --- |
| internalDebug unsigned HAP | 41,228,911 | `f14b024ff5cfdf56d03cc949f5f87ad8aa0271e1fc41cdd6e2e52e50120334cb` |
| default unsigned Release HAP | 37,842,068 | `21ccc491d7ec632536c41487bd05d95d23e8e11d6465c6cf390bdaf7f2cac591` |

Release 内容门禁输出为 `RELEASE_HAP_VERIFY_RESULT=PASS`。

## 未执行与阶段边界

- 真实 USB/蓝牙键盘：`NOT_RUN`；模拟器的字母键盘枚举不能替代真实硬件结论。
- ARM64 2in1：`NOT_RUN`。
- signed Release 电脑端验收：`NOT_RUN`。
- Esc、方向键、PageUp/PageDown 及阶段 3 完整实体按键消费合同：未在本阶段启用。
- 跟随光标正式候选窗和鼠标选词：留到阶段 4；本阶段只完成候选面板所有权基础。
