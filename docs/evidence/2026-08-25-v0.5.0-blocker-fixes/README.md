# 0.5.0 三项阻断修复复验

日期：2026-08-25

## 结论

本轮结论为 **PASS**。上一轮发现的三个主要阻断均已修复并按原失败路径复验通过：

1. Pad、2in1 冷启动首次聚焦普通中文框时，T9 面板均首次显示成功，8 个 T9 字母数字键可见，`12800008` 均为 0。
2. 2in1 实体键盘输入 `un..` 后得到 `熟能生巧.`，不再出现 `熟能生巧。.`。
3. 同一份签名 Release 在 Phone、Pad、2in1 上均识别为 `0.5.0 / 5000000`、`debug=false`、`releaseType=Release`。

## 修复内容

- 横屏 T9 面板使用受控高度预算。Pad 从失败时的 `1354px` 调整为 `1152px`，2in1 从 `1469px` 调整为 `1248px`；键盘行继续通过 `layoutWeight` 在可用区域内均分。
- 面板 resize 失败后，仅在上一轮 resize 成功且期间目标发生变化时才执行合并补偿；相同失败目标不再无界重试。
- 实体中文句号提交候选并清空组合后，在智能句号时间窗内继续消费第二个物理 `.`，交给既有原子替换逻辑处理；其他无组合标点仍按原行为直通。
- 应用版本更新为 `versionName=0.5.0`、`versionCode=5000000`。

## 包与主机门禁

- HAP：`entry/build/default/outputs/default/entry-default-signed.hap`
- 大小：`71,193,992 bytes`
- SHA-256：`7967DAE0EC5C5A516FB5C24885BE4847658A8AFA1927E76FF0E35056D18A3B3B`
- 发布包校验：PASS
- ArkTS 单元测试：`511/511` PASS，Failure 0，Error 0
- Release 构建：PASS

## 设备复验

| 设备 | HDC target | 复验项 | 结果 |
| --- | --- | --- | --- |
| Phone | `127.0.0.1:5555` | 版本、Release 标志 | PASS：`0.5.0 / 5000000`、`debug=false` |
| Pad | `127.0.0.1:5557` | T9 冷启动首次显示、`64426` 输入提交、版本 | PASS：8 键、`12800008=0`、提交“你好” |
| 2in1 | `127.0.0.1:5559` | T9 冷启动首次显示、`64426` 输入提交、实体智能句号、版本 | PASS：8 键、`12800008=0`、提交“你好”、`熟能生巧.` |

T9 冷启动日志中的首个 resize 均已完成：

- Pad：`widthPx=2880, heightPx=1152, screenHeightPx=1920, density=2`
- 2in1：`widthPx=3120, heightPx=1248, screenHeightPx=2080, density≈1.9`

## 证据索引

- Pad 冷启动首次显示：`pad/t9_cold_visible.jpeg`、`pad/t9_cold_visible.json`、`pad/t9_cold_visible.log`
- Pad 完整输入链：`pad/t9_64426.jpeg/json`、`pad/t9_commit.jpeg/json`
- 2in1 冷启动首次显示：`2in1/t9_cold_visible.jpeg`、`2in1/t9_cold_visible.json`、`2in1/t9_cold_visible.log`
- 2in1 完整输入链：`2in1/t9_64426.jpeg/json`、`2in1/t9_commit.jpeg/json`
- 2in1 实体智能句号：`2in1/physical_smart_period_fixed.jpeg/json/log`
- Pad 配置恢复：`pad/restore_after.jpeg/json`

## 收尾状态与边界

- Pad 已恢复为“虚拟键盘 + 18 键双拼”；2in1 已恢复为“实体键盘 + 26 键小鹤音形”；Phone 配置未改动。
- 三台均为 x86_64 模拟器，本次结果不替代 ARM64 真机、旋转/分屏、长稳和真实第三方应用矩阵。
