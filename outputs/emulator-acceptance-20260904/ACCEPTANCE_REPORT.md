# 双羽输入法客户反馈项——电脑模拟器最终验收

验收日期：2026-09-04  
最终结论：**全部通过，可以验收。** 2026-09-03 的首次验收报告已被本报告取代。

## 验收环境

- 设备：DevEco Studio 电脑模拟器，`2in1 / x86_64`，分辨率 `3120 × 2080`
- 系统：`OpenHarmony-6.1.1.125`，API 24
- 被测输入法：`com.corrosion.shuangyuime`，完整体验模式
- 独立编辑器：`com.example.shuangyuime.acceptance`，用于验证真实跨应用编辑器连接
- 输入方案：`26 键小鹤音形 / 小鹤音形`
- 操作：实体键盘使用 HDC 键盘事件；虚拟键盘使用模拟器真实触控事件
- 最终安装包：`entry/build/default/outputs/default/entry-default-signed.hap`
- HAP 大小：`92,823,853 bytes`
- HAP SHA-256：`3580ACFBB91E5B476CFB82067FE3BD66F441F2EDE1163B7C380AD962FFF6D03B`

## 总体结果

| 验收模块 | 结果 | 实机结果摘要 |
| --- | --- | --- |
| 实体键盘分号引导 | **通过** | 单符号和成对符号直接上屏；成对符号光标居中；`;f` 重复、`;i` 撤销、`;n` 行末均正常 |
| 中英文下滑符号 | **通过** | 中英文推荐预设、留空键、Tab 和导入导出均符合要求；英文 G 已修正为连续输入 `\~` |
| 候选栏与展开页 | **通过** | `obh` 无裁切；右侧按钮和空格上滑均可展开；展开页覆盖键盘并具有翻页、返回键 |
| 万能键与编码 | **通过** | 万能键候选显示实际编码，展开功能正常 |
| 架空行与底部系统键 | **通过** | 高度、背景、隐藏辅助键、系统输入法选单和隐藏键盘均正常 |
| 中英文符号页 | **通过** | 中文符号齐全，成对符号一次上屏且光标居中；英文页右上角为 `/` |
| 智能标点 | **通过** | 句号、N、M 连续上滑分别得到 `?`、`/`、`:` |
| 浮动候选 | **通过** | 选中项背景加大，`obh` 候选完整显示，编码提示保留 |
| 自动化与发布门禁 | **通过** | ArkTS 全量单测、Release 构建、签名安装、Release HAP 内容门禁全部通过 |

## 逐项验收记录

### 1. 实体键盘

- `;a` 直接上屏 `！`，无需额外空格。
- `;j` 一次上屏 `“”`，光标位于引号中间。
- `;f` 可重复刚上屏内容，`！` 变为 `！！`。
- `;i` 可撤销刚上屏的内容，字段恢复为空：[physical_undo_pass.json](physical_undo_pass.json)。
- `;j` 后执行 `;n` 再输入 `;a`，实际得到 `“”！`，证明光标已移到行末：[physical_line_end.png](physical_line_end.png)、[physical_line_end.json](physical_line_end.json)。
- 单符号、成对符号和重复的原始实机证据继续有效：[首次验收实体键盘证据](../emulator-acceptance-20260903/ACCEPTANCE_REPORT.md#实体键盘)。

### 2. 虚拟键盘下滑符号

- 中文预设：A=`——`、S=`……`、H/J=`“”`、K/L=`（）`、Z=Tab，X 至 N 为空。
- 英文预设：A=`—`、S=`…`、F=`¥`、G=`\~`、H/J=`{}`、K=`^`、L=`|`、Z=Tab。
- 英文其余按键实测证据：[english_down_swipes.png](english_down_swipes.png)。
- 最终 Release 包重新安装后，英文 G 高速下滑实际在字段末尾追加两个字符 `\~`：[final_g_swipe_pass.jpeg](final_g_swipe_pass.jpeg)、[final_g_swipe_pass.json](final_g_swipe_pass.json)。
- 旧 schema 18 的默认英文映射会自动迁移到 schema 19；用户已自行修改的映射不会被覆盖。
- 推荐预设、逐键修改及整套映射导入/导出均有自动化回归覆盖。

### 3. 候选展开与万能键

- 输入 `obh` 后，固定候选栏只布局四个完整候选 `灬 / 虍 / 黑 / 余下`，右侧“展开”按钮完整可见，无第五项残片：[candidates_obh.png](candidates_obh.png)。
- 点击“展开”进入覆盖整个键盘区域的候选页；底部显示“上一页 / 第 1 页 / 下一页 / 返回键盘”：[candidates_obh_expanded.png](candidates_obh_expanded.png)。
- 候选数不少于 3 时，空格上滑可进入同一展开页：[candidates_space_swipe_expanded.png](candidates_space_swipe_expanded.png)。
- 万能键候选显示其实际编码，例如 `砪 u / 初 p / 除 e / 储 r`：[candidates_wildcard_virtual.png](candidates_wildcard_virtual.png)。
- 长按空格可切换中英文键盘：[english_keyboard_longpress.png](english_keyboard_longpress.png)。

### 4. 架空行、系统键与外观

- 架空行与字母键等高，候选栏保持较低高度；架空行背景与键盘背景一致。
- 最下方逗号、句号、左移、右移触控区保留功能但不显示文字或图标。
- `ϟ12` 使用普通功能键文字色，不再使用红色。
- 左下系统键弹出系统输入法选单，而不是应用内部键盘选单；选单中可见“中文26键 / 中文双拼 / 中文五笔 / 双羽输入法”：[system_ime_picker.png](system_ime_picker.png)。
- 右下隐藏按钮可收起键盘：[after_close.png](after_close.png)。

### 5. 符号页

- 中文符号页与客户清单一致，包括 `＃＆￥……——·々`、成对单双引号、六组成对括号、运算符和回删：[chinese_symbol_page.png](chinese_symbol_page.png)。
- 点击 `（）` 后再输入 `＃`，实际字段为 `（＃）`，证明成对符号一次上屏且光标居中：[chinese_pair_center.png](chinese_pair_center.png)、[chinese_pair_center.json](chinese_pair_center.json)。
- 英文符号页右上角为 `/`：[english_symbol_page.png](english_symbol_page.png)。

### 6. 智能标点

在模拟器真实触控链路中连续上滑两次：

| 手势 | 实际结果 | 证据 |
| --- | --- | --- |
| 句号键连续上滑 | `?` | [smart_period.png](smart_period.png)、[smart_period.json](smart_period.json) |
| N 键连续上滑 | `/` | [smart_n.json](smart_n.json) |
| M 键连续上滑 | `:` | [smart_m.png](smart_m.png)、[smart_m.json](smart_m.json) |

实机自动化触控的两次事件间隔约为 777ms，因此默认智能标点窗口调整为 1000ms；旧默认值自动迁移，用户自定义值保持不变。

### 7. 浮动候选与嵌入编码

- 实体键盘模式输入 `obh` 后，浮动候选完整显示 `1. 灬  2. 虍  3. 黑  4. 余下`，右侧无裁切；第一项选中背景已加大：[floating_obh.png](floating_obh.png)、[floating_obh.json](floating_obh.json)。
- 万能键候选继续显示嵌入编码，见 [candidates_wildcard_virtual.png](candidates_wildcard_virtual.png)。

## 自动化与发布验证

- ArkTS 全量单元测试：`BUILD SUCCESSFUL`。
- Release 清理构建：`BUILD SUCCESSFUL`。
- 签名包覆盖安装：`install bundle successfully`。
- 输入法重启后读取配置：`schemaVersion=19`、`keyboardProfileId=xiaohe-yinxing-26`、`schemeId=xiaohe-yinxing`、`smartPeriodTimeoutMs=1000`。
- Release HAP 内容与资源门禁：`RELEASE_HAP_VERIFY_RESULT=PASS`。
- 相关修改执行 `git diff --check`：无空白错误。

综上，本轮列出的客户修改项和新增项均已在电脑模拟器端完成修复并通过最终验收。
