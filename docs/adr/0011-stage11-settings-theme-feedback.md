# ADR 0011：阶段 11 设置、主题与按键反馈

## 决策

阶段 11 在 ArkTS 层建立唯一的强类型 `ImeSettings`，依赖方向继续保持 `ArkTS -> C++ -> Rust`。设置页面不访问 Preferences、Native 或 Rust 句柄；所有修改经 `SettingsController`，持久化成功后才进入 `SettingsStore`。

## 设置模型与默认值

当前 `schemaVersion=1`。字段为 `schemeId`、`themeMode`、`keyboardHeightMode`、`candidateFontSizeMode`、`hapticLevel`、`keySoundEnabled` 和 `userLearningEnabled`。默认小鹤双拼、跟随系统、标准高度、标准候选字号、轻震动、关闭按键音、开启用户学习。

标准高度仍使用 1100px 面板、42vp 字母键和统一 15vp 底部间距；标准候选字号仍为 14fp。因此首次升级不会改变阶段 10 的默认外观。按键音默认关闭，避免在用户未明确选择前发声。

## 校验与迁移

Preferences 键名只存在于 `SettingsRepository`。仓储将值读为独立字符串字段，`SettingsMigration` 先处理无版本配置和已知旧字段（`dark_mode`、`keyboard_scale`、`candidate_font_scale`、`vibration_enabled`），`SettingsValidator` 再逐字段校验。单字段损坏只回退该字段；不存在的方案回退小鹤；未知未来版本被标准化为当前版本而不崩溃。标准化结果写回，迁移重复执行保持幂等。

## 生命周期与即时同步

模拟器证明 MainAbility 与 InputMethodExtensionAbility 具有独立 ArkTS 运行时；因此 `SettingsStore` 只承担各运行时内部的即时通知，Preferences `ime_settings` 是持久化真实来源。EntryAbility 前台和 ExtensionAbility 创建时重新加载，输入会话开始、键盘显示和编辑器切换时重新应用。主题、布局、候选栏和面板控制器均订阅各自运行时的同一个 Store，不创建第二套设置状态。

主题、字号和高度只更新 ArkUI 状态与面板尺寸，不清空组合、不改变模式、不重建 Native。方案切换例外：切换前受控清空未提交组合并 reset Rust 会话；失败时恢复旧方案且不持久化。

## 主题 Token

`KeyboardThemeResolver` 将跟随系统、强制浅色和强制深色解析为已有的浅/深键盘 Token。设置页使用单独但语义一致的 `SettingsThemeTokens`。系统配置变化由 Ability 的 `onConfigurationUpdate` 更新 Store；强制主题忽略系统变化。

## 高度与候选字号

紧凑/标准/较高从同一竖屏或横屏基准按 0.88/1.0/1.12 派生，面板高度为 990/1100/1210px。底部 padding 永远取唯一的 `KEYBOARD_BOTTOM_PADDING=15`；布局行、数字等宽权重和小数三列结构未复制也未修改。

候选字号为 12/14/17fp，只传入 `CandidateBar` 的候选文本；点击区域 padding 和栏高不变，不触发 Native 查询或清空候选。

## 震动与音效

`HapticFeedbackService` 是唯一 vibrator 适配层，使用 SDK API 24 的 `vibrator.startVibration`，四档映射为关闭和 9/16/24ms；连续删除以 120ms 节流。底层异常只记录不含输入内容的能力错误，不阻断按键。

`KeySoundService` 使用一个可复用 SoundPool。`HarmonyKeySoundBackend` 在应用沙箱生成 24ms 项目自有 PCM WAV，按媒体使用类型以低音量播放，快速输入以 24ms 限流，销毁时 unload/release。没有网络、麦克风、录音或版权不明资源。模拟器无法客观证明扬声器或物理震感，相关结论必须留给 ARM64 真机。

## 用户学习与清空

最终学习策略为“全局开关 AND 当前编辑器允许学习”。编辑器密码策略仍优先禁止。关闭开关同时调用现有 Rust 全局能力和会话能力，不删除已有记录；Rust 现有语义也会停用已有用户加权，使排序回到基础顺序。

清空操作由设置页二次确认。MainAbility 先持久化一次性待处理请求，并向本包发送定向 Common Event；存活的 InputMethodExtensionAbility 收到事件后调用 `InputSessionController -> EngineCoordinator -> NativeEngineGateway -> C++ -> Rust` 的阶段 9 既有接口。新输入会话还会尝试消费持久化请求作为兜底。该操作幂等，成功后清空当前候选显示；失败不显示成功，也不删除设置、方案或系统词库。事件不携带输入内容或模型内容。

## 双拼方案

方案目录目前只暴露真实存在的 `xiaohe`。本阶段没有增加微软双拼、自然码或搜狗双拼，没有修改小鹤规则、Rust 解析器、词库、排序或用户模型格式。

## 接口、权限与依赖

没有新增 C ABI、Node-API 或第三方依赖，ABI/interface version 保持 2。跨运行时通知只使用 HarmonyOS BasicServicesKit Common Event。仅新增 `ohos.permission.VIBRATE`；未新增网络、麦克风或录音权限。
