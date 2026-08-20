# Stage 4.1 最终验收记录

日期：2026-07-22

## 验收结论

阶段 4.1 验收完成。候选区顶部显示的是用户逐键输入的精确 `rawInput`，以实线下划线
标识“尚未上屏”；不再把引擎格式化后的 `preeditText`（例如 `ni'hao`）误显示给用户。
原始编码清空、提交、删除至空、切换编辑框、隐藏键盘或结束会话时提示同步消失。

## 实现合同

- `CompositionPreeditView.resolveCompositionPreeditView` 在 `rawInput` 非空时原样返回
  `displayText=rawInput` 和 `UNDERLINE`，不插入下划线字符或分隔符。
- `CandidateBar` 直接绑定响应式 `rawInput`；Pad 路线 C 的 `PadSideCandidateStrip` 使用
  同一原始值和下划线样式。
- HarmonyOS `InputClient.setPreviewText(text, range)` 不提供输入法可控的样式参数，
  因此宿主编辑框的系统预编辑样式仍由宿主决定；键盘候选区提供一致的可见提示。
- 引擎、C++/C ABI、候选排序、正式提交文本和预编辑生命周期协议均未改变。

## 验证结果

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| `nihc` 与引擎 `ni'hao` 分离 | PASS，界面显示带下划线的 `nihc` | `device/stage41_segmented_nihc.png/json` |
| 空输入和所有清理路径 | PASS | `Stage41.test.ets` 生命周期测试 |
| 过期 generation 不恢复旧编码 | PASS | `Stage41.test.ets` 并发保护测试 |
| Phone x86_64 浅色设备验收 | PASS | 同上设备截图 |
| Pad x86_64 深色联动验收 | PASS | `../stage4_2/device/stage42_pad_dark_candidates.png/json` |
| ArkTS 全量测试 | PASS，284/284 | 2026-07-22 最终测试报告 |
| Rust workspace | PASS，fmt/clippy/test | 2026-07-22 最终回归 |
| Release HAP 与内容门禁 | PASS | 11,796,320 bytes，SHA-256 `E27283BCE6273E35B57DFC0E7FC37B426E32CEDFE832B570CCC9151022686B3D` |

## 未覆盖环境

ARM64 物理真机、第三方浏览器、多行文本框和手机横屏未执行。这些属于外部设备/宿主
兼容性扩展，不改变当前 Phone/Pad x86_64 模拟器和自动化合同的阶段验收结论。
