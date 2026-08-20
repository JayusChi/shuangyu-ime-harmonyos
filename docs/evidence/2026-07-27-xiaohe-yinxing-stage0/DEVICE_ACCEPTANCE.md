# 小鹤音形改进阶段 0：设备行为冻结

检查日期：2026-07-27。

当前 `hdc list targets -v` 只发现：

- `127.0.0.1:5555`：`x86_64`、`emulator`、`phone`
- `127.0.0.1:5557`：`x86_64`、`emulator`、`tablet`

没有 ARM64 物理真机。本轮阶段 0 没有把模拟器结果描述成真机结果，也没有重复执行完整 UI 自动化；设备行为引用同日已经完成的 11.6.7/11.6.8 模拟器证据。阶段 0 新增的主机快照仅用于补足可重复的查询与双拼隔离证据。

## 行为矩阵

| # | 行为 | 状态 | 证据或备注 |
| ---: | --- | --- | --- |
| 1 | 切换到 `xiaohe-yinxing` 后输入法进程实际使用音形方案 | PASS | `docs/evidence/2026-07-27-stage-11.6.8-revalidation/positive-device/` |
| 2 | 切回 `xiaohe` 后恢复双拼方案 | PASS | 同上；阶段 0 主机隔离快照再次冻结返回后的“你好”首选 |
| 3 | 设置页与输入法进程跨进程状态一致 | PASS | 11.6.8 positive-device 与 ADR 0019 |
| 4 | 重启输入法扩展后方案保持 | PASS | 11.6.8 positive-device |
| 5 | 强停后重新进入恢复方案 | PASS | 11.6.8 positive-device |
| 6 | 候选第一页 | PASS | 11.6.7/11.6.8 设备证据；阶段 0 `candidate_behavior_baseline.json` |
| 7 | 翻页 | PASS | 11.6.7 device A～N；主机状态机回归 |
| 8 | 选择候选 | PASS | 11.6.7 device A～N；Rust/ArkTS 回归 |
| 9 | 四码唯一自动上屏 | PASS | 11.6.7 device A～N；阶段 0 三个真实四码快照 |
| 10 | 四码多候选不自动上屏 | PASS | 11.6.7 device A～N；阶段 0 三个真实四码快照 |
| 11 | 第五键顶屏 | PASS | 11.6.7 device A～N；状态机回归 |
| 12 | 删除 | PASS | 11.6.7 device A～N；双拼隔离快照 |
| 13 | reset | PASS | 11.6.7 device A～N；双拼隔离快照 |
| 14 | 空码清屏 | PASS | 11.6.7 device A～N；状态机回归 |
| 15 | 正向空码切分 | PASS | 11.6.7 device A～N；状态机回归 |
| 16 | 反向空码切分 | PASS | 11.6.7 device A～N；状态机回归 |
| 17 | 分类开关持久化 | PASS | 11.6.8 positive-device 与 ArkTS 设置测试 |
| 18 | 用户规则持久化 | PASS | 11.6.7 设备证据与 Rust reload 快照 |
| 19 | 资源损坏回退 | PASS | `docs/evidence/2026-07-27-stage-11.6.8-revalidation/negative-device/` 与 `negative-device-j/` |
| 20 | 无网络权限 | PASS | 本轮 Release 正/负门禁；网络权限负例按预期拒绝 |

## 本轮未执行

| 项目 | 状态 | 原因 |
| --- | --- | --- |
| ARM64 物理真机完整矩阵 | NOT_RUN | 没有连接 ARM64 物理设备 |
| 物理真机首键延迟、方案切换延迟和内存 | NOT_RUN | 无物理真机；主机数据不能替代 |
| signed Release 独立第三方 TextInput 本轮重跑 | NOT_RUN | 本轮聚焦阶段 0 主机基线，引用同日既有模拟器证据 |
| 密码场景完整键帽 UI 自动化 | BLOCKED | x86_64 模拟器受保护安全键盘不向 `uitest` 暴露键帽，见 11.6.9 `known-limitations.md` |

后续执行入口：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage11_6_9.ps1 -Scope Arm64 -Arm64Serial <physical-device-serial>
```

在没有补齐上述真机与受保护键盘证据前，不得将本文件解读为 ARM64 真机发布验收通过。
