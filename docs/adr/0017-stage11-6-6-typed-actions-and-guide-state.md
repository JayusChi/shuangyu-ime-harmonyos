# ADR 0017：阶段 11.6.6 单动作协议与引导状态机

状态：接受，2026-07-23。

## 背景

interface/ABI 3 的 `CompositionResult` 只能表达 `commitText`。日期时间需要在 ArkTS/HarmonyOS 边界取得时间，成对符号需要一次插入后执行受控光标定位；两者都不能安全压缩成普通候选字符串。同时正式转换合同没有交付快符、引导或动作表。

## 决策

1. interface/ABI 同步升级为 4，`CompositionResult` 增加一个 `ProtocolAction | null`，禁止数组。
2. 普通静态文本、符号和快符继续返回 `commitText`。
3. 当前跨层动作只允许 `DATE_TIME_TEXT` 与 `INSERT_PAIR`。
4. Rust 决策；C ABI 序列化；C++ 只校验/转换；ArkTS 串行执行有限白名单。
5. 日期时间只传格式 ID，不传任意格式字符串；时间由可注入 `TimeProvider` 提供。
6. 成对符号传完整文本和 UTF-16 偏移。先插入一次，再按编辑器返回的绝对索引定位；定位失败不重放插入。
7. `Idle/NormalCode/GuidePrefix/GuideCode` 状态机留在 Rust，guide、action、普通分类和用户层物理/逻辑隔离。
8. 正式数据缺失时只允许带冻结 SHA-256 且 `fixtureOnly=true` 的 internalDebug 原创动作表；Release 禁止携带。

## 后果

- 旧 interface 3 与新 bridge 不兼容，创建阶段明确失败。
- 未知动作和双提交在 Rust/C++/ArkTS 任一边界都不能静默降级。
- Release 产品入口、默认方案、设置 schema 和正式 bundle 均不改变。
- 正式快符、引导、日期时间和成对符号仍需客户提供可追溯数据后另行接收。
- 本阶段不包含 11.6.7 自动上屏，也不包含 11.6.8 产品入口。
