# 受控动作协议

## 版本与边界

- ArkTS interface version：`11`
- Rust C ABI version：`11`
- engine version：`0.0.1-direct-display`
- 旧 interface `3` 创建请求必须拒绝。

动作协议只保留一个必填但可为 `null` 的单动作字段，不增加动作数组；版本 10 加入经过白名单校验的分类控制和已授权用户词库源导入动作，版本 11 为候选增加独立的 `displayText`，使直通提示与实际 `text` 上屏内容可以安全分离。

## CompositionResult

```typescript
interface CompositionResult {
  // 既有字段保持不变
  commitText: string
  action: ProtocolAction | null
  compositionFinished: boolean
}

type ProtocolAction = DateTimeTextAction | InsertPairAction |
  RepeatCommitAction | UndoCommitAction | MoveLineEndAction |
  DirectControlAction | ImportUserLexiconAction

interface DateTimeTextAction {
  type: 'DATE_TIME_TEXT'
  formatId: 'DATE_ISO' | 'DATE_LOCAL' | 'DATE_LOCAL_UNPADDED' | 'TIME_HM' | 'TIME_HMS' |
    'TIME_LOCAL_HMS' | 'TIME_WEEKDAY' | 'TIME_LOCAL_HM' | 'LUNAR_DATE_FESTIVAL' |
    'DATETIME_LOCAL' | 'UNIX_TIMESTAMP'
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

interface Candidate {
  text: string        // 选择后实际提交内容
  displayText: string // 仅候选展示；空字符串表示使用 text
  reading: string
}

interface DirectControlAction {
  type: 'DIRECT_CONTROL'
  formatId: 'category.enable' | 'category.disable' | 'category.toggle' |
    'category.set' | 'category.all' | 'category.core' | 'category.preset' |
    'settings.smart-period' | 'settings.punctuation' | 'settings.fullwidth' |
    'settings.traditional' | 'settings.numeric-period' | 'settings.empty-clear' |
    'settings.commit-policy' | 'url.open' | 'app.open' | 'editor.delete-line'
  text: string
  cursorOffsetUtf16: 0
}

interface ImportUserLexiconAction {
  type: 'IMPORT_USER_LEXICON'
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

`STATIC_TEXT`、`STATIC_SYMBOL`、`QUICK_SYMBOL` 在 Rust 动作表中是受控记录类型，但选择后仍返回 `commitText`。其余需要编辑器或设置副作用的动作跨层成为 `ProtocolAction`。

## 校验责任

- Rust：加载动作表、拒绝未知字段/类型/危险标记，决定唯一动作。
- C ABI：只把完整结果序列化为 UTF-8 JSON。
- C++：只校验必填字段、白名单枚举、长度、互斥关系并转换成 ArkTS 对象。
- ArkTS Gateway：再次执行同样的结构与互斥校验，缺失 `action` 字段也拒绝。
- ArkTS Executor：串行执行，绑定会话 generation，不解析命令字符串，不发起网络请求。

日期时间每次动作只读取一次 `TimeProvider.now()` 快照，然后按有限格式 ID 生成本地时间文本。成对符号以一次插入完成；提交后等待 80 ms 让编辑器光标状态稳定，再读取一次光标并定位。成功后保存受会话与 120 秒有效期约束的右符号状态，Tab/Enter 跳出前再次核对编辑器；光标读取或定位失败后都不重复插入。

客户确认的生产动作只来自 Rust 内建动作表。网址仅允许 `flypy-home`、`flypy-help`、`flypy-help-mobile` 三个固定目标，由 ArkTS 映射为预置 HTTPS；应用入口仅允许本应用设置页和用户词库页；删行先用有界编辑器查询计算当前行范围，再执行一次删除。设置动作的参数也全部闭合：智能句号仅 `0/600`，数字句点仅 `enabled/disabled`，空码阈值仅 `4/12`，四码策略仅 `top-screen/auto-commit`，三组词库预设只改变全码词、全码字、生僻字。

`ohos.permission.READ_PASTEBOARD` 的平台定义要求 `system_basic` APL，而客户测试包为 normal APL。因而 `ofi` 的“复制单字反查且不粘贴”没有进入正式动作表，Release 也不声明剪贴板读取权限；该项必须等待替代交互或系统级签名条件确认。

## 参数边界

- 动作 ID、编码、标签和文本均有固定长度上限。
- 编码只接受非空小写 ASCII。
- 外部 fixture 文本拒绝控制字符、超长值及命令/URL/网络危险标记；发布内置动作由源码白名单逐项编译，不从客户脚本求值。
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
