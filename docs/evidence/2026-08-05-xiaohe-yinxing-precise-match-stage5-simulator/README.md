# 小鹤音形精准匹配阶段 5 模拟器验收

日期：2026-08-05  
状态：`PASS（x86_64 Phone/Pad 模拟器与 signed Release 范围）`

## Release 产物

- signed Release HAP：`37,912,924` bytes，SHA-256 `292193f8fe3713e18a87cd9a0e4211de95ba6c26576ede0beb751338f4b2e956`。
- unsigned Release HAP：`37,768,240` bytes，SHA-256 `8b4df2853e16de3adfbea7009176b61c42a12e070ee5152636df500d53e302be`。
- 生成配置已核对为 `buildMode=release`、`debug=false`；`verify-release-hap.ps1` 正式资源白名单、bundle 大小/哈希和 Debug 内容负向检查全部 PASS。
- 请求权限仍只有 `ohos.permission.VIBRATE`，没有新增网络、麦克风或账号权限。

验收前曾发现输出目录中的旧 signed HAP 实际为 Debug 构建。该轮结果未作为最终 Release 证据；重新构建并通过内容门禁后，Phone/Pad 完整矩阵均使用上述 signed Release HAP 重跑。

## 设备矩阵

| 设备 | 目标 | 分辨率/方向 | 结果 | Release RSS 增长 |
| --- | --- | --- | --- | --- |
| HarmonyOS 6.1 x86_64 Phone 模拟器 | `127.0.0.1:5555` | `1320×2856` 竖屏 | PASS | `20 KiB` |
| HarmonyOS 6.1 x86_64 Pad 模拟器 | `127.0.0.1:5557` | `2880×1920` 横屏 | PASS | `12 KiB` |

两台模拟器均安装独立验收应用 `com.example.shuangyuime.acceptance`，与输入法包名不同，走真实跨应用编辑器连接。

## 用例

- 聊天单行输入框：`aaba` 唯一全码只提交一次“阿爸”，回车动作显示“发送”。
- URL 输入框：英文 `abc` 正常写入，回车动作显示“前往”。
- 搜索输入框：`aaba` 正常提交，回车动作显示“搜索”。
- 多行输入框：两次 `aaba` 由真实换行分隔，回车动作显示“回车”。
- 应用切换：已提交文本保持，恢复后无重复提交。
- 精准突发：无额外按键等待连续输入 10 轮 `aaba`，两端均得到恰好 10 个“阿爸”。
- 退格恢复：`aab` 退格为 `aa` 后补 `ba`，只提交一次“阿爸”。
- 隐藏/恢复：完成一次全码后隐藏并恢复键盘，再输入一次全码，最终恰好为两个“阿爸”。
- 长输入压力：50 轮成对按键后进程存活，RSS 增长远低于 128 MiB 门限；fatal、panic、SIGSEGV 和 process-crash 扫描为空。

机器摘要分别见 `phone-release/acceptance-summary.json` 和 `pad-release/acceptance-summary.json`；相应目录保留逐步布局 JSON、关键截图和 `fatal-scan.log`。`phone/`、`pad/` 是发现旧 HAP 构建模式问题前的预检记录，不作为最终 Release 结论。

## 范围限制

按本轮要求只做模拟器验收。ARM64 物理真机、分屏自动化、Debug/InternalDebug 重建和完整小鹤双拼设备矩阵为 `NOT_RUN`，因此这里不宣称完整发布门禁完成。
