# 项目结构

```text
AppScope/                              Harmony 应用作用域资源
entry/src/main/ets/inputmethod/        InputMethodExtensionAbility 适配器
entry/src/main/ets/application/        生命周期、面板、会话、键盘控制器和长按删除控制器
entry/src/main/ets/state/              输入会话状态存储
entry/src/main/ets/domain/editor/      编辑器上下文和输入能力模型
entry/src/main/ets/domain/ai/          AI 请求、候选、来源所有权和状态合同
entry/src/main/ets/domain/voice/       语音会话、结果和状态合同
entry/src/main/ets/domain/security/    输入法安全模式、权限与能力门控模型
entry/src/main/ets/domain/keyboard/    结构化键盘动作模型
entry/src/main/ets/domain/settings/    设置模型、默认值和可用方案目录
entry/src/main/ets/presentation/       正式键盘 UI、候选栏、设置组件、设计常量和布局模型
entry/src/main/ets/stage0/             历史阶段 0 验证键盘
entry/src/main/ets/infrastructure/ime/ IME Kit、编辑器属性和文本预览适配
entry/src/main/ets/infrastructure/ai/  AI Provider、严格云代理/传输边界和正式不可用实现
entry/src/main/ets/infrastructure/speech/ 语音 Provider 接口和正式不可用实现
entry/src/main/ets/infrastructure/security/ IME 安全模式探测与能力快照
entry/src/main/ets/infrastructure/native/ Native 引擎网关和跨层类型
entry/src/main/ets/infrastructure/resource/ 生产词库资源安装
entry/src/main/ets/infrastructure/storage/ 设置、用户模型和用户词库沙箱路径
entry/src/main/ets/infrastructure/audio/ 按键音适配
entry/src/main/ets/infrastructure/haptic/ 震动适配
entry/src/main/ets/common/             共享错误和日志助手
entry/src/test/support/                AI/语音确定性 Fake，仅供主机测试且不进入 Release
entry/src/internalDebug/ets/pages/     内部 Debug 启动页、输入框验收页和码表验收页
entry/src/internalDebug/ets/infrastructure/resource/ Debug-only fixture 安装器
entry/src/internalDebug/resources/     Debug 入口覆盖和构建期内部 fixture；不进入 Release
entry/src/main/cpp/napi/               Node-API 导出和转换器
entry/src/main/cpp/bridge/             Rust C ABI 桥接和缓冲区所有权
entry/src/main/cpp/error/              原生错误码映射
entry/src/main/cpp/include/            Rust FFI C 头文件
engine-rust/crates/engine-protocol     跨层协议和错误定义
engine-rust/crates/ime-engine          正式引擎门面、候选会话、提交、学习和用户覆盖
engine-rust/crates/ime-ffi             生产 C ABI、panic 边界和 cfg(test) 回归边界
engine-rust/crates/pinyin-syllable     合法拼音音节集合与规范化
engine-rust/crates/shuangpin-schema    双拼方案模型、JSON 加载和配置校验
engine-rust/crates/shuangpin-parser    双拼编码解析与状态机
engine-rust/crates/lexicon-core        二进制词库、运行时索引、共享校验和 source_order
engine-rust/crates/candidate-query     Exact/Prefix/ExactOrPrefix 查询和缓存
engine-rust/crates/candidate-ranking   ExistingRanking/SourceOrder、去重和稳定排序
engine-rust/crates/context-reranker    会话内重排与有界确定性本地关联词
engine-rust/crates/sentence-decoder    多音节短句图与有界 Viterbi 解码
engine-rust/crates/user-model          自动学习、持久化和损坏恢复
engine-rust/crates/user-lexicon        #删/#固/#N 人工硬规则和可靠保存
engine-rust/tools/lexicon-builder      pinyin-tsv 与 flypy-table 离线构建工具
engine-rust/tools/user-lexicon-tool    用户词库校验和规范化导入工具
engine-rust/schemas/                   小鹤等双拼方案配置数据
engine-rust/tests/fixtures/            parser、候选、短句、学习和用户词库原创 fixture
dictionaries/generated/production.lex V2 构建的冻结基础词库输入；当前正式随包产物为 entry/src/main/resources/rawfile/production.lex
dictionaries/generated/quanpin-v2/    全拼 V2 各 profile 的确定性构建产物
dictionaries/source/test-fixtures/     码表顺序测试数据，不进入 Release HAP
码表/                                  客户交付码表导出；当前仅按冻结合同参与审计
小鹤音形/                              小鹤音形编号正式上游；路径属于来源合同
artifacts/                             可复现评测数据、清单和最终结果
examples/                              用户词库和匿名分布格式示例
scripts/                               PowerShell 构建、测试、Release 包门禁和设备验收入口点
tools/                                 独立验收客户端和 workspace 外入口说明
docs/architecture/                     项目结构、隐私和横切设计
docs/adr/                              架构决策记录
docs/product/                          规划、需求和客户反馈
docs/features/                         各产品能力的设计、实现和验收说明
docs/development/                      编码规则、工具链和开发辅助材料
docs/operations/                       发布与交付说明
docs/audits/                           数据来源、安全和冲突审计
docs/evidence/                         验收摘要及本地原始证据目录
docs/archive/                          非当前事实来源的历史报告
```

根目录的 `PROJECT_STATE.md` 是唯一当前状态入口。历史决策保存在 `docs/adr/`，历史验证日志、截图和布局树保存在 `docs/evidence/`，不再复制回当前状态文件。

Release 使用 `default` target，只消费 `entry/src/main`；内部验收使用 `internalDebug` target/source set。正式小鹤音形来源由根目录上游、`dictionaries/audit/xiaohe-yinxing/` 冻结合同和 `dictionaries/generated/xiaohe-yinxing-production/` 确定性产物共同约束，随包资源位于 `entry/src/main/resources/rawfile/`。
