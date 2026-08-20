# Pinyin stage 5 evidence index

日期：2026-08-13

权威结论与主机指标见 `../../../PINYIN_STAGE5_FINAL_ACCEPTANCE.md`。

- `device-phone/`：x86_64 Phone 1320×2856 竖屏的独立验收客户端布局证据，包括 profile 入口、全拼 `nihao`、T9 `64/64426`、隐藏恢复、深色和 URL 策略。
- `device-pad/`：x86_64 Pad 2880×1920 横屏的布局证据，包括设置页 profile、强制虚拟键盘、双拼 `nihc`、全拼 `nihao`、T9 `64426`。

目录内含探索性自动化的中间布局。曾有一次 Phone T9 使用旧坐标导致数字直输、一次 Pad 在 AUTO 实体模式下找不到虚拟键盘；两者均未计入 PASS，随后分别用每键实时布局定位和设置页强制虚拟键盘重跑。最终结论只采用阶段 5 报告明确列出的断言。

连接设备均报告 `const.product.cpu.abilist=x86_64` 与 `model=emulator`。ARM64 物理真机为 `NOT_RUN`。
