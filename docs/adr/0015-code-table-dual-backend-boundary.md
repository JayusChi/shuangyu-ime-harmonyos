# ADR 0015：阶段 11.6.1 独立码表双后端边界

- 状态：Accepted
- 日期：2026-07-15
- 原始范围：阶段 11.6.1 的需求与架构冻结
- 实施状态：阶段 11.6.3 已实现 fixture 系统查询子集；用户规则、分类开关、引导和三码长提交状态机仍待后续阶段

## 背景

当前 `ime-engine::ImeEngine` 直接持有 `ShuangpinParser`、拼音二进制词库查询器、`sentence-decoder`、`user-model`、用户词库快照和 `CandidateSession`。这条链路的输入语义是“小鹤双拼原始按键先解析为拼音，再按基础词频、整句分和用户学习排序”。

固定码表的语义不同：编码不转换为拼音；有精确码时不得混入更长编码；没有精确码时才按前缀回退；候选顺序由分类列表和 `source_order` 决定；用户规则是硬位置；自动上屏、空码清屏和顶屏依赖原始编码状态。把这些条件直接塞进现有双拼解析或 `ExistingRanking` 会造成以下问题：

- 原始码被错误解释为双拼音节；
- 码表源行顺序被基础词频、整句分或用户学习改写；
- 双拼路径被迫理解分类、引导表和固定码长状态；
- ArkTS 或 C++ 被迫猜测何时提交、清码或重放第五键；
- 码表资源故障可能污染当前稳定的 `xiaohe` 创建和输入行为。

现有代码已经提供可复用基础，但并未形成码表后端：`FlypyTableImporter`、`HSPLEX01` 1.1、`CandidateOrder::SourceOrder`、`QueryMode::ExactOrPrefix`、用户词库硬规则、候选会话、分页和 `CompositionResult`。

## 决策

### 统一门面和双后端

后续实现采用以下依赖边界；本阶段不创建空壳接口或占位类：

```text
ArkTS / C++ / Rust C ABI
            |
            v
        ime-engine                    # 统一门面、句柄和后端选择
            |
            v
        InputBackend                  # 等价名称可按实现风格调整
          /          \
         v            v
ShuangpinBackend   CodeTableBackend
  |                  |
  +-> ShuangpinParser +-> raw CodeTableStateMachine
  +-> production.lex +-> enabled category snapshot / guide table
  +-> sentence-decoder+-> ExactOrPrefix / SourceOrder
  +-> ExistingRanking +-> user-lexicon hard rules
  +-> user-model      +-> auto/empty/top commit decisions
```

`ime-engine` 是唯一统一门面，负责根据已验证的方案选择后端，并把后端结果装入公共的候选会话和 `CompositionResult`。后端选择与所有码表业务判断都在 Rust 内完成。

`ShuangpinBackend` 继续保留当前正式行为：`ShuangpinParser -> production.lex -> candidate-query / sentence-decoder -> ExistingRanking / user-model -> user-lexicon`。不得为了复用码表顺序而把小鹤双拼切换到 `SourceOrder`。

`CodeTableBackend` 直接处理原始编码，不得经过 `ShuangpinParser`、拼音音节转换、`production.lex` 拼音查询、`sentence-decoder`、`ExistingRanking` 或 `user-model` 软排序。

### 可以共享的公共外壳

- Engine Handle、C ABI buffer 所有权、panic 隔离和错误映射；
- 经过后端产生的完整最终候选列表所使用的 `CandidateSession`、分页和选择索引合同；
- `CompositionResult` 的组合、候选、提交文本和操作后状态表达；
- 用户词库文件的解析、不可变快照、保存和恢复基础；
- 二进制资源的版本、校验和、加载失败类型和脱敏日志原则；
- ArkTS 的 `EngineCoordinator`、`InputSessionController`、候选栏和 IME Kit 动作边界。

### 禁止共享的业务逻辑

- 双拼解析、拼音归一化和音节切分不得进入码表后端；
- `ExistingRanking`、整句评分和 `user-model` 软分不得排列码表候选；
- 分类顺序、`source_order`、引导状态和三码长判断不得进入双拼后端；
- ArkTS 和 C++ 不判断当前编码应自动上屏、清码、顶屏或重放；
- C++ 不因 `commitReason` 或后端类型实现状态机；
- `backendId` 不作为 UI 业务分支依据。

### 方案 ID 和产品门禁

- 默认且当前唯一正式方案继续是 `xiaohe`。
- 项目原创测试后端使用稳定内部 ID `code-table-fixture`；现有字符串 ID 允许连字符，无需另造同义 ID。
- 测试显示名称仅使用“码表输入（测试）”，只允许出现在 Rust 单元/集成测试或受保护的 Debug 验收中，不进入 Release 可选方案列表。
- 正式码表方案 ID 保留未确定状态。正式来源、版本、规则和随 HAP 再分发授权全部书面确认前，不得命名为“小鹤音形”，不得创建看似可用的产品入口。
- 不把第三方码表复制到仓库，不把来源不明或授权不完整的码表打入 HAP。

正式命名启用门禁要求同时满足：提供方与正式名称确认、版本固定、完整分类与引导表交付、规则书面确认、版权与许可证归档、修改/二进制转换/HAP 再分发权限确认、构建哈希可复现、Release 资源门禁和完整设备验收通过。缺一项则继续使用测试名称或保持入口不可用。

## 排序和状态机边界

码表查询及用户规则顺序冻结为：

```text
获取启用分类不可变快照
  -> 判定精确命中
  -> 仅在无精确命中时执行更长编码前缀回退
  -> 分类列表顺序、分类内 source_order
  -> #删
  -> 普通用户词
  -> #固
  -> 1-based #N
  -> 稳定去重
  -> 完整最终候选列表
  -> CandidateSession
  -> limit / 分页
```

空字符串返回空候选，不枚举码表。“空码”只表示非空编码既无最终精确候选、也不存在有效更长编码。完整状态表、引导状态和 reset 矩阵见 `docs/features/code-table/CODE_TABLE_BEHAVIOR_SPEC.md`。

码表后端的顶层状态图冻结为：

```text
Idle --普通字母--> NormalCode --退格至空/reset--> Idle
  |                    |
  |                    +--达到 top 后再输入普通键--提交至多一个首选/清旧段
  |                                                  |
  |                                                  +--当前键重放为新段首键
  +--分号--> GuidePrefix --字母--> GuideCode
                 |                     |
                 +--退格--> Idle       +--退格删至空--> GuidePrefix

任意状态 --方案/会话/编辑框/资源/异常 reset--> Idle
```

`GuidePrefix/GuideCode` 只查询专用引导表并跳过普通三码长。所有提交判断在 Rust 后端内完成，一次操作最多生成一个非空 `commitText`。

## 失败与回退

- 默认创建和默认设置始终选择 `xiaohe`。
- 码表资源缺失、损坏、格式或版本不兼容、校验失败时，故障只隔离码表后端，不破坏小鹤双拼资源或状态。
- 不得在输入过程中静默把码表原始编码交给双拼查询。运行中的码表组合遇到致命资源错误时先无提交 reset，再由设置/协调层产生可诊断的不可用状态并回退 `xiaohe`。
- 单个分类失效时优先隔离该分类；如果没有任何可用的必需分类或引导资源违反产品门禁，则整个码表方案不可用。
- 分类快照或参数更新必须原子替换；构建新快照失败时保留最后有效快照，不暴露半更新状态。
- Release 日志只能记录方案/资源的稳定 ID、版本、错误码和动作结果，不记录完整用户输入、用户词条、候选文本、编辑器内容或私人上下文。

## `CompositionResult` 与版本决策

现有合同足以表达“提交前一段首选，同时保留新一段组合”：`commitText` 表达本次唯一可见提交，`rawInput`、`preeditText`、候选和分页字段表达同一操作完成后的状态，`compositionFinished=false` 表示仍有组合。阶段 8 部分提交已经按此形状返回非空 `commitText + rawInput`。

因此本阶段：

- 不增加 `remainingRawInput`，它与操作后的 `rawInput` 同义；
- 不增加 `backendId`，后端选择不应泄漏为 ArkTS 业务判断；
- 不增加 `commitReason` 或 `clearReason`，当前动作执行不需要它们，测试可以用输入、输出和状态断言；
- ArkTS interface version 保持 `2`，Rust ABI version 保持 `2`，C ABI 函数和必填 JSON 字段不变；
- C++ 转换器会忽略 Rust JSON 中未查找的未知字段，但不会把它们转发给 ArkTS；ArkTS 规范化器也忽略额外属性。将来若确有动作执行所需字段，必须同步更新 Rust、C ABI JSON、C++、ArkTS 类型和兼容测试，不能只改一层。

当前 ArkTS `processChineseLetter` 只刷新预编辑和 store，并未执行 `processKey` 返回的 `commitText`；它也没有“看到 `commitText` 就无条件清空”的逻辑。阶段 11.6.8 接入码表时必须按不变量执行一次提交并继续展示返回的操作后组合，但这不是协议缺口，也不在本阶段提前实现。

## 后果

- 现有 `xiaohe` 正式运行、排序、资源和跨层版本保持不变。
- 阶段 11.6.2 可以在不实现运行时状态机的前提下先完成来源、许可和构建门禁。
- 后续码表实现需要新的 Rust 后端边界，但不得以大范围重构当前 `ImeEngine` 为前提。
- `CandidateSession` 必须接收用户硬规则处理后的完整列表，不能先分页再应用规则。
- 每次引擎操作最多返回一个非空 `commitText`；第五键重放不能产生第二次提交。

## 本阶段非目标

本 ADR 不实现码表查询、分类开关、分号路由、自动上屏、空码清屏、顶屏、第五键重放、设置入口或正式码表资源，也不宣称项目已支持“小鹤音形”。

## 实施记录（2026-07-15）

阶段 11.6.3 按本 ADR 在 `ime-engine` 落地 `Shuangpin/CodeTable` Rust 后端边界，并新增 `code-table-runtime` 的严格 bundle 加载、原始编码精确/前缀查询、稳定分类/source_order 合并、去重和分页。内部测试方案为 `code-table-fixture`，通过可选 `codeTableBundlePath` 接入，interface/ABI version 保持 2。上述实现没有改变本 ADR 对正式命名、授权、产品入口、用户规则、引导和三码长提交逻辑的限制。
