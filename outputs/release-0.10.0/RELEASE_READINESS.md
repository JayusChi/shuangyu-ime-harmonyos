# 0.10.0 客户测试构建核查

日期：2026-09-10。结论：**在已明确排除自定义结构／皮肤导入能力的范围内，可以交客户测试，未发现新的阻塞问题。** 用户已明确接受“注明限制后构建测试 APP”。不将此结论外推为全部真机、宿主应用均已验证。

## 本轮范围

本轮应用改动仅为 AppScope 版本元数据：0.10.0 / 10000000 / build 1，另新增交付说明和核查脚本。未为打包改写输入引擎、控制器、存储或按钮业务逻辑。工作区此前的客户反馈修复和设置 UI 迁移整体纳入新包；历史 0.9.0 交付物保持不变。

## 验证结果

| 检查 | 结果与证据 |
| --- | --- |
| ArkTS 全量测试 | 本轮新执行 686 PASS，0 Failure / 0 Error / 0 Ignore；[arkts-test-result.txt](arkts-test-result.txt)，本次成功补齐前一轮 Previewer 崩溃造成的测试缺口 |
| 共享存储契约测试 | 8 PASS；[customization-host-tests.log](customization-host-tests.log)，宿主模拟测试不能代替华为设备授权 |
| 业务逻辑保留 | 599 个基线文件中 593 个不变，6 个既有 UI 文件允许修改；原业务方法 17 + 17 + 9 个保持；[source-preservation.log](source-preservation.log) |
| Native | arm64-v8a 与 x86_64 构建通过；[build-native.log](build-native.log) |
| 清洁构建 | clean 后显式 product=release、buildMode=release、assembleApp 成功；[build-app.log](build-app.log) |
| APP/Profile | 签名、摘要、有效期、release/app_gallery、无开发白名单、与 0.9.0 的 APP 标识/发布证书一致均通过；[delivery-verification.json](delivery-verification.json) |
| 包内容 | 独立签名 HAP 与 APP 内嵌 HAP 的发布门禁均通过；版本、包名、API 24、三类设备和双 ABI 符合预期 |
| 同一发布产品的 HAP 一致性 | 45 个模块文件一致；独立 HAP 额外含签名生成的 `.pages.info`，`pack.info` 使用解析后 JSON 比较，以排除打包格式化空白差异 |
| 0.10.0 模拟器安装 | 手机 5555、电脑 5557 均 PASS，SIGNATURE_RESET=false；[install-emulators.log](install-emulators.log) |
| 0.10.0 模拟器导航 | 关于页版本、皮肤子页、返回、手机堆叠/电脑分屏均 PASS，操作前后设置文件一致；[手机](phone/smoke-result.json)、[电脑](computer/smoke-result.json) |

ArkTS 实际新报告时间为 2026-09-10 09:37，未复用旧报告冒充新结果。Rust 全量沿用 2026-09-09 的 665 项通过记录，本轮未修改 Rust，未重新跑全量 Rust。

## 模拟器与交付包的对应边界

正式交付为 release 产品、正式发布签名；模拟器使用同源码的 default 产品、开发签名。两个产品分别编译，生成 BuildProfile 的 PRODUCT_NAME 分别为 release/default。跨产品核对 43 个非元数据文件：40 个资源文件相同，modules.abc 与两份 libime_bridge.so 的字节不同，**不宣称模拟器包与交付包逐字节相同**。这项额外核查记录构建产品差异，不替代已通过的正式 APP 内容与签名门禁。[比较记录](device-payload-comparison.json)。

本次实际在线设备类型通过系统参数确认：5555=phone，5557=2in1。平板本次未在线；平板和全部详情/子页操作采用上一轮三端记录。正式 APP 尚未通过客户渠道安装，本次未上传 AGC。

完整三端 UI 范围、表单与未保存提示证据：[设置详情统一验收](../settings-details-unification-20260909/ACCEPTANCE_REPORT.md)。完整输入行为、直通、数字便捷输入与成对符号证据：[客户反馈验收](../full-feedback-acceptance-20260909/ACCEPTANCE_REPORT.md)。本轮没有重复全套输入功能操作。

## 已知限制与待测项

- 自定义结构/皮肤共享尚未获华为授权。`KEYBOARD_CUSTOMIZATION_DATA_GROUP_ID` 仍为空；普通配置检查仅警告，`--require-shared` 仍应拒绝。未伪造授权或绕过限制，内置结构/皮肤可用。用户接受该范围后构建。
- 云端 AI、真实语音服务未开通。
- 实际备忘录、QQ、头条等宿主、真实 USB/蓝牙键盘、百度切换、物理震动和声音效果，仍需客户设备测试；此前跨应用输入验收使用独立编辑器与模拟器按键注入。
- 编译仍有既有 SDK 警告，涉及设备能力、废弃 API 和异常提示；窗口样式、音效、光标移动和导入代码已检查现有异常/回退边界。构建无错误，未为消除警告修改本轮禁止改动的业务逻辑。

## 交付

[正式签名 APP](../../artifacts/0.10.0/ShuangYuIME-0.10.0-10000000-release-signed.app)，24,925,233 bytes。

SHA-256：`1733CF6EC718EC9C870E291FA2330632F57ECE9E1222B75FB0D38B995761C326`。

[客户测试说明](../../artifacts/0.10.0/AGC_UPLOAD_README.md)、[客户更新说明](../../artifacts/0.10.0/RELEASE_NOTES_zh-CN.txt)、[APP/HAP 摘要](../../artifacts/0.10.0/SHA256SUMS.txt)。
