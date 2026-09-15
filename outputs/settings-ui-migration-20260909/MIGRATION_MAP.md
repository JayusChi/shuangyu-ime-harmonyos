# 设置界面迁移对照

范围：仅调整 UI 结构、导航、显示绑定和文案。现有控制器、存储、设置模型、迁移规则、键盘行为、原生桥接及 Rust 引擎保持不变。

| 原设置 / 功能 | 新位置 | 保留的调用与行为 |
| --- | --- | --- |
| 输入方案：自动识别 / 虚拟 / 实体 | 输入设置 → 键盘使用方式 | `setInputPresentationPreference`，三个原枚举值 |
| 五种键盘方案 | 输入设置 → 输入方案 → 对应布局；也可从键盘布局进入 | `setKeyboardProfile`；`xiaohe-18`、`xiaohe-26`、`quanpin-26`、`pinyin-9`、`xiaohe-yinxing-26` 原 ID 完整保留，点击后一次提交 |
| 用户学习 | 词库与个性化 → 学习输入习惯 | `setUserLearningEnabled` |
| 清空用户词频 | 词库与个性化 → 清除学习记录 | 原确认框、`clearUserModel`，取消不执行清除 |
| 智能标点时间 | 输入设置 → 智能标点 | `setSmartPeriodTimeoutMs`；关闭 / 300 / 500 / 800 / 1000 毫秒 |
| 智能标点范围 | 输入设置 → 智能标点 → 生效标点 | 原 `SMART_PUNCTUATION_OPTIONS` 完整集合、原 `MultiChoiceSettingRow` 和 `setSmartPunctuationSymbols` |
| AI 总开关 | 输入设置 → AI 辅助输入 | `setAiEnabled`；原服务可用性与同意条件保留，仅简化说明文字 |
| 上屏后本地关联词 | 输入设置 → 上屏后联想 | `setLocalAssociationEnabled`；独立于 AI 云端功能 |
| 音形切分模式 | 输入设置 → 小鹤音形选项 | 原方案条件、`setCodeTableReverseSplitEnabled` |
| 音形分类区域、码表分类管理 | 词库与个性化 → 小鹤音形词库分类 | 复用原分类管理页面；10 个 UI 分类覆盖原 12 个底层分类，关联分类合并、首选必选、重置、暂存、保存和未保存退出确认均不变 |
| 全拼拼写纠错 | 输入设置 → 全拼容错 | 原方案条件、`setSpellingCorrectionEnabled` |
| 8 组模糊音 | 输入设置 → 全拼容错 → 模糊音 | `setFuzzyOption`，n/l、z/zh、c/ch、s/sh、in/ing、en/eng、an/ang、ian/iang 全部保留 |
| 跟随系统 / 浅色 / 深色 | 键盘与外观 → 主题 | `setThemeMode`，原三个枚举值 |
| 键盘高度 | 键盘与外观 → 键盘尺寸 | `setKeyboardHeightScale`；原 0.8–1.2 范围、0.05 步长、2 位小数；新增加减按钮使用同一个方法 |
| 键盘架高层 | 键盘与外观 → 底部工具栏 | `setKeyboardLiftLayerEnabled` |
| 固定候选字号 | 候选设置 | `setCandidateFontSize(value)`，原最小最大常量 |
| 浮动候选字号 | 候选设置 | `setCandidateFontSize(value, true)`，与固定字号分别保存 |
| 候选窗位置 | 候选设置 → 候选位置 | `setCandidatePresentationMode`；原 bar/floating 两个选项、旧 auto 值的原展示映射不变；只浏览不改写 auto |
| 长按时间 | 按键与反馈 → 长按时间 | `setLongPressDurationMs`，原 200/300/500/700 选项 |
| 震动等级 | 按键与反馈 → 按键震动 | `setHapticLevel`，关/轻/中/强 |
| 按键音开关 | 按键与反馈 → 声音 | `setKeySoundEnabled` |
| 按键音量 | 按键与反馈 → 声音 | `setKeySoundVolume`，原 0–100 范围；音效关闭时仍可调整音量 |
| 键盘结构与皮肤 | 键盘与外观 → 键盘结构与皮肤 | 原 `pages/KeyboardCustomization` 及全部编辑、导入功能不变 |
| 用户词库 | 词库与个性化 → 我的词库 | 原 `pages/UserLexicon` 和同一个编辑器；增加、直通、隐藏系统词、固顶、第 N 位、搜索、批量操作和移除保留 |
| 网页 / 目录 / 文字直通 | 词库与个性化 → 自定义直通 | 原词库路由，进入时通过 UI 参数默认选中 DIRECT；保存、目标校验、目录选择、候选提示处理不变 |
| 词库合并 / 覆盖导入与文本导出 | 我的词库 / 自定义直通的原编辑器内 | `importText` 与 `exportText` 原实现 |
| 固定位置词库 | 我的词库 / 自定义直通的原编辑器内 | 来源选择、合并/覆盖、启停、切换模式、立即导入和移除原实现 |

新增内容只包括帮助说明、当前设置摘要、候选显示预览、导航和滑杆加减按钮。预览不连接编辑器、不调用输入引擎；拖动期间只刷新预览，仍在原 Slider End/Click 时机保存。

## 改动边界证明

- `source-baseline.json` 保存改动前 625 个源文件的 SHA-256；验收结束再逐项比较。
- 既有文件只允许 `SettingsPage.ets`、`UserLexiconPage.ets`、`XiaoheYinxingCategoryManagerPage.ets` 出现差异。
- 新增 `SettingsNavigationComponents.ets`，内容仅为设置列表、单选列表、滑杆和候选预览组件。
- 两套 `main_pages.json` 已恢复到原始 SHA-256，不增加页面路由。
- 分类管理页只改两个标题字符串；词库页只增进入直通的默认 UI 状态和标题显示。
- 原主页面 22 个修改方法中，20 个仍在新设置页调用；分类相关操作统一使用原分类管理页的 `setXiaoheYinxingEnabledCategoryIds`。

最终模拟器记录、构建结果与验证边界见 `ACCEPTANCE_REPORT.md`。
