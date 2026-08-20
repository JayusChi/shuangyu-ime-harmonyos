# 小鹤音形安全审计

报告只含类型、位置和摘要哈希，不复制命中原文。

- 安全命中：51
- 原始凭据型命中：4
- 凭据所在 `ime.android.ini`：`REJECTED_AND_QUARANTINED`。
- `sanitized_configuration.json`：不复制任何原始键或值，不可执行、不可转换、不可进入 HAP。
- 网络/路径/平台命令均被隔离，不进入转换或 HAP。
- 当前安全结论：PASS：允许的转换输入范围内不存在凭据或危险动作

| 文件 | 行 | 类型 | 原因代码 | 摘要 |
| --- | ---: | --- | --- | --- |
| `小鹤音形/0.0.小鹤.txt` | 68509 | `url` | `REJECT_NETWORK_ACTION` | `1aa43a3bfc4de4d7` |
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
| `小鹤音形/ime.android.ini` | 52 | `windows_absolute_path` | `REJECT_UNSAFE_PATH_ACCESS` | `701d20001b8fa8b6` |
| `小鹤音形/ime.android.ini` | 215 | `ip_address` | `REJECT_NETWORK_ACTION` | `005a302611749771` |
| `小鹤音形/ime.android.ini` | 556 | `url` | `REJECT_NETWORK_ACTION` | `a86a1c3fff0cf9e8` |
| `小鹤音形/ime.android.ini` | 562 | `credential` | `REJECT_EMBEDDED_CREDENTIAL` | `a233b707f51ee94d` |
| `小鹤音形/ime.android.ini` | 570 | `url` | `REJECT_NETWORK_ACTION` | `1e593434dc6934a3` |
| `小鹤音形/ime.android.ini` | 578 | `credential` | `REJECT_EMBEDDED_CREDENTIAL` | `a233b707f51ee94d` |
| `小鹤音形/ime.android.ini` | 581 | `url` | `REJECT_NETWORK_ACTION` | `6bba6eb5c0969a08` |
| `小鹤音形/ime.android.ini` | 583 | `credential` | `REJECT_EMBEDDED_CREDENTIAL` | `ffa70dead834e3ab` |
| `小鹤音形/ime.android.ini` | 590 | `credential` | `REJECT_EMBEDDED_CREDENTIAL` | `d2d529a7e25fc61d` |
| `小鹤音形/ime.android.ini` | 599 | `url` | `REJECT_NETWORK_ACTION` | `37de2c3cb115ef64` |
| `小鹤音形/ime.android.ini` | 603 | `webdav` | `REJECT_NETWORK_ACTION` | `56973358f69ba1b7` |
| `小鹤音形/ime.android.ini` | 604 | `webdav` | `REJECT_NETWORK_ACTION` | `e1cd2af54f9f8c37` |
| `小鹤音形/ime.android.ini` | 605 | `webdav` | `REJECT_NETWORK_ACTION` | `f6f2d1e621282951` |
| `小鹤音形/ime.android.ini` | 608 | `url` | `REJECT_NETWORK_ACTION` | `0c4ba3b1f09cea9b` |
| `小鹤音形/ime.android.ini` | 610 | `email` | `REJECT_EMBEDDED_ACCOUNT` | `28f4a5c397e3261e` |
| `小鹤音形/ime.android.ini` | 612 | `credential` | `REJECT_EMBEDDED_CREDENTIAL` | `927be5ec8baec9f0` |
| `小鹤音形/ime.android.ini` | 638 | `webdav` | `REJECT_NETWORK_ACTION` | `4da71c7e0eac1ffd` |
| `小鹤音形/ime.android.ini` | 639 | `webdav` | `REJECT_NETWORK_ACTION` | `b652dc9ee93c3937` |
| `小鹤音形/ime.android.ini` | 641 | `webdav` | `REJECT_NETWORK_ACTION` | `6b1f32c147305fd1` |
| `小鹤音形/ime.android.ini` | 642 | `webdav` | `REJECT_NETWORK_ACTION` | `5afb19fd1f587946` |
| `小鹤音形/ime.android.ini` | 643 | `credential` | `REJECT_EMBEDDED_CREDENTIAL` | `0b44aa811a273917` |
| `小鹤音形/ime.android.ini` | 643 | `url` | `REJECT_NETWORK_ACTION` | `0b44aa811a273917` |
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
