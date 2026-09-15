# Harmony 双拼输入法

使用以下技术栈的 HarmonyOS NEXT 输入法原型：

```text
ArkTS InputMethodExtensionAbility -> C++ Node-API -> Rust C ABI
```

当前正式版本是一条完整的小鹤双拼智能拼音链路：双拼编码经 Rust 解析为拼音，查询 65,122 条生产词库，生成单字、词语和短句候选，并支持分页、部分提交、用户学习及 `#删/#固/#N` 用户词库覆盖。HarmonyOS 侧已经具备多编辑器键盘策略、正式设置页、主题、安全区、震动和按键音。

阶段 11.6 已于 2026-07-22 重启为正式小鹤音形双链路：经理交付的根目录 `码表` 与 `小鹤音形` 文件作为正式上游输入，现有小鹤双拼继续保持默认且不改语义。11.6.2B～11.6.8 已完成权威审计、正式 bundle、系统查询、用户规则、产品分类、运行时状态机和正式产品入口；11.6.9 发布验收当前为部分完成。

## 当前状态

- 2026-09-15 已生成 **0.13.0 正式签名 APP**（`versionCode=13000000`），包含皮肤工坊入口及当前反馈修复。双 ABI 构建、签名、升级身份、版本及资源门禁通过，正式 Profile 的皮肤共享目录授权匹配。[下载 APP](artifacts/0.13.0/ShuangYuIME-0.13.0-13000000-release-signed.app) · [发布核查](outputs/release-0.13.0/RELEASE_READINESS.md)。本轮未重新安装或上传 AGC，下方为历史记录。

- 2026-09-14 已生成 **0.12.0 正式签名客户 APP**（`versionCode=12000000`），包含手机、电脑模拟器九项反馈验收后的修复。代码、双ABI引擎和资源与验收包一致；签名、升级身份、版本及资源门禁通过。交付见 [0.12.0 客户测试包](artifacts/0.12.0/AGC_UPLOAD_README.md)，详情见 [发布核查](outputs/release-0.12.0/RELEASE_READINESS.md)。下方为历史阶段记录。

- 2026-09-11 已构建 `0.11.0` 正式签名 APP（`versionCode=11000000`），包含最新键盘/双拼反馈及应用内查形修复。双 ABI、正式签名、与0.10.0升级身份、版本/权限/网页路由/资源门禁通过。交付见 [0.11.0 客户测试包](artifacts/0.11.0/AGC_UPLOAD_README.md)，核查见 [发布报告](outputs/release-0.11.0/RELEASE_READINESS.md)。本轮未上传AGC或重新执行0.11.0设备安装；下述旧版本记录保留为历史证据。

- 2026-09-10 已构建 `0.10.0` 客户测试正式签名 APP（`versionCode=10000000`），纳入最新客户反馈及全部设置详情/子页统一 UI。新运行 ArkTS 686 项、双 ABI 构建、签名与发布资源门禁通过；手机/电脑 0.10.0 模拟器升级与导航补测通过。用户确认本次暂不包含自定义结构/皮肤导入（待华为共享沙箱授权），内置项可测；真实宿主与实体键盘仍需客户验证。下载文件、限制和测试重点见 [0.10.0 客户测试包](artifacts/0.10.0/AGC_UPLOAD_README.md)，完整证据见 [发布核查](outputs/release-0.10.0/RELEASE_READINESS.md)。

- 2026-09-08 已构建 `0.9.0` 客户测试 signed APP（`versionCode=9000000`），包含三/四码自动切分、成对符号及系统子类型同步修复；双 ABI Native、clean Release 构建、正式发布签名与包内资源门禁通过。交付文件和说明见 [0.9.0 客户测试包](artifacts/0.9.0/AGC_UPLOAD_README.md)。最低系统为 HarmonyOS 6.1.1（API 24）；最终 0.9.0 包未新增设备验收，指定第三方宿主和真实实体键盘仍待测试。
- 2026-08-31 已按客户澄清把 0.6.0 第 1～6 点统一纳入实体键盘验收：补齐 PC 新旧按键 API 的按键相位去重，避免 `o→oo`、`ok→okk`；客户 `5.直通.txt` 直接生成可增删的受控动作词条数据，不再逐编码固化；浮动候选窗中的输入码取消下划线，嵌入/固定展示位继续用下划线表达未上屏。signed 0.6.0 HAP 已在 x86_64 2in1 模拟器以系统按键注入逐项通过，Phone 固定候选栏下划线对照通过；真实 USB/蓝牙/内置键盘仍未验收。详见 [0.6.0 实体键盘反馈矩阵](docs/features/input-method/PHYSICAL_KEYBOARD_0_6_0_FEEDBACK.md)与[模拟器验收证据](docs/evidence/2026-08-31-v0.6.0-physical-keyboard/README.md)。
- 2026-08-27 已完成 `0.5.1` 客户反馈闭环修复：复制后使用原生光标移动收起选区，并以受控进程内副本兼容 HarmonyOS 6.1 的扩展粘贴权限限制；删行/恢复不再依赖部分宿主失效的范围选择；中文输入码统一只在候选区域以实线下划线显示；小鹤音形万能键不再被 UI 二次过滤。Rust workspace（FFI `39/39`）、Release 资源/实包门禁及 Phone/Pad/2in1 复验通过；最新 ArkTS `567` 项源码编译通过，但 Windows Previewer 因 AMD OpenGL 驱动崩溃未生成最终执行报告，最近一次完整报告为 `565/565 PASS`。完整证据见 [0.5.1 客户反馈闭环](docs/evidence/2026-08-27-v0.5.1-customer-feedback/README.md)。
- 2026-08-27 皮肤键盘新增可开关架高层：左侧系统输入法、右侧隐藏键盘，中间集中键盘菜单；数字/符号入口统一为 `ϟ12`，辅键盘返回统一左下，逗号/句号分列空格两侧并支持第三/第二候选快捷选择。
- 2026-08-27 已加入皮肤键盘编辑手势：回删键上滑撤销上屏、下滑删行；回车键上滑重复上屏、下滑安全恢复最近删除。26 键字母下滑符号可在“键盘结构与皮肤”页按中英文分别设置，符号不显示在键面。
- 2026-08-26 已按客户给出的 `给予,给ʲⁱ̌予<Tab>gwyu#直` 语义实现可配置直通词条：输入 `gwy` 时显示 `给ʲⁱ̌予u`，选中或输完 `gwyu` 后只上屏 `给予`；`#直` 可写在词条所属分类中、随该分类开关生效且不进入万能键反查。候选协议已分离展示文本和提交文本，正式 bundle 与应用资源同步升级。
- 2026-08-21 已按客户说明补齐全码词置顶和直通语义：`#固` 词条现在真正随全码词分类开关启用/隐藏；全码词来源可用 `#直` 标记“正常编码可输入、万能键不可查”的词条。11 分类和分号快符行为不变，现有源尚未标记具体 `#直` 条目。
- 2026-08-20 按客户要求调整小鹤音形默认分类：在完整直通语法尚未支持期间，二简次选、全码词、生僻字、全码字默认关闭，需要时可在设置页手动开启；新装、重置、旧版全开快照迁移和正式 bundle 已保持一致，非全开自定义组合不被覆盖。
- 2026-08-19 已完成 9 键候选召回、排序与延迟优化：public-regression 900 条 Top1/Top3/Top5 从 `14.667%/17.556%/18.556%` 提升到 `34.333%/42.667%/45.222%`，未召回从 `39.889%` 降到 `34.667%`，每键 P95 从 `237.583 ms` 降到 `71.588 ms`；dev 155 条 Top1 从 `9.032%` 提升到 `15.484%`，P95 从 `247.365 ms` 降到 `65.560 ms`。两组 Release 三轮候选确定，安全计数为 0；blind 与设备未重跑。详见 [9 键候选优化](docs/features/pinyin/PINYIN9_OPTIMIZATION_20260819.md)。
- 2026-08-18 已完成全拼候选质量提升：正式随包词库启用 V2 全领域 131 条增量，并加入 ≥5 音节正式长词精确召回保护；V2 dev Top1/Top3/Top5 为 `97.917%/97.917%/97.917%`。评测器新增三类互斥失败指标、隔离用户学习效果探针和只接受长度桶的匿名分布加权入口；真实匿名分布尚未提供，未伪造真实数据结论。详见 [全拼候选质量提升 V3](docs/features/pinyin/QUANPIN_QUALITY_IMPROVEMENT_V3.md)。
- 2026-09-03 修正实体键盘分号引导的确认时机：`;f` 重复上屏、`;i` 安全撤销、六组成对符号居中和 `;n` 行末定位均在字母按下后立即执行，不再要求额外空格；分类词库原子组合开关及授权固定来源用户词库导入保持不变。实现使用有限动作白名单，不执行任意 `$cmd`。详见 [六项直通编码实现说明](docs/features/direct-control/DIRECT_ENCODING_SIX_REQUIREMENTS.md)。
- 2026-08-13 阶段 5 已完成四正式档案的主机联合收口：`xiaohe-17`、`xiaohe-26`、`quanpin-26`、`pinyin-9` 均从统一入口启用；Rust `505/505`、ArkTS `440/440`、双 ABI Native、Release HAP 与实包内容门禁通过。x86_64 Phone/Pad signed Release 已完成核心全拼/T9/双拼链路，但 ARM64 真机、真实第三方应用和完整旋转/性能矩阵未运行，因此状态为 `IMPLEMENTED / HOST_VALIDATION_COMPLETED / DEVICE_VALIDATION_PARTIAL`；详见 [阶段 5 验收](docs/features/pinyin/PINYIN_STAGE5_FINAL_ACCEPTANCE.md)。
- 2026-08-25 工程版本已升级为 `0.5.0`（`versionCode=5000000`），用于客户测试发布；本版纳入 26 键全拼、9 键拼音、六项直通编码、全领域词库和小鹤音形冷启动/内存优化，并修复横屏 T9 首次面板创建及实体键盘智能句号连续输入。AGC 上传前仍需核对应用身份、完成软件包基础检测和所需设备矩阵。
- 当前四个拼音正式档案：`xiaohe-17`、默认 `xiaohe-26`、`quanpin-26`、`pinyin-9`；小鹤音形另以 `xiaohe-yinxing-17/26` 隔离提供。
- 阶段 12 已加入直通命令、`Ctrl+Alt+0～9` 实体键盘预设、11 类音形词库正式开关，以及支持普通/隐藏/固顶/第 N 位和批量导入导出的用户词库管理页；详见 [阶段 12 文档](docs/features/direct-control/STAGE12_DIRECT_CONTROL_USER_LEXICON.md)。
- 中文组合输入码由 Rust 输出两码展示段；嵌入/固定展示位以下划线表示未上屏，输入码与候选共同显示在浮动窗时不加下划线。例如 `vegewtyijkjj` 显示为 `ve'ge'wt'yi'jk'jj`，显示分隔符不参与查询、学习或上屏。
- 当前生产词库：366,660 条、274,865 个拼音键、24,049,458 bytes，SHA-256 `005169F6050D45F93DD511D7DE183338419419B67FB3556065B15432B0522A41`；正式随包启用 Rime 基础层、Jieba+pypinyin 成熟词库层、时效热词与六类专业领域词条。
- 当前码表基础：严格 bundle、精确/前缀查询、11 分类合同、分类内 `#固/#直`、原子分类快照、分号引导动作运行时、四码唯一提交、第五键顶屏、空码清屏及冻结的正/反向空码切分均已实现。
- 小鹤音形精准输入：当前编码精确命中时只显示同码候选；未命中但存在严格更长编码时，按词库源顺序固定只显示第 1 项精准匹配提示及未输入编码后缀，不提供数量选项，且提示不参与自动上屏、第五键顶屏或空码切分。四码过滤后唯一时仍只自动上屏一次，真实重码等待选择。Phone/Pad x86_64 模拟器上的既有 signed Release 矩阵已通过；本轮固定单项提示尚未执行设备验收，ARM64 真机仍未验收。
- 当前开发入口：11.6.7 与 11.6.8 已完成主机和 x86_64 模拟器范围；默认方案仍为小鹤双拼，正式设置页可选择小鹤音形，正式 bundle 由 HAP 原子安装并校验。详见 [项目计划书阶段 11.6](docs/product/planning/PROJECT_PLAN.md#阶段-116正式小鹤音形双链路2026-07-22-重启)。
- 当前验证：0.2.0 的主机与构建门禁均为 9/9 PASS；保留的 27 个客户源文件哈希不变，含凭据的 Android 配置已删除，15/15 双构建一致，x86_64/arm64-v8a 构建、signed/unsigned Release、负门禁和签名复核均通过。signed Release 已在独立包名验收客户端上完成 Phone 竖屏与 Pad 横屏的聊天、URL、搜索、多行、应用切换和压力场景；0.1.0→0.2.0 覆盖升级保留了方案、设置和 2 条用户学习记录。物理 ARM64、同一设备旋转、系统分屏、真实聊天/浏览器应用和小时级 soak 仍未执行，详见 `docs/evidence/2026-07-29-v0.2.0-acceptance/`。
- 当前状态的唯一详细入口是 [PROJECT_STATE.md](PROJECT_STATE.md)；历史实现记录保存在 [CHANGELOG.md](CHANGELOG.md)、`docs/adr/` 和 `docs/evidence/`。
- **设备支持**：支持手机（phone）和平板（tablet）设备，包括 MatePad Edge。键盘尺寸自适应屏幕分辨率，支持横屏和竖屏模式。
- **Debug/Release 说明**：Release 使用 `default` target，只包含正式页面、路由、文案和 `production.lex`；内部验收使用 `internalDebug` target/source set，包含 Debug 启动页、验收页和临时 fixture。Release 源码与最终 HAP 均由门禁拒绝 Debug 页面名、内部文案和 fixture。

## 主要路径

- 输入法能力：`entry/src/main/ets/inputmethod/Stage0InputMethodAbility.ets`
- 应用控制器：`entry/src/main/ets/application/`
- 会话状态：`entry/src/main/ets/state/InputSessionStore.ets`
- 键盘域动作：`entry/src/main/ets/domain/keyboard/KeyboardAction.ets`
- 正式键盘 UI：`entry/src/main/ets/presentation/keyboard/KeyboardRootStage3.ets`
- 键盘设计常量：`entry/src/main/ets/presentation/keyboard/design/`
- 键盘布局模型：`entry/src/main/ets/presentation/keyboard/model/KeyboardLayoutSpec.ets`
- 键盘按键组件：`entry/src/main/ets/presentation/keyboard/components/`
- IME Kit 包装器：`entry/src/main/ets/infrastructure/ime/ImeConnectionService.ets`
- 原生网关：`entry/src/main/ets/infrastructure/native/NativeEngineGateway.ets`
- 词库 rawfile 安装：`entry/src/main/ets/infrastructure/resource/LexiconResourceInstaller.ets`
- C++ 桥接：`entry/src/main/cpp/`
- Rust 工作空间：`engine-rust/`
- 小鹤双拼配置：`engine-rust/schemas/xiaohe.json`
- Rust 双拼解析器：`engine-rust/crates/shuangpin-parser/`
- Rust 正式引擎：`engine-rust/crates/ime-engine/src/formal.rs`
- 用户学习模型：`engine-rust/crates/user-model/`
- 用户词库覆盖层：`engine-rust/crates/user-lexicon/`
- 用户词库校验/导入工具：`engine-rust/tools/user-lexicon-tool/`
- 用户词库沙箱路径：`entry/src/main/ets/infrastructure/storage/UserLexiconPathProvider.ets`
- 编辑器上下文：`entry/src/main/ets/domain/editor/EditorContext.ets`
- 编辑器属性映射：`entry/src/main/ets/infrastructure/ime/EditorAttributeMapper.ets`
- 模式与 Shift 策略：`entry/src/main/ets/application/KeyboardModePolicy.ets`、`EnglishShiftController.ets`
- 正式键盘布局：`entry/src/main/ets/presentation/keyboard/layouts/Stage10KeyboardLayouts.ets`
- 候选查询：`engine-rust/crates/candidate-query/`
- 候选排序：`engine-rust/crates/candidate-ranking/`
- 短句解码：`engine-rust/crates/sentence-decoder/`
- C ABI：`engine-rust/crates/ime-ffi/`
- 词库核心：`engine-rust/crates/lexicon-core/`
- 词库构建器：`engine-rust/tools/lexicon-builder/`
- 阶段 6 测试词库：`dictionaries/source/stage6_test.tsv`
- 阶段 6 生成词库：`dictionaries/generated/stage6_test.lex`
- 阶段 7 测试词库：`dictionaries/generated/stage6_test.lex`（仅自动回归，不打包）
- 阶段 8 测试词库：`dictionaries/generated/stage8_sentence_test.lex`（仅自动回归，不打包）
- ArkTS 引擎协调器：`entry/src/main/ets/application/EngineCoordinator.ets`
- 双拼 schema 校验：`engine-rust/crates/shuangpin-schema/`
- 拼音音节校验：`engine-rust/crates/pinyin-syllable/`
- 构建和验证脚本：`scripts/`
- 内部 Debug 页面与资源：`entry/src/internalDebug/`（不进入 Release）
- 架构文档：`docs/`

## 命令

环境检查：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check-environment.ps1
```

Rust 格式化、clippy 和测试：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-rust.ps1
```

构建 Rust 原生产物：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all
```

构建 Release HAP（默认）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1
```

构建用于输入框验收页的 Debug HAP：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -BuildMode debug
```

产物分别为 `entry/build/artifacts/entry-release-unsigned.hap` 和
`entry/build/artifacts/entry-debug-unsigned.hap`，不再依赖同名 HAP 判断构建模式。

交付 Release 包前执行内容门禁：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-release-hap.ps1
```

该门禁检查 Release 元数据、正式词库、测试资源缺失状态，以及 ArkTS/Native 产物中不存在回归候选和模型探针调试标识。

构建 Release APP：

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --no-daemon --mode project -p product=release -p buildMode=release assembleApp
```

`default` 产品用于 DevEco 日常运行，固定引用开发签名；`release` 产品引用正式发布签名，
共用 `entry@default` 正式源码，产物目录彼此独立。发布构建会同时保留
`build/outputs/release/HarmonyOS_Input-release-signed.app` 和对应 unsigned 中间产物。
`scripts/build-hap.ps1` 默认构建 `release` 产品，其签名 HAP 位于
`entry/build/release/outputs/default/entry-default-signed.hap`。
本机 `build-profile.json5` 不纳入版本控制；新环境从示例创建配置后，分别为
`default` / `internalDebug` 绑定同一开发签名，为 `release` 绑定正式发布签名。
上传候选只能使用 signed APP；上传前仍必须用签名检查工具复核证书/Profile/包名，确认
Profile 为 `type=release` 且 APP ID 为 `6917611076350696172`，同时确认
`com.corrosion.shuangyuime`、vendor、`0.6.0`/`6000000` 与 AGC 正式应用记录一致，并通过 AGC 软件包基础检测；调试 Profile 即使本地验签通过，也会被 AGC 以错误码 `993` 拒绝。

向开发设备安装当前 signed HAP：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-signed-hap.ps1 -AllConnected
```

如果设备曾安装同包名但不同证书的旧 Debug 包，系统会返回 `9568332 / install sign info inconsistent`。
先使用与旧包匹配的证书覆盖安装，以保留数据。若旧签名材料已丢失，需要导出所需数据后，
再显式执行一次签名重置（会删除该应用的数据）；`bm uninstall -k` 会保留旧签名绑定，无法解决跨证书覆盖问题。
脚本会在重装后恢复原有输入法启用状态和当前输入法选择：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-signed-hap.ps1 -AllConnected -ResetSignature
```

开发设备统一使用 `default` 产品生成的固定开发签名包。正式交付使用 `release` 产品，
不要把正式签名包覆盖到已安装开发签名包的设备上。Build Mode 的 debug/release 控制编译模式，
不决定证书；证书由 Product 选择。需要用正式代码做开发设备验收时执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust -BuildMode release -Product default
powershell -ExecutionPolicy Bypass -File scripts\install-signed-hap.ps1 -AllConnected
```

阶段 3 验证：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage3.ps1
```

阶段 4 验证：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage4.ps1
```

阶段 5 验证：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage5.ps1
```

阶段 6 验证：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage6.ps1
```

阶段 7 验证：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage7.ps1
```

阶段 8 验证：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage8.ps1
```

阶段 9 验证：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage9.ps1
```

阶段 10 本地验证：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage10.ps1
```

阶段 10 在线模拟器/设备验收：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\device-accept-stage10.ps1
```

0.2.0 独立第三方编辑器、应用切换与压力验收：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\device-accept-v0_2_0.ps1 `
  -Target 127.0.0.1:5555 -StressIterations 100 -SoakMinutes 1
```

独立验收客户端源码位于 `tools/ime-acceptance-client/`，包名为
`com.example.shuangyuime.acceptance`，不与输入法应用共享进程或数据目录。

阶段 11 完整本地门禁与模拟器验收：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage11.ps1
powershell -ExecutionPolicy Bypass -File scripts\device-accept-stage11.ps1
```

构建和验证阶段 6 测试词库：

```powershell
cd engine-rust
cargo run -p lexicon-builder -- --input ..\dictionaries\source\stage6_test.tsv --output ..\dictionaries\generated\stage6_test.lex --lexicon-version 1 --strict
cargo run -p lexicon-builder -- --verify ..\dictionaries\generated\stage6_test.lex
```

验证码表顺序和确定性构建：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-lexicon-order.ps1
```

用户词库校验、导入与第二阶段总门禁：

```powershell
cd engine-rust
cargo run -p user-lexicon-tool -- validate tests\fixtures\user-lexicon\valid.txt
cargo run -p user-lexicon-tool -- import tests\fixtures\user-lexicon\valid.txt target\user-lexicon.txt
cd ..
powershell -ExecutionPolicy Bypass -File scripts\verify-lexicon-rules-phase2.ps1
```

带在线模拟器/设备的阶段 5 验证：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage5.ps1 -DeviceValidation
```

## 手动模拟器测试

构建并安装 HAP 后：

1. 在系统输入法设置中启用 `Harmony Shuangpin`。
2. 打开文本字段并显示键盘。
3. 点击 QWERTY 字母插入小写英文文本。
4. 点击 `英`/`中` 在英文和中文模式之间切换。
5. 在中文模式输入阶段 8/9 fixture 中的编码：
   - `n i h c`：候选首选应为 `你好`，按空格提交整词。
   - `u u r u f a`：候选首选应为 `输入法`，按空格提交整词。
   - `x n h e u l p b`：候选首选应为 `小鹤双拼`。
6. 验证部分提交：输入 `u u r u f a` 后点击候选 `输入`，编辑框应先提交 `输入`，候选栏剩余 raw input 应继续转换为 `法`；再按空格提交 `法`。
7. 验证删除回退：输入 `u u r u f a` 后点击 `输入`，剩余 `fa` 时点删除，候选栏应回到 `f` 的前缀状态，并仍能显示 `法` 候选。
8. 使用候选栏上一页/下一页按钮验证分页。
9. 确认键盘不显示“回归”或“模型”调试控件；固定候选回归只在 Rust 测试中运行。
10. 点击删除、空格、回车和隐藏以验证 IME Kit 操作。
11. 阶段 9 手工验证时，重复选择一个非首选候选，隐藏/重开键盘并重启输入法后确认学习结果仍在。
12. 进入密码输入框时确认候选栏不可见且会话学习关闭；当前模拟器会由系统安全键盘接管密码输入。

## 文档

- [文档总索引](docs/README.md)
- [项目交接指南](docs/handover/README.md)
- [架构](docs/ARCHITECTURE.md)
- [编码规则](docs/development/CODING_RULES.md)
- [API 契约](docs/API_CONTRACT.md)
- [构建指南](docs/BUILD_GUIDE.md)
- [测试计划](docs/TEST_PLAN.md)
- [隐私设计](docs/architecture/PRIVACY_DESIGN.md)
- [项目结构](docs/architecture/PROJECT_STRUCTURE.md)
- [词库格式](docs/features/lexicon/LEXICON_FORMAT.md)
- [用户词库格式](docs/features/user-lexicon/USER_LEXICON_FORMAT.md)
- [当前状态](PROJECT_STATE.md)
- [更新日志](CHANGELOG.md)
