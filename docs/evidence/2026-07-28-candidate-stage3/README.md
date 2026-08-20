# 候选词改进阶段 3 证据

日期：2026-07-28  
状态：`COMPLETED`（主机、Rust/ArkTS 自动测试、双 ABI Native 与 HAP 构建范围）

## 结论

阶段 3 已消除小鹤双拼不完整前缀查询“按拼音索引字典序先取 64 条、再排序”的召回偏置。正式 `h` 查询现在完整遍历 2,032 个相关索引、3,234 条原始记录，用 O(K) 有界内存维护 256 项全局 Top-K 召回池；现有用户学习在该全局池上重排后，将最终稳定快照截断为 128 项，最后按正式 50 项页大小分页。

旧 `h` 召回池 64/64 来自 `ha/hai`。新召回池覆盖 19 个首音节分支：

```text
ha:5, hai:25, han:11, hang:5, hao:27,
he:29, hei:5, hen:26, heng:1,
hong:5, hou:14,
hu:15, hua:18, huai:4, huan:10, huang:4, hui:28, hun:5, huo:19
```

新快照前 20 覆盖 9 个分支，不再由 `ha/hai` 垄断，并包含“和、好、还、会、很、后、或”。阶段 3 没有修改正式词频或词库，也没有硬编码这些候选的顺序。

## 原问题的准确位置

阶段 3 修改前，提前停止位于 `engine-rust/crates/candidate-query/src/query_engine.rs` 的 `collect_prefix`（历史行 110～134）：

```text
find_prefix_indexes(..., max_prefix_index_records)
→ 按字典序逐索引追加
→ candidates.len() >= max_candidates 时 break
→ truncate(max_candidates)
→ rank
```

为保留明确回退边界，旧实现目前原样收口为同文件 `collect_lexical_prefix`（当前约 146～165 行），只在显式 `PrefixRecallStrategy::LexicalEarlyStop` 下使用。正式缺省为 `GlobalTopK`；阶段 0 工具显式选择旧策略，因此冻结快照仍可逐字节复现。

## 新召回与排序流程

```text
QueryMode::Prefix + ExistingRanking
  → 定位全部相关前缀索引
  → 遍历全部相关原始候选
  → 按可见文字去重的有界 Top-K（256）
  → 现有系统排序
  → 查询缓存保存系统召回池
  → ime-engine 应用现有用户学习分数
  → 截断稳定前缀快照（128）
  → CandidateSession 按页面大小分页（正式 50，最大 64）
```

Top-K 和系统排序使用现有稳定键：

1. 匹配类型：精确优先于前缀；
2. 系统频率降序；
3. 文字、reading、来源、稳定 ID 升序。

同一可见文字来自多个 reading 时只占一个 Top-K 槽位；冲突项用上述完整排序键选择稳定最佳项。Top-K 使用最差项在堆顶的有界堆、按文字索引和惰性版本清理，堆超过 `2K` 时重建，因此不会随命中总数无界增长。用户重排保持匹配类型边界，并使用“系统频率＋现有有界用户分数”，随后沿用相同稳定 tie-breaker。

完整双拼 `QueryMode::Exact` 继续使用原 `max_candidates=64` 路径；句子解码、部分提交、音形 SourceOrder/状态机均不进入新策略。

## 最终配置

| 数量 | 值 | 作用 |
| --- | ---: | --- |
| 不完整前缀召回池 | 256 | 完整索引遍历后的系统全局 Top-K |
| 不完整前缀候选快照 | 128 | 用户学习重排后的稳定快照 |
| 完整精确查询上限 | 64 | 保持原合同 |
| 正式页面大小 | 50 | 保持阶段 1 合同 |
| 最大允许页面大小 | 64 | 保持阶段 1 安全上限 |
| 查询缓存容量 | 64 | 保持原配置 |

## `h` 修改前后

旧前 20：

```text
还、哈哈、哈、哈哈哈、海、哈哈哈哈、害、哈尔滨、海边、海报、
嗨、咳、孩、海拔、哈利波特、海岸、还被、哈佛、还把、哈利
```

新前 20：

```text
和、好、还、呵呵、会、回复日期、还是、很、后、哈哈、
还有、或、号、很多、话、或者、哈、好像、回来、孩子
```

旧前 50：

```text
还、哈哈、哈、哈哈哈、海、哈哈哈哈、害、哈尔滨、海边、海报、
嗨、咳、孩、海拔、哈利波特、海岸、还被、哈佛、还把、哈利、
哈尔滨市、蛤蟆、哈哈大笑、還、哈市、哈根达斯、蛤、哈佛大学、
哈马斯、海岸线、哈珀、哈欠、哈里、哈卡、哈喽、哈尼、哈尔、亥、
哈罗、哈工大、海豹、哈韩、哈达、哈士奇、骇、哈飞、哈密、哈特、
哈密瓜、嘿
```

新前 50：

```text
和、好、还、呵呵、会、回复日期、还是、很、后、哈哈、
还有、或、号、很多、话、或者、哈、好像、回来、孩子、
好的、活动、换、回、嘿嘿、还要、后来、花、回家、回去、
获得、好了、环境、行业、合作、好好、回答、还在、黄、很好、
还没、喝、好多、后面、黑、汗、红、还好、哈哈哈、海
```

完整字段、reading、来源、稳定 ID 和频率见 `host-report.json` 的 `h_comparison`。

## a～z、分页、缓存和回归

- `generated-summary.md` 保存 a～z 每个单键的命中首音节分支数、召回池/快照大小、前 20 分支数以及冷/热 P50/P95。
- `i/u/v` 没有以该 ASCII 字母开头的规范拼音索引，稳定返回空；`e` 的前 20 由精确音节 `e` 占据，属于既有“精确匹配优先”，不是字典序提前停止。其他具有多个分支和至少 20 项快照的单键，前 20 均覆盖多个分支。
- 页大小 9、20、30、50 拼接后均得到同一 128 项 `h` 快照；无重复、无丢失，页状态正确。50 项页面为 50＋50＋28，第二页首项“会议”提交为“会议”并结束组合。
- 每个 a～z 性能样本均执行一次冷查询和紧随其后的缓存命中，受控命中率为 50%；26 个键的冷/热结果逐项完全一致。该 50% 是测试序列设计值，不代表真实用户运行时命中率。
- 阶段 0 的 6 个稳定候选文件继续由 `candidate-baseline` 单元测试与已提交产物逐字节比较，3/3 PASS。
- 完整双拼 `hc/ni/ui/vi` 的第一页全部字段与阶段 0 基线一致。
- 句子 `nihc/uurufa`、`uurufa` 部分提交前后全部字段与阶段 0 基线一致。
- 新增测试确认：不完整前缀最终为 128 项，而同一份 150 项精确 `ni` 词表仍只保留原 64 项；原本位于系统前 128 之外但在 256 召回池内的候选，已有学习分数时可在快照截断前升至首位；禁学习、隐私会话、清除模型和持久化行为继续由既有 Stage 9 测试覆盖。

## 性能与内存

同机 x86_64 Windows Release，5 次预热、每键 30 个冷/热样本：

| 指标 | P50 | P95 |
| --- | ---: | ---: |
| 旧阶段 0 `h` 冷查询 | 92.9 µs | 142.2 µs |
| 新 `h` 完整遍历＋Top-K＋系统排序 | 3.416 ms | 4.398 ms |
| 旧阶段 0 `h` 热查询 | 9.3 µs | 26.5 µs |
| 新 `h` 缓存命中 | 45.5 µs | 64.6 µs |
| 新 a～z 冷查询 | 2.471 ms | 5.656 ms |
| 新 a～z 缓存命中 | 38.2 µs | 72.8 µs |

新策略相对旧 64 项提前停止显著增加冷查询工作，但 `h` P95 保持在 5 ms 内、a～z 汇总 P95 保持在 6 ms 内，均低于证据脚本的 20 ms 主机门槛；因此本阶段没有引入分支预计算索引。`h` 查询扫描数固定为 3,234，Top-K/去重结构固定受 256/512 槽位边界约束。

阶段 3 报告进程的 `h` 查询后工作集相对单份已加载 lexicon 增加 23,101,440 bytes，进程峰值 141,328,384 bytes。该工具为同时比较新旧结果而持有完整 lexicon 克隆，不能把 23 MB 全部解释为 Top-K 自身开销；Top-K 的结构性额外内存为 O(256)。阶段 0 报告进程峰值为 149,012,480 bytes，但它还加载正式音形 bundle，两者不作为严格一对一内存 benchmark。设备端 Rust/进程内存仍需阶段 7 补测。

## 自动测试与构建

- `cargo fmt --all -- --check`：PASS。
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`：PASS。
- `cargo test --workspace`：407/407 PASS。
- ArkTS `hvigor ... test`：PASS；本阶段没有 ArkTS 代码改动。
- x86_64 与 arm64-v8a Native Release：PASS。
- internalDebug HAP：40,973,734 bytes，SHA-256 `d22d74a4692efa92045d95a2fdf29fe27a409610fccf819edbc8d14d64b7c2dc`。
- unsigned Release HAP：37,699,880 bytes，SHA-256 `69931320aebb8d22c2a7a853dcd249ff33f285d2996a7e25e30967ce0ca2c7ad`。
- 构建仍输出项目既有的异常处理、废弃 API、资源重复和未启用混淆警告，没有新增构建错误。

执行命令：

```powershell
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
powershell -ExecutionPolicy Bypass -File scripts\generate-candidate-stage3-evidence.ps1 -PerformanceWarmups 5 -PerformanceSamples 30
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -BuildMode debug
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -BuildMode release -SkipRust
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test
```

## 资源与隔离确认

- `production.lex` 未修改：3,734,484 bytes，SHA-256 `765e2b0bd90244192a4c1bb6b2ec501ed28e0dbd731cbab4c326534f091eca10`。
- 正式音形 bundle 未修改：25,397,952 bytes，SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`。
- 未修改小鹤音形查询、排序、用户规则、四码/第五码行为、候选 UI、页面大小、C++/FFI/ABI、正式词频或正式词库。
- 完整双拼精确查询、句子解码、部分提交和用户学习隐私策略均保持原合同。

## 未执行

- Phone/Pad 模拟器阶段 3 正式双拼 `h` 设备专项：`NOT_RUN`。
- ARM64 物理真机：`NOT_RUN`。
- signed Release 第三方输入框：`NOT_RUN`。
- UI 首帧、设备端内存、快速连续输入、旋转/分屏和压力矩阵：`NOT_RUN`。

本阶段只声明主机、自动测试、双 ABI Native 和 HAP 构建范围完成；设备与最终发布性能仍属于阶段 7。
