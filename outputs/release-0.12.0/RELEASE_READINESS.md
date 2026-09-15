# 0.12.0 客户测试发布核查

结论：正式签名 APP 已完成本地打包和核验，可以交付客户用于后续测试。版本 `0.12.0 / 12000000 / build 1`，日期 2026-09-14。

## 交付

- [APP](../../artifacts/0.12.0/ShuangYuIME-0.12.0-12000000-release-signed.app)：25,015,019 bytes，SHA-256 `0E23F5BBB4248D53C7F4983A951B164D18AE3A12DF6B2DBDD2593BDB3BCBDF4F`。
- [HAP](../../artifacts/0.12.0/ShuangYuIME-0.12.0-12000000-release-signed.hap)：SHA-256 `08AAB0549CFCA065BD7E8439AD6EBA625CEAD2BAEC921C69E6ACFC7B7467B6BC`。
- [客户更新说明](../../artifacts/0.12.0/RELEASE_NOTES_zh-CN.txt)、[校验码](../../artifacts/0.12.0/SHA256SUMS.txt)。旧版本交付文件保留。

## 构建与签名

仅更新 `AppScope/app.json5` 中版本名和版本码。使用 `build-hap.ps1 -SkipRust -Clean -BuildMode release -Product release` 干净构建 HAP，再运行同产品 Release `assembleApp`。复用当天已通过回归和双 ABI 构建的 Rust 静态库；Native 链接、ArkTS 编译重新执行。

| 检查 | 结果 |
| --- | --- |
| APP、Profile、独立 HAP 签名 | PASS |
| APP/HAP Profile 一致 | PASS |
| 与 0.11.0 的发布证书、APP 标识一致 | PASS |
| Profile | release / app_gallery，无开发设备白名单，有效至 2029-07-17 |
| APP 内版本、内嵌 HAP 版本 | 0.12.0 / 12000000 / build 1 |
| 构建 | release，debug=false |
| 设备与 ABI | phone / tablet / 2in1；arm64-v8a / x86_64 |
| 最低 API | 60101024，即 HarmonyOS 6.1.1（API 24） |
| 权限 | VIBRATE + INTERNET，沿用已批准 flypy-web-v1 |
| 内嵌、独立 HAP 资源和发布内容门禁 | PASS |
| 内嵌、独立 HAP 45 个模块文件 | 内容一致，单独处理签名页元数据及 JSON 空白格式 |

机器结果：[delivery-verification.json](delivery-verification.json)。构建日志：[HAP](build-hap.log)、[APP](build-app.log)。验证日志：[APP 签名](verify-app-signature.log)、[HAP 签名](verify-hap-signature.log)、[Profile](verify-profile.log)、[独立 HAP 门禁](verify-signed-hap.log)、[内嵌 HAP 门禁](verify-embedded-hap.log)。

## 与刚验收版本的连续性

版本更新前未发现晚于最终验收包的功能源码修改，见 [源码时间核对](acceptance-source-continuity.json)。与最终验收后生成的正式 0.11.0 HAP（SHA-256 `BDFE9196B990020F7C5608565020A04C1394EF8ECC0CE220ABAF82D046109204`）逐文件比较 46 项，仅 `module.json` 和 `pack.info` 变化；ArkTS 字节码、双 ABI Native、词库和全部其他资源一致。见 [比对结果](accepted-payload-verification.json)、[基线哈希](accepted-0110-payload-hashes.json)。

功能验收承接紧邻的 [手机、电脑九项验收报告](../feedback-reacceptance-20260914/ACCEPTANCE_REPORT.md)：748 项 ArkTS、31 项 UI 证据检查通过；当天双拼专项 326 项 Rust 结果见 [专项证据](../../docs/evidence/2026-09-14-shuangpin-fixed-words/README.md)。本次版本打包没有把这些记录计作重新运行，也未重新安装 0.12.0。

未上传 AGC、未对外发送文件。ARM64 真机、真实外设、客户实际应用仍需客户测试。共享沙箱授权、云端 AI 与真实语音服务的原有限制沿用，详见客户更新说明。
