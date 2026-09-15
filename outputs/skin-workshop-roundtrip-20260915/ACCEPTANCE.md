# 键盘皮肤工坊模拟器验收

日期：2026-09-15。结论：本次修改配色与键盘结构，导出并导入后，在手机、电脑模拟器的实际输入法键盘中均生效。

## 环境与路径

- 手机：Pura 90，127.0.0.1:5555。
- 电脑：MateBook Pro 2in1，127.0.0.1:5557。
- HarmonyOS 6.1.1 / API 24，应用 0.12.0。
- 两端均从应用的“键盘结构与皮肤 → 设计自己的皮肤与布局”入口打开浏览器工坊。
- 完整的编辑、浏览器下载、应用文件选择器导入流程在电脑模拟器完成。手机通过文件选择器导入同一份电脑浏览器实际导出的包，验证跨端应用效果；未将手机独立编辑导出计为通过项。

## 修改与结果

| 项目 | 实际修改 | 验收结果 |
| --- | --- | --- |
| 配色 | 选择樱花粉，手动将面板背景改为 #123456；字母键背景 #FFFAFC | 导出包字段正确，两端实际键盘面板颜色为 #FF123456 |
| 按键顺序 | 将 Q 右移，首行以 W、Q 开头 | 两端实际键盘 W 位于 Q 左侧；电脑点击移动后的 W，编码区得到 w |
| 空格键 | 相对宽度 6.3，显示文字 qa space | 导出结构字段正确，两端实际键盘显示新文字，截图留证 |
| 输入 | 点击 N、I，再点击 qa space | 两端独立验收应用的输入框均收到“你” |
| 保持效果 | 电脑关闭并重新打开验收应用输入窗口 | 自定义结构仍生效 |

实际浏览器导出文件：

- [皮肤包](computer/qa.roundtrip.pc.skin.sy-skin)，571 字节，ID qa.roundtrip.pc.skin。
- [结构包](computer/qa.roundtrip.pc.layout.sy-layout)，540 字节，ID qa.roundtrip.pc.layout。
- [解析后的内容](verified-exports.json)。

## 截图与可复核记录

- [手机实际键盘](phone/actual-keyboard.png)、[手机输入结果](phone/typing-committed.png)。
- [电脑实际键盘](computer/actual-keyboard.png)、[电脑输入结果](computer/typing-committed.png)、[重新打开后的键盘](computer/reopened-keyboard.png)。
- 原始 UI 树和操作检查分别保存在 phone、computer 目录。
- `node outputs/skin-workshop-roundtrip-20260915/verify-packages.cjs`：通过，检查实际导出文件中的颜色、顺序、宽度和文字。
- `node outputs/skin-workshop-roundtrip-20260915/verify-evidence.cjs`：通过，检查两端实际显示、输入结果和原配置恢复。

## 测试后恢复

- 手机恢复：柔和蓝 / 默认键盘结构。
- 电脑恢复：我的纯色皮肤 / 我的键盘结构。
- 两端均删除本次临时导入的 roundtrippc 皮肤和结构；原有模板保留。恢复后的选中行与测试前逐项一致，并重新打开实际键盘确认临时空格文字消失。
- 本次为模拟器功能验收，没有修改产品源码。本结果覆盖上述配色与结构编辑，不代表所有编辑选项或真机兼容性已逐项验收。
