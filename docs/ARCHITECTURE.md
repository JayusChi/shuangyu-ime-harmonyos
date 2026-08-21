# 架构

## 阶段 5 联合状态事务

`keyboardProfileId` 仍是布局与 Rust scheme 的唯一产品真实来源。任何 profile 变化（包括同为 `xiaohe` 的 17/26 布局变化）都必须先经 ArkTS 调用 Native reset；跨 scheme 再调用 `changeScheme`。只有 Native 成功且 Preferences 保存成功后才发布 UI/Store 快照；任一步失败都恢复旧 Rust scheme、旧 profile 和旧持久化值。组合清理仍由 Rust reset 与 ArkTS Store 清理共同完成，不在 C++ 增加状态机。

全拼单字母前缀召回和 T9 路径继续完全位于 Rust。C++ 只透传句柄/参数/JSON/错误码，ArkTS 只分发 profile、动作并展示 Rust 的 `currentPinyin/pinyinCombinations`。三层边界仍为 `ArkTS → C++ → Rust`。

## 26 键全拼和 9 键计划阶段 4：传统九宫格 UI 链路

```text
Pinyin9KeyboardLayout（2～9 专用 T9 动作）
  -> KeyboardController 串行队列
  -> InputSessionController.insertT9PinyinDigit
  -> EngineCoordinator / NativeEngineGateway.processKey
  -> C++ Node-API（校验与转发）
  -> Rust C ABI 7 / T9PinyinParser
  -> CompositionResult(currentPinyin, pinyinCombinations, candidates)
  -> InputSessionStore 原子快照
  -> CandidateBar + PinyinCombinationBar
```

`T9_PINYIN_DIGIT` 是 ArkTS 键盘语义动作，用于将中文九键数字与普通 `CHARACTER` 数字彻底分离；跨 Native 边界继续复用阶段 3 已冻结的 `processKey`，因此本阶段不增加 ABI 或 Node-API。字母组只存在于键帽、按键预览和无障碍文案，ArkTS/C++ 不展开或解释数字。组合栏按 Rust 顺序渲染，并把组合索引送回 `selectPinyinCombination`；Rust 返回的下一份完整结果是唯一真实状态。

九键布局复用统一 `KeyboardLayoutSpec`、`BaseKey`、`LetterKey`、`KeyboardPalette`、反馈服务和动态 `KeyboardMetrics`。中文为四排九宫格加共享底栏；英文、数字、电话和符号仍走原有布局及 `EditorPolicy`。完整规则和主机验证见 `PINYIN_STAGE4_KEYBOARD_UI.md`。

## 26 键全拼和 9 键计划阶段 3：T9 引擎链路

```text
ArkTS（数字输入 / 组合索引选择）
  -> C++ Node-API（只校验和转发）
  -> Rust C ABI 7
  -> T9PinyinParser
     -> 共享合法音节数字 Trie
     -> 有界动态规划 / 显式边界 / 当前选择
  -> CandidateQuery / SentenceDecoder / CandidateSession / UserModel
  -> CompositionResult(currentPinyin, pinyinCombinations, candidates)
  -> C++ 结构转换
  -> ArkTS 保存结果
```

T9 映射、数字签名、音节切分、未完成前缀、多路径稳定顺序和当前选择只存在于 Rust。索引由合法拼音音节初始化一次并经 `OnceLock<Arc<_>>` 共享；运行时沿数字 Trie 查询，禁止 `3^n`/`4^n` 字母展开，也不扫描完整音节集合。`rawInput` 仅含 `2`～`9`，显式边界作为解析器状态保存。

解析上限集中为：raw 64 位、单音节深度 6、每偏移 32 路、每起点最多 512 个生成状态、最多 32 个拼音组合、前缀缓存 65 项；候选快照最多 256 项。初始歧义状态聚合有界标准拼音路径并复用正式词库/整句/分页/学习链；显式组合选择会清空旧候选会话，只按所选路径重查。自动学习键使用独立 `scheme_id=pinyin-9` 和最终候选稳定 ID。

跨层新增 `selectPinyinCombination(index)`；索引 0 表示当前路径，后续索引对应 `pinyinCombinations`。interface/ABI 为 7，engine version 为 `0.0.1-pinyin-stage3`。该段的档案禁用状态是阶段 3 历史边界；阶段 4 已正式启用九宫格。详细合同和验证见 `PINYIN_STAGE3_T9_ENGINE.md`，决策见 ADR 0025。

## 26 键全拼和 9 键计划阶段 2 全拼链路

```text
用户键盘选择
  -> KeyboardProfile（合法的方案、布局、引擎 ID、能力组合）
  -> SettingsController / SettingsRepository（schema 5、迁移、持久化与回滚）
  -> EngineCoordinator.changeScheme

Rust PhoneticParser
  -> XiaoheShuangpinParserAdapter
  -> QuanpinParser（音节 Trie + 有界动态规划）
  -> ParseResult(raw/displaySegments/currentPinyin/pinyinCombinations/query intent)
  -> ime-engine 候选会话
  -> ABI 6 CompositionResult
  -> C++ 仅校验转换
  -> ArkTS 仅保存展示
```

`keyboardProfileId` 是设置层唯一合法组合来源；布局适配器不再拥有独立持久化状态。
旧 17/26 键偏好只在迁移时读取并映射为稳定档案 ID。全拼档案已启用；9 键引擎已在阶段 3 实现，
档案在阶段 4 UI 完成前曾保持禁用，当前已随九宫格完整链路正式启用。小鹤音形使用独立档案
保留原 17/26 键布局和引擎语义。

拼音分段和拼音路径的解释权属于具体 Rust 解析器。`engine-protocol` 只承载
`displaySegments`、`currentPinyin` 和 `pinyinCombinations`，不再按两个字符猜测分段；
C++ 与 ArkTS 不新增切分、路径展开或候选排序逻辑。

全拼首选路径和最多 32 条解析路径由 Rust 生成。单音节走既有精确/前缀查询，多音节和备选切分走既有整句解码；候选会话在 Rust 内稳定去重。部分提交的原始码消费长度按方案计算：双拼为两码槽，全拼为候选标准拼音实际字母数。自动学习键继续包含方案 ID；人工全拼规则使用 `qp` 代码前缀，与旧双拼 raw code 隔离。

性能修订后，解析器仍可返回最多 32 条有界展示路径，但候选热路径不再全部解码：raw input 不超过 12 字母时最多解码 4 条，超过 12 字母只解码首选路径。`quanpin` 不因组合长度、候选唯一性或下一按键自动提交，只有候选选择、空格、回车或标点等明确用户动作才能产生 `commitText`；64 字母是拒绝继续增长并保留现有组合的硬门禁。ArkTS 为支持能力的 `quanpin` 编辑器使用原生 TextPreview，兼容模式的增长更新只追加后缀，并在等待编辑器异步确认前先发布同步候选结果，失败时回滚；C++ 仍仅转发协议。

## 阶段 12 直通与用户词库管理链

```text
Ctrl+Alt+数字 / EntryAbility Want / 正式设置页
  -> DirectControlCommand（封闭动作与目标校验）
  -> DirectControlService
  -> SettingsController（资源校验、规范化、持久化、回滚）
  -> SettingsSyncBus
  -> 输入法进程 EngineCoordinator

用户词库页面
  -> UserLexiconController（串行编辑、revision）
  -> NativeEngineGateway -> C++ Node-API -> Rust user-lexicon
  -> 完整解析 + revision CAS + 原子保存
  -> 当前句柄 reload + UserLexiconSyncBus
  -> 其他输入法进程 reload
```

ArkTS 不解析用户词库格式，也不实施候选硬排序。Rust 返回结构化管理文档并拥有 revision、恢复、保存和不可变快照替换。Common Event 只携带“文件已变化”的通知，限定本包 publisher，不携带词条正文。快捷键和命令行不直接调用 Native，从而避免产生第二套方案/分类状态。

## 阶段 11.6.7 普通码表提交链

```text
按键开始
  -> Rust 捕获一次分类快照 + 用户规则快照 + 不可变提交策略
  -> 旧段达到 top：完整最终首选占用本次唯一提交预算
  -> 当前键作为新段首键处理一次
  -> 完整最终精确候选 + 有效更长编码
  -> empty split（正向优先，反向兜底）或 empty clear
  -> unique auto commit
  -> ABI 4 CompositionResult(commitText?, rawInput, candidates, action=null)
  -> C++ 仅转换
  -> ArkTS 提交 commitText 一次并保存/展示新段
```

`CodeTableCommitPolicy` 集中保存 auto/top/empty 默认长度 4、普通编码上限 64 和空码切分上限；非法策略在 Rust 创建时拒绝。空码切分已于2026-07-24经产品授权冻结并实现（ADR 0018）：正向从右向左扫描选择最长左前缀提交首选、右侧为剩余段；反向从左向右扫描选择最长右后缀、左段原样提交；正向优先于反向；相同输入和快照结果唯一。Guide 状态跳过整条普通提交链，`xiaohe` 仍走独立双拼后端。

## 阶段 11.6.6 安全动作链

```text
独立 guide/action 数据
  -> Rust code-table-runtime（加载、查询、四状态机）
  -> Rust ime-engine（唯一 commit/action 决策）
  -> C ABI JSON（interface/ABI 4）
  -> C++ Node-API（结构校验和类型转换）
  -> ArkTS NativeEngineGateway（再次校验）
  -> ProtocolActionExecutor（串行、generation、白名单）
  -> TimeProvider / ImeConnectionService
  -> HarmonyOS 编辑器
```

普通文本和符号仍走 `commitText`。日期时间由 ArkTS 从一次可注入时间快照生成；成对符号由 `ImeConnectionService` 插入一次，等待编辑器状态稳定后用 UTF-16 偏移定位。光标失败只返回部分失败，不重放插入。UI 不直接访问 `InputClient`，C++ 不包含格式化、引导、排序或符号业务规则。

引导表、动作表、11 个正式分类和用户规则保持独立；其中快符分类保持隔离，不进入普通系统候选。分类/用户快照更新不能污染动作层。原创动作 fixture 仅由 internalDebug 构建临时注入，Release 构建前后均清理。详见 `ACTION_PROTOCOL.md`、`GUIDE_STATE_TRANSITIONS.md` 和 ADR 0017。

本项目使用固定的三层架构：

```text
ArkTS HarmonyOS 层
  -> C++ Node-API 桥接层
  -> Rust C ABI 输入引擎
```

## 职责划分

ArkTS 负责 HarmonyOS 集成：`InputMethodExtensionAbility`、IME Kit 调用、键盘 UI、候选词显示、页面生命周期、用户可见状态、文本提交/删除、回车、隐藏/显示、设置、触觉反馈、音频和主题工作。

C++ 仅负责桥接：Node-API 注册、ArkTS 参数验证、UTF-8 转换、调用 Rust C ABI、错误转换、Rust 缓冲区释放，以及将 Rust 有效负载转换为 ArkTS 值。

Rust 负责输入法核心行为。正式链路已经在 Rust 层串起小鹤双拼解析、运行时二进制词库查询、候选去重、基础频率与用户词频排序、短句解码、分页、缓存和候选选择提交。生产 C ABI 只暴露正式 Engine Handle 及其输入、候选、学习和生命周期能力；固定候选回归接口仅在 `ime-ffi` 的 `cfg(test)` 构建中存在，不会进入 OHOS 静态库。

阶段 9 的用户词频学习仍完全位于 Rust。ArkTS 只传递沙箱路径、生命周期 flush 和会话学习策略；C++ 只转发路径/布尔参数和状态 JSON；`user-model` 负责学习记录、加权、持久化、原子保存、恢复和清空。

阶段 11 的设置、Preferences、主题 Token、键盘度量、震动和音频全部位于 ArkTS。设置页只调用 `SettingsController`；`SettingsStore` 是每个 ArkTS 运行时内唯一内存快照，Preferences 是持久化真实来源。MainAbility 通过本包定向 Common Event 将清空命令交给 InputMethodExtensionAbility；事件不携带输入数据。方案、学习和清空最终仍复用 `EngineCoordinator -> NativeEngineGateway`，没有新增跨语言接口。

设置页窗口外观由 `SettingsWindowCoordinator` 订阅同一个 `SettingsController`。它只消费 `SettingsStore` 解析出的实际生效主题，并通过 `HarmonySettingsWindowBackend` 串行调用主窗口沉浸式布局、窗口背景和系统栏属性；不会调用 `setColorMode(DARK/LIGHT)` 改写应用资源配置。正式 `Index`/`SettingsPage` 与 internalDebug 的 `DebugStage10` 使用独立背景层扩展到 `SYSTEM`/`CUTOUT` 四边；内容层订阅协调器发布的四边安全 inset，滚动视口本身位于安全区中，因此首项不能滚入状态栏，最后一项也不会落到手势条下方。

安全 inset 来自主窗口 API 24 的 `TYPE_SYSTEM`、`TYPE_CUTOUT` 与 `TYPE_NAVIGATION_INDICATOR` 避让区。后端在建窗后同步读取 `getWindowAvoidArea`，注册 `avoidAreaChange`，使用当前窗口矩形合并四边几何并通过 `UIContext.px2vp` 转为 ArkUI 单位；窗口销毁时使用相同回调注销。查询、事件注册、窗口属性或换算失败只记录日志并保留页面可用性，不用固定 `vp` 猜测状态栏或挖孔高度。

Debug 验收页显示时向同一协调器设置带单调令牌的 `DEBUG_FIXED_LIGHT_WINDOW_STYLE` 页面覆盖：白色背景、深色状态栏/导航栏内容。覆盖优先于设置变更、系统主题更新和前台同步；页面退出只可清除自己仍为最新的令牌，随后重新解析设置页实际主题。版本号负责跳过尚未开始的旧请求，串行 Promise 队列负责最终顺序，因此快速进入/退出或主题连切不会让旧样式成为最终状态。键盘主题没有进入该覆盖链路。

## 阶段 3 ArkTS 结构

```text
Stage0InputMethodAbility
  -> InputMethodLifecycleDispatcher
     -> InputPanelController
     -> InputSessionController
        -> ImeConnectionService
     -> InputSessionStore

KeyboardRootStage3
  -> CandidateBar
  -> BaseKey / LetterKey / DeleteKey / InputMethodSwitchKey / KeyPreviewPopup
  -> KeyboardLayoutSpec / KeyboardMetrics / KeyboardPalette
  -> KeyboardController
     -> InputSessionController
     -> NativeEngineGateway
```

能力类保持其现有名称以保持模块兼容性，但其角色现在是一个薄输入法生命周期适配器。

阶段 3.5 的系统输入法操作保持在 ArkTS 系统集成边界内：

```text
InputMethodSwitchKey / BaseKey（中/英键长按）
  -> SWITCH_INPUT_METHOD / SHOW_INPUT_METHOD_PICKER / HIDE_KEYBOARD
  -> KeyboardController
  -> InputSessionController
  -> InputMethodSwitcher
  -> IME Kit 系统输入法枚举、切换或选择器
```

`KeyboardAuxiliaryAreaPolicy` 是无副作用的窗口形态策略，只消费宽高、密度、方向和底部系统 inset。手机不再创建额外辅助行：标准竖屏手机存在系统输入法区域时，通过“中/英”键长按打开系统选择器；Pad、横屏、窄/宽特殊窗口以及系统输入法区域缺失时，切换入口位于现有文本功能键行。`InputPanelController` 在面板创建和每次 resize 前读取 API 21 系统面板 inset，并把同一快照同时交给面板高度计算和 UI 策略，避免布局判断与实际面板尺寸分叉。系统 API、系统输入法对象和权限判断不进入 presentation 层。

## 数据流

正常按键流：

```text
KeyboardRootStage3 -> KeyboardAction -> KeyboardController
  -> InputSessionController -> ImeConnectionService
  -> IME Kit insertText
```

固定候选回归仅存在于 Rust 自动测试：

```text
engine-rust unit/integration tests
  -> ime-engine 固定候选行为
  -> cfg(test) ime-ffi 回归边界
```

正式键盘、ArkTS Native 网关、Node-API 和 OHOS 静态库不暴露该调试路径。

正式中文候选流：

```text
InputMethodExtensionAbility inputStart
  -> InputMethodLifecycleDispatcher
  -> InputSessionController.handleAbilityCreated
  -> LexiconResourceInstaller copies production.lex rawfile to filesDir
  -> EngineCoordinator.initialize(lexiconPath)
  -> NativeEngineGateway.createEngine
  -> C++ Node-API / EngineRegistry / RustEngineHandle
  -> Rust ImeEngine loads BinaryLexicon once
```

```text
KeyboardRootStage3 key tap in Chinese mode
  -> KeyboardController.processChineseLetter
  -> InputSessionController.processChineseLetter
  -> EngineCoordinator.processKey
  -> NativeEngineGateway.processKey
  -> C++ Node-API forwarding
  -> Rust C ABI
  -> shuangpin-parser
  -> candidate-query / candidate-ranking / lexicon-core runtime_index
  -> CompositionResult current candidate page + displaySegments
  -> InputSessionStore
  -> CandidateBar / PadSideCandidateStrip
```

展示段由 Rust `shuangpin-parser` 的解析结果生成，经 `engine-protocol` 随每个组合快照传递。C++ 只转换
`displaySegments` 字符串数组，ArkTS 只使用 `'` 连接，不按长度猜测声母、韵母、
简拼或音节。候选栏插入的分隔符和下划线仅为绘制结果；编辑器预览、候选查询、
学习和提交继续使用既有原始组合字段。

候选提交和翻页流：

```text
CandidateBar click / page button / space
  -> KeyboardRootStage3
  -> KeyboardController
  -> InputSessionController
  -> EngineCoordinator
  -> NativeEngineGateway
  -> C++ forwarding
  -> Rust ImeEngine candidate session
  -> CompositionResult
  -> ImeConnectionService.insertText when commitText is present
```

编辑器文本预览兼容流：

```text
EditorAttribute.isTextPreviewSupported
  -> EditorAttributeMapper -> EditorContext.textPreviewSupported
  -> true：InputClient.setPreviewText / finishTextPreview
  -> false：组合文本仅保留在 InputSessionStore/CandidateBar
           -> 候选确认时 ImeConnectionService.insertText 单次提交
```

浏览器等明确声明不支持文本预览的编辑器不会调用预览 API。兼容范围模式记录组合起点和文本；下一按键前会读取当前光标前文本确认组合是否仍附着。若宿主搜索框静默清空内容且没有发送 `discardTypingText`，ArkTS 只丢弃本地旧组合和预览所有权，从当前按键建立新组合，不把旧范围写回编辑器。该降级只改变组合文本的展示和连接层所有权，不改变 Rust 解析、候选查询、候选确认和学习链路。

所有预览/兼容写入、提交、清理和附着检查均绑定 `InputSessionStore` 的单调 generation。输入停止、键盘隐藏、编辑框切换或 Ability 销毁会使旧 generation 失效并重置连接状态；随后完成的旧异步操作只能返回陈旧结果，不能更新新会话。

删除流：

```text
DeleteKey -> DeleteRepeatController -> KeyboardRootStage3
  -> KeyboardController -> InputSessionController
  -> 中文且 rawInput 非空：Rust engine backspace -> preview/candidate refresh
  -> 其他情况：ImeConnectionService
  -> 读取光标索引
  -> InputClient.deleteForward（HarmonyOS 退格：删除光标前文本）
  -> 验证光标向前移动
  -> 明确失败时后备 selectByRange + 空插入
  -> 光标不可用时后备 deleteForwardSync
```

## 阶段 4 Rust 结构

```text
ime-engine
  -> shuangpin-parser
     -> shuangpin-schema
        -> pinyin-syllable
     -> pinyin-syllable
```

`engine-rust/schemas/xiaohe.json` 是阶段 4 小鹤双拼规则数据源。解析器采用确定性的两键切分，末尾单键作为 `Incomplete` pending code 保留，删除通过原始按键历史重新解析来恢复一致状态。阶段 7 的正式中文候选链路复用这套解析器。

## 阶段 7 Rust 结构

```text
ime-engine
  -> shuangpin-parser
  -> candidate-query
     -> candidate-ranking
     -> lexicon-core
        -> runtime_index
  -> engine-protocol

ime-ffi
  -> ime-engine
  -> engine-protocol
```

`candidate-query` 只读取已经校验过的 `.lex` 二进制词库，不在运行时读取 TSV/CSV。精确查询对 `PinyinIndex.pinyin_key` 二分查找；正式前缀查询从 lower-bound 开始完整扫描连续前缀范围，以现有稳定频率键维护 256 项有界 Top-K。`candidate-ranking` 负责去重、合并来源、精确优先和稳定 tie-breaker；`ime-engine` 只对阶段 4 标记为单键/不完整前缀且使用正式 GlobalTopK 的结果选择阶段 5 质量排序并接入有界用户分，完整精确和句子路径保持独立。分页状态由 `ime-engine` 的候选会话维护，ArkTS 不切片制造正式候选页。

面板流：

```text
InputMethodExtensionAbility inputStart/keyboardShow
  -> InputMethodLifecycleDispatcher
  -> InputPanelController.create/show
  -> setUiContent('presentation/keyboard/KeyboardRootStage3')
```

## 阶段 8 Rust 结构

```text
ime-engine
  -> shuangpin-parser
  -> candidate-query / candidate-ranking   # 单音节和前缀回归路径
  -> sentence-decoder                      # 多音节短句路径
     -> graph.rs                           # SyllableGraph / WordEdge
     -> decoder.rs                         # bounded Viterbi search
     -> scorer.rs                          # independent sentence scoring
     -> path.rs                            # path/candidate metadata
     -> limits.rs                          # centralized search limits
     -> lexicon-core runtime_index
  -> engine-protocol
```

阶段 8 对两个及以上完整音节使用 `sentence-decoder`。音节图节点是音节位置，词语边来自已加载的 `BinaryLexicon` exact pinyin-key 范围。搜索采用带 beam 上限的 Viterbi 动态规划，整句评分由 `SentenceScorer` 独立计算，不复用阶段 7 候选排序分数。

部分提交由 Rust 内部候选会话保存 `consumed_raw_len`。选择只覆盖前缀音节的候选时，`ime-engine` 提交该候选文本、保留剩余 raw input、重新解析并返回新的 `CompositionResult`。ArkTS 只提交 `commitText` 并按返回结果刷新 store。

短句候选流：

```text
KeyboardRootStage3 key tap in Chinese mode
  -> KeyboardController
  -> InputSessionController
  -> EngineCoordinator
  -> NativeEngineGateway
  -> C++ forwarding
  -> Rust C ABI
  -> ime-engine processKey
  -> shuangpin-parser
  -> sentence-decoder SyllableGraph
  -> bounded Viterbi path search
  -> independent sentence scoring
  -> candidate session pagination
  -> CandidateBar
```

## 阶段 9 Rust 结构

```text
ime-engine
  -> user-model                         # 学习记录、用户评分、持久化、恢复
  -> candidate-ranking                  # 单字/词语候选基础排序 + 用户分接入
  -> sentence-decoder                   # 短句基础路径 + 只读用户分回调
  -> candidate-query                    # 仍只查询系统词库
  -> engine-protocol

ime-ffi
  -> ime-engine                         # C ABI、panic 隔离、状态 JSON
```

用户学习流：

```text
CandidateBar click / space commit
  -> InputSessionController
  -> EngineCoordinator
  -> NativeEngineGateway
  -> C++ Node-API forwarding
  -> Rust C ABI
  -> ime-engine select_candidate
  -> user-model record_selection
  -> delayed flush / explicit lifecycle flush
```

用户模型路径流：

```text
InputMethodExtensionAbility onCreate
  -> UserModelPathProvider reads context.filesDir
  -> EngineCoordinator.loadUserModel(path)
  -> NativeEngineGateway
  -> C++ forwards UTF-8 path
  -> Rust user-model load/recover
```

## 词库规则增强第二阶段：用户覆盖层

```text
ime-engine
  -> candidate-query / candidate-ranking / sentence-decoder
  -> user-model                 # 自动学习与软分
  -> user-lexicon               # 人工规则与硬位置
       -> lexicon-core validation

user-lexicon-tool
  -> user-lexicon parser / snapshot / store
```

`user-lexicon` 与系统 `BinaryLexicon`、自动学习 `user-model` 分离。ArkTS 在 Ability 创建时只生成沙箱内 `user_lexicon.txt` 的可选路径并随 `EngineConfig.userLexiconPath` 传入；文件不存在时 Rust 使用空快照。C++ Node-API 只把该字符串加入已有配置 JSON，不读取文件、不解释标记、不执行排序。

运行时顺序固定为：

```text
系统二进制词库查询 / 整句解码
  -> 基础频率与 user-model 软排序
  -> user-lexicon #删
  -> 普通用户词条合并
  -> #固 保护前缀
  -> #N 全局位置放置
  -> 稳定去重
  -> CandidateSession 数量限制与分页
  -> ArkTS 候选栏与 IME Kit 提交
```

人工规则不使用魔法分数。普通用户候选使用独立 ID 命名空间并且 `learning_key=None`；系统候选被 `#固/#N` 提升时仍可保留原稳定 ID，但硬位置在每次软排序之后重新施加，因此学习无法突破。用户词库只在加载/显式 reload 时完整解析，按键热路径只读不可变快照。

保存由 `user-lexicon::store` 独立实现：同目录临时文件完整写入、`flush`、`sync_all`、重新解析校验、备份和可回滚 rename。加载返回 `EmptyMissing`、`LoadedPrimary`、`LoadedBackup` 或 `RecoveredEmpty` 明确状态；损坏内容不会进入系统词库或用户模型。

## 阶段 11.6.3～11.6.4 双后端、系统码表查询与用户覆盖

当前可发布产品运行时仍只有 `schemeId='xiaohe'`，正式链路为：

```text
raw shuangpin
  -> ShuangpinParser
  -> normalized pinyin
  -> candidate-query / sentence-decoder
  -> ExistingRanking / user-model
  -> user-lexicon overlay
```

正式双拼的宽松前缀链路为：

```text
QueryIntent::SingleKeyPrefix / IncompleteSyllable
  -> complete prefix-index scan
  -> stable visible-text Top-K 256 by system frequency
  -> deterministic deduplication
  -> bounded length/repetition quality score + bounded user score
  -> stable prefix snapshot 128
  -> CandidateSession pagination
```

长度和重复信号只用于上述宽松前缀路径，且除数封顶；完整音节仍按原始系统频率，句子仍按独立句子评分。小鹤音形不进入该链路。

ADR 0015 冻结的边界已在 Rust 内落地。`ime-engine` 仍是唯一统一门面：

```text
ime-engine
  -> xiaohe backend
     -> shuangpin-parser
     -> pinyin production.lex
     -> sentence-decoder / ExistingRanking
  -> code-table backend
     -> raw-code state machine
     -> HSPCTF01 fixture 或严格冻结的 HSPYXP01 正式包
     -> category order / source_order
     -> exact-or-prefix / stable dedup
     -> embedded user-rules snapshot
     -> external user-lexicon snapshot
     -> deterministic immutable snapshot merge
     -> exact delete / ordinary / fixed / position / stable dedup
     -> full merge then limit / pagination
```

两种后端共享引擎句柄、`CompositionResult`、候选会话、分页和 ArkTS 提交边界，但不得共享候选排序语义。码表模式不经过 `ShuangpinParser`、拼音词库或 `sentence-decoder`；小鹤双拼也不得被切换为 `SourceOrder`。

公共外壳仅包括 Engine Handle、C ABI buffer/错误边界、后端完成排序后的 `CandidateSession`、分页、`CompositionResult`、用户词库文件基础和 ArkTS 协调/提交边界。禁止共享 `ExistingRanking`、整句评分、`user-model` 软分、双拼解析、分类顺序、引导状态或三码长业务判断。ArkTS 和 C++ 不判断自动上屏、空码清屏、顶屏或第五键重放。

`code-table-runtime` 负责 bundle 读取和结构/摘要/嵌套词库校验，并以不可变 `Arc<CodeTableBundle>` 支持并发只读查询。`CodeTableStateMachine` 另持有可原子替换的 `Arc<CategorySelectionSnapshot>` 和独立 `Arc<UserLexiconSnapshot>`；每个按键/退格/分页/分类更新只捕获一次分类快照。精确命中不混入更长编码；没有精确命中时才跨 enabled 分类回退，排序键固定为合同 order 后分类内 `source_order`。

阶段 11.6.4 的唯一业务插入点是 `CodeTableStateMachine::requery`：完整系统结果进入 `user-lexicon::merge_code_table_candidates`，依次执行候选完整编码＋词条的精确删除、普通用户候选合并、固顶保护前缀、全局指定位置和稳定文本去重，最后才执行结果上限与分页。精确系统候选被删空时不会再次回退到更长系统码；用户候选也保留其完整规则编码用于后续精确判断。系统 bundle 始终只读，按键热路径不读盘或解析用户文本。

`ImeEngine` 创建时只加载一次外部用户文件。`xiaohe-yinxing` 从已通过冻结画像校验的正式包取得 36 条内置规则快照，再调用 `merge_user_lexicon_snapshots` 按“内置在前、外部在后”重建单一不可变快照；同完整编码＋词条由后层外部规则覆盖。合并只操作已解析规则，重新分配稳定 `source_order`，不复制候选算法。fixture 继续只使用外部快照，`xiaohe` 继续使用原有用户覆盖路径。reset、清空 `user-model`、候选提交和方案切换不会修改快照；重新创建句柄/进程时从磁盘重新加载，主文件损坏则沿用既有备份恢复/空覆盖降级。

测试方案使用内部 ID `code-table-fixture`、显示名“码表输入（测试）”，继续只用于通用 Rust/FFI 回归。正式音形已接入 Rust/FFI 和 `internalDebug` A～L 分类验收；Debug 构建脚本临时注入冻结正式包。Release 门禁共同拒绝 fixture、正式 `.hsyx`、Debug 页面名与内部文案。默认和唯一可发布方案仍为 `xiaohe`；11.6.5 分类已完成，引导和四码提交/顶屏/空码切分仍未实现。

11.6.5 跨层增加分类配置读取和替换函数，interface/ABI 升级为 3。ArkTS 串行化设置更新，C++ 只校验数组/字符串和转发 JSON，Rust 校验 required/未知 ID/canonical 顺序并返回重算结果。详细决策见 ADR 0016。

详细依赖、失败回退和协议结论见 `docs/adr/0015-code-table-dual-backend-boundary.md`；精确/前缀顺序、三码长状态表、分号引导和 reset 矩阵见 `docs/features/code-table/CODE_TABLE_BEHAVIOR_SPEC.md`。

2026-07-22 重启后新增的正式供应链位于运行时之前：

```text
经理交付的 码表/ 与 小鹤音形/
  -> 11.6.2B 权威来源 manifest / SHA-256 / 分类与命令合同
  -> 11.6.2C 正式离线转换器
  -> versioned xiaohe-yinxing bundle
  -> 冻结生产身份与 CodeTableBundle 严格加载
  -> 现有 code-table runtime（11.6.3 系统基线）
```

原始 txt/ini 不进入运行时或 Release HAP；网络、凭据、外部程序和平台私有命令在转换边界拒绝。11.6.3 正式系统数据回归与 11.6.4 正式用户规则分层均已通过；11.6.5～11.6.8 补充分类、引导、提交状态和产品入口。

阶段 11.6.2B 已由独立的 `engine-rust/tools/yinxing-source-auditor` 落地。该工具只读两个正式交付根，使用稳定 UTF-8 路径顺序生成 `dictionaries/audit/xiaohe-yinxing/` 下的 manifest、分类映射、命令策略、差异、缺失引用、判定、脱敏配置参考与转换合同；人工报告写入 `docs/audits/data/`。安全命中只保存类型、1-based 物理行和摘要哈希。原始 Android 配置整文件拒绝并隔离，脱敏派生物不复制键值；小鹤音形编号文件是首版唯一权威输入，码表备选导出仅作审计证据。当前合同 `conversion_allowed=true`、阻断项为空；11.6.2C 不得绕过合同重新扫描目录或猜测来源。

阶段 11.6.2C 由独立的 `engine-rust/tools/yinxing-converter` 落地。转换器先校验冻结审计哈希，再只按合同路径读取权威文件；所有来源在任何行解析前完成大小和 SHA-256 预检。正式输出使用 `HSPYXP01` 1.0 容器；当前容器复用 11 个 `HSPLEX01` 1.1 分类二进制和既有用户规则合同。`code-table-runtime` 的通用加载器服务转换器兼容测试，冻结生产加载器额外锁定版本、归档拓扑、分类画像、规则画像和哈希；查询算法、分类顺序、`source_order`、精确/前缀仍共用既有实现。后续阶段已经把正式生成物接入 Rust、C ABI/FFI、产品设置与 Release 资源。

## 阶段 10 编辑器上下文与键盘策略

阶段 10 不改变 Native 候选链路，而是在 ArkTS 增加编辑器适配层：

```text
InputMethodExtensionAbility inputStart / editorAttributeChanged
  -> ImeConnectionService
  -> EditorAttributeMapper
  -> EditorContext
  -> InputSessionController
  -> InputSessionStore
     -> KeyboardModePolicy
     -> EnglishShiftController
     -> EnterActionPolicy
  -> KeyboardRootStage3
  -> Stage10KeyboardLayouts
```

`EditorContext` 只保存类型、首选模式、允许模式、回车动作、候选可见性和学习策略，不保存编辑框文本。HarmonyOS `PATTERN_*` 与 `ENTER_KEY_TYPE_*` 常量只存在于 `EditorAttributeMapper`。普通文本可以在中文与英文之间长期恢复；数字、电话和符号是受限或临时模式，不污染普通文本偏好。

密码上下文会先清空组合和候选，再关闭会话学习；密码字符不进入 Rust 解析、排序或用户模型。平台强制系统安全键盘时，第三方输入法不会接收密码按键。

Shift 状态为 `LOWERCASE -> ONE_SHOT_UPPERCASE -> CAPS_LOCK`。一次性大写只在成功提交 ASCII 字母后消费；删除、数字、符号和回车不消费。声明式英文布局使用状态转换键帽和提交字符，不复制大小写两份布局。

API 24 模拟器会把调试页的 `InputType.NUMBER_DECIMAL` 错误上报为普通数字。标准 `PATTERN_NUMBER_DECIMAL` 仍是主路径；调试页通过 `IMEClient.setExtraConfig` 提供 namespaced `number_decimal` 兼容提示，Mapper 不根据 placeholder 或用户内容猜测。

## 与前序阶段的关系

旧的阶段 0 键盘和阶段 2 `presentation/keyboard/KeyboardRoot` 仅保留布局历史上下文，其交互式固定候选入口已删除。阶段 3 的 `presentation/keyboard/KeyboardRootStage3` 是唯一活动键盘面板，只接入正式 Rust 候选链路。

MainAbility 通过 `settings_entry_page` 资源选择入口：Release 的 `default` target 加载正式 `pages/Index`，`internalDebug` 覆盖为 `pages/DebugIndex`。多输入框 `DebugStage10`、码表 `DebugCodeTable` 及其路由只登记在 internalDebug 页面清单；Release 的 `main_pages.json`、`entry/src/main` 和最终 HAP 均不包含这些页面或“调试与验收”文案。

## 禁止的依赖关系

- Rust 不得调用 HarmonyOS API。
- C++ 不得实现双拼、词典查询、排序、分页、缓存或用户模型逻辑。
- ArkTS 不得解析词库、查询词库、切分音节、拼接短句、排序正式候选、计算用户分、解析用户模型、切片制造正式分页或硬编码正式中文候选。
- UI 组件不得直接导入 `libime_bridge.so`。
- 候选栏不得直接调用 Native 或 IME Kit。
- 多个 ArkTS 模块不得创建单独的原生引擎所有权路径。
- 固定候选回归只能在测试进程内运行，不得进入正式 HAP、键盘 UI 或 Node-API。
