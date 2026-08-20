# Known limitations and required follow-up

1. 改造密码验收：在系统安全键盘被 `uitest` 隐藏时记录为受保护系统路径并使用可审计
   的替代信号/人工真机证据，不得误判为应用布局；随后在 Phone/Pad 复跑完整 Stage 10。
2. 将 Stage 11 清空用户模型流程改为通过 DebugIndex 导航，在 Phone/Pad 完整复跑。
3. 提供并安装独立 ArkUI TextInput 测试包，使用本轮 signed Release HAP 执行。
4. 连接至少一台非模拟器 ARM64 HarmonyOS 设备，执行完整矩阵。
5. 增加设备端时延/内存采集，覆盖安装、复用、方案切换、提交、分页和 reset。
6. 执行聊天、搜索、浏览器、多行、旋转/分屏、应用切换与持续输入压力。
7. 当前 `.git` 目录不能被 Git 识别，无法提供基线状态、diff 或提交 ID；修复仓库元数据后
   再做一次可追溯复验。
