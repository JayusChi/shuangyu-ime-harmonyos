# Security and negative gate results

结果：PASS。

- fixture、原始来源、trace、build report、未知资源均被 Release 门禁拒绝。
- 正式 bundle 大小不变但内容被篡改时被哈希门禁拒绝。
- INTERNET 权限负例被拒绝。
- signed/unsigned HAP 实包扫描均只包含批准 rawfile。
- signed HAP 签名结构验证通过。

通用门禁曾有一处测试夹具过期：正向控制只复制 `production.lex`，未复制当前已批准的
正式 bundle，导致正向控制被现行白名单正确拒绝。修复仅补齐正向控制资源，并清除预期
负例遗留的子进程退出码；产品 Release 门禁逻辑未放宽。
