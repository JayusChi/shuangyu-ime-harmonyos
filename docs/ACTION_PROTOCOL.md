# 受控动作协议

## 版本与边界

- ArkTS interface version：`9`
- Rust C ABI version：`9`
- engine version：`0.0.1-quanpin-features`
- 旧 interface `3` 创建请求必须拒绝。

动作协议只保留一个必填但可为 `null` 的单动作字段，不增加动作数组；版本 8 加入重复、撤销和当前行末定位。版本 9 只增加全拼创建配置并保持动作字段不变。

## CompositionResult

```typescript
interface CompositionResult {
  // 既有字段保持不变
  commitText: string
  action: ProtocolAction | null
  compositionFinished: boolean
}

type ProtocolAction = DateTimeTextAction | InsertPairAction |
  RepeatCommitAction | UndoCommitAction | MoveLineEndAction

interface DateTimeTextAction {
  type: 'DATE_TIME_TEXT'
  formatId: 'DATE_ISO' | 'DATE_LOCAL' | 'TIME_HM' | 'DATETIME_LOCAL'
  text: ''
  cursorOffsetUtf16: 0
}

interface InsertPairAction {
  type: 'INSERT_PAIR'
  formatId: ''
  text: string
  cursorOffsetUtf16: number
}

interface RepeatCommitAction {
  type: 'REPEAT_COMMIT'
  formatId: ''
  text: ''
  cursorOffsetUtf16: 0
}

interface UndoCommitAction {
  type: 'UNDO_COMMIT'
  formatId: ''
  text: ''
  cursorOffsetUtf16: 0
}

interface MoveLineEndAction {
  type: 'MOVE_LINE_END'
  formatId: ''
  text: ''
  cursorOffsetUtf16: 0
}
```

互斥规则：

```text
commitText 非空 => action 必须为 null
action 非空 => commitText 必须为空
普通候选刷新 => 两者都可为空
一次引擎操作 => 最多一个逻辑动作
```

`STATIC_TEXT`、`STATIC_SYMBOL`、`QUICK_SYMBOL` 在 Rust 动作表中是受控记录类型，但选择后仍返回 `commitText`。`DATE_TIME_TEXT`、`INSERT_PAIR`、`REPEAT_COMMIT`、`UNDO_COMMIT` 和 `MOVE_LINE_END` 跨层成为 `ProtocolAction`。

## 校验责任

- Rust：加载动作表、拒绝未知字段/类型/危险标记，决定唯一动作。
- C ABI：只把完整结果序列化为 UTF-8 JSON。
- C++：只校验必填字段、白名单枚举、长度、互斥关系并转换成 ArkTS 对象。
- ArkTS Gateway：再次执行同样的结构与互斥校验，缺失 `action` 字段也拒绝。
- ArkTS Executor：串行执行，绑定会话 generation，不解析命令字符串，不发起网络请求。

日期时间每次动作只读取一次 `TimeProvider.now()` 快照，然后按有限格式 ID 生成本地时间文本。成对符号以一次插入完成；提交后等待 80 ms 让编辑器光标状态稳定，再读取一次光标并定位。光标读取或定位失败后都不重复插入。

## 参数边界

- 动作 ID、编码、标签和文本均有固定长度上限。
- 编码只接受非空小写 ASCII。
- 文本拒绝控制字符、超长值及命令/URL/网络危险标记。
- `INSERT_PAIR.cursorOffsetUtf16` 必须严格位于文本内部，且为 `1..=16`。
- 光标偏移单位冻结为 UTF-16 code unit；ArkTS `string.length`、测试和 HarmonyOS 6.1 x86_64 ArkUI `TextInput` 设备探针均按该单位处理。设备证据记录插入后索引 `20`、目标索引 `15`、偏移 `5`。
- 未知动作、未知格式、跨类型参数、`commitText + action` 双提交均拒绝整个结果，不降级成普通文本。

## 数据隔离

动作 fixture 的冻结身份：

```text
path = engine-rust/tests/fixtures/code-table/stage11_6_6_actions.json
bytes = 2171
sha256 = 05a7653e44fe72c45b1b5b0dc1dc245baaafbc1f4becd5c2ec6c657687c59b63
fixtureOnly = true
```

它只能与 `code-table-fixture` 方案组合，只在 internalDebug 构建时临时复制，构建后立即清理；Release 源资源与最终 HAP 均不得包含它。
