# 实体键盘快符 End 与成对符号跳出修复

客户反馈：备忘录中快符 `;n` 模拟 End 不成功，Tab、回车也不能跳出成对符号。

## 代码定位与修改

- 原 `moveToLineEnd` 和 `PairInsertionService.jumpOut` 只等待 `selectByRange` 返回，没有核对光标。选区接口返回成功但编辑器未移动时，End 会误报成功，跳出逻辑还会提前弹出待跳出的符号记录。这是与客户现象一致的代码缺陷；尚未通过客户备忘录日志确认其具体接口行为。
- 两条路径现在复用 `PairCursorPositioner.advance`：先核对光标及右侧文本，尝试选区定位，等待位置稳定；选区被拒绝或无效且原位置仍可验证时，使用 `CURSOR_RIGHT`，逐步验证实际位移。只有移动被证实后才完成跳出。
- `LineEndCursorMover` 保留按当前逻辑行定位的语义，在 CR/LF 前停止，查询窗口不拆开 UTF-16 代理对。发生会话变化或未知位移后终止，不用旧坐标强行恢复。
- Tab 保留独立的路由命令；Tab 和回车在串行执行时重新检查已完成的成对符号插入，覆盖快速连按时按键到达早于符号定位完成的情况。正在组词时 Tab 仍取消组词，Esc 保持取消行为。

## 验证

2026-09-09：

- `node scripts/test-pair-navigation.cjs`：20/20 通过。运行在主机，模拟 IME API，包含真实 `PairInsertionService` 的嵌套符号插入/跳出流程。
- `hvigorw --no-daemon --mode module -p module=entry@default test`：657 项通过，Failure 0，Error 0，Ignore 0；核对实际 `test_result.txt`，未仅依赖构建退出码。
- 覆盖选区静默无效、抛错、延迟生效、两个移动接口均无效、嵌套及多字符右符号、Unicode 代理对、CR/LF/CRLF、长行分段读取、光标/会话变化及快速 Tab/主回车/小键盘回车。
- 日志：`outputs/pair-navigation-host-tests.log`、`outputs/pair-navigation-arkts-tests.log`、`outputs/pair-navigation-arkts-result.txt`。

未安装本次修改到设备。当前仅检测到模拟器，未完成客户设备的备忘录实测。

## 客户备忘录复验步骤

1. 小鹤音形模式，实体键盘输入 `;k` 得到 `（|）`（`|` 表示光标），输入并上屏文字。
2. 分别重新建立符号场景，验证 `;n`、Tab、主回车、小键盘回车。光标应移到右符号后；Tab/回车跳出不插入制表符或换行。
3. 在 `（文字|）尾文` 场景，`;n` 应到当前行末尾；Tab/回车只越过右符号。末尾有换行时不进入下一行。
4. 验证 `;o`、`;p`、`;h`、`;j`、`;l` 及嵌套符号；快速输入快符后紧接 Tab/回车，确认没有丢失跳出动作。
5. 正在组词时 Tab 仍取消组词；无待跳出的符号时空闲 Tab/回车仍交由编辑器正常处理。
