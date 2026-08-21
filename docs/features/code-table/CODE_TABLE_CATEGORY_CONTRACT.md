# 小鹤音形产品分类合同

状态：阶段 11.6.5 建立，2026-08-20 更新默认启用画像。运行时分类 schema version 为 `1`；合同来源是冻结正式 bundle 的 manifest，运行时不得扫描目录或猜测分类。

| order | id | 显示名称 | kind | defaultEnabled | required | userToggleable |
| ---: | --- | --- | --- | --- | --- | --- |
| 0 | `core` | 核心主表 | `PRIMARY` | true | true | false |
| 1 | `category-secondary` | 分类/次选 | `PRIMARY_EQUIVALENT` | true | false | true |
| 2 | `quick-symbol` | 快符 | `EXTENSION` | true | false | true |
| 3 | `one-key-secondary` | 一简次选 | `PRIMARY_EQUIVALENT` | true | false | true |
| 4 | `two-key-secondary` | 二简次选 | `PRIMARY_EQUIVALENT` | false | false | true |
| 5 | `out-of-table-character` | 表外字 | `EXTENSION` | true | false | true |
| 6 | `full-code-word` | 全码词 | `EXTENSION` | false | false | true |
| 7 | `symbol` | 符号 | `EXTENSION` | true | false | true |
| 8 | `symbol-group` | 符号组 | `EXTENSION` | true | false | true |
| 9 | `rare-character` | 生僻字 | `EXTENSION` | false | false | true |
| 10 | `full-code-character` | 全码字 | `EXTENSION` | false | false | true |

完整直通语法尚未支持，因此二简次选、全码词、生僻字、全码字默认关闭，需要时由用户手动开启；其余七类默认开启。空选择至少恢复 `core`；重复 ID 稳定去重；未知 ID 在运行时 API 中拒绝并保持旧快照，在设置迁移中忽略；最终 enabled 列表始终按合同 order 规范化。

## USER 与 FUNCTIONAL 边界

`USER` 是外部用户词库不可变快照，不是第十二个系统二进制分类。关闭系统分类不会删除用户新增词；针对已关闭系统候选的删除规则自然没有目标。`FUNCTIONAL` 用于引导、快符或命令动作，不进入普通系统候选、分类去重或分页；正式 bundle 不把外部用户层或动作层计入 11 个分类。

全码词来源中的 `#固` 和 `#直` 属于全码词分类自身，不属于外部用户词库：`#固` 在普通候选前建立不可跨越的置顶保护；`#直` 允许完整编码精确输入，但不参加反引号万能键反查。两者都随 `full-code-word` 开关启用或隐藏。外部用户词库仍保持独立，不受系统分类开关影响。

## 查询与状态语义

每次按键、退格、分页和分类更新在操作开始时捕获一个完整 `Arc<CategorySelectionSnapshot>`。查询顺序固定为：捕获快照 → 查询 enabled 系统分类 → 分类内 `source_order` → 跨分类稳定去重 → 用户规则 → 结果上限与分页。精确候选、前缀回退、有效更长编码和唯一精确候选都使用同一快照。

分类替换先在旧状态之外完成校验与构建，再一次交换 `Arc`。成功后保留 `rawInput`，页码归零，不产生 `commitText`，用新快照重算候选；无候选时仍保留 raw。失败时不替换快照、不修改组合、不持久化设置。

## 设置与可见性

当前设置 schema version 为 `8`，分类字段使用独立 schema version `4` 和 canonical enabled ID 数组。旧设置缺字段时迁移为当前七类默认集合；旧版“全部开启”快照会迁移为新默认，非全开自定义组合保持不变。重复、未知、乱序和空数组按上述规则规范化，迁移幂等。

分类模型、控制器、正式设置入口和 `.hsyx` bundle 均位于 main 产品链路。分类管理页的“重置为默认”使用上述七类集合，“全部启用”仍可作为显式手动操作。
