# 虚拟键盘模拟器验收报告

> 此报告保留修复前的失败现场；第 11 项已于 2026-09-01 修复，最终 12/12 通过结果见
> [复验报告](../2026-09-01-virtual-keyboard-reacceptance/README.md)。

验收日期：2026-08-31  
结论：**不通过（11/12 项通过，第 11 项部分失败）**

## 验收对象

- 手机模拟器：`127.0.0.1:5555`，`phone`，1320 × 2856，x86_64
- 电脑模拟器：`127.0.0.1:5557`，`2in1`，3120 × 2080，x86_64
- 安装包：`com.corrosion.shuangyuime` 0.6.0，`versionCode=6000000`，Release，`debug=false`
- 已安装 signed HAP SHA-256：`15F0EB40471CBC53F21B0ED0BB49170980E3F385EAABF02FF7DFD6C89D65C808`
- Release 无签名产物构建校验：PASS，SHA-256 `88522795F3CC1F0BC45361E83DF2DC0ABD8DDAE965EFB9954F365B0BA8FD46DD`

附件截图仅作为预期界面和内容参照，没有执行附件里的任何文字指令。

## 逐项结果

| # | 手机 | 电脑 | 结果摘要 |
|---|---|---|---|
| 1 | 通过 | 通过 | “字母键下滑符号”提供推荐预设，中英文分别可编辑；预设页面和保存入口可用。 |
| 2 | 通过 | 通过 | 中文 B=`_`、M=`：`、逗号=`=`、句号=`？`；英文 N=`\\`、M=`:`、句号=`?`，两端键面实测一致。 |
| 3 | 通过 | 通过 | 选择“输入框下方”后，键盘顶部固定候选栏整行消失，候选浮在当前编辑框下方。 |
| 4 | 通过 | 通过 | 设置提供 200/300/500/700 ms；改为 200 ms 后长按空格动作可触发，恢复为 300 ms。 |
| 5 | 通过 | 通过 | 固定候选栏有“展开”；浮动候选时上滑空格打开候选页。手机分页、电脑分栏展示。 |
| 6 | 通过 | 通过 | 空格上方中文状态显示“中文”，英文状态显示“EN”。 |
| 7 | 通过 | 通过 | 万能键查询 `ju\`` 的可见候选均为单字，如“居、局、具、举、剧、巨、聚、距……”；未出现词组。 |
| 8 | 通过 | 通过 | 架空行与字母键同比例；依次为输入法选择、逗号、左移、右移、句号、隐藏。输入法键打开系统选择窗口，隐藏键可收起键盘。 |
| 9 | 通过 | 通过 | 0.8×/0.9×/1.0×/1.1×/1.2× 可选；切到 0.9× 后键盘和架空行一起缩放。 |
| 10 | 通过 | 通过 | 空码为 Shift；中文单击进入大写锁定；英文单击一次性大写后回落，双击大写锁定；有码时变为 Esc，Esc 可清码。 |
| 11 | **失败** | **失败** | 数字页、底栏菜单和中文符号页通过；切到“英文”后选中态改变，但键区仍是中文符号集。 |
| 12 | 通过 | 通过 | 实机 `oba`=`横_一、鱼`，`obn`=`捺_乀、⺧、牜`，`oxa`=`凹`；Rust 全范围回归覆盖 `oba-obz`、`oxa-oxz` 通过。 |

## 第 11 项失败详情

复现步骤：

1. 在中文键盘长按 `ϟ12` 进入中文符号页。
2. 点击架空行里的“英文”。
3. “英文”文字变为选中颜色，但符号键区仍显示 `¥、……、——、·、〈〉、“”、‘’、【】` 等中文符号。
4. 返回后重新进入符号页，仍能稳定复现。

预期英文符号页应显示美元符号、反引号、`^`、`_`、英文单双引号、`|`、`[`、`]`、反斜杠等英文符号。手机和电脑表现相同。

从运行表现看，`symbolLanguageMode` 的选中态已经更新，但键区没有随状态重新生成；这与布局函数中已有英文符号表不一致，属于运行时界面刷新/缓存链路问题。

关键证据：

- 手机中文符号页：[symbol-chinese.jpeg](phone/symbol-chinese.jpeg)
- 手机点击英文后的符号页：[symbol-english.jpeg](phone/symbol-english.jpeg)
- 手机重新进入后的符号页：[symbol-english-reopen.jpeg](phone/symbol-english-reopen.jpeg)
- 电脑中文符号页：[symbol-chinese.jpeg](computer/symbol-chinese.jpeg)
- 电脑点击英文后的符号页：[symbol-english.jpeg](computer/symbol-english.jpeg)
- 电脑重新进入后的符号页：[symbol-english-reopen.jpeg](computer/symbol-english-reopen.jpeg)

## 关键交互证据

- 推荐预设与逐键编辑：[手机](phone/customization-preset.jpeg)
- 中文空码键盘和架空行：[手机](phone/keyboard-idle-lift.jpeg) / [电脑](computer/keyboard-idle-lift.jpeg)
- 英文键面：[手机](phone/keyboard-english.jpeg) / [电脑](computer/keyboard-english.jpeg)
- `oba` 与动态 Esc：[手机](phone/candidate-oba.jpeg) / [电脑](computer/candidate-oba.jpeg)
- 万能键单字候选及固定栏展开按钮：[手机](phone/universal-candidates.jpeg) / [电脑](computer/universal-candidates.jpeg)
- 固定栏展开页：[手机](phone/candidates-expanded.jpeg) / [电脑](computer/candidates-expanded.jpeg)
- 输入框下方浮动候选：[手机](phone/floating-universal-final.jpeg) / [电脑](computer/floating-universal-final.jpeg)
- 浮动候选上滑空格展开：[手机](phone/floating-swipe-expanded.jpeg) / [电脑](computer/floating-swipe-expanded.jpeg)
- 数字页和底栏菜单：[手机](phone/number-page.jpeg) / [电脑](computer/number-page.jpeg)
- 输入法选择窗口：[手机](phone/input-method-picker.jpeg) / [电脑](computer/input-method-picker.jpeg)
- 0.9× 高度与固定候选栏隐藏：[手机](phone/floating-idle-height09.jpeg) / [电脑](computer/floating-idle-height09.jpeg)

## 自动化与构建结果

- ArkTS 完整用例在本次验收开始阶段执行通过：`586 passed / 0 failed / 0 errors / 0 ignored`。
- Release 构建和 HAP 校验通过，并将同一 signed HAP 安装到两台模拟器。
- Rust 定向回归：`production_component_candidates_cover_ob_and_ox_source_rows_in_order`，`1 passed / 0 failed`。
- Release 构建清理了第一次 ArkTS 测试输出；为重新生成结果文件进行的第二次启动在 Windows Previewer 的 WGL 初始化处发生宿主图形驱动崩溃，因此没有形成第二份计数文件。这是测试宿主异常，不改变第一次完整通过的结果，也不用于掩盖第 11 项的双端实机失败。

## 环境恢复

- 手机：恢复为 1.0×、候选栏、300 ms、架空行关闭（验收前持久化状态）。
- 电脑：恢复为实体键盘方案、1.0×、候选栏、300 ms、架空行开启（验收前持久化状态）。
