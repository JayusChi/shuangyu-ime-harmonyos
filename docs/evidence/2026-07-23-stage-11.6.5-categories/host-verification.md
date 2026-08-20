# Host verification

| 命令 | exit code | 结果 |
| --- | ---: | --- |
| `cargo fmt --all --check` | 0 | PASS |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` | 0 | PASS |
| `cargo test --workspace` | 0 | 348/348 PASS |
| `cargo test -p ime-ffi --lib` | 0 | 23/23 PASS |
| `hvigorw --no-daemon --mode module -p module=entry@default test` | 0 | Tests run 290 / Failure 0 / Error 0 / Pass 290 / Ignore 0 |
| `scripts/build-native.ps1 -Abi all` | 0 | x86_64、arm64-v8a PASS |
| `scripts/build-hap.ps1 -SkipRust -BuildMode debug` | 0 | PASS |
| `scripts/build-hap.ps1 -SkipRust -BuildMode release` | 0 | PASS |
| `scripts/verify-release-hap.ps1` | 0 | PASS |
| `scripts/test-release-resource-gate.ps1` | 0 | PASS |
| `scripts/test-xiaohe-yinxing-stage11_6_3-release-gate.ps1` | 0 | formal/fixture/raw/trace/report/INTERNET 六类负向 PASS |
| `scripts/audit-xiaohe-yinxing.ps1` | 0 | 28/28 不可变 |
| PowerShell Parser 解析 `scripts/*.ps1` | 0 | 40/40 PASS |
| `scripts/device-accept-xiaohe-yinxing-stage11_6_5.ps1 -Target 127.0.0.1:5555 -SkipInstall` | 0 | 两轮 A～L PASS |

Release HAP 内容门禁输出：

```text
RELEASE_HAP_VERIFY_RESULT=PASS
HAP_SIZE=12046372
HAP_SHA256=59BA888F90CFF91A49ADA30D76ED02A83A39B5B6646DA35D9319ECA0731AC809
RELEASE_RESOURCE_INPUT_VERIFY_RESULT=PASS
RELEASE_RESOURCE_GATE_TEST_RESULT=PASS
STAGE11_6_3_RELEASE_NEGATIVE_RESULT=PASS
```

正式审计输出：

```text
AUDIT_FILE_COUNT=28
AUDIT_MANIFEST_SHA256=ef93b39e05a0e11c818f8dd837b3f5b2e87777ab02aaba374765a846be7dce55
AUDIT_CONTRACT_SHA256=2353a4b41bd9b1e9aeb1e309cb6ae657078de0d133f624921086f68d82ad8692
SOURCE_IMMUTABILITY_CHECK=PASS
```
