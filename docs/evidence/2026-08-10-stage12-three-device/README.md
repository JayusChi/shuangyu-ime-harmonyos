# 阶段 12 三设备验收

日期：2026-08-10

## 设备

| 设备 | HDC target | 系统/API | 分辨率 |
| --- | --- | --- | --- |
| Phone | `127.0.0.1:5555` | HarmonyOS 6.1 / API 24 / x86_64 | `1320×2856` |
| 2in1 | `127.0.0.1:5557` | HarmonyOS 6.1 / API 24 / x86_64 | `3120×2080` |
| Tablet | `127.0.0.1:5559` | HarmonyOS 6.1 / API 24 / x86_64 | `2880×1920` |

三台均安装同一份 default signed Release HAP：`38,123,521 bytes`，SHA-256 `f2302e707882e6ebc3e30841382b80dde11db7c790b802f4ab25a3cb00f78c40`。独立验收宿主为 `com.example.shuangyuime.acceptance`。

## 验收结论

| 项目 | Phone | 2in1 | Tablet |
| --- | --- | --- | --- |
| `aa` 方案/分类 enable、disable、all、core、status | PASS | PASS | PASS |
| `Ctrl+Alt+3/4` 真实物理组合键注入 | PASS | PASS | PASS |
| 直通设置强停后保持 | PASS | PASS | PASS |
| 用户词库 UI 添加/删除/固顶/第 N 位 | PASS | PASS | PASS |
| 设置进程保存后输入法进程热重载 | PASS | PASS | PASS |
| 强停输入法后的冷启动镜像 | PASS | PASS | PASS |
| 输入 `ni`：固顶第 1、普通第 2、指定第 3、系统“你”隐藏 | PASS | PASS | PASS |

最终候选证据：

- Phone：`phone/release_final_candidate.json`，显示 `1. 验收固顶 / 2. 跨进程固顶 / 3. 验收三位`。
- 2in1：`2in1/release_final_candidate.json`，显示 `1. 三端固顶 / 2. 三端普通 / 3. 三端三位`。
- Tablet：`tablet/release_final_candidate.json`，显示 `1. 三端固顶 / 2. 三端普通 / 3. 三端三位`。

三份最终布局均不包含候选 `你`。对应 `release_final_runtime.log` 在三台均出现 `user lexicon shared snapshot mirrored`、`InputMethodExtensionAbility runtime ready`、`input session started: editor=normal_text`，顺序证明冷启动先恢复词库、再执行首个输入会话。

后续 UI 回归在 Phone Release 包验证：`phone/userlex_ui_fixed.jpeg` 中标题与返回按钮完整位于状态栏下方；实际滑动后 `phone/userlex_ui_fixed_scrolled.jpeg` 显示页面可正常滚动且右侧无视觉滚动条。

设置主页文案精简证据为 `phone/settings_text_removed.jpeg` 和布局 `phone/settings_text_removed.json`；布局不包含页头“本地设置，修改后立即应用”、双拼方案说明及用户学习说明。

## 测试中发现并修复的问题

1. 输入法独立进程不能写主进程 Preferences，且两进程 `filesDir` 不共享。设置快照改为所有进程以 `SHARED_CONFIG` 为 canonical；用户词库改为版本化分块快照，manifest 切换成功后回收旧分块，输入法进程镜像到自己的沙箱文件。
2. 等待异步词库镜像时延后注册 IME 事件会在较快设备漏掉首个 `inputStart`。最终实现先注册、后按初始化 Promise 排队执行。
3. 用户词库“编码”输入框原为普通文本类型，启用本输入法时 ASCII 编码可能被转换为中文。现固定为 `InputType.Email`，设备布局证据确认 `zzzz` 保持原始 ASCII。

目录中保留了操作过程布局、窗口截图和失败路径复现证据；验收结论以上述三个 `release_final_candidate.json`、对应运行日志和最终 signed HAP 为准。
