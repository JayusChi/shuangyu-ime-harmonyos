# 原创码表测试 fixture

本目录仅包含项目自行编写的离线测试数据，不包含、转换或模仿任何第三方码表。

- `golden/` 是小型人工可读 fixture，用于分类顺序、分类内 `source_order`、前缀链、同码候选、跨分类重复和引导表隔离断言。
- `invalid/cases.tsv` 以转义形式记录负面输入与稳定错误码；非 UTF-8、NUL 和控制字符由测试按字节还原，不把危险字节放进普通文本资源。
- 25,000＋2,000 条大规模 fixture 由 `code-table-fixture-generator` 在临时目录确定性生成，不把巨型文本提交到仓库。

所有这些文件均禁止复制到 `entry/src/main/resources`，也禁止进入 Release HAP。

