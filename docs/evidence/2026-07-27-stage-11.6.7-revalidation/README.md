# 阶段 11.6.7 独立 TextInput 复验

结论：**PASS**。

- 设备：HarmonyOS 6.1 x86_64 Phone 模拟器，`1320x2856`，序列号 `127.0.0.1:5557`。
- 链路：独立应用 `com.example.nexttest` 的 ArkUI `TextInput` → 输入法 ArkTS → Node-API C++ → Rust。
- 执行：从 force-stop/clean 启动，A～N 连续两轮；每轮 14/14 PASS。
- 第一轮最终输出证据保存在 `editor-device-phone/round-1/assert_A_field_1.json` 至
  `assert_N_field_1.json`；第二轮汇总见
  `editor-device-phone/editor-a-n-rounds-2-2.json` 和
  `editor-device-phone/round-2/round_2_result.json`。

| 用例 | 实际结果 |
| --- | --- |
| A 三码唯一不自动提交 | `pqr` 保持预编辑，PASS |
| B 四码唯一自动提交 | 仅提交一次“测”，PASS |
| C 四码多候选保留 | `wxyz` 保持预编辑，PASS |
| D 有有效后续码不提交 | `abcd` 保持预编辑，PASS |
| E 第五码顶屏 | 旧段顶屏，新键只处理一次，PASS |
| F 旧段无候选 | 不提交旧段且第五键保留，PASS |
| G `#删` | 已删候选未提交，PASS |
| H `#固/#N` | 顶屏首选改变且第五键保留，PASS |
| I 分类开关 | 设置操作本身不提交，PASS |
| J 正向切分 | 文本顺序与冻结合同一致，PASS |
| K 反向切分 | 文本顺序与冻结合同一致，PASS |
| L 无合法切分 | 安全清空且不提交，PASS |
| M Guide 隔离 | `;g` 保持引导预览，PASS |
| N 切回 `xiaohe` | “你好输入法”，PASS |

本轮还修正了设备脚本的两个证据风险：只滚动应用内容区，避免系统 Back/完成键意外提交候选；按当前布局语义定位键帽和 TextInput，不再依赖固定坐标。

ARM64 物理真机未执行，归入 11.6.9，不影响本阶段要求的 x86_64 模拟器验收结论。
