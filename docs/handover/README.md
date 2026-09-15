# 项目交接指南

本指南帮助新的维护者快速建立项目全貌。它只提供入口，不复制容易过期的版本状态；
最新结论以根目录 [PROJECT_STATE.md](../../PROJECT_STATE.md) 为准。

## 建议阅读顺序

1. [项目 README](../../README.md)：产品能力、关键路径和常用命令。
2. [当前状态](../../PROJECT_STATE.md)：已完成范围、未验证项和当前风险。
3. [架构说明](../ARCHITECTURE.md)：ArkTS → C++ Node-API → Rust C ABI 数据流。
4. [项目结构](../architecture/PROJECT_STRUCTURE.md)：目录职责和源码分层。
5. [构建指南](../BUILD_GUIDE.md) 与 [测试计划](../TEST_PLAN.md)。
6. [更新日志](../../CHANGELOG.md) 和 [ADR](../adr/)：需要追溯历史原因时再阅读。

## 代码与数据入口

| 范围 | 位置 | 说明 |
| --- | --- | --- |
| HarmonyOS/ArkTS | `entry/src/main/ets/` | 能力入口、应用控制、领域模型、基础设施和 UI |
| Native 桥接 | `entry/src/main/cpp/` | Node-API、Rust C ABI 和错误转换 |
| Rust 引擎 | `engine-rust/` | workspace、生产引擎、查询、排序、学习和离线工具 |
| 拼音词库 | `dictionaries/` | 来源、生成物、审计、许可证和冻结清单 |
| 小鹤音形正式上游 | `码表/`、`小鹤音形/` | 当前路径属于构建与审计契约，不要直接改名或移动 |
| 构建与验收 | `scripts/` | 脚本入口见 [scripts/README.md](../../scripts/README.md) |
| 独立工具 | `tools/` | 验收客户端和 workspace 外的入口说明 |

## 首次拉取

1. 安装 Git LFS，并确认 `.lex`、`.hsyx`、`.qng` 已完整拉取。
2. 按 [工具链说明](../development/TOOLCHAIN.md) 配置 DevEco Studio、HarmonyOS SDK 和 Rust。
3. 以根目录 `build-profile.example.json5` 为参考创建本机 `build-profile.json5`。
4. 签名材料、`local.properties`、缓存和构建产物不得提交。
5. 先运行环境检查，再执行主机测试和 HAP 构建。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check-environment.ps1
powershell -ExecutionPolicy Bypass -File scripts\test-rust.ps1
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1
powershell -ExecutionPolicy Bypass -File scripts\verify-release-hap.ps1
```

## 重要边界

- `entry/src/main` 是 Release 正式源码；`entry/src/internalDebug` 只用于内部验收。
- `码表/`、`小鹤音形/` 的路径写入来源审计和冻结合同。迁移它们必须重新生成审计清单、更新身份哈希并验证生产 Bundle。
- `dictionaries/generated/` 与 `entry/src/main/resources/rawfile/` 中的正式资源有确定性复制关系，不要手工去重。
- `docs/evidence/` 的 Markdown 摘要进入 Git；原始截图、日志、布局树和 JSON trace 默认被忽略，应通过单独的交付介质归档。
- `artifacts/` 只提交可复现的基线、数据集、清单和最终摘要；中间优化产物保持本地。
- 当前设备覆盖、性能结论和发布阻塞始终从 `PROJECT_STATE.md` 获取，不以旧验收报告推断现状。

## 交接检查清单

- 工作区无意外修改，Git LFS 文件不是指针文本。
- 环境检查、Rust 测试、双 ABI Native、Release HAP 和内容门禁结果已记录。
- 本机签名配置与 AGC 应用身份一致，但私钥和 Profile 未进入仓库。
- 新增或调整的功能同时更新当前状态、测试计划和对应功能文档。
- 需要保留的本机验收原始证据已单独归档，并附提交号、设备和时间信息。
- 0.4.0 上传说明见 [AGC 邀请测试上传说明](https://github.com/JayusChi/shuangyu-ime-harmonyos/blob/f343416795303a3e844bcc80463191d122856c32/artifacts/0.4.0/AGC_UPLOAD_README.md)。
