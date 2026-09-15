# Project State

更新时间：2026-09-11

## 当前阶段

**0.11.0 复制反查补充 APP RELEASE_APP_BUILT_AND_VERIFIED（2026-09-11）** — 按用户要求保持 0.11.0 / 11000000 / build 1，使用正式 release 产品签名重新构建，包含 ofi 复制反查。双 ABI、clean HAP、APP、签名与独立/内嵌 HAP 门禁通过；功能源码714项ArkTS及相关Rust回归通过。交付 artifacts/0.11.0/ShuangYuIME-0.11.0-11000000-release-signed.app，24,997,853 bytes，SHA-256 3C49E80FC4558AFAF6E3586C8955D776AE83380A1793AEF80106A33F3F8BFCAA。未上传或安装到客户设备，复制反查设备授权/上屏待实测；共享沙箱限制保持。详见 outputs/release-0.11.0-clipboard-reverse/RELEASE_READINESS.md。下方同版本首次构建记录为历史，其旧APP已保留到本次输出目录的 previous/。

**0.11.0 首次构建（历史，未包含复制反查）RELEASE_APP_BUILT_AND_VERIFIED（2026-09-11）** — 已将版本更新为 0.11.0 / 11000000 / build 1，包含下述键盘/双拼及应用内查形修复。双 ABI Native、clean release 产品 HAP、assembleApp、APP/Profile 签名及独立/内嵌 HAP 门禁全部通过；发布证书和 APP 标识与 0.10.0 一致。交付 `artifacts/0.11.0/ShuangYuIME-0.11.0-11000000-release-signed.app`，24,980,564 bytes，SHA-256 `7DCE29688E0CDB3382D278DE0A93B5DBF417DF9C4CB68A3A5E0B247954CD391B`。功能验收沿用刚完成的708项 ArkTS及双端18项网页检查；本轮仅版本/打包，未安装0.11.0到设备或上传AGC。已接受的共享沙箱导入限制保留，详见 `outputs/release-0.11.0/RELEASE_READINESS.md`。以下均为各自日期/包身份的历史记录。

**查形全屏空白修复 PHONE_AND_COMPUTER_WEB_PASS（2026-09-11）** — 用户明确批准应用内查形页及 INTERNET 权限；oix 光标/剪贴板查形与小鹤官网/帮助直通改走非导出的 FlypyWebAbility，绕开手机模拟器系统浏览器的冷启动空白。两端冷启动、重复查询、刷新、换字及宿主文本检查18项通过，截图确认完整网页；最终源码708项 ArkTS 与权限/资源正负向门禁通过。最终开发签名 Release HAP 已安全覆盖安装，双方46项设置保留。包 SHA-256 `441EBBE6C4A21B4BB3D0E35180247623CB32100DD85ABDEDCDDB8F9CFF174A33`，完整证据见 `outputs/browser-fullscreen-fix-20260911/ACCEPTANCE_REPORT.md`。未修改系统浏览器本体，未重打正式客户 APP。下述同日 PARTIAL 记录属于修复前的历史包。

**新反馈手机/电脑模拟器 FUNCTIONAL_CHECKS_PASS / PHONE_BROWSER_RENDERING_PARTIAL（2026-09-11）** — 复核反引号、ojz、oix、浮动候选、次选标签、上档对齐、四码直通、候选数/方案层级及两条双拼例句。实测补修触屏/鼠标控制器缺少启动上下文与异步查形标题不刷新的遗漏；ArkTS 707、Rust 374、工坊10项通过，最终开发签名 Release HAP 已在 Phone/2in1 无重置覆盖安装。UI证据22条通过，3条手机完整网页检查未完成：标签缩略图有正确官网与“你/鹤”结果，但浏览器全屏仍空白；电脑完整网页通过。设置已恢复，真实实体键盘未测，未重打正式客户 APP。完整证据及最终 HAP 哈希见 `outputs/feedback-acceptance-20260911/ACCEPTANCE_REPORT.md`。以下正式发布状态属于历史产物，不能视为包含本次补修。

**0.10.0 客户测试 APP READY_WITH_ACCEPTED_LIMITATION / RELEASE_SIGNATURE_VALIDATED / PHONE_COMPUTER_SMOKE_PASS（2026-09-10）** — 已构建 `0.10.0 / 10000000 / build 1`，显式使用 release 产品及正式发布签名，发布证书与 APP 标识同 0.9.0。新运行 ArkTS 686/686、共享存储契约 8/8、双 ABI Native、clean APP 构建、签名及 signed/内嵌 HAP 门禁通过；同源码开发签名 0.10.0 在手机和电脑模拟器无重置覆盖安装，版本、子页、返回与设置保留通过。所有可达详情/子页已完成统一 UI 的三端验收，业务方法及非 UI 层源码保持，详见 `outputs/settings-details-unification-20260909/ACCEPTANCE_REPORT.md`。用户接受自定义结构/皮肤导入仍待华为共享沙箱授权，限制已写入客户说明；内置项可测。交付 APP 为 `artifacts/0.10.0/ShuangYuIME-0.10.0-10000000-release-signed.app`，24,925,233 bytes，SHA-256 `1733CF6EC718EC9C870E291FA2330632F57ECE9E1222B75FB0D38B995761C326`。未上传 AGC，最终正式 APP 的客户渠道安装、真实宿主及实体键盘仍待测试。完整结论及本次与既有证据的边界见 `outputs/release-0.10.0/RELEASE_READINESS.md`。以下状态按各自日期保留为历史记录。

**虚拟键盘输入法选择键 APP_LIST_FIXED / HOST_RELEASE_VALIDATED / PHONE_SIMULATOR_VALIDATED（2026-09-09）** — `ϟ12` 下方按键不再使用展开默认键盘子类型的 `InputMethodListDialog`，改为系统已启用输入法应用列表，按包名去重并显示系统应用名称，通过 `switchInputMethod` 切换。Phone 模拟器已复现旧列表、验证新列表仅显示“小艺/双羽”，并确认点击小艺后系统当前输入法切换、重新聚焦后显示小艺键盘；当前项/取消/重新打开通过，验收后恢复双羽。ArkTS 645/645、Release 构建和资源门禁 PASS，开发签名设备包与正式 Release 的 ArkTS/native/资源索引哈希一致。百度及真机未测，未重打客户 APP；9 月 8 日交付的 0.9.0 APP 不包含本次修复。证据见 `docs/evidence/2026-09-09-input-method-app-picker/README.md`。

**0.9.0 客户测试 APP HOST_RELEASE_VALIDATED / FINAL_PACKAGE_DEVICE_NOT_RUN（2026-09-08）** — 版本为 `0.9.0`、`versionCode=9000000`。双 ABI Native、clean Release HAP 和 signed APP 构建通过；APP/Profile 签名、版本身份与 signed/内嵌 HAP 内容门禁 PASS。已将本机默认产品签名从开发配置切回已有正式 `release` 配置，最终 Profile 为 `release / app_gallery`，无调试设备白名单，发布证书与 0.8.0 相同。交付 APP 为 `artifacts/0.9.0/ShuangYuIME-0.9.0-9000000-release-signed.app`，24,815,268 bytes，SHA-256 `C2B1F0CF644CEA6591DDC11A85D7142B9E14CAFDB850495968C7C46A0FF36EEA`。包含三/四码逆切分及 9 月 7 日符号/子类型修复；当天功能测试记录为 Rust 654 项、ArkTS 639 项通过，模拟器证据见 `outputs/device-acceptance-20260908/ACCEPTANCE_REPORT.md` 与 `outputs/device-acceptance-20260907/REPAIR_ACCEPTANCE_REPORT.md`。本轮未重新安装最终 0.9.0 包，未新增 QQ、备忘录、头条或真实 USB/蓝牙键盘验收。最低系统为 HarmonyOS 6.1.1（API 24）。完整交付校验见 `outputs/release-0.9.0/delivery-verification.json`。

**音形逆切分模式 IMPLEMENTED / HOST_VALIDATED / DEVICE_NOT_RUN（2026-09-07）** — 按客户确认新增默认关闭的独立切分开关及 `oit` 前两项 `[传统] / [切分]`。仅在四码空码且无有效长码续码时按精确 `2+2` 合成：前组固定首选，后组唯一时联动唯一自动上屏，重码按候选页显示；后组次选的展示与完整上屏文字分离，第五码顶前后首选并保留新码，符号二简、用户排序/删除、退格与分页均覆盖。schema 20 持久化及跨进程同步、方案恢复和保存失败回滚已接通。ArkTS `636/636`、Rust 三个相关 crate `318/318`、最终切分专项、适配器主机测试、fmt/严格 Clippy、双 ABI Native PASS；正式词库四组例句均通过。详见 `docs/features/code-table/REVERSE_SPLIT_MODE.md` 与 `docs/evidence/2026-09-07-reverse-split/README.md`。设备安装、虚拟/实体键盘实测尚未执行。

**0.6.0 小鹤音形四码边界修复 IMPLEMENTED / HOST_VALIDATED / DEVICE_NOT_RUN（2026-09-01）** — 客户再次确认自动上屏、顶屏均以四码和“无有效后续编码”为边界，空码只允许四码清屏或不清屏。运行时已删除会把 `niuo / ladj` 拆成短码提交与尾码重放的空码切分路径；顶屏在普通码表、用户词库、OK 拼字和直通动作上统一检查有效后续；实体键盘浮动窗也会在 `jda` 这类三码空候选状态保留输入码展示。清码直通候选改为“[四码空码清] / [空码不清]”。码表运行时 `83/83`、码表协议 `24/24`、正式小鹤音形 `21/21`、FFI `39/39`、ArkTS 全量测试任务及 Rust fmt/严格 Clippy PASS；设备实机未运行。

**0.6.0 开发设备签名迁移 PARTIAL_DEVICE_VALIDATED（2026-08-31）** — DevEco 错误 `9568332` 已确认不是业务代码或设备类型差异，而是 0.5.1 开发安装使用 Debug 证书、当前 `default` 产物使用固定 Release 证书所致。新增统一安装脚本，默认只尝试安全覆盖，只有显式 `-ResetSignature` 才删除旧签名应用并恢复输入法启用/选中状态；设备实测证明 `bm uninstall -k` 会保留旧签名绑定，不能跨证书迁移。两台在线 x86_64 Phone/Pad 环境已清除旧 0.5.1 沙箱、安装 0.6.0 并再次覆盖 PASS；旧沙箱和受保护目录中的旧 HAP 未能导出，不能从本次迁移记录恢复。第三台设备因 HDC 尚未在设备侧授权而未修改。以后签名迁移前，所需用户数据必须先从应用内导出。

**0.6.0 客户反馈第 1～6 点实体键盘复核 IMPLEMENTED / HOST_VALIDATED / X86_64_SIMULATOR_VALIDATED / REAL_HARDWARE_NOT_RUN（2026-08-31）** — 已确认第 1～6 点全部以实体键盘为验收范围。第 1～3 点经实体分号实时路由、实体字母串行队列及正式码表引导状态共同生效。第 5 点已纠正为两类数据：分类内 `#直` 由 bundle 加载；客户 `5.直通.txt` 则直接生成实体键盘直通动作数据表，编码、候选标题与顺序来自客户行，不再逐编码写死在 Rust。当前 44 行接受 31 行受支持语义、明确隔离 13 行未实现或不安全语义，原始 `$cmd/$ddcmd` 不进入运行时。复核发现第 4 点此前只修复触屏组件身份，并未覆盖实体键盘：PC 宿主的新旧按键 API 若按完整 DOWN/UP 对交错派发，单槽去重会漏掉较早的 DOWN，造成 `o→oo`、`ok→okk`；现按键码与按下/抬起相位保存 80 ms 有界记录并跨通道一次性配对，同通道长按重复保持正常。第 6 点由展示位置显式控制：输入码和候选同处浮动窗时无下划线，嵌入/固定展示位保留下划线；不修改组合、查询或提交数据。ArkTS 全量、转换器 `24/24`、码表运行时 `104/104`、正式音形 `19/19`、fmt/严格 Clippy、双 ABI OHOS Native PASS。signed 0.6.0 HAP 已安全覆盖安装到 x86_64 Phone/2in1 模拟器；2in1 使用系统 `uitest keyEvent` 从 `HARDWARE_READY` 实体按键路由逐项通过 `;q`、唯一候选分号顶屏、`; Space`、`;;`、`o/ok`、分类 `#直` 与 `5.直通.txt` 动作词条，Phone 固定候选栏完成下划线对照。模拟器注入不能替代真实 USB/蓝牙/内置键盘的新旧 API 双通道时序证明，真实硬件仍未运行。详细矩阵见 `docs/features/input-method/PHYSICAL_KEYBOARD_0_6_0_FEEDBACK.md`，证据见 `docs/evidence/2026-08-31-v0.6.0-physical-keyboard/`。

**0.6.0 客户反馈分类直通词条化 IMPLEMENTED / HOST_VALIDATED / DEVICE_NOT_RUN（2026-08-31）** — 分类内 `#直` 保留原词条、完整编码、候选提示、所属分类和 `Direct` 类型，可由外部同词同码 `#删` 隐藏。独立 `5.直通.txt` 不再仅作审计：导入器以整份客户文件为来源生成 `production-direct-actions.json`，增删受支持行后重新导入即可同步候选，不必查找并修改内置编码；当前 44 行转换 31 行、隔离 13 行，转换报告逐行记录编码和原因。运行时只接收离线生成的类型化记录，并继续拒绝原始命令、任意网络目标和未授权动作。

**0.6.0 客户反馈 `o` 起始编码重复修复 IMPLEMENTED / HOST_VALIDATED / DEVICE_NOT_RUN（2026-08-31）** — 已确认正式引擎不会自行补码，异常来自触屏组合刷新把 `rawInput` 纳入 ArkUI 键盘行身份，导致行组件在一次触摸尚未结束时重建并偶发重复派发末键。现已使键盘行身份与组合码无关，并缓存只依赖编辑器、键盘模式、方案与自定义配置的布局；单击 `o` 保持 `rawInput=o`，再按 `k` 保持 `rawInput=ok`，`ocd` 设置菜单等 `o` 前缀直通继续可达。正式音形专项 `19/19`、ArkTS `574/574` PASS；bundle 未改，仍为 `56,184,505` bytes、SHA-256 `EDEDA1CF055CB959B01F26683A7FC850737A061E0E6D12420A043B4C2A670C60`。设备触屏复验未运行。

**0.6.0 客户测试包与安装图标修复 HOST_RELEASE_VALIDATED / DEVICE_NOT_RUN（2026-08-28）** — 应用版本已升级为 `0.6.0`（`versionCode=6000000`），并将 AGC 展示使用的白色环形双羽图标同步写入应用级、Entry/输入法模块和启动窗口资源，修复此前只更新 AGC 展示图而 HAP 继续携带旧图标的问题。首次候选误用了 DevEco 自动生成的调试 Profile，导致 AGC 返回 `993`；现已切回正式发布材料，最终 APP/HAP 内嵌 Profile 均为 `type=release`，包名 `com.corrosion.shuangyuime`、APP ID `6917611076350696172`，无调试设备白名单，有效期至 2029-07-17。双 ABI Native、clean Release HAP、signed APP、Release 资源输入门禁、unsigned/signed/APP 内嵌 HAP 内容门禁及 APP 签名复核均 PASS。unsigned HAP 为 `92,637,226` bytes、SHA-256 `A090FC2D2DFF13B6C1927AEB28366BBC1CF1A9B30738C6B2313B50BA39B23426`；最终 signed HAP 为 `92,800,195` bytes、SHA-256 `17732794B8EE202456029F453E987936AC93738AB049EB7AF381C0368AE8735E`；最终 signed APP 为 `24,741,084` bytes、SHA-256 `DD27260C3068139D5055A491E725F29D1808B20D8AD0178BECAA4AC8B35BB80A`。本轮未执行设备安装与功能回归。

**0.5.1 客户反馈闭环修复 IMPLEMENTED / HOST_RELEASE_VALIDATED / THREE_DEVICE_REGRESSION_PASS / WINDOWS_PREVIEWER_BLOCKED（2026-08-27）** — 已修复 0.5.0 复验中仍未通过或未完全通过的四项：复制命令给宿主保留 500 ms 异步读取窗口、用原生光标移动收起选区，并以内存副本兼容独立宿主的扩展粘贴权限限制；删行改用光标两侧删除并支持失败回滚，回车下滑可按上下文恢复；中文组合码不再交给宿主绘制，统一只在候选区域显示实线下划线；小鹤音形万能键候选不再被精确码 UI 二次过滤。完整 Rust workspace（FFI `39/39`）、发布资源正负门禁、Release 构建与实包审计均 PASS。最新 ArkTS `567` 项测试源码已通过 `UnitTestArkTS` 编译，但 Windows Previewer 在执行前崩溃于 AMD OpenGL 驱动，最近一次完整执行报告仍为新增两项回归前的 `565/565 PASS`，不伪报 `567/567`。应用版本为 `0.5.1`（`versionCode=5001000`）；unsigned/signed HAP 分别为 `71,296,141`/`71,450,631` bytes，SHA-256 分别为 `EA94F3F1776CCC7BE991A506EB672C4473370C0B411D0A4FD70BEAE1957E8A83`、`230536B8189C9BA7F3D7255BD1734D3743A61953FD0CE1828616C68A36E8A840`。2in1 Stage 4、Pad 四条专项和 ARM64 Phone 系统浏览器输入码隔离 smoke 均 PASS；证据见 `docs/evidence/2026-08-27-v0.5.1-customer-feedback/README.md`。

**客户 44 条直通确认 IMPLEMENTED_WITH_ONE_PLATFORM_DECISION_PENDING / HOST_RELEASE_VALIDATED / THREE_DEVICE_SMOKE_PASS（2026-08-25）** — 客户回填结果为 33 条正向选择、6 条“不需要”、5 条未填写。已实现其中 31 条功能项，另按确认保留 1 条 HTTP URL 安全拒绝；未实现项保持隔离。功能覆盖日期/农历/时间、固定 HTTPS 页面、设置与用户词库、删行、简繁/标点/全半角、数字句点、智能句号、空码和四码策略、三组词库预设、二简次选、授权导入及多行诗词。`ofi` 要求“读取复制单字但不粘贴”，但设备确认 normal APL 无法获得 `system_basic` 级 `ohos.permission.READ_PASTEBOARD`；失败入口和权限声明已撤下，等待客户在“显式粘贴/当前输入替代”与“系统级签名条件”之间二次决策。最终 signed Release 为 71,255,985 bytes、SHA-256 `39DA69D38C4BD5F0BCFE9358F8E2487BCFF6DF2A766DAD4581345DDF1749B4E9`；ArkTS 全量、Rust 四核心 crate 全量、双 ABI Native、Release 正负门禁 PASS。Phone、Pad、2in1 均安装同包并以 26 键小鹤音形输入 `orq` 显示两条日期候选，Phone/2in1 点击后上屏 `2026-08-25`；最终包仅声明 `VIBRATE`，不存在剪贴板读取权限。证据见 `docs/evidence/2026-08-25-customer-direct-actions/README.md`。

**可配置直通提示 IMPLEMENTED / HOST_VALIDATED / HAP_BLOCKED_BY_UNRELATED_WORKTREE（2026-08-26）** — 已支持 `上屏内容,候选提示<Tab>完整编码#直`；正式词条 `给予,给ʲⁱ̌予<Tab>gwyu#直` 在输入 `gwy` 时显示 `给ʲⁱ̌予u`，选中或输完 `gwyu` 后只提交 `给予`。`#直` 保留来源分类、随所属分类开关生效并继续跳过万能键。候选协议升级至 interface/ABI 11，以 `displayText` 与 `text` 分离展示和提交。正式 bundle 接受 162,731 条、拒绝/隔离 390 条，大小 56,184,164 bytes，SHA-256 `F7BBFDF4473E9317D618C9AD02A792B47FF2DAB8BFD74FA23416579E01F9BDC7`，安装缓存升级到 v5。源审计、构建/复验、基线、Rust 全目标检查与相关回归、ArkTS 526/526、双 ABI Native 均 PASS；Release HAP 被当前工作区内无关的键盘自定义/设置模型 ArkTS 错误阻断，真机未运行。

**客户回传小鹤音形词库 IMPORTED / HOST_RELEASE_VALIDATED / DEVICE_NOT_RUN（2026-08-24）** — 已清理并导入 `双羽词库分类/双羽词库/` 的 162,759 条客户记录，原件保持不变，规范化结果写入 `双羽词库分类/清理后/`；导入器严格校验 UTF-8、Tab、编码和重复项，并通过重复导入逐文件 SHA-256 不变的幂等检查。客户未提交表外段，按“未提交不等于删除”保留项目既有 362 条表外字；`5.直通.txt` 的 44 条命令或 URL 已合并为 `#直` 审计输入，但继续按正式安全策略隔离，未变成可执行候选，项目既有批准直通动作保持不变。正式 bundle 仍为 12 个内部分类，接受 162,730 条、拒绝/隔离 391 条：首选 68,568、分类 1,690、快符 16、一简 26、二简 66、表外 362、全码词 464、符号 623、符号组 707、生僻字 498、全码字 1,654、ok 拼字 88,020，另含 36 条全码词 `#固` 规则。bundle 为 56,183,822 bytes、SHA-256 `0963f9c28b750c375dbe693feaa2b1c9334ecd9c2c58df2e367138b22b82c942`，安装缓存升级到 v4。源审计、正式构建/复验、候选基线、完整 Rust workspace、fmt、严格 Clippy、ArkTS 502/502、双 ABI OHOS Release Native、Release 正负资源门禁、default Release HAP 与实包内容门禁均 PASS；unsigned HAP 为 71,008,252 bytes、SHA-256 `0C1753EB17569F8478B50CE2475D709BA868756CF0575719DDF53C23B49BEA03`。真机安装与输入验收未运行。

**AI 输入法第 1 阶段 CORE_IMPLEMENTED / PRODUCTION_COMPLETION_BLOCKED / HOST_RELEASE_VALIDATED / DEVICE_NOT_RUN / CLOUD_NOT_CONFIGURED（2026-08-24）** — 已复用 AI-0 架构完成默认关闭、纯本地且确定性的上屏后关联词，以及续写、精简、礼貌、正式、翻译五个显式云动作。关联词复用 Rust context-reranker，会话内有界排序且最多 3 条；云 Provider 只接受配置注入的自有 HTTPS 代理，具备闭合载荷、8 秒硬超时、取消、响应字节/JSON/协议/requestId/Provider/候选严格校验。新输入、光标或原文变化、隐藏、停止、换框、乱序、迟到和旧 generation 都不能更新 UI 或编辑器；接受建议前再次核对原文，成功后复用安全撤销。模型输出含 `$cmd`、URL 或 HTML 时仍只作为普通文本。本轮补充了 Node.js 22 自有代理参考实现、EdDSA 最长 300 秒鉴权、客户端仅内存令牌和撤回失效边界、OpenAPI/容器/部署模板、隐私同意草案及宿主证据门禁。

仓库仍未提供已批准的生产代理域名、真实令牌签发/吊销、最终协议与配额、留存/不训练约定、供应商适配和最终隐私文案，故正式运行时保持 Cloud Provider 不可用，AI/云/关联开关默认关闭，未加入 INTERNET 或凭证，真实云为 `NOT_RUN`。ArkTS `506/506`（AI-1 `19/19`）、代理协议 `9/9`、context-reranker `9/9`、关联词引擎专项 `9/9`、AI-1 FFI 定向测试、fmt、workspace 严格 Clippy、Release 负向门禁 `13/13`、default Release 构建和实包审计均 PASS。Rust workspace 全量测试仍被当前工作区既有小鹤生成 bundle 与冻结候选快照不一致阻塞，未改写冻结基线。unsigned HAP 为 71,008,252 bytes、SHA-256 `FF34FFB08E66CBDDC81BAF46D4B3AFFD2DA5EE6CD4D5D27B032C81CD35184921`；Phone/Pad/2in1 和第三方宿主未运行。AI-1 明确未达到生产完成，详见 `docs/features/ai/AI1_FIRST_INPUT.md`。

**AI 输入法第 0 阶段 IMPLEMENTED / HOST_RELEASE_VALIDATED / DEVICE_NOT_RUN（2026-08-21）** — 已完成 AI/语音可替换协议、集中能力门控、稳定 request/session ID 与 generation 生命周期、确定性 Fake AI/Fake Speech、候选栏最小交互、设置 schema 9 和隐私骨架。AI 只处理最近一次仍可核对的 IME 上屏文本，接受建议时重新核对原文并原子替换，失败不先删除，成功可反向撤销；模型输出即使包含 `$cmd` 或 URL 也只作为普通文本。语音只验证准备/聆听/中间/最终/确认/取消/错误状态，不录音且必须明确确认上屏。两个总开关、云能力和自动上屏默认关闭；密码、未知及非普通文本编辑器失败关闭。正式包未增加网络或麦克风权限，Release 门禁现同时拒绝 `ohos.permission.INTERNET` 与 `ohos.permission.MICROPHONE`。ArkTS 全量测试、default Release HAP、实际 HAP 内容门禁及正负资源门禁 PASS；unsigned HAP 为 40,764,250 bytes、SHA-256 `0642944603309F84A71FFBF50BE6B7A539AFCD648A201E8EF1050C0C323402AB`。真实模型、云服务、真实语音、Phone/Pad/2in1 设备与第三方宿主验收均未运行。详见 `docs/features/ai/AI0_FOUNDATION.md`。

**小鹤音形分类置顶/直通语义 IMPLEMENTED / HOST_RELEASE_VALIDATED / PRODUCTION_DIRECT_DATA_PENDING / DEVICE_NOT_RUN（2026-08-21）** — 正式分类仍为 11 个，快符继续只走分号引导。全码词 `#固` 包内规则已改为随 `full-code-word` 开关启用/隐藏，外部用户词库保持独立；转换器新增全码词专用 `#直`，使词条可按编码输入但不进入反引号万能键反查，其他分类使用该标记会被拒绝。客户现有权威全码词源尚无 `#直` 标记，未猜测具体条目；直通动作源中的 `$cmd/$ddcmd`、网络和平台动作继续隔离。转换器 23、码表运行时 95、输入引擎 158，共 276 项 Rust 测试、严格 Clippy 及 ArkTS 466/466 通过；正式 bundle 重建/校验仍为 11 分类、26,039,684 bytes、SHA-256 `cda61bc4011ab03100b52327325a4c908c3af1eddfe3daf3d2b871f840b15e94`。x86_64/arm64-v8a Native Release、default Release HAP 和内容门禁 PASS；unsigned HAP 为 40,671,548 bytes、SHA-256 `d1cb5173a27b90fb9c4b03ad9b0d916755ada0947321fa4ccff9a6ba403d4111`。设备验收未运行。

**小鹤音形四类默认关闭 IMPLEMENTED / HOST_BUILD_VALIDATED / DEVICE_NOT_RUN（2026-08-21 复验）** — 因完整直通语法尚未支持，二简次选、全码词、生僻字、全码字现在默认关闭，需要时可从设置页手动开启。新装、重置、旧版全开快照迁移和 Rust bundle manifest 已统一；非全开自定义分类组合不会被升级覆盖。正式 bundle 为 26,039,684 bytes、SHA-256 `cda61bc4011ab03100b52327325a4c908c3af1eddfe3daf3d2b871f840b15e94`。正式包重建/校验、基线生成、Rust runtime/engine/FFI/converter、双 ABI OHOS Release Native 和 default Release HAP 均通过；此前 Windows Hypium 宿主执行器挂起本次未复现，ArkTS 466/466 PASS；设备验收未运行。

**智能句号 IMPLEMENTED / HOST_VALIDATED / DEVICE_NOT_RUN（2026-08-20）** — 中文句号在 300/500/800/1000 毫秒可配置时间窗内连续输入时，安全替换为单个 ASCII `.`；超时保留两个中文句号，也可关闭。虚拟键盘和实体键盘均接入，替换前核对光标前文本，按键时间以入队到达时刻为准。设置 schema 为 8，ArkTS 全量单测与工程编译通过；真实 USB/蓝牙键盘及多宿主编辑器设备验收未运行。

**小鹤音形空码后续提示固定单项 IMPLEMENTED / HOST_VALIDATED / DEVICE_NOT_RUN（2026-08-20）** — 客户确认空码时只显示源序第 1 项后续提示，不再需要 9 项或数量设置。Rust 查询和 ArkTS 所有候选表面同时固定为 1，并退出旧数量字段、持久化键和设置页控件；精确同码重码仍完整保留。Rust 状态机 81/81、正式词库 `un` 首项专项、ArkTS 454/454 及工程编译通过；设备验收未运行。本条结论替代 2026-08-05 阶段 6 中“1～9 项可设置”的产品结论；该阶段的 9 项验收记录仍作为历史证据保留。

**小鹤音形冷启动与内存优化 IMPLEMENTED / HOST_RELEASE_VALIDATED / ARM64_BUILD_PASS / ARM64_DEVICE_NOT_RUN（2026-08-19）** — `.hsyx` 生产加载已改为只读 mmap、流式 SHA/content hash、查询专用 compact metadata 和按文件身份共享的弱缓存不可变索引；ArkTS 安装器增加绑定 SHA/inode/size/mtime/ctime 的原子校验回执，后续冷启动不再重复哈希已安装的 26 MB 文件，Native 边界仍校验冻结完整 SHA。Windows x86_64 Release 5 进程加载 P50 `633.962 → 163.511 ms`，同进程复用 P50 `636.181 → 0.258 ms`，load 内存增量 P50 `59.20 → 15.59 MB`，峰值工作集 `147.39 → 46.47 MB`。相关 Rust、严格 Clippy、ArkTS 与 ARM64 OHOS Release 构建 PASS；当前只连接三台 x86_64 emulator，真实 ARM64 加载/RSS 为 `NOT_RUN`，已提供拒绝 emulator 的采集脚本。详见 `docs/evidence/2026-08-19-yinxing-cold-start-memory/README.md`。

**9 键拼音热路径第二轮优化 IMPLEMENTED / HOST_RELEASE_VALIDATED / DEVICE_NOT_RUN（2026-08-24）** — `SentenceDecoder` 的搜索限制现在随每次方案切换同步，9 键计算量不再取决于引擎最初从小鹤、全拼还是 9 键创建；联合搜索态改为父节点/边索引回溯，不再在每次扩展复制整条 `WordEdge` 数组，beam 排序也不再在比较器中临时克隆完整路径。最多 32 条兼容拼音路径的句子解码增加 128 项 LRU，仅复用拼音路径和完成状态均未变化的结果；候选提交、用户模型变更、重置和方案切换都会失效缓存。

同一 Windows x86_64 主机、正式 `production.lex`、冻结 dev 155 条三轮即时 A/B 中，每键 P50/P95/P99 从 `17.859/92.176/132.113 ms` 降至 `5.258/16.078/23.717 ms`，平均值从 `27.943 ms` 降至 `6.004 ms`；三轮完整候选 SHA-256 均保持 `6b68e9b8bcb89a64ca81f4f5bb5f2c5aa0284f24650f12ed367061106cd8fae7`。public-regression 900 条三轮为 `5.041/16.164/22.744 ms`，候选 SHA-256 保持冻结值 `10de0fcd5c092f31f7e3c89605699954bf983c78102e16a4d64244d52ed0bda6`，Top1/Top3/Top5 仍为 `34.889%/43.889%/46.333%`。Rust workspace 全目标、T9 专项、增量/全量等价、缓存失效、方案切换限制和严格 Clippy 均 PASS；未重跑 blind，ARM64 真机、真实宿主、设备 P95/P99、RSS 和 soak 仍为 `NOT_RUN`。详见 `docs/features/pinyin/PINYIN9_RUNTIME_PERFORMANCE_20260824.md`。

**9 键候选召回、排序与延迟优化 IMPLEMENTED / HOST_RELEASE_VALIDATED / DEVICE_NOT_RUN（2026-08-19）** — T9 数字词典索引改为优先保留不同拼音读法，联合排序加入单字母音节、过多音节和过多词边的专用歧义代价；完整词直达、32 路 Top-4 兼容候选和联合句子按显式层级合并，替代旧 400 万分兼容偏置及 `32 × 16` 候选扇出。联合 beam 仍为每位置 16 状态，不靠无界扩张换质量。

正式 `production.lex` Release 三轮结果：public-regression 900 条 Top1/Top3/Top5 `14.667%/17.556%/18.556% → 34.333%/42.667%/45.222%`，未召回 `39.889% → 34.667%`，每键 P50/P95/P99 `41.759/237.583/345.435 → 14.418/71.588/109.433 ms`；dev 155 条 Top1 `9.032% → 15.484%`、未召回 `81.290% → 72.258%`、P95 `247.365 → 65.560 ms`。两组各三轮候选 SHA-256 一致，自动上屏、ASCII 泄漏、状态丢失、引擎错误均为 0。fmt、严格 Clippy、Rust workspace、T9 `10/10`、FFI `36/36` PASS。本轮未运行 blind 或设备验收；ARM64、真实应用、设备性能/RSS/soak 仍为 `NOT_RUN`。详见 `docs/features/pinyin/PINYIN9_OPTIMIZATION_20260819.md`。

**26 键全拼候选质量 V3 IMPLEMENTED / HOST_VALIDATED / REAL_ANONYMOUS_DATA_NOT_PROVIDED / DEVICE_NOT_RUN（2026-08-18）** — 正式随包词库已从 V2 `default` 提升为已审计 `all_domains` profile，基础、有效热词和六类专业领域共 131 个新增文本/读音对全部进入产品；当前 `production.lex` 为 3,751,923 bytes、SHA-256 `e4dead906109136470691d0e463c2ada34c8e5bb9b3fc62bb2de552ed751d365`，安装缓存升至 `production-v118.lex`。新增只读长词紧凑全拼索引，仅保护 ≥5 音节的既有正式词条、每次最多 8 项，修复“词库已存在但被 4 路解析/16 项 decoder beam 截掉”的召回缺口；`粤港澳大湾区`、`逆周期调节`、`检索增强生成` 专项 PASS，不合成词库外文本，不改变 rawInput/消费长度/自动上屏。

独立 V2 dev 48 条 Top1/Top3/Top5 从 `95.833%/95.833%/95.833%` 提升为 `97.917%/97.917%/97.917%`：未召回 1、召回但 Top5 外 0、Top5 内排序错误 0；唯一未召回的冻结 `nizhouqidiaojie` 把规范 `tiao` 写为 `diao`，未修改数据。旧公开 dev 300 条当前为 Top1/Top3/Top5 `62.000%/66.000%/67.000%`，互斥失败为未召回 94（31.333%）、Top5 外 5（1.667%）、排序错误 15（5.000%）。用户学习隔离探针对 20 个已召回非首选目标选择 3 次：17 个提升、16 个升 Top1、3 个不变、0 个退化。三轮候选确定，自动上屏/ASCII 泄漏/状态丢失/引擎错误均为 0。

评测器新增总体和各分组 `failureBreakdown`、同名 failure JSONL、1～5 次隔离学习探针，以及只接受五个长度桶的自愿本地匿名聚合入口。匿名 schema 禁止原始输入、候选/编辑器文字、应用/用户标识，拒绝未知字段，总事件 ≥100、非空桶 ≥20，并报告真实事件覆盖率和未覆盖桶；仓库当前没有真实匿名文件，示例只用于格式 smoke，未伪造真实分布结论。candidate baseline 24/24、candidate query 16/16、ime-engine 153/153、Clippy、ArkTS、V2 构建/篡改/资源门禁、双 ABI OHOS Release 原生库和 Release HAP 实包门禁 PASS；unsigned HAP 为 40,502,445 bytes、SHA-256 `1FEA7059263B8ADE7201BA74634E967FCCCAA6FA9465F87A7A10508D1C1429A1`。全量 ime-ffi 仍有一项与本轮无关的既有九宫格旧组合顺序断言失败；全新 blind、真机和 HAP 真机安装仍为 `NOT_RUN`。详见 `docs/features/pinyin/QUANPIN_QUALITY_IMPROVEMENT_V3.md`。

**26 键全拼纠错延迟第一轮治理 HOST_VALIDATED / DEVICE_NOT_RUN（2026-08-18）** — 纠错热路径已改为进程级共享只读音节 Trie，拼写变体按原确定顺序流式校验并在上限处立即停止；新增 32 项解析扩展 LRU，保留不可变词典查询缓存跨 composition 复用。只有无高置信完整候选时才启动纠错；已有候选且尾部仍是单字母合法音节前缀时延后到后续按键。句子解码按错误类型分配 `4/2/2/2` 的公平预算，全部未延后的纠错路径仍先执行精确词典查询。纠错单开口径下，候选扩张均值 `33.89 → 9.23`，纠错查询路径均值 `21.44 → 8.77`，句子解码均值/最大 `10.61/16 → 2.96/10`。

正式 `production.lex`、冻结 dev 300 条、纠错单开的 Release 三轮复测中，P50/P95/P99 `16.658/160.287/297.569 → 5.834/145.121/286.198 ms`，平均值 `41.443 → 31.116 ms`。单次最大值受新结果第一轮 `573.863 ms` 异常点影响，不宣称长尾已解决。纠错单开 Top1 保持 `62.000%`，Top3 `65.333% → 66.000%`，Top5 `69.333% → 69.667%`，typo Top5 保持 `44.444%`，三轮候选 SHA-256 均为 `c444b72c95fd6d7fc17452c947fdd60ac26577b804c63de37650b4e0f9958688`，自动上屏、ASCII 泄漏、状态丢失、引擎错误均为 0。纠错+模糊音组合模式 Top1/Top3/Top5 为 `62.000%/66.000%/72.667%`，typo/fuzzy Top5 为 `44.444%/91.667%`。未重新运行 blind；原冻结 blind 结论不外推到本性能修订。

Rust → C++ → ArkTS 路径确认正式候选页只序列化 7 项，不是 Rust 长尾主因；C++ 转换器已按页内对象数预留 vector 并移动字符串字段，不改 ABI。`TextPreviewManager.commitReplacement` 的固定 80 ms 等待已改为光标状态立即确认、8 ms 短轮询兜底、80 ms 最长窗口；正常编辑器不再固定付出等待，HarmonyOS 6.1 延迟释放场景仍不重试写入并保留原安全上限。Rust 全拼专项、严格 Clippy、Native CMake 与 ArkTS 全量单测 PASS；设备性能、真实应用、低内存和长时输入仍为 `NOT_RUN`。证据见 `artifacts/quanpin-evaluation/optimized-final-dev-*-results.json`，详见 `docs/features/pinyin/QUANPIN_SPELLING_CORRECTION_AND_FUZZY.md`。

**26 键全拼有界纠错与模糊音 IMPLEMENTED / FROZEN_BLIND_VALIDATED / DEVICE_NOT_RUN（2026-08-14）** — 正式链路已支持编辑距离 1 的漏字、多字、固定对称 QWERTY 邻键和相邻错序，以及默认全关、可独立配置的 `n/l`、`z/zh`、`c/ch`、`s/sh`、`in/ing`、`en/eng`、`an/ang`、`ian/iang`。Rust → C ABI → N-API → ArkTS → 设置持久化/迁移/回滚完整接通；interface/ABI 升至 `9`，settings schema 为 `7`，engine version 为 `0.0.1-quanpin-features`。默认全关候选指纹与改进前完全一致。

冻结 1070 条集上，Top1/Top3 保持 `56.168%/62.150%`，Top5 `63.551% → 68.224%`，MRR `0.593924 → 0.607086`；typo Top5 `0% → 28.333%`，fuzzy Top5 `7.5% → 87.5%`，clean Top5 `69.794% → 69.897%`。实现清单冻结后唯一一次 blind 三轮为 Top1/Top3/Top5 `53.896%/60.909%/66.623%`、MRR `0.588036`，三轮完整候选指纹相同，安全计数全 0；49 个冻结实现文件运行后复算无差异。实现清单 SHA-256 为 `6f9f297b650f094c35d57c141e076dea522a1937495cb395b2f9362b499f7af4`。

fmt、严格 Clippy、本任务 Rust/FFI、ArkTS、双 ABI OHOS Release 库、Native CMake 和默认产品 debug HAP 均 PASS。此前 `yinxing-converter` 分类顺序测试仍断言 8 类时代索引 7 的漂移已修复：现按正式合同完整断言 11 类顺序，`full-code-character` 位于索引 10。纠错开启的 dev P50/P95/P99 为 `16.631/162.414/295.771 ms`，明显高于基线，设备性能、低内存、进程重建和真实应用矩阵为 `NOT_RUN`，不宣称成熟商业输入法水平。详见 `docs/features/pinyin/QUANPIN_SPELLING_CORRECTION_AND_FUZZY.md`。

**26 键全拼候选质量冻结基线 ESTABLISHED / HOST_MEASURED / DEVICE_NOT_RUN（2026-08-13）** — 已建立 1,070 条项目独立编写、300 dev/770 blind 的全拼质量集，并在首次运行正式引擎前以文件清单、字节数、SHA-256 和冻结时间固化；基线身份 `f68c3006ee1c714eb9f1c543439785fd1164e61b6ef21a4d8da851d2b1e2ba22`。Release 正式 `ImeEngine`/`production.lex` 三轮完整输出确定：Top1/Top3/Top5 `56.168%/62.150%/63.551%`，MRR `0.593924`，目标未召回 `34.486%`；typo Top5 `0%`，fuzzy Top5 `7.5%`，未修改候选语义或生产数据。53,316 键主机 P50/P95/P99 `2.195/63.565/101.811 ms`，自动上屏、ASCII 泄漏、状态丢失、引擎错误均为 0。设备质量/性能仍为 `NOT_RUN`；详见 `docs/features/pinyin/QUANPIN_QUALITY_BASELINE.md`。

**客户六项直通编码 IMPLEMENTED / HOST_VALIDATION_COMPLETED / DEVICE_VALIDATION_NOT_RUN（2026-08-13）** — 正式小鹤音形已支持 `;f` 重复、`;i` 带内容核对的 5 秒安全撤销、六组成对符号居中、`;n` 当前行末定位、分类词库完整集合原子切换，以及经系统授权的固定来源用户词库 MERGE/APPEND/REPLACE。命令字符串不进入执行层，只允许 Rust 内建白名单动作；interface/ABI 为 `8`，engine version 为 `0.0.1-direct-actions`。Rust workspace、Clippy、ArkTS、双 ABI Native Release、Release HAP 与内容门禁 PASS；设备专项未运行。详见 `docs/features/direct-control/DIRECT_ENCODING_SIX_REQUIREMENTS.md`。

**26 键全拼和 9 键拼音阶段 5 IMPLEMENTED / HOST_VALIDATION_COMPLETED / DEVICE_VALIDATION_PARTIAL（2026-08-13，不标记 COMPLETED）** — 四正式档案联合切换、schema 5 配置迁移、失败回滚、生命周期清理、用户数据隔离、Rust/C++/ArkTS 门禁、双 ABI Native、Release HAP 和实包内容门禁已收口。修复了同 engine scheme 的 profile 布局切换不清组合，以及全拼单字母 `n` 被独立读音截断前缀召回的问题。Rust workspace `505/505`（含 candidate baseline `4/4`、T9 `6/6`、FFI `31/31`），ArkTS `440/440` PASS。

signed Release 已在 x86_64 Phone 竖屏和 Pad 横屏的独立包名验收客户端验证：全拼 `nihao → 你好`、T9 `64426 → ni'hao/你好`，Pad 同时验证 `xiaohe-17/xiaohe-26` 切换与双拼 `nihc → 你好`；Phone 验证 T9 `64 → ni` 后隐藏/恢复无残留和 URL 策略隔离。ARM64 真机、真实浏览器/聊天应用、同机旋转/分屏、完整数字/电话设备矩阵、设备性能/RSS/soak 为 `NOT_RUN`。全拼主机完整引擎 P50/P95 `5.144/58.495 ms/键`，相对历史质量修订前基线存在明显回退，已如实列为待审查；T9 `64426` 候选刷新 P50/P95 `0.273/0.460 ms`。候选冻结基线当前通过，但 `.git` 目录为空，无法审计本轮开始前已有的 2026-08-13 基线更新来源。完整结论见 `docs/features/pinyin/PINYIN_STAGE5_FINAL_ACCEPTANCE.md`。

**9 键拼音阶段 4 IMPLEMENTED / HOST_VALIDATION_PARTIAL（2026-08-12，不标记 COMPLETED）** — `pinyin-9` 档案已正式启用，中文软键盘接入四排 3 列九宫格和共享底栏：`2～9` 使用专用 `T9_PINYIN_DIGIT` 动作，经过既有串行输入链和 Native `processKey` 进入 Rust；`1` 进入既有符号模式，`0` 调用显式分音，`符/123` 进入真实数字键盘。当前拼音直接显示 Rust `currentPinyin`，独立横向组合栏严格保持 `pinyinCombinations` 发布顺序并通过 `selectPinyinCombination` 刷新 Rust 真实状态；英文继续使用 QWERTY。删除、空格、动态动作键、输入框策略、主题、反馈、无障碍和生命周期均复用现有正式链。

ArkTS 全量 `434/434`、T9/parser/engine/FFI 定向回归（含 T9 `6/6`、FFI `31/31`）、Release HAP 和 Release 内容门禁 PASS。unsigned Release HAP 为 `38,739,216` bytes、SHA-256 `AB4B9B6B9BB5DB573A9F1FA3D80F29F95D9EAF75D849AE55F0976DEF3C529863`。本阶段没有修改 C++、Rust、Node-API 或 C ABI，interface/ABI 保持 `7`。Rust 全 workspace 仍被既有小鹤冻结候选基线不一致阻塞；模拟器、ARM64 真机、Phone/Pad 旋转/分屏、三方应用和长时压力均为 `NOT_RUN`。仓库仍缺少可用 Git 元数据。完整记录见 `docs/features/pinyin/PINYIN_STAGE4_KEYBOARD_UI.md`。

**9 键拼音阶段 3 IMPLEMENTED / HOST_VALIDATION_PARTIAL（2026-08-12，不标记 COMPLETED）** — Rust 已实现标准 T9 数字音节 Trie 和有界动态规划：运行时不做 `3^n`/`4^n` 字母展开或全音节扫描，支持最多 64 位数字、未完成音节、显式分音、多路径稳定展示/选择、删除/重置/方案恢复。`64` 专项包含 `ni` 与“你”，`64426` 包含 `ni'hao` 与“你好”。候选查询、整句解码、分页、部分提交、提交和用户学习复用现有正式链；学习以 `pinyin-9` 命名空间隔离。interface/ABI 已同步为 `7`，engine version 为 `0.0.1-pinyin-stage3`，新增 `selectPinyinCombination` 的 ArkTS → C++ → Rust 透传接口。该段保留阶段 3 交付时的历史边界；九宫格与档案启用状态以上方阶段 4 为准。

T9 parser/engine/FFI 专项、学习隔离、fmt/Clippy、ArkTS 全量测试、双 ABI Native、unsigned Release HAP、资源负门禁及 HAP 内容门禁均 PASS。Release `64426` 候选刷新 P50/P95 为 `0.282/0.535 ms`；64 个连续 `6` 的逐键完整输入 P50/P95 为 `411.041/444.066 ms`，约 `6.42/6.94 ms/键` 摊销，状态数和缓存均受硬上限约束。x86_64/arm64-v8a 静态库分别为 `26,839,064`/`27,338,314` bytes，SHA-256 `AD87B4A1B9DD4E2841D5BFD8927AD02FFC3F0580247156D8F17BC59A6674D561` / `4478CAB42751796E1C81EFD247E8C8450B298EA3F809740165ECB82A98D08302`；unsigned Release HAP 为 `38,719,780` bytes，SHA-256 `BE630BCBAB7234B936933E93ACF12C1C754B1D30AEAE71F920C86E3785C70CCA`。

全 Rust workspace 仍有 1 项独立阻塞：冻结的 `sentence-baseline.json` 与当前 `production.lex` 在既有小鹤 `nihc`/`uurufa` 候选排序上不一致；本阶段未改写冻结基线。仓库缺少可用 Git 元数据，无法从提交历史归因，因此阶段状态保持部分验证。Phone/Tablet/2in1、ARM64 真机、真实键盘、三方应用、旋转/分屏和长时压力均为 `NOT_RUN`。完整记录见 `docs/features/pinyin/PINYIN_STAGE3_T9_ENGINE.md`，决策见 ADR 0025。

**全拼候选与桌面浮窗质量修复 COMPLETED（主机自动化、signed Release 与 x86_64 2in1 范围，2026-08-11）** — 全拼部分选词现在会在提交前缀后清空旧候选快照，并只针对剩余 raw input 重查；桌面默认每页 7 项，浮窗按 7 项完整内容估宽并只受屏幕安全区限制。浮窗根容器左右留白由 12vp 收紧到 6vp；宽度估算区分窄数字前缀、ASCII 字母和占满 em 的中文字符，使短候选页保持紧凑、长候选页按实际中文长度扩展，不再裁切第 7 项。兼容预编辑在光标已到自有范围末端而文本查询短暂滞后时继续保持所有权，避免浏览器搜索框偶发遗留英文前缀。新增 `nishizgyisi` 部分提交、`sousuohuoshuru → 搜索或输入` 和宿主读延迟回归。engine version 为 `0.0.1-pinyin-stage2-quality4`。

Rust `ime-engine` 全套 109 项、`ime-ffi` 30 项、fmt/Clippy、ArkTS 全量测试、双 ABI Native Release、unsigned/signed Release HAP 和内容门禁均 PASS。最终 signed HAP 为 38,600,568 bytes、SHA-256 `722B932A7A0D3165C3CAC70572198F871490D87B5E63307D3A96D6BC6EB8E61F`。HarmonyOS 6.1 / API 24 / x86_64 2in1 已安装 signed Release，完成独立 ArkUI 宿主与系统浏览器候选、鼠标/数字提交、Esc、焦点、窗口移动缩放、应用切换闭环；部分提交专项确认旧候选消失且剩余编码重查，浏览器 450 ms 逐键间隔仍生成覆盖整段输入的中文候选。自适应浮窗专项中，短页 `jint` 为 969px、左右留白各 27px；长页 `jintianshige` 自动扩展为 1341px、左右留白 27/28px，第 7 项完整宽度 174px，7 项均在窗口内。Phone/Tablet 与 ARM64 本轮专项未重跑。

**26 键全拼阶段 2 性能修复 COMPLETED / QUANPIN_FAST_PHYSICAL_INPUT（主机自动化与 Release 构建范围，2026-08-10）** — 已修复实体键盘快速输入时的两级放大：Rust 不再对长组合逐键解码最多 32 条切分路径，12 字母内最多解码 4 条、长组合只解码首选路径；ArkTS 在编辑器支持时为 `quanpin` 使用原生 TextPreview，不支持时只增量追加新字母。完整且有正式中文候选的组合达到 24 字母后会安全自动提交并重放触发键，fallback 不允许自动收口；无法安全收口时 64 字母硬门禁保留原组合。

Release 完整引擎基线从 `82.359 ms/键` 降至 `2.027 ms/键`（约 40.6 倍），46 字母长输入从 `122.714 ms/键` 降至 `2.002 ms/键`（约 61.3 倍）；1,620 键为 0 失败、20 次中文自动收口、0 次 ASCII 自动提交。interface/ABI 保持 `6`，engine version 为 `0.0.1-pinyin-stage2-perf1`。Rust/ArkTS/FFI、双 ABI Native、Release HAP 与内容门禁 PASS；新 HAP 为 38,261,216 bytes/SHA-256 `98DFB338B502055FBE87D69F165F73B5BD4E07B7A83F6E5FD5EF5A6CD5AC343F`。实体键盘设备复测为 `NOT_RUN`。

**26 键全拼和 9 键计划阶段 2 COMPLETED / QUANPIN_26_COMPLETE_PATH（主机自动化与 Release 构建范围，2026-08-10）** — `quanpin-26` 已正式启用并复用 QWERTY 中文布局。Rust `QuanpinParser` 基于合法音节 Trie 和最多 32 路的有界动态规划解析连续全拼，支持末尾未完成音节、`'` 显式分音、`xian/xi'an` 多路径和逐键退格恢复。精确/前缀查询、整句解码、分页、候选提交、部分提交和用户学习继续复用正式链路；全拼候选按实际字母数计算部分提交消费长度。

设置页与空闲工具栏现统一按 `KeyboardProfile` 切换并显示“26 键全拼”，Native 成功后才持久化；`pinyin-9` 仍登记且禁用。自动学习以 `quanpin` 隔离，人工全拼词库使用 `qp` 前缀命名空间，不解释旧双拼规则。阶段 2 初始 engine version 为 `0.0.1-pinyin-stage2`，当前性能修订见上方状态块。

Rust workspace 全量测试（含全拼专项、`ime-engine 42/42`、`ime-ffi 29/29`）、fmt/Clippy、ArkTS 全量测试、x86_64/arm64-v8a Native Release、unsigned Release HAP 和内容门禁均 PASS。HAP 为 38,256,044 bytes/SHA-256 `CD9D5003E91C5426FA56FF11E53F5C9917C7AB499A7CC5946CCE56C1E37AEAD0`；性能基线为 160,000 次解析/13,858 ms，平均 86.616 µs。模拟器与 ARM64 真机专项为 `NOT_RUN`。阶段记录见 `docs/features/pinyin/PINYIN_STAGE2_QUANPIN_26.md`；阶段 1 公共协议记录保留于 `docs/features/pinyin/PINYIN_STAGE1_KEYBOARD_PROFILE_AND_PROTOCOL.md`。

**阶段 12 COMPLETED / DIRECT_CONTROL_AND_USER_LEXICON_MANAGEMENT（三设备闭环，2026-08-10）** — 正式产品已加入统一直通控制：命令行 Want 支持方案切换、八类词库启用/禁用/切换、全部/仅核心预设和状态查询；实体键盘提供严格 `Ctrl+Alt+0～9` 高频预设。所有入口统一复用设置持久化、资源校验、规范化和跨进程同步，音形引擎未运行时也可预配置分类。

正式设置页已加入八类词库开关和用户词库管理页。用户可添加普通词、精确隐藏系统词、固顶或指定第 N 位，并搜索多选、批量改动作/移除、合并或覆盖导入及导出。Rust 负责完整解析、稳定 revision、CAS 冲突检测和原子保存；主进程把任意批量文本分块发布到 `SHARED_CONFIG`，输入法进程在热更新和冷启动时镜像到自己的沙箱文件后原子重载，失败保留最后一个有效不可变快照。输入法系统事件在 onCreate 中立即注册，并在异步镜像完成后按到达顺序执行，首个 `inputStart` 不会丢失。interface/ABI 为 `5`，engine version 为 `0.0.1-stage12`。

已通过 user-lexicon `23/23`、ime-engine lib `42/42`、ime-ffi `29/29`、ArkTS `395/395`、Rust workspace/fmt/Clippy、x86_64/arm64-v8a Native Release 和内容门禁。最终 unsigned Release 为 37,984,852 bytes/SHA-256 `42c92678ddeffde84ec2ea72f5a04203c95db2a474435ac87e5d38103daa36d9`；signed Release 为 38,123,521 bytes/SHA-256 `f2302e707882e6ebc3e30841382b80dde11db7c790b802f4ab25a3cb00f78c40`。HarmonyOS 6.1 / API 24 / x86_64 Phone `1320×2856`、2in1 `3120×2080`、Tablet `2880×1920` 已完成真实 `aa` 命令、物理快捷键、强停持久化以及用户词库 UI、跨进程热重载和冷启动闭环；三台输入 `ni` 均得到固顶第 1、普通词第 2、指定词第 3，系统词“你”被删除规则隐藏。用户词库页面后续已统一避让系统/挖孔安全区并隐藏视觉滚动条；设置主页已移除三处指定辅助说明，Phone Release 布局与滚动验证通过。完整说明见 `docs/features/direct-control/STAGE12_DIRECT_CONTROL_USER_LEXICON.md`，设备证据见 `docs/evidence/2026-08-10-stage12-three-device/README.md`，决策见 ADR 0024。

**移动端候选位置阶段 1 COMPLETED / TOUCH_CURSOR_CANDIDATE_CLOSED_LOOP（Phone/Tablet 输入框下方候选窗，2026-08-06）** — 设置页“候选窗位置”现提供 `候选栏 / 输入框下方` 两项。历史 `AUTO` 在触屏端兼容为候选栏；选择输入框下方后，Phone/Tablet 使用与固定 `SOFT_KEYBOARD + FLG_FIXED` 共存的 `STATUS_BAR` 附属面板，根据宿主光标绝对坐标在下方优先、上方回退并避让软键盘。2in1 实体模式仍走既有 `FLAG_CANDIDATE` 路线。

触屏浮动候选复用正式候选筛选、字号、主题、分页、精准后缀和提交链；候选窗真正显示后才隐藏键盘栏内容。缺少锚点、能力不足或面板失败时继续使用候选栏，不清组合。Pad 历史固定侧面候选条已退出 `FLOATING` 正式解释；设置持久化与跨进程同步继续复用 schema 4，无权限、Native ABI、词库或排序变更。

ArkTS `383/383`、internalDebug 与 unsigned Release 构建 PASS。HarmonyOS 6.1 / API 24 / x86_64 Phone `1320×2856` 和 Tablet `2880×1920` 已验证固定软键盘与光标下候选窗共存、候选点击提交及收起；Phone 候选根坐标 `[168,868][1135,1064]`，Tablet 为 `[96,464][1216,576]`。ARM64 实体设备、三方应用矩阵、旋转/分屏和 2in1 本阶段专项重跑为 `NOT_RUN`。报告见 `docs/evidence/2026-08-06-touch-candidate-placement-stage1/README.md`。

**电脑端整改阶段 5 COMPLETED / COMPUTER_REMEDIATION_COMPLETED_WITH_HARDWARE_LIMITATIONS（产品化收口，2026-08-06）** — 电脑端浮动候选窗现只显示编号与候选词，不再重复显示宿主输入框中的组合字母，也不显示候选编码提示。窗口宽度按实际候选数量、文字、字号和分页状态在 `72～560 vp` 内自适应；2in1 设备输入 `s` 时仅有 `1. 三 / 2. 所有`，实测宽度约 `162.6 vp`。

设置 schema 已升至 4，并正式提供 `AUTO / 始终使用实体键盘 / 始终显示虚拟键盘`。AUTO 规则覆盖 2in1 与连接字母实体键盘的 Tablet；设置与设备热插拔均可触发运行时重算，固定键盘和候选窗经统一所有权队列串行切换。正式模块已经加入 `2in1` 设备声明。

ArkTS `384/384`、default Debug、internalDebug、unsigned/signed Release 及内容门禁 PASS。signed Release 为 38,008,487 bytes/SHA-256 `b6f5cef6bcd9a0dbb5b478a302c03b4e510040ad31dd86224bf8822537a92da4`，并在 API 24 / x86_64 2in1 模拟器的独立 ArkUI 宿主与系统浏览器完成候选、鼠标/数字提交、Esc、移动缩放、应用切换和 `HARDWARE -> TOUCH -> AUTO/HARDWARE` 闭环。真实 USB/蓝牙键盘、ARM64 2in1、Phone/Tablet 本阶段专项重跑和 AGC 上传检测为 `NOT_RUN`。报告见 `docs/evidence/2026-08-06-computer-stage5/README.md`。

**电脑端整改阶段 4 COMPLETED / FLOATING_CANDIDATE_CLOSED_LOOP（正式浮动候选窗与鼠标交互，2026-08-05）** — 2in1 的 `HARDWARE_READY` 已按阶段 1 冻结的路线 A 正式启用 `SOFT_KEYBOARD + FLAG_CANDIDATE`。候选窗只在中文、有组合且候选非空时显示，包含组合编码、编号、选中态、分页和精准后缀；内容驱动 `280～560 vp` 动态宽度。光标锚点采用下方优先、上方回退和安全区夹紧，窗口/光标/候选内容变化时重算，配置变化会先废弃旧锚点并隐藏。

鼠标点击映射到正式候选索引并复用 `commitCandidate`，提交中重复点击被拦截；数字键提交同一候选，Esc、清空、输入框/应用切换和 `inputStop` 均安全隐藏，宿主焦点与 `HARDWARE_READY` 会话保持。HARDWARE 模式不再被异步物理键盘枚举或旧候选位置偏好误降级，固定键盘保持零显示；Phone/Tablet 继续走 `TOUCH_READY`。

ArkTS 全量 `378/378 PASS`。HarmonyOS 6.1 / API 24 / x86_64 2in1 的独立 ArkUI 宿主和系统浏览器本地 HTTP 输入框完成候选定位、鼠标/数字键、Esc、焦点、窗口移动/缩放及应用切换闭环；Phone/Tablet/2in1 模拟器矩阵 PASS。default unsigned Release 内容门禁 PASS，37,857,196 bytes/SHA-256 `7f8ce1bdd168033640b15a8eea8b9f12ea32707a4bcc5fd279e840198b89d7eb`；internalDebug 为 41,270,408 bytes/SHA-256 `fbb29fdba9d01add815da1fb7d0352de6db7dbc4b2312c410469cb1151021d06`。真实 USB/蓝牙键盘、ARM64 2in1 和 signed Release 专项为 `NOT_RUN`，进入阶段 5。报告见 `docs/evidence/2026-08-05-computer-stage4/README.md`。

**电脑端整改阶段 3 COMPLETED / HARDWARE_INPUT_CLOSED_LOOP（实体键盘完整输入闭环，2026-08-05）** — 正式物理按键合同已经覆盖 A-Z、Backspace、Space、Enter、1-9、`'`、Esc、四方向和 PageUp/PageDown。无组合时仅中文 A-Z 由输入法开始组合；有组合时才消费编辑、选词、取消和分页；Ctrl/Alt/Logo、英文、URL 和密码输入继续交还宿主。

Esc 走独立组合取消链路，不结束会话或触发固定键盘隐藏。方向键移动当前页 `highlightedIndex`，分页复用既有 Native 页；Space/Enter 提交当前选中项。DOWN/UP 成对消费、重复 DOWN、无 `unicodeChar` KeyCode 回退、快速连续输入 pending 保护和跨会话 generation 隔离均已接入既有串行输入队列。

ArkTS 全量单元测试 PASS。HarmonyOS 6.1 / API 24 / x86_64 2in1 模拟器使用正式 default Release 与独立 ArkUI 宿主、系统浏览器完成中文组合、方向选词、Esc、无组合直通、URL、密码、分页路由和 10 轮快速输入闭环；全程保持 `HARDWARE_READY` 且固定面板零创建/零显示。internalDebug HAP 为 41,253,823 bytes/SHA-256 `507fe89b77d1d48c276cc375d98b7b7726f788d3970f816d624f80ba7a721e31`；default Release HAP 为 37,850,616 bytes/SHA-256 `87302bf1d071e65e4e5872ebd63a09b62e26fc42ddeb08213840ed04b2549e17`，Release 内容门禁 PASS。阶段 4 正式候选窗未启用；真实 USB/蓝牙键盘、ARM64 2in1、signed Release 专项和本阶段 Phone/Tablet 设备专项重跑为 `NOT_RUN`。报告见 `docs/evidence/2026-08-05-computer-stage3/README.md`。

**电脑端整改阶段 2 COMPLETED / HARDWARE_READY（输入会话与面板生命周期解耦，2026-08-05）** — 已建立独立 `TOUCH / HARDWARE` 有效展示模式、`AUTO / TOUCH / HARDWARE` 偏好入口和 `INACTIVE / TOUCH_READY / HARDWARE_READY` 状态。阶段 2 的 AUTO 规则仅把 2in1 解析为实体模式；Phone/Tablet 保持触屏模式，外接键盘动态切换留到阶段 5。

正式 `inputStart` 现在先绑定编辑器并启动会话，再决定是否显示固定键盘。2in1 的 `HARDWARE_READY` 不创建 `FLAG_FIXED`，但保留 `sessionActive=true` 和 `editorConnected=true`。固定面板隐藏已拆成无副作用的可见性更新；实体模式不会因系统 keyboard show/hide 清预览、清组合、重置引擎或停用会话。internalDebug 的阶段 1 探针不再自动接管 2in1，正式生命周期已可直接验收。

新增统一 `SoftKeyboardPanelOwnershipCoordinator`，以单一队列串行协调 `FIXED_KEYBOARD` 与 `CANDIDATE_WINDOW`，新所有者创建前必须销毁并撤销旧所有者。阶段 2 单测覆盖模式解析、固定面板零创建、hide 语义隔离、触屏到实体切换和所有权互斥；ArkTS 全量测试 PASS。HarmonyOS 6.1 / API 24 / x86_64 Phone、Tablet、2in1 模拟器矩阵 PASS：2in1 连续切换 TextInput、TextArea 和浏览器均无固定面板，Phone/Tablet 固定键盘仍可见。internalDebug HAP 为 41,228,911 bytes/SHA-256 `f14b024ff5cfdf56d03cc949f5f87ad8aa0271e1fc41cdd6e2e52e50120334cb`；default unsigned Release HAP 为 37,842,068 bytes/SHA-256 `21ccc491d7ec632536c41487bd05d95d23e8e11d6465c6cf390bdaf7f2cac591`，Release 内容门禁 PASS。阶段 3/4 未提前启用，真实 USB/蓝牙键盘、ARM64 2in1 和 signed Release 电脑端验收为 `NOT_RUN`。报告见 `docs/evidence/2026-08-05-computer-stage2/README.md`。

**电脑端整改阶段 1 COMPLETED / ROUTE A FROZEN（2in1 平台能力验证，2026-08-05）** — internalDebug 已增加仅在 `deviceType=2in1` 激活的隔离探针。探针不创建固定 `FLAG_FIXED` 面板，日志中 `fixedPanelCreateCount=0` 且无 `InputPanelController`；Phone/Tablet 的调试和正式输入入口保持不变。候选面板任一步失败时才会销毁残留并转测 `STATUS_BAR`。

HarmonyOS 6.1 / API 24 / x86_64 2in1 模拟器中，独立 `SOFT_KEYBOARD + FLAG_CANDIDATE` 的 create、setUiContent、resize、moveTo、show/hide/show、鼠标点击、焦点保持和 destroy 全部 PASS。ArkUI `TextInput`、`TextArea`、系统浏览器分别获得有效绝对光标锚点 `(651,438,35)`、`(651,965,35)`、`(968,386,40)`；点击候选后宿主仍 focused，A/B 键继续进入 IME 且宿主文本为 `ab`。模拟器检测到 1 个字母键盘设备，但真实 USB/蓝牙键盘仍为 `NOT_RUN`。

路线已从历史 C 修订并冻结为 A。历史错误码 1 只发生在固定键盘存在时创建第二个软键盘面板的竞争条件下。正式浮动门禁暂不打开，下一阶段先实现 `HARDWARE_READY`、输入会话/固定键盘/候选窗生命周期解耦和唯一面板所有权。ArkTS 全量单元测试、internalDebug clean build、一键 2in1 验收脚本和正式 default Release HAP 构建均 PASS；internalDebug HAP 为 41,235,447 bytes/SHA-256 `50253da5e804a22f3608ecfadb3cfe502ee9bcb965b8dc283e65cb1dfc4b2375`，default Release 为 37,832,144 bytes/SHA-256 `dcf16e73dd9acbe2da429d338c0e581e69977fa2e1327e61303ea01084b25ebe`。报告见 `docs/evidence/2026-08-05-computer-stage1/README.md`。

**17/26 键双拼 UI 阶段 1 COMPLETED（主机实现、ArkTS 自动测试与 Debug HAP 构建范围，2026-08-05）** — 已按 `键盘UI-17和26键.md` 接入统一键盘方案入口。无输入码时，顶部候选栏切换为空闲工具栏并显示当前 `17 键双拼`/`26 键双拼`、系统“输入法”、双羽“设置”和“收起”；出现输入码或候选后恢复纯候选栏，工具入口不挤占候选。选择浮层支持当前项标记、立即切换与点击外部关闭，独立 Preferences 记忆布局，未知值回退到默认 26 键。

截图反馈已完成：左侧方案按钮不再显示下拉尖号；右侧收起按钮只保留 20×20 矢量尖号，并在点击区内水平、垂直居中；方案浮层删除两项说明小字，仅保留方案名和选中标记，宽度由 72% 收紧到 52%；字母键、功能键、工具栏、输入码及预览字号整体下调，动态字母/功能/预览上限收紧到 `18/14/27`。

17 键三排已固定为 `HP/SH/ZH/B/OXV/MS`、`L/D/Y/WZ/JK/NR`、`CH/Q/G/CF/T/删除`，底栏为 `符/123`、中/英、空格、逗号/句号和动态动作键。由于需求文档明确把点击/连击/滑动/长按映射留待最终输入逻辑确认，阶段 1 采用同一键帽内每个字母独立点击目标，确保 26 个字母均可输入而不预设手势。后续手势只需替换 `SegmentedKey` 交互。17 键在中文/英文内部模式均保持布局，标点按语言切换中文/ASCII。

新版 26 键保持标准 QWERTY，第三排固定为 Shift、`Z`～`M`、图标删除；组合期间不再用分词键替换 Shift。中/英键已移除系统输入法长按动作，只负责内部语言切换；系统选择器迁移到空闲工具栏，“设置”通过输入法扩展上下文启动 `EntryAbility`。没有修改 Rust/C++/FFI、interface/ABI、双拼解析、候选排序、正式词库或音形 bundle。

门禁：ArkTS 全量单元测试 PASS；`entry@default` Debug HAP 的 ArkTS 编译、资源打包与签名 PASS。Phone/Pad 视觉、横竖屏、深浅色、运行时布局持久化、系统选择器、设置跳转、第三方输入框与 ARM64 真机矩阵均为 `NOT_RUN`，进入阶段 2 设备验收，不宣称完整交付完成。

**小鹤音形精准匹配阶段 6 COMPLETED（精准匹配提示，主机、signed Release 与 x86_64 Phone/Pad 模拟器范围，2026-08-05）** — 正式 `xiaohe-yinxing` 现在先锁定精确路径：有精确词条时只显示同码候选；没有系统精确词条和用户精确规则、但存在严格更长编码时，才按分类顺序与分类内 `source_order` 返回最多 9 项提示。提示显示未输入的编码后缀，可主动选择，但不参与唯一自动上屏、第五键顶屏或空码切分；精确路径被 `#删` 清空也不回退提示。

设置 schema 已从 2 升级为 3，设置页新增“精准匹配提示数量”，范围 1～9、默认 9，只控制提示可见数量，不截断精确同码重码。正式 `un` 源序固定为“熟能生巧、伤脑筋、施耐庵、史努比、十拿九稳、上年结转、受虐狂、少年郎、十年树木”；候选栏依次显示 `uq/jb/an/bi/jw/jv/kl/lh/um` 后缀。FFI、C++、interface/ABI version 4、正式 bundle、用户词库文件格式和小鹤双拼均未修改。

Rust 全 workspace、fmt、全 workspace/all-target/all-feature Clippy、ArkTS 全量单元测试、双 ABI Release Native、signed Release HAP 与 Release 内容门禁全部 PASS。signed HAP 为 37,942,313 bytes/SHA-256 `2f038338305c857e9c2ddfc3b6319b41b3db91967c7ad7644256c5583d352f4b`。Phone `1320×2856` 验证默认 9、设置为 3、提示主动提交和精确路径锁定；Pad `2880×1920` 完整显示 9 项，与经理示例顺序一致。两端各 10 轮压力预检及 fatal 扫描通过。ARM64 真机、分屏、长时间 soak 和完整双拼设备矩阵 `NOT_RUN`。完整证据见 `docs/evidence/2026-08-05-xiaohe-yinxing-precise-match-stage6-hints/README.md`，决策见 ADR 0023。

**小鹤音形精准匹配阶段 5 COMPLETED（x86_64 Phone/Pad 模拟器与 signed Release 范围，2026-08-05）** — 真正的 signed Release HAP 已重新构建并通过生成 profile 与内容门禁：`buildMode=release`、`debug=false`，37,912,924 bytes/SHA-256 `292193f8fe3713e18a87cd9a0e4211de95ba6c26576ede0beb751338f4b2e956`；unsigned Release 为 37,768,240 bytes/SHA-256 `8b4df2853e16de3adfbea7009176b61c42a12e070ee5152636df500d53e302be`。正式资源白名单和音形 bundle 大小/哈希通过，权限仍只有 `ohos.permission.VIBRATE`。旧输出目录中的 signed HAP 被核实为 Debug 构建，其设备结果不作为最终 Release 证据。

HarmonyOS 6.1 x86_64 Phone `1320×2856` 竖屏和 Pad `2880×1920` 横屏均使用 signed Release 与独立第三方应用 `com.example.shuangyuime.acceptance` 完整重跑。聊天单行、URL、搜索、多行、应用切换、10 轮连续 `aaba`、退格恢复、隐藏/恢复及 50 轮长输入压力全部 PASS；未发现误上屏、重复上屏或丢键。Phone/Pad 输入法进程 RSS 分别增长 20/12 KiB，崩溃关键字扫描为空。按用户要求本阶段只做模拟器；ARM64 真机、分屏自动化、Debug/InternalDebug 重建与完整双拼设备矩阵为 `NOT_RUN`，不得表述为完整发布门禁通过。证据见 `docs/evidence/2026-08-05-xiaohe-yinxing-precise-match-stage5-simulator/README.md`。

**小鹤音形精准匹配阶段 4 COMPLETED（正式数据全量审计与同机 Release A/B，2026-08-05）** — 新增可复现的 `precise_match_stage4_audit` 和生成脚本，遍历全部 456,976 个四码：零候选 394,265、唯一 59,010、重码 3,701、最大候选 5。全部唯一项单次自动提交、全部重码等待选重/顺序稳定/候选可达、精确码无前缀混入均通过；6,636 个简码对、59,151 个词组对、7 个可选分类和全部 62,711 个非空四码用户删除变化无异常。两次报告哈希均为 `61e18fcf474e90e52d05e4568b0a7d536e78f8d26da512078469ff2ec0a9cc40`。

Release A/B 覆盖 13,781 个正式一至三码前缀，历史渐进/精准策略查询 P95 为 24.6/8.2 µs；候选传输下降 95.51%，候选 JSON 下降 92.75%，工作集增量辅助观测下降 90.68%。正式 bundle 未修改。阶段 4 完整证据见 `docs/evidence/2026-08-05-xiaohe-yinxing-precise-match-stage4/README.md`。

**小鹤音形精准匹配阶段 3 COMPLETED（主机自动化、HAP 构建与 x86_64 Phone 竖屏范围，2026-08-05）** — 候选 UI 已按稳定 `schemeId` 显式隔离。`xiaohe-yinxing` 只显示当前精确候选快照，不显示展开动作，也不进入 Phone/Pad 展开面板或 Pad 浏览侧栏；`xiaohe` 的 50 项分页、展开面板和原候选浏览路径保持不变。进入精准模式会关闭遗留展开状态，切回双拼后原布局能力恢复。

音形一至三码继续只渲染阶段 1 引擎返回的精确简码；无候选时显示“继续输入形码”，完整码无候选时显示“无匹配全码”，不创建伪候选。无障碍文案区分精确简码和完整码候选；候选点击继续把索引交给既有 `commitCandidate(index)`，没有 UI 直接写入宿主文本的旁路。C++/FFI/interface/ABI、查询排序、正式码表、八分类和用户规则均未修改。

门禁：ArkTS 349/349、internalDebug/unsigned/signed Release HAP 构建和 Release 内容门禁 PASS；Debug HAP 为 41,066,440 bytes/SHA-256 `3516f065820d165cb72c41f1abab1610a5130daefc8f0918c8b017135c64bef6`，unsigned Release HAP 为 37,768,848 bytes/SHA-256 `96b7a1a3459e51eeb0bda30f160b8926c47e55c3936225de980de7af84c50667`。x86_64 Phone 竖屏独立第三方编辑框验证音形 `bm` 无展开、双拼 `h` 保留展开。正式音形 bundle 哈希保持冻结。Pad、横屏、分屏、ARM64 真机和压力矩阵本轮 `NOT_RUN`，继续由阶段 5 验收。下一阶段为阶段 4 正式数据全量审计；第二候选快捷键仍待产品确认，不阻断阶段 0～3。完整证据见 `docs/evidence/2026-08-05-xiaohe-yinxing-precise-match-stage3/README.md`。

**客户修改阶段 4.3 COMPLETED（主机与自动测试范围，2026-07-29）** — 输入码展示现由 Rust `CompositionResult.displaySegments` 提供结构化原始码段，ArkTS 只使用 `'` 连接，不再按原始字符串猜测音节。完整编码每两码一段，奇数尾码保留；客户示例 `vegewtyijkjj` 显示为 `ve'ge'wt'yi'jk'jj`。顶部候选栏、Pad 固定侧栏和保留浮动组件共用同一格式化入口，并继续显示下划线“未上屏”状态。显示分隔符不进入 `rawInput/preeditText`、查询、学习或提交。C ABI/interface version 4 不变；ArkTS 343/343、`engine-protocol` 4/4、Rust workspace 全量测试、x86_64/arm64-v8a Native、Release HAP 构建与内容门禁 PASS；本轮 unsigned Release HAP 为 37,763,052 bytes，SHA-256 `efd650c9bcf84884bcf0065cae9b72229f618f1660d6b923d34b17b8cae7d5fb`。模拟器/真机视觉验收和第三方宿主回归本轮 `NOT_RUN`。

**候选词改进阶段 6 COMPLETED（覆盖审计、稳定语料、确定性门禁、主机性能探针与现有 unsigned Release HAP 资源审计范围，2026-07-29）** — 新增 112 项独立验收 TSV 和 `candidate-baseline stage6-audit`，逐条输出词条、输入/预期编码或拼音、词库存在性、正常召回、最终排名、分页可达性、缺失分类和来源。语料覆盖常用字词、成语、口语、网络表达、地名、人名、项目专业词、多音字、音形/双拼一至四码、生僻/扩展字符和非法编码。

审计确认 `MISSING_IN_LEXICON=11`、`PRESENT_NOT_RECALLED=6`、`PRESENT_RANKED_TOO_LOW=0`、`PRESENT_NOT_ACCESSIBLE=0`、`INVALID_ENCODING=2`、`DATA_CONFLICT=0`、`UNSUPPORTED_BY_CONTRACT=2`。11 项真实缺失已进入延期清单；本阶段没有新增经独立版本和许可证审查的数据源，因此正式词库新增/删除/重排均为 0。已有但未召回的 6 项没有通过添加重复词条处理。

来源审计确认双拼现有固定 Rime 源和项目短句为 Apache-2.0；音形客户数据在项目审批范围内允许产品使用和 HAP 交付，但正式 bundle 继续冻结。双拼频率仍使用统一的 `clamp(weight + 1, 1, 1000000)` 尺度及确定性冲突合并，音形继续使用分类和物理 `source_order`，两者保持隔离。

覆盖报告连续两次均为 76,291 bytes、SHA-256 `8ac272fc24fffb3793850d904f63431ddd1e5b7b283482539e88148c9fc94105`。Rust workspace 420/420、fmt 和 Clippy PASS。`production.lex` 与音形 bundle 大小和 SHA-256 保持冻结值；现有 unsigned Release HAP 37,750,936 bytes/SHA-256 `1b2a815b4b52f7982d7e6921aab4a5922c6e53aff2fb78071f8dcb91ca628ead` 的资源门禁 PASS。未修改阶段 3 召回、阶段 4 输入语义、阶段 5 排序/学习、候选 UI、ABI 或正式数据。Phone/Pad、ARM64 真机、signed Release 第三方输入框和设备压力矩阵为阶段 7 `NOT_RUN`。下一阶段为阶段 7 最终性能、稳定性和发布验收；完整证据见 `docs/evidence/2026-07-29-candidate-stage6/README.md`。

**候选词改进阶段 5 COMPLETED（主机、自动测试、双 ABI Native 与 HAP 构建范围，2026-07-28）** — 小鹤双拼的单键/不完整前缀现使用独立质量排序；完整音节精确查询、句子解码、阶段 0 旧召回回退和小鹤音形码表排序均保持原合同。前缀排序依次使用匹配类型、有限质量分加有界用户分、原始频率和稳定文字/reading/来源/ID；1～2 字不衰减，3 字使用 2 倍除数，4 字及以上使用封顶 8 倍除数，单字符重复项额外使用封顶 8 倍除数。该规则不删除候选，不硬编码候选名单。

阶段 3 的全索引扫描、可见文字去重 Top-K 256、最终快照 128、正式页大小 50 和阶段 4 `QueryIntent` 均未修改。用户分作用于完成召回、系统去重与基础排序后的完整 256 项池，再截断 128 项快照和分页。正式 `h` 前 20 现为“和、好、还、会、还是、很、后、还有、或、号、很多、话、或者、哈、好像、回来、孩子、好的、活动、换”，包含 11 个单字和 9 个 2～4 字短词，覆盖 10 个首音节分支；“回复日期/呵呵/哈哈”由第 6/4/10 调整到第 25/22/40。`a/h/n/s/z` 前 20 均无 5 字以上候选。

生产词频审计确认 65,115 条均来自 `rime_pinyin_simp`，频率为 1～1,000,000；已记录“回复日期”等异常，但没有清洗、扩充或替换数据。生产候选“会议”连续选择的排名为 48→44→43→41→38；引擎重建后保持 38，清除后恢复 48，禁学习会话选择 4 次仍为 48。密码框、数字密码、隐私/禁学习、失败提交、会话失效、分数上限和隐私哈希合同不变。

门禁：Rust workspace 419/419、ArkTS 332/332、fmt、全 workspace/all-target/all-feature Clippy、x86_64/arm64-v8a Native Release、internalDebug 和 unsigned Release HAP 全部 PASS。同机 Release a～z 冷查询 P50/P95 为 2.195/4.555 ms，缓存命中为 37.1/68.1 µs；256 项去重/系统排序/用户重排 P50 为 92.9/128.8/142.4 µs。Debug HAP 为 41,024,806 bytes/SHA-256 `02b399fdc94afc3d4c454ffaefaf06221d8896f82a30f76183f347fc0ed916b65`；unsigned Release HAP 为 37,750,936 bytes/SHA-256 `1b2a815b4b52f7982d7e6921aab4a5922c6e53aff2fb78071f8dcb91ca628ead`。

`production.lex` 和正式音形 bundle 哈希保持冻结值；未修改召回覆盖、输入语义、候选 UI、页面大小、C++/FFI/interface/ABI 或小鹤音形。Phone/Pad 阶段 5 专项、ARM64 物理真机、signed Release 第三方输入框和设备性能/内存/压力矩阵为 `NOT_RUN`。阶段 6 词库缺口评估已于 2026-07-29 完成；阶段 5 完整证据见 `docs/evidence/2026-07-28-candidate-stage5/README.md`。

**候选词改进阶段 4 COMPLETED（主机、自动测试、双 ABI Native 与 HAP 构建范围，2026-07-28）** — 小鹤双拼现由 parser 输出统一的 `QueryIntent`：空、单键前缀、完整音节、不完整音节、多音节和非法输入。`ime-engine` 只按该意图进入现有 Prefix/Exact/句子路径；ranking 继续使用既有精确/前缀匹配合同或句子评分；ArkTS/C++/FFI 不解释双拼语义，只转发和展示引擎快照。

最终合同：单键 `h/a/o` 是规范拼音前缀，`h` 不混入韵母键 `ang`；`a/o` 通过正常前缀命中方案允许的零声母 reading。`hc/ni/ui/vi` 保持 `hao/ni/shi/zhi` 精确查询。修复了单个歧义完整双键 `lo → lo/luo` 因旧 `syllables.len() >= 2` 被误送句子解码的层间不一致；parser 现在输出逻辑音节槽位，单音节合法 reading 走精确合并，多音节歧义按方案声明顺序规范化而不依赖词库。输入/删除逐级转换会替换旧快照并重置到第 0 页，删除到空清除候选和分页。

门禁：Rust workspace 415/415、ArkTS 332/332、fmt、全 workspace/all-target/all-feature Clippy、x86_64/arm64-v8a Native Release、internalDebug 和 unsigned Release HAP 全部 PASS。Debug HAP 为 40,981,174 bytes/SHA-256 `707de14f30a2d67a4a76004a502791550198fecd689a2b2720eda6844a068c1b`；unsigned Release HAP 为 37,707,304 bytes/SHA-256 `0ea34054dc13a650a49db197a568e91603588ab6be2bd9a114b13eda6ad22376`。

本阶段未实现首字母简拼或设置项，未修改阶段 3 的 256/128 Top-K 合同、词频/学习、正式词库、小鹤音形、`#固/#删/#N`、候选展开 UI、C++/FFI/interface/ABI 或候选提交 ABI。Phone/Pad 阶段 4 专项、ARM64 物理真机、signed Release 第三方输入框、设备性能/内存/压力矩阵为 `NOT_RUN`。ADR 见 `docs/adr/0021-xiaohe-query-intent-contract.md`，完整证据见 `docs/evidence/2026-07-28-candidate-stage4/README.md`。

**候选词改进阶段 3 COMPLETED（主机、自动测试、双 ABI Native 与 HAP 构建范围，2026-07-28）** — 小鹤双拼不完整前缀已从“按 reading 字典序先取 64 项、再排序”切换为完整相关索引遍历和 O(K) 有界全局 Top-K。正式召回池为 256，跨 reading 按可见文字稳定去重；现有用户学习在最终截断前重排，稳定快照为 128，最后沿用 50 项正式分页。旧 `LexicalEarlyStop` 保留为显式回退策略，阶段 0 工具继续使用旧策略逐字节复现冻结基线。

正式 `h` 查询扫描 2,032 个相关索引和 3,234 条原始记录；旧 64 项召回仅覆盖 `ha/hai`，新 256 项召回池覆盖 19 个分支，前 20 覆盖 9 个分支并包含“和、好、还、会、很、后、或”。页大小 9/20/30/50 拼接后均为相同的 128 项稳定快照，50 项页为 50＋50＋28，第二页首项“会议”提交正确。完整双拼 `hc/ni/ui/vi`、句子 `nihc/uurufa` 和部分提交与阶段 0 全字段基线一致；完整精确查询仍保留原 64 项上限。

门禁：Rust workspace 407/407、阶段 0 冻结文件 3/3、fmt、全 target/feature Clippy、ArkTS 测试、x86_64/arm64-v8a Native Release、internalDebug 和 unsigned Release HAP 全部 PASS。同机 Release 下 `h` 冷查询 P50/P95 为 3.416/4.398 ms，缓存命中为 45.5/64.6 µs；a～z 冷查询汇总 P50/P95 为 2.471/5.656 ms。Debug HAP 为 40,973,734 bytes/SHA-256 `d22d74a4692efa92045d95a2fdf29fe27a409610fccf819edbc8d14d64b7c2dc`；unsigned Release HAP 为 37,699,880 bytes/SHA-256 `69931320aebb8d22c2a7a853dcd249ff33f285d2996a7e25e30967ce0ca2c7ad`。

本阶段未修改小鹤音形、候选 UI、页面大小、C++/FFI/ABI、正式词频或词库。Phone/Pad 阶段 3 正式双拼专项、ARM64 物理真机、signed Release 第三方输入框、设备端首帧/内存、快速输入与压力矩阵为 `NOT_RUN`。完整证据见 `docs/evidence/2026-07-28-candidate-stage3/README.md`。

**候选词改进阶段 2 COMPLETED（主机、构建与 x86_64 Phone/Pad 模拟器范围，2026-07-28）** — 候选栏已经接入独立、可发现的“展开候选/收起候选”动作，右侧“收起键盘”保留原动作、ID 和语义；展开面板标题行不再重复显示“收起”，展开与收起统一由候选栏中的单一入口完成。Phone 普通状态仍为单行候选栏；展开后在固定输入法窗口内以 5 列竖屏/8 列横屏当前页网格替换键页，避免覆盖或裁切键区，收起后恢复完整键区。Pad 展开后使用约 48% 宽的右侧 10×5 网格，左侧完整字母键区保持可见、可点击，正式 50 项当前页可在单屏容纳。

分页继续复用 `candidatePage/hasPreviousPage/hasNextPage` 和当前页 `commitCandidate(index)`，不修改 ABI，也不跨页累计候选。翻页期间同步防重入；成功才替换当前页，失败保留旧候选。空候选、会话结束、隐藏键盘、切换输入框、方案/模式切换、错误与销毁均清理展开和加载状态。展开时普通栏候选内容隐藏，因此 ArkUI 候选节点上限仍为当前页 N 项。无障碍语义明确区分“展开候选”“收起候选”“上一页候选”“下一页候选”和“收起键盘”。

门禁：ArkTS 330/330、Rust workspace 403/403 与 fmt PASS；internalDebug 和 unsigned Release HAP 构建 PASS。Phone x86_64 `1320×2856` 已验证第 1 页→第 2 页→上一页→候选栏收起并恢复键区；Pad x86_64 `2880×1920` 已验证侧栏、翻页和第 2 页候选“海边”提交，提交后面板关闭且键盘保持。Debug HAP 为 40,909,750 bytes/SHA-256 `4116C46349AA4C2301C3CC97D6AEB4582F73B1C2A71EACE98648D81008F9DCFC`；unsigned Release HAP 为 37,635,864 bytes/SHA-256 `4425ADF11427673ECCB51035558C6F4C1566456D85264F0A880DB13E1553DA3B`。

正式页大小仍为 50；internalDebug 为制造稳定两页回归继续显式使用 8 项 fixture 页。本阶段未修改 Rust 查询、音形/双拼召回和排序、学习、用户规则、正式词库、C++/FFI 或 ABI。ArkUI 首帧/设备内存独立插桩、ARM64 物理真机、signed Release 第三方输入框、旋转/分屏完整矩阵、快速触键和压力测试为 `NOT_RUN`。完整证据见 `docs/evidence/2026-07-28-candidate-stage2/README.md`。

**候选词改进阶段 1 COMPLETED（主机、构建与 x86_64 Phone/Pad 模拟器基本运行时范围，2026-07-28）** — 已解除公共 `max_page_size=9` 硬限制。ArkTS、Node-API 与 Rust 正式缺省页大小统一为 50；Rust 最大允许页大小为 64，显式 3/5/8/9 小页继续可用，0 被拒绝，异常超大值钳制为 64。`QueryConfig::normalize_page_size` 的同一结果用于小鹤音形状态机、小鹤双拼查询和 `CandidateSession`，方案切换不产生页大小分叉。

阶段 0 快照保持原文件与哈希不变。音形 `h` 页大小 9/50 拼接后的完整 512 项和顺序一致，前 9 仍为“和、忽略、化、会、行、合、后、好、海”，第二页从全局第 51 项开始；双拼 `h` 的 64 项召回池在 9/50 下完全一致，50 项首页加 14 项末页，原前 9 顺序不变。FFI 自动测试直接确认请求 50 返回 50、请求 9 返回 9；超大请求在音形与双拼后端均钳制为 64。

门禁：Rust all-targets 403/403（含 FFI 28/28）、ArkTS 324/324、fmt、全 target/feature Clippy、x86_64/arm64-v8a Native、internalDebug、unsigned Release HAP 全部 PASS。Phone x86_64 `1320x2856` 与 Pad x86_64 `2880x1920` 的 internalDebug 运行时页整体 PASS；Phone 长矩阵首轮 14/14 PASS，但第二轮因 240 秒命令上限中止，不声明双轮完成。性能 A/B 中查询耗时基本持平，当前页 JSON 约由 1.2 KB 增至 5.0 KB，峰值工作集基本不变。

本阶段未修改双拼前缀召回、`max_candidates=64` 召回语义、双拼/音形排序、用户 `#固/#删/#N` 规则、正式词库、候选展开 UI 或收起键盘行为。ARM64 物理真机、signed Release 独立第三方输入框、ArkTS Candidate Store 独立更新时间、设备性能/压力矩阵为 `NOT_RUN`。完整报告见 `docs/evidence/2026-07-28-candidate-stage1/README.md`。

**小鹤音形改进阶段 1 COMPLETED（主机与 x86_64 模拟器运行时页范围，2026-07-27）** — 正式 `xiaohe-yinxing` 已切换为显式 `ProgressiveXiaoheYinxing` 查询策略：一至三码按“精确候选在前、严格更长的前缀候选在后”合并，四码只取完整精确候选；通用码表 fixture 继续使用 `ExactOrPrefixFallback`，`ExactOnly` 作为独立可测策略提供，`xiaohe` 双拼不进入码表策略。正式后端完整候选快照上限由通用 64 独立提高为 512，ArkUI 仍只创建当前页节点。

候选流水线为：捕获同一次按键的分类与用户词库不可变快照 → 最多收集 4,096 个系统精确/前缀候选 → 精确路径优先稳定去重 → 应用完整编码感知的 `#删/#固/#N` → 再次稳定去重 → 截断为方案上限 → 分页。四码唯一自动提交、有效后续码、第五键顶屏和空码切分继续使用独立的完整精确候选/后续码判断，不以渐进展示列表长度判断。没有修改 FFI、C++、ArkTS 正式数据模型、bundle schema 或正式源数据。

正式二码由阶段 0 旧数量变为：`aa 1→41`、`ai 1→115`、`an 3→165`、`ni 1→94`、`hc 1→209`、`ui 4→343`、`vi 6→353`、`wo 1→68`、`xm 3→264`、`xq 2→135`。`ni` 首页为“你、尼、呢、拟、逆、倪、妮、腻、匿”；`ui` 首页为“时间、试试、事、室、时、十、市、实、使”，既有固顶仍最高，精确“事、室”保持相对顺序。页大小 3/9 的 `ni` 完整列表一致，重复查询一致，三码为二码合理过滤子集。

门禁：Rust workspace 395/395、FFI 26/26、ArkTS 323/323、fmt、全 target/feature Clippy、x86_64/arm64-v8a Native、internalDebug、unsigned/signed Release HAP、当前 Release 正向与负向资源门禁、正式输出 15/15 双构建确定性全部 PASS。正式 bundle 仍为 25,397,952 bytes、SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`。x86_64 HarmonyOS 6.1 Phone 模拟器 `1320x2856` 的 internalDebug ArkTS→C++→Rust 正式运行时页两轮 10/10 PASS，包含 `ni` 94 项加两条用户规则后的 96 项全局分页、分类过滤、四码唯一、用户规则、reset/重建及双拼隔离。

未完成：ARM64 物理真机、Pad 本阶段专项复验、真实第三方中文/多行/搜索输入框、快速连续触键和阶段 1 专项设备性能均为 `NOT_RUN`；当前未安装独立 `com.example.nexttest`，因此不将运行时页结果表述为真实输入框验收。历史上 11.6.3 门禁曾禁止正式 `.hsyx`；该规则已由 11.6.8 起的正式白名单取代，冲突脚本现已删除，当前统一使用 `verify-release-hap.ps1` 及其现行负向测试。完整报告见 `docs/evidence/2026-07-27-xiaohe-yinxing-stage1/README.md`，决策更新见 ADR 0020。

**小鹤音形改进阶段 0 COMPLETED（2026-07-27）** — 已在不改变当前查询、提交、切分、用户规则、分类或双拼语义的前提下，冻结正式 bundle、十个指定二码完整候选、四码唯一/多候选、无结果与非法输入、用户规则、分类过滤、小鹤双拼隔离和主机 Release 性能。统一生成入口为 `scripts/generate-xiaohe-yinxing-stage0-baseline.ps1`，机器证据位于 `dictionaries/audit/xiaohe-yinxing/baseline/`，报告见 `docs/evidence/2026-07-27-xiaohe-yinxing-stage0/STAGE0_BASELINE.md`，决策见 ADR 0020。

正式 bundle 仍为 25,397,952 bytes、SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`；两个独立目录的 15/15 正式输出逐字节一致且与当前正式 bundle 一致。阶段 0 新增 CI 测试锁定机器基线和 `aa/ai/an/ni/hc/ui/vi/wo/xm/xq` 的完整候选字段与顺序。主机性能 5 样本：融合加载 P50/P95 `633.9623/634.1907 ms`，首键到 Rust 候选 P50/P95 `0.3291/0.3611 ms`，逐查询 P50/P95 `4.88/19.74 µs`，峰值内存 `147,406,848` bytes。

本轮 Rust 修改后 389/389、fmt、Clippy，ArkTS、FFI、双 ABI、internalDebug/unsigned Release HAP、Release 正负内容门禁均 PASS；没有新增权限。当前只连接 Phone/Pad 两台 x86_64 模拟器，ARM64 物理真机、真机性能和本轮 signed Release 第三方 TextInput 重跑为 `NOT_RUN`；受保护密码键盘自动化仍是既有 `BLOCKED`。这些设备缺口不被伪装成真机 PASS，详见阶段 0 设备清单。

**11.6.9 PARTIALLY COMPLETED（2026-07-27）** — 本轮主机与构建门禁通过：
Rust 387/387、FFI 26/26、ArkTS 323/323、fmt、Clippy、x86_64/arm64-v8a Native、
internalDebug/unsigned Release/signed Release HAP、signed/unsigned Release 内容门禁、
负向安全门禁、签名验证、28/28 来源不可变与 15/15 生产输出双构建一致均 PASS。
五个独立 Release 主机进程测得正式 bundle 加载 P50/P95 650.1365/657.4287 ms，
逐键查询 P50/P95 4.86/18.88 µs，峰值进程内存 114,126,848 bytes。

11.6.9 尚不能完成：当前只连接 Phone/Pad 两台 x86_64 模拟器，没有 ARM64 物理真机；
两台模拟器的密码场景均只显示受保护的灰色安全键盘表面，`uitest` 布局不暴露键帽；
现有脚本因识别不到系统键 ID 而误走应用安全布局分支，随后以“缺少 Shift”失败；设置自动化修正 DebugIndex 导航后通过
主题、高度、学习、反馈和重启持久化，但清空用户模型后半程仍被旧导航假设阻断；
独立 `com.example.nexttest` 未安装，故本轮 signed Release 独立 TextInput、设备性能、
完整应用/旋转/分屏/稳定性矩阵均为 NOT RUN。Release 产物哈希和全部证据见
`docs/evidence/2026-07-27-stage-11.6.9-final-acceptance/`。在修复密码布局、补齐自动化、
ARM64 真机和设备性能/压力证据前，不得宣称客户交付或正式发布验收通过。

**11.6.8 COMPLETED（主机与 x86_64 模拟器范围，2026-07-27）** — 正式方案产品合同、设置页、原子资源安装、Native-first 回滚、跨进程持久化和 Release 白名单均已完成并真实复验。复验发现并修复了关键接入缺陷：设置 Ability 与 InputMethodExtensionAbility 位于独立进程，旧实现只在设置进程加载正式 bundle，导致 UI 显示 `xiaohe-yinxing` 而独立 TextInput 实际仍运行 `xiaohe`。当前以主进程 Preferences 为 canonical 存储，通过本包 `SHARED_CONFIG` DataProxy 发布规范化 schema 2 快照；输入法进程冷启动读取快照并用正式 bundle 重建 Native handle。新 handle 创建失败、安装失败或保存失败时保留旧 handle、旧设置和旧 UI 状态。

interface/ABI version 4（未变）；设置 schema version 2（未变）。正式方案：`xiaohe`（默认）、`xiaohe-yinxing`。正式 bundle：`xiaohe-yinxing-production.hsyx`，25,397,952 bytes，SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`。Rust 387/387、FFI 26/26、ArkTS 323/323、fmt、Clippy、双 ABI、Debug/Release HAP 均 PASS。Debug HAP `40,801,306` bytes/SHA-256 `44A583E51852549BB792D3057DBAF99968C4622A86B8A243A0A0DD7BCC2630C1`；unsigned Release HAP `37,572,616` bytes/SHA-256 `A9F84A9E83D6B60792BFAFA6F8D887284F08B97133663E912A15668DF8A05295`；设备安装的 signed Release HAP `37,707,165` bytes/SHA-256 `3C86B29ED6C36E8AC706333C0A286AA63B4FC6837129343953CAD2ADB2A5137D`。

x86_64 HarmonyOS 6.1 Phone 模拟器 `1320x2856` 已完成 A～L：signed Release 在独立 TextInput 完成默认小鹤、首次/重启后银杏、带组合切回小鹤、再次切银杏和 bundle 复用；internalDebug 的缺失、损坏、不兼容、旧设置迁移、临时文件恢复经 force-stop/restart 两轮 PASS；实际 HAP 大小、SHA 和内容门禁 PASS。Release rawfile 仅批准 `production.lex` + 正式 bundle；fixture、原始 TXT/INI、trace、审计报告、大小不变的 bundle 篡改和网络权限负例全部按预期拒绝；28/28 来源不可变 PASS。证据见 `docs/evidence/2026-07-27-stage-11.6.8-revalidation/`，决策见 ADR 0019。ARM64 物理真机、Phone/Pad 全场景、性能与最终发布验收仍为 11.6.9 NOT RUN，不影响 11.6.8 的主机与模拟器完成结论。

**11.6.7 COMPLETED** — Rust `CodeTableStateMachine` 已实现集中且严格校验的四码提交策略、完整最终候选唯一性、有效更长编码保护、第五键顶屏和当前键单次重放、空码正向/反向切分和空码清屏，以及分类/用户规则感知。ArkTS 对 `processKey` 返回的 `commitText + rawInput` 只提交一次并保存新段；C++、interface/ABI 仍为 4。空码切分已于2026-07-24经产品授权冻结规则并完整实现，见 ADR 0018。

11.6.7 最终主机门禁：Rust、FFI、ArkTS、双 ABI、Debug/Release HAP、Release 正负门禁和 28/28 来源不可变均 PASS。2026-07-27 又在 x86_64 HarmonyOS 6.1 Phone 模拟器 `1320x2856` 的独立 ArkUI `TextInput` 中从 force-stop/clean 启动连续执行 A～N 两轮，28/28 用例 PASS，覆盖四码单次提交、第五键、用户/分类影响、正反向空码切分、Guide 隔离和切回小鹤“你好输入法”；证据见 `docs/evidence/2026-07-27-stage-11.6.7-revalidation/`。ARM64 物理真机仍为 11.6.9 NOT RUN。

**11.6.6 RUNTIME COMPLETED / PRODUCTION DATA PARTIALLY DEFERRED / EDITOR-SIDE DEVICE ACTION ACCEPTANCE COMPLETED** — 已完成封闭动作表、Rust 四状态引导机、interface/ABI 4 单动作协议、C++ 严格桥接、ArkTS 安全执行器、双 ABI、Debug/Release HAP、Release 正负门禁、28/28 来源不可变和 x86_64 internalDebug fixture 两轮 A-G 验收。独立 MainAbility ArkUI `TextInput` 中的日期实际提交、成对 emoji 单次插入及非 BMP 光标探针也已通过；设备日志确认本次 `InputClient` 光标索引按 UTF-16 code unit 计算。正式转换合同没有交付快符、引导、日期时间或成对符号映射，因此这些正式产品能力继续保持延期。

正式八类普通静态文本/符号继续为 `AVAILABLE` 并走既有 `commitText`。原创动作 fixture 仅用于 internalDebug，大小 `2,171` bytes，SHA-256 `05a7653e44fe72c45b1b5b0dc1dc245baaafbc1f4becd5c2ec6c657687c59b63`；Release 不包含它、正式音形 bundle、原始 TXT/INI、审计报告或网络权限。本阶段没有实现 11.6.8 产品入口。

**11.6.2B COMPLETED** — 正式数据接收、权威清单与审计已完成。

**11.6.2C COMPLETED** — 正式规范化、生产 bundle、确定性、完整性和基础查询已完成。

**11.6.3 COMPLETED** — 冻结正式系统码表查询、损坏矩阵、性能与 Debug-only 跨层验收已完成。

**11.6.4 COMPLETED** — 正式包内 36 条 `#固` 与外部用户词库已按“内置在前、外部在后、同完整编码＋词条由外部覆盖”组成单一不可变快照；候选仍复用 `merge_code_table_candidates`，系统表、fixture 与 `xiaohe` 行为不变。

**11.6.5 COMPLETED** — 八个正式分类已冻结为 schema 1 产品合同；默认全开、`core` 必选。Rust 使用每操作捕获的不可变分类快照，原子替换后保留 raw、清零页码、无提交重算；精确/前缀/有效后续码/唯一性、用户规则和分页均使用同一 enabled 快照。

11.6.5 新增分类读取/替换跨层接口，interface/ABI 同步升级为 3；设置 schema 升级为 2，旧值迁移、canonical 顺序、native-first 持久化和失败回滚已覆盖。分类 UI 与正式 bundle 仍只在 internalDebug，Release 默认设置页和资源不变；没有实现引导、四码提交状态机或正式产品入口。

11.6.5 最终门禁：Rust 348/348、ArkTS 290/290、FFI 23/23、双 ABI、Debug/Release HAP、Release 正负门禁和 28/28 来源不可变均 PASS。x86_64 HarmonyOS 6.1 模拟器 `2880x1920` 经 force-stop/restart 两轮 A～L 全 PASS。Debug HAP `40,551,155` bytes/SHA-256 `03BFDC39CE9191486836D93A125AF7A0E0C5E186C1C12D64696C35DC1A28C73E`；Release HAP `12,046,372` bytes/SHA-256 `59BA888F90CFF91A49ADA30D76ED02A83A39B5B6646DA35D9319ECA0731AC809`。

11.6.2C 新增独立 `yinxing-converter/1.0.0`，严格读取合同中的八个权威文件并生成 `HSPYXP01` 1.0 正式包。转换前完整复核路径、大小和 SHA-256；未扫描目录猜测输入，未读取 `ime.android.ini` 或审计专用“码表”导出，未执行任何来源动作。

## 11.6.2C 正式构建结果

```text
scheme_id = xiaohe-yinxing
bundle_id = xiaohe-yinxing-production
data_version = source-receipt-1
converter_version = yinxing-converter/1.0.0
bundle_format = HSPYXP01 1.0
nested_lexicon_format = HSPLEX01 1.1
bundle_content_sha256 = a2b2a8500c68e7e904fbc6bdefa89e4e9cc821182a0c6cbe409e0ec045229f68
bundle_sha256 = 00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30
```

输入为 8 文件、963,555 bytes、73,319 个物理行。普通记录 73,263；用户新增/删除/固顶/位置为 0/0/36/0；复合规则 0；`$cmd`/`$ddcmd` 为 5/0。最终接受 73,299、转换 36、延期 0、拒绝 6、完全重复 0、同编码同词条重复 0、冲突 0。拒绝项为 5 条不支持命令和 1 条网络动作，只进入安全摘要元数据，不进入运行时候选。

分类系统记录数：核心 68,505、分类/次选 1,690、一简次选 26、二简次选 66、表外字 362、全码词 464、生僻字 498、全码字 1,652；另有 36 条全码词固顶用户规则。Unicode 扩展区记录 354，Emoji/特殊符号启发式记录 205，均经过边界验证，未擅自开放延期动作功能。

生成目录：`dictionaries/generated/xiaohe-yinxing-production/`。

| 输出文件 | Bytes | SHA-256 |
| --- | ---: | --- |
| `action-metadata.json` | 1,726 | `26fe0d54609357e07f23cd4201e43be79dd01ad9c350e124b1de3cbe91dd7f8c` |
| `build-report.json` | 8,103 | `b5de2a74a846a0a6f6240fb909b2b6dff2038a4eb1089ab893e719616c676266` |
| `build-report.md` | 2,039 | `d0e080209974734f1aaf621c2898b2bd9598ecce54c8b7e2872a338e89b93fd0` |
| `categories/category-secondary.lex` | 115,959 | `e0676343dd756c23556a80eb929e853cdd57b651ddc7588845effe1fc3bed537` |
| `categories/core.lex` | 4,591,497 | `cdc37681700f173f7a9e1abe5315cf5f3c1b5ea33a6b6cbcb52c2069991eb5fb` |
| `categories/full-code-character.lex` | 103,270 | `9969dc88b88620a8e82bab28bb8a52e2fe1bb182eafe78a6875dff344b241f57` |
| `categories/full-code-word.lex` | 31,148 | `ea8aed7b4d2aa6280f531ab48b7b25b8ac3e26ffbaa2165403f32c2b5246874c` |
| `categories/one-key-secondary.lex` | 1,730 | `27eb79f3703a68b18af949e1249ed266772f377841be08cb50bb415919492670` |
| `categories/out-of-table-character.lex` | 22,721 | `61328b2357562618cc277fcc1ed93c55f73be3e5bbdb4ab9f3f3b777d057c9c8` |
| `categories/rare-character.lex` | 31,131 | `76b32ea8967cba66892fe44c5db884251af7e243e5e52bf507072ead727df874` |
| `categories/two-key-secondary.lex` | 4,139 | `4d103737f6c6a40b86a2a4c89616d31a772dcc78f7f2e78db2092956c12df9a1` |
| `manifest.json` | 8,239 | `8696575f96455f6cd65dc5f191a02e0ef5f5ec66d319948825c9918772b293df` |
| `trace-index.jsonl` | 20,476,629 | `64d6c2275fcfd9c0a874c906e8dd79a667d41ba16e46b8e60237e45bdf575f99` |
| `user-rules.txt` | 582 | `6167a97066c38cd19ba3d3ac88085da0f52fc635a98b0b8144889f148897d3ab` |
| `xiaohe-yinxing-production.hsyx` | 25,397,952 | `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30` |

两个独立干净目录的 15/15 文件集合、相对路径、大小、字节和 SHA-256 完全一致。输出敏感名、网络地址和绝对路径扫描通过。正式加载、1～4 码精确查询、前缀回退、分类顺序、`source_order`、稳定去重、空输入、无结果、大重码翻页、用户固顶覆盖与篡改拒绝均通过 Rust Debug profile 冒烟测试。

## 审计工具与交付物

- Rust 工具：`engine-rust/tools/yinxing-source-auditor`
- 统一入口：`scripts/audit-xiaohe-yinxing.ps1`
- 正式来源 manifest：`dictionaries/audit/xiaohe-yinxing/source_manifest.json`
- 转换合同：`dictionaries/audit/xiaohe-yinxing/conversion_contract.json`
- 脱敏配置参考：`dictionaries/audit/xiaohe-yinxing/sanitized_configuration.json`
- 分类、命令、引用、判定和比较：同目录下 `category_mapping.json`、`command_policy.json`、`missing_references.json`、`decisions.json`、`comparisons.json`
- 人工报告：`docs/audits/data/XIAOHE_YINXING_*`

最终哈希：

```text
source_manifest.sha256 = ef93b39e05a0e11c818f8dd837b3f5b2e87777ab02aaba374765a846be7dce55
conversion_contract.sha256 = 2353a4b41bd9b1e9aeb1e309cb6ae657078de0d133f624921086f68d82ad8692
sanitized_configuration.sha256 = b4b7705055953e0c65d579767875516fd11c8c973af810b3821045551e0d04f0
```

冻结版本字段：

```text
scheme_id = xiaohe-yinxing
bundle_id = xiaohe-yinxing-production
data_version = source-receipt-1
audit_manifest_version = 1.1.0
conversion_contract_version = 1.1.0
auditor_version = yinxing-source-auditor/1.1.0
converter_version = yinxing-converter/1.0.0
```

本阶段实现了离线正式转换器和 `code-table-runtime` 的正式包严格加载；没有修改设置入口或 ArkTS/C++/C ABI 行为。

## 正式来源接收结果

- `码表/`：11 文件，1,284,388 bytes。
- `小鹤音形/`：17 文件，2,265,494 bytes。
- 总计：28 文件，3,549,882 bytes；全部可读取，未识别角色为 0。
- 编码：UTF-8 16、UTF-8 with BOM 11、Binary/Unknown 1；含控制字节的 Android 符号参考已拒绝转换。
- 换行：CRLF 13、LF 7、无结尾换行 7、Binary/Not applicable 1。
- 文件判定：ACCEPTED 1、TRANSFORM 11、DEFERRED 11、REJECTED 5。
- 语法统计：普通记录 266,560；用户删除 489；用户固顶 39；用户位置 0；复合规则 33；`$cmd` 772；`$ddcmd` 1,553。
- 差异比较：9 组；全部具有冻结处理结论，`requires_manual_confirmation=false`。

## 首版权威关系

| 分类 | 11.6.2C 唯一权威输入 | 审计专用、不合并 |
| --- | --- | --- |
| 核心主表 | `小鹤音形/0.0.小鹤.txt` | 无 |
| 分类/次选 | `小鹤音形/1.0.分类.txt` | `码表/导出 - 主码 - 次选字词.txt` |
| 一简次选 | `小鹤音形/2.1.一简次选.txt` | 无 |
| 二简次选 | `小鹤音形/2.2.二简次选.txt` | `码表/导出 - 辅码 - 「二简次选」.txt` |
| 表外字 | `小鹤音形/2.4.表外字.txt` | `码表/导出 - 主码 - 表外字.txt` |
| 全码词 | `小鹤音形/2.5.全码词.txt` | `码表/导出 - 主码 - 全码词.txt` |
| 生僻字 | `小鹤音形/2.8.生僻字.txt` | 无 |
| 全码字 | `小鹤音形/2.9.全码字.txt` | `码表/导出 - 次显 - 「全码字」.txt` |

所有分类已按用户授权冻结：首版只读取“小鹤音形”编号文件；五个对应“码表”导出只保留差异证据，不是补充输入，不参与合并。分类顺序、输入路径和 SHA-256 已写入转换合同。

## 敏感配置处置

客户原始 `小鹤音形/ime.android.ini` 中存在 4 个已赋值凭据型字段及网络、WebDAV、路径和平台动作。原文件保持字节不变并完整进入接收 manifest，但其处置固定为：

```text
original_source_disposition = REJECTED_AND_QUARANTINED
conversion_input = false
eligible_for_hap = false
```

`sanitized_configuration.json` 是项目生成的确定性安全派生物，只记录源文件 SHA-256、物理行号、命中类型、原因码和行摘要哈希，不复制任何 INI 键或值；`contains_source_values=false`、`contains_credentials=false`、`runtime_configuration=false`。它仅证明隔离决策，不是 HarmonyOS 运行配置，也不进入 HAP。

因此：客户原始审计证据中仍可追溯到凭据型命中；11.6.2C 允许输入范围和 Release HAP 范围内不存在凭据、账号、网络动作或外部命令。

## 缺失引用处置

`ime.android.ini` 共解析 38 条文件引用：15 条已解析；23 条缺失引用全部已有稳定决定且均不阻断转换：

- DEFERRED 10：暗词库、纠错、英文补全、引导等未交付可选资源；保留证据，等待后续客户交付，不创建伪数据。
- REJECTED 13：动态用户路径 8、Android 平台引用 1、旧系统表 2、通配符 2；不读取、不扩展、不转换。
- 目录外引用：0；大小写/规范化冲突：0。

## 功能分流与授权

延期：拼字、完整符号组、全部直通、简繁转换、暗词库、纠错、英文补全、快符、日期时间动作、成对符号动作和光标动作。

拒绝：外部程序/shell、网络/URL/FTP/WebDAV、账号或凭据、Android Intent、无法映射的平台键码、绝对路径访问、动态脚本、通配符和未知命令。

授权元数据按用户 2026-07-22 明确指示冻结：文件为客户提供，允许项目清理、转换、验证、产品使用及 HAP/客户交付；`source_owner=customer_provided`。接收日期没有证据，记录为 `unknown_not_required_by_user_direction`，不伪造日期或许可证编号，也不构成技术阻断。

## 原始数据和 Release 边界

- 两次独立正式审计均核对 28/28 文件相对路径、数量、大小和 SHA-256，全部未变化。
- 原始目录没有新增缓存、报告或生成物；工具不跟随源目录符号链接、不执行配置或命令、不访问网络。
- 10 个机器输出两次逐字节一致，Manifest、合同和脱敏配置 SHA-256 一致。
- Release 门禁拒绝原始 `.txt/.ini`、fixture/code-table 测试资源、凭据命名文件和审计报告。
- 实际 Release HAP 内容扫描通过：11,796,320 bytes，SHA-256 `E27283BCE6273E35B57DFC0E7FC37B426E32CEDFE832B570CCC9151022686B3D`。
- 小鹤双拼算法、排序和默认方案未修改；`xiaohe-yinxing` 只接入 Rust/FFI 与 `internalDebug` 正式包验收链路，尚未开放产品 UI 或 Release 入口。

## 最终验证

- `cargo fmt --all --check`：PASS。
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`：PASS。
- `cargo test --workspace`：PASS；包含正式包 23 项快照、完整损坏矩阵、Rust/FFI 跨层回归、19 项转换器单元测试和全部既有小鹤双拼回归。
- 正式审计复核：PASS，28/28 原始文件构建前后不变；manifest 和合同哈希保持冻结值；阻断项为空。
- 确定性重复生成：PASS，15/15 输出文件逐字节一致。
- 正式 bundle 完整性/兼容性：PASS；旧 fixture 41 项运行时集成测试保持通过。
- Debug 正式查询：PASS；覆盖单码至四码、精确/前缀、分类与来源顺序、去重、空/无结果、39 项大重码翻页、退格/reset、非法/超长输入和损坏资源回退。
- Release 资源正向/负向门禁：PASS。
- 实际 Release HAP 内容扫描：PASS，11,952,684 bytes，SHA-256 `4034F1EFEF559BC3A004119410966684B88FD0AA2BFF45DB00857C4612CC7A77`；包内 rawfile 仅有 `production.lex`。
- JSON、SHA-256、版本不兼容、篡改、截断、缺失文件、绝对路径和敏感内容检查：PASS。
- Release 性能（5 个独立新进程，OS 文件缓存未控制）：加载 P50/P95 `631.64/658.1578 ms`，逐查询 P50/P95 `2.14/16.16 μs`，峰值工作集 `114,237,440 bytes`。
- x86_64 HarmonyOS 6.1 模拟器真实 ArkTS → C++ → Rust 链路：强停重启前后两轮 A～J 全 PASS；Debug HAP 40,387,851 bytes，SHA-256 `712DD5051B70D181BD178CD75755F38104F0DD5F03C0D6359EDAE0E028FB2CB9`。

11.6.4 复验：`cargo fmt --all --check`、全 workspace Clippy 和 `cargo test --workspace` 全 PASS；ArkTS 288/288 PASS；双 ABI Native、Debug/Release HAP、Release 正负门禁和 28/28 正式来源不可变审计 PASS。x86_64 模拟器在 `2880x1920` 下两轮 A～J 全 PASS。Debug HAP 40,392,164 bytes/SHA-256 `04222CD447734DE05B8B76C2ACD5A4C663210E3F4CFCB30BE7E3C97E371E83B9`；Release HAP 11,956,076 bytes/SHA-256 `30B0F2742A5AABC6ED7FA65C77C35AA03B520AF38908D1F62288766E0967EAF3`，rawfile 仍仅 `production.lex`。

11.6.3 已完成模拟器设备验收和性能 P50/P95；尚未执行真实物理设备与产品 UI 验收。正式 bundle 仅由 Debug 构建临时注入并在构建后清理，不进入 Release HAP、产品设置或默认方案。

## 阶段结论

```text
11.6.2B = COMPLETED
11.6.2C = COMPLETED
11.6.3 = COMPLETED
11.6.4 = COMPLETED
11.6.5 = COMPLETED
11.6.6 = RUNTIME COMPLETED
11.6.6 PRODUCTION DATA = PARTIALLY DEFERRED
11.6.6 EDITOR-SIDE DEVICE ACTION ACCEPTANCE = COMPLETED
11.6.7 = COMPLETED
```

下一步：修复 11.6.9 密码安全布局和设备验收脚本，补齐 signed Release 独立
TextInput、ARM64 物理真机、设备性能及完整稳定性/应用矩阵后复验。正式动作数据
（快符、引导、日期时间、成对符号）仍待上游补齐。
