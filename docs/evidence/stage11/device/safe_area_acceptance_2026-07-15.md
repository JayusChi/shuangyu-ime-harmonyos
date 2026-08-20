# 沉浸式安全区与 Debug 固定浅色验收（2026-07-15）

环境：x86_64 HarmonyOS 6.1.1 模拟器，API 24，目标 `127.0.0.1:5555`，Debug HAP。系统“显示和亮度”已选择深色，输入法设置已选择强制深色。

结果：

- 设置页标题完整显示，背景、状态栏和底部导航区均为深色。
- Debug 页标题 `阶段 10 · 输入框类型验收` 上边界 220px，高于状态栏下边界 136px，不相交。
- Debug 页在系统深色 + 输入法深色时仍为固定白色，状态栏时间/信号/电量为深色，底部导航区为浅色。
- Debug 页切到系统设置再回到前台后仍保持固定浅色。
- 弹出输入法的深色键盘后，键盘按用户主题显示，Debug 页面主体仍为浅色。
- Debug 页滚到底部时，最后一个 `TextArea` 下边界 2674px，小于安全 `Scroll` 下边界 2758px。
- 从 Debug 返回后，设置页主体及上下系统区立即恢复强制深色。

主要证据：`safe_area_settings.png`、`safe_area_system_dark_input_dark_debug.png`、`safe_area_debug_foreground.png`、`safe_area_debug_dark_keyboard2.png`、`safe_area_debug_bottom2.png`、`safe_area_return_dark.png` 及对应 JSON 布局树。

限制：模拟器没有真实摄像头挖孔；本轮未覆盖分屏、悬浮窗和厂商定制系统栏。代码会监听窗口避让区变化并处理四边几何，但这些形态仍需在目标设备上复验系统窗口管理器的最终呈现。
