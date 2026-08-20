# 阶段 11.6.8 证据

日期：2026-07-24

## 状态

```text
11.6.8 PARTIALLY COMPLETED / ARM64 物理真机与独立 TextInput A-L 未执行
```

## 前置门禁结果

- 11.6.7 状态：COMPLETED（见 PROJECT_STATE.md）
- 空码切分合同状态：已于 2026-07-24 由产品授权冻结，见 ADR 0018
- 是否允许进入 11.6.8：YES
- 依据文件：PROJECT_STATE.md、docs/adr/0018-stage11-6-7-commit-policy-and-split-gate.md

## 新增文件清单

| 文件 | 职责 |
|---|---|
| `entry/src/main/ets/infrastructure/resource/YinxingBundleInstaller.ets` | 从 HAP rawfile 原子安装音形 bundle，验证大小和 SHA-256，幂等，临时文件清理 |
| `entry/src/test/SchemeSwitch.test.ets` | 测试方案常量和 isAvailableScheme |
| `entry/src/test/SettingsMigration.test.ets` | 测试设置迁移幂等性和未知 ID 迁移 |
| `entry/src/test/YinxingBundleInstaller.test.ets` | 测试 bundle 元数据验证逻辑 |
| `entry/src/main/resources/rawfile/xiaohe-yinxing-production.hsyx` | 正式音形 bundle，25,397,952 bytes，SHA-256 `00c7d5a9...` |

## 修改文件清单

| 文件 | 修改原因 |
|---|---|
| `entry/src/main/ets/domain/settings/ImeSettings.ets` | 新增 `XIAOHE_YINXING_SCHEME_ID` 常量，扩展 `AVAILABLE_SHUANGPIN_SCHEMES` 为两个方案 |
| `entry/src/main/ets/application/SettingsController.ets` | 导入 `XIAOHE_YINXING_SCHEME_ID` 和 `YinxingBundleInstaller`，changeScheme 增加安装逻辑，load 增加启动回退 |
| `entry/src/test/List.test.ets` | 注册三个新测试套件 |
| `scripts/verify-release-hap.ps1` | 更新 rawfile 白名单，允许正式 bundle 进入 Release；新增 bundle 大小校验 |

## 核心实现说明

### 方案注册
`ImeSettings.ets:91` 新增 `XIAOHE_YINXING_SCHEME_ID = 'xiaohe-yinxing'`；`AVAILABLE_SHUANGPIN_SCHEMES` 包含两个方案，`SettingsPage` 自动展示。

### 设置切换
`SettingsController.changeScheme`（line ~238）：切换到音形前调用安装器；安装失败立即返回失败，不进行 Native 切换；切换时清理组合状态；Native 失败时回滚到旧方案；持久化在 Native 成功后进行。

### 设置迁移
`SettingsValidator.scheme` 通过 `isAvailableScheme` 过滤：`xiaohe` 和 `xiaohe-yinxing` 通过；未知 ID 迁移到 `DEFAULT_SCHEME_ID = 'xiaohe'`；幂等。

### 资源打包
正式 bundle 复制到 `entry/src/main/resources/rawfile/`；`verify-release-hap.ps1` 精确白名单验证两个 rawfile；SHA-256 和大小均校验。

### 原子安装
`YinxingBundleInstaller.installYinxingBundle`：读取 HAP rawfile → 验证大小 → 写入 `.tmp.xxx` → 计算 SHA-256 → 重命名为 `-v1.hsyx` → 原子激活；已安装且哈希匹配时直接复用；失败时保留旧版本。

### 哈希与版本校验
ArkTS 层负责文件大小和 SHA-256；Rust 层继续负责 HSPYXP01 格式、manifest 一致性、内容哈希和篡改检测。

### Engine 切换
`EngineCoordinator.changeScheme` → `NativeEngineGateway.changeScheme` → Rust `ImeEngine::change_scheme`；xiaohe-yinxing 使用已加载的 code_table_bundle，切换失败保留旧状态。

### 故障回退
启动时 `SettingsController.load`：若持久化值为 `xiaohe-yinxing` 但安装失败，修改内存和持久化为 `xiaohe`；方案切换时安装失败则直接返回失败，不切换 Native；均不使用 fixture 回退。

### 双后端隔离
两个方案共用同一 Engine Handle；`change_scheme` 重建后端状态机并清空 session；`xiaohe` 候选不进入 `xiaohe-yinxing` 候选链路，反之亦然。

### Release 门禁
白名单：`production.lex` + `xiaohe-yinxing-production.hsyx`；第二个未知 `.hsyx` 失败；TXT/INI/fixture/trace/报告/凭据 负向门禁保持。

## 执行命令

```text
cargo fmt --all --check                                          PASS
cargo clippy --workspace --all-targets --all-features           PASS
cargo test --workspace                                          PASS (387/387)
build-native.ps1 -Abi x86_64                                    PASS
build-native.ps1 -Abi arm64-v8a                                 PASS
build-hap.ps1 -BuildMode debug                                  PASS
build-hap.ps1 -BuildMode release                                PASS
verify-release-hap.ps1                                          PASS
audit-xiaohe-yinxing.ps1                                        PASS (28/28)
```

## 测试结果

| 类型 | 数量 | 结果 |
|---|---|---|
| Rust workspace | 387/387 | PASS |
| FFI | 25/25 | PASS |
| ArkTS（主机） | 299/299 | PASS（含新增 3 套件，设备端待运行） |
| x86_64 Native 构建 | - | PASS |
| arm64-v8a Native 构建 | - | PASS |
| internalDebug HAP | - | PASS |
| Release HAP | - | PASS |
| Release 资源正向门禁 | - | PASS |
| Release 负向门禁 | - | PASS |
| 28/28 来源不可变 | - | PASS |
| x86_64 模拟器设备验收 A-L | - | NOT RUN（需独立 TextInput 验收页） |
| ARM64 物理真机 | - | NOT RUN |

## 构建产物

| 产物 | 大小 | SHA-256 |
|---|---|---|
| Debug HAP | 40,768,260 bytes | `32FBAF2B99798AEE4F8AEC58775E9C3F18EB9114F1BFE29E25E764BA20E1A19E` |
| Release HAP | 37,565,064 bytes | `B413C26673A895921EEBFCE273785256A724650ABBF93BD83AE7A796EBD8B966` |
| 正式 bundle | 25,397,952 bytes | `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30` |

Release rawfile 扫描：`production.lex` (3,734,484 bytes) + `xiaohe-yinxing-production.hsyx` (25,397,952 bytes)。

## 遗留问题

1. **11.6.6 正式动作数据延期**：快符、引导、日期时间、成对符号仍无授权数据，产品继续延期。
2. **11.6.9 待办**：x86_64 独立 TextInput A-L 设备验收、ARM64 物理真机验收、全量发布验收。
3. **当前环境未执行**：x86_64 模拟器设备验收（需 DevEco Studio 运行环境和模拟器）。

## 架构与协议变化

- interface/ABI version：4（未变）
- 设置 schema version：2（未变）
- 无新增 ADR（现有 ADR 0018 已覆盖切分合同；11.6.8 方案接入无需新 ADR）
- 无新增 Node-API 或 C ABI 函数
- ArkTS → C++ → Rust 边界未变
