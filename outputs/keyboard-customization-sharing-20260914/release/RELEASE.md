# 共享授权发布签名记录（2026-09-14）

## 签名材料归档

- 调试 Profile：`D:/CompanySecrets/HarmonyOS/shuangyuime/profile/shuangyuime_debug_shared_20260914Debug.p7b`
- 发布 Profile：`D:/CompanySecrets/HarmonyOS/shuangyuime/profile/shuangyuime_release_shared_20260914Release.p7b`
- 两份副本与 Downloads 原文件的 SHA-256 均一致；原文件及旧 Profile 保留。
- 包名为 `com.corrosion.shuangyuime`，共享组为 `group.1516753898738609081`。两份 Profile 中对应开发/发布证书均与本地配置的证书链匹配。
- 本地 build-profile.json5 的 default/release 签名 Profile 路径已切至归档文件，证书、私钥、密码、别名保持原配置。default、internalDebug、release 的共享授权严格检查全部通过。

## 发布包

- 文件：[shuangyuime-0.12.0-shared-release-signed.hap](shuangyuime-0.12.0-shared-release-signed.hap)
- 版本：0.12.0；构建模式 release，产品 release，使用新发布 Profile 签名。
- 文件大小：93,337,811 字节。
- SHA-256：`BA224052AEF0A3157C59ABC939997104425760E35FC52CFD72BF05955EA2A45C`
- `scripts/build-hap.ps1 -BuildMode release -Product release` 成功，包含双 ABI 原生库重建、ArkTS 编译及 HAP 签名，见 [build.log](build.log)。
- `scripts/verify-release-hap.ps1` 结果为 `RELEASE_HAP_VERIFY_RESULT=PASS`，见 [verify-signed-hap.log](verify-signed-hap.log)。

## 验收边界

本轮为签名归档、路径配置与发布包构建检查，未安装此发布签名包。此前手机、电脑、平板模拟器的完整体验模式运行证据来自调试签名包。电脑基础模式的面板创建异常仍未定位，MatePad Edge 实机按用户要求暂不验收。完整结果见 [验收记录](../ACCEPTANCE.md)。
