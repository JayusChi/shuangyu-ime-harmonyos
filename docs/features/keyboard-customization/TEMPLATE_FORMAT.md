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
| `punctuation-comma` | 逗号键，默认在空格左侧 |
| `punctuation-period` | 句号键，默认在空格右侧 |
| `input-method-switch` | 系统输入法切换键（仅在当前界面提供时显示） |

逗号、句号可以对调：在工坊“结构”页拖动两个键交换位置，导出 `.sy-layout` 并导入选择；只导出 `.sy-skin` 不会保存键位。动作、上档符号与结构切换组合键跟随逻辑按键，与左右位置无关。中文有候选时，句号键暂时显示“次选”，候选清空后恢复模板文字（默认“。”）。

旧模板中的 `symbol` 与 `punctuation-comma-period` 仍可导入；运行时会自动移除重复符号入口，并在空格所在行补充缺少的逗号、句号。该行已经显式放置两个标点键时，保留模板顺序。

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

- 回删键：上滑撤销最近上屏；下滑时若有编码或候选，先清空待上屏输入，无编码和候选时才删除当前行；
- 回车键：点按时有编码则上屏原始编码，无编码则执行输入框的换行、搜索或发送；上滑重复最近上屏，下滑恢复最近一次回删或删行内容；
- 26 键字母键：下滑输入设置页为该字母配置的符号。

上述回删行为适用于固定和浮动候选，也适用于实体键盘输入后再操作虚拟键盘。实体键盘 Backspace 与虚拟键盘点按回删均先逐码删除，Esc 清空待上屏输入；`oui` 直通保持显式删除当前行的行为。

实体键盘主回车、小键盘回车与虚拟键盘点按回车，在有编码时都只上屏原始编码，例如 `nihc` 上屏为 `nihc`。空格和候选选择仍提交候选。实体键盘在输入编码时以 `[` 翻到上一页、`]` 翻到下一页；到达边界不插入符号，Shift＋方括号仍输入花括号。无组合输入、英文和受限制输入框保持宿主键盘行为。

“键盘字号增减”以屏幕分辨率和密度得到的逻辑短边计算默认字号，平板默认随尺寸放大，再叠加用户调整量。设为 0 或点击“恢复自适应字号”即可恢复当前屏幕的默认值；旋转屏幕保留调整量。

上档符号右边距在“设置 → 键盘与外观 → 键盘尺寸”中调整，默认 10 vp（原固定值为 7 vp），范围 0–16 vp。数值越大，符号越向左移动；该设置随输入法保存，不写入皮肤或结构模板。

有正在组词的文字候选时，上滑回车或回删会先上屏当前高亮候选（默认首选），再分别执行重复或撤销。例如 `kj` 候选为“看”时，上滑回车一次得到“看看”；上滑回删则先提交“看”，再撤销这次提交，保留此前的原文。两步在同一个输入队列任务内执行，候选提交失败或输入会话变化时停止后续操作。没有组词时沿用最近上屏记录；有编码但没有文字候选时保留当前输入。

字母下滑符号在“设置 → 数据管理 → 键盘结构与皮肤”中配置，中文键盘和英文键盘分别保存。配置只在设置页显示，不写入 `layout.json`、`skin.json`，也不在键面增加文字。空值表示该字母不启用下滑动作。

### 下滑符号映射导入与导出

设置页提供“导入映射”和“导出映射”：

- “导出映射”把当前中文、英文两套配置一起保存为 `.sy-swipe` 文件；
- “导入映射”读取 `.sy-swipe` 或 JSON 文件，校验成功后立即保存并生效；
- 导入后仍可逐键调整、保存并再次导出，方便用户维护自己的预设；
- 单个文件最大 64KB，当前 `schemaVersion` 固定为 `1`。

文件是可直接编辑的 UTF-8 JSON，示例见
`examples/keyboard-customization/letter-swipe-symbols.sy-swipe`：

```json
{
  "schemaVersion": 1,
  "type": "shuangyu-letter-swipe-symbols",
  "chinese": {
    "q": "[",
    "w": "]"
  },
  "english": {
    "q": "[",
    "w": "]"
  }
}
```

`chinese`、`english` 的键名只能是 26 个小写字母。没有写出的字母按空值处理；每个符号最多 8 个 UTF-16 代码单元，不能包含换行。制表符使用 JSON 转义值 `"\t"`，且不能与其他字符混用。
