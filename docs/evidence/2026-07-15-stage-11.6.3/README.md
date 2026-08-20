# 阶段 11.6.3 验收证据

日期：2026-07-15  
结论：**COMPLETED（项目原创 fixture 测试链路）**  
限制：阶段 11.6.2B 正式码表来源与授权仍为 `BLOCKED`；本记录不证明正式“小鹤音形”可发布。

## 实现边界

- Rust 新增 `code-table-runtime`：严格读取/验证 `HSPCTF01`，执行原始编码精确优先、前缀回退、分类/source_order、稳定去重、完整合并后限量与分页。
- `ime-engine` 在 Rust 内选择 `Shuangpin` 或 `CodeTable` 后端；码表路径不经过双拼解析、生产拼音词库、整句解码、ExistingRanking 或 user-model。
- EngineConfig JSON 新增可选 `codeTableBundlePath`；C ABI 函数、结果 JSON 和 interface/ABI version 2 不变。
- ArkTS/C++ 只转发配置和结果。Debug-only 页面调用真实 ArkTS -> C++ -> Rust 链路；正式设置和输入法仍只有 `xiaohe`。

## 主机验证

以下命令均通过：

```powershell
cd engine-rust
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace
cd ..
powershell -ExecutionPolicy Bypass -File scripts\verify-code-table-fixture.ps1
powershell -ExecutionPolicy Bypass -File scripts\build-native.ps1 -Abi all
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust -BuildMode debug
powershell -ExecutionPolicy Bypass -File scripts\build-hap.ps1 -SkipRust -BuildMode release
powershell -ExecutionPolicy Bypass -File scripts\verify-release-hap.ps1
powershell -ExecutionPolicy Bypass -File scripts\test-release-resource-gate.ps1
```

专项计数与产物：

- `code-table-runtime`: 33 passed；`ime-engine/tests/code_table_backend.rs`: 7 passed；`ime-ffi`: 18 passed。
- 原创 fixture：25,000 normal + 2,000 guide，2,024,260 bytes，SHA-256 `345887C1F6052514758A1D3F53B4F280E6FF04086AB1736582C9A8CCD42DF71C`；两个独立构建目录字节一致。
- x86_64 Native：24,970,728 bytes，SHA-256 `81D02C64060FD4C8C70AEDF724D0B1E162E1E8DF8529B4BA251EB61D05563942`。
- arm64-v8a Native：25,528,642 bytes，SHA-256 `B129BB83895A59AE1F23BA60ACBB91A35A0D359417CEBA01F822AECE23D51EA4`。
- 最终 Debug HAP：13,973,727 bytes，SHA-256 `3E84F740FEF017DCBB38FD199C3B9268AFB8607A30567952A7C14D0F4D81FB3C`。
- 最终 Release HAP：11,353,521 bytes，SHA-256 `4473AAC84D06E1E65934473A1838CBB59B358BD2B57E70E19B08B4FA4D45C8E4`。

## 模拟器验收

设备：`127.0.0.1:5555`，model `emulator`，`emulator 6.1.0.125(SP9DEVC00E120R4P11)`，ABI `x86_64`。

Debug HAP 安装成功后，从设置页 Debug 区进入“码表运行时验收”。页面自动安装原创 fixture 和生产拼音词库，并通过真实 Native 句柄执行：

| 用例 | 输入 | 结果 |
| --- | --- | --- |
| A 空输入 | reset | PASS，空 raw/候选 |
| B 精确优先 | `ab` | PASS，只返回 reading=`ab` |
| C 前缀回退 | `z` | PASS，分类与源行顺序稳定 |
| D 跨分类去重 | `a` | PASS，保留首分类项 |
| E 分页 | `zzzz -> nextPage` | PASS，进入 page 1 且仍有后页 |
| F 退格 | `abcd -> backspace` | PASS，raw=`abc` 并重新查询 |
| G 超长输入 | 65 × `a` | PASS，第 65 键返回 `code_too_long`，raw 保持 64 bytes |
| H xiaohe 回归 | switch -> `nihc` | PASS，首选“你好” |
| H xiaohe 整句 | `uurufa` | PASS，首选“输入法” |

页面总结果为 `PASS`。上半部分见 [acceptance_result.png](acceptance_result.png)，下半部分见 [acceptance_lower.png](acceptance_lower.png)；对应布局树为 [acceptance_result.json](acceptance_result.json) 和 [acceptance_lower.json](acceptance_lower.json)。

首次设备运行暴露了 Node-API 可选属性存在但值为 `undefined` 时被当作非法配置的问题。修复为可选字符串/整数同时接受缺失、`undefined` 和 `null` 后，重新构建、安装和执行，以上 A～H 全部通过。

## Release 资源门禁

- `RELEASE_HAP_VERIFY_RESULT=PASS`
- `RELEASE_RESOURCE_INPUT_VERIFY_RESULT=PASS`
- `RELEASE_RESOURCE_GATE_TEST_RESULT=PASS`
- Release HAP 保留 3,734,484-byte `production.lex`。
- Release HAP 不包含 `code-table-fixture-synthetic.bundle`，也不包含 fixture/test/synthetic/code-table rawfile。
- Debug fixture 只在 `build-hap.ps1 -BuildMode debug` 中临时生成/复制，`finally` 清理后源码资源目录无残留。
- `module.json5` 未增加 `ohos.permission.INTERNET`；正式设置存储与产品方案列表未加入 `code-table-fixture` 或“小鹤音形”。

## 未完成项

- 11.6.2B 正式来源、许可证和再分发权仍未解决。
- 11.6.4 用户码表规则、11.6.5 分类开关、11.6.6 分号引导、11.6.7 三码长提交状态机、11.6.8 产品接入、11.6.9 完整设备验收均未提前实现。
- ARM64 Native 可构建，但本阶段未在 ARM64 物理真机运行。
