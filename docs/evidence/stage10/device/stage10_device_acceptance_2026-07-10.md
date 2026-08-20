# 阶段 10 模拟器设备验收

- 日期：2026-07-10
- 设备：HarmonyOS 模拟器（非物理设备）
- 目标：`127.0.0.1:5555`
- 系统：`emulator 6.1.0.125(SP9DEVC00E120R4P11)` / API 24
- ABI：`x86_64`
- HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap`
- 大小：7,276,504 bytes
- SHA-256：`AC5CCF4FB7A9EAC26C8A960F96A73C5F660EFD23E11AB6BC1D1565967384FF55`
- 签名：unsigned
- 自动化脚本：`scripts/device-accept-stage10.ps1`
- 结果：`STAGE10_DEVICE_ACCEPTANCE_RESULT=PASS`

## 逐项结果

| 项目 | 结果 |
| --- | --- |
| HAP 安装、IME 启用和切换 | 通过 |
| 普通文本默认中文、候选栏、数字/符号入口 | 通过 |
| `ni -> 你` 候选查询与提交 | 通过 |
| 英文小写、一次性 Shift、实际大写提交后复位 | 通过 |
| 双击 Shift Caps Lock、连续大写、退出锁定 | 通过 |
| 临时数字、符号与原文本模式恢复 | 通过 |
| 中文候选栏恢复 | 通过 |
| 普通密码系统安全键盘、无候选、应用模型不增长 | 通过 |
| 数字密码系统安全数字布局、无候选 | 通过 |
| 整数受限布局 | 通过 |
| 小数点布局 | 通过 |
| 电话 `* # +` | 通过 |
| 邮箱 `@ .` | 通过 |
| URL `. / : - _` | 通过 |
| 搜索动作到达编辑器 | 通过 |
| 多行中文候选与回车动作 | 通过 |

## 本轮排版几何验收

- 模拟器布局树坐标密度：3.5 px/vp。
- 普通中文、普通英文、临时数字、符号、整数、小数、电话、邮箱、URL、搜索和多行共 11 个布局，最后一行按钮底边到键盘内容区底边均为 52px，即 15vp 的像素取整结果。
- 整数键盘：`0`、`删除`均为 616×147px；`完成`、`隐藏`均为 616×147px。
- 小数键盘：`7/8/9`和`./0/删除`两行均使用 X 边界 `35–440`、`458–863`、`880–1285`，每键 405×147px；`完成`、`隐藏`均为 616×147px。
- 所有数据来自本目录本轮重新生成的 `stage10_*.json`，截图已同步刷新。

## 密码运行时说明

本模拟器对 `Password` 和 `NUMBER_PASSWORD` 使用系统安全键盘，系统不展示第三方输入法面板。这是实际平台行为。验收脚本识别 `safeImage`、`CanvasKeyboard` 和系统安全按键节点，验证无中文候选；普通密码安全输入前后，应用用户模型记录数相同。

应用自有密码上下文的禁中文、禁候选、禁 Native、禁学习与直接提交分支由 `entry/src/test/Stage10.test.ets` 覆盖，不能在这个会强制系统安全键盘的模拟器上直接触发。

## 证据文件

- 完整命令与断言：`stage10_device_acceptance_2026-07-10.log`
- 主要截图：`stage10_normal_layout.png`、`stage10_normal_candidates.png`、`stage10_shift_caps_lock.png`、`stage10_password_layout.png`、`stage10_number_password_layout.png`、`stage10_decimal_layout.png`、`stage10_phone_layout.png`、`stage10_email_layout.png`、`stage10_url_layout.png`、`stage10_search_layout.png`、`stage10_multiline_final.png`
- 每个步骤对应的 `stage10_*.json` 为 `uitest dumpLayout` 原始布局证据。

## 未覆盖

- 真实物理设备、ARM64 运行时和其他 HarmonyOS 版本。
- 第三方 IME 自有密码布局的设备运行时，因为系统安全键盘强制接管。
- 横屏、折叠屏、完整深色主题和无障碍视觉矩阵。
- 已尝试使用 DisplayManager `-motion,1` 旋转模拟器，但截图和布局树仍为竖屏；`stage10_rotation_attempt_multiline_layout.*` 仅记录该失败尝试，不计作横屏验收。
