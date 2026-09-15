# 脚本入口

脚本当前保持在 `scripts/` 根层。多数脚本通过 `$PSScriptRoot` 解析项目根目录或调用同级脚本，
因此不要只为目录外观批量移动；需要分层时，应先提供兼容入口并完成全部门禁。

## 常用命令

```powershell
# 环境检查
powershell -ExecutionPolicy Bypass -File scripts\check-environment.ps1

# 逆切分的 Native bridge 主机适配器回归（模拟原生桥接）
node scripts/test-reverse-split-gateway.cjs

# Rust 格式、Clippy 和 workspace 测试
powershell -ExecutionPolicy Bypass -File scripts\test-rust.ps1

# 双 ABI Native
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all

# Release HAP 与内容门禁
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1
powershell -ExecutionPolicy Bypass -File scripts\verify-release-hap.ps1

# 开发设备安装：正式代码 + 固定开发签名（与发布产品隔离）
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust -BuildMode release -Product default
powershell -ExecutionPolicy Bypass -File scripts\install-signed-hap.ps1 -AllConnected
```

`build-hap.ps1` 的 Release 默认选择 `release` 产品，签名包位于
`entry/build/release/outputs/default/entry-default-signed.hap`；DevEco Run 使用 `default` 产品，
签名包位于 `entry/build/default/outputs/default/entry-default-signed.hap`。
本机配置中 `default` / `internalDebug` 应绑定同一开发签名，`release` 绑定发布签名。
出现 `9568332` 时先核对现有安装的证书，优先沿用匹配的签名保留数据；
只有明确接受清除旧应用数据后才使用 `install-signed-hap.ps1 -ResetSignature`。

## 命名分类

| 前缀 | 职责 | 示例 |
| --- | --- | --- |
| `check-*`、`clean`、`format` | 环境和日常维护 | `check-environment.ps1` |
| `build-*`、`copy-*` | Rust、Native、词库和 HAP 构建 | `build-native.ps1` |
| `test-*` | 单元、资源门禁和专项测试 | `test-rust.ps1` |
| `verify-*` | 阶段总门禁、发布包和确定性检查 | `verify-release-hap.ps1` |
| `accept-*` | 电脑端专项验收 | `accept-computer-stage5.ps1` |
| `device-accept-*` | 模拟器和设备验收 | `device-accept-v0_2_0.ps1` |
| `audit-*` | 正式来源审计 | `audit-xiaohe-yinxing.ps1` |
| `create-*`、`generate-*` | 数据集、基线和证据生成 | `generate-candidate-baseline.ps1` |
| `evaluate-*`、`measure-*` | 质量和性能评测 | `evaluate-pinyin9-quality.ps1` |
| `freeze-*` | 冻结可复现实现和词库身份 | `freeze-quanpin-implementation.ps1` |
| `toolchains/` | OHOS linker 适配 | `ohos-clang-linker.ps1` |

## 维护约定

- 从 `$PSScriptRoot` 推导项目路径，不依赖调用者的当前工作目录。
- 入口脚本使用稳定、可搜索的前缀；新增脚本时同步更新本文件和相关构建/测试文档。
- 生成物写入已约定的 `build/`、`target/`、`artifacts/` 或临时目录，不写到仓库根目录。
- 发布脚本必须保留 Release/Debug 隔离、正式资源身份和敏感文件门禁。
