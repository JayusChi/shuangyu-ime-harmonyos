# 小鹤音形产品分类合同

状态：阶段 11.6.5 冻结。分类 schema version 为 `1`；合同来源是冻结正式 bundle 的 manifest，运行时不得扫描目录或猜测分类。

| order | id | 显示名称 | kind | defaultEnabled | required | userToggleable |
| ---: | --- | --- | --- | --- | --- | --- |
| 0 | `core` | 核心主表 | `PRIMARY` | true | true | false |
| 1 | `category-secondary` | 分类/次选 | `PRIMARY_EQUIVALENT` | true | false | true |
| 2 | `one-key-secondary` | 一简次选 | `PRIMARY_EQUIVALENT` | true | false | true |
| 3 | `two-key-secondary` | 二简次选 | `PRIMARY_EQUIVALENT` | true | false | true |
| 4 | `out-of-table-character` | 表外字 | `EXTENSION` | true | false | true |
| 5 | `full-code-word` | 全码词 | `EXTENSION` | true | false | true |
| 6 | `rare-character` | 生僻字 | `EXTENSION` | true | false | true |
| 7 | `full-code-character` | 全码字 | `EXTENSION` | true | false | true |

默认八类全部开启，以保持 11.6.3/11.6.4 正式系统候选基线。空选择至少恢复 `core`；重复 ID 稳定去重；未知 ID 在运行时 API 中拒绝并保持旧快照，在设置迁移中忽略；最终 enabled 列表始终按合同 order 规范化。

## USER 与 FUNCTIONAL 边界

`USER` 是外部用户词库不可变快照，不是第九个系统二进制分类。关闭系统分类不会删除用户新增词；针对已关闭系统候选的删除规则自然没有目标。`FUNCTIONAL` 预留给引导、快符或命令动作，不进入普通系统候选、分类去重或分页。本阶段没有将任何正式 bundle 分类标为 `USER` 或 `FUNCTIONAL`，也没有实现后续阶段的功能动作。

## 查询与状态语义

每次按键、退格、分页和分类更新在操作开始时捕获一个完整 `Arc<CategorySelectionSnapshot>`。查询顺序固定为：捕获快照 → 查询 enabled 系统分类 → 分类内 `source_order` → 跨分类稳定去重 → 用户规则 → 结果上限与分页。精确候选、前缀回退、有效更长编码和唯一精确候选都使用同一快照。

分类替换先在旧状态之外完成校验与构建，再一次交换 `Arc`。成功后保留 `rawInput`，页码归零，不产生 `commitText`，用新快照重算候选；无候选时仍保留 raw。失败时不替换快照、不修改组合、不持久化设置。

## 设置与可见性

设置 schema version 为 `2`，分类字段包含独立 schema version 和 canonical enabled ID 数组。旧设置缺字段时迁移为八类全开；重复、未知、乱序和空数组按上述规则规范化，迁移幂等。

分类模型、控制器和可复用行组件位于 main 层，但可见入口只存在于 `entry/src/internalDebug`。Release 的默认设置页、页面清单和资源不显示小鹤音形分类，也不包含冻结 `.hsyx` bundle。
