# 双羽输入法 · HarmonyOS

面向 HarmonyOS 的中文输入法，支持小鹤双拼、小鹤音形、26 键全拼和 9 键拼音，提供触屏键盘、实体键盘输入、候选管理及键盘皮肤定制。

项目采用 **ArkTS + C++ + Rust** 分层架构：ArkTS 负责输入法生命周期与界面，C++ 提供原生桥接，Rust 处理编码解析、词库查询、候选排序和用户学习。

[快速开始](#快速开始) · [构建与验证](#构建与验证) · [文档中心](docs/README.md) · [更新日志](CHANGELOG.md) · [项目状态](PROJECT_STATE.md)

## 项目信息

| 项目 | 说明 |
| --- | --- |
| 当前版本 | `0.13.0`（`versionCode: 13000000`） |
| 最低系统 | HarmonyOS 6.1.1 / API 24 |
| 声明的设备类型 | 手机、平板、二合一设备（`phone` / `tablet` / `2in1`） |
| 原生架构 | `arm64-v8a`、`x86_64` |
| 默认输入方案 | 26 键小鹤双拼（`xiaohe-26`） |
| 应用包名 | `com.corrosion.shuangyuime` |

**版本验证范围：** 2026-09-15 已完成 0.13.0 正式签名 APP 构建，以及双 ABI、签名、升级身份、版本和资源检查。功能验证沿用打包前的模拟器记录；本轮未重新安装 0.13.0，也未上传 AppGallery Connect（AGC）。具体范围见 [0.13.0 发布核查](https://github.com/JayusChi/shuangyu-ime-harmonyos/blob/542ab009c7ada6bbaa57f2f699e24392bd0f5947/outputs/release-0.13.0/RELEASE_READINESS.md)，持续更新的实现与设备验证状态见 [PROJECT_STATE.md](PROJECT_STATE.md)。

APP、HAP 安装包及本机签名材料不随 Git 仓库分发；克隆源码后需配置本地构建环境。

## 主要功能

| 功能 | 内容 |
| --- | --- |
| 拼音输入 | 小鹤双拼 17 / 26 键、26 键全拼、9 键拼音；支持词语、短句候选、分页和部分提交 |
| 小鹤音形 | 独立的 17 / 26 键方案，支持精确匹配、编码提示、分类词库、自动上屏和空码切分 |
| 候选展示 | 固定候选栏、候选展开面板、电脑浮动候选窗及键盘选词 |
| 用户词库 | 词条管理、导入导出、隐藏、固顶和指定位置规则；各输入方案的用户学习隔离 |
| 编辑与直通 | 中英文切换、成对符号、重复上屏、撤销、删除恢复及受控直通动作 |
| 键盘定制 | 主题、布局、按键手势、字母下滑符号、震动、按键音及皮肤与结构导入 |
| 皮肤工坊 | 随包提供离线可视化编辑器，可调整配色、图片和按键结构，导出 `.sy-skin` / `.sy-layout` |

皮肤工坊的操作方式和设备验证范围见 [工坊说明](tools/keyboard-customization-editor/README.md)。

## 架构与目录

```text
HarmonyOS IME Kit
       ↕
ArkTS：输入法生命周期、会话控制、键盘与设置界面
       ↕ Node-API
C++：原生网关、句柄管理、数据转换
       ↕ C ABI
Rust：编码解析、词库查询、候选排序、用户学习
```

| 路径 | 职责 |
| --- | --- |
| `AppScope/` | 应用身份、版本及应用级资源 |
| `entry/src/main/ets/` | ArkTS 应用、领域逻辑、基础设施和界面 |
| `entry/src/main/cpp/` | C++ Node-API 与 Rust C ABI 桥接 |
| `entry/src/main/resources/` | 正式页面资源、随包词库和离线工坊 |
| `entry/src/internalDebug/` | 内部验收页面和测试资源 |
| `entry/src/test/` | ArkTS 单元测试 |
| `engine-rust/` | Rust 工作空间、输入引擎、FFI、词库工具与测试 |
| `dictionaries/` | 词库来源、生成产物、审计及第三方许可记录 |
| `examples/` | 用户词库、键盘结构和皮肤模板示例 |
| `tools/` | 皮肤工坊、独立验收客户端等辅助工具 |
| `scripts/` | 环境检查、构建、测试和发布校验脚本 |
| `docs/` | 架构、功能设计、开发规范和验收摘要 |

模块职责和跨层接口分别见 [架构说明](docs/ARCHITECTURE.md)、[API 契约](docs/API_CONTRACT.md)。

## 快速开始

### 1. 准备环境

以下命令以 **Windows PowerShell** 为例，在仓库根目录执行。

- Git 与 Git LFS：用于获取源码及大体积词库资源。
- DevEco Studio 6.1.1 与 HarmonyOS SDK 6.1.1（API 24），包含 Native 构建工具。
- Rust 工具链：版本、组件和 OHOS 编译目标由 [rust-toolchain.toml](engine-rust/rust-toolchain.toml) 固定。
- Node.js、ohpm、Hvigor：可使用 DevEco Studio 配套工具，并将需要的命令加入当前终端的 `PATH`。

已验证的工具版本与 SDK 路径配置见 [工具链说明](docs/development/TOOLCHAIN.md)。

### 2. 获取源码和词库

```powershell
git lfs install
git clone https://github.com/JayusChi/shuangyu-ime-harmonyos.git
cd shuangyu-ime-harmonyos
git lfs pull
```

词库资源通过 Git LFS 管理。首次构建前应完成 `git lfs pull`，确保本地获得实际资源文件。

### 3. 配置本地工程

首次配置时，从示例创建本机配置文件：

```powershell
Copy-Item build-profile.example.json5 build-profile.json5
```

使用 DevEco Studio 打开仓库并同步依赖，按本机 SDK 路径和签名材料补全配置：

- `default` 和 `internalDebug` 产品绑定同一开发签名。
- `release` 产品绑定正式发布签名。
- 键盘定制共享目录所需的 Profile 授权须与工程声明一致，详见 [共享沙箱接入说明](docs/features/keyboard-customization/SHARED_SANDBOX_INTEGRATION.md)。

`build-profile.json5`、`local.properties` 和签名材料仅保存在本机。已有本地配置时，按示例核对并补全字段。

运行环境检查，确认工具和 SDK 路径可用：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check-environment.ps1
```

## 构建与验证

### 开发设备构建

使用正式功能源码与开发签名构建 HAP：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -BuildMode release -Product default
```

脚本默认先构建两个 ABI 的 Rust 原生库。完成构建后，向已连接的开发设备安装：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-signed-hap.ps1 -AllConnected
```

安装后，在系统输入法设置中启用“**双羽输入法**”，打开文本框并切换到该输入法。默认小鹤双拼可输入 `nihc` 查找“你好”；其他输入方案可在设置页切换。

### 发布与内部验收构建

| 用途 | 命令参数 | 产品 / Target |
| --- | --- | --- |
| 开发设备验收正式功能 | `-BuildMode release -Product default` | `default` / `default` |
| 正式发布 HAP | 默认参数，或 `-BuildMode release -Product release` | `release` / `default` |
| 内部 Debug 验收页 | `-BuildMode debug` | `internalDebug` / `internalDebug` |

以上参数均传给 `scripts/build-hap.ps1`。**BuildMode 控制编译模式，Product 选择签名配置。** 内部验收页面与测试资源独立放置在 `internalDebug`，发布检查会验证其未进入正式包。

正式发布 HAP 构建和资源检查：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1
powershell -ExecutionPolicy Bypass -File scripts\verify-release-hap.ps1
```

主要构建产物：

| 路径 | 用途 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-signed.hap` | 开发设备安装 |
| `entry/build/release/outputs/default/entry-default-signed.hap` | 正式发布产品 HAP |
| `entry/build/artifacts/entry-release-unsigned.hap` | Release 内容校验 |
| `entry/build/artifacts/entry-debug-unsigned.hap` | 内部 Debug 构建检查 |

市场发布需进一步构建 `release` 产品的 signed APP，并复核签名、应用身份及分发渠道要求。当前版本的构建与核查记录见 [0.13.0 发布核查](https://github.com/JayusChi/shuangyu-ime-harmonyos/blob/542ab009c7ada6bbaa57f2f699e24392bd0f5947/outputs/release-0.13.0/RELEASE_READINESS.md)。

### 常用检查

```powershell
# Rust 格式、Clippy 和工作空间测试
powershell -ExecutionPolicy Bypass -File scripts\test-rust.ps1

# 发布资源检查器的正反例回归
powershell -ExecutionPolicy Bypass -File scripts\test-release-resource-gate.ps1

# 离线皮肤工坊校验
node tools/keyboard-customization-editor/verify.cjs
```

ArkTS、Native 和设备专项验证入口见 [测试计划](docs/TEST_PLAN.md) 与 [脚本索引](scripts/README.md)。实际设备支持范围以对应验收记录为准。

## 文档导航

| 文档 | 内容 |
| --- | --- |
| [文档中心](docs/README.md) | 全部文档的分类入口 |
| [项目状态](PROJECT_STATE.md) | 当前实现、验证结果和待办事项 |
| [更新日志](CHANGELOG.md) | 版本变更与历史记录 |
| [交接指南](docs/handover/README.md) | 新维护者的阅读顺序与工程约定 |
| [编码规则](docs/development/CODING_RULES.md) | 开发与代码维护规范 |
| [用户词库快速开始](docs/features/user-lexicon/QUICKSTART.md) | 词条编写、校验和导入 |
| [键盘模板格式](docs/features/keyboard-customization/TEMPLATE_FORMAT.md) | 结构与皮肤包格式 |
| [隐私设计](docs/architecture/PRIVACY_DESIGN.md) | 输入数据与隐私边界 |

## 第三方资源

词库来源与许可记录见 [dictionaries/LICENSES](dictionaries/LICENSES/README.md)；离线皮肤工坊使用的 zip.js 许可见 [zip.js-LICENSE.txt](tools/keyboard-customization-editor/vendor/zip.js-LICENSE.txt)。

新增或更新第三方资源时，应同步维护来源、版本、许可、转换过程和校验信息。
