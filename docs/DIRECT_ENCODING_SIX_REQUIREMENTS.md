# 直通编码六项需求实现说明

更新时间：2026-08-13

## 交付结论

六项需求均已进入正式小鹤音形输入链路，并采用受控动作白名单实现。产品不会解析或执行任意 `$cmd`/`$ddcmd` 字符串；码表编码只映射到经过 Rust、C++ 和 ArkTS 三层校验的有限动作。

小鹤音形引导键为 `;`，当前正式映射如下：

| 编码 | 功能 | 实现行为 |
| --- | --- | --- |
| `;f` | 重复上屏 | 再次插入当前输入会话最近一次成功上屏的文本 |
| `;i` | 撤销上屏 | 仅在 5 秒窗口内、且光标前文本与刚上屏内容完全一致时删除；不一致则拒绝，避免误删 |
| `;o` / `;p` / `;h` / `;j` / `;k` / `;l` | 成对符号 | 一次插入 `「」`、`『』`、`《》`、`“”`、`（）` 或 `〔〕`，随后把光标定位到符号中间 |
| `;n` | End | 在当前编辑器中把光标移动到本行末尾；HarmonyOS 不注入物理 End 键，而是实现相同编辑结果 |

分类词库支持一次提交完整启用集合，启用与关闭在同一个设置事务内完成；无效分类会使整次操作失败，必需的 `core` 分类仍由规范化规则保留。

用户词库页支持添加经系统文件选择器授权的固定来源，并可配置启用状态、优先级以及 `MERGE`（合并）、`APPEND`（补充）、`REPLACE`（替换）模式。手动导入与输入法启动时的自动导入使用同一流程：先读取并校验全部来源，再通过 revision/CAS 原子保存和热重载；任一来源失败时不写入半成品。

## 协议与兼容边界

- 当前 interface/ABI version：`9`。
- 当前 engine version：`0.0.1-quanpin-features`；受控动作本身仍使用版本 8 已冻结的字段合同。
- 新增动作：`REPEAT_COMMIT`、`UNDO_COMMIT`、`MOVE_LINE_END`；原有 `INSERT_PAIR` 保持兼容。
- 撤销和行末定位依赖宿主编辑器提供文本查询、删除和光标定位能力；宿主拒绝或会话已切换时安全失败，不猜测、不重试写入。
- 外部固定文件必须先经系统授权；应用不绕过 HarmonyOS 沙箱读取任意绝对路径。

## 主机验收

- `cargo test --workspace`：PASS。
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`：PASS。
- ArkTS 单元测试：PASS。
- x86_64 与 arm64-v8a Native Release：PASS。
- Release HAP 构建及内容门禁：PASS。
- unsigned Release HAP：`38,843,948` bytes，SHA-256 `EF432ECECD186EB3A14F2B09BB481D63413EA9FC183D48311141DE8E88F4D8DF`。

本轮未执行 HarmonyOS 模拟器或 ARM64 物理真机的六项专项手工验收，因此交付状态为 `IMPLEMENTED / HOST_VALIDATION_COMPLETED / DEVICE_VALIDATION_NOT_RUN`。
