# 2026-09-07 手机与电脑模拟器验收

结论：**本轮未全部通过，不能作为发布验收通过记录。** 两端已安装并实际测试当前签名包；切分核心用例、普通成对符号居中和独立编辑器删行通过，发现符号页遗漏及系统子类型覆盖方案的问题。指定宿主应用和真实键盘插拔仍需补测。本轮仅增加验收脚本、截图、日志和报告，未修改产品代码。

## 测试对象与方法

| 项目 | 手机 | 电脑 |
| --- | --- | --- |
| HDC | 127.0.0.1:5555 | 127.0.0.1:5557 |
| 类型 | Phone 模拟器 | 2in1 模拟器 |
| 分辨率 | 1320 × 2856 | 3120 × 2080 |
| 被测版本 | 双羽 0.8.0 | 双羽 0.8.0 |
| 宿主 | com.example.shuangyuime.acceptance | com.example.shuangyuime.acceptance |
| 输入路径 | 屏幕逐键点击；补测实体按键事件 | 实体按键事件；补测虚拟键盘 |

HAP：`entry/build/default/outputs/default/entry-default-signed.hap`，94,949,342 字节。
SHA-256：`d76ab4997ed94e3bc5a9b49af3264edfe32082ec3b524b446146389750723963`。
完整版本与包信息：[metadata.json](metadata.json)。安装为覆盖安装，没有卸载、清空沙箱或重置签名。电脑端安装脚本恢复 IME 返回过错误 90；复查当前 IME 为双羽，随后完成了真实输入测试。

使用 HDC `uitest` 逐键点击或注入按键，在另一包名的编辑器检查最终文本；没有把 `inputText` 直接填入的中文作为输入法通过证据。实体测试属于设备上的按键事件路径，不等同于真实 USB / 蓝牙键盘。所有截图旁均保存同名布局 JSON。

## 客户清单结果

| 需求 | 手机 | 电脑 | 本轮证据与范围 |
| --- | --- | --- | --- |
| 上档标记向右上偏移 | 通过（外观） | 通过（外观） | [手机键盘](phone/keyboard-ready.png)、[电脑虚拟键盘](computer/system-picker-open.png)；数字键盘也可见右上标记 |
| ϟ12 下方系统输入法选择键 | 通过（弹窗） | 通过（弹窗） | [手机列表滚动后](phone/system-picker-list.png)、[电脑列表](computer/system-picker-open.png)；系统键盘及双羽出现在系统窗口中。未安装百度，未验证切换到百度 |
| 第二行 `〔〕` 成对 | **未通过** | **未通过** | 仍为独立 `〔` 和 `〕` 两键；点左括号再点 ＆ 得到 `〔＆`，没有右括号。[手机](phone/paired-square.png)、[电脑](computer/paired-square.png) |
| 已有 `（）` 光标居中 | 通过（独立编辑器） | 通过（独立编辑器） | 点 `（）` 再点 ＃，结果含 `（＃）`。[手机](phone/paired-cursor.png)、[电脑](computer/paired-cursor.png)。备忘录未测 |
| 实体快符成对居中 | 通过（`;l`） | 通过（`;k`、`;l`） | 输入快符后再输入 `ni`，落在括号内部。[手机](phone/physical-square.png)、[电脑圆括号](computer/physical-pair.png)、[电脑六角括号](computer/physical-square.png) |
| 编码同行、无原始字母误上屏 | 已测用例通过 | 已测用例通过 | 切分候选出现时编辑框为空，提交后仅有中文；删行后同样无字母。当前采用编码与候选同行，未验收嵌入编码及虚线下划线 |
| 自动识别选项 | 通过（静态状态） | 通过（静态状态） | [手机设置](phone/auto-settings.png)、[电脑设置](computer/auto-settings.png)；选自动后手机 TOUCH_READY、电脑 HARDWARE_READY。真实连接/断开未测 |
| 数字页 / 左下、粘贴右上 | 通过（布局） | 通过（布局） | [手机](phone/numeric.png)、[电脑](computer/numeric-ready.png)。本轮未验证非空剪贴板内容粘贴 |
| 固定候选窗菜单左、收起右 | 通过（布局） | 通过（布局） | 同上述键盘截图；未单独执行收起按钮用例 |
| 固定候选序号 | 通过 | 待补独立用例 | [手机切分候选](phone/split-ambiguous.png)清晰显示 1、2；电脑本轮切分用的是浮动候选，不据此证明固定候选序号 |
| `oui` 删行和继续输入 | 通过（独立编辑器） | 通过（独立编辑器） | 手机 `你\n回复` → `你\n` → `你\n你`；电脑 `你\n很` → `你\n` → `你\n你`。第一行保留，后续没有原始字母 |
| QQ、备忘录、头条兼容性 | **未测试** | **未测试** | 两端包清单未找到指定应用。不能用独立编辑器结果代替这些宿主的验收 |

删行证据：[手机删除前](phone/oui-yinxing.png)、[删除后](phone/oui-deleted.png)、[继续输入](phone/oui-followup.png)；[电脑删除前](computer/oui-fixture.png)、[删除后](computer/oui-deleted.png)、[继续输入](computer/oui-followup.png)。

## 切分模式结果

以下通过项均在小鹤音形确实生效、切分已开启的会话中测试。

| 用例 | 手机 | 电脑 | 实际结果 |
| --- | --- | --- | --- |
| `oit` 菜单 | 通过 | 通过 | 1.[传统]、2.[切分]；[手机](phone/split-menu.png)、[电脑](computer/oit-active.png) |
| 通过 `oit` 开启后 `hfkn` | 通过 | 通过 | 编码 `hf'kn`；第一候选“很可能”，第二候选仅显示“困难”；编辑框不提前提交。[手机](phone/split-ambiguous.png)、[电脑](computer/split-ambiguous.png) |
| 选择第二候选 | 通过 | 通过 | 上屏完整“很困难”，不丢失前半“很”。[手机](phone/split-second.png)、[电脑](computer/split-second.png) |
| `hfkn` 后继续第五码 `n` | 通过 | 通过 | 上屏“很可能”；[手机](phone/split-fifth.png)、[电脑](computer/split-fifth.png) |
| `alyg` 四码空码自动切分 | 通过 | 通过 | 无需空格，上屏“按理应该”。[手机](phone/split-unique.png)、[电脑](computer/split-unique.png) |
| 独立设置开关 | 待补点击用例 | UI 通过，端到端未通过 | [电脑关闭状态](computer/lower-settings.png)、[开启状态](computer/split-toggle-on.png)；随后受下述系统子类型问题影响，未完成完整开关回归 |
| 切回传统后完整输入回归 | 未完成 | 未完成 | 观察到 `hfkn` 不上屏，但后续取消/重新进入会话改变状态，未将“不上屏”单独认定为通过 |
| 候选数量配置、跨页选择 | 未测试 | 未测试 | 本轮用例后半仅有两个候选，不足以证明按任意设定候选数分页 |
| 二简含符号、半边无候选回退、已有全码优先 | 未测试 | 未测试 | 本轮未构造设备用例；以前的单元测试不能冒充本次设备验收 |
| 全新安装默认传统、重启持久化 | 未测试 | 未测试 | 使用覆盖安装保留数据，未清除用户设置 |

## 发现的问题

### A. 中文符号页遗漏成对 `〔〕`

复现：打开虚拟键盘 → ϟ12 → 中文 → 第二行点击 `〔` → 输入 ＆。
实际只有 `〔＆`。客户要求该括号成对，当前两端都未满足。已有快符 `;l` 可输出 `〔〕` 并居中，说明快符能力与符号页键位定义需要分别验收。

### B. 系统记住的输入法子类型覆盖应用内方案

复现路径：设置页选择“26 键小鹤音形” → 切到编辑器/重新建立输入法会话 → 系统回传之前保存的子类型。期间多次观察到原本可用的 `oit` 不再显示直通菜单、`hf` 变为其他拼音方案候选。再次在应用设置中选择小鹤音形，可恢复上述通过的用例。

电脑日志明确记录：`input method subtype applied: id=shuangyu_quanpin_zh_cn, mode=chinese_placeholder, profile=quanpin-26`。例如 [initial-hilog.txt](computer/initial-hilog.txt) 中 15:50:45 初始化音形，随后 15:50:46 engine scheme active 变为 quanpin；[split-hilog.txt](computer/split-hilog.txt) 与 [final-hilog.txt](computer/final-hilog.txt) 也保留了 subtype applied 记录。手机也观察到新会话方案改变，但本轮未保留该次切换的完整回调链，不将其与电脑判定为已证明相同根因。

代码定位：`entry/src/main/ets/application/InputMethodLifecycleDispatcher.ets` 的 `handleInputMethodSubtype` 根据平台回传值调用 `setKeyboardProfile`；应用设置与系统子类型的同步需继续检查。此问题影响音形功能在新会话中的可用性，应在完整验收前解决。

## 补测与证据说明

1. 修复 A、B 后，重新跑传统/切分来回切换、冷启动、换编辑框、换宿主。
2. 安装或提供 QQ、备忘录、头条环境，分别测试虚拟/实体编码、成对符号、`oui` 删行后输入。两端已安装包列表：[手机](phone/packages.txt)、[电脑](computer/packages.txt)。
3. 真机 USB/蓝牙键盘插拔、候选分页和非空剪贴板粘贴需补测。
4. `split-results.json`、`traditional-recheck.log` 保存了探索脚本原始断言，包括候选文本格式差异、等待/焦点和方案切换造成的中断；不代表全部脚本通过。本报告只将有对应最终文本及截图的步骤标为通过。
5. 第一次尝试用 `uitest text` 建立英文多行夹具未成功，已弃用；正式 `oui` 证据使用逐键输入的中文夹具。
6. 本轮最后将两端输入方式设为自动识别，当前 IME 为双羽。测试设置不代表全新安装默认值；编辑器中留存的均为本轮测试文字。
