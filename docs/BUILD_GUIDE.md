# 构建指南

## 环境检查

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check-environment.ps1
```

如果 `%USERPROFILE%\.cargo\bin` 包含 `cargo.exe` 但不在当前 PATH 中，脚本会暂时将其添加到当前 PowerShell 进程并打印警告。它们不会永久修改用户 PATH。

## Rust 检查

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-rust.ps1
```

## Rust 原生库

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-rust.ps1 -Abi x86_64
powershell -ExecutionPolicy Bypass -File scripts\copy-native-artifacts.ps1 -Abi x86_64

powershell -ExecutionPolicy Bypass -File scripts\build-rust.ps1 -Abi arm64-v8a
powershell -ExecutionPolicy Bypass -File scripts\copy-native-artifacts.ps1 -Abi arm64-v8a
```

或构建所有配置的 ABI 产物：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all
```

最终 CMake 输入产物：

```text
engine-rust/target/ohos/x86_64/libime_ffi.a
engine-rust/target/ohos/arm64-v8a/libime_ffi.a
```

## HAP

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1
```

除非提供 `-SkipRust`，否则脚本首先构建 Rust 产物。

脚本默认显式构建 Release；如需 Debug 输入框验收页，使用
`-BuildMode debug`。当前输出：

```text
entry/build/artifacts/entry-release-unsigned.hap
entry/build/artifacts/entry-debug-unsigned.hap
```

`default` 产品已配置本机 Release 签名，Hvigor 会在常规输出目录同时生成 signed/unsigned HAP。为保持内容门禁输入稳定，`scripts/build-hap.ps1` 当前仍显式复制 unsigned HAP 到上述 `entry/build/artifacts` 路径；该 artifacts 文件不是客户上传包。`internalDebug` 不引用发布签名配置。

Release 使用 `default` target 和 `entry/src/main`；内部验收包使用 `internalDebug` target/source set。Debug 页面、Debug 入口资源和内部码表 fixture 位于 `entry/src/internalDebug`，不属于 Release 页面清单。构建脚本仅在 Debug 编译窗口内准备 Hvigor 所需页面映射和原创 fixture，并在 `finally` 中清理临时文件。

Release 包构建后必须执行内容门禁：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-release-hap.ps1
```

门禁会检查 `module.json` 的 Release 元数据、`production.lex`、测试词库缺失状态，并同时扫描 `entry/src/main` 和最终 HAP 的 ArkTS/Native 内容，拒绝 `DebugStage10`、`DebugCodeTable`、“调试与验收”、内部 fixture、固定候选和模型探针等调试标识。门禁本身的正负用例使用：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-release-resource-gate.ps1
```

## APP

应用市场上传前应构建项目级 Release APP：

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --no-daemon --mode project -p product=default -p buildMode=release assembleApp
```

当前 `default` Release 构建会生成：

```text
build/outputs/default/HarmonyOS_Input-default-signed.app
build/outputs/default/HarmonyOS_Input-default-unsigned.app
```

只有 signed APP 可以进入后续发布验收；unsigned APP 只用于工程检查。文件名包含 `signed` 仍不足以证明可发布，正式发布前必须：

1. 在 AGC 创建正式 HarmonyOS 应用并确定唯一包名；
2. 将 `AppScope/app.json5` 中当前 `com.corrosion.shuangyuime`、vendor、`versionName/versionCode` 与 AGC 正式应用记录核对并保持一致；
3. 确认 `build-profile.json5` 的本机 signing config 指向正确的发布证书/Profile/私钥库，且材料不进入仓库或交付包；
4. 重新构建，并用签名检查工具验证 signed Release APP 的证书链、Profile 类型、包名和有效期；
5. 按 [0.1 版本交付验收](../0.4.0交付问题) 完成签名、ARM64 真机和上架资料检查；Release Debug 物理隔离已完成并由门禁持续验证。

## 阶段 3 验证

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage3.ps1
```

该命令会执行环境检查、Rust format/clippy/test、x86_64 和 arm64-v8a 原生产物构建、ArkTS 单元测试、HAP 构建、阶段 3 源码守卫和产物摘要。

在需要在线模拟器或设备验证安装/IME 状态的情况下：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage3.ps1 -DeviceValidation
```

真实手机运行期接入不是阶段 3 当前阻塞项。仅在记录无法运行 HAP 构建的环境时使用 `-SkipHap`。

阶段 2 回归脚本仍可按需运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage2.ps1
```

## 手动设备命令

```powershell
& "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" list targets
& "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" install -r entry\build\artifacts\entry-release-unsigned.hap
& "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" shell ime -e com.corrosion.shuangyuime -f
& "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" shell ime -g
```
