# 阶段 11.6.4 验收证据

日期：2026-07-15  
结论：**PASS（项目原创 fixture 的用户码表规则接入）**

该结论只覆盖内部 `code-table-fixture`。正式方案仍只有 `xiaohe`；11.6.2B 正式来源与授权保持 `BLOCKED`，11.6.5～11.6.9 未完成。

## 实现边界

- Rust 在完整系统候选之后应用 `#删`、普通新增、`#固/#N`、后规则覆盖和稳定去重，再限量/分页。
- 删除匹配候选完整编码＋词条，精确候选删空后不二次回退系统前缀。
- 用户文件创建时只解析一次，运行时共享不可变快照；系统 bundle 只读。
- ArkTS 只提供 Debug 验收文件和显示真实结果；C++ 未改；interface/ABI version 仍为 2。
- 未实现分类开关、分号引导、三码长提交、正式设置入口或正式码表资源。

## 主机命令与结果

```powershell
cd engine-rust
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace
cd ..

$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test

powershell -ExecutionPolicy Bypass -File scripts\verify-lexicon-order.ps1
powershell -ExecutionPolicy Bypass -File scripts\verify-code-table-fixture.ps1
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust -BuildMode debug
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust -BuildMode release
powershell -ExecutionPolicy Bypass -File scripts\verify-release-hap.ps1
powershell -ExecutionPolicy Bypass -File scripts\test-release-resource-gate.ps1
```

结果：Rust fmt PASS；clippy `-D warnings` PASS；workspace PASS；ArkTS `BUILD SUCCESSFUL`；词库顺序、原创 fixture、双 ABI、Debug/Release HAP、Release HAP 检查和资源正负门禁均 PASS。`verify-stage8.ps1`/后续串联命令曾因外层 120 秒限制在重复 HAP 构建期间超时，因此不将该整条串联脚本记为 PASS；超时前显示的 Stage 8/9 回归、Rust、ArkTS 与双 ABI 子项均通过，最终结论只引用上方独立完成的门禁。

最终再次执行的 Rust workspace 共 43 个测试结果段、272 PASS/0 FAIL；专项计数为 `user-lexicon` 17、`code-table-runtime` 41、`ime-engine` 码表集成 13、`ime-ffi` 19。ArkTS 为 176 PASS/0 FAIL/0 ERROR。

原创 fixture：14 个输出逐文件确定性一致；bundle 2,024,260 bytes，SHA-256 `345887C1F6052514758A1D3F53B4F280E6FF04086AB1736582C9A8CCD42DF71C`。

## 产物

| 产物 | 大小 | SHA-256 |
| --- | ---: | --- |
| `engine-rust/target/ohos/x86_64/libime_ffi.a` | 25,149,332 | `8DDB310157246FFD1FDC5303EA21302CCCD297C8AF694F7B955029121A0D693E` |
| `engine-rust/target/ohos/arm64-v8a/libime_ffi.a` | 25,697,670 | `21B49BA538588C3422E3B83EF7A7902B15E97BB3579459A6E13DBAA77D3C94AA` |
| `entry/build/artifacts/entry-debug-unsigned.hap` | 14,275,678 | `1F4CA1189CDA66B71E7AD0D215CF800986E91FA09D8A9A3A46C88BAD9AE2305F` |
| `entry/build/artifacts/entry-release-unsigned.hap` | 11,487,053 | `96EF0230183B84D6495E4561B192378E6EAA79945CA669A850B193D99580C533` |

Release `module.json` 为 `buildMode=release/debug=false`；rawfile 仍只包含 3,734,484-byte `production.lex`，没有 fixture/test/synthetic/code-table 或 Debug 用户文件。HAP 未配置正式签名。

## 设备结论

x86_64 HarmonyOS 6.1 模拟器 A～J 全部 PASS。首次启动 H 为 `reusedExisting=false`；执行 `aa force-stop com.example.harmonyos_input` 并重新启动 `EntryAbility` 后，第二次为 `reusedExisting=true`，总结果仍 PASS。详见 [device/README.md](device/README.md)。

ARM64 静态库已构建；ARM64 物理真机、正式签名、真实设备系统栏/震感/扬声器等不属于本阶段完成证据。
