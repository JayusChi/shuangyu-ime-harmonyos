# 小鹤音形精准匹配阶段 0 基线

本目录冻结切换到精准查询之前，正式 `xiaohe-yinxing` 渐进策略的真实行为。它与 `../baseline/` 的历史基线用途不同：历史目录记录 2026-07-27 渐进策略实施前的回退查询行为，本目录记录 2026-08-04 精准匹配实施前的当前渐进行为；两者均不得互相覆盖。

统一生成命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate-xiaohe-yinxing-precise-match-stage0.ps1
```

仅重建确定性文件并保留已有性能采样：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\generate-xiaohe-yinxing-precise-match-stage0.ps1 -SkipPerformance
```

生成器会分别运行当前渐进候选快照和当前小鹤双拼隔离快照两次，并逐字节比较。性能延迟与进程内存天然波动，不纳入字节确定性门禁。

文件说明：

- `formal_bundle_baseline.json`：bundle 大小、SHA-256、分类计数和权限集合。
- `formal_bundle_manifest_snapshot.json`：正式 manifest 的规范化完整快照。
- `progressive_behavior_baseline.json`：一至四码渐进路径、十个二码全局候选 ID、唯一/重码/无结果/第五码/空码切分、退格和 reset 快照。
- `four_code_user_rule_compatibility.json`：四码精确路径、用户规则和分类旧快照的不可变引用及哈希。
- `xiaohe_isolation_baseline.json`：当前小鹤双拼逐键、提交、分页、退格、reset、重建和方案切换隔离快照。
- `performance_baseline.json`：主机 Release 渐进查询延迟、当前页协议 JSON 大小、候选快照内存与峰值工作集。
- `baseline_index.json`：文件哈希和确定性状态索引。

CI 门禁：

```powershell
cargo test --manifest-path engine-rust\Cargo.toml -p ime-engine --test precise_match_stage0_baseline
cargo test --manifest-path engine-rust\Cargo.toml -p code-table-runtime --test stage0_baseline
```

精准匹配阶段 1 不得用新策略结果覆盖本目录；应新增独立期望并保留本目录作为对比和回滚证据。
