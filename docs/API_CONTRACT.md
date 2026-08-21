# API 契约

## 26 键全拼有界纠错与模糊音配置

当前 ArkTS interface version 与 Rust ABI version 同步为 `9`，engine version 为
`0.0.1-quanpin-features`。C ABI 函数签名不变；版本提升用于阻止旧 Native 丢弃新增
`EngineConfig` 字段后仍创建引擎。配置新增：

```typescript
quanpinConfigVersion?: number       // 当前只接受 1
spellingCorrectionEnabled?: boolean // 缺省 false
fuzzyOptions?: FuzzyOptionId[]      // 缺省 []，最多 8 项
```

`FuzzyOptionId` 的封闭集合为 `n_l`、`z_zh`、`c_ch`、`s_sh`、`in_ing`、`en_eng`、
`an_ang`、`ian_iang`。Native 将字段原样编码进 Rust 配置 JSON；未知选项、错误类型、
错误配置版本或超过 8 项均拒绝创建。纠错后的拼音不进入跨层结果，`rawInput` 始终保留
用户原始按键，纠错/模糊候选的 `consumedRawLen` 覆盖原始输入长度。

设置 schema version 为 `8`。迁移缺省关闭全拼纠错/模糊音，智能句号窗口缺省为 500 毫秒；设置变更通过创建并恢复完整运行时
状态的新 Rust handle 事务式应用，成功后才替换旧 handle 和持久化快照。创建或持久化失败
时恢复最后有效配置。输入法进程冷启动从共享的同一 schema 8 快照恢复；非 `quanpin`
profile 不执行扩展，切回 `quanpin` 时继续使用已保存的全拼设置。

## 26 键全拼和 9 键计划阶段 4：九键 UI 动作合同

ArkTS 新增键盘语义动作：

```typescript
KeyboardActionType.T9_PINYIN_DIGIT
digit: string // 仅 "2".."9"
```

该动作只能在中文、非密码、活动编辑会话且当前 Native 方案为 `pinyin-9` 时执行，并调用既有 `processKey(handle, digit)`。它不能进入普通 `CHARACTER` 或编辑器 `insertText` 分支。数字键盘中的 `2`～`9` 继续使用 `CHARACTER`，两种语义不可互换。

本阶段没有新增 Node-API/C ABI：阶段 3 的 `processKey` 已包含 T9 数字合同，`selectPinyinCombination` 已包含组合选择合同；interface/ABI 保持 `7`。`currentPinyin` 和 `pinyinCombinations` 仍完全来自 Rust，ArkTS 只按原顺序展示。`1` 使用既有符号模式动作，`0` 使用 `insertSegmentBoundary`，删除使用 `backspace`，均不进入 T9 数字动作。

## 26 键全拼和 9 键计划阶段 3：T9 组合选择

当前 ArkTS interface version 与 Rust ABI version 同步为 `7`，engine version 为 `0.0.1-pinyin-stage3`。`CompositionResult` 继续使用：

```typescript
currentPinyin: string
pinyinCombinations: string[]
```

T9 的 `rawInput` 只允许 `2`～`9` 数字。`currentPinyin` 与 `pinyinCombinations` 是 Rust 返回的规范标准拼音；显式分音边界不写入 raw input。`displaySegments` 由 Rust 按数字分段生成。C++/ArkTS 不允许从数字展开字母、重建音节、排列路径或重排候选。

新增跨层操作：

```typescript
selectPinyinCombination(handle: number, combinationIndex: number): CompositionResult
```

对应 C ABI：

```c
int32_t ime_engine_select_pinyin_combination(
    ImeEngineHandle handle,
    size_t combination_index,
    ImeBuffer* out_buffer);
```

`combinationIndex=0` 选择当前 `currentPinyin`；`1..N` 依次选择 `pinyinCombinations[0..N-1]`。成功后返回完整刷新结果，候选和分页从第一页重建；越界、非 `pinyin-9` 方案或无有效组合返回错误并保持原状态。

引擎正式支持 `schemeId=pinyin-9` 的创建与方案切换；阶段 4 已启用对应 `KeyboardProfile` 和正式九宫格 UI。`processKey` 在该方案只接受 `2`～`9`；其他拼音/码表方案保持原有键合同。

候选 `consumedRawLen` 继续表示部分提交消费的 raw 长度；T9 按候选标准拼音的数字签名计算，例如 `ni hao` 对 `64426` 消费 5 位。自动学习的方案 ID 为 `pinyin-9`，与 `quanpin`、`xiaohe` 隔离。完整算法、上限和验收见 `PINYIN_STAGE3_T9_ENGINE.md`。

## 26 键全拼和 9 键计划阶段 2：全拼与通用拼音结果

当前 ArkTS interface version 与 Rust ABI version 同步为 `6`，engine version 为
`0.0.1-pinyin-stage2-quality4`。阶段 1 新增的两个必填字段继续保持：

```typescript
currentPinyin: string
pinyinCombinations: string[]
```

`displaySegments`、`currentPinyin` 和 `pinyinCombinations` 均由 Rust 解析器生成。
C++ 只校验并转发；ArkTS 只保存和展示，不得按字符长度重建音节或排列拼音路径。
现有小鹤双拼返回规范化的当前拼音，且没有多选路径时
`pinyinCombinations=[]`。码表方案和错误结果返回空的拼音字段。协议层不再提供“两码一段”
默认实现；具体分段属于解析器合同。

键盘设置的唯一产品入口是 `keyboardProfileId`。`schemeId` 是经过档案校验后派生给引擎的值，
不能与布局偏好独立组合。`quanpin-26` 已启用并映射到 `schemeId=quanpin` 与 QWERTY 26 键布局；
`pinyin-9` 在阶段 2 交付时保持禁用，当前已由阶段 4 正式启用。

全拼连续输入由 Rust 返回首选标准拼音路径和有界备选路径。`xian` 的首选为 `xian`，备选可包含 `xi'an`；显式 `xi'an` 不允许跨边界合并。未完成输入通过 `pendingCode` 和 prefix 查询意图进入既有候选链。FFI/C++/ArkTS 不拆分全拼。

## 阶段 12 直通与用户词库管理

阶段 12 发布时 ArkTS interface version 与 Rust ABI version 同步为 `5`，engine version 为 `0.0.1-stage12`。该阶段的 `CompositionResult` 字段保持不变；新增以下管理接口：

```typescript
reloadUserLexicon(handle: number): CompositionResult
loadUserLexicon(path: string): UserLexiconDocument
saveUserLexicon(path: string, expectedRevision: string, content: string): UserLexiconDocument
```

对应 C ABI 为 `ime_engine_reload_user_lexicon`、`ime_user_lexicon_load`、`ime_user_lexicon_save`。管理文档包含 `success/errorCode/errorLine/errorField/message/warningCode/revision/entries/stats`。保存中的格式错误和 revision 冲突作为结构化文档返回；无效指针、UTF-8 或句柄仍使用 C ABI 错误码。

`saveUserLexicon` 必须先完整解析内容，再比较磁盘当前 revision，匹配后才执行原子保存。`reloadUserLexicon` 只在完整加载成功时替换引擎不可变快照；运行时恢复为空或失败时保留最后有效快照。

直通命令不是 Native ABI 字段。ArkTS 使用封闭 `action + target` 合同，并统一调用现有 SettingsController；完整命令表见 `STAGE12_DIRECT_CONTROL_USER_LEXICON.md`。

## 阶段 11.6.7 四码提交与顶屏

当前 interface/ABI 继续为 `4`，engine version 为 `0.0.1-stage11.6.7`。没有新增字段、C ABI 函数或 Node-API。

码表 `processKey` 可以返回：

```text
commitText = 旧四码段最终首选
rawInput/preeditText/candidates/page = 同一按键处理后的新段
action = null
compositionFinished = false
```

四码唯一自动提交则返回非空 `commitText`、空 `rawInput/candidates`、`action=null` 和 `compositionFinished=true`。一次结果最多一个非空 `commitText`；`commitText` 与 `action` 继续互斥。

Rust 是完整候选唯一性、有效更长编码、顶屏、第五键单次重放和空码清屏的唯一决策层。C++ 只校验/转换。ArkTS 收到非空 `commitText` 时只执行一次 `commitPreviewText`；若同一结果仍有 `rawInput`，提交成功后继续设置新段预览并保存该结果。提交失败必须 reset 并返回失败。

正向/反向空码切分合同已由 ADR 0018 冻结并属于当前可用行为；两条路径继续复用同一个
`commitText + rawInput` 结果，不新增协议字段。

## 阶段 11.6.6 单动作扩展

当前 interface/ABI 为 `4`，engine version 为 `0.0.1-stage11.6.6`。`CompositionResult` 包含必填 `action` 和 `displaySegments` 字段；`action` 只能为 `null`、`DATE_TIME_TEXT` 或 `INSERT_PAIR`。`commitText` 非空与 `action` 非空严格互斥；缺失字段、未知动作、未知格式、超长参数或双提交均作为序列化/桥接错误拒绝。新增 JSON 展示字段不改变 C ABI 函数签名或 interface version。

`EngineConfig` 为 internalDebug 动作 fixture 增加可选 `codeTableActionFixturePath` 和 `codeTableActionFixtureSha256`。生产 `xiaohe` 与正式 `xiaohe-yinxing` 均拒绝 fixture 动作表，Release 不提供这些字段或资源。完整字段、参数和责任边界见 `ACTION_PROTOCOL.md`。

`processKey` 在码表后端额外接受 `;` 作为 Rust 引导状态机输入；`xiaohe` 明确拒绝该引擎键，ArkTS 随后按既有普通符号路径处理，不在 ArkTS 中复制方案状态机。

## Stage 3.5 系统输入法边界

Pad/Phone 输入法切换完全位于 ArkTS `InputMethodSwitcher` 适配器与 IME Kit 之间，没有新增或修改 Node-API、C++、C ABI、Rust Engine Handle、组合结果 JSON 或词库格式。UI 只发送 `SWITCH_INPUT_METHOD`、`SHOW_INPUT_METHOD_PICKER` 和既有 `HIDE_KEYBOARD` 语义动作；因此 3.5 不改变本文件以下跨语言 ABI 合同。

## 原生模块

- 共享库：`libime_bridge.so`
- CMake 目标：`ime_bridge`
- Node-API 模块名：`ime_bridge`
- ArkTS 导入只允许在 `NativeEngineGateway.ets` 中出现：`import imeBridge from 'libime_bridge.so';`

## 版本

| 项 | 值 |
| --- | --- |
| 当前 ArkTS interface version | `9` |
| 当前 Rust ABI version | `9` |
| 当前 engine version | `0.0.1-quanpin-features` |
| Stage 0 fixed-candidate result version | `0.0.1-stage0` |

`createEngine` 同时检查 ArkTS interface version 与 Rust ABI version。任一不匹配时拒绝创建引擎。

当前契约在既有 `createEngine` JSON 配置中支持可选字符串 `userLexiconPath`。阶段 11.6.5 新增分类配置读取和原子替换操作，因此 ArkTS interface 与 Rust ABI 同步升级到 `3`；不支持新旧桥接库混装。

## ArkTS 设置契约

`SettingsController` 是设置页面唯一写入口。Preferences 写入成功后才发布新的 `SettingsStore` 快照；写入失败时内存状态不前移。配置 schemaVersion 当前为 `8`，`keyboardProfileId` 是方案与布局的唯一真实来源；`schemeId` 只作为派生兼容字段持久化。未知或尚未启用的档案安全回退到 `xiaohe-26`。正式码表分类先在 native 原子替换，成功后再保存；保存失败恢复旧分类和旧组合。

主 Ability 的 Preferences 是 canonical 设置存储；成功写入后把同一规范化 schema 8 快照发布到
本包 `SHARED_CONFIG` DataProxy，供 `:inputMethod` 进程冷启动读取。输入法进程不写 canonical
Preferences。Preferences 或共享快照任一步保存失败时必须恢复上一个持久化快照；不能发布一个
Native 未生效或只在单进程可见的方案状态。完整决策见 ADR 0019。

`smartPeriodTimeoutMs` 取值为 `0..2000` 的整数，`0` 表示关闭，默认为 `500`。中文句号的两次按键到达间隔不大于该值、且两次之间没有其他输入动作时，输入法才核对并尝试将光标前的 `。` 替换为单个 `.`；核对失败或超时时仅插入新的 `。`。

用户学习的有效会话值为：

```text
settings.userLearningEnabled && editorContext.learningAllowed
```

密码与数字密码上下文的 `editorContext.learningAllowed` 永远为 false。设置页不得直接导入 `libime_bridge.so`。

MainAbility 与 InputMethodExtensionAbility 之间的清空命令使用仅定向本包的 Common Event；事件只表达“执行清空”，不携带输入、候选或用户模型内容。输入法侧收到后仍调用既有 `clearUserModel` 契约，因此没有新增 Node-API/C ABI。

## ArkTS 正式接口

```typescript
export interface NativeImeEngine {
  getInterfaceVersion(): number
  getEngineVersion(): string

  createEngine(config: EngineConfig): number
  destroyEngine(handle: number): void

  processKey(handle: number, key: string): CompositionResult
  insertSegmentBoundary(handle: number): CompositionResult
  backspace(handle: number): CompositionResult
  reset(handle: number): CompositionResult
  changeScheme(handle: number, schemeId: string): CompositionResult
  selectCandidate(handle: number, candidateIndex: number): CompositionResult
  nextCandidatePage(handle: number): CompositionResult
  previousCandidatePage(handle: number): CompositionResult
  getCodeTableCategoryConfig(handle: number): CodeTableCategoryConfig
  setCodeTableCategories(handle: number, enabledCategoryIds: string[]): CompositionResult

  setUserModelPath(handle: number, path: string): UserModelStatus
  loadUserModel(handle: number): UserModelStatus
  flushUserModel(handle: number): UserModelStatus
  clearUserModel(handle: number): UserModelStatus
  setUserLearningEnabled(handle: number, enabled: boolean): UserModelStatus
  setSessionLearningAllowed(handle: number, allowed: boolean): UserModelStatus
}
```

分类配置返回 schema、canonical 定义和 enabled ID；替换操作成功时返回按新快照重算的 `CompositionResult`，必须 `commitText=''`、保留 raw、页码归零。未知 ID 返回结构化失败并保持旧快照。正式字段合同见 `CODE_TABLE_CATEGORY_CONTRACT.md`。

```typescript
export interface EngineConfig {
  interfaceVersion: number
  schemeId: string
  lexiconPath?: string
  codeTableBundlePath?: string
  codeTableActionFixturePath?: string
  codeTableActionFixtureSha256?: string
  userLexiconPath?: string
  candidatePageSize?: number
  quanpinConfigVersion?: number
  spellingCorrectionEnabled?: boolean
  fuzzyOptions?: FuzzyOptionId[]
}
```

`lexiconPath` 是 ArkTS 从 rawfile 安装到应用沙箱后的绝对路径。ArkTS 只复制资源和传递路径，不解析词库内容。测试可以省略 `lexiconPath` 来验证“词库未加载”错误。

`codeTableBundlePath` 是码表 bundle 的沙箱绝对路径：`schemeId='code-table-fixture'` 使用通用测试包，`schemeId='xiaohe-yinxing'` 使用严格冻结的正式包。两者只用于测试或 Debug-only 验收；Release 产品配置不提供这些方案或资源。

`userLexiconPath` 是沙箱内可选用户文本词库路径。未传、空字符串或文件不存在表示空覆盖层；空文件同样有效。Rust 必须先完整解析并生成不可变快照才参与候选合并。损坏用户词库不得导致系统 `production.lex` 加载或引擎创建失败。格式与恢复合同见 `USER_LEXICON_FORMAT.md`。

```typescript
export type ParserState =
  | 'empty'
  | 'incomplete'
  | 'complete'
  | 'invalid'
  | 'ambiguous'

export interface Candidate {
  id: string
  text: string
  reading: string
  source: string
}

export interface CompositionResult {
  success: boolean
  errorCode: number
  errorMessage: string
  rawInput: string
  preeditText: string
  parsedSyllables: string[]
  displaySegments: string[]
  currentPinyin: string
  pinyinCombinations: string[]
  segmentBoundaries: number[]
  pendingCode: string
  parserState: ParserState
  candidates: Candidate[]
  highlightedIndex: number
  hasNextPage: boolean
  hasPreviousPage: boolean
  candidatePage: number
  commitText: string
  action: ProtocolAction | null
  compositionFinished: boolean
}
```

`displaySegments` 是 Rust 解析器生成的原始输入码展示段。现有小鹤适配器保持历史两码分段，奇数
尾码保留为最后一段，显式 `'` 边界重置分段；其他解析器可以按自己的语义返回分段。
ArkTS 只使用 `'` 连接非空段；字段缺失或非法时安全回退显示未修改的 `rawInput`，
不得在 UI 重新解析音节。显示分隔符不进入 `rawInput`、`preeditText`、查询键、
用户模型或 `commitText`。

`currentPinyin` 是解析器当前首选的规范化拼音路径；`pinyinCombinations` 是需要用户消歧时的
有界备选路径。普通双拼没有多选时必须返回空数组。阶段 2 已启用全拼解析器；9 键解析器仍未启用。

## 阶段 3.3 中文动态键与显式分词契约

- `insertSegmentBoundary` 是结构化引擎动作，不能通过 `processKey("'")` 伪装普通字符输入；UI、Controller、Node-API 和 C ABI 均有独立入口。
- `segmentBoundaries` 记录每个显式边界之前的 ASCII 原始编码字母数。`rawInput` 可在预编辑展示中包含 `'`，但该字符不得进入 `commitText`、用户学习键或最终编辑器提交。
- 空组合、连续边界或不完整尾段上的边界请求返回 `INVALID_ARGUMENT`，并保持请求前的引擎组合、候选和页码不变。
- 退格先删除末尾边界，再按既有规则删除编码字母；候选提交继续走既有 `selectCandidate` 路径。部分候选消费边界时，剩余 `rawInput` 会移除前导边界。
- 当前仅小鹤双拼后端支持显式分词；码表 fixture 后端拒绝该动作。并发、generation 与编辑框预览回滚继续由既有串行队列和会话隔离规则负责。
- 中文大写直输是 ArkTS 会话状态，不属于 Rust 组合：仅在中文且组合为空时启用，A-Z 直接提交编辑器，不查询候选、不产生预编辑、不学习；模式、编辑框、会话、隐藏、失焦、恢复性重置或 Ability 销毁都会清除该状态。

```typescript
export interface UserModelStatus {
  loaded: boolean
  enabled: boolean
  sessionLearningAllowed: boolean
  dirty: boolean
  recordCount: number
  formatVersion: number
  dataVersion: number
  lastErrorCode: string
}
```

`UserModelStatus` 只暴露状态和计数，不返回候选文本、原始输入、学习记录明细或上下文。

阶段 7 起，正式链路不再固定返回空候选。候选由 Rust 查询、去重、排序和分页后返回：

```text
candidates = 当前页候选
highlightedIndex = candidates 非空时 0，否则 -1
hasNextPage / hasPreviousPage = Rust 候选会话状态
candidatePage = Rust 当前页索引，0-based
```

`selectCandidate(handle, candidateIndex)` 的索引基于当前页候选数组。成功选择完整覆盖当前组合的候选时返回：

```text
commitText = 选中候选文本
compositionFinished = true
rawInput/preedit/candidates = 清空状态
```

阶段 8 起，成功选择只覆盖前缀音节的部分候选时返回：

```text
commitText = 本次需要提交到 IME Kit 的文本
compositionFinished = false
rawInput = Rust 移除已消费编码后的剩余双拼编码
preeditText / parsedSyllables / candidates = 剩余编码重新解析和解码后的状态
candidatePage = 0
```

ArkTS 不根据字符串长度推断消费范围；消费范围由 Rust 内部候选会话决定。

## 阶段 11.6.1 码表协议评估结论

现有 `CompositionResult` 足以表达顶屏的原子结果，无需新增字段或升级版本：

```text
commitText = 前一段本次需要提交的首选
rawInput = 同一次操作中已作为下一段首键重新处理后的编码
preeditText / candidates / candidatePage = 下一段操作后状态
compositionFinished = false
```

这与阶段 8 的“部分提交文本 + 剩余组合”是同一协议能力。`remainingRawInput` 会与操作后的 `rawInput` 重复；`backendId` 不应成为 ArkTS 业务分支；当前也没有必须依赖 `commitReason` 或 `clearReason` 才能执行的动作。因此该阶段评估时 ArkTS interface version 和 Rust ABI version 均保持 `2`，C ABI 函数、buffer 所有权和 JSON 必填字段不变。阶段 11.6.5 因新增分类读取/替换函数将两者同步升级为 `3`。阶段 11.6.6 需要表达日期时间和成对符号光标行为，因而新增单个可选 `action` 并同步升级为 `4`；旧结论只适用于纯文本/部分提交路径。

后续码表接入必须保持以下不变量：

- 每次引擎操作最多返回一个非空 `commitText`，ArkTS 最多执行一次编辑框提交；
- ArkTS 执行非空 `commitText` 后，仍按同一结果刷新非空 `rawInput`、预编辑和候选，不能无条件清空；
- C++ 只转换结果，不根据提交原因、后端或长度实现状态机；
- 未知 JSON 顶层字段不会被当前 C++ 查找式解析拒绝，但旧 C++ 不会把未知字段转发给 ArkTS；如未来确需新增字段，必须同步修改 Rust、C ABI JSON、C++、ArkTS 类型和兼容测试；
- `processKey` 的 ArkTS 调用方已执行非空 `commitText`，并在成功后应用同一结果中的
  `rawInput/preeditText/candidates`；失败时 reset。独立 TextInput 的自动提交、第五键和
  正反向切分已在 11.6.7 A～N 两轮验证。

完整证据和结论见 `docs/features/code-table/CODE_TABLE_BEHAVIOR_SPEC.md` 第 6 节。

## 阶段 11.6.3～11.6.4 码表后端配置与规则分层

既有 EngineConfig JSON 新增一个可选字段，不改变 ABI 或 interface version：

```text
interfaceVersion: 2
schemeId: 'xiaohe' | 'code-table-fixture' | 'xiaohe-yinxing'
lexiconPath?: string
codeTableBundlePath?: string
userLexiconPath?: string
candidatePageSize?: number
```

- `code-table-fixture` 仅供 Rust/FFI 测试与 Debug-only 设备验收，创建时必须提供有效的 `codeTableBundlePath`；缺失或损坏返回明确的创建错误。
- `xiaohe-yinxing` 只接受冻结生产身份、版本、归档拓扑、11 类画像、规则画像和哈希完全一致的 `HSPYXP01`。包内 `#固/#直` 规则归属 `full-code-word`，只在该分类启用时组成内置基础层；可选 `userLexiconPath` 为不受系统分类开关影响的外部覆盖层。同完整编码＋词条由外部规则覆盖，两层合并后再由既有候选算法统一执行。
- `xiaohe` 继续只使用 `lexiconPath`，忽略无关的 `codeTableBundlePath`；同时提供两种资源不会混合两种候选语义。
- Node-API 的可选配置属性兼容缺失、`undefined` 和 `null`；其他类型仍返回 `INVALID_ARGUMENT`。
- 候选 ID 使用确定的 `ct:{bundleId}:{categoryId}:{source_order}` 命名空间；`reading` 为原始码，`source` 为分类 ID。
- 本阶段不增加分类开关、引导、码长或提交原因字段；这些字段只能在相应后续子阶段确定后扩展。

## Rust C ABI

```c
typedef struct ImeEngineOpaque* ImeEngineHandle;

typedef struct ImeBuffer {
    uint8_t* data;
    size_t len;
} ImeBuffer;

uint32_t ime_engine_get_abi_version(void);
int32_t ime_engine_get_version(ImeBuffer* out_buffer);

int32_t ime_engine_create(
    const uint8_t* config_utf8,
    size_t config_len,
    ImeEngineHandle* out_handle
);

int32_t ime_engine_process_key(
    ImeEngineHandle handle,
    const uint8_t* key_utf8,
    size_t key_len,
    ImeBuffer* out_buffer
);

int32_t ime_engine_insert_segment_boundary(
    ImeEngineHandle handle,
    ImeBuffer* out_buffer
);

int32_t ime_engine_backspace(ImeEngineHandle handle, ImeBuffer* out_buffer);
int32_t ime_engine_reset(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_engine_change_scheme(
    ImeEngineHandle handle,
    const uint8_t* scheme_utf8,
    size_t scheme_len,
    ImeBuffer* out_buffer
);

int32_t ime_engine_select_candidate(
    ImeEngineHandle handle,
    size_t candidate_index,
    ImeBuffer* out_buffer
);

int32_t ime_engine_next_candidate_page(ImeEngineHandle handle, ImeBuffer* out_buffer);
int32_t ime_engine_previous_candidate_page(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_engine_set_user_model_path(
    ImeEngineHandle handle,
    const uint8_t* path_utf8,
    size_t path_len,
    ImeBuffer* out_buffer
);

int32_t ime_engine_load_user_model(ImeEngineHandle handle, ImeBuffer* out_buffer);
int32_t ime_engine_flush_user_model(ImeEngineHandle handle, ImeBuffer* out_buffer);
int32_t ime_engine_clear_user_model(ImeEngineHandle handle, ImeBuffer* out_buffer);
int32_t ime_engine_set_user_learning_enabled(
    ImeEngineHandle handle,
    bool enabled,
    ImeBuffer* out_buffer
);
int32_t ime_engine_set_session_learning_allowed(
    ImeEngineHandle handle,
    bool allowed,
    ImeBuffer* out_buffer
);

int32_t ime_engine_destroy(ImeEngineHandle* handle);
int32_t ime_engine_free_buffer(ImeBuffer* buffer);
```

固定候选回归接口只在 `ime-ffi` 的 `cfg(test)` 构建中保留：

```c
int32_t ime_engine_get_test_candidates(const char* input_utf8, ImeBuffer* out_buffer);
```

该符号不进入 OHOS 生产静态库，C++ Node-API 和 ArkTS 类型也不再暴露它。

## 错误码

`engine-rust/crates/engine-protocol/src/error.rs` 是语义真实来源；ArkTS 与 C++ 镜像同一组值。

| 代码 | 名称 | 含义 |
| --- | --- | --- |
| 0 | SUCCESS | 成功 |
| 1001 | INVALID_ARGUMENT | 参数为空、类型错误或按键参数非法 |
| 1002 | INVALID_HANDLE | 无效或已销毁的引擎 ID / Rust handle |
| 1003 | UNSUPPORTED_OPERATION | 不支持的操作 |
| 1004 | INVALID_UTF8 | UTF-8 解码失败 |
| 1005 | SERIALIZATION_ERROR | 返回结果序列化或解析失败 |
| 1006 | BUFFER_ALLOCATION_FAILED | 输出 buffer 参数或分配失败 |
| 1007 | ENGINE_NOT_INITIALIZED | 引擎或运行时词库未初始化 |
| 1008 | ENGINE_INTERNAL_ERROR | Rust panic 或内部错误 |
| 1009 | NATIVE_BRIDGE_ERROR | ArkTS/C++ 桥接错误 |
| 1010 | ABI_VERSION_MISMATCH | ABI / interface version 不匹配 |
| 1011 | INVALID_CONFIG | EngineConfig 格式错误 |
| 1012 | INVALID_SCHEME | 双拼方案不存在或无效 |
| 1013 | LEXICON_NOT_FOUND | 词库文件不存在 |
| 1014 | LEXICON_LOAD_FAILED | 词库读取或格式校验失败 |
| 1015 | INVALID_PAGE | 候选页请求非法 |
| 1016 | INVALID_CANDIDATE | 候选索引非法 |
| 1099 | UNKNOWN_ERROR | 未分类错误 |

语义上的非法双拼组合不是 Native 调用失败，正式结果以 `success=true`、`errorCode=0`、`parserState='invalid'` 返回。

用户模型损坏恢复不是 Native 调用失败。Rust 会返回 `UserModelStatus.lastErrorCode='corrupt'` 或其他脱敏错误码，并保持系统候选可用。

用户词库恢复状态是 Rust 内部/工具层的强类型 `UserLexiconLoadReport`，当前不新增公开 Node-API 状态方法。Release 日志只允许记录脱敏动作和错误码，不返回整行词条。用户词库候选通过既有 `Candidate`/`CompositionResult` 返回，`source='user-lexicon'` 仅用于内部来源区分和既有结果字段，不扩展 UI 合同。

## 所有权与线程安全

- `ImeEngineHandle` 只能由 Rust 创建和销毁。
- ArkTS 只持有 C++ `EngineRegistry` 返回的正整数 ID，不接触裸指针。
- C++ `EngineRegistry` 使用互斥锁保护 ID 到 `RustEngineHandle` 的映射。
- `ime_engine_destroy` 接收可清零的 handle 指针；释放后将句柄置空；已置空句柄再次 destroy 不崩溃。
- `ImeBuffer.data` 由 Rust 分配，调用者复制后必须通过 `ime_engine_free_buffer(&buffer)` 释放。
- `ime_engine_free_buffer` 释放后将 `data` 置空、`len` 置零；空 buffer 和已清零 buffer 可重复 free。
- 所有正式 C ABI 入口通过 `catch_unwind` 隔离 panic；panic 不允许穿过 FFI 边界。

## 输入规则

- `processKey` 在 `xiaohe/quanpin` 接受单个小写 ASCII 字母，在 `pinyin-9` 只接受单个 `2`～`9`；码表后端另外接受单个 `;` 进入/重启 Rust 引导状态，`xiaohe` 对 `;` 返回明确错误。
- ArkTS 可传入大小写字母，应用层在中文模式下规范化为小写再调用 Native。
- 空字符串、多个字符、当前 scheme 不接受的字符和非法 UTF-8 都返回参数或编码错误，不导致 Native 崩溃。
- 正式 scheme 为 `xiaohe`、`quanpin`、`pinyin-9`、`xiaohe-yinxing`；内部 `code-table-fixture` 只允许测试和 internalDebug 验收。

阶段 11.6.4 当时只改变 Rust 内部快照组成，不增加配置字段、结果字段或 C ABI 函数，interface/ABI version 继续为 2。阶段 11.6.5 新增分类配置读取/替换函数并升级为 3；阶段 11.6.6 新增单动作结果并升级为 4。受控分号只在码表后端和 internalDebug fixture 验收，Debug-only `xiaohe-yinxing` 仍不得被调用方视为已经开放的产品设置接口。
