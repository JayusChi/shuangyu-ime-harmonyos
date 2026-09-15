# 皮肤工坊 App 入口（2026-09-15）

## 完成内容

“键盘结构与皮肤”页顶部新增“设计自己的皮肤与布局”卡片，复用 SettingsNavigationRow、18 vp 卡片圆角和现有 SettingsThemeTokens。包含浏览器编辑、导出后返回对应项目导入、关闭前导出保存的说明。重复点击有保护，启动失败会在页面保留提示。

随包携带单文件离线 HTML，按需写入 App 缓存，通过只读 URI 授权交给鸿蒙系统浏览器。系统通用 HTML 处理器实际是文件预览，首轮出现“预览失败”；最终明确打开 com.huawei.hmos.browser / MainAbility，两端加载编辑器成功。未启动服务器、未增加权限。

文件共享调用依据：[华为文件处理应用拉起说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/file-processing-apps-startup)；浏览器目标及 HTML 支持已通过设备包声明核对。

## 验证

- Release clean build、ArkTS 编译、签名通过；覆盖安装手机和电脑，SIGNATURE_RESET=false。
- 编辑器包读写与内置 HTML 一致性检查 **11/11 PASS**。
- Release 资源门禁正反例 PASS，新增缺少 HTML、旧 HTML 拒绝用例；最终 HAP 门禁 PASS，并校验包内 HTML 与源文件一致。
- 手机：入口可见，浏览器加载完整页面，点击导出皮肤包出现下载确认，已确认下载；返回 App 后皮肤导入按钮可见。
- 电脑：入口可见，浏览器加载完整页面，切换樱花粉可预览；结构包实际显示“下载完成”，返回 App 后结构导入按钮可见。
- 手机浅色、深色和电脑宽屏截图已人工核对，与已有卡片、字体和箭头样式一致。手机主题已恢复“跟随系统”。两端停留在入口页。
- 本次没有重新导入或替换用户模板，原有皮肤、结构与输入设置保留。未重跑输入引擎全套单测，也未将前次的 766 项计入本轮。

## 证据

- [手机入口](phone/final-entry.png) / [深色入口](phone/entry-dark.png) / [电脑入口](computer/final-entry.png)
- [手机浏览器](phone/browser-ready.png) / [电脑浏览器](computer/browser-settled.png)
- [手机导出](phone/export-skin.png) / [电脑导出与下载完成](computer/export-layout.png)
- [编辑器测试](editor-tests.log) / [门禁测试](resource-gate-tests.log) / [包门禁](package-gate.log)

安装包：entry/build/default/outputs/default/entry-default-signed.hap，93,504,844 bytes；SHA-256 `C5DF0532B78EF302D956E89A2EE73E62EBD8A4166EDC42B1072C642690FA82FF`。用于本次验收的是开发签名 Release 包，未宣称完成市场发布及全设备验收。
