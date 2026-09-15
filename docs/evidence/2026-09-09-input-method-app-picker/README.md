# ϟ12 下方输入法选择键修复

日期：2026-09-09。结论：代码、ArkTS 全量、Release 构建/资源门禁，以及 Phone 模拟器应用级列表与实际切换验收通过。

## 原因和修复

旧包使用 `InputMethodListDialog`。该系统控件将默认输入法的键盘子类型展开为“中文26键、中文9键、笔画、手写、双拼、五笔”等条目；虽然它可以包含其他输入法，仍不符合客户要求的按输入法应用名称选择。2026-09-07 报告中仅凭控件弹出将此项记为通过的结论不充分，本次验收替代该条结论。

`ϟ12` 下方按键仍走 `SHOW_INPUT_METHOD_PICKER`，但弹窗现通过 `getInputMethods(true)` 读取系统启用列表，按应用包名去重并使用系统提供的 `label` 显示名称。点击其他应用时调用 `switchInputMethod`，不读取/选择双羽键盘档案或系统输入法子类型。点击当前应用只关闭弹窗，不改变键盘方案；关闭后丢弃迟到查询，切换前复查目标仍启用、当前输入法仍属于本次会话，并阻止重复点击。

本轮新增 `InputMethodAppPicker.ets` 和 `InputMethodAppPickerDialog.ets`，扩展系统适配器以保留应用名称，并替换键盘根组件中的旧控件。

## 验证

| 检查 | 结果 | 证据（仓库根目录下） |
| --- | --- | --- |
| ArkTS 全量 | 645/645 通过；新增 6 项应用选择回归 | `outputs/input-method-app-picker-20260909/arkts-test-result.txt` |
| clean Release HAP | PASS | `outputs/input-method-app-picker-20260909/build-release.log` |
| 最终 Release 资源门禁 | PASS | `outputs/input-method-app-picker-20260909/verify-release-hap.log` |
| 测试签名包与 Release 代码/资源一致 | `modules.abc`、双 ABI native 库和 `resources.index` 哈希相同 | `outputs/input-method-app-picker-20260909/release-device-payload-comparison.json` |
| 旧包复现 | 点击后首屏显示键盘子类型 | `outputs/input-method-app-picker-20260909/old-picker.png/json` |
| 新列表 | 仅“小艺输入法、双羽输入法”，每款一项，无中文26键等子类型 | `outputs/input-method-app-picker-20260909/fixed-picker.png/json` |
| 选择当前双羽 | 弹窗关闭，当前输入法仍为双羽 | `outputs/input-method-app-picker-20260909/selected-current.png/json` |
| 取消 | 弹窗关闭，可重新打开 | `outputs/input-method-app-picker-20260909/cancelled.png/json` |
| 选择小艺 | 系统当前 IME 变为 `com.huawei.hmos.inputmethod`；重新点击输入框后显示小艺键盘 | `outputs/input-method-app-picker-20260909/switched-ime.txt`、`celia-refocused.png/json` |
| 验收后恢复 | 当前 IME 恢复双羽完整体验模式 | `outputs/input-method-app-picker-20260909/final-ime.txt` |

设备为 `127.0.0.1:5555` Phone 模拟器，1320×2856，独立宿主为 `com.example.shuangyuime.acceptance`。本机仅启用小艺与双羽，百度未安装，因此百度与其他真实设备切换未运行；应用标签不会硬编码或伪造。

模拟器旧安装使用开发证书。正式发布签名覆盖安装被系统以 `9568332` 拒绝后，生成相同代码的匹配开发签名测试 HAP 覆盖安装，未卸载或清空数据；安装脚本恢复 IME 时短暂返回 `77`，重新检查并选择双羽后正常完成验收。本机产品签名配置和默认构建输出已恢复正式 Release。

最终 Release HAP：`entry/build/default/outputs/default/entry-default-signed.hap`，92,895,882 bytes，SHA-256 `398B423A6DD38E1D1A296FF5106B095F3011578D1A87C13B62174155E682431C`。

本轮未升级版本号或重新生成客户 APP。`artifacts/0.9.0/` 中 2026-09-08 的交付 APP 仍为历史原包，不包含本次修复。
