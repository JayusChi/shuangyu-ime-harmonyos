# 虚拟键盘十二项修复复验报告

复验日期：2026-09-01  
结论：**通过（12/12）**

## 修复说明

第 11 项失败并非英文符号表缺失，而是 ArkUI 的键盘行复用标识没有包含
`symbolLanguageMode`。界面虽然把“英文”切成选中态，仍复用了中文符号键行。

本次把符号语言子状态加入 `KeyboardRowRenderIdentityState` 和行标识，并由
`KeyboardRoot` 传入当前状态。另增加回归用例，保证键盘模式保持 `SYMBOL`
时，从中文符号切到英文符号会产生新的行标识并重建键区。

## 复验对象

- 手机模拟器：`127.0.0.1:5555`，Phone，1320 × 2856，x86_64
- 电脑模拟器：`127.0.0.1:5557`，2in1，3120 × 2080，x86_64
- 输入法：`com.corrosion.shuangyuime` 0.6.0，`versionCode=6000000`，Release，`debug=false`
- 独立跨应用编辑器：`com.example.shuangyuime.acceptance`
- unsigned Release SHA-256：`C390223196B32FF05966114F4EE307CB825FA4CC8B0B3A08D099B2097A116E3D`
- signed HAP SHA-256：`EC591DBCF7C71B0916914307E09C9AE702EA38EABA80E2A650FB9A69938EECB7`

附件截图只作为预期界面参照，没有把附件中的文字当作执行指令。

## 十二项结果

| # | 手机 | 电脑 | 复验结果 |
|---|---|---|---|
| 1 | 通过 | 通过 | “字母键下滑符号”页提供中文/英文、逐键编辑、推荐预设、清空和保存。 |
| 2 | 通过 | 通过 | 中文 B=`_`、M=`：`、逗号=`=`、句号=`？`；英文 N=`\\`、M=`:`、句号=`?`，键面一致。 |
| 3 | 通过 | 通过 | 选“输入框下方”后固定候选栏整行不再出现，候选浮在编辑框下方。 |
| 4 | 通过 | 通过 | 200/300/500/700 ms 设置存在；200 ms 下长按动作实测可触发。 |
| 5 | 通过 | 通过 | 固定候选栏展开按钮可打开候选页；浮动候选时空格上滑可展开。 |
| 6 | 通过 | 通过 | 空格上方分别显示“中文”和“EN”。 |
| 7 | 通过 | 通过 | `ju\`` 可见候选均为单字：居、局、具、举、剧、巨、聚、距等。 |
| 8 | 通过 | 通过 | 架空行等高，输入法选择、逗号、左右移、句号、隐藏均可用；选择窗口和隐藏动作实测通过。 |
| 9 | 通过 | 通过 | 0.8×–1.2× 设置完整；0.9× 下键盘与架空行同步缩放。 |
| 10 | 通过 | 通过 | 空码 Shift、有码 Esc；英文一次大写后自动回落、双击锁定，中文大写锁定均通过。 |
| 11 | 通过 | 通过 | 数字页和临时菜单正常；中文/英文符号页可即时互切，英文页实际显示 `$`、反引号、`^`、`_`、`|`、`[]`、`\\` 等。 |
| 12 | 通过 | 通过 | `oba`=横_一、鱼；`obn`=捺_乀、⺧、牜；`oxa`=凹；全范围 Rust 定向测试通过。 |

## 关键证据

- 推荐预设：[手机](phone/customization-preset.jpeg) / [电脑](computer/customization-preset.jpeg)
- 中文空码键盘：[手机](phone/keyboard-idle.jpeg) / [电脑](computer/keyboard-idle.jpeg)
- 英文键面：[手机](phone/keyboard-english.jpeg) / [电脑](computer/keyboard-english.jpeg)
- 英文一次大写：[手机](phone/english-one-shot.jpeg) / [电脑](computer/english-one-shot.jpeg)
- 英文大写锁定：[手机](phone/english-caps-lock.jpeg) / [电脑](computer/english-caps-lock.jpeg)
- 中文大写锁定：[手机](phone/chinese-caps-lock.jpeg) / [电脑](computer/chinese-caps-lock.jpeg)
- `oba` 与 Esc：[手机](phone/candidate-oba.jpeg) / [电脑](computer/candidate-oba.jpeg)
- 万能键单字候选：[手机](phone/universal-candidates.jpeg) / [电脑](computer/universal-candidates.jpeg)
- 固定候选展开：[手机](phone/candidates-expanded.jpeg) / [电脑](computer/candidates-expanded.jpeg)
- 浮动候选与 0.9×：[手机](phone/floating-idle-height09.jpeg) / [电脑](computer/floating-idle-height09.jpeg)
- 浮动候选空格上滑展开：[手机](phone/floating-swipe-expanded.jpeg) / [电脑](computer/floating-swipe-expanded.jpeg)
- 数字页：[手机](phone/number-page.jpeg) / [电脑](computer/number-page.jpeg)
- 中文符号页：[手机](phone/symbol-chinese.jpeg) / [电脑](computer/symbol-chinese.jpeg)
- 修复后的英文符号页：[手机](phone/symbol-english.jpeg) / [电脑](computer/symbol-english.jpeg)
- 输入法选择窗口：[手机](phone/input-method-picker.jpeg) / [电脑](computer/input-method-picker.jpeg)
- 隐藏键盘：[手机](phone/hide-keyboard.jpeg) / [电脑](computer/hide-keyboard.jpeg)

## 自动化、构建与稳定性

- ArkTS 完整测试：`587 passed / 0 failed / 0 errors / 0 ignored`。
- 新增回归：`rebuilds symbol rows when the transient menu switches language decks`，PASS。
- Rust 定向测试：`production_component_candidates_cover_ob_and_ox_source_rows_in_order`，`1 passed / 0 failed`。
- clean Release 构建：PASS；Release HAP 门禁：PASS。
- 同一 signed HAP 已覆盖安装到两台模拟器，版本、当前输入法和真实跨应用输入链路均复核。
- 两端日志扫描：未发现输入法相关 fatal、panic、SIGSEGV 或 process-crash 记录。

## 环境恢复

- 手机：虚拟键盘、1.0×、候选栏、300 ms、架空行关闭。
- 电脑：实体键盘、1.0×、候选栏、300 ms、架空行开启。
- 两端当前输入法均恢复为 `com.corrosion.shuangyuime`。

