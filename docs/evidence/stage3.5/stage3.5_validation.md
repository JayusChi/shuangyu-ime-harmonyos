# 客户修改阶段 3.5 验收记录

> 历史记录：本页记录的是旧版 Phone 独立辅助行方案。2026-07-21 后续产品决策已取消该行，改为“中/英”键长按系统选择器，并只在 Pad、特殊窗口或系统输入法区域缺失时保留内联显式切换键；当前规则见 `docs/INPUT_METHOD_SWITCHER_CAPABILITY.md`。

## 2026-07-21 后续布局调整验收

- ArkTS 全量单测通过；Release 与 Debug HAP 均构建成功。
- Phone（1320×2856）设备验收通过：没有自定义底部辅助行，候选栏右侧是唯一自定义收起键，长按“中/英”打开系统输入法选择器。
- Pad（2880×1920）设备验收通过：显式切换键位于现有功能行，短按切换下一输入法，长按打开系统选择器。
- Phone/Pad 验收均先完成 Stage 3.3 输入、候选、动态键与退格回归。最新日志和截图位于本目录对应的 `device/127_0_0_1_5555` 与 `device/127_0_0_1_5557` 子目录。

日期：2026-07-21

## 范围

- Pad 文本键盘空格行输入法切换键：短按下一输入法，长按系统选择器。
- Phone 独立底部辅助行：左切换、右收起、中间弹性留白。
- 窗口形态、方向、底部系统 inset 与高度模式的集中策略。
- 系统能力适配、直接切换失败回退、并发/连点、短长按互斥和会话失效。
- 3.1～3.4 输入、候选、中文大写键帽、动态键与顶部收起入口回归。

## 自动化结果

| 门禁 | 命令/入口 | 结果 |
| --- | --- | --- |
| ArkTS 全量单测 | `hvigorw --no-daemon --mode module -p module=entry@default test` | PASS：221 run / 221 pass / 0 failure / 0 error |
| Rust workspace | `scripts/test-rust.ps1` | PASS：workspace 单元、集成与 doc tests 全通过 |
| Debug HAP | `scripts/build-hap.ps1 -SkipRust -BuildMode debug` | PASS：双 ABI，14,723,047 bytes，SHA-256 `DD04CF2B95B3C9CAD0EC3CC67B38F3EC19A1451A8C30E1B82058C4ADE2C5D6E2` |
| Release HAP | `scripts/build-hap.ps1 -SkipRust -BuildMode release` | PASS：11,760,296 bytes，SHA-256 `0179EC769F095574E60769A9A0ECDFF6F3A3D923709EA21EDAFAAA9913944462` |
| Release 内容隔离 | `scripts/verify-release-hap.ps1` | PASS：正式源数量/冻结方案门禁通过 |
| Release APP | `hvigorw --no-daemon --mode project -p product=default -p buildMode=release assembleApp` | PASS：signed 4,748,343 bytes，SHA-256 `61B24E68A5E54A2C5AE4FB91850B9668D2792BAAE6FBD64107B3EE691A09309A` |
| Phone 设备验收 | `scripts/device-accept-stage3_5.ps1 -Target 127.0.0.1:5555 -Form Phone` | PASS |
| Pad 设备验收 | `scripts/device-accept-stage3_5.ps1 -Target 127.0.0.1:5557 -Form Pad` | PASS |

## 单元覆盖

- Phone 竖/横屏、Pad 竖/横屏、窄分屏和标准/高键盘模式。
- bottom inset 为 0 与大值、旋转后的重新分类和面板 resize 传播。
- Pad 切换键只进入文本空格行，三行字母键与其他功能键顺序不变，空格行总权重稳定。
- 直接切换成功、失败回退选择器、能力全部缺失、并发请求、失败后恢复和会话中止。
- 短按、长按、长按后 Click 抑制、连续快速点击、Cancel/销毁，以及 ArkUI Click 先于 Up/仅 Click 的事件顺序。
- 顶部与 Phone 辅助收起入口都映射既有 `HIDE_KEYBOARD`。

## 模拟器验收

Phone（1320×2856，竖屏）实际布局显示独立辅助行，左侧通用输入法图标、右侧收起图标、中间留白；主键区键位未压缩。短按从 `com.corrosion.shuangyuime` 切换到下一已启用输入法；恢复本输入法后，右侧收起使键盘窗口消失、宿主页保留。

Pad（2880×1920，横屏）实际布局在 `123` 与语言键之间显示输入法图标，字母三行不变。短按切到下一已启用输入法；恢复后长按打开系统“选择输入法”面板，面板列出 3 个实际可切换输入法。

两个设备验收都先执行 Stage 3.3 自动回归，中文 A-Z 大写键帽、中文小写输入、动态 Shift/分词、退格和候选提交全部 PASS。证据位于本目录的两个 target 子目录，包含日志、布局 JSON 和截图。

## 修复过程

首次设备短点按发现 ArkUI 自动化可能在 `TouchType.Up` 前触发 `onClick`，旧状态机仍处于 `PRESSING`，导致短按漏触发；长按不受影响。修复后状态机同时接受 Click-before-Up 与无障碍 only-Click，并保持 Long/Cancel 后的 Click 只消费不触发短按。新增回归后 ArkTS 221/221，Phone/Pad 短按均实际切换成功，Pad 长按仍只打开一次系统选择器。

## 未覆盖与风险

- 未连接物理 ARM64 真机；物理机结果为未执行。
- 三键导航、外接键盘、Phone 横屏与 Pad 竖屏未做设备交互验收；其中形态/安全区由单元测试覆盖，不能替代真机结论。
- 系统选择器服务 API 在 API 18 起被标为 deprecated，目标 API 24 当前仍可用；后续 SDK 升级需评估 `InputMethodListDialog` 迁移。
- Release 构建仍有项目既有 deprecated/可能抛异常警告，未发现新增编译错误；3.5 新增的选择器 deprecation 已在能力记录中显式登记。
