# Pad results

目标：x86_64 Tablet 模拟器，OpenHarmony 6.1.1.125，2880×1920 横屏。

- Stage 10 编辑器链路在密码场景前的普通中文输入、候选、删除、提交、Shift/Caps、
  数字与符号模式均 PASS。
- 阻断失败与 Phone 一致：受保护表面不向 `uitest` 暴露键帽，脚本误判为
  `APPLICATION_SAFE_LAYOUT` 后报无 Shift；不能据此认定产品 Shift 缺失。
- 原 Stage 11 脚本错误地要求 internalDebug 启动后直接位于正式设置页，实际入口为
  `pages/DebugIndex`；脚本已做最小导航修正，但本轮未完成 Pad 全量复跑。
- signed Release 独立 TextInput 与完整分屏/旋转/应用矩阵：NOT RUN。

结论：Pad 发布验收未通过。
