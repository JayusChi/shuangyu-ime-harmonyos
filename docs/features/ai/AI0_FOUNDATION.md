# AI 输入法第 0 阶段：安全骨架与可控假实现

> 历史基线说明：AI-0 的骨架已由 `AI1_FIRST_INPUT.md` 继续实现。当前正式运行时不再包含 Fake Provider；Fake AI/Speech 仅位于 `entry/src/test/support/`。云端仍因生产代理材料缺失而失败关闭。

## 阶段结论

AI-0 已建立 AI 辅助和语音输入的可替换协议、能力门控、生命周期、隐私默认值、确定性 Fake Provider、受控替换与最小可验证 UI。当前没有接入真实模型、云端服务、网络、麦克风或系统录音能力；两个总开关默认关闭，设备验收仍为 `NOT_RUN`。

## 不可突破的边界

- 模型输出始终是普通文本数据，不能解释为命令、URL、路由、系统动作或 Native 调用。
- AI 只能读取本输入法刚刚提交且仍可核对的最近文本；不读取编辑器全文、光标前后任意上下文、剪贴板、联系人或宿主应用标识。
- 密码、未知、数字、电话、邮箱和 URL 编辑器关闭 AI 与语音；会话未激活、编辑器断开或能力未知时同样失败关闭。
- AI-0 Provider 只允许 `LOCAL_ONLY + FAKE`。云端开关和同意版本字段只是迁移安全的设置骨架，当前不可用且默认关闭。
- 语音流程是状态机验证，不申请 `ohos.permission.MICROPHONE`，不录音，不访问真实语音服务；最终文本必须由用户明确点击“上屏”。
- Release 源码与最终 HAP 禁止 `ohos.permission.INTERNET` 和 `ohos.permission.MICROPHONE`，门禁含对应负向测试。

## 运行时能力模型

`InputMethodSecurityModeProvider` 在 Ability 创建和每次输入会话开始时读取 `InputMethodAbility.getSecurityMode()`，并把结果映射为集中式 `InputMethodCapabilityState`：

- `BASIC`：本地 Fake AI 可用；语音不可用。
- `FULL`：在非敏感编辑器中可使用 Fake AI 与 Fake Speech。
- `UNKNOWN`：失败关闭，不展示可执行入口。

最终可用性由安全模式、编辑器类型、会话状态、Provider 能力和用户设置共同决定，UI 只消费这一份解析结果，不自行猜测权限。

## AI 协议与状态

`AiContracts.ets` 固定请求身份、会话 generation、动作、来源所有权、Provider 策略、截止时间和建议替换策略。当前动作合同包含续写、礼貌、正式、精简和翻译；最小 UI 默认发起礼貌改写。

状态流为：

```text
IDLE -> LOADING -> READY -> APPLYING -> APPLIED
                \-> ERROR / CANCELED / UNAVAILABLE
```

请求 ID 与 session generation 必须同时匹配。新输入、新请求、隐藏键盘、切换编辑器、停止会话、丢弃输入或 Ability 销毁都会取消当前请求；超时、取消后的迟到结果和乱序旧结果均被忽略。

`FakeAiProvider` 可确定性模拟成功、空结果、Provider 错误、超时、取消、乱序和取消后的迟到回调。每个成功请求返回最多 3 条有界建议。

## 语音协议与状态

`VoiceContracts.ets` 固定语音会话 ID、session generation、语言、最长时长、中间/最终结果和 Provider 身份。状态流为：

```text
IDLE -> PREPARING -> LISTENING -> FINALIZING -> RESULT_READY
                                                 -> COMMITTING -> COMMITTED
      \-> ERROR / CANCELED / UNAVAILABLE
```

`FakeSpeechProvider` 可模拟中间结果、最终结果、空结果、Provider 错误、超时、取消后迟到结果和最终/中间结果乱序。中间结果只显示；最终结果进入待确认态，不能自动写入编辑器。

## 受控替换与撤销

AI 建议接受路径如下：

```text
用户点击建议
  -> AiAssistController 校验 requestId + generation + suggestionId
  -> VerifiedTextReplacer 校验长度和 LAST_IME_COMMIT 所有权
  -> ImeConnectionService 重新读取光标前精确原文
  -> 选择该范围并用一次 insertText 原子替换
  -> UndoCommitManager 记录替换文本和原文
```

原文核对失败时不先删除、不写入建议，并提示“原文已变化”。替换成功后，既有撤销入口使用相同的内容核对机制反向替换为原文。日志只记录状态、错误码、请求阶段和文本长度，不记录来源文本、建议文本或语音结果。

## 设置与 UI

设置 schema 为 9。AI/语音总开关默认关闭；本地联想、云 AI、语音自动上屏均默认关闭；语言固定为 `zh-CN`。设置页明确说明 AI-0 只运行本地假流程、无上传、无网络、无麦克风、无录音，并展示云能力当前不可用。

候选栏在开关开启后显示 AI 和语音入口。不可用时入口保留禁用原因；AI 加载、候选、错误和取消使用独立面板；语音显示中间结果、最终结果、停止、重试、取消和明确上屏动作。普通候选与组合状态的现有路径不变。

## 自动化与构建验证

ArkTS 自动化覆盖：

- BASIC/FULL/UNKNOWN、敏感编辑器、开关关闭和会话失效门控；
- AI 成功、空结果、错误、超时、取消、乱序和迟到结果；
- 看似命令的 `$cmd`/URL 输出只作为普通文本提交；
- 原文变化时替换失败且原文不丢失，成功替换可记录原文以撤销；
- 语音中间/最终结果、明确确认、空结果、错误、超时、取消、乱序和迟到结果；
- schema 9 迁移默认值与显式开关保留；
- Release HAP 构建、内容白名单及 INTERNET/MICROPHONE 负向门禁。

2026-08-21 主机验证结果：ArkTS 全量测试 `BUILD SUCCESSFUL`；default Release HAP 和内容门禁 PASS。unsigned HAP 为 40,764,250 bytes，SHA-256 `0642944603309F84A71FFBF50BE6B7A539AFCD648A201E8EF1050C0C323402AB`。

## 后续阶段约束

接入真实本地模型、真实语音或任何云 Provider 前，必须单独完成数据最小化、权限与同意流程、供应商协议、超时/配额、设备兼容性、安全审查和 Release 门禁设计。不得通过替换 Fake Provider 绕过当前的能力门控、内容核对、generation、显式确认和日志脱敏边界。
