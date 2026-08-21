# 阶段 11.6.2A 原创模拟码表生成

## 范围

`engine-rust/tools/code-table-fixture-generator` 是独立 Rust 离线工具，不属于 `ime-engine`、ArkTS、C++ 或生产拼音词库构建路径。它只生成内部 `code-table-fixture` 测试数据，不实现运行时查询、分类开关、分号状态机或自动/顶屏行为。

来源事实见 `dictionaries/LICENSES/CODE_TABLE_FIXTURE_ORIGIN.md`。生成器只组合仓库内直接编写的少量测试标签、固定编码样式和确定性序号；不访问网络、系统时间、随机数、目录扫描结果或 `production.lex`。

## 固定规模与顺序

| order | 分类 | 条数 | 默认启用 | 源 SHA-256 |
| ---: | --- | ---: | --- | --- |
| 10 | `core` | 8,000 | 是 | `857d56b8b5483c83f92a38bd450907fe2d9349eb6624eb8224632ec932fe495c` |
| 20 | `phrases` | 6,000 | 是 | `af6c44acd48dbb215e3e7ea1b02ccc2fd03696192dca2b52269f8618183c2039` |
| 30 | `extended` | 5,000 | 是 | `c90f5f5d89b7bc073ce47f71603b1c7de443c512ae57022aba4f60377fcad4de` |
| 40 | `domain` | 4,000 | 否 | `151014f985c9798d94da854dc50a3864e54a7ebb05bdc214dde1842ece5450b3` |
| 50 | `symbols` | 2,000 | 否 | `32cae2f3e2ec8f8ad273d3113e3b3e5cba0c33d73bde9d72bc3dd9fd040948c2` |
| — | `guide` | 2,000 | 隔离 | `dcaab337ec75577f45e59032fadd184906103cc5aee8edc65fe35ffd3861a311` |

分类顺序只来自 `code-table-fixture-manifest.json` 的 `order`，构建器不扫描目录补充分类。生成文件统一使用 UTF-8、无 BOM、LF 和固定末尾换行。

## 覆盖

大规模数据固定覆盖：1～6 字符编码，以 4 字符为主体；单候选、2 候选、5 以上、20 以上及超过一页的同码候选；跨分类同码、同词异码和同码同词；`a -> ab -> abc -> abcd -> abcde -> abcdef` 前缀链；单个汉字、两字/多字合成、ASCII、中文与 ASCII 混合、合法测试符号、UTF-8 多字节和 32 字符上边界。

小型人工可读 fixture 位于 `engine-rust/tests/fixtures/code-table/golden/`。负面用例位于相邻 `invalid/cases.tsv`，以转义字节保存非 UTF-8、NUL 和控制字符，避免危险字节混入普通文本资源。

## 命令与基线

```powershell
cargo run -p code-table-fixture-generator -- all <temporary-output-dir>
powershell -ExecutionPolicy Bypass -File scripts\verify-code-table-fixture.ps1
```

2026-07-15 两个独立目录的全部 14 个输出文件逐文件 SHA-256 相同。两次 bundle SHA-256 均为 `345887C1F6052514758A1D3F53B4F280E6FF04086AB1736582C9A8CCD42DF71C`，大小均为 2,024,260 bytes。最终门禁一次记录为生成 89 ms、bundle 构建 2,475 ms；第二次为生成 93 ms、bundle 构建 2,388 ms。峰值内存因当前工具链没有稳定跨平台测量方式而未记录，不伪造数值。

这些时间是本机 Debug 工具构建的基线，不是运行时性能结论。
