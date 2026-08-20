# 9 键拼音阶段 4：传统九宫格界面与交互

日期：2026-08-12

状态：`IMPLEMENTED / HOST_VALIDATION_PARTIAL`

## 范围

本阶段在阶段 3 的 `pinyin-9` Rust 引擎、T9 数字音节索引和组合选择接口之上，正式启用 `pinyin-9` 键盘档案并接入 HarmonyOS 软键盘。没有在 ArkTS 或 C++ 中新增数字到字母展开、音节切分、T9 消歧或候选排序。

## 键盘结构

中文 9 键使用四排 3 列九宫格和一排共享动作键：

```text
1 标点   2 ABC   3 DEF
4 GHI    5 JKL   6 MNO
7 PQRS   8 TUV   9 WXYZ
符/123   0 分词  删除
中       空格    动态动作键
```

- `2`～`9`：`T9_PINYIN_DIGIT`，主文案为数字，次文案为字母组；字母组仅用于键帽、预览和无障碍文案。
- `1`：进入既有符号模式。切换前若存在中文组合，沿既有模式切换合同提交首选或清理无候选组合。
- `0`：调用阶段 3 的显式分音接口，不向 raw input 插入伪字符。
- `符/123`：进入既有数字键盘；该模式的 `2`～`9` 仍是普通 `CHARACTER`，用于输入真实数字。
- 删除、空格、中英文切换和动态动作键复用既有 `InputSessionController`、`EditorContext` 与 `EditorPolicy`。
- 英文模式继续使用既有 QWERTY，不实现英文 T9 或多击输入。

## 数据流与真实状态

```text
Pinyin9KeyboardLayout
  -> KeyboardAction.T9_PINYIN_DIGIT("2".."9")
  -> KeyboardController 串行队列
  -> InputSessionController.insertT9PinyinDigit
  -> EngineCoordinator.processKey
  -> NativeEngineGateway.processKey
  -> C++ Node-API 参数校验与转发
  -> Rust C ABI / pinyin-9 parser
  -> CompositionResult
  -> InputSessionStore
  -> 当前拼音、拼音组合、汉字候选
```

专用动作位于 ArkTS 键盘语义层，用于保证中文九键数字永远不能进入编辑器普通字符分支。跨 Native 边界继续复用阶段 3 已冻结、已覆盖 T9 数字的 `processKey`，所以本阶段没有新增或修改 C ABI/Node-API，interface/ABI 仍为 `7`。C++ 与 Rust 源码不需要修改。

`currentPinyin` 直接显示 Rust 当前路径。拼音组合栏按 `currentPinyin`、`pinyinCombinations` 的发布顺序构建，索引 `0` 表示当前路径，`1..N` 对应 Rust 备选路径；点击后必须调用 `selectPinyinCombination` 并以新的完整 `CompositionResult` 替换 Store。ArkTS 不排序、不猜测，也不只修改选中样式。

## 状态与回滚

- T9 数字只允许在中文、非密码、活动编辑会话且当前 Native 方案为 `pinyin-9` 时处理。
- 数字返回 commit/action 或编辑器预览更新失败时，重放数字、显式分音位置和已选拼音路径，恢复完整 Rust 状态。
- 删除优先调用 Rust `backspace`；组合为空后才删除编辑器正文。
- 空格有候选时提交现有首选，无组合时输入普通空格。
- 方案切换继续执行 Native 成功后更新 Store 并持久化，保存失败回滚引擎方案。
- 键盘隐藏、输入会话结束、编辑器丢弃组合、Ability 销毁、Profile/中英文切换均复用既有清理路径；raw、当前拼音、备选、候选、页码和高亮一起清理。

## 展示与适配

九键复用 `KeyboardPalette`、`BaseKey`、`LetterKey`、按压反馈、震动、音效、键帽预览和无障碍体系。`KeyboardMetrics` 新增有界拼音组合栏高度，并按同一屏幕 px 快照为 Phone/Pad 横竖屏计算面板高度；九键中文面板包含五排按键，英文、数字、电话和符号模式保持原有高度。

## 主机验证

| 项目 | 结果 |
| --- | --- |
| ArkTS 全量单元测试 | PASS：434 run / 434 pass / 0 failure / 0 error |
| `shuangpin-parser`、`ime-engine`、`ime-ffi` 定向回归 | PASS；T9 集成 6/6，FFI 31/31，相关 crate 其余单元/集成/doc tests 全部通过 |
| Rust fmt / workspace Clippy | PASS |
| Rust workspace 全量测试 | FAIL（既有阻塞）：`candidate-baseline` 的小鹤 `sentence-baseline.json` 与当前 `production.lex` 排序不一致；本阶段未修改 Rust、词库或冻结基线 |
| Release HAP | PASS：38,739,216 bytes，SHA-256 `AB4B9B6B9BB5DB573A9F1FA3D80F29F95D9EAF75D849AE55F0976DEF3C529863` |
| Release 内容门禁 | PASS |
| 模拟器九键输入闭环 | `NOT_RUN`：本轮没有执行设备安装和 UI 注入 |
| ARM64 真机 | `NOT_RUN`：没有连接目标设备 |
| Phone/Pad 旋转、分屏、三方应用和长时压力 | `NOT_RUN`：不能用主机单测替代设备结论 |

由于设备矩阵未执行且仓库缺少可用 Git 元数据，本阶段不标记 `COMPLETED`。
