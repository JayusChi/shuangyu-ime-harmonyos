# 26 键小鹤音形热切换修复验收

日期：2026-08-25

## 结论

- 根因：`EngineCoordinator` 原先把初始化配置里的 `codeTableBundlePath` 当作当前原生句柄已经加载音形码表的依据。拼音句柄虽然携带这个配置值，Rust 实际不会加载码表，因此直接切换方案会被原生层拒绝并回滚，界面显示“键盘方案切换失败”。
- 修复：单独跟踪当前原生句柄实际持有的码表路径；从拼音切到小鹤音形时，如果句柄未持有目标码表，事务式创建已加载正式码表的新句柄，再替换旧句柄。
- 回归测试：ArkTS 全量单测 512/512 通过，新增“拼音句柄仅携带相同 bundle 路径仍必须重建”的专项用例。
- 构建：default Release HAP 构建通过，`verify-release-hap.ps1` 门禁 PASS。

## 安装包

- 文件：`entry/build/default/outputs/default/entry-default-signed.hap`
- 大小：71,193,633 bytes
- SHA-256：`0A25CC4116EA4719C14FDAF4AFAFF6ED7EDA75A32064749E9BFA213E8D5B01FE`
- 应用元数据：`0.5.0 / 5000000`、`releaseType=Release`、`debug=false`

## 三设备复验

| 设备 | 场景 | 结果 | 证据 |
|---|---|---|---|
| Phone `127.0.0.1:5555` | 输入法面板从 18 键双拼切到 26 键小鹤音形 | PASS；面板立即变为 26 键小鹤音形，日志记录 `engine recreated with production code table bundle`，无失败回滚 | `phone/picker.jpeg`、`phone/after.jpeg`、`phone/after.json` |
| Pad `127.0.0.1:5557` | 独立验收应用内从 18 键双拼切到 26 键小鹤音形 | PASS；面板立即更新，日志确认生产码表引擎重建并应用跨进程设置，无失败回滚 | `pad/panel.jpeg`、`pad/after.jpeg`、`pad/after.json` |
| 2in1 `127.0.0.1:5559` | 实体键盘模式从拼音切到 26 键小鹤音形 | PASS；设置选中音形，原生引擎以正式码表初始化，跨进程设置应用成功，无失败回滚 | `2in1/after.jpeg`、`2in1/after.json` |

三台设备安装包元数据均复核为 `0.5.0 / 5000000`，失败日志扫描均为 0 条。
