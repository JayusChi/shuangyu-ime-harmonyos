# 小鹤音形改进阶段 0 基线

本目录冻结修改渐进查询语义之前的正式资源、候选、双拼隔离和主机性能证据。

统一生成命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate-xiaohe-yinxing-stage0-baseline.ps1
```

跳过非确定性的性能采样、只重新生成确定性证据：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate-xiaohe-yinxing-stage0-baseline.ps1 -SkipPerformance
```

生成器会对候选快照和双拼隔离快照各执行两次并逐字节比较；不一致时失败，且不会把失败结果当成新基线。更新这些快照必须显式执行上述命令并审查差异。

文件：

- `formal_bundle_baseline.json`：正式 bundle 身份、大小、格式、版本、分类、记录数与内容白名单。
- `formal_bundle_manifest_snapshot.json`：规范化 manifest 完整快照。
- `formal_bundle_sha256.txt`：正式 bundle SHA-256。
- `candidate_behavior_baseline.json`：十个指定二码及四码、无结果、用户规则、分类场景的旧行为。
- `xiaohe_isolation_baseline.json`：`你好/输入法/小鹤/双拼` 的真实小鹤双拼按键和会话行为。
- `performance_baseline.json`：机器可读主机 Release 性能数据。
- `PERFORMANCE_BASELINE.md`：性能口径、限制与 `NOT_RUN` 项。

CI 入口：

```powershell
cargo test --manifest-path engine-rust\Cargo.toml -p code-table-runtime --test stage0_baseline
```

该测试锁定正式资源身份和十个规定编码的完整候选字段与顺序。现有 `production_regression`、状态机、用户词库、方案切换、空码切分和四码提交测试继续共同承担专项门禁。

阶段 0 不允许修改正式来源、正式 bundle、通用 `query_exact_or_prefix` 语义、小鹤双拼行为或应用权限。
