# 阶段 11.6.6 分号引导状态转移

状态机只存在于 Rust `code-table-runtime`。ArkTS 只路由按键、展示 Rust 结果和执行已选择动作，不复制状态判断。

| 当前状态 | 输入 | 新状态 | raw | 候选/动作 | 提交与清理 |
| --- | --- | --- | --- | --- | --- |
| `Idle` | `;` | `GuidePrefix` | 空（协议展示为 `;`） | 空，不枚举引导表 | 无提交 |
| `NormalCode` | `;` | `GuidePrefix` | 空 | 清除普通查询，不访问普通表 | 无提交 |
| `GuidePrefix` | `a-z` | `GuideCode` | 追加首字母 | 仅查 guide/action 表 | 无提交 |
| `GuidePrefix` | `;` | `GuidePrefix` | 空 | 空 | 确定性重启引导 |
| `GuidePrefix` | 非法键 | `Idle` | 空 | 空，`INVALID_KEY` | 只清一次 |
| `GuidePrefix` | Backspace | `Idle` | 空 | 空 | 只清一次 |
| `GuidePrefix` | Space/Enter | `Idle` | 空 | 空 | 不提交字面分号 |
| `GuideCode` | `a-z` | `GuideCode` | 追加字母 | 仅查 guide/action 表 | 无提交 |
| `GuideCode` | `;` | `GuidePrefix` | 空 | 空 | 确定性重启引导 |
| `GuideCode` | 非法键 | `Idle` | 空 | 空，`INVALID_KEY` | 只清一次 |
| `GuideCode` | Backspace（仍有字母） | `GuideCode` | 删除一字母 | 重新查询独立表 | 无提交 |
| `GuideCode` | Backspace（删至空） | `GuidePrefix` | 空 | 空 | 无提交 |
| `GuideCode` | Space/Enter（有候选） | `Idle` | 空 | 选择当前页首项 | 返回一个 commit 或 action |
| `GuideCode` | Space/Enter（无候选） | `Idle` | 空 | 空 | 不提交字面分号 |
| `GuideCode` | CandidateSelect | `Idle` | 空 | 选择指定项 | 返回一个 commit 或 action |
| `GuideCode` | Next/PreviousPage | `GuideCode` | 不变 | 只改变页索引 | 无提交 |

额外不变量：

- 从中文键盘进入临时符号页后，分号仍路由到 Rust 引导机；从英文、数字等非中文来源进入符号页时保持普通符号提交。
- 空引导前缀永不枚举整个 guide/action 表。
- 引导查询不访问八个普通系统分类；普通查询不访问 guide/action 表。
- 分类开关和用户词库替换不会改变功能动作表。
- reset、方案切换、会话结束、编辑框切换、键盘隐藏和 Extension 销毁都清除引导状态。
- 切回 `xiaohe` 后 raw、候选和 action 均为空。
- 本状态机没有四码自动上屏、第五码切分或空码切分。
