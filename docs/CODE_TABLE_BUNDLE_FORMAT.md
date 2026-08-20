# `HSPCTF01` 测试分类码表 bundle 格式

## 作用域

`HSPCTF01` 1.0 是阶段 11.6.2A～11.6.3 的测试专用容器。它组合显式 manifest、五个 `HSPLEX01` 1.1 分类二进制和一个隔离的 guide 二进制。生产 `production.lex` 的 1.0/1.1 兼容性不变；该容器已接入内部 `code-table-fixture` Rust 运行时和 Debug-only 临时资源安装器，但不会进入 Release HAP，也不是正式码表分发格式承诺。

阶段 11.6.2C 在同一 `code-table-runtime` 加载边界新增正式容器 `HSPYXP01` 1.0。它保留 `HSPCTF01` 的全部 fixture 语义与测试，并用八个 `HSPLEX01` 1.1 分类表、用户规则、动作分流、追溯索引和统计报告承载正式数据。详细规范、冻结哈希和 Release 边界见 [XIAOHE_YINXING_PRODUCTION_BUNDLE_FORMAT.md](XIAOHE_YINXING_PRODUCTION_BUNDLE_FORMAT.md)。

## 布局

所有整数为 little-endian，固定头为 128 bytes：

| Offset | Type | Field |
| ---: | --- | --- |
| 0 | `[u8;8]` | magic `HSPCTF01` |
| 8 | `u32` | header length `128` |
| 12 | `u16` | major `1` |
| 14 | `u16` | minor `0` |
| 16 | `u32` | generator version |
| 20 | `u32` | manifest format version |
| 24 | `u32` | normal category count |
| 28 | `u32` | total table count（含 guide） |
| 32 | `u64` | embedded manifest byte length |
| 40 | `u64` | table-record payload byte length |
| 48 | `[u8;32]` | overall build-input SHA-256 |
| 80 | `[u8;32]` | all bytes after header SHA-256 |
| 112 | `[u8;16]` | reserved zero |

头后依次为原始 manifest 字节和按显式 category order 排列的 table records，guide 固定最后且通过 `isGuide=1` 隔离。每条 record 保存稳定 ID、guide 标志、默认开关、order、词条数、源 SHA-256、嵌套二进制长度、ID 字节和 `HSPLEX01` 1.1 字节。

整体输入 SHA-256 对“原始 manifest + 按分类 order 的源文件 + guide 源文件”逐项写入 `u64` 长度后计算，避免连接歧义。内容 SHA-256 覆盖 manifest 和全部 table records；最终 bundle SHA-256由外层构建/门禁记录。

`code-table-runtime` 加载时验证 magic、header/生成器/manifest 版本、保留位、所有长度、内容 SHA-256、manifest UTF-8/schema、manifest/header 一致性、分类 ID/order/数量和 guide 隔离、源 SHA-256，以及每个嵌套 `HSPLEX01` 的 CRC32、结构、边界、entry count 和连续零基 `source_order`。任何错误都返回稳定的结构化类别和脱敏原因；不会用部分损坏数据降级查询。
