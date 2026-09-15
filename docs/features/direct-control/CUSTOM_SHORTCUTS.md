# 自定义网页和目录直通

在「用户词库 → 新增或覆盖词条」中选择「直通」，再选择「打开网页」或「打开目录」。

- 网页：填写完整的 http:// 或 https:// 地址、编码，以及可选候选提示。
- 目录：点击「选择目录」，使用系统目录选择器选定当前鸿蒙设备上的文件夹，再填写编码和可选候选提示。
- 点击「保存并立即应用」。音形四码唯一且没有更长编码时，输入最后一码即执行；其他情况点击候选或用空格／编号选择。地址和候选提示不会上屏。
- 未设置候选提示时显示「打开网页」或「打开目录」。普通「上屏文字」直通保持原有行为。

目录打开通过主应用的 UIAbilityContext 拉起系统文件选择器，并将保存的文档 URI 作为默认目录。可以浏览目录内容；选择器关闭后回到主应用。这里不解释 Windows 盘符、cmd 或任意脚本。系统不接受的目录会提示重新选择。

该实现使用 SDK 的 DocumentViewPicker、DocumentSelectMode.FOLDER 和 defaultFilePathUri；参见 [OpenHarmony 选择用户文件](https://github.com/openharmony/docs/blob/master/en/application-dev/file-management/select-user-file.md)。

## 文本导入和导出

每行三个字段，以真正的 Tab 分隔；第三列可为空。与原有 #直 的逗号分隔提示不同，这两类动作以独立第三列保存提示，网址或目录中的逗号不会被拆分。

```text
https://example.com/Help?q=a,b#Part	zzweb#网页	帮助网页
file://docs/storage/Users/currentUser/Documents	zzdir#目录	工作目录
```

目录 URI 建议通过「选择目录」获得，不要将其他设备的路径直接复制过来。音形使用原始编码；双拼和全拼沿用已有用户词库编码规则（全拼条目使用 qp 前缀）。

## 执行约束与回归

- 外部目标以独立用户词库动作保存；普通词条的中文校验没有放宽。
- 音形四码唯一的直通在第四码执行，包括内置网页动作与用户网页／目录直通；同码有其他候选或仍有更长编码时继续等待选择。三字母直通（例如 oix、ojz）保留候选确认。地址与动作提示不作为文字上屏，顶屏和反查切分也不会提交地址。
- 网页与目录共用输入动作串行队列和会话检查。浏览器／选择器由系统负责展示。
- ofa 的顺序固定为 1.[音形] 2.[双拼] 3.[全拼]，三个方案都能再次输入 ofa 切换。

验证日志：项目 outputs/direct-shortcuts-arkts-result.txt、direct-shortcuts-user-lexicon.log、direct-shortcuts-action-tests.log、direct-shortcuts-engine-tests.log 和 direct-shortcuts-release-build.log。
