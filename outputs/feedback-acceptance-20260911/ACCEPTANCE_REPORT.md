# 2026-09-11 客户反馈：手机与电脑模拟器验收

**后续状态：本报告中的3条手机网页未完成项已由新包补齐。** 用户批准应用内网页和联网权限后，两端18项网页/宿主检查通过，见 [查形全屏修复验收](../browser-fullscreen-fix-20260911/ACCEPTANCE_REPORT.md)。以下原包结论与失败证据按历史原样保留。

输入法侧修复与对应功能检查已完成；不能标记为全部端到端通过：手机模拟器浏览器全屏页面持续空白，虽然标签预览已经显示正确的官网和“你 / 鹤”查形结果。电脑浏览器完整网页通过。真实 USB、蓝牙或内置实体键盘未测试。

## 实测后补修

1. **触屏输入、鼠标点击候选无法打开直通网页。** 生命周期控制器持有 InputMethodExtensionContext，键盘及浮动候选组件创建的另一个控制器没有该上下文。新增共享的 DirectAbilityLauncherRegistry，由当前输入法能力绑定/解绑；旧能力销毁不会清除新能力的启动器。各控制器在执行时取得当前启动器。新增跨控制器执行和生命周期替换回归，电脑鼠标点击、手机触屏直通均已实际启动目标页面。
2. **手机 oix 标题停在 `{last_0}`。** 字符解析异步更新 displayText 后，候选 ForEach 仍按相同 id 复用旧显示。固定栏、浮动栏、展开网格的显示身份现包含 displayText，动作 id 与提交文本保持原值。最终安装包手机实测显示“「查」：你 / 「查」：剪贴板”。

代码位于 `entry/src/main/ets/application/DirectSessionActionService.ets`、`InputSessionControllerBase.ets` 及 `presentation/candidate/` 三个候选组件。其余需求沿用本轮开始前工作区已有修复，经本次重新构建与实测确认；没有覆盖或撤销其他未提交工作。

## 逐项结果

| 用户需求 | 实际结果与证据 | 结论 |
| --- | --- | --- |
| 1. 实体反引号万能键 | 电脑通过系统 keyEvent 2056 输入，组合为 `u` 加反引号，宿主未漏入反引号，正常显示万能匹配。[最终包截图](computer/final-universal.png)、[初次完整断言](computer/universal.json) | 模拟器按键路由通过 |
| 2. ojz 字体直通 | 顺序为 `[键字12号] / [+2] / [-1]`。手机实际执行 12→14→13→12，Q 字形高度为 49→57→53→49 px；候选字号保持。[菜单](phone/final-ojz-menu.png)、[14号](phone/font-14.png)、[13号](phone/font-13.png)、[恢复12号](phone/font-reset-12.png)；电脑也检查菜单和设置变化 | 通过 |
| 3. 输入后 oix 查形 | 手机先上屏“你”，候选标题解析为“「查」：你”，点击启动浏览器。电脑光标前“鹤”通过鼠标点击进入网页，页面显示“汉字：鹤”。[手机最终标题](phone/label-fix-cursor-menu.png)、[电脑网页](computer/final-cursor-browser.png) | 启动与查询通过；手机全屏浏览待复验 |
| 3. 复制后 oix 查形 | 在独立宿主复制“鹤”，空输入框输入 oix，进入输入法主应用的系统 PasteButton 页面，点击“粘贴”后打开查形。[手机粘贴页](phone/label-fix-paste-page.png)、[手机正确结果的标签预览](phone/final-clipboard-tabs.png)、[电脑完整网页](computer/final-clipboard-browser.png) | 启动与查询通过；手机全屏浏览待复验 |
| 4. 浮动候选完整显示、阴影 | 电脑默认5项和改为6项均完整显示，候选文本 bounds 与 origBounds 相同，右侧展开入口有独立空间；圆角、边框及阴影已截图检查。[5项](computer/universal.png)、[6项](computer/six-candidates.png) | 通过 |
| 5. 句号显示次选 | 手机有候选时显示“次选”，清空后恢复句号。[有候选](phone/final-ojz-menu.png)、[清空后](phone/font-reset-12.png) | 通过 |
| 5. 自定义对调句号、逗号 | 结构模型支持将二者在空格同行交换，动作和上档符号随按键；对应 ArkTS 回归与工坊10项检查通过。做法见下文。当前共享沙箱授权限制下没有实机导入自定义结构 | 模型与工坊通过；不冒充设备导入通过 |
| 6. 上档符号右边距 | 数字、全选、等号、问号采用统一右对齐和7vp右边距，手机截图检查。[完整键盘](phone/font-reset-12.png) | 通过 |
| 7. 四码唯一直通立即执行 | 电脑系统按键、手机触屏输入 xhgw，第4码后启动浏览器，无需空格或候选点击；补修共享启动器后手机不再报 guide action failed。[电脑最终包官网](computer/label-fix-home-browser.png)、[手机启动后](phone/final-home-browser.png)、[手机官网标签预览](phone/phone-tabs-now.png) | 自动执行通过；手机全屏浏览待复验 |
| 8. 默认候选数与展开 | 默认5，可配置1–10；电脑切换6后显示6项，展开网格、下一页、第2页、上一页、收起通过。手机窄屏固定栏右侧展开到网格，窄屏允许横向滚动。[电脑展开](computer/six-expanded.png)、[下一页](computer/expanded-next.png)、[收起](computer/six-collapsed.png)、[手机网格](phone/fixed-expanded.png) | 通过 |
| 8. 输入方案层级 | 手机进入“输入设置”即显示三个方案行；双拼同一行26/18键，拼音同一行26/9键。电脑保留左右分栏，选项对齐。[手机](phone/input-settings.png)、[电脑](computer/input-settings.png) | 通过 |
| 双拼1. 尾部单声母 d | 连续输入 `hduihfhcd`，首选并上屏“还是很好的”。[手机候选](phone/sentence1-new.png)、[手机上屏](phone/sentence1-committed.png)、[电脑上屏](computer/sentence1-committed.png) | 两端通过 |
| 双拼2. 非法声韵退回声声 | 连续输入 `qiuihfjdd`，首选并上屏“其实很简单的”。[手机候选](phone/sentence2-new.png)、[手机上屏](phone/sentence2-committed.png)、[电脑上屏](computer/sentence2-committed.png) | 两端通过 |

例句中的 `'` 在上述设备测试中表示分组说明，实际连续输入字母串。已有实体单引号第三候选快捷键保持；没有把字面单引号按键测试冒充为连续输入测试。

## 使用说明与边界

- 对调逗号、句号：工坊“结构”页将二者在空格所在行交换，导出 `.sy-layout`。单独 `.sy-skin` 保存外观，不保存排列。应用的自定义结构导入仍受既有华为共享沙箱授权限制，本次没有绕过该限制；详见 `docs/features/keyboard-customization/TEMPLATE_FORMAT.md`。
- oix 优先使用光标前的汉字。无可用光标前汉字且外部剪贴板不能直接读取时，进入“粘贴查形”页，必须点击系统“粘贴”。本包没有声明会导致 normal APL 安装失败的 READ_PASTEBOARD 权限。这里不是宣称外部复制内容在所有宿主都能无额外点击读取。
- 手机浏览器问题：进入完整页面时只显示底部工具栏，网页与地址栏未显示；切换已有标签、回到浏览器首页、下拉及仅重启浏览器后仍可复现。浏览器标签缩略图却能显示官网、“汉字：你”和“汉字：鹤”。这证明页面收到查询并生成了结果，但不等于完整浏览体验通过。保留 [空白页面](phone/final-clipboard-browser.png)、[带实际结果的缩略图](phone/final-clipboard-tabs.png)、`phone/final-oix-launch.log` 等原始证据。未清浏览器数据、未关闭原有标签、未改系统网络配置。
- 两台安装都使用安全覆盖，`SIGNATURE_RESET=false`。测试结束后两端 preferences 的所有字符串设置项与 `settings-before.xml` 一致，包括键盘字体12、候选数5、小鹤音形26键及各自原来的高度/候选展示设置；没有重置用户数据。测试本身产生了宿主文本、复制内容和可能的输入学习记录。

## 环境和验证

- 手机：`127.0.0.1:5555`，1320×2856，x86_64 Phone 模拟器，触屏键盘为主。
- 电脑：`127.0.0.1:5557`，3120×2080，x86_64 2in1 模拟器，系统注入实体按键及点击浮动候选。
- 独立宿主：`com.example.shuangyuime.acceptance`，与输入法不同包名。网页验证使用设备上的 `com.huawei.hmos.browser`。URL输入框的英语旁路不用于中文例句测试。
- ArkTS：**707通过，0失败，0错误**，含新增共享启动器生命周期及跨控制器执行回归。[结果](arkts-final-result.txt)、[日志](arkts-launch-fix.log)。最后三处候选显示身份调整随后通过最终 Release 编译及上列设备标题复测；没有把这三处 UI 调整后的流程描述成又运行了一遍全量单测。
- Rust：`shuangpin-parser / sentence-decoder / code-table-runtime / ime-engine` 共 **374通过，0失败**。[日志](rust-tests.log)。本次没有改 Rust 或重新生成词库。
- 工坊：**10项集成检查通过**。[日志](editor-verify.log)。
- UI证据脚本：`node outputs/feedback-acceptance-20260911/verify-evidence.cjs`，**22条通过，0失败，3条手机浏览器完整页面检查未完成**。[机器结果](device-checks.json)。缩略图文字为人工视觉检查，不计为完整网页 UI 断言。
- 最终包 Release 构建、内容门禁、两台安全覆盖安装通过。[构建](build-final-device.log)、[门禁](verify-final-hap.log)、[安装](install-final.log)。

## 最终设备包

- [entry-device-release-signed.hap](entry-device-release-signed.hap)
- 版本：0.10.0 / 10000000；default 产品、release 编译模式、现有设备开发签名。
- 大小：93,241,241 bytes。
- SHA-256：`0D629AC8CF2A961CCC2F579DFF435C5DFFC1CECB43E98C3EB097B8C72AC947EB`。
- 本次未重新生成或发布 AGC 客户 APP；`artifacts/0.10.0/` 的历史正式 APP 不包含这次实测补修，不能与此设备验收 HAP 混用。
