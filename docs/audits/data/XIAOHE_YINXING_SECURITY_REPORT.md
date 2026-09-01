# 小鹤音形安全审计

报告只含类型、位置和摘要哈希，不复制命中原文。

- 安全命中：29
- 原始凭据型命中：0
- 凭据所在 `ime.android.ini`：`REJECTED_AND_QUARANTINED`。
- `sanitized_configuration.json`：不复制任何原始键或值，不可执行、不可转换、不可进入 HAP。
- 网络/路径/平台命令均被隔离，不进入转换或 HAP。
- 当前安全结论：PASS：允许的转换输入范围内不存在凭据或危险动作

| 文件 | 行 | 类型 | 原因代码 | 摘要 |
| --- | ---: | --- | --- | --- |
| `小鹤音形/0.0.小鹤.txt` | 68571 | `url` | `REJECT_NETWORK_ACTION` | `1aa43a3bfc4de4d7` |
| `小鹤音形/2.3.直通-安卓.txt` | 25 | `url` | `REJECT_NETWORK_ACTION` | `5fd51d98c52d6a4e` |
| `小鹤音形/2.3.直通-安卓.txt` | 26 | `url` | `REJECT_NETWORK_ACTION` | `1aa43a3bfc4de4d7` |
| `小鹤音形/2.3.直通-安卓.txt` | 27 | `url` | `REJECT_NETWORK_ACTION` | `5536cf367e878ea0` |
| `小鹤音形/2.3.直通-安卓.txt` | 28 | `url` | `REJECT_NETWORK_ACTION` | `febd481fe2de0c92` |
| `小鹤音形/2.3.直通-安卓.txt` | 29 | `url` | `REJECT_NETWORK_ACTION` | `f1334ea4a324873d` |
| `小鹤音形/2.3.直通-安卓.txt` | 118 | `url` | `REJECT_NETWORK_ACTION` | `77e211ab7869ad62` |
| `小鹤音形/2.3.直通-安卓.txt` | 119 | `url` | `REJECT_NETWORK_ACTION` | `cb314cb7789abbef` |
| `小鹤音形/2.3.直通-安卓.txt` | 120 | `url` | `REJECT_NETWORK_ACTION` | `9d26ae50247136f0` |
| `小鹤音形/2.3.直通-安卓.txt` | 309 | `url` | `REJECT_NETWORK_ACTION` | `56edb482b7614559` |
| `小鹤音形/2.3.直通-安卓.txt` | 310 | `url` | `REJECT_NETWORK_ACTION` | `ebd2f90b2d74b3b0` |
| `小鹤音形/2.3.直通-安卓.txt` | 311 | `url` | `REJECT_NETWORK_ACTION` | `5e326ed781f95aa5` |
| `小鹤音形/2.3.直通-安卓.txt` | 315 | `android_storage_path` | `REJECT_UNSAFE_PATH_ACCESS` | `522badb7373baabb` |
| `小鹤音形/2.3.直通-安卓.txt` | 316 | `android_storage_path` | `REJECT_UNSAFE_PATH_ACCESS` | `5ba17c3dd479ced1` |
| `码表/导出 - 主码 - 直通.txt` | 10 | `url` | `REJECT_NETWORK_ACTION` | `d178511df1440c81` |
| `码表/导出 - 主码 - 直通.txt` | 11 | `external_process` | `REJECT_EXTERNAL_PROCESS` | `b4fa81d223480561` |
| `码表/导出 - 主码 - 直通.txt` | 13 | `external_process` | `REJECT_EXTERNAL_PROCESS` | `493e8d3cf19730f3` |
| `码表/导出 - 主码 - 直通.txt` | 14 | `external_process` | `REJECT_EXTERNAL_PROCESS` | `151801a559ea6044` |
| `码表/导出 - 主码 - 直通.txt` | 15 | `external_process` | `REJECT_EXTERNAL_PROCESS` | `35379f0bca585960` |
| `码表/导出 - 主码 - 直通.txt` | 16 | `external_process` | `REJECT_EXTERNAL_PROCESS` | `2de849702db32f25` |
| `码表/导出 - 主码 - 直通.txt` | 17 | `external_process` | `REJECT_EXTERNAL_PROCESS` | `05f2834f3646a327` |
| `码表/导出 - 主码 - 直通.txt` | 18 | `external_process` | `REJECT_EXTERNAL_PROCESS` | `28d0c69ac2f3d9ee` |
| `码表/导出 - 主码 - 直通.txt` | 44 | `url` | `REJECT_NETWORK_ACTION` | `d2d763ca6096c55f` |
| `码表/导出 - 主码 - 直通.txt` | 45 | `url` | `REJECT_NETWORK_ACTION` | `721629debb714b2f` |
| `码表/导出 - 主码 - 直通.txt` | 46 | `url` | `REJECT_NETWORK_ACTION` | `c8e0958af5938bdb` |
| `码表/导出 - 主码 - 直通.txt` | 52 | `url` | `REJECT_NETWORK_ACTION` | `6d12dc9a2d9b3aeb` |
| `码表/导出 - 主码 - 直通.txt` | 62 | `url` | `REJECT_NETWORK_ACTION` | `266f2f3689ca1eaa` |
| `码表/导出 - 主码 - 直通.txt` | 63 | `url` | `REJECT_NETWORK_ACTION` | `96130514b14a058d` |
| `码表/导出 - 主码 - 直通.txt` | 64 | `url` | `REJECT_NETWORK_ACTION` | `df92992713cde342` |
