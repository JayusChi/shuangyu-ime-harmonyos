# 小鹤音形精准匹配阶段 6：精准匹配提示证据

日期：2026-08-05  
结论：`PASS（主机自动化、signed Release、x86_64 Phone/Pad 模拟器范围）`

## 验收对象

- signed Release HAP：`37,942,313` bytes
- SHA-256：`2f038338305c857e9c2ddfc3b6319b41b3db91967c7ad7644256c5583d352f4b`
- Phone：HarmonyOS x86_64，`1320×2856` 竖屏，目标 `127.0.0.1:5555`
- Pad：HarmonyOS x86_64，`2880×1920` 横屏，目标 `127.0.0.1:5557`
- 独立第三方编辑器：`com.example.shuangyuime.acceptance`

两个模拟器均重新安装本轮 signed Release，启用并切换至 `com.corrosion.shuangyuime`，输入法方案选择“小鹤音形”。Phone/Pad 各执行 10 轮连续输入压力预检；进程 RSS 变化分别为 `-40 KiB` 与 `+624 KiB`，fatal、panic、SIGSEGV 和 process-crash 扫描均为空。

## 功能结果

| 用例 | 结果 | 证据 |
| --- | --- | --- |
| 设置页存在“精准匹配提示数量”，范围 1～9、默认 9 | PASS | `phone-settings.png/json` |
| Phone 输入 `un`，源序从“熟能生巧 uq、伤脑筋 jb、施耐庵 an、史努比 bi”开始 | PASS | `phone-un-hints.png`、`phone_after_n.json` |
| 设置改为 3 后，Phone 只显示前三项，不创建第 4 项 | PASS | `phone-settings-3.png/json`、`phone-un-count3.png`、`phone_count3_after_n.json` |
| 主动点击“伤脑筋 jb”提交“伤脑筋”并清空提示 | PASS | `phone-hint-commit.png/json` |
| 输入精确简码 `h` 只显示“和、忽略”，不附编码后缀 | PASS | `phone-exact-h.png`、`phone_exact_h.json` |
| 设置从 3 恢复为 9 并持久化 | PASS | `phone-settings-restored-9.json` |
| Pad 输入 `un` 横屏完整显示 9 项及未输入编码后缀 | PASS | `pad-un-hints.png`、`pad-direct-un.json` |

Pad 最终 9 项依次为：

1. 熟能生巧 `uq`
2. 伤脑筋 `jb`
3. 施耐庵 `an`
4. 史努比 `bi`
5. 十拿九稳 `jw`
6. 上年结转 `jv`
7. 受虐狂 `kl`
8. 少年郎 `lh`
9. 十年树木 `um`

## 主机与构建门禁

- `cargo fmt --all -- --check`：PASS
- `cargo test --workspace`：PASS；包含正式 456,976 四码审计、正式 `un` 源序、提示上限、规则隔离、主动选择和第五键不顶屏回归
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`：PASS
- ArkTS 全量单元测试：`BUILD SUCCESSFUL`
- x86_64/arm64-v8a Release Native 重建：PASS
- signed Release HAP 构建：PASS
- `verify-release-hap.ps1`：PASS；正式资源、权限和 Debug 内容门禁通过

候选稳定基线同步到当前精准策略。更新后的 `xiaohe-yinxing` 单键/双键快照反映精确路径；`xiaohe` 小鹤双拼对应快照逐字一致。

## 范围说明

本轮结论限定为主机和 x86_64 Phone/Pad 模拟器。ARM64 物理真机、分屏自动化、长时间 soak 和完整小鹤双拼设备矩阵未执行，不据此宣称完整发布门禁完成。
