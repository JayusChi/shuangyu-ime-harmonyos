# 电脑端整改阶段 3 验收报告

日期：2026-08-05  
结论：`COMPLETED / HARDWARE_INPUT_CLOSED_LOOP`  
阶段范围：实体键盘输入、编辑、选词、取消和分页合同；不包含阶段 4 正式跟随光标候选窗。

## 正式按键合同

| 状态 | 按键 | 行为/消费 |
| --- | --- | --- |
| 中文、无组合 | A-Z | 开始组合并消费 |
| 中文、无组合 | 数字、空格、回车、退格、Esc、方向键、PageUp/PageDown、`'` | 交还宿主 |
| 中文、有组合 | A-Z、退格、`'` | 继续组合、删除、插入分隔并消费 |
| 中文、有组合 | 1-9 | 选择当前页对应候选并消费；空槽不会把数字泄漏到宿主 |
| 中文、有组合 | 左/上、右/下 | 当前页向前/向后移动选中项，页首/页尾夹紧 |
| 中文、有组合 | PageUp/PageDown | 上一页/下一页，使用既有 Native 分页结果 |
| 中文、有组合 | Space/Enter | 提交当前选中候选；Enter 继续遵守编辑器动作合同 |
| 中文、有组合 | Esc | 清除预览、重置组合并隐藏候选状态，不提交、不学习 |
| 任意状态 | Ctrl/Alt/Logo 组合 | 交还宿主，不触发输入法动作 |
| 非中文或禁用候选编辑器 | 所有实体键 | 交还宿主 |

已消费的 DOWN 会记录到会话内追踪器，对应 UP 也由输入法消费，避免宿主收到半个按键事件；重复 DOWN 保持串行且只记录一个待释放键。驱动不给 `unicodeChar` 时，字母、主键区数字、小键盘数字、空格、回车、退格和分隔符均可由标准 KeyCode 恢复。

## 实现结论

- `PhysicalKeyboardRouting` 补齐 Esc、四方向、PageUp/PageDown、小键盘数字和无 Unicode 回退，并以显式 `compositionPending` 覆盖快速 `N → I → Space` 在前序异步动作尚未落状态时的消费竞态。
- `InputMethodLifecycleDispatcher` 对所有已消费按键记录 DOWN/UP 对，并以独立 generation 隔离输入框快速切换时的旧异步完成；新会话不会被旧会话的完成回调误改 pending 状态。
- `InputSessionStore.highlightedIndex` 现在可由实体方向键在当前页内移动；`KeyboardController` 将方向、分页、取消、空格和回车全部放入既有 `SerialActionExecutor`，快速连续输入保持原事件顺序。
- Esc 通过 `InputSessionController.cancelComposition()` 清理宿主预览、Native 组合和 Store 状态，不走键盘隐藏生命周期，也不结束 `HARDWARE_READY` 会话。
- 空格和回车使用当前 `highlightedIndex`，数字键仍提交明确索引；提交继续复用原候选确认、用户学习、用户词库和失败恢复链路。
- 密码编辑器仍由编辑器策略禁用中文、候选与学习；目标 2in1 系统对安全编辑器没有派发 IME `inputStart`，现场由宿主直接收到三个字符，UI 计数为 `PASSWORD_LENGTH=3`。

## 自动化验证

新增 `entry/src/test/ComputerStage3PhysicalKeyboard.test.ets` 并加入全量 `List.test.ets`，覆盖：

- 无组合/有组合消费边界；
- Esc、四方向、PageUp/PageDown 和 1-9；
- KeyCode 无 Unicode 与小键盘数字；
- Ctrl/Alt/Logo 快捷键；
- DOWN/UP 成对、重复 DOWN、pending 快速输入；
- 当前页选中夹紧、方向后空格提交选中项；
- 固定键盘不可见时 PageDown/PageUp；
- Esc 不提交候选；
- 英文、密码和禁用候选编辑器直通。

ArkTS 全量单元测试结果为 `BUILD SUCCESSFUL`。internalDebug 与 default Release ArkTS/HAP 构建均 PASS；设备闭环使用正式 default Release，因为 internalDebug 保留历史 11.6.7 fixture 覆盖，不代表正式词库输入。

## 2in1 设备闭环

设备为 HarmonyOS 6.1 / API 24 / x86_64 `2in1` 模拟器，分辨率日志为 `3120×2080`，使用独立宿主 `com.example.shuangyuime.acceptance` 和系统浏览器。

| 场景 | 结果 |
| --- | --- |
| 聊天 TextInput：`ni + Space` | 上屏“你”，PASS |
| URL TextInput：`a b Space` | 宿主得到 `ab `，PASS |
| 搜索 TextInput：`ui + Right + Space` | 提交索引 1“室”，PASS |
| TextArea：`ni + Esc` | 组合清空且无上屏，PASS |
| TextArea 无组合 Space/Backspace | 宿主插入后删除，PASS |
| PageDown/PageUp | 正式路由均到达；完整分页成功由 ArkTS Native 页测试覆盖，PASS |
| 快速连续 10 轮 `ni + Space` | 恰好上屏 10 字，无重复/丢键，PASS |
| Password | 宿主字符计数 3，未进入中文候选链路，PASS |
| 系统浏览器 URL | 实体 A/B 直接输入且焦点保持，PASS |
| 面板/会话 | 始终 `HARDWARE_READY`，固定面板零创建/零显示，PASS |
| fatal/panic/crash/ENGINE_INTERNAL_ERROR | 扫描为空，PASS |

一键入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\accept-computer-stage3.ps1
```

原始环境、UI 树、截图、日志和机器汇总位于 `device/`。

## 构建产物

| 产物 | 字节数 | SHA-256 | 结论 |
| --- | ---: | --- | --- |
| internalDebug HAP | 41,253,823 | `507fe89b77d1d48c276cc375d98b7b7726f788d3970f816d624f80ba7a721e31` | 编译 PASS；不用于正式输入闭环 |
| default Release HAP | 37,850,616 | `87302bf1d071e65e4e5872ebd63a09b62e26fc42ddeb08213840ed04b2549e17` | 构建、设备安装、内容门禁 PASS |

Release 内容门禁输出为 `RELEASE_HAP_VERIFY_RESULT=PASS`。

## 未执行与阶段边界

- 真实 USB/蓝牙键盘：`NOT_RUN`；`uitest keyEvent` 和模拟器字母键盘不能替代真实硬件结论。
- ARM64 2in1：`NOT_RUN`。
- signed Release 电脑端专项验收：`NOT_RUN`；本报告不把文件名为 unsigned 的 default Release 产物描述为 signed Release。
- Phone/Tablet 设备专项重跑：本阶段 `NOT_RUN`；触屏路径由全量 ArkTS 回归和阶段 2 三端矩阵继续约束。
- 正式 `FLAG_CANDIDATE` 候选窗、鼠标选词和跟随光标定位仍属于阶段 4，本阶段没有提前启用。
