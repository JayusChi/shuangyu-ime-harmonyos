# Stage 4.2 最终验收记录

日期：2026-07-22

## 验收结论

阶段 4.2 验收完成。顶部候选栏、Pad 固定侧栏以及保留的浮动候选组件都统一通过
`CandidateDisplayItem` 展示候选文字；普通视觉文本和无障碍文案均不再包含全拼、
双拼码或其他 `candidate.reading` 内容。

## 数据边界

- `Candidate.reading` 继续存在于 ArkTS 类型、Store 快照、Node-API/C++ 转换和 Rust
  引擎结果中，供内部协议、调试与后续功能使用。
- UI 只消费 `candidate.text`；候选顺序、分页、宽度、点击索引、学习与提交路径未改变。
- 点击提交仍使用 `candidate.text`，不拼接或提交 `reading`。

## 验证结果

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| Phone 浅色候选不显示 reading | PASS | `device/stage42_phone_light_candidates.png/json` |
| Pad 深色侧栏候选不显示 reading | PASS | `device/stage42_pad_dark_candidates.png/json` |
| 普通视觉与无障碍文案 text-only | PASS | `Stage42.test.ets` 展示合同测试 |
| Store 保留 reading、顺序和长候选 | PASS | `Stage42.test.ets` 数据合同测试 |
| 提交只取 candidate.text | PASS | `Stage42.test.ets` 提交合同测试 |
| Phone 候选查询/退格/恢复/点击与空格提交回归 | PASS | `docs/evidence/stage10/device/stage10_device_acceptance.log` |
| ArkTS 全量测试 | PASS，284/284 | 2026-07-22 最终测试报告 |
| Release HAP 与内容门禁 | PASS | 11,796,320 bytes，SHA-256 `E27283BCE6273E35B57DFC0E7FC37B426E32CEDFE832B570CCC9151022686B3D` |

## 未覆盖环境

ARM64 物理真机、第三方浏览器和 Pad 分屏未执行；本阶段的显示合同已由两种设备形态、
深浅主题截图及全量自动化覆盖。

2026-07-22 的完整 Stage 10 Phone 设备脚本在上述候选与密码隔离段落全部 PASS，之后
在无关的“小数输入框”页面滚动定位处停止。因此本文只引用已明确完成的候选回归，
不把整套 Stage 10 脚本记为全量通过。
