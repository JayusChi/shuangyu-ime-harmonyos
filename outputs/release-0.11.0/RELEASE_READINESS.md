# 0.11.0 正式签名 APP 构建核查

2026-09-11：**RELEASE_APP_BUILT_AND_VERIFIED**。已生成 0.11.0 / 11000000 / build 1，包含当前工作区的键盘/双拼反馈修复和应用内查形修复。

本轮产品源码改动仅为 AppScope 版本元数据。沿用已有 release 签名配置，未更换证书、修改签名 Profile 或清除设备数据，未提交 Git、上传 AGC 或发布。

## 新执行的检查

| 检查 | 结果 |
| --- | --- |
| Rust/Native 双 ABI | x86_64、arm64-v8a 构建通过，两个目标库重新复制进本轮构建 |
| Release HAP | 显式 product=release、buildMode=release，从 clean 构建通过 |
| APP | 同一 release 产品 assembleApp 成功并完成正式签名 |
| APP / Profile 签名 | PASS，摘要有效；release / app_gallery，无开发设备白名单，有效期至 2029-07-17 |
| 升级身份 | 与 0.10.0 发布证书及 APP 标识相同 |
| 版本与平台 | APP 和内嵌 HAP 均为 0.11.0 / 11000000 / 1，API 24，手机/平板/电脑，双 ABI |
| 权限及网页 | flypy-web-v1 的 VIBRATE + INTERNET、非导出 FlypyWebAbility、包内 pages/FlypyWeb 均通过门禁 |
| 发布资源 | 独立正式签名 HAP 与 APP 内嵌 HAP 均通过发布门禁 |
| 模块一致性 | 同一 release 产品的45个模块文件一致；忽略独立签名额外生成的 .pages.info，pack.info 按解析后的 JSON 比较 |

证据：[HAP/Native 构建](build-release-hap.log)、[APP 构建](build-app.log)、[签名及身份检查](delivery-verification.json)、[核验脚本](verify-delivery.ps1)、[独立 HAP 门禁](verify-signed-hap.log)、[内嵌 HAP 门禁](verify-embedded-hap.log)。

## 沿用的近期功能验收

- 本次任务前刚完成最终功能源码 708 项 ArkTS 测试，0失败；本轮版本打包没有重复全量测试。[结果](../browser-fullscreen-fix-20260911/arkts-final-source-result.txt)
- 手机和电脑 18 项官网/查形/重复查询/刷新/换字/剪贴板/宿主文本检查通过，完整网页截图已复核。[报告](../browser-fullscreen-fix-20260911/ACCEPTANCE_REPORT.md)
- 8项键盘反馈及2条双拼例句的先前验收见 [反馈报告](../feedback-acceptance-20260911/ACCEPTANCE_REPORT.md)，其中原手机网页未完成项已由上述应用内网页补修完成。

这些设备证据对应同一功能源码、开发签名0.10.0设备包，不是本次正式签名0.11.0 APP 的实际安装记录。本轮未构建新的开发签名模拟器包，也未执行0.11.0客户渠道升级。

## 交付与范围

[ShuangYuIME-0.11.0-11000000-release-signed.app](../../artifacts/0.11.0/ShuangYuIME-0.11.0-11000000-release-signed.app)

- 大小：24,980,564 bytes。
- SHA-256：`7DCE29688E0CDB3382D278DE0A93B5DBF417DF9C4CB68A3A5E0B247954CD391B`。
- [交付说明](../../artifacts/0.11.0/AGC_UPLOAD_README.md)、[更新说明](../../artifacts/0.11.0/RELEASE_NOTES_zh-CN.txt)、[摘要清单](../../artifacts/0.11.0/SHA256SUMS.txt)。

沿用已接受的自定义结构/皮肤共享沙箱授权限制，内置结构/皮肤可测；云端AI和真实语音未开通。INTERNET 已由用户明确批准用于应用内小鹤网页，属于应用级权限。真实宿主、实体键盘、真机兼容和正式客户渠道升级仍需客户测试。
