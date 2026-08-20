# 11.6.6 外部编辑器设备验收

环境：

- 设备：`127.0.0.1:5555`
- HarmonyOS：`emulator 6.1.0.125(SP9DEVC00E16R1P1)`
- 架构：x86_64
- 编辑器：与输入法 Extension 分离的 MainAbility ArkUI `TextInput`
- 验收时间：2026-07-23 16:15（Asia/Shanghai）

结果：

```text
date committed = 2026-07-23
pair inserted = 2026-07-23🧑‍💻🧑‍💻
caret probe = 2026-07-23🧑‍💻x🧑‍💻
cursor after insert = 20
target cursor = 15
pair offset UTF-16 = 5
STAGE11_6_6_EDITOR_DEVICE_ACTION_RESULT=PASS
```

`🧑‍💻` 在 UTF-16 中占 5 个 code unit。成对文本一次提交后，光标从索引 20 移至 15；随后提交字母 `x`，最终位于两个 emoji cluster 之间。该探针确认本次 HarmonyOS 6.1 ArkUI `TextInput`/`InputClient` 路径的光标索引按 UTF-16 code unit 计算。

证据：

- `editor-device-acceptance.json`：机器可读结论、HAP 身份和三项断言。
- `date_committed.png`：日期实际提交。
- `emoji_pair_committed.png`：成对 emoji 只插入一次。
- `emoji_pair_caret_verified.png`：光标探针结果。
- `pair-cursor-hilog.txt`：IME 成功定位日志。
- 对应 `.json` 文件：各步骤 UI 布局快照。

本验收只证明通用动作运行时和编辑器侧行为。正式转换合同没有交付快符、引导、日期时间或成对符号映射，正式产品数据仍为 `PARTIALLY DEFERRED`。
