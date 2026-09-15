# 0.11.0 复制反查补充包

2026-09-11：构建与交付检查通过。按用户要求保持 **0.11.0 / 11000000 / build 1**，使用既有正式发布签名。

- 双 ABI Native、clean release 产品 HAP、assembleApp 构建通过。
- APP 与 Profile 签名、有效期、包名和版本通过；正式证书与 APP 标识沿用 0.10.0。
- 独立与内嵌 HAP 资源门禁通过，模块内容一致；两个 ABI 均包含复制反查接口和 clipboard.reverse 动作。
- 沿用刚完成的同源码功能验证：714 项 ArkTS、98 项码表、34 项音形引擎、5 项直通动作与3项复制反查专项通过。[功能证据](../../docs/evidence/2026-09-11-clipboard-reverse/README.md)
- 未安装到设备或上传 AGC，复制反查真实设备授权和上屏待客户验收。既有共享沙箱授权限制保持。

交付：[APP](../../artifacts/0.11.0/ShuangYuIME-0.11.0-11000000-release-signed.app)，24,997,853 bytes，SHA-256 `3C49E80FC4558AFAF6E3586C8955D776AE83380A1793AEF80106A33F3F8BFCAA`。

[签名、身份及包检查](delivery-verification.json) · [HAP构建](build-release-hap.log) · [APP构建](build-app.log) · [独立HAP门禁](verify-signed-hap.log) · [内嵌HAP门禁](verify-embedded-hap.log)

本次包替换同版本旧交付文件；不含复制反查的旧 APP 已保留在 previous/ 目录。
