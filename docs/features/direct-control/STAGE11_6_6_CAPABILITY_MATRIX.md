# 阶段 11.6.6 能力矩阵

冻结日期：2026-07-23。

权威审计输入：

- `dictionaries/audit/xiaohe-yinxing/conversion_contract.json`
- `dictionaries/audit/xiaohe-yinxing/command_policy.json`
- `dictionaries/generated/xiaohe-yinxing-production/manifest.json`
- `dictionaries/generated/xiaohe-yinxing-production/action-metadata.json`

正式来源 28/28 文件在本阶段保持路径、大小和 SHA-256 不变。正式 action metadata 共 6 条，`execution_allowed=false`；5 条不支持命令和 1 条网络动作均保持拒绝。本阶段没有把它们重新解释为候选或协议动作。

| 能力 | 正式状态 | 依据与处置 |
| --- | --- | --- |
| 八类普通静态文本/符号 | `AVAILABLE` | 已在正式生产 bundle 中，通过既有 `commitText` 提交；排序和分类语义不变。 |
| 快符 | `DEFERRED_MISSING_SOURCE` | 转换合同明确延期，正式 bundle/action metadata 没有可执行快符表。 |
| 日期/时间文本 | `DEFERRED_MISSING_SOURCE` | 没有获批格式映射和触发编码；仅实现封闭运行时与 internalDebug fixture。 |
| 成对符号/光标定位 | `DEFERRED_MISSING_SOURCE` | 没有获批成对符号表；仅实现封闭运行时与 internalDebug fixture。 |
| 分号引导表 | `DEFERRED_MISSING_SOURCE` | 正式 bundle 不含 guide 区；状态机已实现，但正式数据不伪造。 |
| 通用动作运行时 | `INTERNAL_DEBUG_FIXTURE_ONLY` | 原创 `stage11_6_6_actions.json`，`fixtureOnly=true`，仅 internalDebug 注入。 |
| shell/PowerShell/cmd/外部程序 | `REJECTED_UNSAFE` | 不进入动作模型，不执行，不作为文本降级。 |
| URL/FTP/WebDAV/网络 API | `REJECTED_UNSAFE` | 不进入动作模型；Release 继续无 `INTERNET` 权限。 |
| 账号、密码、Token、API Key | `REJECTED_UNSAFE` | 原始敏感配置继续隔离，不进入运行时或 HAP。 |
| Android Intent/任意平台键码/动态脚本 | `REJECTED_UNSAFE` | 无适配白名单，加载阶段拒绝。 |
| 任意文件读写/剪贴板读取 | `REJECTED_UNSAFE` | 不在本阶段动作协议中。 |

阶段结论：

```text
11.6.6 RUNTIME COMPLETED
11.6.6 PRODUCTION DATA PARTIALLY DEFERRED
11.6.6 EDITOR-SIDE DEVICE ACTION ACCEPTANCE COMPLETED
```

通用运行时、跨层协议、ArkTS 安全执行器、Release 隔离和 x86_64 Debug fixture 两轮验收已经完成。独立 MainAbility ArkUI `TextInput` 中的日期实际提交、成对 emoji 单次插入和非 BMP 光标探针也已通过；设备日志确认本次 `InputClient` 光标索引按 UTF-16 code unit 计算。`PRODUCTION DATA PARTIALLY DEFERRED` 仅表示正式转换合同仍未交付快符、引导、日期时间和成对符号映射，不能用测试 fixture 伪造正式产品数据。
