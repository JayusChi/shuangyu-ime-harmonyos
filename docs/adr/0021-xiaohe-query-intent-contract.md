# ADR 0021：小鹤双拼查询意图与键位歧义合同

## 状态

Accepted（候选词改进阶段 4，2026-07-28）。

## 背景

小鹤双拼的同一个键可能同时出现在声母映射、韵母映射或零声母规则中。此前 parser 只输出
`Empty/Incomplete/Complete/Invalid/Ambiguous`，`ime-engine` 再根据
`pending_code` 和 `syllables.len()` 推测使用精确查询、前缀查询或句子解码。

这种推测存在真实歧义：`lo` 在当前方案中合法解析为 `lo/luo` 两个精确 reading，但它们是同一个
双键音节的合法解释。旧引擎会因 `syllables.len() == 2` 将其误判为两个连续音节并送入句子解码。
按键长度、解析候选数量或词库顺序都不应成为产品语义。

## 决策

### 统一查询意图

`shuangpin-parser::ParseResult` 固化以下 `QueryIntent`，下游只能按该字段选择路径：

| 查询意图 | 定义 | Rust 执行路径 | 排序合同 |
| --- | --- | --- | --- |
| `Empty` | 没有输入 | 清空候选会话 | 无 |
| `SingleKeyPrefix` | 一个合法单键 | `QueryMode::Prefix` | 阶段 3 的完整索引遍历＋有界全局 Top-K＋现有用户重排 |
| `CompleteSyllable` | 一个合法双键完整音节；可含多个方案声明的精确 reading | 对每个合法 reading 执行 `QueryMode::Exact`，合并去重后使用现有精确排序并保持 64 项上限 | 精确匹配优先，随后沿用现有频率与稳定 tie-breaker |
| `IncompleteSyllable` | 一个完整音节后带一个待完成键 | 对“完整 reading＋待完成前缀”执行 `QueryMode::Prefix` | 现有前缀排序 |
| `MultiSyllable` | 至少两个完整双键音节，可再带待完成尾键 | 现有 `sentence-decoder` | 现有句子评分、切分和用户分 |
| `Invalid` | 非法键、非法双键或非法边界 | 清空候选会话，保留可退格恢复的原始输入 | 无 |

parser 按小鹤确定性的两键切分和方案校验生成逻辑音节槽位与意图。一个槽位的多个合法 reading
共享同一 `logical_index`，因此歧义 reading 的数量不等于音节数量。`ime-engine` 不再检查
`syllables.len()` 来猜测是否应进入句子解码。

### 单键合同

一个合法单键表示“声母或规范拼音前缀”，不表示该键在韵母表中的单独韵母：

- `h` 是前缀 `h`，召回 `ha/hai/.../he/.../huo` 等 `h*` reading；不混入 `ang`。
- `a` 是前缀 `a`。当前方案允许的零声母 reading（例如 `a/ai/an/ang/ao`）可按正常拼音前缀命中。
- `o` 是前缀 `o`。当前方案允许的 `o/ou` 等 reading 可按正常拼音前缀命中。

`h` 的韵母映射 `ang` 只在它作为完整双键的第二键且组合通过合法音节校验时生效。不得为了增加
候选数量将单键声母/前缀候选与韵母候选混合，也不得依靠词库遍历顺序决定单键含义。

### 双键、零声母与特殊音节

双键只有在当前方案集中规则层生成合法音节后才是 `CompleteSyllable`：

- `hc → hao`
- `ni → ni`
- `ui → shi`
- `vi → zhi`
- `aa → a`、`oo → o` 来自当前 `zero_initial` 配置

零声母规则、声母映射、韵母映射、特殊音节和合法音节过滤继续唯一来源于
`engine-rust/schemas/xiaohe.json`、`shuangpin-schema` 和 `pinyin-syllable`，候选查询函数不硬编码
小鹤键表。非法双键进入 `Invalid`，不会伪造 reading。

当单个双键存在多个合法精确 reading（当前例：`lo → lo/luo`），所有方案声明的 reading 都按
精确查询处理；合并后使用现有确定性精确排序。规则不读取词库的物理遍历顺序。

歧义双键位于多音节输入时，现有句子解码器尚不支持一个槽位的 reading 分支图，因此采用集中且
可测试的规范化规则：每个逻辑槽位选择方案声明顺序中的第一个合法 reading，再进入句子解码。
例如 `loni` 使用 `lo ni`，不会由词库中 `lo ni/luo ni` 的频率或物理顺序反向决定按键解释。
未来若句子解码器支持 reading 分支图，可在保持 `QueryIntent` 和槽位边界不变的前提下扩展。

### 多音节、部分提交与删除

两个或更多完整音节进入现有句子解码；待完成尾键由现有 pending-tail 逻辑处理。句子候选的部分
提交继续由 Rust 返回 `commitText` 和剩余组合。

状态转换如下：

| 操作 | 示例 | 查询意图 | 会话要求 |
| --- | --- | --- | --- |
| 输入首键 | `"" → h` | `SingleKeyPrefix` | 新前缀快照，第 0 页 |
| 输入第二键 | `h → hc` | `CompleteSyllable` | 丢弃前缀快照，精确快照，第 0 页 |
| 输入第三键 | `hc → hcn` | `IncompleteSyllable` | 丢弃精确快照，新前缀快照，第 0 页 |
| 完成下一音节 | `hcn → hcni` | `MultiSyllable` | 丢弃词查询快照，句子快照，第 0 页 |
| 从句子退格 | `nihc → nih` | `IncompleteSyllable` | 丢弃句子快照，新前缀快照，第 0 页 |
| 再退格 | `nih → ni` | `CompleteSyllable` | 丢弃前缀快照，精确快照，第 0 页 |
| 再退格 | `ni → n` | `SingleKeyPrefix` | 丢弃精确快照，新单键快照，第 0 页 |
| 删除到空 | `n → ""` | `Empty` | 候选、页码、前后页标志全部清空 |

### 层间职责

- parser：基于方案和原始按键输出解析结果与唯一 `QueryIntent`。
- query：由 `QueryIntent` 选择精确或前缀召回；不重新解释按键。
- ranking：精确/前缀候选继续使用现有 `CandidateMatchType` 与排序合同；多音节继续使用句子评分。
- C++/FFI：只转发既有组合 JSON 和命令，不解析双拼语义。
- ArkTS/UI：原子应用 Rust 返回的 `rawInput/parserState/candidates/page`，只展示候选，不自行推导
  声母、韵母、简拼、召回或排序含义。

`QueryIntent` 是 Rust 核心内部合同，不新增跨语言字段；这样 UI 不需要也不能复制语义判断，同时
保持现有 interface/ABI version 和候选提交 ABI 不变。

## 非目标与限制

- 本阶段不实现词语首字母简拼；单键 `h` 不因本阶段专门召回“很好、回来、还是”。
- 未新增简拼设置项。
- 未修改阶段 3 的 256 项召回池、128 项前缀快照或全局 Top-K。
- 未修改现有词频、用户学习公式、句子评分、正式词库或小鹤音形语义。
- `IncompleteSyllable` 当前按既有连续 reading 前缀查询；更自由的混合简拼属于后续独立设计。
- 设备端快速输入、旋转、第三方输入框和 ARM64 真机仍属于后续发布验收。

## 自动化对应

- `shuangpin-parser/tests/stage4_cases.rs`：意图分类、`h/a/o`、完整双键、歧义双键和逐级退格。
- `ime-engine/src/formal.rs`：单键前缀隔离、精确双键、歧义精确合并、句子与逐级回退。
- `entry/src/test/CandidateStage4Contract.test.ets`：UI Store 原子替换引擎快照，不残留旧候选或分页。
- 既有阶段 0～3、句子、部分提交、小鹤音形测试继续作为回归门禁。
