# 复制反查直通 ofi

在小鹤音形中文模式下，复制一个汉字，再输入 `ofi`，候选区显示本地码表里的编码。选中反查候选，将显示的编码上屏；无结果时显示 `[复制反查]`，选中不输出文字。

- 仅接受单个汉字，可以包含首尾空白，支持扩展汉字，例如 `𠮷`。空剪贴板、非文字、多字和码表未收录的字均无结果。
- 查整个本地音形码表的单字编码，包括已隐藏的全码字分类；四码在前，简码在后，同长度按字母排序，去重后用空格分隔。当前用户词库的增加、删除和固定规则参与查询。结果最多 64 个编码。
- 只在 `ofi` 反查中读取剪贴板；密码框不读取。读取受限时，点击候选区的系统“粘贴”按钮授权并就地刷新，固定候选栏和浮动候选窗均提供入口。不新增受限的 `READ_PASTEBOARD` 权限。
- 反查不修改当前组合、分类开关和词频。候选显示与选中上屏共享同一会话快照；编辑输入码、切换会话和清空组合会作废旧结果。剪贴板内容与查询结果不持久化。

支持客户表达式及原词库中的旧格式，两者均转换为 `DIRECT_CONTROL / clipboard.reverse`，目标参数为空。原始表达式不会被解释执行。

```text
$CC(default(dict.rev(clip()), "[复制反查]"), type(dict.rev(clip())))	ofi
$cmd(querycode,[复制反查])	ofi
```

以上两种写法择一使用，分隔符为 Tab。内置表沿用原有旧格式记录，恢复其功能，不新增重复 `ofi` 项。直通记录仍为 68 条，接受 56 条、隔离 12 条。

`$CC` 的显示与上屏分离语义参见 [清风命令直通文档](https://windinput.com/docs/guides/command-bar)。粘贴授权沿用项目现有 `PasteButton` 方案。

验证入口：

```powershell
pwsh -File scripts/test-clipboard-reverse-import.ps1
pwsh -File scripts/import-shuangyu-customer-lexicon.ps1 -UpdateProject -DirectActionsOnly
cd engine-rust
cargo test --release -p code-table-runtime -p ime-engine -p ime-ffi clipboard_reverse
```

ArkTS 回归：`ClipboardReverseLookup.test.ets` 与 `Stage2Controller.test.ets` 覆盖 Unicode 单字校验、无结果、读取受限、显示与上屏分离、共享快照和过期异步结果。

设备验收：在外部应用复制“你”，输入 `ofi`，确认编码候选；若显示占位提示，点击粘贴后确认编码出现；空格或点击候选上屏编码。用空剪贴板、多字、扩展汉字重复验证，并检查固定栏／浮动窗、实体／虚拟键盘以及退出输入框后不会显示旧结果。
