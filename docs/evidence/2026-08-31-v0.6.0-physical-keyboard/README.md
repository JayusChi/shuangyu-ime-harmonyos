# 0.6.0 客户反馈第 1～6 点模拟器验收

## 结论

`SIMULATOR_PASS / REAL_HARDWARE_NOT_RUN`

2026-08-31 使用 HarmonyOS 6.1 x86_64 2in1 模拟器，通过系统 `uitest uiInput keyEvent` 注入实体按键码，六项客户反馈均通过。运行日志确认输入法处于 `HARDWARE_READY`、`keyboardVisible=false`，各按键从 `InputMethodLifecycle` 的 `physical key consumed` 路径进入。Phone 模拟器另用于固定候选栏的下划线对照。

本次模拟器按键注入不能替代真实 USB、蓝牙或内置实体键盘对现代 `keyEvent` 与旧版 `keyDown/keyUp` 双通道时序的最终证明；真实硬件仍为 `NOT_RUN`。

## 环境与安装包

- 2in1：`127.0.0.1:5557`，`OpenHarmony-6.1.1.125`，x86_64，`HARDWARE_READY`。
- Phone：`127.0.0.1:5555`，`OpenHarmony-6.1.1.125`，x86_64，`TOUCH_READY`，固定键盘候选栏对照。
- 输入方案：`xiaohe-yinxing-26` / `schemeId=xiaohe-yinxing`。
- 应用版本：`0.6.0`，`versionCode=6000000`。
- signed HAP：`entry/build/default/outputs/default/entry-default-signed.hap`。
- HAP 大小：`94,761,274` bytes。
- HAP SHA-256：`5EEEFD00B676CA1182EFE0C1BBCCC03F1B1DFB38685BB3C2A1EE63A077165239`。
- 两台模拟器均安全覆盖安装成功；`SIGNATURE_RESET=false`，未卸载、未清数据。

## 逐项结果

| 序号 | 输入与断言 | 结果 | 主要证据 |
| --- | --- | --- | --- |
| 1 | `;q`：单分号先显示 `1. ：`，按 `q` 后无需空格直接提交 `：“`，组合清空 | PASS | `device-2in1/01_semicolon_q_guide.json`、`01_semicolon_q_commit.json/.jpeg` |
| 2 | `anf` 仅有 `1. 按`；按 `;` 后宿主先得到“按”，浮动窗同时进入 `; → 1. ：` 引导 | PASS | `device-2in1/02_unique_semicolon_before.json`、`02_unique_semicolon_after.json/.jpeg` |
| 3 | `; Space` 提交 `：`；`;;` 提交 `；` | PASS | `device-2in1/03a_semicolon_space_guide.json/.jpeg`、`03a_semicolon_space_commit.json/.jpeg`、`03b_double_semicolon_commit.json/.jpeg` |
| 4 | 单击 `o` 的原始码严格为 `o`，继续 `k` 后严格为 `ok`；无 `oo/okk`；`ocd` 仍显示 `1. 「设置菜单」` | PASS | `device-2in1/04_o.json/.jpeg`、`04_ok.json/.jpeg`、`04_o_direct_ocd.json/.jpeg` |
| 5 | 分类 `#直` 的 `gwy` 显示 `1. 给ʲⁱ̌予u`，补 `u` 提交“给予”；客户 `5.直通.txt` 的两个 `orq` 行按顺序显示，空格选择首项提交 `2026年8月31日` | PASS | `device-2in1/05_category_direct_gwy.json/.jpeg`、`05_category_direct_gwyu_commit.json/.jpeg`、`05_file_direct_orq.json/.jpeg`、`05_file_direct_orq_commit.json/.jpeg` |
| 6 | 2in1 浮动窗输入码 `o` 无下划线；Phone 固定候选栏输入码 `o` 保留实线下划线 | PASS | `device-2in1/04_o.jpeg`、`device-phone/inline-o.json/.jpeg` |

## 直通数据边界

设备用例同时覆盖了两条独立数据链：分类词库内 `#直` 的 `gwyu`，以及客户 `5.直通.txt` 的 `orq` 动作行。现有转换报告记录源文件共 44 行，接受 31 行，明确隔离 13 行不支持或不安全语义；设备运行时没有解释原始 `$cmd/$ddcmd`。

## 日志检查

- `device-2in1/issues-1-3.log`：第 1～3 项的实体按键路由与候选窗生命周期。
- `device-2in1/issues-4-6.log`：`o` 前缀、分类直通和动作直通链路；可见 `HARDWARE_READY` 与逐键 `physical key consumed`。
- 两份日志均未检出 `fatal`、`panic`、`crash`、`ENGINE_INTERNAL_ERROR` 或 `physical keyboard operation failed`。

## 未覆盖

- 真实 USB、蓝牙或内置实体键盘。
- ARM64 真机。
- 未获 HDC 授权的设备 `25PVB24111002516` 未做任何修改。
