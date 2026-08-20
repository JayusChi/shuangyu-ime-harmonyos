# ADR 0010：ArkTS 编辑器上下文与统一键盘模式状态

- 状态：Accepted
- 日期：2026-07-10

## 背景

阶段 9 的活动键盘只维护中英文占位模式，`inputStart` 未读取编辑框属性，回车固定发送换行。阶段 10 需要覆盖普通文本、密码、数字、电话、邮箱、URL、搜索、多行和未知输入框，同时保持 `ArkTS -> C++ -> Rust` 边界。

本机 API 24 SDK 的真实声明确认：

- `inputMethodEngine.InputClient.getEditorAttributeSync()` 和异步版本返回 `EditorAttribute`；
- `EditorAttribute` 提供 `inputPattern` 与 `enterKeyType`；
- API 20 起提供 `placeholder`，API 22 起提供 namespaced `extraConfig.customSettings`；
- 编辑属性变化通过 `inputMethodEngine.getKeyboardDelegate().on('editorAttributeChanged', ...)` 订阅；
- SDK 提供文本、数字、电话、邮箱、URI、密码、锁屏密码、数字密码、新密码和小数 `PATTERN_*`；
- SDK 提供 Go、Search、Send、Next、Done 与 Newline 回车动作。

## 决策

1. 在 ArkTS domain 层定义不含原始文本的 `EditorContext`、`EditorKind`、`ShiftState` 和 `EnterAction`。
2. 仅由 `infrastructure/ime/EditorAttributeMapper.ets` 引用 HarmonyOS `PATTERN_*` 与回车常量。测试通过显式数值 catalog 验证纯映射逻辑。
3. 搜索识别为文本 pattern 加 Search 动作；多行识别为文本 pattern 加 Newline 动作。未知或缺失 pattern 回退为可输入的中文普通策略。
4. `InputSessionStore` 是编辑器上下文、当前模式、临时模式返回点、Shift、回车、候选栏和会话学习策略的唯一状态所有者，并向活动键盘发布状态变化。
5. `KeyboardModePolicy` 统一执行模式约束。普通文本只长期记忆中文或英文；数字、电话和符号不作为普通文本长期恢复模式。
6. `EnglishShiftController` 实现 Lowercase、OneShotUppercase 与 CapsLock。只有成功提交英文字母才消费一次性大写；数字、符号、删除和回车不消费。
7. 编辑框或输入会话切换直接 reset 组合，不提交到新编辑框。用户主动离开中文时，有首选候选则先提交，随后 reset 并切换。
8. 密码上下文在应用时 reset 组合、清空候选、禁止中文与候选选择、设置 `setSessionLearningAllowed(false)`，并只通过 ArkTS IME 服务直接提交字符。
9. `ImeConnectionService` 统一映射并发送编辑动作；动作失败时沿用已有 Newline 安全回退。UI 不直接调用 IME Kit。
10. 中、英、数字、电话和符号布局使用声明式按键描述与既有 `BaseKey`、`LetterKey`、`DeleteKey` 组件，不复制英文大小写布局。
11. 标准 `PATTERN_NUMBER_DECIMAL` 是小数识别的主路径。针对当前 API 24 模拟器把 `InputType.NUMBER_DECIMAL` 错误上报为普通数字的问题，协作应用可通过 SDK 标准 `IMEClient.setExtraConfig` 传递 namespaced `number_decimal` 显式提示；Mapper 只在数字 pattern 上接受该提示，不通过 placeholder 或内容猜测类型。
12. ArkUI 键盘行 identity 包含编辑器种类、模式、Shift、小数能力与回车动作，确保编辑器属性变化时不会复用不兼容布局。

## 影响

- C++、Rust、C ABI、Node-API 接口和用户模型格式均不变。
- 不新增第三方依赖或网络权限。
- `InputSessionState` 增加编辑器与键盘 UI 状态，但不保存编辑框文本、密码、完整按键序列或候选历史。
- 小数点只在 SDK 明确返回小数 pattern，或编辑器通过 namespaced extraConfig 明确声明时提供；SDK 未提供负号子类型，因此不猜测负号能力。
- 搜索和多行识别依赖 SDK 当前暴露的回车动作语义。
- 当前模拟器的密码字段由系统安全键盘接管；这是比第三方 IME 自有密码布局更强的系统隔离。应用自有密码分支仍保留用于允许第三方 IME 的平台，并由单元测试守卫。

## 被否决方案

- 在 C++ 或 Rust 判断输入框类型：破坏既定分层。
- 在每个 UI 组件读取系统属性：造成兼容逻辑分散。
- 为英文大小写维护两套字母布局：产生重复状态与维护成本。
- 对未知输入类型显示空键盘：会导致无法输入。
