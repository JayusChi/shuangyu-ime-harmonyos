# 输入法共享皮肤授权接入验收（2026-09-14）

## 配置与构建

- 用户提供 `C:/Users/CX-03/Downloads/shuangyuime_debug_shared_20260914Debug.p7b`。
- 包名 `com.corrosion.shuangyuime`；类型 debug；共享组 `group.1516753898738609081`。
- Profile 中开发证书与本地 .cer 证书链的叶子证书、旧调试 Profile 一致，沿用原签名材料。初步只读取根证书造成的“不匹配”判断已更正。
- 已配置 `KeyboardCustomizationStorageConfig.ets`、输入法扩展 `dataGroupIds`、本机 build-profile.json5 的 default 签名 Profile。随后收到新发布 Profile，两份新 Profile 均归档至 `D:/CompanySecrets/HarmonyOS/shuangyuime/profile/`，default/release 签名路径已同步更新；证书、私钥保持原配置，旧 Profile 保留。
- default、internalDebug、release 严格检查现均通过。根目录 `profile-check-release.log` 保留首次使用旧 Profile 的失败记录；新发布配置结果见 `release/profile-check.log`。
- 构建使用正式功能源码（release 编译模式、default 产品）及新开发签名；不是客户发布签名。
- 最终包：`shuangyuime-0.12.0-shared-debug-signed.hap`。
- SHA-256：`C3407FAA1EBC73E460D06A62FEF5980F695A9A55DB75D123D13F25DB76BAF688`。
- 原生双 ABI 构建、ArkTS 编译、HAP 签名通过。见 `build-debug-signed.log`、`build-layout-refresh.log`、最终 `build-image-uri.log`。
- 存储契约 8 项通过（本轮终端输出）；模板领域 14 项通过，见 `domain-tests-final.log`。

## 本轮发现并修复

1. 同一结构 ID 在 getGroupDir 异步就绪前后对应不同内容，而 ForEach 仍复用旧行。根据实际结构内容变化更新响应式渲染版本，兼顾首次加载和同 ID 替换；普通候选刷新不递增版本。
2. ArkUI 背景图片不能按普通文件系统路径引用共享图片。改为 `file:///...` 并编码路径片段，避免只显示颜色。领域测试同步校验 URI。

## 测试材料与设备

使用之前从桌面浏览器编辑器实际导出的 `chrome-layout.sy-layout`、`chrome-tablet.sy-skin`、`chrome-images.sy-skin`，从模拟器自带浏览器下载，再通过 App 的系统文件选择器导入。

结构检查为 W/Q 换位、空格权重 6.3、标签 TEST；纯色检查为粉色键面与 `#12345680` 半透明面板；图片检查覆盖 panelBackground、letterKey、functionKey、spaceKey、enterKey 五个槽位（测试包有意使用同一张圆角键图片）。测试素材不以美观或文字对比度作为验收目标。

本轮端口与 9 月 9 日不同，以设备查询为准：5555 是 phone，5557 是 2in1，5559 是 tablet；均报告 OpenHarmony-6.1.1.125。平板为 MatePad Pro 13 模拟器，不是 MatePad Edge 实机。

## 已验证结果

- 手机：完整体验模式，浏览器下载后，通过“浏览 → 我的手机 → Download → 浏览器”选择文件，结构包和图片包均导入成功。最终版本实际键盘同时显示 W/Q 换位、TEST 宽空格、修改后的配色和五种图片，见 `device-evidence/127.0.0.1_5555/phone-final-result.png`、`phone-final-tree-before.json`、`phone-runtime.log`。最终覆盖安装见 `install-phone-image-uri.log`。
- 电脑：完整体验模式，实际外部应用键盘的自定义颜色、W/Q 换位、TEST 宽空格与五种图片显示通过。最终截图 `device-evidence/127.0.0.1_5557/pc-image-stable-focus.png`，布局树为同名前后的 JSON。
- 平板：完整体验模式，系统选择器导入成功，外部应用键盘的自定义结构与五种图片同时显示通过。最终截图 `device-evidence/127.0.0.1_5559/tablet-uri-result.png`，`tablet-final-tree-before.json` 含 TEST。
- 电脑重建输入法进程后已重新显示结构和图片；共享读取日志见 `pc-final-runtime.log`，平板见 `tablet-runtime.log`。
- 所有安装均保留应用数据，未重置签名或卸载清空。见 `install*.log`。

## 尚未通过或未覆盖

- 电脑基础模式下，系统面板创建返回 code 1（error is out of definition），同时设置读到默认值。尚未定位为系统或应用原因，不能宣称基础模式通过；测试后已恢复完整体验模式。证据 `pc-runtime.log` 中 15:53:25 之后的 SettingsController / InputPanelController 日志。
- 新发布 Profile 已接入，发布签名包已构建并通过发布包检查，详见 `release/RELEASE.md`。尚未安装该发布签名包，以上三端运行证据来自调试签名包。
- MatePad Edge 实机按用户要求暂不验收；此轮模拟器结果不能保证指定实机及系统版本。
- 未完成设备重启、损坏包、同 ID 覆盖的全部三端设备回归；主机存储测试覆盖部分对应契约。
- 浏览器编辑器在三端的完整交互回归沿用历史记录，本轮重点是下载、系统选择器导入、共享读取及实际键盘渲染，不是重新验收所有编辑控件。

## 操作边界

本地 8774 端口服务仅为提供三份固定验收包，不是产品服务器部署。没有上传用户文件。电脑验收时将 App 的“实体键盘”设置改为“虚拟键盘”，最终三端保留完整体验模式与测试模板便于查看。发布 Profile 已更新；客户完整交付验收仍需处理上述未通过项。
