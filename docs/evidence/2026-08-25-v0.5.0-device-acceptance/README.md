# 0.5.0 新功能三设备验收

> 后续状态（2026-08-25）：本文记录的三个主要阻断已修复并复验通过，见 `../2026-08-25-v0.5.0-blocker-fixes/README.md`。本文以下内容保留为修复前的原始验收记录。

日期：2026-08-25

## 结论

本轮设备验收结论为 **FAIL / 不建议直接交付客户测试**。

新音形词库、T9 输入链、本地关联词、AI 默认关闭策略和第三方 URL 编辑器策略均已在三种设备形态跑通；但存在两个真实设备阻断问题：

1. Pad 和 2in1 在冷启动后首次直接聚焦普通中文输入框时，9 键拼音面板不显示，并持续返回系统输入面板错误 `12800008`。
2. 2in1 实体键盘的智能句号未完成替换，`un..` 实际得到 `熟能生巧。.`，而不是 `熟能生巧.`。

此外，安装包仍声明 `0.4.0 / 4000000`，不能按 `0.5.0` 对外识别。

## 设备与包

| 设备 | HDC target | ABI | 分辨率 |
| --- | --- | --- | --- |
| Phone | `127.0.0.1:5555` | x86_64 | 1320×2856 |
| Pad | `127.0.0.1:5557` | x86_64 | 2880×1920 |
| 2in1 | `127.0.0.1:5559` | x86_64 | 3120×2080 |

最终三台统一安装同一份签名 Release HAP：

- 路径：`entry/build/default/outputs/default/entry-default-signed.hap`
- 大小：`71,194,703 bytes`
- SHA-256：`51339F860DE3B76669566DB15665EFC1932B2B291782E621B7287D07FFBD3BDC`
- HAP 校验：`PASS`
- 三台 `bm dump`：`debug=false`、`cpuAbi=x86_64`
- 当前版本：`versionName=0.4.0`、`versionCode=4000000`

测试过程中 DevEco/IDE 曾于 10:48 自动生成 Debug HAP 并覆盖 Phone。发现后已废弃受影响的 Phone 本地关联词结果，重新构建、校验并向三台覆盖安装上述最终 Release；Phone 本地关联词已在最终 Release 上重跑通过。正式验收时应停止 IDE 自动部署。

## 验收矩阵

| 项目 | Phone | Pad | 2in1 | 结果说明 |
| --- | --- | --- | --- | --- |
| 签名 Release 安装、启动 | PASS | PASS | PASS | 最终均为 `debug=false` |
| 设置页及输入方案切换 | PASS | PASS | PASS | Phone/Pad/2in1 布局正常 |
| 小鹤音形前缀提示 | PASS | PASS | PASS | 输入 `un` 均显示 `熟能生巧 uq` |
| 智能句号（虚拟键盘） | PASS | PASS | N/A | 两次中文句号在 500ms 内替换为 `.` |
| 智能句号（实体键盘） | N/A | N/A | **FAIL** | `熟能生巧。.`，未替换为单个英文句点 |
| T9 `64426` 候选与提交 | PASS | PASS | PASS | 均出现 `ni'hao / 你好`，空格提交 `你好` |
| T9 冷启动首次显示 | PASS | **FAIL** | **FAIL** | Pad/2in1 面板隐藏，T9 键数量为 0 |
| T9 经 URL 面板预热后 | PASS | PASS | PASS | 先显示 QWERTY，再回中文框可显示并输入 T9 |
| 第三方 URL 字段直通 | PASS | PASS | PASS | 均得到 `ab `，未进入中文组合 |
| AI 默认与生产策略 | PASS | PASS | PASS | AI 总开关、本地关联默认关闭；云代理未配置提示可见 |
| 本地关联词 | PASS | PASS | PASS | 提交“今天”后出现“星期一/星期三/星期二”；点击后为“今天星期一” |
| 崩溃、panic、引擎内部错误 | PASS | PASS | PASS | 验收过程未观察到此类标记 |

## 阻断问题

### P1：Pad/2in1 的 T9 冷启动面板不显示

最终 Release 最小复现：设置为“虚拟键盘 + 9 键拼音”，强停输入法进程，启动独立验收宿主并首次聚焦 `ACCEPT_CHAT_SEND`。

- Pad：`T9_KEY_COUNT=0`，日志内 `12800008` 共 544 条。
- 2in1：`T9_KEY_COUNT=0`，日志内 `12800008` 共 534 条。
- 聚焦 URL 字段可正常建立 QWERTY 面板；再返回中文字段后，T9 可正常显示。这说明不是宿主字段、IME 选择或系统输入面板整体失效，而是 T9 中文布局首次建面板/调整高度路径的问题。
- 失败时 Pad 请求的 T9 横屏面板高度为 `1354px`（屏幕高 `1920px`），2in1 为 `1469px`（屏幕高 `2080px`）；`InputPanelController` 在失败后持续 `queueResize('coalesced')`，形成高频重试。

证据：

- `pad/t9_cold_failure.jpeg`、`pad/t9_cold_failure.json`、`pad/t9_cold_failure.log`
- `2in1/t9_cold_failure.jpeg`、`2in1/t9_cold_failure.json`、`2in1/t9_cold_failure.log`
- 成功链：`pad/t9_64426.jpeg`、`pad/t9_commit.jpeg`、`2in1/t9_64426.jpeg`、`2in1/t9_commit.jpeg`

建议修复：为 T9 横屏单独建立受系统面板上限约束的高度预算，把候选栏、拼音组合栏、四行九宫格和功能行压缩到可接受高度；`panel.resize` 失败后不要在目标尺寸未变化时无限 coalesced 重试，并增加失败降级尺寸。

### P1：2in1 实体智能句号失效

实体键盘输入 `un` 后快速连续注入两个句点，候选“熟能生巧”被提交，但结果是 `熟能生巧。.`。第一个句点在有组合时由 IME 转为中文句号并提交候选；组合清空后，第二个句点被物理路由当作 `NONE` 直通宿主，智能句号状态同时被清除，因此无法触发替换。

证据：`2in1/physical_smart_period.jpeg`、`2in1/physical_smart_period.json`。

建议修复：在无组合但仍处于实体中文输入会话、且前一个中文句号仍在时间窗内时继续消费第二个句点；不要在 `NONE` 分支提前清除可替换状态。新增设备级回归：空组合 `..`、候选提交后 `..`、超时 `..`、关闭功能 `..`。

### P0：版本身份仍是 0.4.0

`AppScope/app.json5` 仍为：

- `versionCode: 4000000`
- `versionName: "0.4.0"`

修复上述设备问题并完成回归后，再更新为正式批准的 0.5.0 版本号并重建签名包。

## 通过项证据

- 小鹤音形：`phone/yinxing_un.jpeg`、`pad/yinxing_un.jpeg`、`2in1/yinxing_un.jpeg`
- Phone/Pad 智能句号：`phone/smart_period_fast.json`、`pad/smart_period_fast.json`
- URL 直通：三设备各自的 `url_passthrough.jpeg/json`
- AI 策略：`phone/ai_policy.jpeg`、`pad/ai_policy.jpeg`、`2in1/ai_policy_visible.jpeg`
- 本地关联词：Phone 最终 Release 的 `release_assoc_today.jpeg/json`、`release_assoc_accept.json`；Pad/2in1 的 `association_today.jpeg/json`、`association_accept.json`
- 最终恢复：Phone 为 `final_verified.jpeg/json`；Pad/2in1 为 `post_failure_restored.jpeg/json`

## 验收边界

- 三台均为 x86_64 模拟器，本轮不代表 ARM64 真机通过。
- 未执行长时稳定性、RSS、旋转/分屏、真实聊天应用全矩阵和弱性能设备测试。
- 2in1 旧阶段 3 脚本的 `ni → 你` 断言被设备已有用户词库固顶词“三端固顶”覆盖；这是脚本不具备状态隔离，不作为本轮产品缺陷，但应改为使用隔离编码或准备/恢复测试数据。
