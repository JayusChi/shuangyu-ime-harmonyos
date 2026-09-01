# 测试计划

## 0.5.1 客户反馈闭环回归（2026-08-27）

- 复制/粘贴：选择 `abc` 后触发皮肤复制，必须保留一个 500 ms 有界派发窗口供异步宿主读取选区，再调用原生右移命令收起选区；命令失败时才允许回退零宽范围选择。皮肤全选产生的文本还须保存为有界进程内副本，以便系统拒绝宿主扩展粘贴动作的环境仍可完成随后粘贴；未经过本键盘复制时仍使用原生粘贴回退。最终必须得到可见的第二份 `abc`，不能因过早收起导致剪贴板为空，也不能因原选区仍激活而等值覆盖。
- 删行/恢复：在 `a\nb` 的当前行中执行回删下滑，必须按“光标右侧、光标左侧”顺序删除整行且不调用范围选择；左侧删除失败时必须恢复已经删除的右侧内容。成功后回车下滑须在会话、光标及两侧上下文仍匹配时恢复原行。
- 输入码互斥与样式：普通中文、分号引导、显式分词、9 键、万能键及退格后的非空组合都只允许写入 `CANDIDATE_BAR`；嵌入/固定展示位自绘实线下划线，输入码与候选共同位于浮动候选窗时不画下划线；编辑器文本与 `TextPreview` 均不得出现原始编码。
- 0.6.0 实体键盘反馈：按实体键盘入口连续验证 `;＋字母` 唯一快符直接上屏、唯一候选后分号顶首选并进入引导、单分号冒号候选/空格冒号/双分号全角分号、双事件通道下 `o→ok` 不重复、分类 `#直/#删`、`5.直通.txt` 生成的动作候选，以及浮动窗输入码无下划线。不得用触屏点击用例代替这些实体键盘路由断言。
- 万能键：正式小鹤音形 bundle 必须经 Rust FFI 对 `j`、`u`、反引号返回成功、保留 `rawInput=ju\`` 且候选数大于 0；音形精确码 UI 遇到任意含反引号的万能码时必须完整保留 Rust 已过滤的候选，不能再次按字面码过滤。ArkTS → Native 设备日志只能记录成功状态、编码长度和候选数，不记录原码或候选正文。
- 发布资源测试夹具必须包含实际输入法资源、模块 Ability 声明和 Ability 基类；正向校验及逐项负向矩阵均须通过。

2026-08-27 最终结果：完整 Rust workspace PASS（FFI `39/39`），发布资源正负门禁及 unsigned/signed Release HAP 实包审计 PASS。最新 ArkTS `567` 项源码和 Release 应用均编译通过；Windows Hypium Previewer 在用例执行前崩溃于 AMD OpenGL 驱动，故未生成也不宣称 `567/567`，最近一次完整报告为新增两项回归前的 `565/565 PASS`。2in1 Stage 4、Pad 万能键/输入码隔离/复制粘贴/删行恢复、ARM64 Phone 系统浏览器输入码隔离 smoke 均 PASS；包身份、哈希和证据索引见 `docs/evidence/2026-08-27-v0.5.1-customer-feedback/README.md`。

## 客户回传小鹤音形词库更新（2026-08-24）

客户回传目录已执行严格 UTF-8/Tab/编码/重复校验、元数据清理、直通转换和符号组规范化；原件未改写。客户缺失的表外段保留项目既有 362 条。`5.直通.txt` 的 44 行当前转换 31 条受支持动作词条，13 条未实现或不安全语义进入显式报告；必须复验生成数据中不含 `$cmd/$ddcmd`、HTTP、动态 URL、路径或平台键码，并验证重复导入字节一致。

2026-08-26 直通显示/上屏分离改动结果：源审计、正式 bundle 构建与 `-VerifyOnly`、候选基线、Rust workspace 全目标检查、相关单元/正式包/端到端回归、fmt、ArkTS `526/526` 和 x86_64/arm64-v8a OHOS Release Native 均 PASS。bundle 为 56,184,164 bytes、SHA-256 `F7BBFDF4473E9317D618C9AD02A792B47FF2DAB8BFD74FA23416579E01F9BDC7`。Release HAP 已完成 Native 编译，但被当前工作区内与本改动无关的键盘自定义/设置模型 ArkTS 编译错误阻断，未产出本轮 HAP；真机及 Phone/Pad/2in1 输入验收为 `NOT_RUN`。

## AI 输入法第 1 阶段

主机自动化覆盖五个动作、本地关联开关/确定性/边界、普通输入零回退；Cloud Provider 成功、断网、超时、取消、空/超长响应、非法 JSON、协议/request/provider 不匹配、重复 ID、乱序和迟到；新输入、光标/原文变化、隐藏、停止和换框；BASIC/FULL/UNKNOWN、敏感编辑器、同意/开关/Provider 门控；Unicode 安全替换与撤销；命令形输出惰性处理。

2026-08-24 实际结果：ArkTS `506/506 PASS`（AI-1 `19/19`），自有代理协议 `9/9 PASS`，无配置启动按预期失败关闭，宿主结果 schema 正向 PASS 且全 `NOT_RUN` 示例被完成门禁拒绝；`context-reranker 9/9 PASS`，`quanpin_context_reranking_v2 9/9 PASS`，AI-1 FFI 定向测试 PASS，fmt 与 workspace 严格 Clippy PASS，Release 负向门禁 `13/13 PASS`，default Release HAP 与实包内容审计 PASS。Rust workspace 全量测试被当前工作区既有小鹤生成 bundle 与冻结候选快照不一致阻塞，冻结基线未被改写。参考代理为 `IMPLEMENTED / HOST_TESTED / NOT_DEPLOYED`；真实代理/供应商为 `CLOUD_NOT_CONFIGURED / NOT_RUN`，Phone/Pad/2in1 和第三方宿主全部 `NOT_RUN`。因此 AI-1 是 `CORE_IMPLEMENTED / PRODUCTION_COMPLETION_BLOCKED`，不是生产完成。完整记录见 `features/ai/AI1_FIRST_INPUT.md`。

## AI 输入法第 0 阶段

主机自动化必须覆盖：

- 安全模式 BASIC/FULL/UNKNOWN、普通/搜索/多行和密码/未知/数字/电话/邮箱/URL 编辑器门控；
- AI/语音开关默认关闭、schema 9 迁移、显式值保留和会话未激活失败关闭；
- Fake AI 成功、空结果、错误、超时、取消、乱序、迟到结果与协议上限；
- Fake Speech 中间/最终、空结果、错误、超时、取消、乱序、迟到结果与明确确认上屏；
- request/session ID、generation 和生命周期失效；
- AI 原文精确核对、失败不删除、成功替换、替换撤销，以及命令形文本保持不可执行；
- 日志不输出正文，Release 不声明 INTERNET/MICROPHONE，正式资源白名单不变。

2026-08-21：ArkTS 全量测试、default Release HAP、实际 HAP 内容门禁和 Release 资源负向门禁 PASS。Phone/Pad/2in1 的真实宿主输入框、触摸 UI、安全模式差异、窗口隐藏/换框压力和可访问性均为 `NOT_RUN`，不得表述为设备完成。

## 26 键全拼和 9 键拼音阶段 5

2026-08-13 实际执行矩阵：

- Profile/迁移：四正式档案、旧 17/26、合法/未知/损坏值、同 scheme 布局切换、Native/持久化失败回滚；ArkTS PASS。
- 输入与生命周期：普通/搜索/聊天/多行/邮箱/URL/密码/数字/电话策略，候选/空格/回车/分页/部分提交/删除/取消，隐藏/显示/换框/reset；主机 PASS，Phone/Pad 核心路径 PARTIAL PASS。
- 全拼：`ni/nihao/zhongguo/zhon/xian/xi'an`、删除、分页、长输入零隐式提交；Rust PASS，Phone/Pad `nihao` PASS。
- T9：`64/64426`、组合切换、显式分音、删除、分页、64 位高碰撞；Rust PASS，Phone/Pad `64426` PASS。
- 数据隔离：`xiaohe/quanpin/pinyin-9/xiaohe-yinxing` 学习和人工规则、损坏恢复；Rust PASS。
- 门禁：Rust 505/505、ArkTS 440/440、FFI 31/31、双 ABI、Release HAP 和实包内容 PASS。
- 设备缺口：ARM64 真机、真实浏览器/聊天应用、同机旋转/分屏、设备性能/RSS/soak 均 `NOT_RUN`。
- 音形 ARM64 冷启动/RSS 使用 `scripts/measure-yinxing-arm64.ps1`；脚本必须拒绝 emulator，并记录 process-cold ready、bundle preparation、Native engine initialization、ready/settled RSS 与回执/哈希模式。当前环境无物理 ARM64，仍为 `NOT_RUN`。

完整命令、性能数值、HAP 与阻塞项见 `PINYIN_STAGE5_FINAL_ACCEPTANCE.md`。

## 阶段 12 直通与用户词库管理

主机门禁必须覆盖：

- 封闭命令解析、未知动作/方案/分类/多余参数失败关闭；
- 严格 Ctrl+Alt+数字映射、Logo/缺少修饰键不截获；
- 引擎离线时分类规范化持久化、核心分类保护、在线 Native 失败和保存失败回滚；
- 用户词库普通/删除/固顶/第 N 位的单条及批量序列化；
- 文档读取、物理行诊断、稳定 revision、旧 revision 冲突、原子保存与备份恢复；
- 小鹤双拼和小鹤音形运行时热重载，失败保留最后有效快照；
- C ABI、C++、Node-API、ArkTS interface/ABI 5 一致；
- ArkTS 全量、Rust workspace fmt/clippy/tests、双 ABI Native、Release HAP 和内容门禁。

设备验收必须分别执行 `aa` 命令、物理键盘快捷键、设置页分类、用户词库单条/批量、输入法进程存活和冷启动两种热重载；设备未执行时必须明确记录 `NOT_RUN`。

## 阶段 11.6.9 最终验收

2026-07-27 实际执行：

- Host：Rust 387/387、FFI 26/26、ArkTS 323/323、fmt、Clippy、28/28 来源不可变、
  15/15 生产输出双构建一致，全部 PASS。
- Build/Release：双 ABI Native、internalDebug、unsigned/signed Release HAP、
  signed/unsigned 内容门禁、两组负向门禁和签名验证，全部 PASS。
- Performance：五个独立 Windows x64 Release 进程的加载、查询、状态循环和内存
  数据已记录；设备性能 NOT RUN。
- Device：Phone/Pad x86_64 模拟器的受保护密码键盘不向 `uitest` 暴露键帽，脚本
  未识别系统安全键盘并在应用布局分支以“无 Shift”失败；设置持久化多数
  项通过，但清空用户模型后半程的自动化导航未完成；signed Release 独立 TextInput
  因测试包未安装而 NOT RUN；没有 ARM64 物理真机。

阶段结论为 `11.6.9 PARTIALLY COMPLETED`。权威证据目录：
`docs/evidence/2026-07-27-stage-11.6.9-final-acceptance/`。

## 阶段 11.6.8 验证

主机门禁包括 Rust fmt/Clippy/workspace tests、ArkTS 全量测试、双 ABI Native、
internalDebug/Release HAP、正式 bundle 大小与 SHA、实际 HAP 白名单、负向资源门禁和
28/28 来源不可变。设备必须使用 signed Release 独立 TextInput 验证 A～F，并使用
internalDebug 真链路验证 G～K；强停前后都必须有证据。

2026-07-27 执行结果：Rust 387/387、FFI 26/26、ArkTS 323/323、双 ABI、两个 HAP、
实包正向门禁、六类负向门禁和 28/28 来源不可变全部 PASS。x86_64 HarmonyOS 6.1
Phone 模拟器 `1320x2856` 完成 A～L；G/H/I/J/K 经 force-stop/restart 两轮均命中
PASS 标签。ARM64 物理真机和 11.6.9 全量发布验收为 NOT RUN。

## 阶段 11.6.7 验证

必须继续执行 Rust fmt、workspace Clippy/tests、ArkTS 全量测试、双 ABI Native、internalDebug/Release HAP、Release 正负资源门禁、最终 HAP 扫描和 28/28 正式来源不可变审计。

专项覆盖：

- 四码最终唯一自动提交、多候选保留、有效更长编码保护；
- 完整候选在分页/limit 前参与唯一性；
- 分类关闭、用户新增/删除/固顶/位置规则改变唯一性、后续码与顶屏首选；
- 第五码旧段最多提交一次，新键成为新段首键且只处理一次；
- 旧段无首选、非法键、退格、翻页、选择、reset、方案切换和 Guide 隔离；
- 空字符串不枚举、空码达到冻结长度后清屏、超长和确定性混合序列不 panic；
- FFI 序列化 `commitText + rawInput + candidates + action=null`；
- ArkTS 单次 `commitPreviewText`、新段 store 同步、失败 reset 和非 BMP 文本；
- `xiaohe` 解析、整句、学习和用户规则全量回归。

空码正/反向切分已由 ADR 0018 冻结：正向取最长合法左前缀，反向取最长合法右后缀并按文本顺序提交左侧；正向优先，单次最多一个提交。

2026-07-27 复验结果：除既有主机门禁外，x86_64 HarmonyOS 6.1 Phone 模拟器
`1320x2856` 在独立 ArkUI `TextInput` 中从 force-stop/clean 启动执行 A～N 两轮，
28/28 PASS。ARM64 物理真机仍记录为 11.6.9 NOT RUN。

## 阶段 11.6.6 验证

必须执行：

```text
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace
hvigor --no-daemon --mode module -p module=entry@default test
scripts/build-native.ps1 -Abi all
scripts/build-hap.ps1 -SkipRust -BuildMode debug
scripts/build-hap.ps1 -SkipRust -BuildMode release
scripts/verify-release-hap.ps1
scripts/test-release-resource-gate.ps1
scripts/test-xiaohe-yinxing-stage11_6_8-release-gate.ps1
scripts/audit-xiaohe-yinxing.ps1 -AllowBlocked
scripts/device-accept-xiaohe-yinxing-stage11_6_6.ps1
scripts/device-accept-xiaohe-yinxing-stage11_6_6-editor.ps1
```

专项覆盖包括动作表版本/哈希/截断/未知字段/危险标记、快符全列表后分页、空引导不枚举、四状态转移、中文来源符号页分号路由、连续分号、非法键、退格、翻页、选择、reset/方案切换、commit/action 互斥、旧 interface 拒绝、固定时间、闰日、补零、24 小时制、UTF-16 emoji 偏移、光标失败不重试和 generation 失效。

第一套设备自动化把 Debug 页面 A-G 作为通用 fixture 跨层运行时验收；第二套在独立 MainAbility ArkUI `TextInput` 中验证日期实际提交、成对 emoji 只插入一次，并用非 BMP 字符之间的字母探针验证 UTF-16 光标位置。两套均 PASS 后才可把 editor-side 待办标记为完成。

## 当前总门禁

正式交付基线使用 Release HAP：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-lexicon-rules-phase2.ps1
powershell -ExecutionPolicy Bypass -File scripts\verify-code-table-fixture.ps1
powershell -ExecutionPolicy Bypass -File scripts\verify-stage11.ps1
powershell -ExecutionPolicy Bypass -File scripts\verify-release-hap.ps1
powershell -ExecutionPolicy Bypass -File scripts\test-release-resource-gate.ps1
powershell -ExecutionPolicy Bypass -File scripts\test-xiaohe-yinxing-stage11_6_8-release-gate.ps1
```

`verify-lexicon-rules-phase2.ps1` 是输入引擎与用户词库总门禁；`verify-code-table-fixture.ps1` 验证原创模拟数据、确定性构建与 Release 资源输入；`verify-stage11.ps1` 保留设置、主题、反馈和架构隐私回归。阶段 11.6.4 已在 fixture 码表运行时接入用户规则；正式小鹤音形来源、转换器和 bundle 门禁由 11.6.2B～11.6.2C 新增。

## 阶段 11.6.2A 构建门禁

`scripts/verify-code-table-fixture.ps1` 在两个不同临时目录分别执行完整生成和构建，逐文件比较全部 14 个输出的 SHA-256，而不是只比较大小。随后验证 bundle、运行 `code-table-fixture-generator` 的 15 项单元/集成测试，并执行 Release 资源输入白名单。

测试覆盖：25,000＋2,000 规模；1～6 码长；同码 1/2/5+/20+ 与分页准备；前缀链和跨分类重复；黄金 fixture；manifest JSON、ID/order/path/count/SHA/guide 隔离；UTF-8、TAB、空字段、空白、非法码、长度、NUL、控制字符、`#删/#固/#N` 和同分类重复的精确诊断；`HSPLEX01` 1.1 `source_order` 往返；`HSPCTF01` 内容校验；两次独立构建字节一致。

2026-07-15 基线：正常分类 25,000、guide 2,000；bundle 2,024,260 bytes；两次 SHA-256 均为 `345887C1F6052514758A1D3F53B4F280E6FF04086AB1736582C9A8CCD42DF71C`。最终门禁记录的生成分别为 89/93 ms，bundle 构建分别为 2,475/2,388 ms；当前无可靠跨平台峰值内存数据。

`scripts/test-release-resource-gate.ps1` 自动证明三项正式资源控制目录通过，而加入 `code-table-fixture-synthetic.bundle` 后门禁失败。`verify-release-hap.ps1` 同时检查源码资源输入和最终 HAP ZIP：rawfile 当前只允许已审计的 `production.lex`、`quanpin-context-v2.qng` 和 `xiaohe-yinxing-production.hsyx`，并拒绝 fixture/test/synthetic/code-table、bundle、测试 manifest 和任何额外未审批 rawfile。`test-xiaohe-yinxing-stage11_6_8-release-gate.ps1` 进一步验证正式 `.hsyx` 篡改、未知资源、原始数据、trace/report 和网络权限均被拒绝。

其中 Release 包门禁必须确认：

- `module.json` 为 `buildMode=release` 且 `debug=false`；
- 包内存在且只包含三项已审批正式 rawfile，不包含阶段 7/8 fixture 词库或第二个未知 `.hsyx`；
- `modules.abc` 和各 ABI 的 `libime_bridge.so` 不包含固定候选回归、模型探针或固定文本提交等调试标识；
- 正式键盘源码不依赖 `BuildProfile`，也不包含“回归”或“模型”交互控件。

Debug HAP 仅用于设置页中的输入框验收入口；Debug 和 Release 的正式键盘行为一致，都不得暴露上述调试控件。

## 阶段 11.6.3 系统码表运行时查询

主机门禁：

```powershell
cd engine-rust
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace
cd ..
powershell -ExecutionPolicy Bypass -File scripts\verify-code-table-fixture.ps1
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust -BuildMode release
powershell -ExecutionPolicy Bypass -File scripts\verify-release-hap.ps1
powershell -ExecutionPolicy Bypass -File scripts\test-release-resource-gate.ps1
```

固定覆盖包括：`code-table-runtime` 33 项、`ime-engine` 码表集成 7 项、`ime-ffi` 共 18 项；验证空输入、精确优先、前缀回退、分类/source_order、跨分类去重、完整排序后限量/分页、退格/reset、非法键、64-byte 上限、损坏 bundle、稳定 ID、并发只读、反复创建销毁和切回 xiaohe。ArkTS 单元测试和双 ABI Native 构建也必须通过。

设备验收使用 Debug-only `pages/DebugCodeTable`，由构建脚本临时注入原创 fixture，经 ArkTS -> Node-API C++ -> Rust 真正调用。A～H 必须全部 PASS：空输入、精确优先、前缀回退、跨分类去重、分页、退格、超长保护，以及切回 xiaohe 的 `nihc -> 你好`、`uurufa -> 输入法`。2026-07-15 已在 x86_64 HarmonyOS 6.1 模拟器通过，证据位于 `docs/evidence/2026-07-15-stage-11.6.3/`。

Release 门禁必须同时证明源码 rawfile 和最终 HAP 均不存在 `fixture/test/synthetic/code-table` 资源；正式 `production.lex` 仍存在。11.6.3 留档的 Release HAP 为 11,353,521 bytes，SHA-256 `4473AAC84D06E1E65934473A1838CBB59B358BD2B57E70E19B08B4FA4D45C8E4`。

当前 Release 还必须证明 `entry/src/main` 与最终 HAP 均不存在 `DebugStage10`、`DebugCodeTable`、“调试与验收”和 Debug fixture 安装器。`test-release-resource-gate.ps1` 覆盖 production-only 正向用例以及 fixture、Debug 页面名、Debug 文案负向用例。

2026-07-22 正式数据回归在上述通用基线上追加：

```powershell
cd engine-rust
cargo test --workspace
cargo run --release -p code-table-runtime --example production_benchmark -- <正式包> <输出 JSON>
cd ..
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust -BuildMode debug
powershell -ExecutionPolicy Bypass -File scripts\device-accept-xiaohe-yinxing-stage11_6_3.ps1
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust -BuildMode release
powershell -ExecutionPolicy Bypass -File scripts\verify-release-hap.ps1
powershell -ExecutionPolicy Bypass -File scripts\test-xiaohe-yinxing-stage11_6_8-release-gate.ps1
```

- 正式包必须严格匹配 25,397,952 bytes/SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`、八类 73,263 条和冻结审计/合同身份；23 个独立参考快照逐项比较文本、编码、分类、`source_order` 和候选 ID。
- 损坏矩阵覆盖缺失/空文件、magic/header/版本、截断/尾随字节、内容/记录 SHA、manifest 元数据、分类缺失/重复/乱序、嵌套 `HSPLEX01`、`source_order`、用户规则和不安全路径；每类都必须返回结构化错误且进程继续存活。
- Release 性能使用 5 个独立新进程，每进程 20 轮预热和 18,000 次固定查询；OS 文件缓存未控制。留档结果为加载 P50/P95 `631.64/658.1578 ms`、查询 P50/P95 `2.14/16.16 μs`、峰值工作集 114,237,440 bytes。
- Debug-only `pages/DebugCodeTable` 经 ArkTS → Node-API C++ → Rust 验证正式身份、1～4 码、精确/前缀、跨类去重、分页、退格/reset、非法/超长、损坏包和显式双拼回退；x86_64 HarmonyOS 6.1 模拟器强停重启前后两轮 A～J 全 PASS。
- 最终 Debug HAP 为 40,387,851 bytes/SHA-256 `712DD5051B70D181BD178CD75755F38104F0DD5F03C0D6359EDAE0E028FB2CB9`；最终 Release HAP 为 11,952,684 bytes/SHA-256 `4034F1EFEF559BC3A004119410966684B88FD0AA2BFF45DB00857C4612CC7A77`，rawfile 仅有 `production.lex`。正式 `.hsyx`、fixture、原始 txt/ini、trace/report 和 INTERNET 权限负向注入均被拒绝。
- 完整元数据、性能结果、设备布局树与截图位于 `docs/evidence/2026-07-22-stage-11.6.3-formal/`。

## 阶段 11.6.4 用户码表规则接入

主机门禁与 11.6.3 相同，并额外固定以下覆盖：

- `user-lexicon` 17 项：码表专用普通新增、系统重复提升、候选完整编码精确删除、精确删除后禁止二次前缀回退、多个固顶、`#N`、固顶保护、同位置冲突、后规则覆盖、超界追加与稳定去重；
- `code-table-runtime` 41 项：覆盖作用于完整系统列表后才限量/分页、真实候选编码参与删除、快照替换与并发只读确定性；
- `ime-engine` 码表集成 13 项：使用真实生成 fixture 和实际用户文件，覆盖新增/删除/固顶/位置、后规则、分页、reset/句柄重建/清空学习、主备份恢复、双损坏降级、空文件和 `xiaohe` 隔离；
- `ime-ffi` 19 项：既有配置/结果 JSON 经过 FFI 后仍得到相同用户覆盖，interface/ABI version 保持 2；
- ArkTS 单元测试、x86_64/arm64-v8a Native、Debug/Release HAP、fixture 确定性和 Release 正负资源门禁。

Debug-only 设备页 A～J 必须全部 PASS：A 基线系统候选；B 普通用户词；C 完整编码精确删除及其他编码同名词对照；D 多个固顶；E `#2` 与固顶保护；F 后规则覆盖；G 完整列表后分页；H 句柄与真实应用进程重建；I 损坏主文件与备份恢复；J 切回 `xiaohe` 的 `nihc -> 你好`、`uurufa -> 输入法`。H 必须记录首次 `reusedExisting=false`，强停并重新启动应用后记录 `reusedExisting=true`，不能只用同一进程内重建替代。

2026-07-15 x86_64 HarmonyOS 6.1 模拟器 A～J 全部通过；设备布局树和截图位于 `docs/evidence/2026-07-15-stage-11.6.4/device/`。该阶段留档 Debug HAP 为 14,275,678 bytes/SHA-256 `1F4CA1189CDA66B71E7AD0D215CF800986E91FA09D8A9A3A46C88BAD9AE2305F`；同期 Release HAP 为 11,487,053 bytes/SHA-256 `96EF0230183B84D6495E4561B192378E6EAA79945CA669A850B193D99580C533`，包内仍只允许正式 `production.lex`。

## 阶段 11.6.5 产品分类

- Rust：八类合同/默认值/required/canonical/未知与重复 ID、不可变快照并发、分类过滤、分页、前缀、有效后续码、唯一性、非空 raw 原子重算、失败不变和 `xiaohe` 隔离。
- FFI：分类配置 JSON、数组更新、重复规范化、未知拒绝、非法 UTF-8/句柄和非码表 backend；interface/ABI 为 3。
- ArkTS：设置 schema 2 迁移幂等、空/重复/未知/乱序、native-first、保存失败回滚和跨运行时同步。
- internalDebug：A～L 连续两轮，第二轮由 force-stop/restart 开始；脚本为 `scripts/device-accept-xiaohe-yinxing-stage11_6_5.ps1`。稳定样例 `ahqi`、`a`、`bc`、`aift`、`bcbn`、`aoq` 来自冻结 bundle 参考快照。
- Release：默认设置页不得出现分类入口，HAP rawfile 仍仅 `production.lex`，正式 `.hsyx` 只在 internalDebug 构建窗口注入。

## 设置页系统栏与安全区专项

ArkTS 单元测试覆盖：

- 浅色/深色窗口背景严格复用设置页 `pageBackground` Token；
- 系统栏内容颜色复用高对比的 `primaryText` Token，图标明暗标志与背景匹配；
- 跟随系统、强制浅色、强制深色及主题保存成功后的窗口同步；
- 快速连续主题更新按串行队列落地，最终样式不会被旧异步请求覆盖；
- 沉浸式布局只初始化一次，协调器停止后取消设置状态订阅。
- Debug 固定浅色窗口 Token 使用白色背景、深色系统栏内容，不读取系统或输入法主题；
- 系统/强制主题更新和前台同步期间 Debug 页面覆盖保持最高优先级，退出后恢复设置页实际主题；
- 陈旧页面令牌不能清除较新的覆盖，快速进入/退出与异步主题切换最终落地最新状态；
- 窗口能力与安全区监听失败只降级记录日志，不拒绝协调器生命周期；
- 状态栏、挖孔、导航指示器和横屏侧边避让区合并为动态四边 inset。

模拟器或真机手工验收需要分别覆盖“系统浅色 + 输入法深色”“系统深色 + 输入法浅色”和跟随系统动态切换，检查状态栏、页面、底部手势区域无色带，时间/信号/电量/手势条可读，标题与列表未进入状态栏、挖孔或手势点击区。还需在旋转、分屏和设备支持的悬浮窗形态下复查；这些形态可能由系统窗口管理器限制或重写系统栏呈现，不能仅由桌面单元测试证明。

2026-07-15 的 x86_64 模拟器 Stage 11 验收已完成设置页深色、浅色、再次持久化深色和进程重启流程。安全区专项又在系统深色 + 输入法强制深色下完成：设置标题位于状态栏下方；Debug 标题上边界为 220px，状态栏下边界为 136px；滚到底部时 `TextArea` 下边界为 2674px，安全滚动视口下边界为 2758px；Debug 页面、状态栏和导航区保持浅色且系统栏内容为深色；深色键盘弹出后页面仍为浅色；切后台再回前台仍为浅色；返回设置页后上下系统区恢复深色。截图与布局树位于 `docs/evidence/stage11/device/safe_area_*`。

`scripts/device-accept-stage11.ps1` 现在会自动断言设置页/Debug 标题低于 `StatusBarBox`，滚到底部后最后一个 `TextArea` 不超过安全 `Scroll` 下边界，并保存 Debug 固定浅色及返回深色设置页截图。当前模拟器没有物理挖孔，也未覆盖真实设备厂商系统栏策略、分屏或悬浮窗；这些窗口形态下系统可能压缩、移动或接管系统栏，仍需对应设备复验。

## 阶段 11.6 正式码表测试合同

本节以 `CODE_TABLE_BEHAVIOR_SPEC.md` 和项目计划书的 11.6 重启版为语义来源。11.6.3 已实现系统查询，11.6.4 已实现用户规则，11.6.5 已完成产品分类合同、不可变选择快照和跨层设置闭环，11.6.6 已完成引导与封闭动作运行时；11.6.7 已实现冻结范围内的四码提交、顶屏、第五键单次重放、空码清屏和正/反向空码切分（ADR 0018）。测试 ID `code-table-fixture` 继续验证通用能力且不得进入 Release；正式数据测试必须使用独立的 `xiaohe-yinxing` bundle ID 和锁定来源 manifest。

Rust 表驱动测试至少覆盖：

- `词条<TAB>编码` 的确定性分类构建、许可清单和 Release fixture 排除；
- 有精确码时只返回精确候选，无精确码时跨启用分类按分类顺序和源行顺序枚举更长编码；
- 空字符串不枚举全表；退格后重新计算精确、前缀和候选唯一性；
- 普通用户词、`#删`、多个 `#固`、`#2`、位置冲突、越界位置和后规则覆盖；
- 正式包 36 条内置 `#固` 全部生效，规则画像、唯一键、稳定顺序和系统元数据保持；
- 包内优先、外部后置；同完整编码＋词条的外部普通/删除/固顶/位置规则覆盖内置规则；不同键保持稳定顺序；
- 外部文件缺失/空、主损坏备份有效、主备双损坏、进程重建、reset、切换方案和清空 `user-model`；
- 分类开关对候选、后续编码存在性和自动上屏判断同时生效；
- 分号引导状态、非法引导输入、连续退格和退出；
- 自动上屏码长、空码清屏码长、顶屏码长的完整状态矩阵；
- 第五码顶出前四码首选后，第五键作为下一段编码原子重放；
- 前四码无首选时不提交旧段，清空旧段并把当前键作为新段首键；
- 顶屏已产生提交时，重放的新段即使达到自动阈值也不得在同一次操作产生第二次提交；
- 精确候选被 `#删` 清空后不在同一次查询中二次混入系统前缀候选；
- 三码长参数不相等时执行“旧段 top 前置 -> 新段 empty -> 新段 auto”的固定优先级；
- 引导空码不枚举引导全表，连续分号、非法键、空格、回车、无候选和方案切换均有退出路径；
- 方案切换后双拼和码表状态、缓存及候选会话互不泄漏；
- 随机 ASCII、超长输入、连续删除、损坏码表和反复分类切换不 panic。

跨层和设备测试至少覆盖：

- ArkTS 只路由方案、分号、分类和参数，不包含码表查询或顶屏算法；
- C++ 只转换参数和结果，不包含业务规则；
- 一次按键最多触发一次对编辑框可见的提交；
- `processKey` 同时返回 `commitText` 和非空 `rawInput` 时，ArkTS 只提交一次并继续展示操作后组合；
- 设置切换即时生效并在进程重启后保留，码表不可用时安全回退 `xiaohe`；
- Release HAP 只包含许可证和校验通过的正式二进制码表；
- 现有小鹤双拼解析、生产语料、整句解码、用户学习和用户覆盖全量无回归。

11.6.4 的 internalDebug A～J 必须连续运行两轮，每轮从 force-stop/restart 开始，覆盖冻结身份与 36 条画像、代表性内置固顶、全 36 规则 Rust 集合证明、未命中系统基线、外部删除、固顶/位置保护、完整列表后分页、主备份恢复/双损坏、重启/reset/清学习持久性和 `xiaohe` 隔离。2026-07-23 x86_64 HarmonyOS 6.1 模拟器两轮均通过；证据位于 `docs/evidence/2026-07-23-stage-11.6.4-formal/`。

## Rust

运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-rust.ps1
```

这将执行：

- `cargo fmt --check`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test --workspace`

## C++ 桥接

当前通过 `ime-ffi` 测试、正式 Engine Handle 的 ArkTS 原生网关测试、双 ABI Native 构建和 Release HAP 内容门禁验证 C++ 桥接。固定候选接口只在 Rust `cfg(test)` 中编译，不再通过键盘 UI、ArkTS Native 网关或 Node-API 验证。C++ 层只做参数校验、UTF-8 转换、错误映射和 Rust 调用转发，不包含候选查询、排序、分页或缓存算法。

专用 C++ 单元测试尚未引入，因为当前项目没有 C++ 测试工具。未来的桥接测试应涵盖无效参数、Rust 错误码、无效 JSON、空缓冲区、重复调用和 Rust 缓冲区释放。

## ArkTS

运行：

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test
```

阶段 2 控制器测试涵盖：

- 默认英文键盘模式
- 英文/中文模式切换
- 清晰的无会话错误处理
- 会话启动/停止状态
- 键盘可见性状态
- QWERTY 布局数据保持 Q/A/Z/功能键的自然自上而下顺序
- 字母和空格插入路由
- 删除、回车和隐藏路由
- 正式候选会话、提交和原生错误映射

阶段 3 键盘 UI 工程化测试涵盖：

- `QWERTY_LAYOUT` 行数和 Q/A/Z 自然顺序
- 字母键种类、权重和预览开关
- 功能键预览关闭
- 删除键、空格键和旧版 `QWERTY_KEY_ROWS` 兼容导出
- 竖屏/横屏尺寸差异和总高度计算
- 浅色/深色调色板差异
- 长按删除启动、停止、销毁和残留计时器清理
- 阶段 2 布局兼容性

## 阶段 3 验证脚本

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage3.ps1
```

在需要在线模拟器或设备安装/IME 状态验证的情况下：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage3.ps1 -DeviceValidation
```

这将检查环境、Rust 格式化/lint/测试、x86_64 和 arm64-v8a 的原生产物、ArkTS 单元测试、HAP 构建、源代码级回归守卫、产物摘要、安装、启用和当前 IME 状态。

阶段 3 源码守卫还会检查：

- 阶段 3 设计常量、布局模型、候选栏和基础按键组件必须存在。
- `InputPanelController` 必须加载 `KeyboardRootStage3`。
- 面板创建失败时不得继续把键盘标记为可见。
- `KeyboardLayoutSpec` 不得通过 `.reverse()` 反转行顺序。
- `KeyboardRootStage3` 不得直接导入 IME Kit 或 `libime_bridge.so`。
- `DeleteRepeatController` 必须具备 `destroy` 和 `clearTimeout` 清理逻辑。
- 阶段 2 的会话状态、键盘动作路由和删除后备仍需保留。

阶段 2 回归脚本仍可按需运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage2.ps1
```

## 阶段 4 验证脚本

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage4.ps1
```

这将检查环境、Rust format、Rust clippy、Rust workspace tests、阶段 4 parser 专项测试、x86_64 和 arm64-v8a 原生产物、ArkTS 单元测试、HAP 构建、阶段 4 源码边界、产物摘要和可选设备验证。

阶段 4 Rust 测试覆盖：

- `pinyin-syllable`：合法音节集合、大小写、`ü/v` 规范化和非法音节。
- `shuangpin-schema`：小鹤 schema 加载、空 ID、非法键、重复映射、冲突映射、非法目标音节、损坏 JSON、缺少字段和错误版本号。
- `shuangpin-parser`：正常音节、零声母、非法组合、不完整组合、连续编码、删除回退、方案切换和稳定性。

阶段 4 源码守卫还会检查：

- 小鹤配置必须来自 `engine-rust/schemas/xiaohe.json`。
- 阶段 4 fixture 测试必须注册。
- C++ 中不得出现小鹤或双拼业务规则。
- ArkTS 中不得出现双拼解析实现。
- Rust parser 不得依赖 HarmonyOS API。
- 正式输入页面入口必须保留；固定候选回归路径不得进入 ArkTS、Node-API 或生产 OHOS 静态库。

## 阶段 7 验证脚本

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage7.ps1
```

阶段 7 本地验证覆盖：

- Rust format：`cargo fmt --check`
- Rust lint：`cargo clippy --workspace --all-targets -- -D warnings`
- Rust workspace tests：当前 98 个显式 Rust 测试
- 阶段 4 parser 回归：`cargo test -p shuangpin-parser --test stage4_cases`
- 阶段 5/7 FFI 回归：`cargo test -p ime-ffi`
- 阶段 6 词库构建、验证和确定性回归
- 阶段 7 查询测试：`cargo test -p candidate-query`
- 阶段 7 排序测试：`cargo test -p candidate-ranking`
- 阶段 7 分页、缓存、候选提交和固定候选回归：`cargo test -p ime-engine`
- Rust OHOS x86_64 与 arm64-v8a 静态库构建
- ArkTS 单元测试：hvigor `entry@default test`
- Release HAP 构建：`scripts\build-hap.ps1 -SkipRust -BuildMode release`
- Release HAP 内容门禁：`scripts\verify-release-hap.ps1`
- 架构边界扫描

阶段 7 源码守卫检查：

- ArkTS 不包含候选排序公式或正式中文候选硬编码。
- ArkTS rawfile installer 只复制二进制资源并传递沙箱路径。
- CandidateBar 不直接调用 Native 或 IME Kit。
- C++ 不包含拼音索引、词库查询、排序、分页或缓存算法。
- Rust 查询/引擎 crate 不依赖 HarmonyOS API。
- 运行时 crate 不读取 TSV。

阶段 7 固定候选回归数据位于：

```text
engine-rust/tests/fixtures/stage7_candidate_cases.tsv
```

该 fixture 记录原始双拼编码、预期解析音节、查询类型、第一页候选、必须出现/禁止出现候选、首选、`hasNextPage` 和提交文本。

## 阶段 8 验证脚本

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage8.ps1
```

阶段 8 本地验证覆盖：

- 阶段 8 必需文件和 `sentence-decoder` workspace 注册。
- Rust format：`cargo fmt --check`
- Rust lint：`cargo clippy --workspace --all-targets -- -D warnings`
- `sentence-decoder` 单元测试：19 个测试，覆盖空输入、单音节、两音节词、多音节短句、多切分、完整覆盖优先、fallback 惩罚、不完整尾部、去重、稳定排序、beam/边数/长度上限和重复执行稳定性。
- 阶段 8 集成 Rust 测试：`candidate-query`、`candidate-ranking`、`sentence-decoder`、`ime-engine`。
- `ime-engine` 阶段 8 fixture：`engine-rust/tests/fixtures/stage8_sentence_cases.tsv`，覆盖短句首选、部分提交、剩余 raw input、剩余首选、禁止候选和稳定 tie-breaker。
- `ime-ffi` 回归：14 个测试，包含短句候选数组、部分提交结果、剩余 `rawInput`、无效索引、panic 隔离和 buffer 释放。
- Stage 4 parser regression。
- Stage 6 lexicon build/verify。
- Stage 8 lexicon build/verify。
- x86_64 与 arm64-v8a OHOS native artifact 构建。
- ArkTS 单元测试，包含 `compositionFinished=false` 时保留剩余组合、空格提交短句和阶段 7 控制器回归。
- HAP 构建。
- 架构边界扫描。

阶段 8 源码守卫检查：

- `sentence-decoder` 必须存在图、Viterbi/path search、评分和 limits 模块。
- ArkTS 不包含短句解码、整句评分、二进制词库解析或 graph/path 算法。
- C++ 不包含 Viterbi、Beam Search、音节图、词库索引或评分算法。
- Rust 核心不依赖 OHOS/HarmonyOS API。
- 运行时 crate 不读取阶段 8 TSV 文件。

阶段 8 设备安装、IME 启用和真实输入框验证尚未自动执行。

## 阶段 9 验证脚本

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage9.ps1
```

阶段 9 本地验证覆盖：

- Rust format：`cargo fmt --check`
- Rust lint：`cargo clippy --workspace --all-targets -- -D warnings`
- `user-model` 单元测试，覆盖缺失文件、选择次数、饱和计数、最近使用、禁用学习、保存/加载、延迟刷盘、清空、截断文件、魔数错误、版本错误、备份恢复、容量控制和 rawInput 哨兵隐私检查。
- `candidate-ranking` 用户分接入测试，验证空用户分保持阶段 8 顺序、非首选提升、match type 边界和稳定 tie-breaker。
- `sentence-decoder` 用户分回调测试，验证空用户分保持阶段 8 顺序和短句候选可被用户分提升。
- `ime-engine` 阶段 9 单元和 fixture 测试，覆盖非首选上升、加权上限、重启保留、禁用学习、清空恢复、损坏恢复、短句和部分提交。
- `ime-ffi` 测试，覆盖新增用户模型路径、load、flush、clear、学习开关、会话学习策略、无效句柄和路径校验。
- Rust workspace tests。
- x86_64 与 arm64-v8a OHOS native artifact 构建。
- ArkTS 单元测试，覆盖 EngineCoordinator 用户模型加载、会话学习策略、输入会话结束 flush 和 clearUserModel 服务调用。
- HAP 构建。
- 架构边界扫描：ArkTS 不含用户排序公式，C++ 不含用户模型业务算法，user-model 不依赖 HarmonyOS API，candidate-query 和 sentence-decoder 不直接操作用户模型文件，无新增网络权限。

阶段 9 固定 fixture：

```text
engine-rust/tests/fixtures/stage9_user_learning_cases.tsv
```

设备安装、系统 IME 启用、真实输入框重复选择、真实密码输入框和截图/录屏仍需手工验收。

## 词库规则增强第二阶段验证

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-lexicon-rules-phase2.ps1
```

专项门禁覆盖：

- `user-lexicon` 严格解析：四种规则、BOM、LF/CRLF、空文件、末行无换行、最大位置、非法 UTF-8、字段数、空字段、非法编码、未知/重复/错位标记、`#0`、负数、正号、小数和溢出。
- 重复规则后者覆盖、最终 `source_order`、固定/同位置规则顺序和哈希插入无关性。
- `#删/#固/#N`、普通用户词条、系统重复提升、固顶与位置冲突、超长位置追加、稳定去重及精确/前缀空输入规则。
- 主/备份保存恢复、相同快照字节一致、损坏主文件、双损坏、缺失文件、失败 reload 保留旧快照和并发保存完整性。
- `ime-engine` 启动加载、缺失/损坏文件降级、用户候选选择提交、空格首选共用候选会话、学习不突破硬位置及分页前全局位置。
- `ime-ffi` 可选 `userLexiconPath` 向后兼容，ABI version 2 不变。
- 第一阶段 `ExactOrPrefix + SourceOrder` 确定性回归、生产词库重建/大小/SHA-256、5,171 条生产语料、双 ABI Native、ArkTS、Release HAP 及包内无用户 fixture。

原创 fixture 位于 `engine-rust/tests/fixtures/user-lexicon/`，不会复制到 `entry/src/main/resources`。x86_64 模拟器已在正式候选链路验证普通用户词显示/提交、删除、固顶、`#2`、进程重启和空文件恢复；设备证据位于 `docs/evidence/lexicon-rules-phase2/device/`。未来设备不可用时仍必须记录“未执行”，不得用桌面测试替代设备结论。

## 运行时模拟器回归

阶段 2 x86_64 模拟器回归涵盖：

- 键盘面板可见
- QWERTY 行完全可见
- 字母插入
- 空格插入
- 删除
- 隐藏键盘
- 正式 Rust 候选词显示和提交路径保持可调用
- 正式键盘中不存在“回归”或“模型”调试控件

证据文件：

- `docs/evidence/stage2/stage2_keyboard_visible_full_layout.json`
- `docs/evidence/stage2/stage2_after_input_delete_layout.json`
- `docs/evidence/stage2/stage2_space_input_layout.json`
- `docs/evidence/stage2/stage2_after_hide_layout.json`
- `docs/evidence/stage2/stage2_keyboard_order_fix_layout.json`
- `docs/evidence/stage2/stage2_keyboard_order_fix_input_layout.json`
- `docs/evidence/stage2/stage2_keyboard_order_fix_after_hide_layout.json`
- `docs/evidence/stage2/stage2_visual_key_fix_layout.json`
- `docs/evidence/stage2/stage2_visual_key_fix.jpeg`

## 设备覆盖

- 本地构建和单元测试：阶段 8 已于 2026-07-09 验证。
- x86_64 模拟器：阶段 2 运行时已于 2026-07-08 验证。
- 在线模拟器/真实手机 Stage8 运行时：尚未执行，待有稳定系统输入法环境时验证。
- ARM64 真机：待人工验证。

## 回归规则

### 2026-07-14 候选栏与删除键专项回归

- ArkTS：文本编辑器空闲态候选栏可见；中文/英文切换保持；邮箱和 URL 英文布局保持；密码、数字、小数和电话专用布局不显示。
- ArkTS：中文组合态删除只更新预编辑和候选；候选提交后以及英文、数字、小数、电话、邮箱、URL、搜索和多行上下文统一调用编辑器删除服务。
- x86_64 模拟器：空闲态与输入态同一字母键 Y 坐标一致；中文候选提交后、英文、临时数字、数字、小数、电话、邮箱、URL、搜索和多行均从单字符删除到空。
- x86_64 模拟器：快速连续三次删除得到 `abc -> 空`；邮箱框隐藏输入法、重新显示后仍可删除。
- 删除连接层使用 `InputClient.deleteForward` 执行 HarmonyOS 退格语义；`SafeDeleteExecutor` 继续保证一次动作不会在不确定结果下串联第二次删除副作用。

### 2026-07-14 浏览器无文本预览兼容回归

- ArkTS：`textPreviewSupported=false` 时连续中文按键不调用 `setPreviewText`，但 rawInput 与候选正常更新。
- ArkTS：无预览编辑器确认候选时只调用一次 `insertText`，随后执行既有 Native 候选确认并清空组合。
- ArkTS：`textPreviewSupported=true` 的普通 ArkUI 文本框继续逐键更新预览，原预览失败不重试规则保持不变。
- x86_64 模拟器浏览器搜索框：输入 `ni` 后候选栏出现“你”等候选、搜索框不插入拼音、无红色错误；点击“你”后搜索框内容为“你”。
- 设备证据：`docs/evidence/stage10/device/browser_fix_ni.png`、`browser_fix_committed.png` 及对应布局 JSON。

### 2026-07-16 Release 隔离与设备脚本回归

- Release：`default` 页面清单只允许正式设置/键盘页面；`entry/src/main` 和最终 HAP 不得出现 `DebugStage10`、`DebugCodeTable`、“调试与验收”或内部 fixture，资源门禁正负用例必须通过。
- Debug：使用 `internalDebug` target/source set；启动页必须能分别进入正式设置、Stage 10 输入框验收和码表运行时验收。
- 手机设置持久化：脚本必须从控制器日志读取本轮 `widthPx/heightPx`，并与系统 `ResizePanel,success` 精确匹配，不允许写死设备像素；运行前必须启用并确认 `AppScope/app.json5` 对应的当前 IME，三档模式及默认值恢复均需 PASS。
- 平板 Stage 10：包括“123”在内的键位必须在当前 `KeyboardRootStage3` 可见根节点边界内查找，不允许依赖旧绝对 Y 范围；全部编辑器类型、Shift、数字/符号、删除和回车流程需通过。
- 2026-07-16 基线：phone `1320×2856` 的 compact/standard/tall 分别应用 `1320×959`、`1320×1082`、`1320×1211`；tablet `1920×2880` Stage 10 全流程 PASS；ArkTS 184/184 PASS。

### 2026-07-17 浏览器静默清空与会话隔离回归

- 兼容组合仍附着时继续扩展同一范围；编辑器读取结果延迟收敛时允许有限让步，不应误判为已脱离。
- 浏览器搜索框在没有 `discardTypingText` 的情况下清空旧组合后，下一字母必须从空 Rust/ArkTS 组合开始，且不得把旧拼音或候选写回编辑器。
- 收到 `discardTypingText` 时同步重置预览所有权、Rust 组合和候选，不额外执行编辑器文本写入。
- 输入停止、键盘隐藏、编辑框切换和 Ability 销毁后，旧 generation 的预览、提交、清理或附着检查结果不得改变新会话。
- 隐藏后重开键盘应获得全新的组合管理状态；部分候选提交的可信锚点仍只允许在原 generation 内一次性消费。
- Release 构建需同时确认 signed APP 存在、unsigned APP 不作为上传候选；签名文件必须另行检查证书/Profile/包名和 AGC 接受性，不能用文件名代替验签。

### 2026-07-29 输入码两码切分回归

- Rust `engine-protocol`：`vegewtyijkjj` 必须输出
  `displaySegments=["ve","ge","wt","yi","jk","jj"]`，且 `rawInput` 逐字节不变。
- Rust：完整双码、奇数尾码、显式 `'` 边界和 `;` 引导字符均生成确定性展示段；
  空输入和已提交状态返回空数组。
- C++/ArkTS：`displaySegments` 必须跨 Node-API、Native 网关和
  `InputSessionStore` 原样传递；缺失字段的测试替身安全回退为原始输入。
- UI：顶部候选栏、Pad 固定侧栏和保留浮动组件只连接引擎段，不读取候选
  `reading`，并继续用下划线标识未上屏。
- 生命周期：退格、显式分词、部分提交、完整提交、切换焦点和隐藏键盘后不得保留
  旧展示段。
- 门禁：ArkTS 全量单测、Rust workspace、双 ABI Native 和 HAP 构建均需通过；
  稳定候选快照只允许协议字节数变化，候选内容、顺序、分页和提交不得变化。

任何涉及 `module.json5`、`main_pages.json`、target/source set、`settings_entry_page`、`setUiContent`、面板尺寸、QWERTY 行顺序、原生模块名称、CMake、Rust 产物路径、ABI 目录、`ImeConnectionService.deleteBackward` 或键盘动作路由的更改都需要进行新的模拟器回归，并重新执行 Release 源码/HAP 内容门禁。
