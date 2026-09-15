# 双羽输入法：键盘结构与皮肤模板

适用于当前项目的 schemaVersion 1 导入格式。此文件夹包含可编辑源文件、打包脚本和已打好的示例包，无需安装开发工具即可修改并打包。

## 先试一次导入

1. 将 `packages/my-color-skin.sy-skin` 传到安装输入法的设备上。
2. 打开输入法的“设置 → 数据管理 → 键盘结构与皮肤”。
3. 点击“导入皮肤包”，选择该文件。成功后会自动应用“我的纯色皮肤”。
4. 打开文字输入框查看效果。仅改皮肤时，无需导入结构包。
5. 要试结构，再点“导入结构包”，选择 `packages/my-keyboard.sy-layout`。

外层的模板合集 ZIP 用于解压和编辑；应用中请选择里面的 `.sy-layout` / `.sy-skin`，不要选择整个合集。

## 文件对应关系

| 可编辑源文件 | 打包后导入文件 | 用途 |
| --- | --- | --- |
| `structure-standard/layout.json` | `packages/my-keyboard.sy-layout` | 标准 26 键、宽空格结构 |
| `skin-color-blue/skin.json` | `packages/my-color-skin.sy-skin` | 纯色皮肤，建议先用这一份改颜色 |
| `skin-image-blue/skin.json` 和 `assets/` | `packages/my-image-skin.sy-skin` | 带字母键、功能键 PNG 的图片皮肤 |

`build-packages.ps1` 会重新生成这三个包；`package-keyboard-customization.ps1` 是它使用的打包工具。

## 修改、打包、再导入

1. 先解压合集。用文本编辑器打开 `skin-color-blue/skin.json`。
2. 修改 `name` 为显示名称，例如“我的粉色皮肤”。
3. 先试把 `panelBackground` 改为 `#F7E4EA`、`primaryFunctionBackground` 改为 `#D77C9A`，保存为 UTF-8 JSON。
4. 在本文件夹打开 PowerShell，运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-packages.ps1
```

5. 把新生成的 `packages/my-color-skin.sy-skin` 传到设备，再次点“导入皮肤包”。

重新导入同一个 `id` 会更新该模板；想同时保留几个版本，请分别使用不同的 `id`，如 `my.skin.pink`、`my.skin.blue`。`name` 只是显示名称，改名不会创建不同 ID 的模板。打包脚本会覆盖 `packages/` 下对应的三个输出文件。

JSON 中不要添加注释，不要在最后一个字段后面留逗号，不要把文件保存成 `.json.txt`。不要把单个 JSON 直接改后缀当作导入包。

没有 Windows 电脑也可手动打包：把源文件夹里面的 `skin.json` 和需要的 `assets/` 压成 ZIP，再把 `.zip` 改为 `.sy-skin`；结构包同理。打开压缩包后，第一层应直接看到 `skin.json` 或 `layout.json`。

## 皮肤颜色字段

纯色模板包含当前支持的全部 24 个颜色字段，`images` 保持 `{}`。建议使用 `#RRGGBB` 六位十六进制颜色。模板中的 `previewShadow: "#00000000"` 表示透明阴影。删掉某个颜色字段后，该项会继承当前系统浅色或深色默认值；一份模板至少要保留一种有效颜色或图片。

| 字段 | 对应区域 |
| --- | --- |
| `panelBackground` | 键盘面板背景 |
| `candidateBackground` | 候选栏背景 |
| `letterKeyBackground` | 字母等主键帽背景 |
| `functionKeyBackground` | 普通功能键背景 |
| `spaceKeyBackground` | 空格背景 |
| `primaryFunctionBackground` | 回车等主要功能键背景 |
| `modeKeyBackgroundEnglish` | 英文模式切换键背景 |
| `modeKeyBackgroundChinese` | 中文模式切换键背景 |
| `letterKeyPressedBackground` | 字母键按下背景 |
| `functionKeyPressedBackground` | 功能键按下背景 |
| `primaryFunctionPressedBackground` | 主要功能键按下背景 |
| `letterKeyText` | 字母键文字 |
| `functionKeyText` | 功能键文字 |
| `primaryFunctionText` | 主要功能键文字 |
| `modeKeyTextEnglish` | 英文模式切换键文字 |
| `modeKeyTextChinese` | 中文模式切换键文字 |
| `errorText` | 错误提示文字 |
| `previewBackground` | 按键预览气泡背景 |
| `previewText` | 按键预览文字 |
| `previewShadow` | 按键预览阴影 |
| `candidateText` | 候选文字 |
| `candidateReading` | 候选栏编码或读音文字 |
| `candidateDivider` | 候选分隔线 |
| `keyBorder` | 键帽边框 |

部分按键会根据当前模式和状态选择不同颜色。此模板是固定配色；它没有独立的日间、夜间两套配置。

## 图片皮肤怎么改

图片版已有两张可替换素材：

- `skin-image-blue/assets/letter-key.png`：字母等主键帽。
- `skin-image-blue/assets/function-key.png`：普通功能键帽。

直接用自己的 PNG 替换同名文件，再运行打包脚本即可。图片只画底图，按键文字由程序叠加；不要把字母写死在共用键帽图里。不透明图片会遮住对应的背景色，单纯改颜色时建议先用纯色模板。

`images` 最多支持以下五个槽位。下面是完整字段示意，只有把引用的图片实际放入 `assets/` 后才能使用：

```json
"images": {
  "panelBackground": "assets/panel.png",
  "letterKey": "assets/letter-key.png",
  "functionKey": "assets/function-key.png",
  "spaceKey": "assets/space-key.png",
  "enterKey": "assets/enter-key.png"
}
```

分别对应面板、字母键、功能键、空格键、回车键。可以只填需要的项；不使用的项直接删除，不要填空字符串。支持 PNG、JPG、JPEG、WebP，小写扩展名；文件名以英文字母或数字开头，其余使用英文字母、数字、点、横线或下划线，图片直接放在 `assets/` 下。

图片会拉伸铺满对应区域，没有固定必需尺寸。按键图片需预留圆角、边框空间；空格较宽，适合单独画横向图片。当前导入格式不提供逐个字母的不同图片、按下态图片、九宫格切片、字体或圆角数值字段。

## 键盘结构怎么改

当前结构示例为：

```text
Q W E R T Y U I O P
A S D F G H J K L
Esc/Shift Z X C V B N M 删除
ϟ12 逗号      空格      句号 回车
```

`rows` 数组决定行顺序，每行 `keys` 数组决定按键顺序。例如：

```json
{ "id": "space", "weight": 5.2, "label": "空格" }
```

- `id`：按键的逻辑 ID，不能随意改名或重复；`label` 只改显示文字，不改动作。
- `weight`：同一行内的相对宽度，范围 0.4～8；未填写时由内置按键规格决定。
- `label`：可选，长度 1～8；字母键通常不填，保留自动大小写。
- `kind`：可选行类型，支持 `top_letters`、`middle_letters`、`bottom_letters`、`auxiliary`、`bottom_actions`。
- 总计 3～6 行，每行 1～12 键。
- 必须保留 `letter-a` 到 `letter-z`、`left-action`、`delete`、`space`、`enter`，每个只出现一次。
- `left-action` 在中文下为 Esc，在英文下为 Shift。
- 常用可选键：`number`、`punctuation-comma`、`punctuation-period`、`input-method-switch`。系统输入法切换键仅在当前界面提供时显示。

自定义结构应用于 26 键中英文文字布局。18 键、9 键、数字、电话和符号布局使用内置结构。运行时会处理符号入口以及空格两侧逗号、句号的位置；模板不定义新动作或修改固定手势。

## 格式限制和常见问题

- 两类模板的 `schemaVersion` 固定为 `1`。
- 模板 `id` 以小写字母或数字开头，仅含小写字母、数字、点、横线、下划线，最长 64 字符，不能以 `builtin.` 开头。
- `name` 去除首尾空格后长度 1～64。
- 结构和皮肤分别打包，不混在一个导入包里。本格式不直接兼容其他输入法的 XPA/XP。
- 每个导入包最大 12MB，解压后最大 24MB，最多 32 个文件。
- 提示缺少 `skin.json` / `layout.json`：检查包内目录层级，并确认点的是对应的导入按钮。
- 提示图片缺失：检查 JSON 中的路径、文件名大小写和 `assets/` 内文件是否一致。
- 修改后没变化：确认已重新打包、传输并导入最新文件；图片背景请检查是否被图片覆盖。
- 想恢复：在同一设置页选择内置结构或“跟随系统”皮肤。

这份交付依据当前项目源码整理，交付包会进行本地格式和资源检查；设备上的最终显示效果请通过实际导入确认。
