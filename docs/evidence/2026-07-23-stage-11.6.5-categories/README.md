# 阶段 11.6.5 验收证据

结论：`COMPLETED`（2026-07-23）。

八类产品合同、不可变分类快照、分类感知查询、原子跨层更新、设置迁移/回滚与 internalDebug 开关均已完成。interface/ABI 为 3；Release 产品入口仍只有 `xiaohe`，rawfile 仍仅 `production.lex`。

## 主机验证

- Rust fmt、全 workspace/all-targets/all-features Clippy `-D warnings`、348 项 workspace 测试：PASS。
- FFI：23/23 PASS。
- ArkTS：`Tests run: 290, Failure: 0, Error: 0, Pass: 290, Ignore: 0`。
- Native：x86_64 `25,530,484` bytes / `9563D883E8B76DC46E9E6F33B36136FA6B7931A6244888F6D77653E10DAE108B`；arm64-v8a `26,072,516` bytes / `4DDAC43632226AEC5474DFC31389739F229A6F04354F71616E768EC40C6F4D75`。
- Debug HAP：`40,551,155` bytes / `03BFDC39CE9191486836D93A125AF7A0E0C5E186C1C12D64696C35DC1A28C73E`。
- Release HAP：`12,046,372` bytes / `59BA888F90CFF91A49ADA30D76ED02A83A39B5B6646DA35D9319ECA0731AC809`。
- Release 正向与六类负向门禁：PASS；包内 rawfile 仅 `resources/rawfile/production.lex`（3,734,484 bytes）。
- 正式来源不可变：28/28 PASS；manifest/contract SHA-256 保持冻结值。
- PowerShell：40/40 脚本语法解析 PASS。

真实命令和 exit code 见 [host-verification.md](host-verification.md)。

## 设备验证

目标 `127.0.0.1:5555`，x86_64 HarmonyOS emulator `6.1.0.125(SP9DEVC00E16R1P1)`，分辨率 `2880x1920`。安装最终 Debug HAP 后执行第一轮 A～L，force-stop/restart 后执行第二轮 A～L；两轮 12/12 PASS。设备 JSON、transcript、布局树和截图位于 [device](device/)。

开发验收过程中先后发现并修复 UI 线程连续阻塞和错误前缀样例；正式结论只引用最终 `device-acceptance.json` 的两轮 PASS。

## 未执行

- ARM64 物理真机；
- 第三方应用输入框；
- 同一设备横竖屏切换（本轮使用 2880×1920 横屏模拟器）；
- 第二台在线模拟器 `127.0.0.1:5557` 的重复 A～L。
