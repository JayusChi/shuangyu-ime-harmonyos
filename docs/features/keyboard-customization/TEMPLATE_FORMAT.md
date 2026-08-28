# 键盘结构与皮肤模板格式

第一版使用项目自有格式，不兼容其他输入法的 `xpa/xp`。结构与皮肤是两个独立安装包，可自由组合。

应用随包内置 3 种结构（默认、宽空格、居中空格）和 4 种皮肤（跟随系统、柔和蓝、樱花粉、墨紫夜色），无需导入即可在设置页选择或通过组合键循环切换。导入包会继续追加到对应列表。

## 打包和导入

结构包是包含 `layout.json` 的 ZIP 文件，推荐扩展名 `.sy-layout`。皮肤包包含 `skin.json` 和可选的 `assets/` 目录，推荐扩展名 `.sy-skin`。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\package-keyboard-customization.ps1 `
  -Kind structure `
  -SourceDirectory examples\keyboard-customization\structure-standard `
  -OutputFile artifacts\sample-standard.sy-layout

powershell -ExecutionPolicy Bypass -File scripts\package-keyboard-customization.ps1 `
  -Kind skin `
  -SourceDirectory examples\keyboard-customization\skin-soft-blue `
  -OutputFile artifacts\sample-soft-blue.sy-skin
```

在应用设置的“数据管理 → 键盘结构与皮肤”中分别导入并选择。

## 给制作方的交付清单

如果制作方要交付可直接导入的软件包，需要分别提供：

- 键盘结构包：一个 `.sy-layout` 文件。它本质上是 ZIP，包根目录必须有 `layout.json`。
- 键盘皮肤包：一个 `.sy-skin` 文件。它本质上是 ZIP，包根目录必须有 `skin.json`；使用图片时还要包含 `assets/` 目录及被引用的 PNG、JPG、JPEG 或 WebP 文件。

结构与皮肤应分成两个包，不要把 `layout.json` 和 `skin.json` 打在同一个包中。当前格式不直接兼容其他输入法的 `xpa/xp` 文件。

如果制作方只交付设计素材、由开发方代为打包，则还需要说明：模板显示名称和唯一英文 ID；26 键每一行的按键顺序、显示文字和相对宽度；皮肤各区域的颜色值，以及面板、字母键、功能键、空格键和回车键分别使用的图片。图片应提供原图，不要只提供整张效果截图。

## `layout.json`

完整示例见 `examples/keyboard-customization/structure-standard/layout.json`。

- `schemaVersion`：当前固定为 `1`。
- `id`：全局唯一，仅允许小写字母、数字、点、横线和下划线，最长 64 个字符；不能使用 `builtin.` 前缀。
- `name`：设置页显示名称，长度 1～64。
- `rows`：3～6 行，每行 1～12 个按键。
- `keys[].id`：白名单逻辑按键，只能重排已有按键，不能注入代码或新动作。
- `keys[].weight`：可选，相对宽度，范围 0.4～8。
- `keys[].label`：可选，只改显示文字，长度 1～8，不改变按键动作。

必要按键为 `letter-a`～`letter-z`、`left-action`、`delete`、`space`、`enter`。`left-action` 在中文键盘解析为 `Esc`，在英文键盘解析为 Shift。

常用可选按键：

| ID | 含义 |
| --- | --- |
| `number` | `ϟ12` 数字键盘入口；长按进入符号键盘 |
| `punctuation-comma` | 空格左侧逗号键 |
| `punctuation-period` | 空格右侧句号键 |
| `input-method-switch` | 系统输入法切换键（仅在当前界面提供时显示） |

旧模板中的 `symbol` 与 `punctuation-comma-period` 仍可导入；运行时会自动移除重复符号入口，并将逗号、句号恢复到空格两侧。

自定义结构只应用于 26 键中英文文字布局。18 键、9 键、数字、电话和符号布局继续使用内置结构，避免改变输入语义。

## `skin.json`

完整示例见 `examples/keyboard-customization/skin-soft-blue/skin.json`。`schemaVersion`、`id` 和 `name` 的规则与结构包相同。

`colors` 可覆盖以下颜色 Token；没有填写的 Token 自动继承当前系统浅色或深色默认值：

- 面板与候选栏：`panelBackground`、`candidateBackground`；
- 键帽：`letterKeyBackground`、`functionKeyBackground`、`spaceKeyBackground`、`primaryFunctionBackground`；
- 按下状态：`letterKeyPressedBackground`、`functionKeyPressedBackground`、`primaryFunctionPressedBackground`；
- 文字与边框：`letterKeyText`、`functionKeyText`、`primaryFunctionText`、`candidateText`、`candidateReading`、`candidateDivider`、`keyBorder`；
- 其他完整 Token 可参考示例代码中的 `KeyboardSkinColors`。

颜色格式只能是 `#RRGGBB` 或 `#RRGGBBAA`。

`images` 支持以下槽位：

| 字段 | 图片用途 |
| --- | --- |
| `panelBackground` | 整个键盘面板背景 |
| `letterKey` | 字母、九键等主键帽 |
| `functionKey` | Shift、删除、模式切换等功能键帽 |
| `spaceKey` | 空格键帽 |
| `enterKey` | 回车键帽 |

图片必须位于包内 `assets/` 目录，只允许 PNG、JPG、JPEG 或 WebP；文件名只能使用英文字母、数字、点、横线和下划线。按键图片会拉伸铺满键帽，设计时应给圆角和边框预留安全区域。

## 安全与限制

- 压缩包最大 12MB，解压后最大 24MB、最多 32 个文件。
- 模板不能包含脚本、网络地址、绝对路径或目录穿越路径。
- 导入先解压到缓存目录并完整校验，再原子替换正式模板；失败时继续使用旧模板。
- 删除正在使用的模板时会先回退到内置默认项。

## 键盘内快捷切换

- 同时按下 `ϟ12 + 空格`：循环切换已安装皮肤。
- 同时按下 `句号 + 空格`：循环切换已安装结构。

两个按键被识别为组合键后不会再执行原来的单键动作。

## 固定编辑手势与字母下滑符号

皮肤和结构模板只改变外观与排列，不覆盖以下固定编辑语义：

- 回删键：上滑撤销最近上屏，下滑删除当前行；
- 回车键：上滑重复最近上屏，下滑恢复最近一次回删或删行内容；
- 26 键字母键：下滑输入设置页为该字母配置的符号。

字母下滑符号在“设置 → 数据管理 → 键盘结构与皮肤”中配置，中文键盘和英文键盘分别保存。配置只在设置页显示，不写入 `layout.json`、`skin.json`，也不在键面增加文字。空值表示该字母不启用下滑动作。
