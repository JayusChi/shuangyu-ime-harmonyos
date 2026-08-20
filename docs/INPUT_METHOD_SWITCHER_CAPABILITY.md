# HarmonyOS 输入法切换能力记录

记录日期：2026-07-21  
工程目标/兼容 API：HarmonyOS API 24（`6.1.1(24)`）

## 结论

目标 API 24 没有提供独立的“切换下一输入法”调用。当前输入法可枚举已启用输入法、查询当前输入法并切换到指定输入法，因此工程在 `InputMethodSwitcher` 中组合这三个能力；直接切换不可用或失败时打开系统输入法选择器。UI 层不导入 IME Kit。

## 能力矩阵

| 能力 | 使用的 HarmonyOS API | SDK 标注最低 API | 权限 | 目标 API 24 结论 | 降级 |
| --- | --- | ---: | --- | --- | --- |
| 枚举已启用输入法 | `inputMethod.getSetting().getInputMethods(true)` | 9 | 无新增权限 | 可用 | 无法枚举时打开系统选择器 |
| 查询当前输入法 | `inputMethod.getCurrentInputMethod()` | 9 | 无新增权限 | 可用 | 当前项不在枚举列表时打开系统选择器 |
| 当前输入法切换到指定输入法 | `inputMethod.switchInputMethod(property)` 当前 IME 调用形式 | 11 | 无新增权限 | 可用；Phone/Pad 模拟器实测成功 | 返回 false/抛错时打开系统选择器 |
| 打开系统输入法选择器 | `inputMethod.getSetting().showOptionalInputMethods()` | 9 | 无新增权限 | 可用；Pad 模拟器实测成功 | 返回 false/抛错时给出通用错误，不保留无响应按钮状态 |
| 读取系统面板底部 inset | `Panel.getDisplayId()` + `Panel.getSystemPanelCurrentInsets(displayId)` | 15 / 21 | 无新增权限 | 可用 | 查询失败按 0 inset 继续，顶部收起入口保留 |

`showOptionalInputMethods()` 从 API 18 起在 SDK 中标记 deprecated，官方推荐 API 11+ ArkUI `InputMethodListDialog`。当前实现保留服务层调用，以确保系统选择器能力封装在基础设施层且已在目标 API 24 模拟器验证；升级 SDK 时应优先评估由系统适配组件承载 `InputMethodListDialog`，不能把系统 API 散落到键盘 UI。

旧版 `switchInputMethod` 重载曾要求 `ohos.permission.CONNECT_IME_ABILITY` 且面向 system_core；工程没有申请该权限，也没有使用旧重载。当前工程权限仍只有既有震动权限。

## 适配与回退

1. 短按先读取已启用列表与当前输入法，按列表顺序循环选择下一项。
2. 列表少于两项、找不到当前项、指定切换返回 false 或抛错时，在同一受保护请求内打开系统选择器。
3. 长按直接打开系统选择器；500ms 后只触发一次长按动作，释放与随后 Click 不再触发短按。
4. 请求进行中以及完成后 700ms 内的重复请求会被抑制；会话停止、隐藏或销毁会递增 generation，使旧异步结果失效。
5. 若直接切换和选择器能力都不可用，UI 隐藏切换入口；顶部收起入口不受影响。系统调用失败只显示通用提示，日志不记录输入内容、组合串或候选。

## 形态与安全区

- Pad 判定：窗口可用短边至少 `600vp`；不读取品牌或机型名称。
- Phone 不再创建额外辅助行，收起入口只保留候选栏右侧一个。
- 标准竖屏 Phone 存在系统输入法区域时不显示自定义切换图标；短按“中/英”切换语言，长按打开系统输入法选择器。
- Pad、横屏、窄于 `320vp`、宽于等于 `500vp` 的特殊 Phone 窗口，以及 `bottomSystemInsetPx` 为 0、无法确认系统输入法区域存在的布局，把显式切换键放进现有文本功能键行。
- `bottomSystemInsetPx` 会先从窗口高度扣除，并参与系统输入法区域判断和面板高度计算。旋转、窗口 resize 和窄分屏均重新计算。

## 验证边界

已在 1320×2856 Phone 竖屏模拟器确认：不再显示自定义底部辅助行，长按“中/英”会打开系统输入法选择器。已在 2880×1920 Pad 横屏模拟器确认：现有功能行保留显式切换键，短按切换下一输入法，长按打开系统选择器。数字、电话、符号模式的无系统区域回退以及横屏、窄/宽窗口由纯策略/布局单元测试覆盖。

尚未验证物理 ARM64 真机、三键导航和外接键盘。这些场景不得从模拟器结果推断为已通过。
