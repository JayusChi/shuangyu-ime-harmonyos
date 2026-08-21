# 阶段 10 验证记录

## 环境与产物

- 测试日期：2026-07-10
- 工程：`HarmonyOS_Input`
- Target / Compatible SDK：`6.1.1(24)`
- 本机 SDK：`C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony`
- 设备类型：HarmonyOS 模拟器，不是真实物理设备
- 设备地址：`127.0.0.1:5555`
- 系统版本：`emulator 6.1.0.125(SP9DEVC00E120R4P11)` / `OpenHarmony-6.1.1.125`
- API：24
- ABI：`x86_64`
- HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap`
- HAP 大小：7,272,879 bytes
- HAP SHA-256：`068FEE19CBFF08257EAF6EDE9320D2A6C6DBB8FDDCAC2C5AE2FA0CEC3919005D`
- 签名：未配置 `signingConfigs`，产物为 unsigned

最终设备复验安装的就是上述哈希对应的 HAP。

## 前置审计

读取了项目计划、当前状态、README、架构/编码/API 契约、活动 ExtensionAbility、生命周期分发、会话状态、输入面板、键盘组件、候选栏、Native 网关、阶段 9 用户模型和既有测试脚本。

本轮直接审计了 SDK 文件：

```text
sdk/default/openharmony/ets/api/@ohos.inputMethodEngine.d.ts
sdk/default/openharmony/ets/api/@ohos.inputMethod.d.ts
sdk/default/openharmony/ets/api/@ohos.inputMethod.ExtraConfig.d.ts
sdk/default/openharmony/ets/component/text_common.d.ts
sdk/default/openharmony/ets/component/text_input.d.ts
sdk/default/openharmony/ets/component/text_area.d.ts
```

确认了 `InputClient.getEditorAttributeSync()`、`EditorAttribute.inputPattern`、`enterKeyType`、`extraConfig`、`KeyboardDelegate.editorAttributeChanged`，以及文本、密码、数字密码、数字、小数、电话、邮箱、URI等 pattern 和 Go/Search/Send/Next/Done/Newline 动作。SDK 没有表示“允许负号”的编辑器子类型，因此不猜测负号能力。

审计发现阶段 9 活动键盘只有中英文占位模式；`inputStart` 不读取编辑器属性；回车固定换行；候选栏不随编辑器类型变化；没有 Shift/Caps Lock；密码上下文虽有底层会话禁学习能力，但没有真实输入框映射入口。

## 实际执行命令

以下命令均实际执行；设备脚本内部展开的每条 `hdc` 命令保存在设备转录日志中。

```powershell
Get-Content -LiteralPath '提示词模板\第10阶段提示词.txt' -Encoding UTF8
Get-Content -LiteralPath PROJECT_STATE.md -Encoding UTF8
Get-Content -LiteralPath docs/product/planning/PROJECT_PLAN.md -Encoding UTF8
Get-Content -LiteralPath README.md -Encoding UTF8
Get-Content -LiteralPath docs\ARCHITECTURE.md -Encoding UTF8
Get-Content -LiteralPath docs\CODING_RULES.md -Encoding UTF8
Get-Content -LiteralPath docs\API_CONTRACT.md -Encoding UTF8
rg -n "EditorAttribute|PATTERN_|ENTER_KEY_TYPE|NUMBER_DECIMAL|onWillAttachIME|setExtraConfig" <SDK 路径>

& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-hap.ps1 -SkipRust
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-stage10.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\device-accept-stage10.ps1

hdc -t 127.0.0.1:5555 shell param get const.ohos.apiversion
hdc -t 127.0.0.1:5555 shell param get const.ohos.fullname
hdc -t 127.0.0.1:5555 shell param get const.product.cpu.abilist
hdc -t 127.0.0.1:5555 shell param get const.product.software.version
hdc -t 127.0.0.1:5555 shell hilog -x
```

`verify-stage10.ps1` 实际调用 `verify-stage9.ps1 -SkipHap`，其中执行：

```powershell
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test -p user-model
cargo test -p candidate-ranking
cargo test -p sentence-decoder
cargo test -p ime-engine
cargo test -p ime-ffi
cargo test --workspace
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all
```

## 自动化测试结果

| 测试项 | 结果 | 证据摘要 |
| --- | --- | --- |
| ArkTS unit tests | 通过 | 66 tests，0 failure，0 error；阶段 10 测试已由 `List.test.ets` 注册 |
| Rust fmt | 通过 | `cargo fmt --check` |
| Rust clippy | 通过 | workspace/all-targets 且 warnings 视为错误 |
| user-model | 通过 | 20 passed |
| candidate-ranking | 通过 | 10 passed |
| sentence-decoder | 通过 | 21 passed |
| ime-engine | 通过 | 32 passed；阶段 7/8/9 fixture 通过 |
| ime-ffi | 通过 | 16 passed |
| Rust workspace | 通过 | 全量 workspace 与 doc tests 通过 |
| Native x86_64 | 通过 | 23,909,764 bytes；SHA-256 `0DD9BF3711462EE9D7A0C3C4701C3E920C1293379BAC252351628D030654C5FB` |
| Native arm64-v8a | 通过 | 24,493,554 bytes；SHA-256 `E1B38DD2C40FE6D2302803BDF0DB1F419BD7112EAFB1D5CD878EE8C36A25F1CD` |
| HAP build | 通过 | 7,272,879 bytes；最终哈希见“环境与产物” |
| 阶段 10架构边界 | 通过 | UI 无 IME Kit/Native 直连；C++/Rust 无编辑器 UI 策略 |
| 密码和敏感日志守卫 | 通过 | 无密码文本、附近文本、字符值或候选内容日志 |
| `verify-stage10.ps1` | 通过 | 所有步骤均 PASS |

ArkTS 覆盖包括：全部编辑器映射、缺失/未知回退、模式约束与恢复、候选栏可见性、Shift/Caps Lock 状态和实际提交、密码 Native/候选防线、会话禁学习、电话/邮箱/URL/小数布局、搜索/多行回车和编辑器切换不泄漏组合态。

## 模拟器设备验收

| 输入框 / 功能 | 结果 | 实际观察 |
| --- | --- | --- |
| 普通文本 | 通过 | 默认中文；候选栏可见；数字/符号入口可用 |
| 中文候选 | 通过 | 输入 `n i` 得到 `你`，点击后提交 |
| 英文 | 通过 | 切换后为小写，候选栏隐藏 |
| 一次性 Shift | 通过 | 键帽转大写；提交一个字母后回到小写 |
| Caps Lock | 通过 | 双击 Shift 后锁定；连续两个字母保持；再次点击退出 |
| 临时数字 / 符号 | 通过 | 两种模式可用且返回进入前的英文模式 |
| 候选栏恢复 | 通过 | 返回中文后候选栏恢复 |
| 密码 | 通过 | 系统安全键盘接管，无第三方中文候选；安全输入前后应用模型记录数相同 |
| 数字密码 | 通过 | 系统安全数字键盘接管，包含数字，无候选 |
| 整数 | 通过 | 0～9，不能逃逸到文本模式 |
| 小数 | 通过 | 数字布局明确包含 `.` |
| 电话 | 通过 | 包含 `*`、`#`、`+` |
| 邮箱 | 通过 | 默认英文，包含 `@`、`.`，无候选 |
| URL | 通过 | 默认英文，包含 `.`、`/`、`:`、`-`、`_` |
| 搜索 | 通过 | 中文候选可用；“搜索”动作到达页面 `onSubmit` |
| 多行 | 通过 | 中文候选可用；显示“回车”换行动作 |
| 最终结果 | 通过 | `STAGE10_DEVICE_ACCEPTANCE_RESULT=PASS` |

设备详细证据：`docs/evidence/stage10/device/stage10_device_acceptance_2026-07-10.md` 与同目录转录日志、JSON、PNG。

## 密码学习禁用结果

控制器自动化测试证明密码上下文会：重置组合态、禁止中文、隐藏候选、阻止 Native 解析与候选选择、调用会话学习禁用，并仅走 ArkTS IME 直接提交路径。

模拟器的普通密码和数字密码由系统安全键盘强制接管，第三方输入法面板不会收到密码字符。设备脚本在普通上下文提交候选并读取用户模型记录数，随后在系统安全密码键盘输入一个不记录值的字符，再回到普通上下文读取记录数；前后相等。日志不包含密码字符值。

## 失败与修复过程

1. 首次 HAP 编译暴露 ArkTS 键盘行数组推断问题；补充明确的 `KeyboardRowSpec[]` 类型后通过。
2. 初次设备截图发现通用模式键标签被错误统一成“中”；将动态语言标签限定为语言切换按键。
3. ArkUI `ForEach` 复用旧行导致切换英文后仍显示中文行、Shift 缺失；把编辑器、模式和 Shift 状态加入行 identity。
4. 整数切换到小数时复用旧数字行导致小数点缺失；将小数允许标志和回车动作加入行 identity。
5. API 24 模拟器把 `InputType.NUMBER_DECIMAL=12` 上报成 `inputPattern=2`。调试页通过 SDK 标准 `onWillAttachIME` / `IMEClient.setExtraConfig` 附带 namespaced `number_decimal`；Mapper 仍优先支持标准 `PATTERN_NUMBER_DECIMAL`，并只把显式配置作为兼容补充。针对性与全量设备验收均通过。
6. 密码框实际显示系统安全键盘而非第三方输入法。设备脚本改为识别两种合法运行时路径；本模拟器验证系统安全键盘、无候选和应用用户模型不增长，应用自有密码布局分支由单元测试覆盖。
7. 一次设备脚本运行因外层 120 秒命令上限被终止，不是产品断言失败；提高执行上限后完成。

没有删除、注释或跳过失败测试。

## 隐私结论

- `EditorContext` 不保存原始输入、密码、附近文本、完整按键序列或候选历史。
- 密码上下文不进入 Rust 解析/排序/学习链路；系统安全键盘接管时第三方 IME 不获得密码按键。
- 日志只记录 pattern、动作、编辑器种类、键盘模式、学习布尔值、长度、错误类别和结果；不记录字符或候选文本。
- 调试页不绑定输入值，不保存或输出用户输入。

## 未覆盖内容

- 未使用真实物理设备或 ARM64 设备运行时；ARM64 仅构建。
- 未覆盖其他 HarmonyOS 系统版本、所有第三方应用输入组件、硬件键盘、横屏/折叠屏、深色模式与完整无障碍矩阵。
- 系统安全键盘阻止第三方 IME 获得密码按键，因此应用自有密码布局分支未在该模拟器上直接运行。
- 未运行 Valgrind、ASan 或专用泄漏检测。
- 未配置正式 HAP 签名。
- 小数 extraConfig 是本调试页对该模拟器错误 pattern 的标准 API 兼容提示；其他应用若同样错误上报且不提供提示，第三方 IME 无可靠方式区分整数和小数。
- 测试词库不是生产级中文词库。
