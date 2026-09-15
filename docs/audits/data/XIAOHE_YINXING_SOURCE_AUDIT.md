# 小鹤音形正式来源审计

- 阶段状态：**COMPLETED**
- 文件：27（3529678 bytes）
- Manifest SHA-256：`39386e1879db80921e80c2da42778485394ff0594bcf12efc2523fd668778e53`
- Conversion contract SHA-256：`0d2de22b8870114ee5b775f40a83192bcbfbb0766dafc18523603a8b779d9868`
- 不可读取文件：0
- 未识别角色：0
- 阻断原因：none
- 凭据原文件：整文件拒绝并隔离；脱敏派生物不含任何 INI 键值。
- 缺失引用：逐条接受、延期或拒绝，不合成客户数据。

## 文件判定

| 来源 | 角色 | 编码 | 换行 | 判定 |
| --- | --- | --- | --- | --- |
| `小鹤音形/0.0.小鹤.txt` | `core_code_table` | `UTF-8` | `LF` | `TRANSFORM` |
| `小鹤音形/0.2.拼字.txt` | `spelling_resource` | `UTF-8` | `LF` | `ACCEPTED` |
| `小鹤音形/1.0.分类.txt` | `category_table` | `UTF-8` | `LF` | `ACCEPTED` |
| `小鹤音形/1.2.快符-外接.txt` | `quick_symbol` | `UTF-8` | `LF` | `ACCEPTED` |
| `小鹤音形/2.1.一简次选.txt` | `one_key_secondary_table` | `UTF-8` | `LF` | `ACCEPTED` |
| `小鹤音形/2.2.二简次选.txt` | `two_key_secondary_table` | `UTF-8` | `LF` | `ACCEPTED` |
| `小鹤音形/2.3.直通-安卓.txt` | `direct_input` | `UTF-8` | `LF` | `REJECTED` |
| `小鹤音形/2.4.表外字.txt` | `out_of_table_character` | `UTF-8` | `LF` | `ACCEPTED` |
| `小鹤音形/2.5.全码词.txt` | `full_code_word` | `UTF-8` | `LF` | `ACCEPTED` |
| `小鹤音形/2.6.符号-安卓.txt` | `android_reference` | `Binary / Unknown` | `Binary / Not applicable` | `REJECTED` |
| `小鹤音形/2.6.符号.txt` | `symbol_table` | `UTF-8` | `LF` | `ACCEPTED` |
| `小鹤音形/2.7.符号组-安卓.txt` | `android_reference` | `UTF-8` | `LF` | `REJECTED` |
| `小鹤音形/2.7.符号组.txt` | `symbol_group` | `UTF-8` | `LF` | `ACCEPTED` |
| `小鹤音形/2.8.生僻字.txt` | `rare_character` | `UTF-8` | `LF` | `ACCEPTED` |
| `小鹤音形/2.9.全码字.txt` | `full_code_character` | `UTF-8` | `LF` | `ACCEPTED` |
| `小鹤音形/hans2hant.txt` | `simplified_traditional_resource` | `UTF-8` | `LF` | `DEFERRED` |
| `码表/导出 - 主码 - 全码词.txt` | `full_code_word` | `UTF-8 with BOM` | `CRLF` | `DEFERRED` |
| `码表/导出 - 主码 - 快符.txt` | `quick_symbol` | `UTF-8 with BOM` | `CRLF` | `DEFERRED` |
| `码表/导出 - 主码 - 拼字.txt` | `spelling_resource` | `UTF-8 with BOM` | `CRLF` | `DEFERRED` |
| `码表/导出 - 主码 - 次选字词.txt` | `secondary_candidate_table` | `UTF-8 with BOM` | `CRLF` | `DEFERRED` |
| `码表/导出 - 主码 - 用户.txt` | `user_mixed_rule` | `UTF-8 with BOM` | `CRLF` | `TRANSFORM` |
| `码表/导出 - 主码 - 直通.txt` | `direct_input` | `UTF-8 with BOM` | `CRLF` | `REJECTED` |
| `码表/导出 - 主码 - 表外字.txt` | `out_of_table_character` | `UTF-8 with BOM` | `CRLF` | `DEFERRED` |
| `码表/导出 - 主码 - 随心.txt` | `user_addition` | `UTF-8 with BOM` | `CRLF` | `TRANSFORM` |
| `码表/导出 - 主码 - Ｏ符.txt` | `symbol_table` | `UTF-8 with BOM` | `CRLF` | `DEFERRED` |
| `码表/导出 - 次显 - 「全码字」.txt` | `full_code_character` | `UTF-8 with BOM` | `CRLF` | `DEFERRED` |
| `码表/导出 - 辅码 - 「二简次选」.txt` | `two_key_secondary_table` | `UTF-8 with BOM` | `CRLF` | `DEFERRED` |
