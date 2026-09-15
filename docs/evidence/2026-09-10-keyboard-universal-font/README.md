# 实体万能键与键盘字号直通验证

日期：2026-09-10。

- 实体反引号（KeyCode 2056）在小鹤音形中文模式进入万能键队列，兼容 Unicode=96 与 Unicode=0 的事件。快速字母后接万能键的集成回归确认编码为 `u\x60`（反引号），产生候选而不插入文字，按下、抬起均被消费。
- Shift 加反引号保留波浪号；非音形、英文、密码框和修饰组合键不触发万能键。
- `ojz` 顺序固定为 `1.[键字12号] 2.[+2] 3.[-1]`，动作不把标签上屏。字号默认 12、范围 8–32，连续增减串行累积；独立于键高与两套候选字号保存。功能键文字保持略小，键盘随保存值立即刷新。
- 设置版本 22，旧设置初始化为 12 号；覆盖复制、比较、序列化、迁移、偏好存储和进程间共享设置。保存失败时不发布新字号。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| ArkTS 单元测试 | 690 通过，0 失败，0 错误 |
| Rust 动作模型 | 5 通过 |
| Rust 正式码表回归 | 4 通过 |
| Rust 码表状态机（含万能键查询） | 96 通过 |
| Rust 正式引擎（含 ojz 候选顺序及动作） | 31 通过 |
| NativeEngineGateway 主机回归 | 21 个显示/反馈动作通过，非法参数被拒绝 |
| 原生 release 构建 | arm64-v8a、x86_64 均通过 |
| 签名 release HAP 构建、资源门禁 | 通过 |
| HAP 内容核对 | 两套原生库包含 ojz 和 settings.keyboard-font；ArkTS 包含字号与实体万能键路由 |

首轮旧默认字号断言失败，按新默认 12 号更新后全部通过。ArkTS 测试结果在构建 release 的 clean 操作前读取；clean 会清除 entry/.test，编译日志保留在 outputs/keyboard-fixes-arkts-tests.log。

未在客户真机执行实体键盘与视觉验收。

## 安装包

- `entry/build/release/outputs/default/entry-default-signed.hap`
- 93,125,350 字节
- SHA-256：`75CFF60A3195762A4B36A7594EA17AF7A6BCD20E714E4044277BD791E1D7565B`

## 日志与复现

日志：`outputs/keyboard-fixes-{import,arkts-tests,rust-actions,rust-regression,native-build,release-build,release-verify}.log`；打包核对：`outputs/keyboard-fixes-packaged-markers.txt`。

```powershell
& scripts/import-shuangyu-customer-lexicon.ps1 -UpdateProject
$env:DEVECO_SDK_HOME = 'C:/Program Files/Huawei/DevEco Studio/sdk'
& 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --no-daemon --mode module -p module=entry@default test
cargo test --manifest-path engine-rust/Cargo.toml -p code-table-runtime action::tests
cargo test --manifest-path engine-rust/Cargo.toml -p code-table-runtime -p ime-engine --test runtime --test production_regression --test xiaohe_yinxing_production
& 'C:/Program Files/Huawei/DevEco Studio/tools/node/node.exe' scripts/test-reverse-split-gateway.cjs
& scripts/build-native.ps1 -Abi all
& scripts/build-hap.ps1 -SkipRust -BuildMode release
& scripts/verify-release-hap.ps1 -HapPath entry/build/release/outputs/default/entry-default-signed.hap
```