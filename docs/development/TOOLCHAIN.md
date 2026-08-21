# 工具链

| 项目 | 值 |
| --- | --- |
| 操作系统 | Windows 10.0.26200 |
| PowerShell | 5.1.26100.8737 |
| DevEco Studio 版本 | 6.1.1，构建 `DS-243.24978.46.36.611290` |
| HarmonyOS SDK 版本 | `6.1.1(24)` 来自 `build-profile.json5` |
| API 版本 | `6.1.1(24)` 来自 `build-profile.json5`；确切的 SDK API 包待人工确认 |
| SDK 根目录 | `C:\Program Files\Huawei\DevEco Studio\sdk` |
| OpenHarmony SDK 根目录 | `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony` |
| NDK/原生路径 | `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native` |
| CMake 版本 | 3.28.2 |
| Rust 版本 | rustc 1.96.1 (31fca3adb 2026-06-26) |
| Cargo 版本 | cargo 1.96.1 (356927216 2026-06-26) |
| rustup 版本 | rustup 1.29.0 (28d1352db 2026-03-05) |
| rustfmt | 可通过 `%USERPROFILE%\.cargo\bin` 获得 |
| clippy | 可通过 `%USERPROFILE%\.cargo\bin` 获得 |
| Rust 目标 | 已安装：`aarch64-unknown-linux-ohos`、`x86_64-unknown-linux-ohos`、`x86_64-pc-windows-msvc` |
| Node 版本 | v22.19.0 |
| ohpm 版本 | 6.1.2.285 |
| hvigorw 版本 | 6.24.3 |
| 设备系统版本 | 待人工确认 |
| 设备 ABI | 待人工确认 |
| 模拟器 ABI | `x86_64`，运行时已于 2026-07-07 验证 |

## 当前 PATH 注意事项

Rust 安装在：

```text
C:\Users\CX-03\.cargo\bin
```

该目录不在当前 Codex PowerShell PATH 中。当该目录中存在 `cargo.exe` 时，Rust 构建脚本会为当前进程临时添加它，但未来的 DevEco/Codex 会话应将 `%USERPROFILE%\.cargo\bin` 添加到用户 PATH。

## OHOS Rust 交叉编译

中央 ABI 映射维护在：

```text
scripts/ohos-abi.ps1
```

Cargo 链接器包装器：

```text
scripts/toolchains/aarch64-unknown-linux-ohos-linker.cmd
scripts/toolchains/x86_64-unknown-linux-ohos-linker.cmd
scripts/toolchains/ohos-clang-linker.ps1
```

包装器使用以下参数调用 DevEco Native SDK clang：

```text
--target=aarch64-linux-ohos --sysroot=<native>\sysroot -D__MUSL__
--target=x86_64-linux-ohos --sysroot=<native>\sysroot -D__MUSL__
```

本次运行生成的 Rust 产物：

| ABI | Rust 目标 | 最终产物 | 大小 |
| --- | --- | --- | --- |
| `arm64-v8a` | `aarch64-unknown-linux-ohos` | `engine-rust/target/ohos/arm64-v8a/libime_ffi.a` | 22,561,992 字节 |
| `x86_64` | `x86_64-unknown-linux-ohos` | `engine-rust/target/ohos/x86_64/libime_ffi.a` | 21,917,796 字节 |

## HAP 构建

当前命名 HAP 产物：

```text
entry/build/artifacts/entry-release-unsigned.hap
entry/build/artifacts/entry-debug-unsigned.hap
```

`build-hap.ps1` 默认显式构建 `default` Release；Debug 必须通过 `-BuildMode debug` 指定，并使用 `internalDebug` target/source set。2026-07-16 当前 Release 产物为 11,670,662 bytes，SHA-256 `53E29AC8486802E66DA6D9398F1AF1F1F72B4B00215737EF9C30A107F4834FE0`。

HAP 包含：

```text
libs/arm64-v8a/libime_bridge.so
libs/x86_64/libime_bridge.so
```

当前 x86_64 模拟器可以看到并切换到输入法：

```text
bundle: com.corrosion.shuangyuime, status: FULL_EXPERIENCE_MODE
The current input method is: com.corrosion.shuangyuime, status: FULL_EXPERIENCE_MODE
```

键盘显示、正式候选词显示/提交、删除、空格、回车、隐藏和布局证据已在当前 x86_64 模拟器上验证。Release HAP 内容门禁已通过，正式键盘不显示固定候选回归或模型探针控件。ARM64 物理震感和扬声器效果仍待真机人工验收。
