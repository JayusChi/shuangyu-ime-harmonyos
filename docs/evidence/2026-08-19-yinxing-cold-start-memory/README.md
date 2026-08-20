# 小鹤音形冷启动与内存优化证据

状态：`IMPLEMENTED / HOST_RELEASE_VALIDATED / ARM64_BUILD_PASS / ARM64_DEVICE_NOT_RUN`

## 实现

- `.hsyx` 文件在 Windows 与 OHOS/Linux 走只读文件映射，解析阶段不再创建 26 MB 匿名堆副本；其他平台保留安全的 owned fallback。
- SHA-256 改为 64-byte 流式状态，bundle content hash 也按片段更新，不再为每次校验复制整包或拼出第二份 26 MB material。
- 严格生产文件先校验冻结的完整 SHA-256；命中后跳过已经由该冻结哈希覆盖的 trace JSON、逐 archive SHA 和重复全包 SHA。非冻结/损坏输入仍进入原详细校验器并保持结构化错误。
- 码表词典使用 compact load profile：继续校验 source/syllable 元数据，但不保留查询从不读取的逐条 `sources`、`syllables` 分配。
- 同一未变生产文件按 canonical path、长度和 mtime 共享一个 `Arc<CodeTableBundle>`；缓存只持 `Weak`，最后一个 engine handle 销毁后可释放。
- ArkTS 安装器首次完整 SHA 校验后写入绑定 SHA、inode、size、mtime、ctime 的原子回执；后续进程冷启动可用 stat + 回执复用。文件身份变化会使回执失效，Native 边界仍执行冻结完整 SHA。

## Windows x86_64 Release（5 个独立进程）

当前正式包为 26,039,550 bytes、74,644 entries。结果见 `performance-release.json`：

| 指标 | 历史冻结 P50/峰值 | 当前 P50/峰值 | 变化 |
| --- | ---: | ---: | ---: |
| 首次加载 | 633.962 ms P50 | 163.511 ms P50 | -74.2% |
| 同进程第二 handle | 636.181 ms P50 | 0.258 ms P50 | -99.96% |
| load 后工作集 | 63,090,688 B P50 | 20,426,752 B P50 | -67.6% |
| load 内存增量 | 59,203,584 B P50 | 15,593,472 B P50 | -73.7% |
| 峰值工作集 | 147,386,368 B | 46,473,216 B | -68.5% |

历史冻结基线来自 `dictionaries/audit/xiaohe-yinxing/baseline/performance_baseline.json`，其包为 25,397,952 bytes、73,263 entries；当前包更大，因此比较用于工程趋势，不替代同 bundle 的严格 A/B。

## 验证

- `cargo test -p code-table-runtime --lib`：6/6 PASS，含完整生产损坏矩阵与流式 SHA 标准向量。
- `cargo test -p code-table-runtime --test production_regression`：4/4 PASS，含共享索引 pointer identity。
- `cargo test -p ime-engine --test code_table_backend`：24/24 PASS。
- `cargo test -p ime-engine --test xiaohe_yinxing_production`：16/16 PASS。
- `cargo test --workspace`：全工作区与 doc-tests PASS。
- 严格 Clippy（code-table-runtime / ime-engine / ime-ffi，all targets）：PASS。
- ArkTS unit test build：PASS。
- `scripts/build-rust.ps1 -Abi arm64-v8a`：PASS，确认 mmap 路径可为 `aarch64-unknown-linux-ohos` 编译。

## ARM64 真机

本机仅连接三台 x86_64 emulator，物理 ARM64 数量为 0，因此真实冷启动时间与 RSS 为 `NOT_RUN`，不使用主机数据冒充真机结论。

已新增 `scripts/measure-yinxing-arm64.ps1`。它拒绝 emulator，按独立进程样本采集：回执/哈希模式、bundle preparation、Native engine initialization、从点击输入框到 ready 的时长，以及 ready/settled RSS。运行前需安装当前 IME 与 acceptance client，并把活动方案持久化为 `xiaohe-yinxing`。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\measure-yinxing-arm64.ps1 `
  -Target <physical-arm64-serial> `
  -Samples 5 `
  -EvidenceDir docs\evidence\<date>-yinxing-arm64-performance
```
