# 更新日志

## 2026-08-19（0.4.0 客户测试版）

- 正式应用版本升级为 `0.4.0`（`versionCode=4000000`）。
- 本版本交付四个正式拼音档案（17/26 键小鹤双拼、26 键全拼、9 键拼音）、小鹤音形 17/26 键、六项直通编码、分类及用户词库管理。
- 纳入全拼 V2 全领域词库、9 键候选质量优化，以及小鹤音形只读映射、共享索引和校验回执带来的冷启动与内存优化。
- 已生成 signed Release APP；外层 APP 与独立 signed HAP 的 SHA-256 签名验证均通过，嵌入 Profile 为 `release/app_gallery`，包内元数据为 `release`、`debug=false`。AGC 在线软件包基础检测需在上传后完成。

## 2026-08-19（小鹤音形冷启动与内存优化）

- 正式 `.hsyx` 加载改为只读文件映射、流式 SHA-256 和流式 archive content hash，移除多次 26 MB 堆复制；冻结完整 SHA 命中后不再重复扫描 trace JSON、逐 archive SHA 和第二次全包 SHA，损坏/非冻结资源仍走详细结构化诊断。
- 码表词典不再保留查询未使用的逐条 `sources`/`syllables` 分配；同一未变文件在 engine handles 间共享一个弱缓存不可变索引，最后一个 handle 销毁后仍可释放。
- ArkTS 安装器增加绑定 SHA/inode/size/mtime/ctime 的原子校验回执，避免每次进程冷启动重复哈希 26 MB 已安装文件；Native 加载边界仍校验冻结完整 SHA。Engine 与安装器日志新增毫秒级加载分段。
- Windows x86_64 Release 5 进程：加载 P50 `633.962 → 163.511 ms`、同进程复用 P50 `636.181 → 0.258 ms`、load 内存增量 P50 `59.20 → 15.59 MB`、峰值工作集 `147.39 → 46.47 MB`。当前 bundle 比历史基线更大，数据只作为趋势比较。
- 相关 Rust、严格 Clippy、ArkTS 单测与 `aarch64-unknown-linux-ohos` Release 构建 PASS。现场只有三台 x86_64 emulator，ARM64 真机时间/RSS 为 `NOT_RUN`；新增拒绝 emulator 的 `measure-yinxing-arm64.ps1` 采集器。证据见 `docs/evidence/2026-08-19-yinxing-cold-start-memory/README.md`。

## 2026-08-18（门禁漂移收口）

- 修正 `yinxing-converter` 分类顺序测试残留的 8 类时代索引断言，改为完整锁定当前正式 11 类顺序；`full-code-character` 的正式索引为 10。
- 删除仍把正式 `.hsyx` 视为禁止资源的 11.6.3 历史负向脚本；活动测试计划统一使用 11.6.8/当前 `verify-release-hap.ps1` 白名单规则，正式 `xiaohe-yinxing-production.hsyx` 必须存在且大小、SHA-256 正确，未知或篡改的 `.hsyx` 必须失败。

## 2026-08-18（26 键全拼候选质量 V3）

- 正式随包词库提升为 V2 `all_domains`，启用口语、专名、应用/品牌、科技、软件、教育、医疗、金融、法律和有效热词 131 个新增文本/读音对；正式词库为 3,751,923 bytes、SHA-256 `E4DEAD...D365`，安装缓存名升至 `production-v118.lex`。
- 新增 ≥5 音节正式长词的紧凑全拼精确索引，每次最多 8 项并置于同音短词拼接路径之前，修复已在词库的长词被解析路径和 decoder beam 截断的问题；不生成词库外文本。
- 评测汇总与 failures JSONL 统一拆分为 `target_unrecalled`、`recalled_outside_top5`、`ranking_error` 三类互斥失败，并新增每例清空模型的 1～5 次用户学习效果探针。
- 增加只接受自愿本地长度桶聚合的匿名分布校验和加权评测；闭合 schema 禁止原始输入、候选/编辑器文字、应用和用户标识，并显式报告未覆盖桶。仓库未收到真实匿名数据，示例不作为真实结论。
- V2 dev Top1/Top3/Top5 为 `97.917%/97.917%/97.917%`；旧公开 dev 300 条三类失败为 `94/5/15`，学习探针 20 个目标中 17 个提升、16 个升 Top1、0 个退化。相关 Rust、Clippy、ArkTS、词库、双 ABI Native 和 Release HAP 实包门禁 PASS；unsigned HAP 为 40,502,445 bytes、SHA-256 `1FEA7059263B8ADE7201BA74634E967FCCCAA6FA9465F87A7A10508D1C1429A1`。全量 ime-ffi 保留一项无关九宫格旧断言失败；全新 blind、真实匿名数据、设备和 HAP 真机安装未运行。

## 2026-08-14（26 键全拼有界拼写纠错与可配置模糊音）

- 新增编辑距离 1 的漏字、多字、固定对称 QWERTY 邻键和相邻错序纠错；新增八项音节级独立模糊音，所有功能默认关闭并受输入长度、变体、搜索节点、查询路径、句子解码和候选总量硬上限约束。
- 配置已贯穿 Rust、C ABI、N-API、ArkTS gateway/coordinator、设置持久化、schema 迁移、设置页、冷启动恢复和事务失败回滚；interface/ABI 升至 `9`，settings schema 升至 `7`，engine version 为 `0.0.1-quanpin-features`。
- 扩展冻结集评测器，支持 dev/blind 隔离、显式功能开关、每样本 fuzzy 选项、指定新输出、冻结哈希拒绝、三轮完整候选指纹和安全/扩张统计；默认全关指纹与改进前完全一致。
- 冻结全量 Top5 `63.551% → 68.224%`，typo Top5 `0% → 28.333%`，fuzzy Top5 `7.5% → 87.5%`；实现冻结后的唯一 blind 三轮 Top5 为 `66.623%`，三轮确定且安全计数全 0。
- fmt、严格 Clippy、相关 Rust/FFI、ArkTS、双 ABI Native 和默认产品 debug HAP PASS；workspace 仅保留已知无关 `yinxing-converter` 分类索引失败。纠错 P95/P99 延迟明显回退且设备验证未运行，均作为未达项保留。

## 2026-08-13（客户六项直通编码）

- 正式小鹤音形引导区加入受控生产动作：`;f` 重复上屏、`;i` 安全撤销、`;o/;p/;h/;j/;k/;l` 成对符号居中、`;n` 当前行末定位；Rust、C ABI JSON、C++ Node-API、ArkTS Gateway/Executor 和输入会话已完整接通。
- 撤销先核对光标前文本且限制为刚提交后的 5 秒窗口；行末功能通过有界文本查询和绝对光标定位实现 End 的编辑效果。任一编辑器能力失败或会话变化均安全失败。
- 新增 `category.set` 完整分类集合命令，使不同分类的启用/关闭在一次设置事务中提交；保留必需 `core` 分类和未知分类整次拒绝规则。
- 固定来源用户词库接入正式管理页，支持授权来源、优先级、启停及 MERGE/APPEND/REPLACE；修复设置迁移丢失来源、导入绕过 revision/CAS、APPEND 丢失原词库和启动发布字段颠倒问题。
- interface/ABI 升至 `8`，engine version 为 `0.0.1-direct-actions`。Rust workspace、Clippy `-D warnings`、ArkTS 单元测试、双 ABI Native Release、Release HAP 和内容门禁 PASS；unsigned HAP 为 `38,843,948` bytes，SHA-256 `EF432ECECD186EB3A14F2B09BB481D63413EA9FC183D48311141DE8E88F4D8DF`。设备专项为 `NOT_RUN`。

## 2026-08-13（26 键全拼和 9 键拼音阶段 5：联合验收与发布收口）

- 新增四档案联合切换、配置迁移、Native/持久化失败回滚测试；同 `xiaohe` engine 的 17/26 布局切换现在也必须 reset 并清空组合，跨进程 profile 同步不再只比较 scheme。
- 修复全拼单字母 `n` 被精确“嗯/唔”截断的问题：Rust 构建有界预计算单字母前缀池，恢复“你/那/能”等候选；ArkTS/C++ 未加入拼音业务规则。
- 更新两项已过期的标点测试基线，使其验证已冻结的虚拟逗号独立动作和实体标点单次提交合同；未修改产品标点实现。
- Rust workspace `505/505`、candidate baseline `4/4`、T9 `6/6`、FFI `31/31`、ArkTS `440/440`、fmt、Clippy、双 ABI Native、Release HAP 和实际包内容门禁 PASS。
- x86_64 Phone 竖屏与 Pad 横屏 signed Release 的独立第三方包完成全拼 `nihao`、T9 `64426`、双拼回归、档案切换和部分生命周期/编辑器策略验收。ARM64 真机、真实浏览器/聊天应用、旋转/分屏、设备性能/RSS/soak 为 `NOT_RUN`。
- 阶段状态为 `IMPLEMENTED / HOST_VALIDATION_COMPLETED / DEVICE_VALIDATION_PARTIAL`。全拼主机完整引擎性能相对历史质量修订前基线回退，且空 `.git` 目录使既有候选基线刷新来源无法审计，均保留为阻塞；详见 `docs/PINYIN_STAGE5_FINAL_ACCEPTANCE.md`。

## 2026-08-12（9 键拼音阶段 4：传统九宫格界面与交互）

- 正式启用 `pinyin-9` 键盘档案，并加入 `1/2～9/0` 四排 3 列九宫格和“中/空格/动态动作键”共享底栏；英文继续使用既有 QWERTY。
- 新增 ArkTS `T9_PINYIN_DIGIT` 专用动作。中文九键的 `2～9` 只能经过 `KeyboardController -> InputSessionController -> EngineCoordinator.processKey` 进入阶段 3 Rust T9 引擎，不会作为普通数字提交，也不在 ArkTS/C++ 展开字母。
- 候选栏使用 Rust `currentPinyin` 展示当前路径；新增独立横向拼音组合栏，保持 Rust 发布顺序并通过既有 `selectPinyinCombination` 跨层选择和刷新汉字候选。
- `1` 进入既有符号模式，`0` 调用 Rust 显式分音，`符/123` 进入既有真实数字键盘；删除、空格、动态动作键、中英文和输入框策略复用正式控制链。
- 九键键帽接入现有主题、按压态、震动、音效、数字＋字母组预览和无障碍文案；面板高度复用动态 `KeyboardMetrics`，覆盖 Phone/Pad 横竖屏的有界主机计算。
- 新增布局、动作、组合顺序、当前拼音、数字模式隔离、持久化恢复、完整输入/选择/分音/删除/空格和隐藏/显示清理回归。ArkTS `434/434`，T9/parser/engine/FFI 定向回归 PASS，Release HAP 与内容门禁 PASS。
- unsigned Release HAP 为 `38,739,216` bytes、SHA-256 `AB4B9B6B9BB5DB573A9F1FA3D80F29F95D9EAF75D849AE55F0976DEF3C529863`。interface/ABI 保持 `7`，本阶段未修改 C++/Rust/Node-API/C ABI。
- 全 Rust workspace 仍被既有小鹤冻结候选基线不一致阻塞；模拟器、真机、旋转/分屏、三方应用和长时压力均为 `NOT_RUN`，因此阶段状态为 `IMPLEMENTED / HOST_VALIDATION_PARTIAL`。详见 `docs/PINYIN_STAGE4_KEYBOARD_UI.md`。

## 2026-08-12（9 键拼音阶段 3：数字引擎与消歧）

- 新增 Rust `T9SyllableIndex` 与 `T9PinyinParser`：标准 2～9 映射、合法音节数字 Trie、有界动态规划、未完成前缀、显式分音、删除恢复和最多 32 路稳定标准拼音组合；运行时不做指数级字母展开或全音节扫描。
- `ImeEngine` 正式支持 `schemeId=pinyin-9`，复用词库精确/前缀查询、整句解码、稳定候选去重/排序、分页、部分提交和用户学习。自动学习以 `pinyin-9` 隔离，人工规则使用 `p9` 标准拼音命名空间。
- 新增 `ime_engine_select_pinyin_combination`、Node-API `selectPinyinCombination` 和 ArkTS gateway/coordinator 透传；interface/ABI 同步升级为 `7`，engine version 为 `0.0.1-pinyin-stage3`。
- 集中冻结 raw 64 位、单音节深度 6、每偏移 32 路、每起点 512 状态、32 个拼音组合、65 个前缀缓存和 256 个候选快照上限。
- 专项验证覆盖 `64 → ni/你`、`64426 → ni'hao/你好`、多组合选择、分音、删除、重置、分页、方案切换、学习隔离、64 位高碰撞输入、确定性重复和真实 FFI 链路。
- Release 基准：`64426` 候选刷新 P50/P95 `0.282/0.535 ms`；64 个连续 `6` 逐键输入 P50/P95 `411.041/444.066 ms`，摊销约 `6.42/6.94 ms/键`。
- ArkTS 测试、CMake/NAPI、双 ABI Native、unsigned Release HAP、资源门禁和 HAP 内容校验均 PASS。HAP 为 `38,719,780` bytes、SHA-256 `BE630BCBAB7234B936933E93ACF12C1C754B1D30AEAE71F920C86E3785C70CCA`。
- 阶段状态保持 `IMPLEMENTED / HOST_VALIDATION_PARTIAL`：冻结 `sentence-baseline.json` 与当前 `production.lex` 的既有小鹤 `nihc`/`uurufa` 排序仍不一致，未擅自更新基线；设备项均 `NOT_RUN`。阶段 4 UI 未提前启用，`pinyin-9` 档案保持禁用。

## 2026-08-11（全拼候选提交、浮窗分页与英文残留修复）

- 修复全拼部分选词后沿用旧候选快照的问题：例如 `nishizgyisi` 选择“你是”后，剩余 `zgyisi` 会重新独立查询，不再继续显示并允许重复选择旧“你是”。
- 桌面候选页由 9 项调整为 7 项；浮动候选窗取消 `560vp` 固定宽度上限，按当前 7 项的实际编号、文字、间距和字号计算完整宽度，最终只由屏幕安全区限宽，超出时仍可横向滚动。
- 修复不支持原生 TextPreview 的浏览器输入框中，光标已更新但文本查询仍滞后一帧时被误判为组合脱离的问题，避免已输入拼音偶发固化为英文前缀；新增 `sousuohuoshuru → 搜索或输入` 全程不提交 ASCII 的回归。
- engine version 升至 `0.0.1-pinyin-stage2-quality4`。
- 浮窗后续按视觉反馈继续收紧：根容器左右内边距由 `12vp` 改为 `6vp`，候选按钮自身点击内边距保持不变。宽度估算进一步区分窄数字前缀、ASCII 字母和全 em 中文字符，修复短词校准误缩长中文候选、导致第 7 项被遮挡的回归。
- 2in1 正式输入法实测：短页 `jint` 为 `969px`、左右留白各 `27px`；长页 `jintianshige` 自动扩展为 `1341px`、左右留白 `27/28px`，第 7 项完整宽度 `174px`，7 项全部在窗口边界内。
- Rust `ime-engine` 全套 109 项、`ime-ffi` 30 项、fmt/Clippy、ArkTS 全量测试、双 ABI Native Release、unsigned/signed Release HAP 和内容门禁均 PASS；最终 signed HAP 为 `38,600,568 bytes`、SHA-256 `722B932A7A0D3165C3CAC70572198F871490D87B5E63307D3A96D6BC6EB8E61F`。
- HarmonyOS 6.1 / API 24 / x86_64 2in1 已安装 signed Release 并通过完整电脑端候选窗验收；额外验证部分提交后旧候选消失、剩余编码重查，以及系统浏览器在 450 ms 逐键间隔下仍保持整段中文组合。Phone/Tablet 与 ARM64 本轮专项未重跑。

## 2026-08-11（26 键全拼三端词库身份修复）

- 将运行时正式拼音词库身份同步为 `3,741,248` bytes、SHA-256 `E14B9FA5546686CB3C7516C8494DD7BF014D4E525D64F08DE0BB6C8DEE721390`，修复手机、平板和电脑端选择 `26 键全拼` 后因词库安装校验失败而无法输入的问题。
- 安装文件名由 `production-v115.lex` 升级为 `production-v116.lex`，确保应用升级后不会复用上一版缓存词库；资源身份不匹配时补充明确错误日志。
- Release 资源门禁新增源词库与 HAP 内词库的大小及 SHA-256 双重校验，并加入同大小内容篡改的负向测试；内部调试安装器和阶段 11.5 HAP 校验同步新词库大小。
- ArkTS 单元测试/编译、全拼 Rust 专项 `14/14`、Release 资源门禁正负向测试、unsigned Release HAP 构建与内容门禁均 PASS；HAP 为 `38,435,876` bytes，SHA-256 `22BF740B8AFD7A0B39E2AB3A060EB8DFDB2BB0089A29B8B302EAA31E5FCD4389`。

## 2026-08-10（26 键全拼阶段 2：实体键盘快速输入性能修复）

### 延迟与长组合

- 全拼不再为每个字母解码最多 32 条完整切分路径：12 字母以内最多解码 4 条，长组合只解码首选路径；协议仍返回有界拼音组合供展示和短输入消歧。
- 已覆盖且不含 fallback 的全拼组合达到 24 个字母后，在下一个字母到来时自动提交首选中文段并把该字母作为新段首键重放；64 字母硬上限在无法安全收口时保留原组合并拒绝继续增长，不再让解码错误清空候选后误把整段原始字母作为正文结束。
- 支持 `TextPreview` 的编辑器中，`quanpin` 正式使用原生预编辑范围；不支持的编辑器在快速追加时只插入新增后缀，不再重复选择并重写整段 raw input。
- 实体按键与逐键组合成功日志从 info 降为 debug，避免 Release 快速输入热路径同步写高频信息日志。
- interface/ABI 保持 `6`，engine version 升至 `0.0.1-pinyin-stage2-perf1`。

### 验证

- Release 完整引擎基线的四组输入共 1,620 键、0 失败、20 次中文自动收口、0 次 ASCII 自动提交，平均 `2.027 ms/键`；修改前同组单轮平均为 `82.359 ms/键`，约提升 40.6 倍。46 字母长输入由 `122.714 ms/键` 降至 `2.002 ms/键`，约提升 61.3 倍。
- 全拼专项 `5/5`、`ime-engine` 全套、`ime-ffi 29/29`、Rust fmt/Clippy、ArkTS 全量测试、双 ABI Native Release、unsigned Release HAP 与内容门禁均 PASS。
- x86_64 Native archive：26,286,096 bytes，SHA-256 `C7C3B5AB28845F64AD0194D9703F36D29F9B560D4B47A27C5F949E2789E6C36D`；arm64-v8a：26,792,052 bytes，SHA-256 `B9B442E4A32860ADA729C63035FE9EC0C4E1BB5F993B30A0651617AF07300ECE`。
- unsigned Release HAP：38,261,216 bytes，SHA-256 `98DFB338B502055FBE87D69F165F73B5BD4E07B7A83F6E5FD5EF5A6CD5AC343F`。实体键盘设备复测仍为 `NOT_RUN`。

## 2026-08-10（26 键全拼和 9 键计划阶段 2：26 键全拼完整链路）

### 引擎与候选

- 新增 Rust `QuanpinParser`，由合法拼音音节 Trie 和有界动态规划解析连续全拼，支持未完成尾音、`'` 显式分音、`xian/xi'an` 多路径与逐键退格恢复。
- `ImeEngine` 和 FFI 正式支持 `quanpin`，复用精确/前缀查询、整句解码、候选分页、部分提交和用户学习；全拼整句候选按实际拼音字母计算已消费原始码长度。
- 自动学习使用 `quanpin` 方案命名空间；人工用户词库的全拼规则使用 `qp` 前缀，与既有双拼 raw code 隔离。
- interface/ABI 保持 `6`，engine version 升至 `0.0.1-pinyin-stage2`。

### 档案与界面

- 正式启用 `quanpin-26`，复用 QWERTY 中文布局；`pinyin-9` 继续保持禁用。
- 设置页和空闲工具栏统一按 `KeyboardProfile` 展示/切换，工具栏能正确显示“26 键全拼”并持久化档案。
- 候选栏直接展示 Rust 返回的全拼音节段，ArkTS/C++ 未增加拼音切分、消歧或排序逻辑。

### 验证

- 全拼解析器、`ime-engine` 阶段 2 集成测试、Rust workspace 全量测试（含 `ime-engine 42/42`、`ime-ffi 29/29`）、fmt/Clippy、ArkTS 全量测试、双 ABI Native Release、unsigned Release HAP 与内容门禁均 PASS。
- Release 性能基线为 160,000 次解析/13,858 ms，平均 `86.616 µs/parse`。
- unsigned Release HAP 为 `38,256,044 bytes`，SHA-256 `CD9D5003E91C5426FA56FF11E53F5C9917C7AB499A7CC5946CCE56C1E37AEAD0`；设备专项为 `NOT_RUN`。
- 阶段说明见 `docs/PINYIN_STAGE2_QUANPIN_26.md`。

## 2026-08-10（26 键全拼和 9 键计划阶段 1：键盘档案与通用协议）

### 配置与迁移

- 新增统一 `KeyboardProfile`，以稳定档案 ID 绑定输入方案、触屏布局、引擎方案和能力；设置 schema 升至 `5`，`keyboardProfileId` 成为唯一真实来源。
- 旧 17/26 键偏好迁移为 `xiaohe-17` / `xiaohe-26`，并保留小鹤音形对应布局；未知或未启用配置安全回退到 `xiaohe-26`。
- `quanpin-26` 和 `pinyin-9` 已登记但在后续引擎完成前保持禁用；旧布局控制器不再独立持久化。

### 引擎与协议

- Rust 新增通用 `PhoneticParser` 边界和小鹤双拼适配器，展示分段从协议层迁入解析器，取消协议默认两码切段假设。
- `CompositionResult` 新增 `currentPinyin` 和 `pinyinCombinations`；C++ 仅校验转发，ArkTS 仅保存展示。
- ArkTS interface 与 Rust ABI 同步升至 `6`，engine version 升至 `0.0.1-pinyin-stage1`；旧 interface `5` 创建请求被明确拒绝。

### 验证

- 键盘档案/迁移、解析适配、组合、删除、候选提交、分页、方案切换和跨层字段回归 PASS；候选文字、顺序和行为基线不变。
- ArkTS 全量单元测试、Rust workspace/fmt/Clippy/确定性门禁、x86_64 与 arm64-v8a Native Release、unsigned Release HAP 构建均 PASS。
- unsigned Release HAP 为 `38,040,556 bytes`，SHA-256 `69E14BD027E8B700753104E7E0522B784555A9D33ABAAB2A1ACCE2B2A4501E68`。模拟器与真机专项为 `NOT_RUN`。
- 阶段说明见 `docs/PINYIN_STAGE1_KEYBOARD_PROFILE_AND_PROTOCOL.md`。

## 2026-08-10（0.3.0 客户测试版）

- 正式应用版本升级为 `0.3.0`（`versionCode=3000000`）。
- 本版本交付当前小鹤音形精准输入合同，包括无精确项时的受限精准提示和既有空码正向/反向切分规则。
- 纳入 Phone、Tablet、2in1 输入形态、17/26 键双拼 UI、直通控制、八类词库开关和用户词库批量管理。
- 26 键全拼与 9 键输入延期至 `0.4.0`。

## 2026-08-10（阶段 12：直通控制与用户词库管理）

### 直通功能

- 新增封闭的 `scheme.set`、`category.enable/disable/toggle`、`category.all/core` 和 `status.get` 命令合同；命令行通过 `EntryAbility` Want 参数执行，实体键盘新增严格 `Ctrl+Alt+0～9` 高频预设。
- 快捷键、命令行和设置页统一进入 `SettingsController`，复用方案资源校验、分类规范化、持久化、回滚和跨进程同步；音形引擎未运行时也可预配置分类，`core` 始终启用。

### 用户词库

- 正式设置新增用户词库管理页：添加个人词、精确隐藏系统词、固顶、指定第 N 位、搜索多选、批量改动作/移除，以及多行文本合并/覆盖导入和导出。
- Rust 新增结构化读取、revision CAS 原子保存和运行时热重载；多窗口旧版本保存返回 `revision_conflict`，保存或恢复失败不替换最后一个有效快照。
- 保存后当前引擎直接重载；主进程把词库按不超过 DataProxy 单值上限的块发布到本包 `SHARED_CONFIG`，最后切换 manifest，输入法独立进程在热更新和冷启动时先镜像到自己的沙箱文件再原子重载。Common Event 只负责唤醒，不承载可能很大的批量词库内容；系统 bundle 和用户学习模型保持独立。
- 修复三设备验收发现的两个跨进程问题：设置快照改为所有进程以 `SHARED_CONFIG` 为 canonical，主进程监听运行时变更；输入法启动立即注册系统事件并在词库镜像 Promise 后顺序回放，避免 Phone 以外的较快 `inputStart` 丢失。用户词库编码输入框固定为原始 ASCII 输入类型，避免编码被中文输入法转换。
- 用户词库页面接入设置窗口统一安全区，标题和返回按钮避开状态栏及挖孔；关闭页面 Scroll 和词条 List 的视觉滚动条，保留手势滚动。设置主页同时移除页头“本地设置”说明、双拼方案说明和用户学习说明。Phone Release 实机布局及滚动截图验证通过。
- ArkTS interface、Rust ABI 升至 `5`，engine version 升至 `0.0.1-stage12`。新增 C ABI/Node-API `reloadUserLexicon`、`loadUserLexicon`、`saveUserLexicon`。

### 验证

- user-lexicon `23/23`、ime-engine lib `42/42`、ime-ffi `29/29`、ArkTS `395/395`、Rust workspace/fmt/Clippy、双 ABI Native Release 和内容门禁均 PASS；最终 unsigned Release 为 `37,984,852 bytes`、SHA-256 `42c92678ddeffde84ec2ea72f5a04203c95db2a474435ac87e5d38103daa36d9`，signed Release 为 `38,123,521 bytes`、SHA-256 `f2302e707882e6ebc3e30841382b80dde11db7c790b802f4ab25a3cb00f78c40`。
- HarmonyOS 6.1 / API 24 / x86_64 Phone `1320×2856`、2in1 `3120×2080`、Tablet `2880×1920` 三设备完成真实 `aa` 命令、物理 `Ctrl+Alt+数字`、强停持久化及用户词库 UI/热重载/冷启动闭环。三台输入 `ni` 均验证固顶为第 1、普通词为第 2、指定词为第 3，删除规则使系统词“你”不可见。证据见 `docs/evidence/2026-08-10-stage12-three-device/README.md`。
- 设计决策见 `docs/adr/0024-direct-control-and-user-lexicon-management.md`，阶段说明见 `docs/STAGE12_DIRECT_CONTROL_USER_LEXICON.md`。

## 2026-08-06（UI与交互优化阶段）

### 设置页
- 设置页“电脑端键盘显示”选项的文案从“自动”、“始终使用实体键盘”、“始终显示虚拟键盘”简化为“自动”、“实体键盘”、“虚拟键盘”。

### 候选窗
- **修复**：当选择“候选窗在输入框下方”时，抑制候选词在顶部候选栏区域短暂闪现，消除视觉延迟和双重渲染的问题。

### 虚拟键盘
- 26键中文模式空格行（最下行）布局对齐17键布局，将原 `#+=` 符号切换键替换为中文标点键 `，。`。英文模式保持不变。
- 虚拟键盘中文模式空格左侧新增标点/次选键，无候选时输入标点，有候选时作为次选上屏键（提交第2候选）。

### 实体键盘
- 新增分号（`;`）处理逻辑：当有候选词时（候选数≥2），按分号作为次选键（提交第2候选）；无第二候选时，作为符号引导键。支持通过引导映射表快速输入常用符号。
- 新增单引号（`'`）处理逻辑：当有候选词时（候选数≥3），按单引号作为三选键（提交第3候选）；否则保持分段边界（Segment Boundary）功能。

## 2026-08-06（移动端候选位置阶段 1：输入框下方候选窗）

### 设置与交互

- 设置页“候选窗位置”调整为手机和平板用户可直接选择的两项：`候选栏 / 输入框下方`；历史 `AUTO` 值在触屏端兼容显示为“候选栏”，升级后不改变既有默认界面。
- 选择“输入框下方”后，候选跟随宿主 `cursorContextChange` 光标锚点显示，优先位于光标下方、空间不足时回退到上方，并按屏幕安全区和固定软键盘顶边夹紧。
- 浮动候选沿用既有候选字号、主题、实际可见候选、分页状态、精准匹配后缀和 `commitCandidate(index)` 提交链；候选提交、组合清空、隐藏键盘、切换输入框或会话结束后立即隐藏。

### 面板共存与回退

- Phone/Tablet `TOUCH` 模式使用独立 `PanelType.STATUS_BAR` 承载输入框下方候选窗，不进入 `SOFT_KEYBOARD` 唯一所有权队列，因此可与底部 `FLG_FIXED` 软键盘同时存在；2in1/实体键盘继续使用既有 `SOFT_KEYBOARD + FLAG_CANDIDATE` 路线。
- Pad 历史“侧面候选条”不再作为 `FLOATING` 的触屏解释；独立候选窗真正可见前仍保留顶部候选内容，缺少有效光标锚点、SDK 能力不足或面板创建/显示失败时安全留在候选栏。
- 设置仍复用 schema 4 的 `candidatePresentationMode` 和既有跨进程同步，不新增权限、Native ABI、词库或排序变化。

### 验证

- ArkTS 全量 `383/383 PASS`；internalDebug 与 unsigned Release HAP 构建 PASS。internalDebug 为 41,262,403 bytes/SHA-256 `f06ea913c00f6d1ad2d77f207dadc80630da0c3cf58ccca72d4e22b8e9f2c75d`；unsigned Release 为 37,852,688 bytes/SHA-256 `aedbe6803ed16b8fbcea171eaea5807694a2c3b86a22c36d74d9c6e969ea8ccf`。
- HarmonyOS 6.1 / API 24 / x86_64 Phone `1320×2856` 与 Tablet `2880×1920` 模拟器均验证固定软键盘和输入框下方候选窗共存、窗口位于光标下方、候选点击提交并收起。ARM64 实体设备、三方应用矩阵、旋转/分屏和 2in1 本阶段专项重跑为 `NOT_RUN`。
- 完整阶段报告见 `docs/evidence/2026-08-06-touch-candidate-placement-stage1/README.md`。

## 2026-08-06（电脑端整改阶段 5：产品化收口与候选窗自适应）

### 候选窗反馈修正

- 电脑端浮动候选窗删除组合字母和候选编码提示，只保留编号与候选词；输入字母继续由宿主输入框显示，不再在候选窗重复出现。
- 新增可测试的候选窗宽度估算，按实际可见候选数量、文字长度、字号和分页状态在 `72～560 vp` 内自适应。2in1 设备输入单码 `s` 时仅显示 `1. 三 / 2. 所有`，候选窗实测约 `162.6 vp`，不再保留历史 `280 vp` 空白。

### 阶段 5

- 设置 schema 升至 4，新增 `AUTO / 始终使用实体键盘 / 始终显示虚拟键盘`。AUTO 将 2in1 和连接字母实体键盘的 Tablet 解析为 `HARDWARE`，其余设备解析为 `TOUCH`。
- 输入法运行时监听跨进程设置和实体键盘设备变化，使用统一软键盘所有权队列在固定键盘/候选窗之间串行切换。2in1 实测 `HARDWARE -> TOUCH -> AUTO/HARDWARE` 切换成功，无破坏性清组合。
- 正式模块设备声明加入 `2in1`；新增阶段 5 自动测试与 `scripts/accept-computer-stage5.ps1`。
- ArkTS `384/384 PASS`，internalDebug、default Debug、unsigned/signed Release 和内容门禁 PASS。signed Release 为 38,008,487 bytes/SHA-256 `b6f5cef6bcd9a0dbb5b478a302c03b4e510040ad31dd86224bf8822537a92da4`。
- signed Release 在 API 24 / x86_64 2in1 模拟器的独立 ArkUI 宿主和系统浏览器闭环 PASS。真实 USB/蓝牙键盘、ARM64 2in1、Phone/Tablet 本阶段设备专项重跑和 AGC 上传检测为 `NOT_RUN`。报告见 `docs/evidence/2026-08-06-computer-stage5/README.md`。

## 2026-08-05（电脑端整改阶段 4：正式浮动候选窗闭环）

### 候选窗与定位

- 解除阶段 4 正式门禁，2in1 `HARDWARE_READY` 现在使用路线 A `SOFT_KEYBOARD + FLAG_CANDIDATE`；缺少候选面板/光标能力、无有效会话或锚点时安全回退/隐藏，Phone/Tablet 触屏路径保持不变。
- 候选窗补齐组合编码、编号候选、选中态、分页状态和精准匹配后缀，按候选内容在 `280～560 vp` 内动态定宽；鼠标点击映射回原候选索引并复用正式提交链，提交中的重复点击被拦截。
- 光标锚点、候选内容、窗口移动/缩放均触发 resize/move；配置变化立即废弃旧锚点，在新锚点到达前隐藏，避免候选窗停留在过期坐标。Store 可见性回写与决策日志增加去重，减少重复 reconcile/move 和日志噪声。

### 生命周期与验证

- HARDWARE 展示模式成为电脑端正式路由依据，不再被异步物理键盘枚举或旧“候选位置”设置误降级；提交、Esc、组合清空、应用/输入框切换和 `inputStop` 均隐藏候选，固定键盘始终缺席。
- 更新阶段 4 policy/runtime 自动测试，覆盖能力门禁、create/content/resize/move/show/hide、显示失败安全回退、旧锚点失效、配置变化和动态内容尺寸；ArkTS 全量 `378/378 PASS`。
- 新增 `scripts/accept-computer-stage4.ps1` 与本地浏览器测试页。API 24 / x86_64 2in1 的 ArkUI、系统浏览器、鼠标/数字键、Esc、焦点、窗口移动/缩放和应用切换闭环 PASS；Phone/Tablet/2in1 模拟器矩阵 PASS。
- default unsigned Release 内容门禁 PASS，37,857,196 bytes/SHA-256 `7f8ce1bdd168033640b15a8eea8b9f12ea32707a4bcc5fd279e840198b89d7eb`；internalDebug 为 41,270,408 bytes/SHA-256 `fbb29fdba9d01add815da1fb7d0352de6db7dbc4b2312c410469cb1151021d06`。真实 USB/蓝牙键盘、ARM64 2in1 和 signed Release 专项为 `NOT_RUN`。
- 完整报告与原始证据见 `docs/evidence/2026-08-05-computer-stage4/README.md`。

## 2026-08-05（电脑端整改阶段 3：实体键盘完整输入闭环）

### 实体按键合同

- 正式物理按键路由补齐 Esc、四方向、PageUp/PageDown、小键盘数字和无 `unicodeChar` 回退。中文无组合时仅 A-Z 开始组合；有组合时才消费编辑、选词、取消和分页键；英文、URL、密码及 Ctrl/Alt/Logo 快捷键继续交还宿主。
- Esc 新增独立组合取消动作，清理宿主预览、Native 组合和 Store 候选状态，但不提交、不学习、不结束 `HARDWARE_READY` 会话。
- 左/上、右/下移动当前页 `highlightedIndex` 并在页边界夹紧；PageUp/PageDown 复用既有 Native 分页；Space/Enter 提交当前选中项，1-9 继续提交明确候选索引。
- 已消费的 DOWN/UP 现在成对拦截，重复 DOWN 串行执行。pending 快速输入保护避免字母动作尚未完成时紧随的 Space、数字或 Esc 泄漏到宿主；独立 generation 隔离快速换框后的旧完成回调。

### 验证

- 新增 `ComputerStage3PhysicalKeyboard.test.ets` 并加入 ArkTS 全量测试，覆盖消费边界、按下/抬起、无 Unicode、小键盘数字、重复键、快速连续输入、快捷键、方向选择、分页、取消和密码/英文直通；全量结果 `BUILD SUCCESSFUL`。
- HarmonyOS 6.1 / API 24 / x86_64 2in1 模拟器使用正式 default Release 与独立 ArkUI 宿主、系统浏览器完成闭环。中文首选、方向选中、Esc、无组合 Space/Backspace、URL、密码、PageUp/PageDown 路由和 10 轮快速输入全部 PASS；固定键盘零创建/零显示，fatal 扫描为空。
- internalDebug HAP 为 41,253,823 bytes/SHA-256 `507fe89b77d1d48c276cc375d98b7b7726f788d3970f816d624f80ba7a721e31`。default Release HAP 构建、设备安装及内容门禁 PASS，为 37,850,616 bytes/SHA-256 `87302bf1d071e65e4e5872ebd63a09b62e26fc42ddeb08213840ed04b2549e17`。
- 新增一键脚本 `scripts/accept-computer-stage3.ps1`；报告与原始证据见 `docs/evidence/2026-08-05-computer-stage3/README.md`。真实 USB/蓝牙键盘、ARM64 2in1、signed Release 电脑端专项验收、Phone/Tablet 本阶段设备专项重跑和阶段 4 正式候选窗为 `NOT_RUN`。

## 2026-08-05（电脑端整改阶段 2：HARDWARE_READY 与统一面板所有权）

### 会话与展示模式解耦

- 新增 `InputPresentationMode`、`InputPresentationPreference` 和 `InputPresentationState`。阶段 2 的 `AUTO` 规则为 2in1 使用 `HARDWARE`，Phone/Tablet 使用 `TOUCH`，同时保留阶段 5 接入显式偏好与外接键盘决策的稳定入口。
- `inputStart` 先建立会话和编辑器连接，再进入 `HARDWARE_READY` 或 `TOUCH_READY`。2in1 不创建固定面板，Phone/Tablet 继续执行原固定键盘创建、缩放和显示流程。
- 固定面板隐藏改用无副作用的 `handleKeyboardPanelHidden()` 只更新可见性；原 `handleKeyboardHide()` 的清预览、重置引擎和清组合语义只由触屏模式的系统 hide 事件触发。实体模式忽略系统 keyboard show/hide，不再误清组合或关闭活跃会话。
- internalDebug 的阶段 1 隔离探针退出自动激活，2in1 internalDebug 现在进入正式输入法生命周期，阶段 1 探针代码和历史证据保留。

### 唯一软键盘面板

- 新增统一 `SoftKeyboardPanelOwnershipCoordinator`，以单一异步队列协调 `FIXED_KEYBOARD` 和 `CANDIDATE_WINDOW`。所有权切换会先销毁并撤销旧面板，再允许新面板创建，保证正式运行中最多存在一个 `SOFT_KEYBOARD` 面板。
- 固定键盘控制器在进入实体模式时会释放既有固定面板，但不结束输入会话；候选窗控制器已接入同一所有权协调器，为阶段 4 的路线 A 实现准备互斥基础，正式浮动候选门禁仍未提前开启。
- generation 继续保护快速 inputStart/inputStop、重复 show/hide、创建中停止和 Ability 销毁；新增自动测试覆盖实体模式不创建固定面板、无破坏性 hide、触屏到实体切换及固定/候选串行所有权。

### 验证

- ArkTS 全量单元测试 PASS；internalDebug HAP 构建 PASS，41,228,911 bytes/SHA-256 `f14b024ff5cfdf56d03cc949f5f87ad8aa0271e1fc41cdd6e2e52e50120334cb`。
- HarmonyOS 6.1 / API 24 / x86_64 Phone、Tablet、2in1 模拟器矩阵 PASS。2in1 在 ArkUI `TextInput`、`TextArea` 和系统浏览器快速切换中始终为 `HARDWARE_READY`、`sessionActive=true`、`editorConnected=true`、`keyboardVisible=false`，且没有固定面板创建或显示；Phone/Tablet 保持 `TOUCH_READY` 和固定键盘可见。
- default unsigned Release HAP 构建及内容门禁 PASS，37,842,068 bytes/SHA-256 `21ccc491d7ec632536c41487bd05d95d23e8e11d6465c6cf390bdaf7f2cac591`。真实 USB/蓝牙键盘、ARM64 2in1 和 signed Release 电脑端验收为 `NOT_RUN`；阶段 3 完整实体按键合同和阶段 4 正式候选窗未提前声明完成。
- 新增一键矩阵脚本 `scripts/accept-computer-stage2.ps1`；报告和原始证据见 `docs/evidence/2026-08-05-computer-stage2/README.md`。

## 2026-08-05（电脑端整改阶段 1：2in1 能力验证与路线 A 冻结）

### 隔离能力探针

- internalDebug 新增仅在 `deviceType=2in1` 激活的候选面板探针；该分支不创建固定 `FLAG_FIXED` 面板，不进入正式组合输入路径，Phone/Tablet 原 internalDebug 行为不变。
- 探针单独执行 `SOFT_KEYBOARD + FLAG_CANDIDATE` 的创建、页面加载、缩放、移动、显示、隐藏、再次显示、鼠标点击、焦点保持和销毁，并在任一步失败后先清理候选面板、再独立探测 `STATUS_BAR`。
- 新增路线判定纯策略与自动测试：只有完整生命周期通过才冻结 A/B；候选面板和状态栏面板均失败且清理完成后才允许路线 C。
- `scripts/build-hap.ps1` 支持 `-Clean`，并把探针代码和页面仅叠加到 internalDebug 构建；新增 `scripts/accept-computer-stage1.ps1` 自动识别 2in1、执行跨宿主矩阵、采集截图/UI 树/hilog 并断言路线。

### 2in1 结论

- HarmonyOS 6.1 / API 24 / x86_64 `2in1` 模拟器检测到 1 个字母键盘设备；固定面板创建数为 0，运行日志无 `InputPanelController`。
- 候选面板完整生命周期 PASS，尺寸 `988×122 px`；ArkUI `TextInput`、`TextArea` 和系统浏览器均提供有效屏幕绝对光标坐标，代表锚点为 `(651,438,35)`、`(651,965,35)`、`(968,386,40)`。
- 候选鼠标点击后宿主仍保持焦点，随后 A/B 键继续到达输入法，宿主文本同步为 `ab`；切换输入法触发 `inputStop` 后候选面板销毁 PASS。
- 正式路线冻结为路线 A。历史错误码 1 被确认是固定面板存在时创建第二个软键盘面板的竞争结果；`STATUS_BAR` 因路线 A 通过而 `NOT_RUN`。
- 正式浮动能力仍保持关闭，等待阶段 2 完成 `HARDWARE_READY` 和唯一面板所有权；本阶段未改变正式 Phone/Tablet 输入行为。真实 USB/蓝牙键盘和 ARM64 2in1 为 `NOT_RUN`。

### 验证

- ArkTS 全量单元测试 PASS；internalDebug HAP clean build PASS，41,235,447 bytes/SHA-256 `50253da5e804a22f3608ecfadb3cfe502ee9bcb965b8dc283e65cb1dfc4b2375`；正式 default Release HAP 构建 PASS（`debug=false`），37,832,144 bytes/SHA-256 `dcf16e73dd9acbe2da429d338c0e581e69977fa2e1327e61303ea01084b25ebe`。
- 2in1 一键验收脚本 PASS，以 `COMPUTER_STAGE1_RESULT=PASS route=A` 结束。能力报告和原始证据见 `docs/evidence/2026-08-05-computer-stage1/README.md`。

## 2026-08-05（17/26 键双拼 UI 阶段 1：主机实现）

### 截图反馈微调

- 空闲工具栏最左侧方案按钮去掉下拉尖号，仅保留键盘图标与 `17 键双拼`/`26 键双拼` 文字。
- 最右侧收起按钮去掉“收起”文字，改用独立 20×20 矢量尖号，并在完整点击区域内做水平、垂直几何居中，避免字体基线造成图标偏下。
- 方案选择浮层去掉“紧凑分组按键”和“标准 QWERTY 按键”说明，只保留选中标记与方案名称；单项高度由 58vp 收紧到 48vp。
- 方案选择浮层宽度由键盘可用宽度的 72% 收紧到 52%，减少方案名称右侧的无效留白。
- 全键盘字母键、功能键、工具栏、输入码及按键预览字号统一下调；动态字号上限由字母/功能/预览 `21/16/32` 调整为 `18/14/27`。

### 键盘方案与空闲工具栏

- 新增可持久化的 `17 键双拼` / `26 键双拼` 键盘方案。空闲候选栏现在显示当前方案、系统“输入法”、双羽“设置”和“收起”四个入口；开始输入后整栏切回输入码与候选，工具入口不占用候选空间。
- 新增键盘方案选择浮层，当前方案带选中标记，点击后立即替换字母区并写入独立偏好存储；下次输入法扩展创建时恢复上次方案，非法存储值安全回退到默认 `26 键双拼`。
- “输入法”直接调用既有系统输入法选择器；“设置”由输入法扩展上下文启动双羽 `EntryAbility`；中/英键只切换双羽内部语言，不再绑定系统输入法选择器长按动作。

### 17 键与新版 26 键

- 17 键按文档落地三排六槽：`HP/SH/ZH/B/OXV/MS`、`L/D/Y/WZ/JK/NR`、`CH/Q/G/CF/T/删除`，并使用 `符/123`、中/英、空格、逗号/句号和动态动作键底栏。中文、英文模式共用所选 17 键外形，标点随语言使用中文或 ASCII 字符。
- 文档尚未冻结组键的滑动、连击或长按协议；阶段 1 采用“单个键帽内各字母分别可点”的无歧义交互，保证全部字母可输入，同时把后续手势策略限制在组键组件内，不修改引擎按键合同。
- 新版 26 键保持三排标准 QWERTY，第三排固定显示 Shift、`Z`～`M` 和图标删除键；组合输入期间不再把 Shift 临时替换为隐藏的分词键。空格键只显示“空格”。

### 验证

- ArkTS 全量单元测试 PASS，新增 17 键行序、组内目标、底栏、布局规范化、新版 26 键固定 Shift 和中/英键职责回归。
- `entry@default` Debug HAP 编译、资源打包与签名 PASS。Phone/Pad 实机或模拟器视觉、横竖屏、深浅色、布局持久化运行时和第三方输入框矩阵本阶段 `NOT_RUN`，不得表述为设备验收完成。

## 2026-08-05（小鹤音形精准匹配阶段 6：精准匹配提示）

### 精准匹配提示

- `xiaohe-yinxing` 现在先查询当前完整编码：有精确命中时只显示同码候选，不附带编码提示；没有精确命中、但词库中存在严格更长编码时，才显示部分匹配提示。
- 部分匹配提示严格保持正式词库的分类顺序与分类内 `source_order`，不按拼音、频率或用户学习重排。输入 `un` 时，正式主表依次提示“熟能生巧 uq、伤脑筋 jb、施耐庵 an、史努比 bi、十拿九稳 jw、上年结转 jv、受虐狂 kl、少年郎 lh、十年树木 um”。
- 引擎最多生成 9 项提示；设置页新增“精准匹配提示数量”，允许用户选择 1～9 项，默认 9 项。设置只控制提示的可见数量，不截断精确同码候选。
- 提示项可由用户主动点击或按候选序号提交，但不参与唯一候选自动上屏、第五键顶屏或空码切分。系统精确路径即使被用户 `#删` 清空，也不会回退到前缀提示。
- 候选栏只显示尚未输入的编码后缀；设置 schema 从 2 升级为 3，旧配置自动使用默认值 9。FFI、C++、interface/ABI、正式 bundle 和小鹤双拼行为未修改。

### 验证

- 新增 Rust 状态机、正式词库 `un` 源顺序、用户规则隔离、提示可选与第五键不顶屏回归；新增 ArkTS 可见数量、1～9 边界、设置持久化、精确路径锁定和无障碍文案回归。
- Rust 全 workspace、fmt、全特性 Clippy、ArkTS 全量测试、双 ABI Release Native、signed Release HAP 与 Release 内容门禁全部通过。signed HAP 为 37,942,313 bytes/SHA-256 `2f038338305c857e9c2ddfc3b6319b41b3db91967c7ad7644256c5583d352f4b`。
- x86_64 Phone `1320×2856` 验证设置 9→3→9、提示主动提交和精确路径锁定；Pad `2880×1920` 完整显示 9 项，与经理示例顺序一致。两端压力预检及 fatal 扫描通过；证据见 `docs/evidence/2026-08-05-xiaohe-yinxing-precise-match-stage6-hints/README.md`。

## 2026-08-05（小鹤音形精准匹配阶段 5：模拟器与 signed Release 范围 COMPLETED）

### Release 模拟器验收

- 重新生成真正的 signed Release HAP，并以生成 profile 和包内容门禁确认 `buildMode=release`、`debug=false`。signed HAP 为 37,912,924 bytes/SHA-256 `292193f8fe3713e18a87cd9a0e4211de95ba6c26576ede0beb751338f4b2e956`；unsigned HAP 为 37,768,240 bytes/SHA-256 `8b4df2853e16de3adfbea7009176b61c42a12e070ee5152636df500d53e302be`。
- Release 正式资源白名单、音形 bundle 大小/哈希、Debug 内容负向检查全部 PASS。权限仍只有 `ohos.permission.VIBRATE`，未新增网络、麦克风或账号权限。
- 验收过程中识别出输出目录中的旧 signed HAP 实际为 Debug 构建；该轮只保留为预检，不用于最终 Release 结论。下述 Phone/Pad 完整矩阵均在重新构建后使用 signed Release 重跑。

### Phone/Pad 与第三方编辑框

- HarmonyOS 6.1 x86_64 Phone 模拟器 `1320×2856` 竖屏和 Pad 模拟器 `2880×1920` 横屏全部 PASS。两端均使用独立包 `com.example.shuangyuime.acceptance` 验收聊天单行、URL、搜索、多行和应用切换。
- 两端均通过 10 轮无额外等待的连续 `aaba` 精准突发、`aab → 退格 → ba` 恢复、完成全码后的隐藏/恢复和 50 轮长输入压力；未出现误上屏、重复上屏或丢键。
- Release 输入法进程 RSS 在 Phone/Pad 上分别只增长 20/12 KiB；fatal、panic、SIGSEGV 和 process-crash 扫描为空。
- 本阶段结论严格限定为用户要求的模拟器范围。ARM64 真机、分屏自动化、Debug/InternalDebug 重建和完整双拼设备矩阵为 `NOT_RUN`，不宣称完整发布门禁完成。证据见 `docs/evidence/2026-08-05-xiaohe-yinxing-precise-match-stage5-simulator/README.md`。

## 2026-08-05（小鹤音形精准匹配阶段 4：COMPLETED）

### 正式数据全量审计

- 新增 `precise_match_stage4_audit` 和 `scripts/generate-xiaohe-yinxing-precise-match-stage4.ps1`，完整遍历 `26^4 = 456,976` 个四码。结果为零候选 394,265、唯一 59,010、重码 3,701、最大有效候选数 5。
- 全部唯一全码逐一通过状态机单次自动提交；全部重码逐一验证不自动提交、顺序稳定、只含完整精确码且候选可达。没有前缀混入或重复查询顺序漂移。
- 审计 6,636 个简码文字对和 59,151 个词组文字对；7 个可选分类的 4,168 个受影响四码与全部 62,711 个非空四码的用户删除变化均通过。
- 两次全量报告逐字节一致，SHA-256 均为 `61e18fcf474e90e52d05e4568b0a7d536e78f8d26da512078469ff2ec0a9cc40`。

### Release A/B

- 同机独立 Release 进程覆盖正式数据产生的 13,781 个一至三码前缀。历史渐进/当前精准查询 P95 为 24.6/8.2 µs，无性能回退。
- 传输候选数由 147,910 降至 6,636（-95.51%）；候选快照 JSON 由 15,232,656 降至 1,104,396 bytes（-92.75%）；快照工作集增量由 39,931,904 降至 3,723,264 bytes（辅助观测）。
- 正式 bundle 保持 25,397,952 bytes/SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`。完整证据见 `docs/evidence/2026-08-05-xiaohe-yinxing-precise-match-stage4/README.md`。

## 2026-08-05（小鹤音形精准匹配阶段 3：COMPLETED）

### 候选 UI 方案隔离

- 新增 `CandidateUiPolicy`，候选 UI 现在按稳定 `schemeId` 显式分流：`xiaohe` 保留可浏览候选、50 项分页、展开面板和 Pad 侧栏；`xiaohe-yinxing` 只显示当前精确候选快照，并阻断展开动作、Phone/Pad 展开面板和 Pad 浏览侧栏。
- 音形一至三码继续只渲染引擎给出的精确简码；无候选时显示“继续输入形码”。完整码无候选时显示“无匹配全码”，不会创建伪候选或进入大列表浏览。
- 音形候选无障碍文案区分“精确简码候选”和“完整码候选”；双拼原文案保持不变。候选点击继续使用既有 `commitCandidate(index)` 链路，未修改 C++/FFI/interface/ABI、查询、排序、正式码表或用户规则。

### 验证

- ArkTS 349/349 PASS；internalDebug、unsigned/signed Release HAP 构建和 Release 内容门禁 PASS。Debug HAP 为 41,066,440 bytes/SHA-256 `3516f065820d165cb72c41f1abab1610a5130daefc8f0918c8b017135c64bef6`；unsigned Release HAP 为 37,768,848 bytes/SHA-256 `96b7a1a3459e51eeb0bda30f160b8926c47e55c3936225de980de7af84c50667`。
- x86_64 Phone 竖屏独立第三方编辑框验证：音形 `bm` 只有输入码和精确简码候选，没有“展开”；切回双拼输入 `h` 后“展开”仍存在。正式音形 bundle 大小与 SHA-256 保持冻结。
- Pad、横屏、分屏、ARM64 真机和压力矩阵本轮 `NOT_RUN`，继续进入阶段 5。完整证据见 `docs/evidence/2026-08-05-xiaohe-yinxing-precise-match-stage3/README.md`。

## 2026-08-04（小鹤音形精准匹配阶段 2：COMPLETED）

### 顶屏、重放与失败恢复

- 保持 Rust 状态机既有的第五码原子转换：只使用上一段按分类、用户规则和稳定去重后的合法首选顶屏，并把当前键恰好一次重放为新段第一码；正向/反向空码切分、无合法旧候选、非法第五码、退格/reset 和非 BMP 长文本合同继续有效。
- 修复 ArkTS 自动提交失败会 `reset + clear` 丢失组合的问题。宿主拒绝提交或抛出异常时，控制器现在从按键前的不可变 Store 快照重建 Native 原编码与候选，保留可重试状态；成功提交路径仍只写入一次，并保留第五码重放后的剩余组合。
- 新增有状态顶屏回归：四码重码后第五键提交非 BMP 文本 `𠮷😀`，第六键在异步宿主写入期间通过共享串行执行器等待，最终按键序列严格为 `a,b,c,d,e,f`、提交一次、新段为 `ef`；失败路径恢复 `abcd` 和原两项候选，随后退格可得到 `abc`。
- 会话代次失效、候选提交/模式切换/新输入共用队列、重复删除、方案切换清理、删除到空和 reset 继续由既有 ArkTS 回归锁定；FFI/interface/ABI version 保持 4，C++ 转发和正式 bundle 未修改。
- 修正阶段 1 遗留的 FFI 大页旧断言：精准音形单码在页大小 50/9 下均只返回 2 个精确简码且无下一页，不再错误要求返回 50 个前缀候选；小鹤双拼的独立大候选分页合同不变。

### 验证

- `code-table-runtime` 85 项、`ime-engine` 89 项、`ime-ffi` 28 项、Rust fmt 和 ArkTS 全量单元测试全部 PASS；ArkTS 仅报告既有 SDK 弃用/异常处理警告。
- Phone、Pad、ARM64 物理真机、第三方输入框和 signed Release 压力矩阵为阶段 5 `NOT_RUN`；本阶段结论限定为主机自动化范围。

## 2026-08-04（小鹤音形精准匹配阶段 0：COMPLETED）

### 合同、基线与决策

- 确认《精准匹配修改.md》第 3～6 节：一至三码不自动提交，四码只查询完整码，过滤后唯一时单次自动上屏，真实重码保持组合并只显示完整码重码；大规模前缀候选不再作为后续音形产品目标。第二候选快捷键仍待单独确认。
- 新增 ADR 0022，替代 ADR 0020 的后续产品目标但保留其历史实现证据；阶段 0 不修改 `query.rs/state.rs/formal.rs` 生产行为、FFI、C++、ArkTS UI、正式数据、用户词库格式或小鹤双拼。
- 新增 `scripts/generate-xiaohe-yinxing-precise-match-stage0.ps1` 和独立机器目录 `dictionaries/audit/xiaohe-yinxing/precise-match-stage0/`。当前渐进候选与当前双拼隔离快照各运行两次并逐字节比较，不覆盖 2026-07-27 渐进改造前的历史基线。
- 冻结正式 bundle `25,397,952` bytes、SHA-256 `00c7d5a9...bcd1e30`、完整 manifest、八分类 73,263 条普通记录、36 条内置规则和仅 `ohos.permission.VIBRATE` 的权限集合；正式 bundle、manifest 和分类源未修改。
- 当前渐进基线记录 `aaba` 的 50→41→4→唯一提交“阿爸”路径，`jumk` 的 50→50→13→5 个重码路径，以及 `jumke` 顶屏“驹”并重放 `e`、`aaa` 无结果保留、`aaaa` 反向切分、退格/reset、用户规则/分类和当前双拼隔离。

### 性能与验证

- Windows x86_64 Release，3 次预热、10 样本：音形 `h` 冷/热状态查询 P50/P95 为 `1.2965/1.4200 ms` 与 `0.9870/1.1432 ms`；512 项快照的 50 项当前页协议 JSON 为 `5,057 bytes`，候选快照工作集增量 `8,560,640 bytes`，进程峰值 `148,779,008 bytes`。
- 修正 `candidate-baseline performance-page-size` 的观测路径：性能报告的跨语言 JSON 现使用正式 `QueryConfig` 和请求页大小；历史稳定快照继续使用专用阶段 0 配置，不被改写。
- Rust workspace `423/423`、新增精准阶段 0 专项 `2/2`、`candidate-baseline` `4/4`、ArkTS 全量 `BUILD SUCCESSFUL`、`cargo fmt --check` 和全 workspace/all-target/all-feature Clippy 全部 PASS。现有 ArkTS 警告未新增。
- Phone、Pad、ARM64 真机、第三方输入框和设备端性能本阶段 `NOT_RUN`；阶段 0 没有运行时/UI 修改，不借用旧设备证据宣称本轮设备验收。

## 2026-07-29（客户修改阶段 4.3：COMPLETED）

### 输入码按两码切分展示

- `engine-protocol::CompositionResult` 新增 `displaySegments`，由 Rust 对当前原始编码生成展示段；完整编码每两码一段，奇数尾码保留为未完成段，显式分词边界和 `;` 引导字符保持。客户示例 `vegewtyijkjj` 输出 `["ve","ge","wt","yi","jk","jj"]`，UI 显示为 `ve'ge'wt'yi'jk'jj`。
- C++ Node-API、ArkTS Native 类型、`NativeEngineGateway` 和 `InputSessionStore` 同步转发并保存展示段。UI 不按字符串长度猜测音节，只用 `'` 连接引擎段；旧结果缺少字段时安全回退为原始 `rawInput`。
- 顶部候选栏、Pad 固定侧栏和保留的浮动候选组件统一使用 `CompositionPreeditView`，继续保留下划线“未上屏”提示。分隔符仅存在于显示文本，不进入 `rawInput`、`preeditText`、候选查询、用户学习或提交文本。
- 新增 `Stage43.test.ets`，覆盖客户示例、完整双码、奇数尾码、显式分词、引导字符、旧引擎回退、空输入和“不使用全拼 preedit”合同；阶段 4.1 回归同步更新。ArkTS 343/343 PASS，`engine-protocol` 4/4 PASS，Rust workspace 全量测试 PASS，双 ABI Rust Native、Release HAP 构建及内容门禁 PASS；本轮 unsigned Release HAP 为 37,763,052 bytes，SHA-256 `efd650c9bcf84884bcf0065cae9b72229f618f1660d6b923d34b17b8cae7d5fb`。
- 候选稳定基线只因 JSON 新增 `displaySegments` 增加协议字节数，候选内容、顺序、分页和提交行为未变；已用正式 `candidate-baseline stable` 生成器更新四份稳定快照。C ABI 函数签名、interface/ABI version 4、设置 schema、正式词库和音形 bundle 均未修改。

## 2026-07-29（候选词改进阶段 6：COMPLETED）

### 覆盖审计与词库接入门禁

- 为 `candidate-baseline` 新增 `stage6-audit`，使用真实 `ImeEngine` 分页路径和正式二进制资源逐条审计词库存在性、召回、最终排名、分页可达性、来源和七类失败原因；新增 112 项独立 TSV，覆盖常用字词、成语、口语、网络表达、地名、人名、专业词、多音字、音形/双拼一至四码、生僻/扩展字符和非法编码。
- 审计结果为 `MISSING_IN_LEXICON=11`、`PRESENT_NOT_RECALLED=6`、`PRESENT_RANKED_TOO_LOW=0`、`PRESENT_NOT_ACCESSIBLE=0`、`INVALID_ENCODING=2`、`DATA_CONFLICT=0`、`UNSUPPORTED_BY_CONTRACT=2`；已有词条未召回的 6 项没有通过添加重复词条处理。
- 11 项真实缺失写入机器可读延期清单。本阶段没有新增独立版本和许可证已审批的数据源，正式词库新增、删除和重排均为 0；音形正式 bundle 继续冻结。
- 新增来源/许可证、频率尺度、覆盖前后、性能、构建哈希和 Release 资源报告。双拼继续使用固定 Rime Apache-2.0 来源与统一频率尺度；音形继续按分类和物理源顺序，双拼频率不影响音形顺序。
- 覆盖报告连续两次均为 76,291 bytes，SHA-256 `8ac272fc24fffb3793850d904f63431ddd1e5b7b283482539e88148c9fc94105`。`production.lex` 和音形 bundle 哈希保持冻结值，覆盖率修改前后相同。

### 验证

- `candidate-baseline` 测试、Rust workspace 420/420、fmt、Clippy 与阶段 6 证据生成门禁 PASS；损坏/非法词库仍由既有 builder 测试以文件、物理行、词条、编码和原因明确拒绝。
- unsigned Release HAP 资源审计 PASS：37,750,936 bytes，SHA-256 `1b2a815b4b52f7982d7e6921aab4a5922c6e53aff2fb78071f8dcb91ca628ead`，仅含批准的正式二进制词库资源，无原始码表、测试语料、审计材料、调试日志、凭据或模拟词库。
- 本阶段未修改运行时和正式数据，阶段 5 启动/查询与包体积基线保持；附加主机探针及完整机器报告见 `docs/evidence/2026-07-29-candidate-stage6/README.md`。
- Phone/Pad 刷新、ARM64 物理真机、signed Release 第三方输入框和设备压力矩阵为阶段 7 `NOT_RUN`。

## 2026-07-28（候选词改进阶段 5：COMPLETED）

### 前缀排序与用户学习

- 为小鹤双拼 `QueryMode::Prefix + ExistingRanking + GlobalTopK` 新增独立的确定性质量排序；完整音节精确查询、句子评分、阶段 0 旧召回回退和小鹤音形 `SourceOrder` 均保持原合同。
- 前缀排序保持匹配类型硬边界，然后按“有限质量分＋有界用户分、原始频率、文字、reading、来源、稳定 ID”排序。1～2 字不衰减，3 字使用 2 倍除数，4 字及以上使用封顶 8 倍除数，单字符重复项额外使用封顶 8 倍除数；不删除候选，也不硬编码固定首屏。
- 阶段 3 的完整索引遍历、可见文字去重 Top-K 256 和最终快照 128 不变；用户学习在完整 256 项池完成系统去重/排序后重排，再截断快照和分页，不在旧 64 项或第一页局部集合上学习。
- 生产词库审计确认 65,115 条均来自同一 `rime_pinyin_simp` 尺度；记录“回复日期”及重复拟声项的异常频率证据，但未清洗、替换或重新生成正式词库。
- 正式 `h` 前 20 由“和、好、还、呵呵、会、回复日期……”改善为“和、好、还、会、还是、很、后、还有、或……”；“回复日期/呵呵/哈哈”分别由第 6/4/10 调整到第 25/22/40，前 20 为 11 个单字和 9 个 2～4 字短词并覆盖 10 个分支。
- 生产候选“会议”连续选择 4 次的排名为 48→44→43→41→38；重建引擎后保持 38，清除模型恢复 48，禁学习会话选择 4 次仍为 48。既有密码框、隐私会话、学习上限、饱和、持久化和隐私哈希合同未修改。

### 验证

- Rust workspace 419/419、ArkTS 332/332、fmt、全 workspace/all-target/all-feature Clippy、x86_64/arm64-v8a Native Release、internalDebug 和 unsigned Release HAP 全部 PASS。
- 同机 Release 5 次预热、每键 30 样本：a～z 冷查询 P50/P95 为 2.195/4.555 ms，缓存命中为 37.1/68.1 µs；256 项去重/系统排序/用户重排 P50 为 92.9/128.8/142.4 µs。
- internalDebug HAP 为 41,024,806 bytes/SHA-256 `02b399fdc94afc3d4c454ffaefaf06221d8896f82a30f76183f347fc0ed916b65`；unsigned Release HAP 为 37,750,936 bytes/SHA-256 `1b2a815b4b52f7982d7e6921aab4a5922c6e53aff2fb78071f8dcb91ca628ead`。
- `production.lex` 与正式小鹤音形 bundle 的大小和 SHA-256 保持冻结值；未修改输入语义、召回覆盖、页面大小、候选 UI、C++/FFI/interface/ABI 或音形排序。
- Phone/Pad 阶段 5 专项、ARM64 物理真机、signed Release 第三方输入框及设备性能/压力矩阵为 `NOT_RUN`。完整报告见 `docs/evidence/2026-07-28-candidate-stage5/README.md`。

## 2026-07-28（候选词改进阶段 4：COMPLETED）

### 查询意图与歧义合同

- 新增 ADR 0021，冻结 `Empty/SingleKeyPrefix/CompleteSyllable/IncompleteSyllable/MultiSyllable/Invalid` 六种 Rust 核心查询意图；parser 输出唯一意图，`ime-engine` 据此选择现有前缀、精确或句子路径，不再由多个模块通过按键/数组长度猜测语义。
- 单键 `h/a/o` 统一为规范拼音前缀；`h` 不混入同键韵母 `ang`，`a/o` 仅通过正常前缀命中方案允许的零声母 reading。`hc/ni/ui/vi` 继续分别精确解析为 `hao/ni/shi/zhi`。
- 修复单个歧义完整双键 `lo → lo/luo` 因旧 `syllables.len() >= 2` 被误判为多音节的问题；parser 现在输出逻辑音节槽位，单音节所有合法解释均做精确查询，多音节歧义按方案声明顺序选择规范 reading，不依赖词库顺序。
- 输入与删除统一重建候选并回到第 0 页；覆盖单键→完整→不完整→句子及句子→不完整→完整→单键→空的逐级转换，删除到空会清除候选和分页状态。
- ArkTS UI 继续只原子应用并展示 Rust 返回的组合快照，不新增跨语言意图字段，不修改 C++/FFI/interface/ABI 或候选提交 ABI。

### 验证

- Rust workspace 415/415、ArkTS 332/332、fmt、全 workspace/all-target/all-feature Clippy、x86_64/arm64-v8a Native Release、internalDebug 和 unsigned Release HAP 全部 PASS。
- internalDebug HAP 为 40,981,174 bytes/SHA-256 `707de14f30a2d67a4a76004a502791550198fecd689a2b2720eda6844a068c1b`；unsigned Release HAP 为 37,707,304 bytes/SHA-256 `0ea34054dc13a650a49db197a568e91603588ab6be2bd9a114b13eda6ad22376`。
- `production.lex` 与正式小鹤音形 bundle 的大小和 SHA-256 保持冻结值；未实现首字母简拼，未修改阶段 3 Top-K、排序/学习、正式词库、小鹤音形、用户规则或候选展开 UI。
- Phone/Pad 阶段 4 专项、ARM64 物理真机、signed Release 第三方输入框及设备性能/压力矩阵为 `NOT_RUN`。完整报告见 `docs/evidence/2026-07-28-candidate-stage4/README.md`。

## 2026-07-28（候选词改进阶段 3：COMPLETED）

### 双拼前缀召回

- 小鹤双拼不完整前缀的正式策略由“按 reading 字典序先取 64 项、再排序”改为“完整遍历相关索引＋按现有排序键维护有界全局 Top-K”；召回池为 256，现有用户学习在最终快照截断前重排，稳定快照为 128，最后沿用 50 项正式分页。
- Top-K 按可见文字跨 reading 稳定去重，保留完整稳定排序键；堆和去重索引为 O(K) 有界内存。旧 `LexicalEarlyStop` 策略保留为显式回退路径，阶段 0 工具使用该策略继续逐字节复现冻结基线。
- 正式 `h` 由旧 64 项仅覆盖 `ha/hai`，改为 256 项召回池覆盖 19 个分支；前 20 覆盖 9 个分支，并包含“和、好、还、会、很、后、或”。最终 128 项快照在页大小 9/20/30/50 下拼接顺序完全一致，50 项分页为 50＋50＋28。
- 完整双拼精确查询仍使用原 64 项上限；句子解码、部分提交、小鹤音形 SourceOrder/状态机、候选 UI、C++/FFI/ABI、正式词频和正式词库均未修改。

### 验证

- Rust workspace 407/407、阶段 0 冻结文件 3/3、fmt、全 target/feature Clippy 与 ArkTS 测试 PASS；x86_64/arm64-v8a Native Release、internalDebug 和 unsigned Release HAP 构建 PASS。
- 同机 Release 5 次预热、每键 30 个样本：`h` 冷查询 P50/P95 为 3.416/4.398 ms，缓存命中为 45.5/64.6 µs；a～z 冷查询汇总 P50/P95 为 2.471/5.656 ms，缓存命中为 38.2/72.8 µs。
- internalDebug HAP 为 40,973,734 bytes、SHA-256 `d22d74a4692efa92045d95a2fdf29fe27a409610fccf819edbc8d14d64b7c2dc`；unsigned Release HAP 为 37,699,880 bytes、SHA-256 `69931320aebb8d22c2a7a853dcd249ff33f285d2996a7e25e30967ce0ca2c7ad`。
- Phone/Pad 阶段 3 正式双拼专项、ARM64 物理真机、signed Release 第三方输入框、设备端性能/内存和压力矩阵为 `NOT_RUN`。完整报告见 `docs/evidence/2026-07-28-candidate-stage3/README.md`。

## 2026-07-28（候选词改进阶段 2：COMPLETED）

### 展开、分页与生命周期

- 根据最终 UI 复核移除展开面板标题行内重复的“收起”按钮；展开与收起现在统一由候选栏中的单一入口完成。
- 候选栏新增独立“展开候选/收起候选”动作，保留右侧“收起键盘”的原 ID、动作和无障碍语义；Phone 普通状态继续使用单行候选栏。
- 新增当前页候选网格：Phone 竖屏 5 列、横屏 8 列，展开时在固定输入法窗口内替换键页且不覆盖键区；Pad 使用约 48% 宽侧栏和 10×5 网格，完整字母键区保持可见、可点击。
- 翻页复用 `candidatePage/hasPreviousPage/hasNextPage` 与原 `commitCandidate(index)`；请求期间禁止重复翻页，成功后原子替换当前页，失败保留旧候选。展开时普通栏候选内容隐藏，不跨页累计 ArkUI 节点。
- 空候选、会话结束、隐藏键盘、切换输入框、方案/模式切换、错误和销毁均清理展开/加载状态；补齐候选、上一页、下一页、收起候选与收起键盘的独立无障碍文案。
- 修复 ArkUI Builder 计算参数不随第 2 页状态刷新的问题，翻页按钮改为直接读取响应式属性；Phone/Pad 最终设备回归均确认“上一页”可用。

### 验证

- ArkTS 330/330、Rust workspace 403/403 与 fmt PASS；internalDebug HAP 40,909,750 bytes，SHA-256 `4116C46349AA4C2301C3CC97D6AEB4582F73B1C2A71EACE98648D81008F9DCFC`；unsigned Release HAP 37,635,864 bytes，SHA-256 `4425ADF11427673ECCB51035558C6F4C1566456D85264F0A880DB13E1553DA3B`。
- Phone x86_64 `1320×2856` 完成第 1 页→第 2 页→上一页→候选栏收起并恢复键区；Pad x86_64 `2880×1920` 完成侧栏展开、翻页和第 2 页候选“海边”提交，提交后面板关闭且键盘保持。
- 正式每页仍为 50；internalDebug 为制造稳定分页继续使用 8 项 fixture 页。未修改 Rust 查询、召回、排序、学习、用户规则、正式词库、C++/FFI 或 ABI。
- ArkUI 首帧/内存独立插桩、ARM64 物理真机、signed Release 第三方输入框、旋转/分屏、快速触键和压力矩阵为 `NOT_RUN`。完整报告见 `docs/evidence/2026-07-28-candidate-stage2/README.md`。

## 2026-07-28（候选词改进阶段 1：COMPLETED）

### 页大小合同

- 解除 Rust `max_page_size=9` 的公共硬限制：ArkTS、Node-API 与 Rust 正式缺省页大小统一为 50，最大允许页大小设为 64；显式 3/5/8/9 小页继续可用，0 被拒绝，异常超大值钳制为 64。
- `QueryConfig::normalize_page_size` 成为正式引擎的统一规范化入口；同一结果同时用于小鹤音形 `CodeTableStateMachine`、小鹤双拼查询和 `CandidateSession`，方案切换继续沿用该页大小。
- 阶段 0 工具改为显式冻结旧 5/9 合同，既有音形 512 项和双拼 64 项快照保持可重复、逐字节回归；新增可指定页大小的同机 Release 性能 A/B 命令。

### 验证

- FFI 请求 50 时，小鹤音形 `h` 当前页实际序列化 50 项；请求 9 仍为 9。音形 9/50 页拼接后的 512 项列表完全一致，第二页从全局第 51 项开始；双拼 9/50 页拼接后的 64 项召回池完全一致，前 50＋后 14，原前 9 顺序不变。
- Rust all-targets 403/403（含 FFI 28/28）、ArkTS 324/324、fmt、全 target/feature Clippy、x86_64/arm64-v8a Native、internalDebug 与 unsigned Release HAP 全部 PASS。
- 同机 100 样本下，双拼冷/热 P50 为 97.0/9.9 µs，音形冷/热 P50 为 1442.7/1192.3 µs；当前页 JSON 约由 1.2 KB 增至 5.0 KB，峰值工作集基本不变。Phone 1320×2856 与 Pad 2880×1920 两台 x86_64 模拟器的 internalDebug 运行时页整体 PASS。
- 未修改双拼前缀召回和 64 项召回池、音形/双拼排序、用户规则、正式词库、候选展开 UI 或收起键盘行为。ARM64 物理真机、signed Release 第三方输入框、设备性能与压力矩阵为 `NOT_RUN`。完整报告见 `docs/evidence/2026-07-28-candidate-stage1/README.md`。

## 2026-07-27（小鹤音形改进阶段 1：COMPLETED，主机与 x86_64 模拟器运行时页范围）

### 修复与实现

- 修复正式 `xiaohe-yinxing` 在存在一至三码精确简码时排他隐藏更长编码候选的问题；一至三码现在合并“精确候选＋严格更长前缀候选”，四码继续只返回完整精确候选。
- 新增显式 `CodeTableQueryStrategy::{ExactOnly, ExactOrPrefixFallback, ProgressiveXiaoheYinxing}`；通用 `query_exact_or_prefix`、fixture 和工具保持旧回退语义，只有正式方案注册选择渐进策略；`xiaohe` 双拼不受影响。
- 精确路径在普通系统前缀路径前稳定去重；既有 `#固/#删/#N` 仍在分页前作用于完整编码元数据，随后稳定去重、按 512 的正式方案上限截断并分页。ArkUI 仍只接收当前页，没有增加候选面板或 UI 节点规模。
- 四码唯一自动提交继续基于过滤和用户规则处理后的完整精确集合及有效后续码；多重四码、第五键顶屏、正反向空码切分、退格/reset 和方案切换沿用既有状态机合同。
- 更新 internalDebug 正式运行时验收页：用 `ni` 94 个正式渐进候选加 `#固/#2` 后的 96 项验证规则先于分页；分类断言改为检查候选来源，允许同文字由其他启用分类合法提供。

### 正式数据与验证

- 阶段 0 → 阶段 1 数量：`aa 1→41`、`ai 1→115`、`an 3→165`、`ni 1→94`、`hc 1→209`、`ui 4→343`、`vi 6→353`、`wo 1→68`、`xm 3→264`、`xq 2→135`。`ni` 首页包含“你”及八个同音候选；`ui` 的“事、室”保持精确相对顺序并补充更多候选。
- 新增策略隔离、一至四码、精确/前缀跨路径去重、用户规则、分页、四码唯一/多候选、正式数量/首页、三码过滤、退格、页大小稳定和双拼隔离回归。
- Rust workspace 395/395、FFI 26/26、ArkTS 323/323、fmt、Clippy、双 ABI Native、internalDebug、unsigned/signed Release HAP、当前 Release 正负门禁和正式输出 15/15 确定性双构建均 PASS。
- x86_64 HarmonyOS 6.1 Phone 模拟器 `1320x2856` 的 internalDebug 正式运行时页经 force-stop/restart 两轮 10/10 PASS。ARM64 真机、Pad 专项、真实第三方输入框、快速触键和阶段 1 专项设备性能仍为 `NOT_RUN`。
- 正式 bundle 和源数据未修改：25,397,952 bytes，SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`。

## 2026-07-27（小鹤音形改进阶段 0：COMPLETED）

### 基线与决策

- 新增 `scripts/generate-xiaohe-yinxing-stage0-baseline.ps1`，单一入口生成正式资源、旧候选、小鹤双拼隔离和主机 Release 性能基线；候选与双拼快照各生成两次并逐字节比较。
- 在 `dictionaries/audit/xiaohe-yinxing/baseline/` 冻结正式 bundle 的 25,397,952 bytes、SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`、完整 manifest、八分类 73,263 条普通记录、36 条内置固顶规则和 13 文件 archive 白名单。
- 冻结 `aa/ai/an/ni/hc/ui/vi/wo/xm/xq` 的完整分页前候选与第一页，以及四码唯一/多候选、非法/无结果/超长、用户删除/固顶/位置、分类过滤和空码切分的真实旧行为。
- 冻结 `nihc/uurufa/xnhe/ulpb` 对应“你好/输入法/小鹤/双拼”的逐键双拼状态、候选、提交、翻页、退格、reset、重建会话和方案切回行为。
- 新增 ADR 0020：后续只能为 `xiaohe-yinxing` 增加显式渐进查询策略，不直接修改通用 `query_exact_or_prefix`；明确一至四码、排序、去重、分页、自动提交、空码切分、离线权限和 `xiaohe` 隔离合同。本轮未实现阶段 1。

### 测试与证据

- 新增 `stage0_baseline` Rust CI 测试，锁定机器基线、正式资源身份和十个规定编码的完整候选字段与顺序；扩展既有 Release benchmark 的热重载、首键和 500 次会话内存观测。
- 五个独立 x86_64 主机 Release 样本：融合加载 P50/P95 633.9623/634.1907 ms，首键到 Rust 候选 0.3291/0.3611 ms，逐查询 4.88/19.74 µs，峰值进程内存 147,406,848 bytes。
- 两个独立目录的 15/15 正式输出逐字节一致，生成 bundle 与当前正式 bundle 一致；正式来源和正式 bundle 未修改。
- Rust 修改前 387/387、修改后 389/389、fmt、Clippy，ArkTS、FFI、x86_64/arm64-v8a Native、internalDebug/unsigned Release HAP、Release 正负门禁均 PASS。
- 设备清单明确区分 PASS/NOT_RUN/BLOCKED：本轮只有 x86_64 Phone/Pad 模拟器，ARM64 物理真机和真机性能未执行；密码场景 `uitest` 键帽不可见仍为既有阻断。完整报告见 `docs/evidence/2026-07-27-xiaohe-yinxing-stage0/`。

## 2026-07-27（阶段 11.6.9 最终验收：PARTIALLY COMPLETED）

### 验证

- 新增统一 `scripts/verify-stage11_6_9.ps1`，以唯一 run ID 分离 Host、Build、Phone、
  Pad、ARM64 和 Performance 证据；设备按实时属性识别，不按端口假定类型。
- Rust 387/387、FFI 26/26、ArkTS 323/323、fmt、Clippy、双 ABI Native、
  internalDebug/unsigned Release/signed Release HAP、Release 正负门禁、签名验证、
  28/28 来源不可变与 15/15 生产输出双构建一致全部 PASS。
- 五个独立 Release 主机进程测得 bundle 加载 P50/P95 650.1365/657.4287 ms，
  逐键查询 P50/P95 4.86/18.88 µs，峰值进程内存 114,126,848 bytes。
- Phone/Pad x86_64 模拟器的密码场景只显示受保护安全键盘表面，`uitest` 不暴露
  键帽；现有脚本未识别系统安全键盘并在应用布局分支以“缺少 Shift”失败。设置脚本经 DebugIndex
  导航修正后完成多数设置和重启持久化，清空用户模型后半程仍未完成。
- signed Release 独立 TextInput、ARM64 物理真机、设备性能和完整应用/压力矩阵
  均为 NOT RUN，因此不宣称客户交付或正式发布验收通过。

### 门禁维护

- 修复通用 Release 负向门禁的过期正向控制，使其复制现行白名单要求的正式 bundle；
  同时清除预期负例遗留的子进程退出码。产品白名单与安全规则未放宽。
- Stage 10/11 设备脚本支持独立证据目录；Stage 11 修正正式标题与 internalDebug
  DebugIndex 导航。
- 证据：`docs/evidence/2026-07-27-stage-11.6.9-final-acceptance/`。

## 2026-07-27（阶段 11.6.7/11.6.8 真实复验与修复）

### 修复与实现

- 在 x86_64 HarmonyOS 6.1 Phone 模拟器的独立 ArkUI `TextInput` 中复验，不再只依赖文档或 Debug 页。11.6.7 A～N 连续两轮 28/28 PASS。
- 复现 11.6.8 的关键假成功：设置页已选择“小鹤音形”，但输入法独立进程仍加载 `xiaohe`。根因为主 Ability 与 InputMethodExtensionAbility 进程隔离、Preferences 和 Native handle 不共享。
- `SettingsRepository` 以主进程 Preferences 为 canonical 存储，并通过本包 `SHARED_CONFIG` DataProxy 发布规范化 schema 2 快照；输入法进程冷启动优先读取共享快照。保存任一步失败时恢复旧 Preferences 与旧共享快照。
- `EngineCoordinator` 切换正式方案时创建带生产 bundle 的替代 handle，继承配置、用户路径、学习开关和用户模型；成功后原子交换并销毁旧 handle，失败保持旧小鹤引擎可用。
- `SettingsController` 和 `InputSessionController` 接入正式安装路径、Native-first 保存与失败回滚；输入法冷启动先建立安全小鹤 handle，再根据共享设置加载音形。
- `YinxingBundleInstaller` 使用应用 EL2 沙箱，只清理安装器自己的精确 `.tmp`，相同版本与哈希正确时幂等复用。
- Release 门禁由大小检查加强为正式 bundle 大小 + SHA-256 双校验；新增大小不变的篡改负例。internalDebug 新增缺失、首字节损坏、major 9 不兼容和安装中断临时文件恢复用例。
- 11.6.7/11.6.8 设备脚本改为按实时布局语义定位 TextInput 和键帽，避免固定坐标、系统返回键误提交及 PowerShell 大小写匹配导致的假结果。

### 验证

- Rust 387/387、FFI 26/26、ArkTS 323/323、fmt、全 target/feature Clippy、x86_64/arm64-v8a Native、internalDebug/Release HAP 全部 PASS。
- 11.6.8 signed Release 独立 TextInput A～F PASS：小鹤“你好”、正式 `aaba`“阿爸”、强停持久化、带组合切回、再次切换与 bundle 复用均通过。
- internalDebug G/H/I/J/K 经 force-stop/restart 两轮全部 PASS；实际 HAP 白名单和 fixture/raw/trace/report/哈希篡改/network 负例全部 PASS；28/28 正式来源不可变 PASS。
- Debug HAP：40,801,306 bytes，SHA-256 `44A583E51852549BB792D3057DBAF99968C4622A86B8A243A0A0DD7BCC2630C1`。unsigned Release HAP：37,572,616 bytes，SHA-256 `A9F84A9E83D6B60792BFAFA6F8D887284F08B97133663E912A15668DF8A05295`。设备安装的 signed Release HAP：37,707,165 bytes，SHA-256 `3C86B29ED6C36E8AC706333C0A286AA63B4FC6837129343953CAD2ADB2A5137D`。
- ARM64 物理真机、Phone/Pad 全场景、性能和最终发布验收为 11.6.9 NOT RUN。

## 2026-07-24（阶段 11.6.8）

### 正式方案、设置和资源接入

- 前置门禁确认 11.6.7 `COMPLETED`、空码切分合同冻结、ADR 0018 已更新、Rust 373/373、FFI 25/25、ArkTS 299/299 全部通过；允许进入 11.6.8。
- `ImeSettings` 中新增 `XIAOHE_YINXING_SCHEME_ID = 'xiaohe-yinxing'` 稳定常量，`AVAILABLE_SHUANGPIN_SCHEMES` 扩展为 `[xiaohe, xiaohe-yinxing]`，`SettingsController` 统一使用导入常量替换局部拼接字符串。
- 设置页（`SettingsPage`）通过 `AVAILABLE_SHUANGPIN_SCHEMES` 自动展示两个正式方案；默认仍为 `xiaohe`；未知方案 ID 迁移到 `xiaohe` 且幂等；`SettingsValidator` 和 `SettingsMigration` 不变，已正确处理 `xiaohe-yinxing`。
- 创建 `YinxingBundleInstaller`：从 HAP rawfile 读取 `xiaohe-yinxing-production.hsyx`，验证大小（25,397,952 bytes）和 SHA-256 后原子重命名为 `xiaohe-yinxing-production-v1.hsyx`；已安装且哈希匹配时直接复用，不重复复制 25 MB；临时文件以 `.tmp.` 命名，启动时清理；安装失败时日志不含绝对路径。
- `SettingsController.changeScheme` 切换到 `xiaohe-yinxing` 前先调用安装器；安装失败不执行 Native 切换并回退；`SettingsController.load` 启动时若 `xiaohe-yinxing` 资源不可用则回退到 `xiaohe` 并修复持久化。
- 正式 bundle `xiaohe-yinxing-production.hsyx` 已进入 `entry/src/main/resources/rawfile/`；SHA-256 与审计合同吻合（`00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`）；授权元数据确认 `hap_distribution_allowed=true`。
- `verify-release-hap.ps1` 更新：删除对 `xiaohe-yinxing` 字符串的全局禁止，改为精确白名单 `[production.lex, xiaohe-yinxing-production.hsyx]`；rawfile 和 HAP 内部均使用白名单；新增 bundle 大小（25,397,952 bytes）校验；fixture、`.txt`、`.ini`、`trace-index` 等负向门禁保持；第二个未知 `.hsyx` 仍失败。
- Rust 387/387 PASS（373 既有 + 14 新增正式生产回归）；FFI 25/25 PASS；ArkTS 299/299 PASS（含新增 SchemeSwitch、SettingsMigration、YinxingBundleInstaller 三个测试套件，设备端待运行）；双 ABI（x86_64 + arm64-v8a）PASS；Debug HAP `40,768,260` bytes/SHA-256 `32FBAF2B99798AEE4F8AEC58775E9C3F18EB9114F1BFE29E25E764BA20E1A19E`；Release HAP `37,565,064` bytes/SHA-256 `B413C26673A895921EEBFCE273785256A724650ABBF93BD83AE7A796EBD8B966`；Release rawfile 含 `production.lex` + `xiaohe-yinxing-production.hsyx`；HAP 资源正向门禁 PASS；Release 负向门禁 PASS；28/28 来源不可变 PASS。
- interface/ABI version 4、设置 schema version 2 均未变。未修改空码切分合同、小鹤双拼解析/排序/整句、Rust C ABI 或 C++ 业务逻辑。
- 正式动作数据（快符、引导、日期时间、成对符号）仍延期；ARM64 物理真机与独立 TextInput 设备验收保留为 11.6.9 待办。

## 2026-07-24（阶段 11.6.7）

### 四码提交、顶屏与空码切分完全实现

- 准入审计确认四码唯一自动提交、有效更长编码、第五键顶屏和空码清屏只依赖普通码表、分类/用户不可变快照、`NormalCode` 与 ABI 4 `commitText`，不依赖延期动作数据。
- Rust `code-table-runtime` 新增严格 `CodeTableCommitPolicy`：默认 auto/top/empty 均为 4，普通编码上限 64，空码切分上限默认 64；非法值返回稳定 `invalid_commit_policy`。
- `CodeTableStateMachine` 在一次操作中共用同一分类/用户快照，按”旧段 top → 新键一次处理 → empty split → empty clear → auto”执行；唯一性和首选在分页/limit 前基于完整最终候选判断。
- 第五码结果复用 ABI 4，同时返回一个旧段 `commitText` 与新段 `rawInput/candidates`；FFI/C++ 无业务扩展。engine version 更新为 `0.0.1-stage11.6.7`，interface/ABI 仍为 4。
- ArkTS `InputSessionController` 对自动提交只调用一次 `commitPreviewText`，随后保存新段；提交失败执行受控 reset 并返回失败。
- 增加 Rust、正式包、FFI 和 ArkTS 回归，覆盖多候选、有效后续码、用户删除/固顶、分类变化、非 BMP/长文本、第五键一次性、空码清屏和确定性混合序列。
- 新增 ADR 0018（2026-07-23 部分实施；2026-07-24 经产品授权冻结空码切分补充合同）。实现正向切分（从右向左扫描，选择最长左前缀，提交首选，右侧为剩余段）和反向切分（从左向右扫描，选择最长右后缀，左段原样提交，右后缀为剩余段）；正向优先于反向；相同输入和快照结果唯一；切分成功后只产生一个提交，剩余段只处理一次；未读取或复制 `ime.android.ini`。
- Rust 373/373、FFI 25/25、ArkTS 299/299、双 ABI、Debug/Release HAP、Release 正负门禁与 28/28 来源不可变均通过。x86_64 模拟器两轮 A-I/L-N 运行时页通过；J/K、独立 `TextInput` A-N 和 ARM64 物理真机未执行，不宣称通过。
- Release 默认方案、正式设置入口和资源边界不变；未实现 11.6.8。

## 2026-07-23

## 2026-07-23

### 阶段 11.6.6 引导、快符、符号与安全直通运行时完成

- 审计正式转换合同、命令策略、生产 manifest 与 action metadata：普通静态文本/符号 `AVAILABLE`；快符、引导、日期时间和成对符号均因缺少权威数据而 `DEFERRED_MISSING_SOURCE`；命令、网络、凭据、Intent、脚本和任意文件操作继续 `REJECTED_UNSAFE`。
- interface/ABI 从 3 升级为 4；`CompositionResult` 增加唯一 `action | null`，只允许 `DATE_TIME_TEXT` 与 `INSERT_PAIR`，并冻结与 `commitText` 的互斥关系。Rust 决策，C ABI 序列化，C++ 仅校验/转换，ArkTS 串行执行白名单动作。
- `code-table-runtime` 新增严格动作表加载器和 `Idle/NormalCode/GuidePrefix/GuideCode` 状态机。guide/action、八个系统分类和用户层保持隔离；快符按源顺序完整生成后分页；空引导不枚举。
- ArkTS 新增可注入 `TimeProvider`、`ProtocolActionExecutor` 和 `ImeConnectionService.insertPairText`。时间动作只读取一次快照；成对符号只插入一次，光标失败不重试；所有异步操作绑定 session generation。
- 原创 `stage11_6_6_actions.json` 仅用于 internalDebug，冻结为 2,171 bytes / SHA-256 `05a7653e44fe72c45b1b5b0dc1dc245baaafbc1f4becd5c2ec6c657687c59b63`。Release 构建不复制并在构建后清理。
- 修复中文来源的符号页分号未进入引导机，以及成对文本提交后立即读取到旧光标的问题；提交后只等待编辑器状态稳定，不重放插入。
- Rust workspace、Clippy、ArkTS 296/296、双 ABI、Debug/Release HAP、Release 正负门禁和 28/28 正式来源不可变均通过。x86_64 HarmonyOS 6.1 模拟器完成两轮 internalDebug A-G fixture，并在独立 MainAbility ArkUI `TextInput` 完成日期实际提交、成对 emoji 单次插入和非 BMP 光标探针。设备日志确认 `20 → 15`、偏移 `5` 的 UTF-16 索引行为；结论为 `RUNTIME COMPLETED / EDITOR-SIDE DEVICE ACTION ACCEPTANCE COMPLETED / PRODUCTION DATA PARTIALLY DEFERRED`。

### 完成阶段 11.6.5 产品分类、默认开关与顺序

- 冻结八类 schema 1 产品合同：默认全部开启，`core` required 且不可关闭；其余按 manifest order 可切换。USER 用户层与 FUNCTIONAL 动作边界保持独立。
- Rust 新增不可变分类选择快照；每个查询操作捕获一次快照，分类过滤发生在系统合并之前，精确/前缀/有效后续码/唯一性、用户规则与分页共享同一选择。原子更新保留 raw、页码归零、无提交重算，失败保持旧快照和组合。
- 新增 ArkTS → Node-API C++ → Rust 分类读取/替换接口，interface/ABI 从 2 升级为 3；C++ 只做类型/JSON/错误转发。设置 schema 升为 2，支持旧值迁移、canonical 化、native-first 保存和失败回滚。
- internalDebug 扩展现有 `DebugCodeTable`，提供八类开关、当前组合可视化和 A～L 自动验收；Release 设置入口和正式资源不变。x86_64 HarmonyOS 6.1 模拟器两轮 A～L 经 force-stop/restart 全部 PASS。

### 完成阶段 11.6.4 正式包内与外部用户规则分层

- 新增不可变快照合并 API：已解析的包内规则在前、外部用户文件在后，同完整编码＋词条由外部覆盖；通过既有 `UserLexiconSnapshot::from_entries` 重建稳定顺序、索引和统计，不复制候选排序算法。
- `xiaohe-yinxing` 现在严格加载并应用冻结包内 36 条 `#固`，再叠加可选外部 `userLexiconPath`；fixture 保持外部规则语义，纯系统查询和 `xiaohe` 双拼行为不变。缺失/空/损坏外部层、有效备份恢复、reset、重建、方案切换和清空学习均有专项回归。
- 新增正式包全 36 规则、外部删除/新增/固顶/位置、固定保护、精确删空不二次前缀回退、完整列表后分页、FFI 和双拼隔离测试。test-first 用例在旧实现上先失败，接入后 Rust workspace、fmt 和全 target/feature Clippy 全 PASS；ArkTS 288/288 PASS。
- 双 ABI Native 构建通过。x86_64 HarmonyOS 6.1 模拟器在 `2880x1920` 下从 force-stop/restart 开始连续两轮 A～J 全 PASS；Debug HAP 为 40,392,164 bytes/SHA-256 `04222CD447734DE05B8B76C2ACD5A4C663210E3F4CFCB30BE7E3C97E371E83B9`。
- Release HAP 为 11,956,076 bytes/SHA-256 `30B0F2742A5AABC6ED7FA65C77C35AA03B520AF38908D1F62288766E0967EAF3`，正式/fixture/raw source/trace/report/INTERNET 正负门禁通过，包内 rawfile 仍仅 `production.lex`。28/28 正式来源不可变；interface/ABI version 保持 2，C++ 未改，11.6.5+ 未提前实现。

## 2026-07-22

### 完成阶段 11.6.3 正式系统码表查询回归

- 为 `xiaohe-yinxing` 增加冻结生产包加载入口，严格校验 scheme/bundle/data/converter 版本、13 个归档条目、八类顺序/计数/默认值、36 条规则审计材料及全部冻结哈希；通用 `HSPYXP01` 加载路径继续兼容转换器测试，fixture 与正式身份互斥。
- 新增 23 个独立参考快照，覆盖 1～4 码、精确优先、前缀回退、八类/`source_order`、跨类去重、空/无结果、39 项大重码分页、退格/reset、非法键和 64-byte 上限；损坏矩阵覆盖 magic、长度、版本、截断、尾随字节、内容/记录摘要、manifest、分类、嵌套词库、用户规则和不安全路径。
- Rust 引擎和 FFI 正式支持 Debug-only `xiaohe-yinxing`；正式系统基线只取八个系统分类，包内 36 条固定规则仅作转换审计，不污染系统候选，外部用户词库也留待 11.6.4。无关的正式包路径不会影响显式 `xiaohe` 创建，损坏正式包失败后可显式重建双拼句柄。
- `DebugCodeTable` 改为正式包 A～J 验收，经 ArkTS → Node-API C++ → Rust 真链路在 x86_64 HarmonyOS 6.1 模拟器强停重启前后两轮通过。Debug HAP 为 40,387,851 bytes/SHA-256 `712DD5051B70D181BD178CD75755F38104F0DD5F03C0D6359EDAE0E028FB2CB9`。
- Release profile 的 5 个独立新进程样本记录加载 P50/P95 `631.64/658.1578 ms`、查询 P50/P95 `2.14/16.16 μs`、峰值工作集 114,237,440 bytes；OS 文件缓存未控制，因此不宣称冷启动。
- fmt、全 workspace Clippy、全部 Rust/ArkTS 测试、双 ABI Native 构建、正式 Debug/Release HAP、Release 正向门禁及正式包/fixture/原始 txt/trace/报告/INTERNET 六类负向门禁全部通过。最终 Release HAP 为 11,952,684 bytes/SHA-256 `4034F1EFEF559BC3A004119410966684B88FD0AA2BFF45DB00857C4612CC7A77`，rawfile 仅保留 `production.lex`。

### 完成阶段 11.6.2C 正式规范化与生产 bundle

- 新增独立无第三方依赖的 `engine-rust/tools/yinxing-converter` 和统一 PowerShell 构建入口；严格校验冻结 manifest、合同与脱敏配置哈希，只读取合同列出的八个“小鹤音形”权威文件，在任何行解析前完成全量路径、大小、符号链接和 SHA-256 预检。
- 实现 UTF-8/BOM、LF/CRLF/无末尾换行、注释、空行、配置头、普通记录、用户 `#删/#固/#N`、混合规则、命令/网络动作和 Unicode 边界的确定性分类。动作从不执行；5 条不支持命令和 1 条网络动作以稳定原因码拒绝，敏感原行不进入报告。
- 新增正式 `HSPYXP01` 1.0 容器和 `code-table-runtime` 严格加载路径，内部复用八个 `HSPLEX01` 1.1 分类表与现有用户规则合同；旧 `HSPCTF01` fixture 语义、生成器和 41 项运行时集成测试保持不变。
- 正式输入 963,555 bytes、73,319 物理行：普通记录 73,263，用户固顶 36，接受 73,299，转换 36，延期 0，拒绝 6，重复 0，冲突 0。总包 25,397,952 bytes，SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`，内容哈希 `a2b2a8500c68e7e904fbc6bdefa89e4e9cc821182a0c6cbe409e0ec045229f68`。
- 两个独立干净目录的 15/15 文件集合、路径、大小、字节和哈希完全一致；正式包加载、1～4 码、精确/前缀、分类与来源顺序、稳定去重、空/无结果、大重码翻页、用户固顶与篡改拒绝冒烟通过。输出绝对路径/网络地址/敏感名扫描通过，28/28 原始文件不可变。
- `cargo fmt --all --check`、workspace 全 target/feature Clippy、319 项 Rust 测试、Release 资源正负门禁和实际 Release HAP 扫描全部通过。正式包尚未进入 HAP，未修改 ArkTS、C++、C ABI、UI、设置或输入状态机。
- 11.6.2C 离线生产包结论保持 `COMPLETED`；其后的 11.6.3 正式系统查询回归现也已完成。

### 阶段 11.6.2B 阻断闭环并完成验收

- 根据用户明确授权，将客户提供数据的项目清理、转换、验证、产品使用和 HAP/客户交付权限写入审批元数据；来源记录为 `customer_provided`，未知接收日期不再构成技术阻断，也没有伪造日期或许可证编号。
- 客户原始 `ime.android.ini` 保持字节不变并完整留在 manifest 中，但整文件冻结为 `REJECTED_AND_QUARANTINED`、`conversion_input=false`、`eligible_for_hap=false`。新增确定性 `sanitized_configuration.json`，只保留源 SHA-256、物理行、类型、原因码和摘要哈希，不复制任何 INI 键或值，不可执行、不可转换、不可进入 HAP；允许转换范围内凭据为 0。
- 首版权威关系全部冻结：八类只使用 `小鹤音形/` 编号文件；分类/次选、二简次选、表外字、全码词、全码字的对应 `码表/` 导出改为 audit-only，首版不合并。9 组差异均已有稳定处理，人工确认项归零。
- 23 个缺失引用完成逐条处置：10 个未交付可选功能资源延期，13 个动态用户路径、Android/Windows 平台文件、旧系统表或通配符引用拒绝；不创建或伪造客户码表，缺失引用阻断数为 0。
- 审计 manifest/合同版本升级到 1.1.0，合同 `conversion_allowed=true`、阻断项为空。最终 Manifest SHA-256 为 `ef93b39e05a0e11c818f8dd837b3f5b2e87777ab02aaba374765a846be7dce55`，转换合同 SHA-256 为 `2353a4b41bd9b1e9aeb1e309cb6ae657078de0d133f624921086f68d82ad8692`，脱敏配置 SHA-256 为 `b4b7705055953e0c65d579767875516fd11c8c973af810b3821045551e0d04f0`。
- 两次正式默认审计均 exit code 0；10/10 机器产物逐字节一致，28/28 原文件路径、大小和 SHA-256 不变。Rust workspace fmt、全 target/feature Clippy 和 296 项测试通过；Release 正负资源门禁及实际 11,796,320-byte HAP 内容扫描通过。
- 阶段结论更新为 `11.6.2B COMPLETED，11.6.2C READY`。本轮仍未实现正式转换器、生产 bundle、运行时查询、UI/设置入口或跨层接口扩展。

### 阶段 11.6.2B 正式数据接收、权威清单与审计（BLOCKED）

- 新增无第三方依赖的 Rust 工具 `engine-rust/tools/yinxing-source-auditor` 和统一入口 `scripts/audit-xiaohe-yinxing.ps1`；只读递归扫描根目录 `码表/` 与 `小鹤音形/`，不跟随符号链接、不执行交付命令、不访问网络，并在每次运行前后核对原始文件路径、大小和 SHA-256。
- 28 个正式文件全部进入 `dictionaries/audit/xiaohe-yinxing/source_manifest.json`：总计 3,549,882 bytes，0 个不可读、0 个未知角色；记录编码、BOM、换行、物理/非空/注释/配置/数据/异常行数、文件 SHA-256、内容角色、四类判定和脱敏安全命中。Manifest SHA-256 为 `31cd29f5441cfbb2fb151ea3903f90f6d89417db2cefc0af86d05915367b7093`。
- 生成供 11.6.2C 使用的版本化 `conversion_contract.json`，冻结 `scheme_id=xiaohe-yinxing`、`bundle_id=xiaohe-yinxing-production`、显式分类顺序、用户规则分流、命令白名单/拒绝码、延期功能、安全策略、缺失引用和审批元数据；合同 SHA-256 为 `e3d0e83d26e81cbc4a7e02499e6492143bedd426c6d98b8f89f7f73fe4eb2ccb`，当前 `conversion_allowed=false`。
- 核心主表、一简次选、生僻字的权威来源已由唯一/编号交付结构确认；分类/次选、二简次选、表外字、全码词、全码字均固定“小鹤音形编号文件为权威、码表导出为补充”的建议顺序，但补充合并和冲突处理仍需人工确认，合同将这些分类标为阻断。
- 对同用途来源建立 9 组字节/规范文本/记录集合/记录顺序/语义角色差异比较；解析 38 条配置引用，其中 23 条缺失，未读取目录外文件。普通记录、`#删/#固/#N`、复合规则、`$cmd/$ddcmd`、配置、拼字、简繁、符号、直通和平台参考均按文件与物理行分流。
- 安全报告只保留类型、位置、稳定原因码和摘要哈希。静态扫描发现 URL、WebDAV、外部程序、平台路径、账号和凭据型字段；其中 4 条为已赋值凭据字段，触发 `BLOCK_EMBEDDED_CREDENTIAL`。网络、外部程序、平台命令和原始 Android 配置全部拒绝或隔离，不进入转换合同候选或 HAP。
- 新增 `docs/data-audit/XIAOHE_YINXING_SOURCE_AUDIT.md`、安全、冲突和审批状态报告；机器交付另含分类映射、命令策略、缺失引用、判定和比较 JSON。两次正式运行的 9 个机器文件逐字节一致，原始 28/28 文件两次不可变检查通过。
- Release 门禁补充拒绝任意原始 `.txt/.ini`、凭据命名文件和审计报告；正向控制与新增负例全部 PASS。Rust workspace `fmt --check`、全 target/feature Clippy 和 295 项测试通过，其中审计工具 18 项。
- 因正式来源仍含 4 个阻断型凭据字段、5 类补充合并关系待确认，且来源所有者、修改许可、分发范围和 HAP 分发许可仍为 `unknown`，阶段结论严格保持 `11.6.2B BLOCKED，11.6.2C NOT READY`。未实现正式转换器、生产 bundle、运行时查询、UI/设置入口或 C ABI/Node-API 扩展。

### 重启阶段 11.6 正式小鹤音形双链路

- 经理已确认根目录 `码表` 与 `小鹤音形` 的交付文件可用于项目，客户同意采用“小鹤双拼＋小鹤音形”双链路；项目计划将正式音形 ID 冻结为 `xiaohe-yinxing`，并把重启起点固定为 11.6.2B 正式数据接收、权威清单和转换合同。
- 移除已停止使用的自有码表离线研究工具、Unicode 属性输入、生成产物、研究文档和对应来源门禁；这些资产从未进入 ArkTS、C++、正式 Rust 运行时或 HAP。Rust workspace 与 Release 门禁同步解除离线依赖，保留通用 fixture、码表后端、用户覆盖和 Release 测试资源隔离。
- 重写阶段 11.6：保留已完成的 11.6.1、11.6.2A、11.6.3、11.6.4，新增 11.6.2C 正式转换/bundle，并重新启用分类、引导/安全直通、四码提交/顶屏/空码切分、产品接入和发布验收。

### 完成客户修改 3.8、4.1、4.2 最终修正与验收

- 阶段 3.8 由静态 SDK 判断继续验证到真实运行：API 24 Pad 模拟器能够提供光标绝对
  坐标，但第三方输入法创建 `FLAG_CANDIDATE` 面板返回错误码 `1`，因此推翻旧路线 B，
  最终采用路线 C。Phone 保持顶部候选栏，Pad `AUTO` 使用固定右侧候选条；设置中的
  “跟随光标（实验）”真实禁用并显示平台原因。
- Pad 侧栏与顶部栏共享 `InputSessionStore.candidates/rawInput` 和
  `KeyboardController.commitCandidate(index)`，不复制查询、排序、分页、组合或学习路径。
- 阶段 4.1 修正为精确显示用户原始 `rawInput`；即使引擎 `preeditText` 含分段格式，
  `nihc` 仍原样以下划线展示。所有组合清理生命周期保持通过。
- 阶段 4.2 新增统一 `CandidateDisplayItem`，顶部栏、Pad 侧栏、保留浮动组件的视觉和
  无障碍文案只显示 `candidate.text`；`candidate.reading` 仍完整保留在跨层数据协议中。
- Phone x86_64 浅色与 Pad x86_64 深色设备证据通过，包含精确 `nihc`、候选无 reading、
  Pad 侧栏点击提交/收起和设置禁用语义。
- ArkTS 全量测试 284/284 PASS；Rust workspace fmt/clippy/test PASS；Release HAP 构建、
  资源正负门禁和包内容检查 PASS。最终 unsigned HAP 为 11,796,320 bytes，SHA-256
  `E27283BCE6273E35B57DFC0E7FC37B426E32CEDFE832B570CCC9151022686B3D`。
- 真实 USB/蓝牙键盘、ARM64 物理真机、第三方浏览器和 Pad 分屏未执行；设置 Ability 与
  `:inputMethod` Extension 的跨冷启动非默认设置共享仍需发布侧 AppGroup/Data Group。
  默认 `AUTO` 路线、候选显示和提交不受影响。

## 2026-07-21

### 完成客户修改阶段 4.1 未上屏输入码下划线提示

- 新增 `domain/candidate/CompositionPreeditView.ets` 纯函数模块：`resolveCompositionPreeditView(rawInput, preeditText)` 返回 `{ visible, displayText, decoration }`；`rawInput` 非空时 `decoration=UNDERLINE`，空时 `visible=false`。该模块不修改任何字符串，不向引擎传入下划线字符，也不影响正式提交内容。
- `CandidateBar` 新增 `rawInput` prop（默认 `''`）；新增 `PreeditChip` @Builder 使用 `Text.decoration({ type: TextDecorationType.Underline, style: TextDecorationStyle.SOLID, color: palette.candidateText })` 渲染带下划线的组合编码；浅色/深色均使用 `palette.candidateText` 保证对比度。
- 候选存在时，未上屏输入码显示在候选横向滚动行的最左侧（与候选共用同一 Row，不增加候选栏高度）；无候选时，下划线输入码作为 `CompositionView` 的核心 Text 展示（保留原有 `parserState` 辅助文字）。`rawInput` 为空或 `contentVisible=false` 时均不渲染。
- `KeyboardRootStage3` 向 `CandidateBar` 补传 `rawInput` 字段。
- **HarmonyOS API 能力结论**：`InputClient.setPreviewText(text, range)` 自 API 12 起参数固定为 `(string, Range)`，没有为输入法指定预编辑文本样式的接口；系统侧预编辑的视觉效果完全由宿主编辑框决定，输入法侧不能可靠强制。因此本阶段仅采用键盘顶部候选栏自绘下划线作为统一回退方案，继续保留现有 `setPreviewText / finishTextPreview` 调用链不变。
- 生命周期清理路径（候选提交、空格、回车、删除至空、切换焦点、隐藏键盘、会话结束、Extension 销毁）均已由既有 `InputSessionController / ImeConnectionService / InputSessionStore` 管理，本阶段不新增清理路径。
- 修复 `Stage38.test.ets` 中预存在的 5 个 ArkTS 类型错误（untyped object literals），不属于 4.1 功能改动。
- 新增 `entry/src/test/Stage41.test.ets`：15 项自动化测试，覆盖纯函数逻辑（7 项）、Store 生命周期（6 项）、并发保护（3 项）、数据结构回归（4 项）；已在 `List.test.ets` 注册。
- ArkTS 单测 `Tests run: 273, Failure: 0, Error: 0, Pass: 273`；Release HAP BUILD SUCCESSFUL（11,901,095 bytes，SHA-256 `b4229caf...`）；Rust workspace fmt/clippy/test PASS。
- **未执行**：模拟器/真机安装运行、系统文本框/浏览器/多行文本框设备截图验收；上述项目需在具备完整 DevEco 工具链的环境中补跑。详见 `docs/evidence/customer-feedback/stage4_1/stage4_1_validation.md`。
- 未提前实现客户建议 4.2（候选词后不显示全拼码，已在上面单独完成）、4.3 输入码两码切分、4.4 自定义简拼；未新建浮动候选窗。

### 完成客户修改阶段 4.2 候选词后不再显示全拼码

- 普通 `CandidateBar` 候选项从 `Row(Text(candidate.text) + Text(candidate.reading))` 改为单个 `Text(candidate.text)`：候选文字后不再显示全拼、双拼码或其他辅助编码，候选项宽度改为随文字自适应，不再按 `candidate.reading` 长度占位；点击热区随文字容器与 8vp 左右内边距一起收敛，同屏可容纳更多候选，滚动、翻页、组合状态、错误状态和加载状态均未变。
- `Candidate.reading` 字段、`CompositionResult.candidates[].reading` 传输、`napi_converter.cpp` 的 `SetNamedString(env, candidate, "reading", ...)` 和 `NativeEngineGateway` 的 `reading: candidate.reading` 映射未改动；Rust 引擎候选生成、排序、用户学习和用户词库规则未修改，`internalDebug` 侧调试页面仍可通过原有数据结构访问 reading，不会出现在 Release 普通候选栏中。
- 新增 `entry/src/test/Stage42.test.ets`：覆盖候选类型 `reading` 字段保留、`InputSessionStore` 快照保留候选 `text` 与 `reading`、候选顺序不变、长候选保留完整 `text/reading`、提交路径以 `candidate.text` 为准五个契约；已在 `List.test.ets` 注册。
- 未修改 `NativeEngineTypes`、`InputSessionController.commitCandidate`、`selectCandidate` 逻辑、`FloatingCandidatePolicy`、候选栏容器高度、`candidateFontSize` 或键盘布局；未提前实现阶段 4.1 预编辑下划线、4.3 输入码两码切分、4.4 自定义简拼或浮动候选窗。
- 未执行：真机 ARM64、Pad 分屏、外接键盘和 HAP 构建；本会话仅具备静态检查与 ArkTS 单测环境，需在具备完整 DevEco 工具链的机器上再跑 `assembleHap default + ohosTest` 与真机验收。

### 完成客户修改阶段 3.8 浮动候选窗能力验证与实验性设置

- 完成 HarmonyOS SDK 能力盘点：`inputMethodEngine.on('cursorContextChange', (x, y, height))` since API 8 提供物理屏幕绝对坐标；`PanelFlag.FLAG_CANDIDATE` since API 15 提供由输入法自行 show/hide/moveTo 的候选窗；`Panel.moveTo(x, y)` since API 10 对非 FIXED 面板可用。工程 `compatibleSdkVersion=6.1.1(24)` 已满足。证据集中在 `docs/STAGE_3_8_FLOATING_CANDIDATE_CAPABILITY.md`，逐条引用 `@ohos.inputMethodEngine.d.ts` 与 `@ohos.inputMethod.d.ts` 行号。
- 选择实施路线 B（部分支持，实验功能）。宿主 `updateCursor` 触发行为、跨应用焦点抢占、Pad 分屏和外接物理键盘在本会话仅有模拟器可用，不允许写成真机已完成；本阶段严格不创建 `FLAG_CANDIDATE` 面板，也不移动窗口，以免在未验证前引入"伪浮动窗"。
- 新增域层纯函数：`domain/candidate/FloatingCandidatePolicy.ets` 集中决策规则；`resolveEffectivePresentationMode` 覆盖手机→BAR、Pad 无外接键盘→BAR、SDK 不支持→BAR、无锚点→BAR、Pad+外接键盘+已收到锚点→FLOATING、显式 FLOATING 无锚点→BAR。`domain/candidate/FloatingCandidatePosition.ets` 覆盖下方优先/上方回退、左右夹紧、上下都不足时限制高度、无效光标 rect 校验。
- 新增设置项 `候选窗位置`（自动 / 键盘顶部 / 跟随光标（实验））。默认 `AUTO`；`SettingsValidator`/`copyImeSettings`/`imeSettingsEqual`/`settingsToRaw` 一致扩展，无效值安全回退 `AUTO`。SDK 能力不足时 UI 层禁用"跟随光标"选项并显示"当前系统或设备不支持候选跟随光标"说明。
- 新增 `infrastructure/ime/FloatingCandidateCapabilityProbe.ets`：只读取 `deviceInfo.sdkApiVersion` 判断静态 SDK 能力；不订阅事件、不创建窗口，避免"能力探测"变成副作用。会话侧能力（是否允许候选、是否收到锚点）由未来接入实际浮动窗时补充。
- 候选状态仍由 `InputSessionStore` 单一来源；提交路径仍走 `KeyboardController.commitCandidate(index)`，未复制候选、未引入第二套查询，未修改现有中文输入、候选点击、翻页、删除、空格确认或用户学习。
- 新增 `Stage38.test.ets` 定向单测：覆盖决策规则所有分支、位置算法上下左右夹紧与高度收缩、`isCursorRectUsable` 校验、设置项 copy/equal/toRaw/validator。已注册到 `List.test.ets`。
- ArkTS `assembleHap default + ohosTest` 构建通过，只保留原有非本阶段的 deprecated/异常告警；未修改 Rust、Native、词库、Release 资源门禁。
- 未执行：`cursorContextChange` 实际触发频率、跨应用行为、Pad 分屏、外接键盘、真机能力矩阵——由 `docs/STAGE_3_8_FLOATING_CANDIDATE_CAPABILITY.md` 第七节记录，需真机补测。

### 完成客户修改阶段 3.5 输入法切换与手机底部辅助区

- 新增纯窗口度量的 `KeyboardAuxiliaryAreaPolicy`：以可用短边区分 Phone/Pad，并结合方向、密度、底部系统 inset 和键盘高度模式决定手机辅助行；不读取设备型号。API 21+ 的系统面板 bottom inset 在创建/旋转/resize 前刷新，失败安全回退为 0。
- Pad 文本布局在 `123` 与语言键之间增加通用输入法图标，保持三行字母结构、其他功能键权重与空格行总权重稳定；手机辅助行独立增加面板高度，不压缩四行主键区，左侧切换、右侧收起、中间留白。
- 新增 `InputMethodSwitcher` 系统适配器。目标 API 24 使用已启用输入法枚举、当前输入法查询和指定输入法切换组合“下一输入法”；列表不足、当前项缺失、切换失败或异常时回退系统选择器。系统 API 不进入 UI 层。
- 新增 500ms 短按/长按互斥状态机、请求进行中与 700ms 冷却保护、输入会话 generation 失效保护。设备验收发现并修复 ArkUI `onClick` 可早于 `TouchType.Up` 的短按漏触发问题，同时兼容无障碍仅 Click 事件；长按后不会补发短按。
- 手机辅助收起键和顶部状态栏收起键统一发送 `HIDE_KEYBOARD`，复用组合清理、模型 flush 和系统隐藏流程。系统能力不可用时隐藏无效入口；错误只呈现通用用户提示，日志不包含输入内容或候选文本。
- 新增能力矩阵、Stage 3.5 单元/设备验收脚本和证据。ArkTS 221/221、Rust workspace、Debug/Release HAP、Release APP 与 Release 内容门禁通过；1320×2856 Phone 和 2880×1920 Pad 模拟器均通过短按切换，Pad 长按系统选择器和 Phone 辅助收起也通过。物理真机、三键导航与外接键盘仍待验收。

### 完成客户修改阶段 3.4 中文大写键帽与跨设备视觉校正

- 中文 QWERTY 三行在普通组合、大写直输锁定和非空分词状态下均固定显示 `QWERTYUIOP / ASDFGHJKL / ZXCVBNM`；按键 ID 与动作继续携带小写 `a-z`，输入控制器在进入 Rust 前仍统一执行小写归一化。
- 按键预览继续读取键帽 `label`，无障碍文案由同一大写标签生成；英文普通、单次 Shift 和 Caps Lock 的大小写状态机保持不变。
- 状态栏隐藏键从受设备字体基线影响的文本字符 `⌄` 改为固定 `24vp` 矢量图标，由与普通按键一致的 Row 容器做水平和垂直几何居中；手机和平板布局树中心误差均不超过 `2px`。
- 字母字号下调：静态竖屏 `18→16vp`、横屏 `16→15vp`，动态手机/Pad 使用键高 `0.36` 比例并限制为 `13–21vp`；预览字号同步收敛到 `20–32vp`，键位尺寸、间距与点击区域不变。
- 补充 A-Z 显示/输入分离、预览/无障碍、中文引擎小写归一化、英文 Shift 回归、字体上限和矢量图标合同测试。ArkTS 单测和双 ABI Debug HAP 构建通过；1320×2856 竖屏手机与 2880×1920 横屏平板模拟器定向验收均 PASS，真实设备尚未执行。

### 完成客户修改阶段 3.3 中文动态键与结构化分词

- 中文第三行 Z 左侧改为固定动态键：空组合显示 `⇧` 并切换独立中文大写直输锁定，非空组合显示 `'` 并插入显式分词边界；键位 ID、宽度、权重和点击区域保持不变，辅助功能文案与按键预览同步变化。
- 大写直输仅在中文空组合有效，A-Z 直接提交编辑器，不触发 Rust、候选、预编辑或用户学习；模式/编辑器/会话变化、键盘隐藏、失焦恢复、重置、异常和 Extension 销毁均清锁。
- 新增 ArkTS、Node-API、C++、C ABI 与 Rust 的独立 `insertSegmentBoundary` 链路和 `segmentBoundaries` 结果字段；禁止用普通 `processKey` 传递分隔符。空、连续和不完整分词无损失败，退格先删除边界，部分候选和最终提交不泄漏 `'`。
- 3.2 隐藏键 `⌄` 在固定点击区域内上移 `2vp` 做光学居中，不改变布局与热区。
- 新增 3.3 设备验收脚本和证据。ArkTS 203/203、Rust workspace 测试、fmt、Clippy、双 ABI Debug 构建通过；1320×2856 竖屏手机与 2880×1920 横屏平板模拟器定向验收均 PASS。

## 2026-07-17

### 配置 0.1 Release 签名并同步发布状态

- 将工程版本统一为 `versionName=0.1.0`、`versionCode=1000000`；`bundleName` 保持 `com.corrosion.shuangyuime`，vendor 保持“科爱思（深圳）科技有限公司”。
- 为 `default` 产品接入本机 HarmonyOS Release signing config；`internalDebug` 仍不引用发布签名配置，Debug/Release source set 隔离不变。
- 项目级 Release 构建已同时生成 signed/unsigned APP；signed APP 为 4,709,283 bytes，SHA-256 `CC59D51C479C106A38E7F5F88B4C555A6D9566C8EA385113A5AE7A51FA980A9A`。直接 HAP 构建也生成 signed HAP，最新文件为 12,536,169 bytes，SHA-256 `BF1B6051264AB9FD1E4A4BB2EFF9A17C46560E488FD3A1645672CD92FCCD5475`。
- 签名材料使用仓库外绝对路径；文档不记录真实凭据。当前只确认构建器产出 signed 文件，仍需签名工具复核证书/Profile/包名、AGC 软件包基础检测、ARM64 真机和签名升级连续性验收。
- `scripts/build-hap.ps1` 继续保留 `entry-*-unsigned.hap` 作为内容门禁输入；不得把该 artifacts 文件误作客户上传包。

### 修复浏览器清空搜索框后的旧组合残留

- `CompositionTextManager` 增加组合文本附着检查；兼容模式会读取当前光标前文本并容忍编辑器异步收敛，识别宿主已静默删除的旧组合范围。
- 下一次中文按键前若发现旧组合已脱离编辑器，连接层只重置本地预览所有权和 Rust 组合，从当前按键开始新组合，不回写已失效文本。
- 预览/兼容写入、提交、清理和附着检查统一绑定输入会话 generation；输入停止、键盘隐藏、编辑框切换或 Ability 销毁后的旧异步完成结果不能更新新会话。
- 补充静默清空后新字母、`discardTypingText`、延迟编辑器收敛、陈旧 generation、隐藏/重开和生命周期清理回归。

## 2026-07-16

### 完成无 Debug Release 隔离并修复设备验收旧断言

- 新增 `internalDebug` 构建 target/source set。`DebugIndex`、`DebugStage10`、`DebugCodeTable` 与 `CodeTableFixtureInstaller` 迁入 `entry/src/internalDebug`；正式设置页抽为共享 `SettingsPage`，Release 的 `entry/src/main` 不再保存 Debug 页面、路由或“调试与验收”文案。
- `default` Release 的 `main_pages.json` 和 target pages 只登记正式设置页、历史 Stage0 页及正式键盘页；`internalDebug` 使用独立入口资源和页面清单，并只在 Debug 构建期间生成/注入原创码表 fixture。
- `build-hap.ps1` 按 Release=`default`、Debug=`internalDebug` 构建；为兼容 Hvigor 页面解析限制，Debug 构建只在编译窗口内复制内部页面到预期路径，并在 `finally` 中清理，构建前后 `src/main` 均保持无 Debug 页面源码。
- Release 门禁扩展为同时扫描 `entry/src/main` 与最终 HAP 的 ArkTS/Native 内容，拒绝 `DebugStage10`、`DebugCodeTable`、“调试与验收”、内部 fixture 和既有调试探针；正负门禁自测通过。
- 手机设置持久化脚本不再写死三档旧像素值，改为从 `InputPanelController` 日志提取实际请求宽高，并严格匹配系统 `ResizePanel` 成功尺寸；同时校验当前 IME 包名、Debug 启动页导航、选中态和跨进程持久化，避免设备残留旧包造成假失败。
- 平板 Stage 10 脚本不再用旧绝对 Y 范围查找“123”等键，而是在当前 `KeyboardRootStage3` 可见根节点边界内定位语义节点；完整编辑器类型、Shift、数字/符号和回车动作验收通过。
- phone `1320×2856` 实测三档动态尺寸分别为 compact `1320×959`、standard `1320×1082`、tall `1320×1211`，设置持久化与最终默认值恢复全绿；tablet `1920×2880` Stage 10 全流程通过。
- ArkTS 184/184 通过，PowerShell 脚本解析通过。最终 Release HAP 为 11,670,662 bytes，SHA-256 `53E29AC8486802E66DA6D9398F1AF1F1F72B4B00215737EF9C30A107F4834FE0`；Release 源码扫描、资源正负门禁和 HAP 包内扫描均 PASS。产物仍未配置发布签名。

### 完成 0.1 交付与发布准备审计

- 以“小鹤双拼为唯一正式范围”重跑生产词库、Rust fmt/clippy/workspace tests、双 ABI Native、ArkTS、Release HAP 内容门禁、Debug HAP 和项目级 Release APP 构建；核心链路通过。
- 在 phone `1320×2856` 与 tablet `1920×2880` 模拟器安装运行 Debug/Release 包；确认两端只显示小鹤双拼，Debug 有验收入口，Release 无可见入口，输入面板实际 `ResizePanel` 成功。
- Release 实包审计确认 `DebugStage10`、`DebugCodeTable`、路由和调试文案仍进入 `modules.abc/resources`；当前 `BuildProfile.DEBUG` 只实现入口隐藏，不满足严格无 Debug 二进制交付。
- `assembleApp` 成功生成未签名 APP，但 `signingConfigs` 为空，应用包名/vendor/版本仍是占位信息；记录企业认证后的 AGC、签名、测试、隐私、备案、资质和提交审核步骤。
- 发现手机三档高度脚本的固定像素预期和平板 Stage 10 的“123”语义节点断言已过期；实际动态尺寸和键盘显示正常，自动门禁待更新。
- 新增根目录 `0.1版本交付验收.md`，并同步 README、构建指南和当前状态。

### 修复部分候选连续提交产生 `输入fa法`

- 修复 `uurufa` 先选择“输入”、再选择“法”时真实编辑框得到 `输入fa法` 的问题。根因是 HarmonyOS 6.1 的 `finishTextPreview()` 已完成后，`getTextIndexAtCursor()` 仍可能返回旧预编辑 `uurufa` 的末尾位置 6；剩余 `fa` 因此被错误记录为 `6–8`，后续候选无法替换该范围。
- 候选提交现在保留旧预编辑的绝对起点，并以“起点 + 已提交候选长度”计算可信的新锚点；部分提交后的剩余原始输入切换到兼容范围模式，不再立即重启系统 PREVIEW，也不依赖陈旧游标读数。后续输入、退格和候选提交继续只操作剩余范围，已提交前缀不受影响。
- `TextPreviewManager` 在结束系统预编辑后让出一个任务轮次；`CompositionTextManager` 新增已提交末尾锚点的一次性传递和消费，普通新组合、会话重置及非部分提交路径不会复用旧锚点。
- 新增两层回归：预编辑延迟释放时不得立即重启，以及系统游标仍为 6 时必须用可信锚点 2 将 `fa` 精确替换为“法”；控制器测试同时断言剩余文本强制进入兼容模式并携带候选提交锚点。ArkTS 全量 184 项通过、0 失败、0 错误。
- 扩展设备脚本新增 `-OnlyPartialCommit` 专项入口。tablet `127.0.0.1:5557` 上真实 TextInput 已通过 `uurufa → 输入 → 法 → 输入法` 严格相等断言，`STAGE11_5_DEVICE_ACCEPTANCE_RESULT=PASS`。
- Debug/Release HAP 均重新构建通过；Release HAP 内容门禁通过，产物为 11,487,144 bytes，SHA-256 `F493E249E086EF4B617AE771F43A866707E77EFE265295F5E51A3185F92A58D0`。

### 修复输入法横竖屏初始化、旋转度量同步与 Stage 11 假绿

- 新增领域层 `ScreenMetricsPx` 完整快照和可注入 `DeviceMetricsProvider`：Ability 创建、首次输入会话及配置更新都会在首次 `panel.resize()` 前发布方向、宽度、高度与密度；配置方向有效时优先采用，并在 display 宽高晚一拍时成对交换，避免横屏首次启动沿用竖屏状态。
- `InputSessionStore` 原子保存完整屏幕快照，重复快照不通知；方向/尺寸更新不重置组合文本、候选、键盘模式或学习状态。`KeyboardRootStage3` 与 `InputPanelController` 改为消费同一份快照，旋转后不再由 UI 单独读取旧 display 尺寸。
- 明确单位边界：display 与 `panel.resize()` 使用 px，ArkUI 键盘度量使用 vp，并按 `densityPixels` 显式转换；移除候选栏高度的固定三倍换算。面板去重同时比较宽高，保留原串行队列与 generation 合并机制。
- 为 0、负数、NaN、Infinity、异常密度和明显不可用的显示区域增加统一安全回退；动态候选栏、按键、功能行、字体、间距、padding、圆角与总面板高度均有限正数上下界，最终宽高为正且面板高度不超过有效屏幕高度。
- 扩充 ArkTS 回归：覆盖 2880×1920 横屏、1920×2880 竖屏、横竖旋转、重复快照去重、三档高度单调变化、候选栏显示/隐藏、异常尺寸回退、配置方向修正旧宽高，以及旋转保留组合与候选状态。
- `verify-stage11.ps1` 现在删除旧 `test_result.txt`，要求本轮生成新报告，并校验逐项结果与 `Tests run/Failure/Error/Pass/Ignore` 汇总；hvigor 即使退出码为 0 或打印 `BUILD SUCCESSFUL`，只要存在失败、错误、非 Success 结果、陈旧/缺失报告或汇总不一致，门禁都会退出 1。正常 ArkTS warning 不作为断言失败。
- 修复设备验收脚本在平板横向宽页面上把“用户学习”误当“按键音”Toggle、以及中英文模式标签和按键纵坐标范围过时的问题；支持在基础 Stage 11 已通过后单独复跑扩展输入验收。
- Debug HAP 构建通过（14,280,123 bytes）；Stage 11 全量门禁与 Release HAP 内容检查通过，Release HAP 为 11,486,520 bytes，SHA-256 `D20AF1D4AA609AD76F58415D06E1DF9C1D0C4674121AAC8B50DAFA94D0E3C441`。
- phone `127.0.0.1:5555`（1320×2856）与 tablet `127.0.0.1:5557` 的基础 Stage 11 设置、三档高度、真实 `ni` 候选/提交、学习数据清理回归均通过；两端扩展整词输入 `nihc→你好`、`uurufa→输入法` 及多词/句子提交通过。平板验收时系统当前处于 1920×2880 竖屏，未取得 2880×1920 首次横屏实机回调证据；部分候选连续提交问题已由同日上方专项修复并通过真机验收。

## 2026-07-15

### 完成阶段 11.6.4 用户码表规则接入

- 在 `user-lexicon` 复用既有解析器、规则模型和不可变快照，新增码表候选覆盖：按候选完整编码＋词条精确删除，随后普通新增、多个固顶、1-based 全局位置、固顶保护、后规则覆盖与稳定去重；精确删除后不二次回退系统前缀。
- `CodeTableStateMachine` 先查询完整系统结果、再应用用户覆盖，最后限量与分页；状态持有 `Arc<UserLexiconSnapshot>`，支持原子替换和并发只读，系统 bundle 保持不可变。
- `ImeEngine` 在创建和方案切换时把同一用户快照交给码表后端；reset、句柄重建和清空学习不删除用户规则，主文件损坏沿用既有备份恢复/空覆盖降级。没有新增 C ABI、配置字段或结果字段，interface/ABI version 保持 2，C++ 未改。
- Rust workspace `fmt`、`clippy -D warnings` 和全量测试通过；`user-lexicon` 17 项、`code-table-runtime` 41 项、`ime-engine` 码表集成 13 项、`ime-ffi` 19 项。ArkTS 单元测试与 x86_64/arm64-v8a Native 构建通过。
- Debug-only A～J 在 x86_64 HarmonyOS 6.1 模拟器全部 PASS；首次进程创建记录 `reusedExisting=false`，强停并重启应用后为 `reusedExisting=true`。覆盖新增、精确删除、固顶、`#2`、后规则、全列表分页、进程重启、备份恢复和切回 `xiaohe`。
- Debug HAP 为 14,275,678 bytes/SHA-256 `1F4CA1189CDA66B71E7AD0D215CF800986E91FA09D8A9A3A46C88BAD9AE2305F`；Release HAP 为 11,487,053 bytes/SHA-256 `96EF0230183B84D6495E4561B192378E6EAA79945CA669A850B193D99580C533`，发布检查和资源正负门禁 PASS，fixture 与 Debug 用户文件未进入 Release。
- 阶段 11.6.2B 正式来源/授权继续 `BLOCKED`；正式方案仍只有 `xiaohe`，11.6.5～11.6.9 未提前实现，ARM64 物理真机与正式签名仍待后续。

### 完成阶段 11.6.3 系统码表运行时查询

- 新增 `code-table-runtime` Rust crate，严格加载 `HSPCTF01` 1.0：校验 magic/版本/长度/保留位、内容 SHA-256、manifest schema 与分类元数据、guide 隔离、嵌套 `HSPLEX01` CRC/边界及连续 `source_order`，并提供稳定结构化错误。
- 实现原始编码 `CodeTableStateMachine`：空输入不枚举；精确命中时不混入前缀；无精确时按分类顺序和分类内源行顺序回退；跨分类稳定去重；完整合并后再限量和分页；退格、新键、reset、非法键、64-byte 上限和越界页均有确定行为。
- `ime-engine` 新增 Rust 内部 `Shuangpin/CodeTable` 双后端策略；内部 `code-table-fixture` 路径绕过双拼解析、生产拼音词库、整句解码、ExistingRanking 和用户学习，方案切换会清理旧组合并保持 `xiaohe` 行为隔离。
- 沿用 interface/ABI version 2，在既有 EngineConfig JSON 增加可选 `codeTableBundlePath`；ArkTS、Node-API C++ 和 Rust FFI 只做配置转发。C++ 可选属性读取同时兼容缺失、`undefined` 和 `null`。
- 新增 Debug-only fixture 安装器和阶段 11.6.3 验收页。Debug 构建临时生成并注入原创 bundle，构建结束后删除源码资源；Release 构建不注入，也不显示产品可用方案。
- Rust workspace `fmt`、`clippy -D warnings` 和全量测试通过；新增码表 runtime 33 项、引擎集成 7 项，FFI 共 18 项。ArkTS 单元测试、x86_64/arm64-v8a Native 构建和 Debug/Release HAP 构建通过。
- x86_64 HarmonyOS 6.1 模拟器通过 A～H 真实跨层验收：空输入、精确优先、前缀回退、跨分类去重、分页、退格、超长保护，以及切回 `xiaohe` 后“你好/输入法”回归。
- Release HAP 为 11,353,521 bytes，SHA-256 `4473AAC84D06E1E65934473A1838CBB59B358BD2B57E70E19B08B4FA4D45C8E4`；Release HAP 检查和资源门禁测试均 PASS，包内不含 fixture/test/synthetic/code-table rawfile。
- 当时阶段 11.6.2B 正式来源/授权继续 `BLOCKED`，且 11.6.4～11.6.7 与后续产品接入均未提前实现；其后 11.6.4、11.6.5 和 11.6.6 已按各自阶段推进，11.6.7 仍未实现。

### 完成阶段 11.6.2A 原创模拟码表与构建门禁

- 新增独立 Rust 离线工具 `code-table-fixture-generator`，只使用项目原创测试标签、固定编码结构和确定性序号生成 `core/phrases/extended/domain/symbols = 8000/6000/5000/4000/2000` 条普通码表及 2,000 条隔离 guide；不读取网络、第三方码表、系统时间、随机数或 `production.lex`。
- 新增版本 1 显式 JSON manifest，记录测试 bundle ID/显示名、`fixtureOnly`、分类 ID/显示名/相对路径/order/默认开关/数量/SHA-256 和 guide 元数据；拒绝重复 ID/order、绝对路径、`..`、缺失文件、数量/SHA 不符及 category/guide 混放。
- 复用 `FlypyTableImporter` 和 `HSPLEX01` 1.1 为每分类持久化物理有效行 `source_order`；新增测试专用 `HSPCTF01` 1.0 容器，记录分类元数据、整体构建输入 SHA-256、内容 SHA-256 和嵌套二进制，不改变 `production.lex` 1.0/1.1 兼容性。
- 系统码表严格校验覆盖 UTF-8、LF/CRLF/BOM、TAB 字段、空字段、前后空白、非法/超长编码、超长/非法词条、NUL/控制字符、`#删/#固/#N` 和同分类完全重复；错误包含稳定错误码、文件、物理行、字段和脱敏原因。
- 新增人工可读黄金 fixture、14 项声明式负面 fixture 及 15 项 Rust 测试；覆盖 1～6 码长、同码 1/2/5+/20+、分页、前缀链、跨分类重复、Unicode/ASCII/混合/符号/长度边界、manifest、SHA-256、二进制往返和损坏检测。
- 两个独立目录的 14 个输出逐文件 SHA-256 全部相同；两次 bundle 均为 2,024,260 bytes，SHA-256 均为 `345887C1F6052514758A1D3F53B4F280E6FF04086AB1736582C9A8CCD42DF71C`。最终门禁生成耗时 89/93 ms，bundle 构建耗时 2,475/2,388 ms；峰值内存未获得可靠跨平台数据。
- `verify-release-hap.ps1` 新增源码资源输入白名单和最终 HAP rawfile/fixture 扫描；`test-release-resource-gate.ps1` 证明 production-only 通过、加入 fixture bundle 必须失败。重新构建的 Release HAP 仍只包含正式 `production.lex`，大小 11,006,078 bytes，SHA-256 为 `5B3998256370D1BC945565D9516E819AB2AF657762B129FDBD066534DB7F51CA`。
- 当前唯一正式方案仍为 `xiaohe`，未修改 ArkTS、C++、C ABI、设置、正式资源或运行时查询。阶段 11.6.2B 正式来源与授权验收继续 `BLOCKED`，不得把测试数据命名或宣传为正式“小鹤音形”。

### 完成阶段 11.6.1 需求冻结与双后端边界

- 新增 ADR 0015，冻结 `ime-engine` 统一门面下相互隔离的双拼后端和码表后端；`xiaohe` 继续使用双拼解析、生产拼音词库、整句解码、ExistingRanking、用户学习与用户覆盖，码表后端禁止经过这些拼音业务排序。
- 新增码表行为规范，明确空字符串与“空码”的区别、精确优先/前缀回退、分类和 `source_order`、用户硬规则、完整列表后分页，以及默认均为 4 的自动上屏/空码清屏/顶屏逐键状态表。
- 冻结第五键为下一段首键并恰好重放一次；旧段没有首选时不提交，清空旧段后仍处理当前键；每次引擎操作最多产生一个可见提交。
- 冻结 `Idle/NormalCode/GuidePrefix/GuideCode` 分号引导状态、事件表和全生命周期 reset 矩阵；引导只查专用表，不触发普通码表三码长规则。
- 基于真实 Rust、C ABI、C++ 和 ArkTS 代码完成协议评估：现有 `commitText + 操作后 rawInput` 足以表达顶屏提交与剩余组合，不增加 `commitReason/clearReason/remainingRawInput/backendId`，interface/ABI version 均保持 2。
- 新增正式码表来源、授权和规则审计清单；提供方、正式名称、版本、分类/引导表、商业使用、修改、二进制转换和随 HAP 再分发权目前全部“未确认”。
- 测试内部 ID 冻结为 `code-table-fixture`、显示名“码表输入（测试）”，不得进入 Release；正式方案 ID/名称未定，当前唯一正式方案和安全回退仍为 `xiaohe`。
- 同步更新架构、API 契约、测试计划和项目状态。本阶段只修改文档，没有实现码表查询、分号路由、自动上屏、空码清屏、顶屏、设置入口或正式码表资源，未改变正式运行行为。

### 同步当前状态与独立码表链路规划

- 将根目录 `PROJECT_STATE.md` 重构为单一当前状态入口，移除阶段 10、11、11.5 的重复验收流水账；历史细节继续保留在 `docs/evidence/`、ADR 和本更新日志中。
- 在项目计划中加入阶段 11.6：保留现有小鹤双拼，规划独立固定码表后端，并分解正式码表门禁、原始编码查询、用户规则、分类、分号引导、三码长状态机、跨层接入和真机验收。
- 同步 README、架构、项目结构、API、测试计划和词库规则建议；所有文档均明确当前正式运行时仍只支持 `xiaohe`，码表模式尚未编码，也未取得可随 HAP 分发的正式小鹤音形码表。
- 本次只修改文档，没有修改运行时代码、跨语言接口、词库资源或设置 UI。

### 修复沉浸式设置/Debug 页面安全区并固定 Debug 浅色外观

- 设置页和 `DebugStage10` 改为“全窗口背景层 + 安全内容层”：背景继续扩展到 `SYSTEM`/`CUTOUT` 四边，滚动视口按主窗口实际系统栏、挖孔和导航指示器避让区动态收缩，不使用固定状态栏高度。
- `HarmonySettingsWindowBackend` 使用 API 24 的 `getWindowAvoidArea`、`avoidAreaChange` 和 `UIContext.px2vp` 跟踪四边 inset；查询、监听、换算和注销失败均只记录日志，协调器停止时按同一回调注销。
- `SettingsWindowCoordinator` 新增带令牌的页面外观覆盖。Debug 页面显示期间固定白色窗口/系统栏、深色系统栏内容；设置保存、系统主题变化和前台恢复不能越过覆盖，退出后恢复当时设置页实际主题。
- Debug 固定浅色未调用 `setColorMode(LIGHT)`，输入法键盘仍按用户主题显示；快速进出页面、快速主题切换继续由版本号和串行 Promise 队列保证最后状态获胜。
- 新增固定浅色、覆盖优先级/恢复/陈旧令牌、异步竞态、能力失败和避让区几何单元测试；Stage 11 设备脚本新增标题/底部输入框边界断言和往返截图。
- ArkTS 单元测试与 Debug HAP 构建通过。x86_64 HarmonyOS 6.1.1 模拟器在系统深色、输入法强制深色下确认 Debug 页面及上下系统区固定浅色、系统栏图标为深色、深色键盘不改变页面浅色，返回设置页后上下系统区恢复深色。

### 修复设置页主题与上下系统区域颜色割裂

- 新增设置窗口主题协调器，状态栏、导航栏和窗口底色统一复用 `LIGHT_SETTINGS_THEME.pageBackground` / `DARK_SETTINGS_THEME.pageBackground`，不再由系统深浅色直接决定。
- 主窗口启用 `setWindowLayoutFullScreen(true)`；设置页仅让背景层通过 `expandSafeArea` 延伸到状态栏、挖孔和底部导航区域，标题、列表与交互内容继续由 ArkUI 安全区自动避让。
- 同步设置状态栏和导航栏的内容颜色及浅色图标标志，深色背景使用浅色内容，浅色背景使用深色内容。
- 窗口首次创建、持久化设置加载完成、主题保存成功、跟随系统时系统主题变化及应用重新进入前台时都会同步窗口外观。
- 窗口更新使用版本号与串行 Promise 队列，快速切换主题时跳过尚未开始的旧请求，并保证最终落地的是最新主题；窗口能力失败只记录日志，不阻断设置页加载。
- 新增系统栏 Token 映射、跟随系统、强制主题、持久化切换和快速异步切换回归测试，并更新架构、测试计划和项目状态文档。
- ArkTS 测试、Stage 11 架构/隐私门禁、Debug/Release HAP、Release 包内容检查和 x86_64 模拟器 Stage 11 验收通过；深浅主题截图中顶部、页面空白区和底部边缘采样颜色一致，系统栏内容及手势条清晰可见。

## 2026-07-14

### 修复输入法键盘“跟随系统”主题识别

- 修复将 `COLOR_MODE_NOT_SET` 错误解释为浅色的问题；该值表示应用未固定颜色模式，并不能代表系统当前为浅色。
- 输入法扩展与设置 Ability 统一从 `ResourceManager.getConfigurationSync().colorMode` 读取当前实际生效的系统颜色模式。
- 接入 API 24 的 `ApplicationContext.onSystemConfigurationUpdated` 系统级颜色模式监听，并在 Ability 销毁时按同一回调正确注销，避免重复监听和泄漏。
- 输入开始、键盘重新显示、Ability 回到前台及配置更新时都会主动重新读取当前系统模式，覆盖键盘隐藏期间切换主题和重新建立输入会话的场景。
- 保留固定浅色和固定深色优先级；系统模式更新只改变跟随系统设置下的有效主题。
- 新增系统主题监听初始化、刷新、事件更新、重复初始化和取消订阅单元测试。
- 修复系统深色模式下 Debug 输入框验收页继承浅色文字的问题；该页面保持固定浅色背景，并为标题、标签、输入正文、占位文字和光标显式设置高对比颜色，不涉及键盘主题或输入逻辑。

### 词库规则增强第二阶段：用户词库覆盖层

- 新增独立 `user-lexicon` crate，严格解析普通词条、`#删`、`#固` 和 1-based `#N`；支持 UTF-8/BOM、LF/CRLF、空文件、明确的路径/物理行号/字段/原因诊断和“后者覆盖前者”的稳定语义。
- 第一阶段的编码与词条校验抽到 `lexicon-core::validation` 共享；`FlypyTableImporter` 继续拒绝用户标记，正式码表构建流程未接收覆盖规则。
- `ime-engine` 在系统候选、整句评分和 `user-model` 学习软排序之后应用删除、普通用户候选、固顶、指定位置和稳定去重，再进入原候选会话分页；自定义候选可点击或由空格提交，且不伪造系统 ID 或学习键。
- 新增同目录 `.tmp/.bak/.old` 的同步写入、校验、回滚切换与损坏恢复；失败 reload 保留最后有效快照，相同快照保存字节确定。
- 新增 `user-lexicon-tool validate/import`、原创 fixture、Rust/引擎/FFI/ArkTS 测试和 `scripts/verify-lexicon-rules-phase2.ps1`。
- `EngineConfig` 增加向后兼容的可选 `userLexiconPath`；C++ 只转发路径，C ABI/Node-API 函数签名和 interface/ABI version 仍为 2。
- 同步新增 ADR 0014、用户词库格式文档和第二阶段验证证据。未新增第三方依赖、网络权限、管理 UI、文件选择器或第三阶段分类词库。
- 最终本地总门禁、双 ABI、生产词库确定性与 Release HAP 内容检查通过；
  x86_64 模拟器由 IME 扩展自身在真实独立沙箱建立验收文件，正式候选链路
  已验证普通新增/提交、`#删/#固/#2`、进程重启保留及空文件恢复。验收写入
  代码已移除，最终 Release HAP 不含用户 fixture、管理入口或新增权限。

### 词库规则增强第一阶段：码表顺序基础

- 新增独立 `FlypyTableImporter` 与 `--input-format flypy-table`，严格导入
  `词条<TAB>编码`，支持 UTF-8、LF/CRLF、BOM，并对缺 TAB、多字段、
  空字段、非法编码及尚未实施的 `#删/#固/#N` 返回带路径和行号的错误。
- 统一词条模型新增 `source_order`；按显式多源参数顺序和文件物理数据行
  顺序分配，重复词条保留第一次出现顺序。
- `HSPLEX01` reader 兼容 1.0/1.1；仅 TAB 码表以 1.1 追加持久化
  `source_order`，原 pinyin TSV 与 `production.lex` 继续使用 1.0，未改变
  正式词条 ID、用户模型格式或生产资源。
- 新增 `ExistingRanking`/`SourceOrder` 策略边界和 `ExactOrPrefix` 查询：
  精确命中时不混入后续码，无精确命中时跨编码按原始全局行顺序返回，
  排序后再稳定去重、限制和分页，空输入不枚举全表。
- 新增项目原创 fixture、57 项目标模块测试和确定性验证脚本；两次独立构建
  均为 496 bytes，SHA-256 均为
  `13610B57B8A1BEB1EE12643552DC5873EE17F8BC9DCB66997D824D37F527B50C`。
- ArkTS、C++、C ABI、Node-API、设置 UI、权限与生产默认候选排序未修改；
  未导入官方小鹤码表，未实现用户词库、小鹤音形或后续标记语法。

### 候选词与翻页控件重叠修复

- 根因是候选词滚动区与分页区使用 `Stack` 叠放：候选内容仍按候选栏全宽布局，右侧 88vp 分页区只是覆盖在内容上方；候选词或辅助编码较长时，文字和点击区域会延伸到上一页、页码和下一页控件下方。
- 候选栏改为普通 `Row` 的两个兄弟区域：候选内容区使用剩余宽度并允许收缩到 0，分页区保持 88vp 固定宽度且禁止压缩，不再使用 `zIndex` 覆盖。
- 候选内容区、候选项和候选栏外层增加裁剪与宽度约束；候选词和辅助编码继续单行省略，长内容只能在候选区内滚动或省略，不能侵入分页区及其点击范围。
- 分页查询、候选排序、每页数量、翻页状态和候选提交逻辑均未修改；新增长候选与双向翻页状态回归。
- ArkTS 单元测试、Debug/Release HAP 构建和 x86_64 模拟器 Stage 11 回归通过；最新布局快照中候选内容区右边界与分页区左边界同为 `x=949px`，两区无交叠，上一页、页码和下一页点击区域完整保留。

### 浏览器中文输入兼容

- 读取 `EditorAttribute.isTextPreviewSupported`，不再向明确不支持文本预览的浏览器编辑器调用 `setPreviewText`。
- 无预览编辑器改为在候选栏内维护中文组合，候选确认时通过既有 `insertText` 单次提交；支持预览的 ArkUI 输入框流程保持不变。
- 新增无预览编辑器中文组合/提交回归，并在 x86_64 模拟器浏览器搜索框验证 `ni -> 你`，无红色错误提示。

### 候选栏与删除键修复

- 文本键盘候选栏容器改为始终保留，不再依赖组合内容、候选数量或错误状态；英文、邮箱和 URL 键盘复用同一候选栏。
- 修正 HarmonyOS `InputClient` 删除方向：退格统一调用 `deleteForward`/`deleteForwardSync` 删除光标前文本，中文组合态仍优先删除编码并刷新候选。
- 新增候选栏空闲态和中文提交后/多输入框删除单元回归，并完成 Debug/Release HAP 与 x86_64 模拟器专项验证。

## 2026-07-13

### 正式键盘调试隔离

- 从所有键盘面板移除交互式回归候选和用户模型探针，Debug 构建也不再显示它们。
- 从 ArkTS、Node-API、OHOS C 头文件和生产 Rust FFI 构建中移除固定候选路径；该回归 ABI 仅在 `cfg(test)` 中编译。
- 阶段 7/8 fixture 词库不再作为 rawfile 打包，Release HAP 只包含 `production.lex`。
- HAP 构建模式改为显式参数，默认 Release，并分别保存 Debug/Release 产物。
- 新增 Release HAP 元数据、资源和调试标识门禁；设备验收改为断言正式键盘不含调试控件。

## 2026-07-09

### 阶段 7

- 新增 `candidate-query` 和 `candidate-ranking` Rust crate，完成运行时二进制词库查询、候选去重、基础频率排序、分页输入数据和有界缓存。
- `lexicon-core` 新增运行期 pinyin-key 索引查找，阶段 7 直接复用阶段 6 `.lex` 二进制格式，不在运行时读取 TSV/CSV。
- `ime-engine` 接入 `EngineConfig.lexiconPath`，创建引擎时加载二进制词库，按键、删除、翻页和候选选择均维护 Rust 候选会话状态。
- `ime-ffi`、C++ Node-API 和 ArkTS 原生网关升级到阶段 7 interface/ABI version `2`，新增 `selectCandidate`、`nextCandidatePage`、`previousCandidatePage`。
- ArkTS 新增 rawfile 词库安装器，把 `stage7_test.lex` 复制到应用沙箱后传给 Rust；候选栏展示正式候选、首选高亮和上一页/下一页按钮。
- 中文模式空格在存在正式候选时提交首选项；固定候选词回归路径继续保留为显式 `回归` 动作。
- 新增阶段 7 fixture、Rust/FFI/ArkTS 测试覆盖、架构边界检查、`scripts/verify-stage7.ps1`、ADR、API 契约、词库格式说明和验证证据。
- 阶段 7 本地自动化验证通过；设备安装、IME 启用和真实输入框验证未执行。

## 2026-07-08

### 阶段 4

- 新增 `pinyin-syllable`、`shuangpin-schema`、`shuangpin-parser` 三个 Rust crate，实现合法拼音音节校验、双拼配置加载校验和有状态双拼编码解析。
- 新增小鹤双拼配置 `engine-rust/schemas/xiaohe.json`，规则以独立 JSON 数据维护并由 Rust 编译期嵌入。
- 新增阶段 4 parser fixture `engine-rust/tests/fixtures/stage4_parser_cases.tsv`，覆盖正常音节、零声母、非法组合、不完整组合、连续编码、删除回退、方案切换和稳定性。
- `ime-engine` re-export 阶段 4 parser 创建入口，但未修改现有 C ABI、C++ Node-API 或 ArkTS 原生接口。
- 新增 `scripts/verify-stage4.ps1`，串联 Rust fmt/clippy/test、阶段 4 专项测试、双 ABI native、ArkTS 单测、HAP 构建、源码边界检查和产物摘要。
- 通过 `scripts\verify-stage4.ps1` 完成本地阶段 4 验证；设备验证本轮未请求。
- 更新 PROJECT_STATE、README、测试计划、项目结构、架构说明、ADR 和阶段 4 验证记录。

### 阶段 3

- 接入 `KeyboardRootStage3` 作为活动键盘页面，保留 `KeyboardRoot.ets` 作为阶段 2 基线。
- 添加键盘尺寸、调色板、声明式布局模型、候选栏、可复用按键组件和长按删除控制器的阶段 3 测试覆盖。
- 修复 `KeyboardLayoutSpec.ets` 的导入路径，并为 `KeyboardMetrics.ets` 配置对象补充显式 ArkTS 类型。
- 修复 `InputPanelController` 的失败状态流：面板创建失败时不再继续执行 resize/show，也不再把键盘标记为 visible。
- 修复 `scripts/verify-stage3.ps1` 源码检查段的 PowerShell 续行问题，并补充 Stage3 入口、UI 依赖边界和面板失败守卫。
- 通过 `scripts\verify-stage3.ps1` 完成本地阶段 3 验证：Rust、双 ABI native、ArkTS、HAP 和源码守卫均通过；设备/真机接入按本轮要求作为非阻塞项跳过。
- 更新 README、PROJECT_STATE、构建指南、测试计划、项目结构、架构说明和阶段 3 验证记录。

### 阶段 2

- 修复阶段 2 键盘行顺序守卫：`KeyboardRoot` 现在直接按 `QWERTY_KEY_ROWS` 的自然顺序渲染，避免再次把 QWERTY 行倒置。
- 修复阶段 2 键盘文字视觉裁剪：字母键和功能键改为外层 Row 按键面加内层 Text，避免窄键上的 `Button(label)` 把单字母裁成空白或把中文功能键省略成 `...`。
- 为 ArkTS 单元测试补充 QWERTY 布局数据顺序检查。
- 为 `scripts/verify-stage2.ps1` 补充源码守卫，禁止反转 QWERTY 行、禁止键盘按键回退为 `Button(label)`，并检查阶段 2 面板高度不低于已验证的 1100px。
- 在 x86_64 模拟器上重新安装并验证布局、Q/W 输入、删除、空格、中文占位切换和隐藏键盘，新增布局证据到 `docs/evidence/stage2/`。

## 2026-07-07

### 阶段 2

- 添加了阶段 2 输入法外壳，包含生命周期、面板、会话、状态和键盘控制器。
- 添加了带有英文输入、删除、空格、回车、隐藏、中文占位切换和固定候选词回归 UI 的 QWERTY 键盘页面。
- 保留了 ArkTS -> C++ -> Rust 固定候选词桥接和 `ImeConnectionService` 中已验证的删除后备。
- 添加了 ArkTS 控制器测试，涵盖会话状态、动作路由、错误处理、回车/隐藏和原生回归访问。
- 添加了 `scripts/verify-stage2.ps1` 用于环境、Rust、ArkTS、HAP、源代码守卫、产物和可选设备验证。
- 在当前 x86_64 模拟器上验证了阶段 2，并在 `docs/evidence/stage2/` 下记录了布局证据。
