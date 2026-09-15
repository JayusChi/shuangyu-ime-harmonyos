# 候选显示、键高和反馈直通验证

日期：2026-09-09。功能及用户操作见 [直通说明](../../features/direct-control/DISPLAY_FEEDBACK_COMMANDS.md)。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| ArkTS 单元测试 | 672 通过，0 失败、0 错误 |
| Rust 正式动作表测试 `code-table-runtime action::tests` | 5 通过 |
| Rust 正式码表回归 `production_regression` | 4 通过 |
| Rust 码表状态机 `runtime` | 96 通过 |
| Rust 正式引擎 `xiaohe_yinxing_production` | 29 通过 |
| NativeEngineGateway 主机测试 | 17 个新动作均通过；未允许的参数被拒绝 |
| 原生 release 构建 | arm64-v8a、x86_64 均成功 |
| HAP release 编译和资源校验 | 通过，debug=false |
| 已打包原生库检查 | 两种架构均包含全部 7 类新动作 |

新回归覆盖候选顺序、选择动作不上屏标签、双拼 `ofa` 返回音形、单候选分页、回删恢复普通双拼候选、连续键高增减、字号独立保存、上下限、旧设置迁移、无效参数、保存失败回滚，以及按键音量传入播放接口。

初轮测试发现的两处旧断言（键高仍只有 5 档、正式直通仍只有 33 项）已更新为 9 档与 50 项，并通过相关回归。未执行客户真机的备忘录、视觉位置或实际声音/震感验收。

## 产物

- 已签名 HAP：`entry/build/default/outputs/default/entry-default-signed.hap`
- 字节数：92,926,818
- SHA-256：`312ee75992fbcc63ca99ce323e3472cf7a21888545f6c74d1b48769b7a213b02`
- ArkTS 报告：`entry/.test/default/intermediates/test/coverage_data/test_result.txt`
- 原始日志：`outputs/direct-settings-arkts-tests.log`、`outputs/direct-settings-action-tests.log`、`outputs/direct-settings-runtime-regression.log`、`outputs/direct-settings-engine-tests.log`、`outputs/direct-settings-release-build.log`、`outputs/direct-settings-release-verify.log`

## 复现命令

```powershell
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test
cargo test --manifest-path engine-rust/Cargo.toml -p code-table-runtime action::tests
cargo test --manifest-path engine-rust/Cargo.toml -p code-table-runtime --test runtime --test production_regression
cargo test --manifest-path engine-rust/Cargo.toml -p ime-engine --test xiaohe_yinxing_production
& 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' scripts/test-reverse-split-gateway.cjs
& scripts/build-native.ps1 -Abi all
& scripts/build-hap.ps1 -SkipRust -BuildMode release
& scripts/verify-release-hap.ps1 -HapPath entry/build/default/outputs/default/entry-default-signed.hap
```
