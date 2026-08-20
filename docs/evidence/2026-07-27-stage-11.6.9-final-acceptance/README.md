# 阶段 11.6.9 最终验收证据

结论：**11.6.9 PARTIALLY COMPLETED**。

本目录记录 2026-07-27 的实际执行结果。主机、双架构编译、HAP、Release 内容/签名、
来源不可变、确定性双构建和主机性能均通过；Phone/Pad 仅有 x86_64 模拟器，受保护
密码键盘无法由现有 `uitest` 脚本识别，设置自动化在清空用户模型流程前停止；
signed Release 独立 TextInput、
ARM64 物理真机、设备性能和完整稳定性压力测试未执行。因此不能给出发布验收通过结论。

权威运行目录：

- `runs/20260727-121537-fe53c474`：Host
- `runs/20260727-122431-a293a812`：Build/Release
- `runs/20260727-122547-6c99fc31`：Performance
- `runs/20260727-122614-8072c5af`：Phone
- `runs/20260727-122805-4825a95a`：Pad
- `runs/20260727-123010-66c3af81`：ARM64 设备发现
- `reruns/phone-stage11-final`：修正 DebugIndex 导航后的设置链路复跑

汇总文件：

- `acceptance-summary.md`
- `host-gate-results.md`
- `device-matrix.md`
- `performance-results.md`
- `release-hap-audit.md`
- `security-negative-results.md`
- `known-limitations.md`
- `artifacts.json`
- `performance.json`
- `device-results.json`
