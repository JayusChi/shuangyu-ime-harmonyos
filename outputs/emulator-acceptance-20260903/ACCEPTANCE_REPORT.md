# 双羽输入法客户反馈项——电脑模拟器验收

验收日期：2026-09-03  
结论：**不通过，当前版本不能判定为“全部完成”**。

## 验收环境

- 设备：DevEco Studio 电脑模拟器，`2in1 / x86_64`
- 系统：`OpenHarmony-6.1.1.125`，API 24
- 被测包：`com.corrosion.shuangyuime`，版本 `0.7.0 (7000000)`
- 输入方案：虚拟键盘与实体键盘均设置为 `26 键小鹤音形`
- 编辑器：独立验收应用 `com.example.shuangyuime.acceptance`，避免仅在输入法自身界面内自测
- 操作方式：实体键盘路径使用 HDC 键盘事件；虚拟键盘路径使用模拟器触控事件

## 总体结果

| 模块 | 结果 | 说明 |
| --- | --- | --- |
| 实体键盘分号引导 | **部分通过** | 直接上屏、成对符号居中、重复通过；撤销和移到行末失败 |
| 中英文下滑预设 | **通过** | 推荐预设、实际下滑字符、留空键和 Tab 均符合要求 |
| 候选展开 | **基本通过** | `obh`、空格上滑、右侧展开按钮、全键盘展开页、分页与返回均通过；另发现长万能键候选固定栏右缘裁切 |
| 架空行与底部系统键 | **通过** | 架空行、隐藏标识、系统输入法选单和隐藏键盘按钮均符合要求 |
| 中英文符号页 | **通过** | 中文符号集合、成对上屏并居中、英文页右上角 `/` 均通过 |
| 智能标点 | **失败** | 两次快速上滑仍得到两个中文符号，没有替换成英文符号 |
| 自动化回归 | **通过** | ArkTS：607/607 PASS，但没有拦住本次模拟器集成缺陷 |

## 明确失败项

### 1. 实体键盘 `;i` 不能撤销刚上屏内容

- 操作：`;a` 上屏 `！`，随后立即输入 `;i`。
- 预期：撤销刚上屏的 `！`，内容为空。
- 实际：内容变成 `！;`。
- 证据：[physical_undo_fast.jpeg](physical_undo_fast.jpeg)、[physical_undo_fast.json](physical_undo_fast.json)
- 运行日志曾报告：`undo rejected because text before cursor no longer matches`。

### 2. 实体键盘 `;n` 没有把光标移到末尾

- 操作：`;j` 输入 `“”`，再输入 `;n`，随后输入 `;a`。
- 预期：`“”！`
- 实际：`“！”`，说明光标仍在成对符号中间。
- 证据：[physical_line_end_proof.jpeg](physical_line_end_proof.jpeg)、[physical_line_end_proof.json](physical_line_end_proof.json)

### 3. 中文智能标点三条均失败

在 500ms 设置窗口内，分别使用 80ms 和 250ms 间隔复测：

| 操作 | 预期 | 实际 |
| --- | --- | --- |
| 句号键连续上滑两次 | `?` | `？？` |
| N 键连续上滑两次 | `/` | `、、` |
| M 键连续上滑两次 | `:` | `：：` |

证据：[smart_chat_250_result.json](smart_chat_250_result.json)、[smart_n_250_result.json](smart_n_250_result.json)、[smart_m_250_result.png](smart_m_250_result.png)、[smart_m_250_result.json](smart_m_250_result.json)

### 4. 长万能键候选在固定候选栏右缘仍有裁切

- `obh` 本身已完整显示，空格上滑也可以展开。
- 万能键较长候选列表中，右侧最后一项会被“展开”按钮挤压，只剩约 5px 可见；展开页中显示正常。
- 证据：[universal_ju.jpeg](universal_ju.jpeg)、[universal_ju.json](universal_ju.json)
- 此项不阻断展开功能，但固定候选栏的视觉验收仍不完整。

## 通过项明细

### 实体键盘

- `;q` 可直接上屏 `：“`，无需补空格：[physical_q_yinxing_chat2.jpeg](physical_q_yinxing_chat2.jpeg)
- 成对符号直接上屏且光标居中：`;j` 后再输入 `;a` 得到 `“！”`：[physical_pair_center_proof.jpeg](physical_pair_center_proof.jpeg)
- `;f` 可重复刚上屏内容：`！` 变为 `！！`：[physical_repeat_after.jpeg](physical_repeat_after.jpeg)

### 下滑符号与自定义

- 设置页有“推荐预设 / 导入映射 / 导出映射 / 清空 / 保存”入口：[customization_swipe_section.jpeg](customization_swipe_section.jpeg)
- 中文 A/S/H/J/K/L 实测得到 `——……“”（）`：[zh_swipe_uinput_symbols.jpeg](zh_swipe_uinput_symbols.jpeg)
- 中文 X/C/V/B/N 下滑留空；Z 下滑输入真实 Tab：[zh_swipe_uinput_blank_xn.json](zh_swipe_uinput_blank_xn.json)、[zh_swipe_uinput_tab.jpeg](zh_swipe_uinput_tab.jpeg)
- 英文 A/S/F/G/H/J/K/L 实测得到 `—…¥~{}^|`；Z 下滑输入真实 Tab：[en_swipe_uinput_symbols.jpeg](en_swipe_uinput_symbols.jpeg)、[en_swipe_uinput_tab.jpeg](en_swipe_uinput_tab.jpeg)
- ArkTS 回归包含下滑映射导入导出往返测试并通过。

### 候选与空格手势

- 长按空格可在中英文键盘间切换：[space_longpress_toggle.jpeg](space_longpress_toggle.jpeg)
- `obh` 候选栏完整显示 `灬 / 虍 / 黑 / 余下`，右侧有“展开”按钮：[candidate_obh_valid.jpeg](candidate_obh_valid.jpeg)
- `obh` 可通过右侧按钮展开，也可通过空格上滑展开：[candidate_obh_expanded_button.jpeg](candidate_obh_expanded_button.jpeg)、[candidate_obh_expanded_space_swipe2.jpeg](candidate_obh_expanded_space_swipe2.jpeg)
- 展开页占据整个键盘区，下部有“上一页 / 第 1 页 / 下一页 / 返回键盘”。
- 万能键候选会显示所代表的编码，例如 `居 uk / 局 u / 具 q / 举 x / 剧 ud`：[universal_ju.jpeg](universal_ju.jpeg)
- 浮动候选选中项背景比普通项更大，当前模拟器中可见。
- 编码会嵌入当前编辑器显示，`obh`、万能键编码均可见。

### 架空行、系统键和外观

- 架空行背景与键盘背景一致；下方逗号、句号、左右光标区域不显示文字或图标。
- 中文键盘 `ϟ12` 使用普通深色字体，不是红色：[candidate_obh_valid.jpeg](candidate_obh_valid.jpeg)
- 左下系统键会弹出系统输入法选单，而不是应用内部键盘选单；选单含“中文26键 / 中文双拼 / 中文五笔 / 双羽输入法”：[system_ime_chooser.png](system_ime_chooser.png)
- 右下隐藏键盘按钮可正常收起键盘：[hide_keyboard_button.png](hide_keyboard_button.png)

### 符号页

- 中文符号页字符与需求一致：[chinese_symbols_actual.png](chinese_symbols_actual.png)、[chinese_symbols_actual.json](chinese_symbols_actual.json)
- 成对符号一次上屏且光标居中：点击 `（）` 后点击 `＃`，实际得到 `（＃）`：[chinese_pair_center.json](chinese_pair_center.json)
- 英文符号页右上角已改为 `/`：[english_symbols_page.png](english_symbols_page.png)

## 自动化回归

命令：

```powershell
hvigorw.bat --no-daemon --mode module -p module=entry@default test
```

结果：`Tests run: 607, Failure: 0, Error: 0, Pass: 607, Ignore: 0`，`BUILD SUCCESSFUL`。

自动化通过不能替代本次集成验收；当前至少需要修复 `;i`、`;n` 和三条智能标点后再进行回归验收。
