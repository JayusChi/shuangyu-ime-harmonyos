# 候选词改进阶段 4 证据

日期：2026-07-28  
状态：`COMPLETED`（主机、自动测试、双 ABI Native 与 HAP 构建范围）

## 结论

阶段 4 已在 ADR 0021 冻结小鹤双拼单键、完整双键、不完整音节、多音节和非法输入合同。
`shuangpin-parser::ParseResult` 新增 Rust 内部 `QueryIntent` 和逻辑音节槽位，`ime-engine` 只按该意图选择现有
前缀、精确或句子路径，不再用 `pending_code`、按键长度或 `syllables.len()` 分散猜测语义。

最终合同：

- 单键 `h/a/o` 均为规范拼音前缀查询。`h` 不混入韵母键 `ang`；`a/o` 通过正常前缀命中当前
  方案允许的零声母 reading。
- `hc/ni/ui/vi` 分别是 `hao/ni/shi/zhi` 的精确查询。
- 一个完整音节加待完成键使用现有连续 reading 前缀查询；两个或更多完整音节进入现有句子解码。
- 单个双键的多个合法解释均为精确 reading，合并后使用现有确定性精确排序；歧义键位于句子时
  按方案声明顺序选择每个槽位的规范 reading，不让词库顺序反向决定解析。
- 未实现词语首字母简拼，未新增设置项。

## 发现并修复的层间不一致

当前小鹤方案中 `lo` 可合法解析为 `lo/luo`。旧 parser 将两个合法 reading 放入
`syllables` 数组，旧引擎又使用 `syllables.len() >= 2` 判断多音节，因此会把一个歧义完整双键
误送到句子解码。

修复后 parser 将 `lo` 明确标记为一个逻辑槽位的 `CompleteSyllable`；引擎对 `lo` 和 `luo` 分别做精确查询，
合并、按 `text + reading` 去重，再沿用现有精确排序与 64 项上限。该规则由方案与稳定排序键
决定，不依赖词库物理顺序。多音节 `loni` 的自动测试进一步确认句子 reading 固定为方案先声明的
`lo ni`，即使词库同时含 `luo ni` 也不会改变按键解释。

## 层间传递

```text
xiaohe.json + pinyin inventory
  → shuangpin-parser ParseResult.query_intent
  → ime-engine query plan
      SingleKeyPrefix / IncompleteSyllable → QueryMode::Prefix
      CompleteSyllable                    → QueryMode::Exact
      MultiSyllable                       → sentence-decoder
      Empty / Invalid                     → clear CandidateSession
  → existing candidate ranking or sentence scoring
  → existing CompositionResult JSON
  → ArkTS InputSessionStore atomically replaces input/candidates/page
  → UI renders only the engine snapshot
```

`QueryIntent` 不新增跨语言字段。C++/FFI/ArkTS 不复制双拼规则；interface/ABI version 和
`commitCandidate(index)` 保持不变。

## 状态转换

自动测试覆盖：

```text
h → hc → hcn → hcni
SingleKeyPrefix → CompleteSyllable → IncompleteSyllable → MultiSyllable

nihc → nih → ni → n → ""
MultiSyllable → IncompleteSyllable → CompleteSyllable → SingleKeyPrefix → Empty
```

每次输入或删除均替换候选快照并回到第 0 页；删除到空后候选、页码和前后页标志清空。

## 自动测试与构建

- `cargo fmt --all -- --check`：PASS。
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`：PASS。
- `cargo test --workspace`：415/415 PASS。
- ArkTS 单元测试：332/332 PASS（含新增 2 项 UI Store 合同测试）。
- x86_64 Native Release：PASS，`libime_ffi.a` 25,795,758 bytes，
  SHA-256 `b3fa651c3b556f3c9e77fea2710ef019f8cfb7c1a304477b8c1655e1aed15f61`。
- arm64-v8a Native Release：PASS，`libime_ffi.a` 26,324,314 bytes，
  SHA-256 `9ff3337050a0f8c9ed33b33a8d1ba3c2504034508b074964fe2653f2dc710e22`。
- internalDebug HAP：PASS，40,981,174 bytes，
  SHA-256 `707de14f30a2d67a4a76004a502791550198fecd689a2b2720eda6844a068c1b`。
- unsigned Release HAP：PASS，37,707,304 bytes，
  SHA-256 `0ea34054dc13a650a49db197a568e91603588ab6be2bd9a114b13eda6ad22376`。

首次直接调用 Hvigor 因当前进程中的 `DEVECO_SDK_HOME` 无效而在配置检查阶段退出；按项目现有
构建脚本将该进程变量临时设为 DevEco SDK 后，ArkTS 332/332 与 HAP 构建均通过。没有修改本机
持久环境。构建仍输出项目既有的异常处理、废弃 API、资源重复和未启用混淆警告。

## 资源与隔离

- `production.lex`：3,734,484 bytes，SHA-256
  `765e2b0bd90244192a4c1bb6b2ec501ed28e0dbd731cbab4c326534f091eca10`，未修改。
- 正式小鹤音形 bundle：25,397,952 bytes，SHA-256
  `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`，未修改。
- 阶段 3 的 256 项召回池、128 项前缀快照、现有排序与用户学习公式未修改。
- 小鹤音形 SourceOrder、`#固/#删/#N`、候选展开 UI、候选提交 ABI 未修改。
- 既有完整双拼、句子、部分提交、正式音形、FFI 和冻结阶段 0 候选测试均通过。

## 未执行

- Phone/Pad 模拟器阶段 4 输入/删除专项：`NOT_RUN`。
- ARM64 物理真机：`NOT_RUN`。
- signed Release 第三方输入框：`NOT_RUN`。
- 设备端快速连续输入、旋转/分屏、性能、内存与压力矩阵：`NOT_RUN`。

这些设备与最终发布矩阵保留给阶段 7；本阶段只声明上述主机、自动测试、双 ABI Native 和
HAP 构建范围完成。
