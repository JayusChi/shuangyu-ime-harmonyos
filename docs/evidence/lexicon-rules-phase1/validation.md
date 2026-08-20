# 词库规则增强第一阶段验证证据

验证日期：2026-07-14

## Fixture

`dictionaries/source/test-fixtures/flypy_order_table.txt` 是项目原创自动化
测试数据，不属于正式词库，不包含官方小鹤码表，也不会打入 HAP：

```text
第一词<TAB>abz
第二词<TAB>aba
第三词<TAB>abz
第四词<TAB>abc
第五词<TAB>abd
第六词<TAB>abe
```

## 确定性构建

执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-lexicon-order.ps1
```

脚本在两个独立临时目录中分别执行同一构建命令：

```powershell
cargo run --quiet --manifest-path engine-rust\Cargo.toml -p lexicon-builder -- `
  --input dictionaries\source\test-fixtures\flypy_order_table.txt `
  --input-format flypy-table `
  --output <independent-temp-dir>\order.lex `
  --lexicon-version 1 --strict --verify
```

结果：

| 项目 | 第一次 | 第二次 |
| --- | --- | --- |
| 格式 | `HSPLEX01` 1.1 | `HSPLEX01` 1.1 |
| 大小 | 496 bytes | 496 bytes |
| CRC32 payload | `bcacde46` | `bcacde46` |
| SHA-256 | `13610B57B8A1BEB1EE12643552DC5873EE17F8BC9DCB66997D824D37F527B50C` | `13610B57B8A1BEB1EE12643552DC5873EE17F8BC9DCB66997D824D37F527B50C` |
| 原始字节 | 相同 | 相同 |

改变输入行顺序后，二进制字节与前缀查询顺序均相应改变；CLI 集成测试
`cli_flypy_table_build_preserves_order_and_is_byte_deterministic` 覆盖该断言。

## 查询结果

`candidate-query` 通过 `ExactOrPrefix + SourceOrder` 加载实际 1.1 二进制：

| 输入 | 类型 | 结果 |
| --- | --- | --- |
| `abz` | Exact | `第一词, 第三词` |
| `ab` | Prefix fallback | `第一词, 第二词, 第三词, 第四词, 第五词, 第六词` |
| 空字符串 | Empty | 0 项，不枚举全表 |

分页测试使用 page size 2，得到 `[第一词,第二词]`、`[第三词,第四词]`、
`[第五词,第六词]`；页间无重复、无遗漏，重复查询与缓存命中顺序一致。

## 实际执行与结果

| 命令 | 结果 |
| --- | --- |
| `cargo test -p lexicon-core -p candidate-ranking -p candidate-query -p lexicon-builder` | PASS；57 项目标模块测试 |
| `cargo clippy -p lexicon-core -p candidate-ranking -p candidate-query -p lexicon-builder --all-targets -- -D warnings` | PASS |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-lexicon-order.ps1` | PASS；两次大小、字节、SHA-256、加载与查询一致 |
| `cargo fmt --check` | PASS |
| `cargo clippy --workspace --all-targets -- -D warnings` | PASS |
| `cargo test --workspace` | PASS；176 项 Rust 测试 |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-rust.ps1` | PASS；fmt、clippy、176 项测试 |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-stage11_5.ps1` | PASS；生产词库、Rust、Native 双 ABI、ArkTS、Release HAP 与包内容门禁 |

阶段 11.5 重建仍生成原生产产物：65,122 entries，3,734,484 bytes，
`HSPLEX01` 1.0，SHA-256
`765E2B0BD90244192A4C1BB6B2EC501ED28E0DBD731CBAB4C326534F091ECA10`。
生产 corpus 5,171/5,171 通过，其中固定覆盖明确包含 `ni -> 你`、
`nihc -> 你好`、`uurufa -> 输入法`。用户学习、整句解码、部分提交、
剩余编码继续转换、分页、FFI 和用户模型测试均在 workspace 门禁中通过。

构建产物：

| 产物 | 大小 | SHA-256 |
| --- | --- | --- |
| x86_64 Native | 23,963,162 bytes | `FDA6AC6E3D7A4C9D75404E08E10DB0E71028F901C148F349B78F98B4DCE2B0C0` |
| arm64-v8a Native | 24,543,694 bytes | `95E892A5A188AE8384B64CC985B8D4FC565B57B717E5C66CF998346D030996A2` |
| Release HAP | 10,670,706 bytes | `ABB8C2434C6FCA43724143A2A8324226CEE0FF545ED2166F6C21792F627EA035` |

阶段 11.5 原始门禁 transcript：
`docs/evidence/stage11_5/verify-stage11_5.log`。

## 未执行

- 未运行模拟器/设备验收：本轮未修改 ArkTS、C++、C ABI、Node-API、
  生产资源或默认生产查询/排序路径；本地 ArkTS、Native、HAP 和包内容
  门禁已通过。
- 未运行 ARM64 物理真机：当前无物理设备；只声明 arm64-v8a 编译通过。
- 未执行阶段 10/11 设备回归：同上，本轮没有 UI、设置或生产默认行为改动。

## 仓库状态限制

执行修改前检查时，工作区 `.git` 是空目录，`git status --short` 返回
`fatal: not a git repository`。因此无法可靠列出或区分修改前的未提交用户
改动；实施过程中未使用 reset、checkout 或删除未跟踪文件等回退操作。
