# Device matrix

本轮两个连接目标均为 x86_64 模拟器，不是 ARM64 物理真机。

| 设备 | ABI / 系统 | 分辨率 / 方向 | Debug HAP SHA-256 | PASS | FAIL | NOT RUN |
| --- | --- | --- | --- | --- | --- | --- |
| Phone emulator `127.0.0.1:5555` | x86_64 / OpenHarmony 6.1.1.125 | 1320×2856 / 竖屏 | `f1551be1cd0b13453798673bec1fa6db972d4f1c419972680ae1ef690830cf8d` | 普通输入、候选、删除/提交、Shift/Caps、数字/符号；多数设置及重启持久化 | 密码受保护表面被脚本误判后报无 Shift；设置清空模型后半程未完成 | signed Release 独立 TextInput、设备性能、完整应用矩阵 |
| Tablet emulator `127.0.0.1:5557` | x86_64 / OpenHarmony 6.1.1.125 | 2880×1920 / 横屏 | 同上 | 普通输入、候选、删除/提交、Shift/Caps、数字/符号 | 密码受保护表面被脚本误判后报无 Shift；原设置脚本入口假设失败 | 修正后完整设置复跑、signed Release 独立 TextInput、设备性能、完整应用矩阵 |
| ARM64 physical device | NOT AVAILABLE | NOT RUN | NOT RUN | 0 | 0 | 全部 |

Phone 原始结果：`runs/20260727-122614-8072c5af`。Pad 原始结果：
`runs/20260727-122805-4825a95a`。ARM64 发现结果：
`runs/20260727-123010-66c3af81`。Phone 设置复跑：
`reruns/phone-stage11-final`。
