# 最终构建与签名

2026-09-14，版本 0.12.0。含 BASIC 设置共享恢复/同步和模板导入持续错误提示；不含临时 `BASIC_ONCREATE_PROBE` 诊断代码。

| 文件 | SHA-256 | 用途 |
| --- | --- | --- |
| `release/shuangyuime-0.12.0-release-signed.hap` | `02943A4BF69374B28E10342BC24950F87FFD9BB7E1CB842710F79D6641C280AA` | 市场发布签名，等待官方测试渠道受信安装验收 |
| `release/shuangyuime-0.12.0-development-signed.hap` | `4FA28F03C80D0DE5B3CF07CBEB75CEE24350098863978E8F47FBD7576B0B78DD` | 同源 release 构建，开发签名，已安装三台模拟器 |

最终市场签名包 93,339,649 字节；发布构建成功、PackingCheck 成功、发布内容门禁 PASS、`hap-sign-tool verify-app` PASS。构建日志 `build-final-release.log`；内容门禁 `verify-final-release.log`；签名验证 `verify-final-signature.log`。

开发签名构建见 `build-final-default.log`。最终三端安装均 `SIGNATURE_RESET=false`、`INSTALLED_SHARED_GROUPS=PASS`，见 `install-final-default.log`。当前三端保留已导入的测试皮肤和 UPDATED 结构，完整体验模式已启用。

本次市场签名包仍不能标记为发布验收通过：此前同一发布身份侧载后有效共享组为空，系统签名服务拒绝承认来源。最终包包含相同发布身份，未重复清空设备做等价侧载；需要 AGC 官方测试分发后继续验收。详情见 `ACCEPTANCE.md`。

重现命令：

```powershell
& scripts/build-hap.ps1 -SkipRust -BuildMode release -Product release
& scripts/verify-release-hap.ps1 -HapPath entry/build/release/outputs/default/entry-default-signed.hap
& 'C:/Program Files/Huawei/DevEco Studio/jbr/bin/java.exe' -jar 'C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar' verify-app -inFile entry/build/release/outputs/default/entry-default-signed.hap -outCertChain outputs/keyboard-customization-fix-20260914/final-certchain.cer -outProfile outputs/keyboard-customization-fix-20260914/final-profile.p7b
```

签名私钥和口令未复制到交付目录。
