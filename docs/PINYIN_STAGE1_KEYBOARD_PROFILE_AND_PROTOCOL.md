# 26 键全拼和 9 键计划阶段 1：键盘档案与通用协议

状态：`COMPLETED（主机自动化与 Release 构建范围）`  
完成日期：2026-08-10

## 目标与边界

本阶段只建立后续全拼和 9 键共用的配置、解析和跨层协议，不交付可选择的全拼或 9 键输入。
现有 17 键双拼、26 键双拼和小鹤音形继续使用原引擎与候选语义。

## 实现结果

### 键盘档案与设置迁移

- 新增 `KeyboardProfile`，集中描述稳定 ID、输入方案、触屏布局、引擎方案、能力和启用状态。
- 当前启用 `xiaohe-17`、`xiaohe-26` 以及保留音形行为的
  `xiaohe-yinxing-17`、`xiaohe-yinxing-26`。
- `quanpin-26` 和 `pinyin-9` 已登记但保持禁用；未知或未启用档案回退到 `xiaohe-26`。
- 设置 schema 升至 `5`，`keyboardProfileId` 成为方案和布局的唯一真实来源，`schemeId` 由档案派生。
- 旧配置迁移矩阵如下：

| 旧方案 | 旧布局 | 新档案 |
| --- | --- | --- |
| `xiaohe` | 17 键 | `xiaohe-17` |
| `xiaohe` | 26 键或缺失 | `xiaohe-26` |
| `xiaohe-yinxing` | 17 键 | `xiaohe-yinxing-17` |
| `xiaohe-yinxing` | 26 键或缺失 | `xiaohe-yinxing-26` |
| 未知方案或非法组合 | 任意 | `xiaohe-26` |

原键盘布局 Preferences 只作为迁移输入读取。`KeyboardLayoutPreferenceController` 已降为
`SettingsController` 的兼容适配器，不再维护第二份持久化状态。方案切换继续执行
Native 先切换、设置后保存、失败回滚。

### Rust 解析公共层

- 新增 `PhoneticParser` 公共边界和 `XiaoheShuangpinParserAdapter`。
- `ParseResult` 统一携带原始输入、解析音节、查询意图、展示分段、当前拼音和拼音备选组合。
- 现有小鹤解析器负责历史两码展示分段；`engine-protocol` 不再猜测“两字符一段”。
- 双拼没有拼音多选路径时返回空的 `pinyinCombinations`；全拼和 9 键解析器留待后续阶段实现。

### 跨层协议

interface/ABI 同步升级到 `6`，engine version 为 `0.0.1-pinyin-stage1`。
`CompositionResult` 新增必填字段：

```typescript
currentPinyin: string
pinyinCombinations: string[]
```

Rust 是字段语义唯一来源；C++ 负责类型校验和转换，ArkTS 负责状态保存与展示。旧 interface `5`
会在创建引擎时被拒绝，避免新旧桥接库混装。

## 验收与验证

- 键盘档案单测覆盖合法档案、未来禁用档案、17/26 键迁移、音形迁移和未知值回退。
- Rust 回归覆盖解析适配、组合输入、退格、候选提交、分页、方案切换、协议字段和旧 ABI 拒绝。
- 候选基线中的候选文字、顺序和行为保持不变；仅因新增 JSON 字段更新序列化字节基线。
- ArkTS 全量单元测试：PASS。
- Rust workspace check/test/fmt/Clippy 与候选确定性门禁：PASS。
- x86_64 与 arm64-v8a Native Release 构建：PASS。
- unsigned Release HAP 构建：PASS，`38,040,556 bytes`，SHA-256
  `69E14BD027E8B700753104E7E0522B784555A9D33ABAAB2A1ACCE2B2A4501E68`。

本阶段未进行模拟器或 ARM64 真机专项验收，状态为 `NOT_RUN`；不得据此宣称全拼或 9 键已经可用。

## 后续阶段

阶段 2 在上述公共边界上实现并启用 `quanpin-26`。阶段 3、4 再实现 T9 数字解析、拼音组合消歧和
9 键界面；阶段 5 完成联合设备验收与发布收口。
