# 三端部署签名不一致修复

日期：2026-09-09。结果：Phone、Tablet、2in1 本地模拟器均完成 0.9.0 覆盖安装并成功启动。

## 原因与修改

`build-profile.json5` 原先将日常使用的 `default` 产品绑定到正式发布签名；Phone 既有安装使用开发签名，Tablet 初始检查还使用更早的开发证书。因此同一包名的后续部署触发 `9568332 / install sign info inconsistent`。

- 本机 `default` 和 `internalDebug` 固定使用同一开发签名，新增独立 `release` 产品使用正式发布签名。两个产品共用 `entry@default` 正式源码，各自输出到 `entry/build/default` 和 `entry/build/release`。
- 配置示例同步加入 `release` 产品；签名材料仍只存在于忽略的本机配置中。
- `build-hap.ps1` 默认正式构建选择 `release` 产品，允许 `-BuildMode release -Product default` 以开发签名验收正式代码。发布检查和电脑验收入口同步选择对应产品。
- 安装脚本在恢复当前输入法返回错误时，查询实际当前输入法；如果已经恢复，避免将成功安装误报为失败。
- 更新 README 的 HAP/APP 构建、签名隔离和旧证书处理说明。

## 实测结果

证据原件位于 `outputs/signature-fix-20260909/`。

| 验证 | 结果 | 日志 |
| --- | --- | --- |
| default/debug 开发包构建 | PASS | `build-development.log` |
| 脚本默认 release/release 构建 | PASS | `build-release.log` |
| 正式 HAP 资源检查 | PASS | `verify-release.log` |
| 正式 HAP 签名及摘要 | PASS；Profile type=release，包名 com.corrosion.shuangyuime，appIdentifier=6917611076350696172 | `verify-release-signature.log`、`release-profile.p7b` |
| 发布构建后再构建 default/debug | PASS | `rebuild-development-after-release.log` |
| 最终开发 HAP 签名 | PASS | `verify-development-signature.log` |
| Phone / 127.0.0.1:5555 | 覆盖安装 PASS，0.9.0，启动成功 | `install-three-devices.log`、`devices-after.json` |
| Tablet / 127.0.0.1:5557 | 覆盖安装 PASS，0.9.0，启动成功 | 同上 |
| 2in1 / 127.0.0.1:5559 | 覆盖安装 PASS，0.9.0，启动成功 | 同上 |
| 修改的 PowerShell 入口语法 | PASS | PowerShell AST 解析，无错误 |

三端最终证书指纹相同，均为 `C7115209BFC56FFFCF75CAD74146F1E2BECC881DEDEBB4D8BFA8FFC40C6528C4`。最终三端重复覆盖的 `SIGNATURE_RESET` 均为 `false`。用户授权过平板清除旧应用数据重装；实际平板安装脚本也返回 `SIGNATURE_RESET=false`，没有执行卸载分支，不能据此声称本次清除了平板数据。

验证范围是上述三个本地模拟器的构建、安装和启动，不包含物理设备或输入功能全量回归。未修改应用包名、版本号或输入法业务逻辑。
