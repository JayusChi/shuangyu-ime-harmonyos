# 小鹤音形精准匹配阶段 3 证据

日期：2026-08-05  
状态：`COMPLETED`（主机自动化、HAP 构建与 x86_64 Phone 竖屏运行时范围）

## 结论

阶段 3 已按稳定 `schemeId` 把候选 UI 分成两种显式模式：`xiaohe` 保留可浏览的 50 项分页、展开面板和 Pad 侧栏；`xiaohe-yinxing` 只消费当前精确候选快照，不显示展开入口，也不进入 Phone/Pad 展开面板或 Pad 浏览侧栏。候选点击仍把当前页索引交给既有 `commitCandidate(index)`，没有新增 UI 直写宿主文本的路径。

一至三码的候选内容继续完全来自阶段 1 的精确查询结果；没有候选时，一至三码显示“继续输入形码”，完整码显示“无匹配全码”，两种状态都不创建伪候选。四码真实重码继续由引擎返回的完整精确集合直接渲染。无障碍文案区分“精确简码候选”和“完整码候选”，双拼原有“第 N 个候选”文案保持不变。

## 实现

- 新增 `CandidateUiPolicy.ets`，集中定义方案到 UI 模式的映射、浏览能力、展开入口、空候选反馈和无障碍文案。
- `CandidateBar.ets` 只在可浏览模式中显示展开动作；精准模式保留输入码、精确候选和可恢复空状态。
- `KeyboardRootStage3.ets` 从设置快照读取 `schemeId`。进入精准模式时关闭遗留展开状态，并同时阻断 Phone 展开面板、Pad 展开网格和 Pad 浏览侧栏；切回双拼后仍走原布局与分页路径。
- `CandidateExpansionPanel.ets`、`PadSideCandidateStrip.ets`、FFI/interface/ABI 和候选提交协议未改；方案隔离发生在根布局路由和候选栏动作层。

## 自动测试与构建

- ArkTS：349/349 PASS。新增 4 项策略回归，覆盖稳定方案 ID 路由、音形禁用浏览/双拼保留展开、可恢复空状态，以及简码/完整码无障碍文案。
- internalDebug HAP：41,066,440 bytes，SHA-256 `3516f065820d165cb72c41f1abab1610a5130daefc8f0918c8b017135c64bef6`。
- unsigned Release HAP：37,768,848 bytes，SHA-256 `96b7a1a3459e51eeb0bda30f160b8926c47e55c3936225de980de7af84c50667`。
- signed Release HAP：37,912,317 bytes，SHA-256 `e735fd3a640336ca71fe9479c11b4c46d7ebb34ec57c00a05af833afcc1170d1`；用于本轮最终 Phone 运行时复验。
- Release 内容门禁：PASS。正式音形 bundle 仍为 25,397,952 bytes、SHA-256 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`。
- 构建只报告项目既有的 SDK 弃用与可能抛异常警告，本次修改文件没有新增编译警告。

本阶段没有修改 Rust、C++、FFI、正式码表或查询/排序逻辑，因此没有把既有 Rust 门禁重复表述为本轮新执行结果。

## Phone 竖屏运行时证据

设备：HarmonyOS 6.1 x86_64 Phone 模拟器，1320×2856。使用独立包名 `com.example.shuangyuime.acceptance` 的跨应用编辑框。

- [音形 `bm` 精确简码候选](phone-portrait/yinxing-exact-short-code.png)：顶部栏只显示 `bm` 与当前精确候选，右侧是收起键盘图标，没有“展开”动作。布局快照见 `phone-portrait/yinxing-exact-short-code-layout.json`。
- [双拼 `h` 浏览入口保持](phone-portrait/shuangpin-expansion-preserved.png)：切回 `xiaohe` 后，同一位置继续显示“展开”，候选“和、好、还、会……”保持浏览型 UI。布局快照见 `phone-portrait/shuangpin-expansion-preserved-layout.json`。

设备中的验收编辑框和用户数据来自既有长期测试环境，因此本轮只把候选栏结构和方案隔离作为运行时证据，不借其宿主文本宣称全新用户数据基线。

## 限制

Pad、Phone 横屏、Pad 横竖屏、分屏、ARM64 物理真机和 signed Release 压力矩阵本轮 `NOT_RUN`；当前只连接一台 x86_64 Phone 模拟器。这些项目继续进入阶段 5 设备与 Release 验收，不以主机策略测试或 Phone 截图替代。
