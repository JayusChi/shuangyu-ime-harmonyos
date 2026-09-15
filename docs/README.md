# 文档中心

本目录是项目文档的统一入口。当前实现状态只维护在仓库根目录的
[PROJECT_STATE.md](../PROJECT_STATE.md)，历史变更只维护在
[CHANGELOG.md](../CHANGELOG.md)。接手项目时建议先阅读
[交接指南](handover/README.md)。

## 核心文档

- [架构说明](ARCHITECTURE.md)：ArkTS、C++、Rust 和词库链路的职责边界。
- [API 契约](API_CONTRACT.md)：跨层接口、错误和行为合同。
- [构建指南](BUILD_GUIDE.md)：环境、构建、签名和发布入口。
- [测试计划](TEST_PLAN.md)：主机、Native、HAP 和设备验证范围。
- [项目结构](architecture/PROJECT_STRUCTURE.md)：目录职责和源码布局。
- [交接指南](handover/README.md)：新维护者的阅读顺序、常用命令和注意事项。

## 分类导航

| 目录 | 内容 |
| --- | --- |
| `architecture/` | 项目结构、隐私和横切设计 |
| `adr/` | 已冻结的架构决策记录 |
| `product/requirements/` | 保留的功能需求 |
| `features/` | 拼音、码表、用户词库、直通控制等功能文档 |
| `development/` | 编码规则、工具链、根配置和实现辅助材料 |
| `operations/` | 发布、交付和运维说明 |
| `audits/` | 数据来源、安全和冲突审计 |
| `evidence/` | 仅保留现有阶段校验依赖的两份摘要，其余记录保存在本机 |
| `assets/` | 文档及品牌源素材，不作为运行时资源加载 |

## 功能入口

- [26 键全拼和 9 键拼音](features/pinyin/PINYIN_STAGE5_FINAL_ACCEPTANCE.md)
- [小鹤音形生产 Bundle](features/code-table/XIAOHE_YINXING_PRODUCTION_BUNDLE_FORMAT.md)
- [码表行为合同](features/code-table/CODE_TABLE_BEHAVIOR_SPEC.md)
- [直通控制与用户词库管理](features/direct-control/STAGE12_DIRECT_CONTROL_USER_LEXICON.md)
- [用户词库快速开始](features/user-lexicon/QUICKSTART.md)
- [用户词库格式](features/user-lexicon/USER_LEXICON_FORMAT.md)

## 文档维护规则

1. 根目录只保留项目入口、当前状态、更新日志和工具链要求的配置。
2. 必要的需求、功能设计和维护说明分别进入 `product/requirements/`、`features/`、`operations/`。
3. 当前事实写入 `PROJECT_STATE.md`，版本摘要写入 `CHANGELOG.md`；截图、日志、一次性脚本和逐次验收报告保存在被忽略的本机目录。
4. 代码附近只保留与该模块直接绑定的 README；已移出跟踪的历史材料可从 Git 历史访问，文档引用使用固定提交链接。
5. 移动文档后必须更新相对链接，并确认链接检查结果为零。
