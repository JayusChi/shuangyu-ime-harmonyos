# ADR 0014：独立用户词库覆盖层

- 状态：Accepted
- 日期：2026-07-14

## 背景

系统 `production.lex` 是确定性构建的只读二进制词库；`user-model` 只保存候选稳定键的选择次数和逻辑最近使用信息。人工添加、删除、固顶和指定位置是可撤销硬规则，既不能改写系统词库，也不能伪装为学习分数。

## 决策

新增无第三方依赖的 `user-lexicon` crate，负责严格文本解析、最后规则覆盖、不可变快照、候选硬合并、规范化保存和主/备份恢复。第一阶段的编码与词条校验下沉到 `lexicon-core::validation`，系统 `FlypyTableImporter` 继续拒绝所有用户标记。

`ime-engine` 在既有系统查询、整句解码和 `user-model` 软排序之后调用覆盖层，在完整候选列表上完成删除、普通候选合并、固顶、指定位置和稳定去重，然后交给原候选会话分页。自定义候选使用 `user-lexicon-*` 命名空间 ID，不伪造系统词条 ID，也不进入现有用户学习文件。

ArkTS 只把沙箱内可选 `userLexiconPath` 放入 `EngineConfig`；C++ 只验证并转发字符串；Rust 读取并解析。缺失或损坏文件不会阻止系统引擎创建。该字段向后兼容，因此 C ABI/Node-API 函数签名、结构体布局和 interface/ABI version 2 均不提升。

## 依赖方向

```text
lexicon-core validation
        ^
        |
user-lexicon <--- ime-engine ---> user-model
        ^              |
        |              +--> candidate-query / candidate-ranking / sentence-decoder
user-lexicon-tool
```

`user-lexicon` 不依赖 `user-model`、候选查询、HarmonyOS 或 C++。`candidate-query` 不依赖覆盖层，避免改变默认生产查询策略。

## 后果

- 未配置路径时，候选输出保持阶段二修改前行为。
- 硬规则不能被基础频率、整句分或用户学习越过。
- 系统二进制词库、正式词条 ID、用户模型格式和键语义不变。
- 管理 UI、文件选择器和分类词库留给后续阶段。
