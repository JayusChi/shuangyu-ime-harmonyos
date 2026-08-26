# AI-1 云代理接入放行清单

当前状态：`REFERENCE_PROXY_IMPLEMENTED / CLOUD_NOT_CONFIGURED / RELEASE_CLOUD_DISABLED`

仓库现已包含供应商无关的参考代理、严格协议、短期令牌验证边界、配置/部署模板、隐私同意草案和协议自动化测试。它们解决了可由代码仓库完成的工程准备，但不等于生产合同、法务批准、已部署服务或真实联网。下表中的缺失项是外部阻塞，不得以示例值、测试地址或开发凭证替代。

| 放行项 | 当前状态 | 必需证据 |
| --- | --- | --- |
| 自有生产 HTTPS 域名和固定代理路径 | MISSING | 域名所有权、证书和生产路由审批 |
| 客户端到代理的鉴权方式 | PARTIAL | EdDSA 最长 300 秒合同和客户端内存边界已实现；真实签发、刷新、吊销及设备绑定 MISSING |
| 生产协议版本 | DRAFT | 闭合 schema/OpenAPI/实现与测试已完成；双方审批、兼容与下线策略 MISSING |
| 限流与滥用防护 | PARTIAL | 单实例每主体限流、重放拒绝及固定错误已实现；生产数值、共享限流/WAF/风控 MISSING |
| 数据留存期限 | MISSING | 代理、日志、供应商各层明确期限和删除流程 |
| 不训练/不二次使用约定 | MISSING | 与实际模型供应链匹配的正式条款 |
| 隐私文案与当前同意版本 | DRAFT | 数据最小化、撤回与升级规则已有草案；主体/供应商/地域/期限及法务逐字批准 MISSING |
| 安全与合规评审 | MISSING | 威胁模型、渗透/供应链评审和负责人签字 |
| 真实服务联调与故障演练 | NOT_RUN | 超时、断网、限流、5xx、取消、乱序、超限响应证据 |

## 本轮已经完成的可控工作

- `services/ai-proxy/`：Node.js 22 无第三方依赖参考服务；生产配置缺失时启动失败，只有显式 HTTPS origin、身份、公钥、策略 ID、限流、模型网关和 TLS 配置齐全才可启动。
- `services/ai-proxy/openapi/ai-proxy.openapi.yaml`：无 server URL 的协议草案，不暗示实际域名。
- `ShortLivedCloudAiHeaderProvider`：`CloudAiTokenBroker` 注入边界、最长 300 秒、剩余 15 秒刷新、当前同意版本校验、仅内存缓存和显式清除；未接入默认运行时。
- `AI1_PROXY_CONTRACT_DRAFT.md` 与 `AI1_PRIVACY_AND_CONSENT_DRAFT.md`：供相关负责人填值和签署的草案。
- 代理协议自动化测试和第三方宿主验收结果 schema/门禁；测试 fixture 或 `NOT_RUN` 记录不能升级为真实 PASS。

## 当前强制状态

- 默认运行时注入 `UnavailableAiProvider`，能力探测报告云端不可用。
- AI 总开关、云端开关和同意版本均默认关闭或为 0。
- 正式 manifest 不声明 `ohos.permission.INTERNET`；Release 门禁继续拒绝 INTERNET、MICROPHONE、永久密钥、测试地址、测试证书、Fake/Debug Provider。参考代理代码不会被打入 HAP。
- `CloudAiProvider` 与传输适配器只作为安全边界和协议测试存在，不构成真实联网通过证据。

## 未来放行步骤

1. 由产品/服务/身份/安全/法务/隐私负责人填写并批准合同、策略和文案，冻结生产域名、路径及协议版本。
2. 身份团队实现 `CloudAiTokenBroker` 的真实签发/刷新/吊销/设备绑定；不得把模型供应商 Key 或长期代理凭证打入源码、资源或 HAP。
3. 部署自有代理和内部模型网关适配，完成供应链/日志/留存审计；将正式能力探测和 Provider 注入接到生产运行时，并保留集中能力门控。
4. 若产品确需 INTERNET 权限，将 Release 门禁升级为只允许已批准产品配置的精确正向校验，同时继续拒绝其他网络端点和所有禁项。
5. 在测试环境完成协议/失败演练，在生产批准环境完成最小数据实包联调，并对 HAP、日志和抓包重新审计。
6. 只有真实证据齐全后才提升同意版本并开放开关；不得把本阶段主机 Fake/协议测试记作云端 PASS。
