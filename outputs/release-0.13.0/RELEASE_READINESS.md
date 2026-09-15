# 0.13.0 APP 构建核查

2026-09-15，正式签名 APP 构建并验证通过。版本 `0.13.0 / 13000000 / build 1`。

- [APP](../../artifacts/0.13.0/ShuangYuIME-0.13.0-13000000-release-signed.app)：25,082,218 bytes。
- SHA-256：`F608A3E6DA4F11E1E4B8C57EEC11284FA12F00DB848C866ABFECC8A02DC6BAD9`。
- [HAP](../../artifacts/0.13.0/ShuangYuIME-0.13.0-13000000-release-signed.hap)、[校验码](../../artifacts/0.13.0/SHA256SUMS.txt)。

## 本轮构建

仅更新 AppScope/app.json5 的版本名、版本码，基于当前工作区全部功能源码打包。执行双 ABI Rust Release 构建（Cargo 确认目标最新）、干净的 Release 产品 HAP 构建、Release assembleApp。ArkTS 编译与 Native 链接均完成。

| 验证 | 结果 |
| --- | --- |
| APP、HAP、Profile 签名 | PASS |
| Profile | release / app_gallery，有效至 2029-07-17，无开发设备白名单 |
| 升级身份 | 发布证书及应用标识与 0.12.0 一致 |
| APP 与内嵌 HAP 版本 | 0.13.0 / 13000000 / build 1 |
| 构建模式 | release，debug=false |
| 架构、设备 | arm64-v8a / x86_64；phone / tablet / 2in1 |
| 最低 API | HarmonyOS 6.1.1，API 24（60101024） |
| 权限 | VIBRATE + INTERNET，flypy-web-v1 |
| 皮肤共享目录 | 正式 Profile 授权与包内输入法声明匹配 |
| 独立与内嵌 HAP 资源门禁 | PASS，包含内置皮肤工坊 HTML 一致性检查 |
| 独立与内嵌 HAP 内容 | 46 项一致，单独处理签名页元数据和 pack.info JSON 空白 |

机器结果：[delivery-verification.json](delivery-verification.json)。日志：[HAP 构建](build-hap.log)、[APP 构建](build-app.log)、[交付核查](verify-delivery.log)。可复核脚本：[verify-delivery.ps1](verify-delivery.ps1)。

皮肤工坊功能沿用本轮打包前的[入口验收](../skin-editor-entry-20260915/ACCEPTANCE.md)和[手机、电脑配色及结构导入验收](../skin-workshop-roundtrip-20260915/ACCEPTANCE.md)。这些功能验收使用开发签名的 0.12.0 Release 包，本轮未重新安装 0.13.0 或重跑完整功能测试。未上传 AGC。
