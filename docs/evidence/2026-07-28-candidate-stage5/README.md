# 候选词改进阶段 5 证据

日期：2026-07-28  
状态：`COMPLETED`（主机、自动测试、双 ABI Native 与 HAP 构建范围）

## 结论

阶段 5 已为小鹤双拼的单键/不完整前缀查询增加独立的确定性质量排序，同时保持阶段 3 的完整索引遍历、256 项召回池、128 项稳定快照和阶段 4 的 `QueryIntent` 合同不变。

正式前缀排序键为：

1. 匹配类型，精确优先于前缀；
2. 前缀质量分加有界用户学习分，降序；
3. 原始系统频率，降序；
4. 文字、reading、来源、稳定 ID，升序。

质量分只在 `QueryMode::Prefix + ExistingRanking + GlobalTopK` 路径使用。1～2 字候选保留原频率，3 字使用 2 倍除数，4 字及以上使用封顶的 8 倍除数；由同一字符重复组成的 2 字及以上候选再使用封顶的 8 倍除数。候选不被删除，惩罚不会随长度无限增长。完整音节精确查询继续使用原始频率排序；句子继续使用独立句子评分；阶段 0 的 `LexicalEarlyStop` 回退路径保持旧排序；小鹤音形继续使用 `SourceOrder` 和码表忠实模式。

## 词频审计

- `production.normalized.tsv` 共 65,115 条，全部来自 `rime_pinyin_simp`，频率范围为 1～1,000,000；当前没有跨来源频率尺度混合问题。
- 单字/2 字/3 字/4 字分别为 17,038/34,071/7,379/6,627 条；平均频率约为 2,009.218/1,484.973/485.236/324.643。
- 发现明显异常高频 4 字项“回复日期”（199,249），以及“呵呵”（249,663）、“哈哈”（121,641）等重复拟声项。遵守阶段边界，仅以通用质量信号调整宽松前缀排序，没有修改或清洗正式数据。
- 相同文字和相同规范 reading 继续取最大频率并稳定合并来源；同一可见文字跨 reading 在阶段 3 Top-K 中只占一个槽位，由完整稳定排序键选择最佳项。

## `h` 修改前后

阶段 3 前 20：

```text
和、好、还、呵呵、会、回复日期、还是、很、后、哈哈、
还有、或、号、很多、话、或者、哈、好像、回来、孩子
```

阶段 5 前 20：

```text
和、好、还、会、还是、很、后、还有、或、号、
很多、话、或者、哈、好像、回来、孩子、好的、活动、换
```

阶段 5 前 50：

```text
和、好、还、会、还是、很、后、还有、或、号、
很多、话、或者、哈、好像、回来、孩子、好的、活动、换、
回、呵呵、还要、后来、回复日期、花、回家、回去、获得、好了、
环境、行业、合作、回答、还在、黄、很好、还没、喝、哈哈、
好多、后面、黑、汗、红、还好、海、会议、化、合同
```

“回复日期”由第 6 降到第 25，“呵呵”由第 4 降到第 22，“哈哈”由第 10 降到第 40。新前 20 为 11 个单字加 9 个 2～4 字短词，没有 5 字以上候选或单字重复项；前 20 覆盖 10 个首音节分支，完整 128 项快照仍覆盖阶段 3 的 19 个 `h*` 分支。

## `a/h/n/s/z` 回归

| 输入 | 前 20 单字 | 前 20 的 2～4 字词 | 5 字以上 | 首音节分支 |
| --- | ---: | ---: | ---: | ---: |
| `a` | 14 | 6 | 0 | 4 |
| `h` | 11 | 9 | 0 | 10 |
| `n` | 11 | 9 | 0 | 9 |
| `s` | 8 | 12 | 0 | 10 |
| `z` | 9 | 11 | 0 | 10 |

完整候选和逐字段数据见 `host-report.json` 与 `generated-summary.md`。

## 用户学习

生产词库候选“会议”在 `h` 快照中的一基排名实测为：

```text
基线 48 → 选择 1 次 44 → 2 次 43 → 3 次 41 → 4 次 38
```

- 显式 flush 后重建引擎并加载模型，排名仍为 38；
- 清除模型后恢复到 48，模型文件被移除；
- 清除后设置 `session_learning_allowed=false`，再选择 4 次仍为 48；
- 学习键继续包含 scheme、词库版本、来源类型和候选稳定 ID 的哈希，不持久化 raw input 或候选文字；
- 计数、近期性、5,000 分上限、1,024 次饱和和延迟 flush 合同未修改；
- ArkTS 密码框/数字密码路径继续不进入中文候选引擎且 `learningAllowed=false`；现有禁学习、提交失败和失效会话门禁未修改。

学习位置为：

```text
完整相关索引扫描
→ 阶段 3 可见文字去重 Top-K 256
→ 系统去重与基础排序
→ 阶段 5 前缀质量排序＋用户学习重排
→ 稳定快照 128
→ 分页
```

没有先截取第一页或旧 64 项再学习。阶段 3 已有测试继续确认系统基线第 140 项可凭既有学习分在 128 项快照截断前升至首位。

## 稳定性与回归

- `h` 冷查询和缓存命中结果一致；页大小 9/20/30/50 拼接后均为同一 128 项快照。
- 完整双拼 `hc/ni/ui/vi` 全字段顺序与阶段 3 证据一致。
- 句子 `nihc/uurufa`、部分提交和删除回退与阶段 3 证据一致。
- 阶段 0 冻结候选文件 3/3 逐字节一致；显式旧召回回退路径不使用阶段 5 质量排序。
- 小鹤音形精确简码、分类、`#固/#删/#N`、四码、第五码、空码切分和分页测试全部通过。
- 正式页大小、候选展开 UI、`commitCandidate(index)`、C++/FFI/interface/ABI 均未修改。

## 性能与内存

同机 x86_64 Windows Release，5 次预热、每键 30 个冷/热样本：

| 指标 | 阶段 3 P50/P95 | 阶段 5 P50/P95 |
| --- | ---: | ---: |
| a～z 冷查询 | 2.471/5.656 ms | 2.195/4.555 ms |
| a～z 缓存命中 | 38.2/72.8 µs | 37.1/68.1 µs |

256 项池的独立 200 样本：

| 子阶段 | P50 | P95 |
| --- | ---: | ---: |
| 去重 | 92.9 µs | 175.4 µs |
| 系统前缀质量排序 | 128.8 µs | 228.2 µs |
| 用户重排 | 142.4 µs | 257.7 µs |

空模型加载为 172.7 µs；4 次选择后的显式原子 flush 为 14.406 ms，均不在每次候选排序热路径执行。报告进程峰值工作集由阶段 3 的 141,328,384 bytes 变为 141,524,992 bytes；工具同时持有多份 lexicon/报告对象，这不是设备端严格内存 benchmark。结构性边界仍为 Top-K O(256) 和 128 项最终快照。

## 自动测试与构建

- `cargo fmt --all -- --check`：PASS。
- `cargo test --workspace`：419/419 PASS。
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`：PASS。
- ArkTS 单元测试：332/332 PASS。
- x86_64 Native Release：25,842,226 bytes，SHA-256 `2d98f4c5696b2e68fc88fc27435de2d63fbef2caddf986d60965f80b721c36bf`。
- arm64-v8a Native Release：26,366,340 bytes，SHA-256 `28ec62f17c8d90ae1789638ea915f63e7d96612e56fcdbb5afd8e7dc6e86cbc0`。
- internalDebug HAP：41,024,806 bytes，SHA-256 `02b399fdc94afc3d4c454ffaefaf06221d8896f82a30f76183f347fc0ed916b65`。
- unsigned Release HAP：37,750,936 bytes，SHA-256 `1b2a815b4b52f7982d7e6921aab4a5922c6e53aff2fb78071f8dcb91ca628ead`。
- 构建仍只有项目既有的异常处理、废弃 API、资源重复和未启用混淆警告。

执行命令：

```powershell
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
powershell -ExecutionPolicy Bypass -File scripts\generate-candidate-stage5-evidence.ps1 -PerformanceWarmups 5 -PerformanceSamples 30
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -BuildMode debug
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -BuildMode release -SkipRust
```

## 资源与阶段边界

- `production.lex` 未修改：3,734,484 bytes，SHA-256 `765e2b0bd90244192a4c1bb6b2ec501ed28e0dbd731cbab4c326534f091eca10`。
- 正式小鹤音形 bundle 未修改：25,397,952 bytes，SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`。
- 未扩充、替换、清洗或重新生成正式词库。
- 未修改阶段 3 的全索引覆盖、256/128 限制，阶段 4 的输入语义，候选页大小、展开/翻页 UI、C++/FFI/ABI 或小鹤音形排序。

## 未执行

- Phone/Pad 模拟器阶段 5 正式候选与学习专项：`NOT_RUN`。
- ARM64 物理真机：`NOT_RUN`。
- signed Release 第三方输入框：`NOT_RUN`。
- 设备端内存、首帧、快速连续输入、旋转/分屏和压力矩阵：`NOT_RUN`。

本阶段只声明主机、自动测试、双 ABI Native 和 HAP 构建范围完成；设备与最终发布验收仍属于阶段 7。
