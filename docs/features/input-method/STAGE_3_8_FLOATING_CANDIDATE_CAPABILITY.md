# Stage 3.8 Floating Candidate Capability Assessment

更新时间：2026-08-05  
结论状态：`HISTORICAL / SUPERSEDED`

> 2026-08-05 电脑端整改阶段 1 已在 API 24 `2in1` 模拟器中排除固定面板竞争：固定 `FLAG_FIXED` 面板创建数为 0 时，`SOFT_KEYBOARD + FLAG_CANDIDATE` 的创建、内容加载、缩放、移动、显示、隐藏、鼠标点击、焦点保持和销毁均通过，正式路线已改为路线 A。本文第六节的路线 C 是 2026-07-22“固定面板已存在”条件下的历史结论，不再代表平台能力。当前报告见 `docs/evidence/2026-08-05-computer-stage1/README.md`。

## 目的

在动手实现浮动候选窗前，先独立确认 HarmonyOS 输入法 Extension 是否能
可靠地获得宿主编辑框的光标屏幕坐标、能否创建跨应用可见且不抢占宿主
焦点的候选窗口。本文档记录 SDK 接口证据、可验证结论和路线选择依据，
避免以“伪浮动窗”掩盖能力限制。

## 一、SDK 目标与实际调查

| 项目 | 值 | 证据 |
| --- | --- | --- |
| compatibleSdkVersion | `6.1.1(24)` | `build-profile.json5` |
| targetSdkVersion     | `6.1.1(24)` | `build-profile.json5` |
| Extension 类型 | `InputMethodExtensionAbility` | `entry/src/main/ets/inputmethod/Stage0InputMethodAbility.ets` |
| 已持有 API | `inputMethodEngine.InputMethodAbility`, `KeyboardController`, `InputClient` | `Stage0InputMethodAbility.ets` |
| 现有面板 | 通过 `imeAbility.createPanel(context, {type: SOFT_KEYBOARD, flag: FLG_FIXED})` 创建 | `entry/src/main/ets/application/InputPanelController.ets` |

SDK 文件路径以本机安装的 DevEco Studio 为准：
`C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/api/`

## 二、光标矩形能力

### 2.1 `cursorContextChange` 事件

```
InputMethodAbility.on(
  'cursorContextChange',
  callback: (x: number, y: number, height: number) => void
): void;
```

- 来源：`@ohos.inputMethodEngine.d.ts` L1577~L1582
- since 8，位于 `SystemCapability.MiscServices.InputMethodFramework`
- 参数：光标锚点 `(x, y)` 与光标高度 `height`
- 触发场景：宿主编辑框主动调用 `inputMethod.updateCursor(cursorInfo)`
  时由框架转发（`@ohos.inputMethod.d.ts` L798~L828 `updateCursor`）
- 坐标语义（依据 `CursorInfo` 定义
  `@ohos.inputMethod.d.ts` L1833~L1866）：
  > "left/top point of the cursor info and must be absolute coordinate
  > of the physical screen"
  即物理屏幕绝对坐标，单位 px

### 2.2 光标事件的边界

- 事件是否触发**完全取决于宿主编辑框**是否调用 `updateCursor`。
  ArkUI `TextInput` / `TextArea` / `RichEditor` 会自动推送，
  三方 Web 或自绘编辑器不保证。
- 事件返回 `height` 但不返回光标宽度；也没有 `width`。位置算法只能把
  光标视为竖线，用 `height` 作为垂直参考。
- 事件不区分插入点与选区，选区变化由独立
  `on('selectionChange', (oldBegin, oldEnd, newBegin, newEnd))` 提供。
- 该事件仅在输入会话激活时触发；`inputStop` 之后不再回调。

结论：**可以获得光标屏幕矩形近似值（点+高度），仅当宿主编辑框主动推送**。
项目不能对所有第三方应用一致假定可用。

## 三、跨应用附属窗口能力

### 3.1 候选面板类型

```
inputMethodEngine.PanelFlag.FLAG_CANDIDATE   // since 15
inputMethodEngine.PanelType.SOFT_KEYBOARD
```

`@ohos.inputMethodEngine.d.ts` L2385~L2395 明确说明：
> "the soft keyboard is a candidate window which will show the possible
> characters when user types a input code. Panel with candidate style
> will not be automatically shown or hidden by input method service.
> Input method application developers are supposed to control the panel
> status on their own."

该声明说明 SDK 表面上提供了候选面板类型，但不能单独证明第三方输入法在
目标系统上具备创建权限。第六节的历史运行验证曾在固定软键盘已经存在时收到
错误码 `1`；2026-08-05 的隔离验证证明该错误来自两个软键盘面板竞争，不能用于
否定候选面板能力。

### 3.2 `moveTo(x, y)`

`@ohos.inputMethodEngine.d.ts` L1859~L1872：
- since 10
- 对 `SOFT_KEYBOARD + FLG_FIXED` 不可用，但对 `FLAG_CANDIDATE` 可用
- 参数为面板左上角坐标；文档未显式说明坐标系单位，
  按同类 window API 惯例为像素

### 3.3 生命周期

- 由 IME Extension 创建，与 `imeAbility` 绑定，Extension 销毁前必须
  显式 `destroyPanel`；候选面板不受 `inputStop` 自动收起
- 需在 `inputStart` 之后创建以确保有会话上下文
- 不需要独立系统悬浮窗权限；沿用输入法 Extension 权限模型

## 四、位置更新事件

| 事件 | since | 触发条件 |
| --- | --- | --- |
| `cursorContextChange` | 8 | 宿主 `updateCursor` |
| `selectionChange` | 8 | 宿主 `changeSelection` / `updateCursor(selection)` |
| `textChange` | 8 | 宿主 `sendPrivateCommand` 或键入 |
| `editorAttributeChanged` | 10 | `inputPattern`/`enterKeyType` 变化 |
| `inputStart` / `inputStop` | 8 | 会话开始/结束（`Stage0InputMethodAbility` 已订阅） |
| `keyboardShow` / `keyboardHide` | 8 | 已订阅 |

宿主窗口移动、Pad 分屏比例变化没有独立事件；宿主编辑框会在窗口重
布局后重新调用 `updateCursor`，此时 `cursorContextChange` 会再次触发。
若宿主未再推送，本文档明确此为限制。

## 五、能力矩阵与限制

| 项目 | 结论 |
| --- | --- |
| 光标屏幕矩形（点+高度） | 支持（依赖宿主 `updateCursor`） |
| 光标宽度 | 不提供 |
| 坐标系 | 物理屏幕绝对坐标（px） |
| 附属候选窗口 | API 24 `2in1` 隔离验证支持；固定软键盘同时存在时会发生面板竞争 |
| 输入法生命周期管理 | 面板由 `imeAbility.createPanel/destroyPanel` 管理 |
| 移动位置 | `Panel.moveTo(x, y)` 支持（since 10） |
| 输入焦点抢占 | 不抢焦点；鼠标点击候选后实体键仍进入 IME，宿主保持 focused |
| 分屏 | SDK 未提供窗口边界，需要真机与多种应用验证 |
| 外接物理键盘 | 模拟器检测到 1 个字母键盘；真实 USB/蓝牙键盘仍需真机验证 |
| 最低支持 API | `FLAG_CANDIDATE` 自 API 15 声明；工程 API 24 的隔离生命周期已通过 |

## 六、2026-07-22 历史运行验证与当时路线

2026-07-22 在 HarmonyOS 6.1、API 24、2880×1920 x86_64 Pad 模拟器上完成了
真实输入会话实验，结论覆盖了 SDK 静态声明无法证明的关键一环：

1. `KeyboardDelegate.on('cursorContextChange')` 会收到宿主 ArkUI 文本框提供的
   物理屏幕绝对坐标，日志中已观察到有效的 `x/y/height` 连续更新；
2. 外部按键注入会进入 `KeyboardDelegate.on('keyEvent')`，再复用正式
   `KeyboardController` 输入路径；
3. 在有效输入会话、有效光标锚点和显式浮动决策全部满足后，第三方输入法调用
   `createPanel(SOFT_KEYBOARD + FLAG_CANDIDATE)` 仍被系统拒绝，返回错误码 `1`；
4. 创建失败没有清空组合、候选或输入会话，现有顶部候选路径继续可用。

关键原始证据：

- `docs/evidence/stage3_8/device/stage38_floating_live2_pass.log`
- `docs/evidence/stage3_8/device/stage38_floating_live2_pass.json`
- `docs/evidence/stage3_8/device/stage38_floating_live2_pass.png`

因此当时选择了路线 C。该判断已被 2026-08-05 的无固定面板隔离实验推翻；
保留本节仅用于解释历史代码和证据，不能再用于后续电脑端路线选择。

### 6.1 当时的路线 C 实现

1. `FloatingCandidateCapabilityProbe` 的面板能力增加“实际生命周期验证”门禁；
   当前目标平台验证失败，`sdkSupportsPanel=false`，运行时不再重复尝试创建面板。
2. 设置页保留“自动 / 键盘顶部 / 跟随光标（实验）”结构，但“跟随光标”具有
   真实 `enabled=false` 语义和 0.45 视觉透明度，并显示明确的路线 C 说明。
3. 手机继续使用原顶部横向候选栏。
4. Pad 的 `AUTO` 使用输入法窗口内部固定右侧候选条；显式 `BAR` 仍使用顶部栏。
   旧版本遗留的 `FLOATING` 值在能力不可用时安全按 `AUTO` 展示和降级。
5. 侧栏与顶部栏共同读取 `InputSessionStore.candidates/rawInput`，没有复制查询、
   分页或组合状态；点击继续调用 `KeyboardController.commitCandidate(index)`。
6. 侧栏复用阶段 4.1/4.2 展示合同：实时原始编码带下划线，普通候选和无障碍
   文案都不包含 `candidate.reading`。

### 6.2 当时已验证结果（历史）

| 验收项 | 结果 | 证据 |
| --- | --- | --- |
| 光标绝对坐标事件 | PASS（ArkUI 宿主） | `stage38_floating_live2_pass.log` |
| 候选 Panel 创建 | FAIL，系统错误码 1；触发路线 C | 同上 |
| Pad 固定侧栏 | PASS（深色实机截图；浅色由纯展示测试及同组件回归覆盖） | `docs/evidence/stage3_8/device/stage38_side_dark_candidates.png` |
| Pad 深色固定侧栏 | PASS | `docs/evidence/stage3_8/device/stage38_side_dark_candidates.png` |
| 侧栏候选点击提交/收起 | PASS | `stage38_side_dark_committed.json/png` |
| 设置项说明与禁用语义 | PASS | `stage38_settings_disabled_final.json/png` |
| 手机浅色顶部候选栏 | PASS | `docs/evidence/stage10/device/stage10_normal_candidates.png` |
| 物理按键路由 | PASS（HDC keyEvent 注入） | `stage38_floating_live2_pass.log` |
| 真实 USB/蓝牙键盘 | 未执行 | 当前无物理配件 |
| ARM64 真机/三方浏览器/Pad 分屏 | 未执行 | 当前仅两台 x86_64 模拟器 |

## 七、设置跨进程限制

HarmonyOS 将 `EntryAbility` 与 `:inputMethod` Extension 置于隔离数据沙箱。项目
使用受控 CommonEvent 在两个运行中进程之间同步设置；各进程也分别持久化收到的
值。实测 XML Preferences、`distributedFilesDir`、分布式 KV 和 API 24 的 GSKV
在该输入法隔离沙箱之间都不能作为无 AppGroup 的冷启动共享存储。

因此：历史默认 `AUTO` 路线在任何冷启动都安全成立；设置进程与输入法进程同时存活时，
模式切换立即同步并在输入法自己的后续重启中保留。若安装后从未启动过输入法服务、
只在独立设置进程修改模式，然后系统在广播送达前销毁进程，目标模拟器无法跨沙箱
恢复该非默认值。完整消除此平台限制需要发布侧 AppGroup/Data Group ID；当前工程
没有该外部配置，不能伪造。该限制不影响历史路线 C、正常候选、提交或输入安全。

## 八、2026-08-05 最终修订

电脑端整改阶段 1 已冻结路线 A。正式实现必须先由阶段 2 解耦输入会话和面板生命周期，使电脑端不创建固定软键盘，再由阶段 4 启用候选面板；在此之前，主线运行时门禁仍保持关闭。新的能力矩阵、复现脚本、截图和结构化日志统一以 `docs/evidence/2026-08-05-computer-stage1/README.md` 为准。
