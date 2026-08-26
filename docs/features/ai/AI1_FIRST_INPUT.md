# AI 输入法第 1 阶段：第一版 AI 输入

## 阶段结论

状态：`CORE_IMPLEMENTED / PRODUCTION_COMPLETION_BLOCKED / HOST_RELEASE_VALIDATED / DEVICE_NOT_RUN / CLOUD_NOT_CONFIGURED`

AI-1 的客户端核心输入链已完成：本地关联词、五个显式 AI 动作、云端 Provider 安全边界、建议展示与安全替换/撤销、请求生命周期、隐私日志及 Release 门禁。本轮进一步完成了供应商无关的自有代理参考实现、EdDSA 短期鉴权验证、客户端内存令牌边界、OpenAPI/部署模板、隐私同意草案和第三方宿主结果门禁。

**本阶段仍未完全实现，不能标记为生产完成。** 仓库没有已批准的生产 HTTPS 域名、真实身份签发/吊销和设备绑定、最终协议/配额审批、数据留存及不训练合同、最终隐私文案、生产部署与真实供应商适配，也没有完成联网联调和设备/第三方宿主验收。因此没有虚构端点、凭证或合规结论，没有加入 INTERNET 权限，也没有宣称真实云调用成功。正式运行时继续使用不可用 Provider，云端入口失败关闭。

## 产品行为

- 本地关联词默认关闭，只在普通中文文本编辑器、活动且已连接的会话、无未提交编码时出现。它复用 Rust `context-reranker` 的会话内 n-gram，按“计数降序、文本升序”确定排序，去重后最多 3 条；关闭时原候选链不变。
- AI 总开关与云 AI 开关默认关闭；云 AI 还要求 `FULL` 安全模式、普通文本编辑器、活动会话、可用 Cloud Provider 和当前版本同意。
- AI 菜单提供“续写、精简、礼貌、正式、翻译”五个动作。只有用户点击动作才可能产生云请求，不逐键请求、不自动上屏或发送。
- 建议与普通候选、本地关联词分别显示为 `AI·云端`、`关联·本地`，云端建议最多 3 条。
- 新输入、移动光标导致原文不匹配、键盘隐藏、会话停止、编辑器切换、取消、新请求或旧 generation 会取消或废弃结果，迟到及乱序结果不能更新 UI 或编辑器。

## 数据与协议边界

客户端只允许发送仍由本输入法拥有且可再次核对的最近一次上屏文本，以及下列闭合字段：

```json
{
  "protocolVersion": "<approved-version>",
  "requestId": "<ephemeral-id>",
  "action": "continue|concise|polite|formal|translate",
  "text": "<last-owned-commit>",
  "language": "<language-tag>",
  "maxSuggestions": 3
}
```

`CloudAiProvider` 只接受配置注入的已批准 HTTPS 代理主机和路径，拒绝 HTTP、URL 凭证、查询/fragment、非标准端口、localhost 以及保留测试域。鉴权头由短期凭证拥有者注入，Provider 不保存永久模型 API Key；`HarmonyHttpAiTransport` 是可取消的 HarmonyOS HTTPS 适配边界，当前不接入默认正式运行时。`ShortLivedCloudAiHeaderProvider` 只接受最长 300 秒、当前同意版本的 JWT 形访问令牌，仅在内存缓存，剩余不足 15 秒刷新；撤回同意后迟到令牌也会被废弃。真实 `CloudAiTokenBroker` 仍由产品身份系统实现。

`services/ai-proxy/` 提供无第三方运行依赖的 Node.js 22 参考代理：先鉴权后读正文、请求 8 KiB 上限、Ed25519/EdDSA JWT 验签、每主体限流和 requestId 重放拒绝、严格 schema、6.5 秒以内上游超时、64 KiB 响应上限、服务端挂载凭证及脱敏桶日志。生产决策缺失时配置检查和启动都会失败；它未部署，也不是实际供应商联调通过证据。

响应必须同时满足：HTTP 200、声明和实际 UTF-8 字节数不超过 64 KiB、合法 JSON、协议版本一致、requestId 精确匹配、Provider 类型为云端、候选 ID 不重复、1～3 条文本候选、所有字符串和文本长度有界。任何服务端细节只映射为固定脱敏错误码。客户端硬超时为 8 秒，取消后销毁传输或忽略回调。

## 安全替换与撤销

接受建议前再次核对会话 generation、活动编辑器和光标前原文。`ImeConnectionService` 只在原文完全匹配时选中原文并以一次 `insertText` 替换；核对失败不会先删除。替换成功后复用现有 `UndoCommitManager`，反向撤销也要求当前文本匹配。

模型输出始终是不可信普通文本。`$cmd`、URL、协议字符串、HTML 或类似指令不会进入命令解析、Native 动作、网络转发或系统 API。

## 隐私与审计

- 不读取或上传完整编辑框、任意选区、剪贴板、联系人、应用包名、账号、用户词库、按键序列或长期输入历史。
- 日志只允许动作、阶段、Provider 类型、长度桶、耗时桶、候选数和固定错误码；不记录输入原文、建议正文、端点凭证、requestId 或逐键/逐事件行为轨迹。
- BASIC、UNKNOWN、密码、未知、数字、电话、Email、URL 和能力探测失败一律关闭云 AI。
- 云端不可用不影响普通输入和本地关联词；本地关联词不产生网络流量。
- 本阶段不实现真实语音、麦克风、端侧生成模型、逐键云请求、自动上屏、自动发送、远程埋点或长期 AI 历史。

## 主机验证结果（2026-08-24）

| 项目 | 真实结果 |
| --- | --- |
| ArkTS 全量测试 | `506/506 PASS`，其中 AI-1 专项 `19/19 PASS` |
| 自有代理协议测试 | Node.js `9/9 PASS` |
| 无生产配置启动门禁 | `AI_PROXY_CONFIG_CHECK=FAIL`，预期失败关闭 |
| 第三方宿主结果门禁 | schema 正向 PASS；全 `NOT_RUN` 示例被完成门禁正确拒绝 |
| Rust `context-reranker` | `9/9 PASS` |
| Rust `quanpin_context_reranking_v2` | `9/9 PASS` |
| AI-1 FFI 定向测试 | PASS |
| Rust fmt / workspace 严格 Clippy | PASS |
| Rust workspace 全量测试 | BLOCKED：当前工作区既有小鹤生成 bundle 与冻结候选快照不一致；未改写冻结基线 |
| Release 负向门禁 | `13/13 PASS` |
| default Release HAP 构建 | PASS |
| 实际 HAP 内容审计 | PASS |
| 参考代理 | `IMPLEMENTED / HOST_TESTED / NOT_DEPLOYED` |
| 真实生产代理与模型供应商 | `NOT_RUN / CLOUD_NOT_CONFIGURED` |
| Phone / Pad / 2in1 / 第三方宿主 | `NOT_RUN` |

最终 unsigned Release HAP：

- 路径：`entry/build/artifacts/entry-release-unsigned.hap`
- 大小：`71,008,252 bytes`
- SHA-256：`FF34FFB08E66CBDDC81BAF46D4B3AFFD2DA5EE6CD4D5D27B032C81CD35184921`

云接入阻塞及放行条件见 `AI1_CLOUD_PROXY_READINESS.md`，代理合同见 `AI1_PROXY_CONTRACT_DRAFT.md`，隐私文案见 `AI1_PRIVACY_AND_CONSENT_DRAFT.md`；设备和第三方宿主步骤见 `AI1_HOST_ACCEPTANCE.md`。
