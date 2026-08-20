# 电脑端整改阶段 5 验证报告

验证日期：2026-08-06  
结论：`STAGE_5_COMPLETED / COMPUTER_REMEDIATION_COMPLETED_WITH_HARDWARE_LIMITATIONS`

## 实现结论

- 浮动候选窗不再渲染 `rawInput/preeditText` 或候选编码提示，只保留编号和候选词。宽度由当前实际可见候选、文字长度、候选字号和分页状态估算，范围改为 `72～560 vp`，不再固定保留 `280 vp` 空白。
- 设置 schema 升级到 4，新增 `AUTO / 始终使用实体键盘 / 始终显示虚拟键盘`。AUTO 规则为：2in1 使用实体模式；Tablet 仅在检测到 `ALPHABETIC_KEYBOARD` 时使用实体模式；其他设备使用触屏模式。
- 输入法 Ability 同时监听设置 Store 和实体键盘设备变化。有效模式改变时，固定键盘与候选面板通过既有唯一所有权队列串行切换，不清组合、不重复提交。
- 正式 `entry/src/main/module.json5` 已声明 `2in1`。

## 主机验证

| 项目 | 结果 |
| --- | --- |
| ArkTS 全量单元测试 | `384/384 PASS` |
| default Debug HAP | PASS |
| internalDebug HAP | PASS，41,285,424 bytes，SHA-256 `4094efb8831ce7adb867d50bb2a3222e38df45311450a24f1581f3d35f4e4587` |
| unsigned Release HAP | PASS，37,862,293 bytes，SHA-256 `92a800b05e3e9320c0ecc98c771917154e977e9493859e6457abfa93e2c363f9` |
| signed Release HAP | PASS，38,008,487 bytes，SHA-256 `b6f5cef6bcd9a0dbb5b478a302c03b4e510040ad31dd86224bf8822537a92da4` |
| signed/unsigned Release 内容门禁 | PASS |
| 阶段 5 源码与产物门禁 | `COMPUTER_STAGE5_RESULT=PASS` |

新增测试覆盖 AUTO 设备规则、显式偏好覆盖、schema 持久化/非法值回退、候选数量驱动宽度以及超长候选上限。完整测试结果位于 `entry/.test/default/intermediates/test/coverage_data/test_result.txt`。

## 2in1 signed Release 验证

环境：HarmonyOS 6.1 / API 24 / x86_64 / `deviceType=2in1` 模拟器，独立宿主 `com.example.shuangyuime.acceptance` 与系统浏览器。

- signed Release 安装成功；单行、多行、搜索和浏览器输入框的候选显示、鼠标/数字提交、Esc、焦点保持、窗口移动/缩放及应用切换全部 PASS。
- 日志保持 `HARDWARE_READY`、无固定键盘、无 floating fallback 或 fatal 标记。
- 用户显式选择 `TOUCH` 后，活跃输入链路记录 `input presentation switched: ... HARDWARE -> TOUCH`，随后固定键盘创建并显示；重新选择 `AUTO` 后记录 `TOUCH -> HARDWARE`，固定面板释放，重新输入时浮动候选恢复。
- 输入单码 `s` 的设备 UI 树中，候选窗根节点为 `[1042,495][1351,601]`，物理宽度 309 px；密度 1.9 下约 `162.6 vp`。其文本节点只有 `1. 三` 和 `2. 所有`，没有单独的 `s` 或候选编码；这直接验证了“仅候选词 + 按候选数量收缩”。原始 UI 树见 `adaptive-width-s-candidates.json`。
- signed Release 原始运行证据见 `signed-release-device/`；同代码 unsigned Release 的对照闭环见 `device/`。两个自动化目录均以复用的阶段 4 跨宿主闭环脚本采集，因此控制台终态标签仍为 `COMPUTER_STAGE4_RESULT=PASS`。

## 设备矩阵与限制

| 设备/场景 | 本阶段结论 |
| --- | --- |
| x86_64 2in1 模拟器 + signed Release | PASS |
| Phone 模拟器阶段 5 专项重跑 | `NOT_RUN`；阶段 4 触屏基线 PASS，不冒充本阶段重跑 |
| Tablet 模拟器热插拔专项 | `NOT_RUN`；AUTO 热插拔策略与串行切换由自动测试覆盖 |
| 真实 USB/蓝牙键盘 | `NOT_RUN` |
| ARM64 2in1 物理设备 | `NOT_RUN` |
| AGC/应用市场上传检测 | `NOT_RUN` |

阶段 5 的代码、设置、正式设备声明、主机构建门禁和现有 2in1 signed Release 闭环已经完成。以上真实硬件与市场侧项目必须在获得对应设备/账号后补验，不能用模拟器或按键注入替代。

## 复现入口

```powershell
powershell -ExecutionPolicy Bypass -File scripts\accept-computer-stage5.ps1 -Target 127.0.0.1:5555
```
