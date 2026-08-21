# ADR 0016：产品分类使用不可变快照并原子跨层替换

## 状态

Accepted，阶段 11.6.5。

## 决策

Rust 是分类合同和业务校验的唯一权威。`CodeTableBundle` 生成版本化 `CategoryDefinition`，`CategorySelectionSnapshot` 保存 canonical 定义、enabled 顺序和集合。`CodeTableStateMachine` 通过 `Arc<RwLock<Arc<_>>>` 持有当前值；每个操作只捕获一次内部 `Arc`，分类更新在完整构建后单次交换并重算当前 raw。

跨层增加“读取分类配置”和“替换 enabled ID 列表并返回 `CompositionResult`”两个操作。ArkTS 只传递用户选择、串行化异步设置更新并执行 native-first/persist-second/失败回滚；C++ 只校验 Node-API 参数形状、转换 JSON 和转发 C ABI，不实现 required、canonical 顺序或候选规则。interface/ABI 从 2 同步升级到 3。

## 理由

单个不可变快照保证并发按键不会读到半新半旧分类；原子替换让“保留 raw、不提交、页码归零并重算”成为一个可测试结果。required 和顺序留在 Rust 可防止 ArkTS/C++ 漂移。设置持久化在 native 成功后执行，磁盘失败则恢复旧快照与旧组合。

## 后果

- 默认八类全开，`core` 必选。
- 未知运行时 ID 失败且旧状态不变；设置迁移可忽略未知值。
- 用户词库仍是独立 USER 层，功能动作仍被隔离。
- `xiaohe` 调用分类 API返回 unsupported，不改变双拼状态。
- 正式分类 UI 和 bundle 仍只在 internalDebug；Release 产品入口不变。

详细字段和值见 `docs/features/code-table/CODE_TABLE_CATEGORY_CONTRACT.md`。

## 2026-08-20 修订

完整直通语法尚未支持期间，`two-key-secondary`、`full-code-word`、`rare-character`、`full-code-character` 改为默认关闭，但仍保持可手动启用。该修订不改变不可变快照、原子替换、`core` 必选或用户词库边界；当前值以分类合同和正式 bundle manifest 为准。
