# AI-1 生产代理合同草案

状态：`TECHNICAL_DRAFT_IMPLEMENTED / APPROVAL_MISSING / PRODUCTION_NOT_DEPLOYED`

本文把客户端、身份服务、自有代理和内部模型网关的责任固定为可评审合同。它不是生产域名批准、供应商合同、合规结论或真实联调记录；实际负责人必须完成文末签署项后才能启用 Release 云能力。

## 数据流和责任

1. 用户在受支持普通文本编辑器中主动点击五个 AI 动作之一。
2. 客户端集中门控再次确认 FULL、安全编辑器、活动会话、开关、当前同意版本、Provider 可用和最近一次自有上屏文本仍可核对。
3. 产品身份服务基于既有登录/设备证明签发最长 300 秒、作用域仅为 `ai:suggest` 的访问令牌。令牌只保存在内存，不写 Preferences、文件或日志。
4. 客户端向自有 `https://<待批准域名>/v1/ime/suggestions` 发送闭合请求。自有代理先验签再读正文，执行同意版本、限流、重放和 schema 校验。
5. 代理通过内部 HTTPS 模型网关调用获批供应链；供应商凭证只从服务端密钥系统挂载，绝不返回客户端。
6. 代理验证并截断边界后最多返回 3 条普通文本。客户端仍会重新验证 request/session/generation/原文，再允许安全替换和一次撤销。

任何层都不得把模型文本解释成命令、URL 跳转、HTML、协议或系统动作。

## 客户端请求合同

唯一业务路径为 `POST /v1/ime/suggestions`，Content-Type 为 `application/json`，请求体最多 8 KiB：

```json
{
  "protocolVersion": "ai-input-v1",
  "requestId": "ephemeral-request-id",
  "action": "continue|concise|polite|formal|translate",
  "text": "最近一次仍由输入法拥有的上屏文本",
  "language": "zh-CN",
  "maxSuggestions": 3
}
```

字段集合封闭，服务拒绝额外字段。禁止增加完整编辑框、任意选区、剪贴板、联系人、应用包名、账号、用户词库、按键序列、长期历史或稳定设备标识。客户端硬超时 8 秒；代理上游超时必须不超过 6.5 秒，不重试、不跟随重定向。

成功响应必须严格匹配仓库的 OpenAPI 草案：协议和 requestId 原样匹配、`providerType=cloud`、1～3 条 `{suggestionId,text,label,type:"text"}`，总响应不超过 64 KiB。失败只返回固定结构 `{"error":{"code":"<fixed_code>"}}`，不得透传供应商错误、提示词、正文或内部标识。

## 短期鉴权合同

访问令牌建议采用 Ed25519 签名 JWT，并同时满足：

- JOSE header：`alg=EdDSA`、`typ=at+jwt`、已登记 `kid`；代理挂载只含公钥的 JWKS。
- claims：精确 `iss`、包含精确 `aud`、`sub`、唯一 `jti`、`iat`、`nbf`、`exp`、`scope` 包含 `ai:suggest`、整数 `consentVersion`。
- `exp-iat <= 300` 秒；过期、尚未生效、错误同意版本、错误作用域/签发者/受众统一返回 `unauthorized`。
- 客户端只在内存复用令牌，并在剩余不足 15 秒时刷新；退出账号、撤回同意或能力关闭时清空。
- 身份服务必须另行定义签发资格、吊销、密钥轮换、设备/会话绑定和异常处置。仓库只提供 `CloudAiTokenBroker` 接口，不虚构现有身份系统。

## 限流、重放和日志

参考代理实现每主体每分钟固定窗口限流，并在短窗口拒绝相同 `(subject, requestId)`。生产配额数值、横向扩展共享存储、出口/IP 异常检测和申诉策略均须服务负责人批准；单实例内存计数器不是多副本生产限流结论。

允许日志字段仅为：动作、阶段、输入长度桶、耗时桶、候选数、固定错误码。禁止记录输入/建议正文、Authorization、requestId、subject、IP 与逐事件行为；基础设施访问日志也必须按相同原则脱敏或关闭 query/body/header 采集。

## 必须批准后才能启用的合同字段

| 项目 | 当前值 | 负责人/证据 |
| --- | --- | --- |
| 生产 HTTPS origin 与证书 | TBD | 域名/平台负责人 |
| 身份 issuer、audience、JWKS、签发/吊销 | TBD | 身份与安全负责人 |
| 最终协议版本与兼容期 | DRAFT `ai-input-v1` | 客户端/服务负责人 |
| 每主体及全局限流 | TBD | 服务/风控负责人 |
| 代理正文/内存/备份留存期限 | TBD | 隐私/服务负责人 |
| 模型网关和实际供应商 | TBD | AI 平台/采购负责人 |
| 供应商不训练、不二次使用、地域和删除条款 | TBD | 法务/隐私负责人 |
| 隐私文案版本 | DRAFT | 产品/法务/隐私负责人 |
| 威胁模型、渗透和应急响应 | NOT_RUN | 安全负责人 |
| 预生产及生产最小数据联调 | NOT_RUN | QA/服务/客户端负责人 |

参考实现位于 `services/ai-proxy/`，机器可读草案位于 `services/ai-proxy/openapi/ai-proxy.openapi.yaml`。
