# PC 版应用输入兼容修复

## 结论

MatePad Edge 上“普通鸿蒙应用可输入、标注 PC 版的 WPS 和东方财富不可输入”，而搜狗、百度输入法在相同应用中可用，说明系统和 PC 宿主允许第三方输入法，故障属于双羽项目自身的注册与事件兼容问题。

2026-08-26 已同时修复以下两条链路：

1. 输入法扩展重新使用标准 `ohos.extension.input_method` 元数据，并通过 `stage0_input_method.json` 声明唯一的 `shuangyu_zh_cn` / `zh-CN` 子类型；
2. 物理键盘同时订阅 API 10+ 的 `keyEvent` 与 PC 宿主仍可能使用的 API 8 `keyDown` / `keyUp`。旧事件会重建 Ctrl、Alt、Shift、Meta 状态，两通道同时上报时会复用第一次的消费结果，避免重复输入。

Release 门禁会检查源配置、三个事件订阅、HAP 内的扩展元数据及打包后的子类型文件，防止后续版本误删兼容配置。

## 本地验收结果

- 完整 ArkTS 单元测试：`PASS`，包含 5 个新增 PC 宿主兼容用例；
- internalDebug HAP：`BUILD SUCCESSFUL`；
- Release HAP：`BUILD SUCCESSFUL`；
- 签名和未签名 Release HAP 内容门禁：`PASS`；
- HarmonyOS 6.1 / API 24 / x86_64 2in1 模拟器：`COMPUTER_STAGE5_RESULT=PASS`；
- 系统浏览器 Web 输入框：物理键产生正式中文候选、鼠标提交一次、切换应用正确清理候选，均为 `PASS`；
- `ime -l` 可见 `com.corrosion.shuangyuime`，`bm dump` 可见 `ohos.extension.input_method` 与 `$profile:stage0_input_method`。

模拟器证据位于 `docs/evidence/2026-08-26-pc-host-compatibility/x86_64-2in1`。

## MatePad Edge 客户验收

由于输入法扩展元数据发生变化，建议不要只覆盖旧进程：

1. 先切换回系统输入法，卸载客户设备上的旧双羽；
2. 安装新的签名 Release HAP，进入系统输入法设置，重新启用并选择双羽；
3. 完全退出并重新打开 WPS PC 版与东方财富 PC 版；
4. 在普通文本框中用实体键盘输入 `ni`，应出现双羽中文候选，按 `1` 或空格应提交“你”；
5. 验证 Backspace、Enter、候选翻页以及 Ctrl+C / Ctrl+V。快捷键不应被双羽当作拼音；
6. 分别在 WPS 和东方财富完成一次上述流程，再切换应用，旧候选窗应消失。

若同一签名包在客户真机仍失败，需要采集该 MatePad Edge 的系统版本、`ime -l`、`bm dump -n com.corrosion.shuangyuime` 与故障时 hilog。只有完成这一步真机验收，才能把结论从“代码、打包和 2in1 模拟器通过”提升为“客户具体 ARM64 设备与两个商业应用通过”。
