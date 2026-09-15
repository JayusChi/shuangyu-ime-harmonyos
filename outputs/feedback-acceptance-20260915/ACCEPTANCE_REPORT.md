# 2026-09-14 客户反馈：手机、电脑模拟器验收

后续更新：本报告中的 D1 已在同日修复，并在手机、电脑模拟器复测通过（766 项单测、146 条设备证据断言）。详见[修复记录](../../docs/features/input-method/HARDWARE_CANDIDATE_CLIPPING_20260915.md)。下文保留修复前结果与证据；QQ 按用户要求暂不继续。

验收日期：2026-09-15。**结论：未全部通过。发现 1 个显示问题：手机实体键盘模式的浮动候选被裁切。QQ 专属场景未验证，其余下表所列操作在独立验收宿主中通过。**

本轮实际操作模拟器上的已安装输入法，触屏项目点击或滑动真实键盘组件，实体键盘项目通过鸿蒙 `uitest uiInput keyEvent` 注入系统按键。本轮没有修改产品源码，没有把此前单元测试或旧截图计入新的设备验收。

## 逐项结果

| 客户要求 | 手机 | 电脑 | 实测与证据 |
| --- | --- | --- | --- |
| 1. 进入群聊/私聊不直接弹键盘，点击后可输入 | 独立宿主通过；QQ 待测 | 独立宿主通过；QQ 待测 | 页面初次打开及重新进入均无键盘，点击输入框后显示并能输入。电脑特意切回原有虚拟键盘模式验证。[手机进入](phone/initial-unfocused.png)、[手机点击](phone/after-focus.png)、[电脑进入](computer/touch-initial-unfocused.png)、[电脑点击](computer/touch-current.png)、[电脑上屏](computer/touch-focus-commit.png)。两端未安装 QQ，不能据此声称 QQ 群聊、私聊已修复。 |
| 2. 浮动编码两侧固定留白、候选左对齐 | 左对齐通过；窄屏裁切见 D1 | 通过 | `f → fi → fi'h → 回删到 fi`，编码始终从相同左侧位置开始；候选紧随编码的实际宽度排列，回删后未在保留的窗口宽度内居中。[手机](phone/floating-fi-back.png)、[电脑](computer/floating-fi-back.png)。 |
| 3. 实体键盘用 `[ ]` 翻页、横排、数字选词 | 翻页与数字选词通过；5 项完整显示失败 | 通过 | `ui` 第 1 页“是/时/事/使/市”，第 2 页“式/试/石/十/室”；`[` 返回，第二页数字 2 上屏“试”。无展开按钮。电脑还验证第 10→11→10 页跨引擎批次、数字 5 上屏“虱”。[电脑下一页](computer/paging-next.png)、[电脑选词](computer/paging-selected.png)、[跨批次](computer/batch-page-11.png)、[手机裁切](phone/hardware-clipping-repro-next.png)。 |
| 4. 嵌入编码作为可选显示效果 | 独立宿主通过 | 独立宿主通过 | 开启设置后编码出现在宿主光标处，候选窗不重复显示编码；“你kjk”回删为“你kj”，选词变成“你看”，再输入并取消后仍为“你看”。手机重启输入法后开关仍生效。[手机预编辑](phone/inline-kjk.png)、[手机提交](phone/inline-commit.png)、[电脑预编辑](computer/inline-kjk.png)、[电脑取消](computer/inline-cancel.png)。未覆盖不支持预编辑的宿主、密码框和 QQ。 |
| 5. 句中固定 `up=双拼`、`zm=怎么` | 通过 | 通过 | 从“我的词库”实际新增两条固顶规则，`woysup` 上屏“我用双拼”，`nizmbuxk` 上屏“你怎么不行”。[手机 zm](phone/fixed-zm-commit.png)、[手机 up](phone/fixed-up-commit.png)、[电脑 zm](computer/fixed-zm-commit.png)、[电脑 up](computer/fixed-up-commit.png)。 |
| 6. `bu/ui/ni/a` 末尾单字母参与识别 | 通过 | 通过 | 实际输入 `buuinia`，显示分段 `bu'ui'ni'a`，候选 2“不是你啊”上屏后无剩余字母。首选“不是你爱”，未把“啊”固定首选作为验收条件。[手机](phone/trailing-a-commit.png)、[电脑](computer/trailing-a-commit.png)。 |
| 7. 双拼分号直接上屏 | 通过 | 通过 | 系统分号键：空输入为“；”，有 `ni` 候选时得到“你；”，后续 `h` 正常组成候选。手机还用实际 F 键上滑输入其上档半角分号，得到“你;”，随后 `h` 首选“和”。[手机实体分号](phone/semicolon-composition.png)、[手机触屏分号](phone/touch-semicolon-composition.png)、[手机后续字母](phone/touch-semicolon-follow-letter.png)、[电脑](computer/semicolon-composition.png)。上档符号使用该键配置的半角字符。 |

## D1：手机实体模式每页 5 项未能完整显示

- 环境：Pura 90，1320×2856，密度 3.5，双拼，实体键盘模式，候选数 5，浮动字号 17，嵌入编码关闭。
- 复现：进入聊天输入框，输入 `ui`，按 `]`。等待界面稳定后仍复现。
- 实际：只完整看到“1 式、2 试”，“3 石”部分可见，第 4、5 项不在可见区域。[复现截图](phone/hardware-clipping-repro-next.png)。
- 再按数字 5 能正确上屏“室”，表明当前页的候选映射正常，缺陷在可见区域。[不可见第 5 项的上屏结果](phone/hardware-clipping-number-5.png)。
- 显示分析：当前 `FloatingCandidateRoot` 在窄屏中仍为翻页控件保留 108 vp，编码与候选行的剩余空间不足。电脑宽屏未复现。触屏浮动窗也能看到尾部候选被截断，但它仍有展开/滚动入口；实体模式去掉展开后影响更明显。
- 后续建议：优先压缩实体模式的翻页控件占位，或根据可用宽度确定实际页容量，同时保证 `[ ]`、数字键和点击共用同一页映射。本轮仅验收、定位和记录，未修复此问题。

## 浮动对齐量测

以下均为实际 UI 布局像素，按 `f/fi/fi'h/fi` 四个状态检查。

| 设备 | 卡片左边缘到编码布局框 | 编码布局框到首候选 | 卡片高度 | 卡片宽度变化 |
| --- | --- | --- | --- | --- |
| 手机 | 均为 24 px | 均为 21 px | 均为 196 px | 1096→1096→1096→1096 px |
| 电脑 | 均为 12 px | 均为 11 px | 均为 108 px | 1075→1115→1310→1310 px |

编码组件的左右 padding 均为 10 vp；截图中 `f` 的可见字形左边缘也保持固定（手机 172 px、电脑 787 px）。不同末尾字母的字形留白不同，不能把字形最右像素与布局内边距混为一谈。[布局与断言](verification.json)、[字形像素量测](text-pixel-measurements.json)。

## 运行与产物

- 手机：`127.0.0.1:5555`，Pura 90 / phone，1320×2856；电脑：`127.0.0.1:5557`，MateBook Pro / 2in1，3120×2080。HarmonyOS 6.1.1，API 24，x86_64 模拟器。
- 宿主：`com.example.shuangyuime.acceptance` 的独立聊天输入框；没有真实 USB/蓝牙键盘、QQ 或客户真机实测。
- 本轮重新 clean build：Release 编译、签名及资源门禁通过；两端覆盖安装 0.12.0 成功，`SIGNATURE_RESET=false`，没有卸载或清空用户数据。[构建](build.log)、[安装手机](install-phone.log)、[安装电脑](install-computer.log)、[包门禁](package-gate.log)。
- 安装包副本：[device-signed.hap](accepted-device-signed.hap)，93,347,665 bytes；SHA-256 `81FD61A6BE30AE0F14212EA3ACCBED0B3FACF0D19257BF586DB5B1E3B61AF4EA`。这是用于模拟器验收的开发签名 Release 包，含上述待修复问题，不代表验收全通过。
- [证据复核脚本](verify-evidence.cjs) 共 62 条断言：**59 通过、3 失败**。3 条失败均与 D1 的可见候选裁切有关，未把它们抹掉或降为通过。
- 前一轮源码单测 764/764 的结果仍在 `../qq-keyboard-test-result.txt`；本轮没有重新运行单测，也没有将旧结果计入本次设备断言数。
- 历史调试截图保留。`touch-semicolon.png` 是误点上档标注所在按键、实际触发主键“/”对应“、”的失败尝试；正确上滑手势的证据是 `touch-semicolon-composition.png`。早期词库填充和冷启动截图包含尚未刷新完成的状态，最终结果以本报告引用及 `verification.json` 为准。

## 清理与恢复

两端起始“我的词库”均为有效 0 条。本轮临时添加的 `up/zm` 已通过界面移除，恢复为空：[手机](phone/lexicon-restored.png)、[电脑](computer/lexicon-restored.png)。未清理学习记录。

按本轮最初观察到的实际设置恢复：手机自动识别、固定候选栏；电脑虚拟键盘、固定候选栏；两端候选数 5、嵌入编码关闭。原有自定义皮肤和布局保留。设置页面截图分别见两端 `final-input-settings.png`、`final-candidate-settings.png`。安装前进程本地 XML 与实际共享设置存在旧值差异，因此本报告只声明已恢复观察到的相关设置，不声称全部 XML 字节完全一致。

手机、电脑模拟器仍在线，均保留本轮安装的 0.12.0 验收包。QQ 场景需要在已安装并登录 QQ 的目标环境继续验收。
