# 客户反馈清单：模拟器验收

日期：2026-09-09。设备：Phone `127.0.0.1:5555`（1320×2856）、2in1 `127.0.0.1:5559`（3120×2080）。使用正式源码、开发签名 HAP 覆盖安装，未卸载、未清空应用数据。跨应用编辑器为独立验收客户端 `com.example.shuangyuime.acceptance`。

## 本轮发现并修复

1. **便捷候选显示停在旧值**：输入 `=1234.5`，旧界面仍显示“壹元整”，实际上屏却是完整金额；`=hello` 也只显示 `h`。原因是所有编辑阶段复用 `convenience:0` 候选 ID。现在候选 ID 随原始输入变化，固定栏和浮动窗同步刷新。
2. **实体便捷计算漏掉独立运算键码**：`unicodeChar=0` 时，独立 `KEYCODE_PLUS`、`KEYCODE_STAR` 未映射。补齐 `2066 → +`、`2010 → *`，保留 Shift 组合键与小键盘路径。
3. **网址编辑框被中文组词接管**：“完整网址”使用普通文本类型，直接填写链接时字母可能进入中文组词。现在网页直通使用 `InputType.URL`。
4. **五位自定义网页直通提前逆切分**：保存 `zzweb` 后，`zzwe` 会提交“走玩儿”，最后剩下 `b`。外部动作不属于可自动上屏的文字，但其长码应保留继续输入的通路。现在将有效网页／目录长码纳入后续编码判断；继续禁止自动执行外部动作。新增回归先复现失败，再修复通过。

另修正新增 Rust 代码的格式和 Clippy 问题。

## 逐项验收

| 客户要求 | 结果与实际观察 | 主要证据 |
| --- | --- | --- |
| ϟ12 下方切换其他输入法 | 通过：窗口显示“小艺输入法、双羽输入法”，无当前输入法的键盘子类型；选择小艺后系统当前 IME 确认变为小艺，再恢复双羽 | `input-method-picker.png`、`switched-celia.png` |
| 实体 `;n`、Tab、回车跳出成对符号 | 独立编辑器通过：分别输入后续数字，得到 `（）1（）2（）3（）4`；涵盖 Tab、`;n`、主回车、小键盘回车 | `computer/pair-*-correct.png`、`computer/pair-end.png`、`computer/pair-enter.png`、`computer/pair-numpad-enter.png` |
| 有候选时上滑回车：先提交再重复 | 通过：`kj` 候选“看”，上滑后输入框为“看看” | `kj-candidate.png`、`kj-repeat-retry.png` |
| 有候选时上滑删除：先提交再撤销 | 通过：已有“看看”，再输入 `kj` 上滑删除后仍为“看看”，组词结束 | `candidate-undo.png` |
| `ohx` 固定／浮动 | 通过：候选在键盘上方或输入框下方显示，恢复固定后保存 `bar` | `ohx-menu.png`、`floating-candidate.png`、`settings-after-directs.xml` |
| `ojg` 1.0、+0.05、-0.05 | 通过：连续两次增加、减少一次、恢复默认，键盘实际尺寸随之变化；Q 字母顶部位置依次 1715、1668、1715、1763 px | `height-*-applied.json` |
| `ohz` 固定字号 | 通过：15 → 17 → 16；最后恢复 15 | `fixed-font-*-menu.png`、`settings-after-directs.xml` |
| `ofz` 浮动字号 | 通过：17 → 19 → 18；与固定字号分别保存，最后恢复 17 | `floating-font-*-menu.png`、`settings-after-directs.xml` |
| `ofa` 三种 26 键通用 | 通过：音形 → 双拼 → 全拼 → 音形，每种方案均显示相同三项 | `ofa-*-menu.png` |
| `ovd`、`oyx` | 开关与持久化通过：保存 `haptic_level=off`、`key_sound_enabled=true` 后核对，验收后恢复轻震动／音效关闭 | `vibration-off-menu.png`、`sound-on-menu.png`、`settings-after-directs.xml` |
| 按键音强度 | 设置页“按键音量”0–100%，默认 16%；最终响度同时受系统媒体音量影响 | 设置代码及默认配置；模拟器不判断手机扬声器实际响度 |
| 智能标点默认 300 ms | 默认常量、迁移和测试通过；旧模拟器保存的 1000 ms 被保留，验收时通过界面选为 300 ms | `final-eighteen-persisted.xml`、ArkTS 测试 |
| 有候选时空格下左右方向键做空格 | 通过：左右各点击一次，分别增加一个首候选“看” | `candidate-left-space.png`、`candidate-right-space.png` |
| 中文 Shift 大写锁定显示 EN | 通过：点击 Shift 后空格键上方显示 EN | `caps-lock.png` |
| 自定义打开网页／目录直通 | 通过：网页五位编码 `zzweb` 保留完整候选，空格选择后浏览器显示 Example Domain、地址 example.com；目录直通打开文档目录 | `computer/url-typed.png`、`computer/url-saved-final.png`、`computer/directory-returned.png`、`computer/directory-opened.png`、`computer/long-web-fixed.png`、`computer/website-final-state.png` |
| `=1234.5` 金额 | 最终包通过：候选和上屏都是“壹仟贰佰叁拾肆元伍角整” | `final-phone/money-*.png` |
| `=2026.8.` 年月 | 最终包通过：仅“2026年8月” | `final-phone/month-*.png` |
| `=2026.5.5` 日期 | 最终包通过：仅“2026年5月5日”和“2026-05-05”；粘贴键选择第二项 | `final-phone/date-*.png` |
| `=123+5*6` 计算 | 最终包通过：候选“123+5*6=153”“153”，粘贴键提交 153 | `final-phone/calc-*.png` |
| 便捷临时英文 | 最终包通过：数字页按 =，返回字母页输入 hello，候选和上屏均为 hello | `final-phone/english-*.png` |
| 等号选择首候选、双击输出自身 | 通过：金额／年月使用 = 确认；连续两次 = 输出一个等号 | `final-phone/double-equals.png`、`final-numeric.log` |
| 实体单引号引导、双击交替单双引号 | 通过：日期及计算进入便捷候选，两次双击单引号输出 `‘’`；修复后独立 +/* 键码的算式显示、上屏均正确 | `computer/convenience-date.png`、`computer/convenience-quotes.png`、`computer/calc-fixed.png`、`computer/calc-fixed-commit.png` |
| 字母上档符号向内移动 | 已实现并检查截图：单字符上档标记在字母中心与右边缘之间 | `virtual-start.png`、`final-phone-keyboard.png` |
| 18 键等宽、直接选择 | 通过：从 26 键音形直接点 18 键双拼，保存 `xiaohe-18/xiaohe`；各组字母键宽均为 166 px，双字母组内部各半 | `final-eighteen-keyboard.png/json`、`final-eighteen-persisted.xml` |

## 验证记录

- ArkTS 全量：686 通过，0 失败、0 错误。修复键码后复跑，仍为 686 通过。
- Rust 工作区：限制测试线程为 2 后，69 组测试／文档测试共 665 项通过，0 失败。首次默认并发运行出现旧全拼资源加载测试超过 10 秒；未放宽阈值，降低并发后该项及全套通过。
- 便捷输入最终专项：4 通过，包含候选 ID 随内容变化并保持同一快照稳定的回归。
- 长网页直通：补入 `zzweb` 并启用逆切分，修复前失败、修复后通过；码表状态机 96 项回归通过。
- 最后修改后的 Rust fmt、Clippy `-D warnings` 通过。
- 手机数字便捷输入脚本 `final-numeric.ps1`：金额、年月、日期、计算、双等号、临时英文六项均核对候选与上屏通过。
- 原始日志、设置快照、界面 JSON 和截图均保存在本目录。

## 实机边界

- 模拟器没有客户的“备忘录”应用。成对符号和 End 已在跨应用 TextInput 中验证；客户备忘录特有的光标接口仍需要在实际设备复验，不能用模拟器结果替代。
- 模拟器只启用了小艺与双羽；百度未安装，未虚构百度切换结果。
- 震动、音效开关及参数已验证，真实震感、扬声器音量仍以手机体验为准。

自定义直通入口：**用户词库 → 直通 → 打开网页／打开目录 → 填编码 → 保存并立即应用**。目录请使用“选择目录”获得鸿蒙 URI。

## 最终交付与收尾

- 正式发布签名 HAP：[entry-default-signed.hap](../../entry/build/release/outputs/default/entry-default-signed.hap)。版本沿用 0.9.0。
- 大小：93,011,043 bytes；SHA-256：`2CFB1E1918D605238FBBD36BF5CB16BCA327BC6F2EFF34E2D2E5E5804ED53838`。
- 最终签名 HAP 资源校验 `RELEASE_HAP_VERIFY_RESULT=PASS`，日志 `verify-release-final.log`。
- 最后一轮开发签名安装在 Phone、2in1 均为 `PASS / SIGNATURE_RESET=false`，日志 `install-shortcut-final.log`。发布包与模拟器验收包来自同一份正式源码，使用各自产品签名；未声称从设备回读 HAP 做逐字节比较。
- 完整 Rust 工作区回归后，最后的长码补修另跑了正式引擎专项、96 项码表状态机回归和 fmt／Clippy。
- 网页、目录两条验收记录已通过界面移除，用户词库恢复验收前的有效 0 条。证据：`computer/cleanup-complete.png/json`。
- Phone 恢复 26 键音形、固定候选、15／17 号字、1.0 键高、轻震动、音效关闭；智能标点设置为客户要求的 300 ms。
- `artifacts/0.9.0/` 中历史 APP 未重新打包；本轮交付上述新 HAP。