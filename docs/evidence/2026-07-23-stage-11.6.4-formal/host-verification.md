# Host verification

实际执行并通过：

```text
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test -p user-lexicon
cargo test -p code-table-runtime
cargo test -p ime-engine
cargo test -p ime-ffi
cargo test -p yinxing-converter
cargo test --workspace
powershell -File scripts\build-native.ps1 -Abi all
powershell -File scripts\build-hap.ps1 -SkipRust -BuildMode debug
powershell -File scripts\device-accept-xiaohe-yinxing-stage11_6_4.ps1
powershell -File scripts\build-hap.ps1 -SkipRust -BuildMode release
powershell -File scripts\verify-release-hap.ps1
powershell -File scripts\test-release-resource-gate.ps1
powershell -File scripts\test-xiaohe-yinxing-stage11_6_3-release-gate.ps1
powershell -File scripts\verify-code-table-fixture.ps1
powershell -File scripts\audit-xiaohe-yinxing.ps1
hvigorw --no-daemon --mode module -p module=entry@default test
powershell -File scripts\verify-lexicon-rules-phase2.ps1 -SkipNative -SkipArkTS -SkipHap
```

关键结果：

- Rust workspace：PASS，0 failed。
- 旧通用用户规则门禁：`LEXICON_RULES_PHASE2_VERIFY_RESULT=PASS`；`production.lex` 3,734,484 bytes/SHA-256 `765E2B0BD90244192A4C1BB6B2EC501ED28E0DBD731CBAB4C326534F091ECA10` 前后不变。
- ArkTS：288 run / 288 pass / 0 failure / 0 error / 0 ignore。
- Native、Debug/Release HAP、Release 正负资源门禁、fixture 确定性、正式来源不可变审计：PASS。
- 模拟器：两轮 A～J PASS。

已知历史门禁问题：`scripts/verify-stage11.ps1 -SkipNative -SkipHap` 在 required-files 步骤失败，因为它要求构建后本应被清理的 `entry/src/main/ets/pages/DebugStage10.ets` 永久存在。ArkTS 测试已使用该脚本内部相同的 hvigor 命令独立执行并解析机器报告。
