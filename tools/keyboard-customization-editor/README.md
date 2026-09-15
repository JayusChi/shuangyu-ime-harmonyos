# 双羽键盘皮肤工坊

这是独立的离线可视化编辑器。优先使用 `standalone.html`（交付包中为“双羽键盘皮肤工坊.html”）：所有脚本和样式都在一个文件里，不需要服务器、安装开发工具或联网。开发入口 `index.html` 仍需保留旁边的 JS、CSS 和 vendor 文件夹。

**2026-09-15 App 入口已接入：** 设置 → 键盘与外观 → 键盘结构与皮肤 → **设计自己的皮肤与布局**。App 将随包附带的离线工坊交给鸿蒙系统浏览器打开，不需要另行下载 HTML。设计后分别导出皮肤包、结构包，再回到该页的“键盘皮肤”“键盘结构”导入。入口已在手机、电脑模拟器验证；详见[入口验收记录](https://github.com/JayusChi/shuangyu-ime-harmonyos/blob/542ab009c7ada6bbaa57f2f699e24392bd0f5947/outputs/skin-editor-entry-20260915/ACCEPTANCE.md)。

**2026-09-14 验收状态：三端原生浏览器编辑与导出已通过。** 手机、电脑、平板鸿蒙 6.1 模拟器已验证颜色、五类图片、结构调整与真实下载文件，App 导入、同 ID 结构更新、整机重启保留也已补验。功能验证使用开发签名的 release 构建和完整体验模式；市场发布包受信安装、电脑基础模式面板仍未通过，MatePad Edge 实机未测试。详情见 [修复验收记录](https://github.com/JayusChi/shuangyu-ime-harmonyos/blob/542ab009c7ada6bbaa57f2f699e24392bd0f5947/outputs/keyboard-customization-fix-20260914/ACCEPTANCE.md)，不能据此承诺所有设备及模式均可用。

手机、平板：先将 HTML 保存到文件管理的下载目录，再用浏览器打开。在平板浏览器下载列表点击 HTML 的方式已实测；聊天软件的文件预览页不等同于浏览器运行页面。

## 客户操作

1. **选颜色**：在“配色”页修改皮肤名称、颜色，右侧即时预览。颜色旁的 ↶ 恢复该项为继承系统颜色。
2. **换图片**：在“图片”页选择面板背景、字母键、功能键、空格或回车的图片。不透明图片会覆盖该区域底色；按下键时会使用按下态颜色。
3. **改结构**：切换“结构”页，在右侧点选按键，调整相对宽度、显示文字或位置。也可以拖动两个键交换位置，例如对调逗号和句号；动作与上档符号会随按键移动，两个标点键保留在空格所在行即可。
4. **保存并导入**：点击“导出皮肤包”或“导出结构包”。浏览器会下载 `.sy-skin` / `.sy-layout` 文件，无需再手动压缩。
5. **在设备使用**：把下载的文件传到设备，在输入法“设置 → 键盘与外观 → 键盘结构与皮肤”选择结构或皮肤，再点击对应导入按钮。

只改皮肤时，导出皮肤即可，不需要改结构。皮肤和结构分别保存，两个都修改时请分别导出。

“打开已有模板”支持 `.sy-skin`、`.sy-layout`、单个模板 ZIP 以及 `skin.json` / `layout.json`。打开导出的文件就能继续编辑。直接打开 JSON 时，被引用的图片需要在“图片”页补充；打开皮肤包则会一并读取图片。

同一 ID 再次导入输入法会更新模板。想保留多个版本，请使用不同 ID，例如 `my.skin.pink` 和 `my.skin.blue`。ID 以小写字母或数字开头，仅使用小写字母、数字、点、横线和下划线，不超过 64 字符，不能以 `builtin.` 开头。

**关闭页面之前请导出保存。** 编辑内容只在当前页面内存中，不会自动写回原文件。导出的模板包也就是下一次编辑所用的文件。

## 预览范围

- 预览颜色、五类背景图片、键宽、文字、按键排列和按下状态。支持中英文文字示意、小屏/手机/平板宽度，以及缺省颜色的系统浅色/深色切换。
- 这是浏览器中的近似外观预览，不运行输入引擎。实际字体、系统图标、候选状态、手势、行缩进、键盘高度和设备上的最终显示以实际输入法为准。预览气泡、错误提示等仅在对应设备状态出现，当前预览不展示所有提示状态。
- 结构只影响 26 键中英文文字布局。当前编辑器保留已有行，可移动或交换已有按键；新增行、可选按键需先在结构 JSON 中配置后打开。
- 设备会根据当前模式处理不可用按键，以及在空格行补充逗号、句号。建议把空格、逗号、句号放在同一行，并保留数字入口。
- 不支持自定义输入动作、逐个字母独立图片、按下态图片、字体文件、圆角参数、九宫格切片或其他输入法的 XPA/XP。
- 图片支持 PNG/JPG/JPEG/WebP。每个模板包不超过 12MB，解压后不超过 24MB、最多 32 个文件。工具按输入法现有规则校验后导出。

## 开发维护

源目录：`tools/keyboard-customization-editor/`。`format.js` 由输入法当前 `KeyboardCustomization.ets` 直接生成，`defaults.js` 来自项目示例与默认调色板，避免手写第二套格式规则。无需前端框架或打包服务器。

```powershell
node tools/keyboard-customization-editor/build-editor.cjs
node tools/keyboard-customization-editor/verify.cjs
node tools/keyboard-customization-editor/package-preview.cjs
```

生成脚本默认读取本机 DevEco Studio 的 TypeScript 和 zip.js。其他开发机器可设置 `KEYBOARD_EDITOR_TYPESCRIPT`、`KEYBOARD_EDITOR_ZIPJS` 为对应模块路径。客户无需运行上述脚本。

打包命令从当前源码和 `examples/keyboard-customization/` 生成离线页面、说明、许可及可导入的示例包，默认输出到 `outputs/keyboard-customization-editor-preview/` 和同名 ZIP；可传入输出目录作为第一个参数。输出目录不纳入 Git。测试使用 `fixtures/powershell-packages/` 中的兼容性样本，无需本机历史交付文件。

ZIP 读写依赖随包提供的 zip.js（BSD-3-Clause），许可证见 `vendor/zip.js-LICENSE.txt`。运行不请求远程脚本、不上传客户图片。
