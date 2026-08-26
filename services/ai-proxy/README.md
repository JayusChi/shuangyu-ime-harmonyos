# AI-1 自有云代理参考实现

这是不绑定模型供应商、无第三方运行依赖的安全边界实现，不是已部署的生产服务。仓库当前没有获批域名、身份签发系统、模型网关合同或法务批准文案，因此配置模板故意不能直接启动。

## 已实现边界

- 仅接收 `POST /v1/ime/suggestions`，请求体上限 8 KiB；先鉴权再读取正文。
- 只接受 Ed25519/EdDSA、`typ=at+jwt`、最长 300 秒且包含 `ai:suggest` 和当前 `consentVersion` 的访问令牌。
- 严格校验封闭 JSON schema、五个动作、协议版本、请求 ID、文本和候选边界。
- 每主体固定窗口限流和 `(subject, requestId)` 重放拒绝。
- 模型网关凭证每次从只读挂载文件读取；客户端永远不接触供应商凭证。
- 模型响应有 64 KiB 硬上限、6.5 秒以内服务端超时、无重试、无跳转；输出只作为文本返回。
- 日志只含动作、阶段、长度/耗时桶、候选数和固定错误码。

## 本机验证

要求 Node.js 22 或更高版本，无需 `npm install`：

```powershell
cd services/ai-proxy
npm test
npm run check-config # 无生产配置时应 FAIL，这是预期的失败关闭
```

## 生产接入顺序

1. 产品、安全、隐私和服务负责人批准 `docs/features/ai/AI1_PROXY_CONTRACT_DRAFT.md`、实际策略 ID、限流、域名和供应链条款。
2. 身份团队实现令牌签发与吊销，代理只挂载公钥 JWKS；客户端令牌必须短期、最小作用域、当前同意版本。
3. 服务团队实现并验证内部模型网关适配，使其只返回 `{suggestions:[{text,label}]}`；供应商永久密钥只能存在服务端密钥系统。
4. 复制 `deploy/production.env.template` 到密钥/配置平台并替换全部占位符；固定基础镜像和业务镜像 digest。
5. 在预生产完成抓包、超时、断网、限流、上游异常、取消和日志审计；再由变更流程决定生产发布。

容器构建故意要求调用方提供已批准且固定版本/摘要的 Node 22 基础镜像：

```powershell
docker build --build-arg NODE_BASE_IMAGE=REPLACE_APPROVED_NODE22_IMAGE -t REPLACE_IMAGE .
```

不得把测试地址、示例身份、永久 Key 或本仓库的协议测试结果当成生产联调证据。
