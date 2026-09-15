# 手机、电脑模拟器九项反馈验收（2026-09-14）

**结论：九项需求的模拟器验收通过。第1项在本轮实际复现了慢速下滑误删正文，补修后复测通过。** 实体键盘项目采用鸿蒙系统 `uitest keyEvent` 注入，触屏项目点击/滑动实际键盘；没有将主机单测作为设备操作证据。

| 需求 | 验收结果 |
| --- | --- |
| 1. 固定候选时下滑回删 | 手机3次、电脑2次慢滑：已有正文“你”，输入 `ni` 后下滑，只取消候选，正文保留。空组合下滑仍删行，后续点按和实体 Backspace 正常。[手机](phone/final-swipe-1-after.png)、[电脑](computer/final-swipe-1-after.png) |
| 2. 上档符号右边距 | 两端设置页有调整项，默认10 vp。10→11 vp 后数字“1”实测向左移动：手机3 px，电脑1 px；恢复10后回到原位。[像素量测](appearance-measurements.json) |
| 3. 屏幕自适应默认字号及增减 | 手机1320×2856、密度3.5，默认13号；电脑3120×2080、密度1.9，默认24号。增加1号后 Q 文本高度手机53→57 px、电脑53→56 px；恢复默认均回到53 px。[手机增大](phone/final-font-plus-keyboard.png)、[电脑增大](computer/final-font-plus-keyboard.png) |
| 4. 回车上屏编码 | 两端虚拟回车和实体 Enter 均提交原始编码，未选汉字候选；已有正文保留。[手机](phone/final-virtual-enter-after.png)、[电脑](computer/final-virtual-enter-after.png) |
| 5. 实体 `[` / `]` 翻页 | 输入 `ui`，第一页首选“是”，`]` 后首选“浉”，`[` 回到“是”；正文不插入括号。随后回车上屏 `ui`。[手机下一页](phone/final-paging-next.png)、[电脑下一页](computer/final-paging-next.png) |
| 6. 浮动候选高度变化、收窄 | 两端 `k → kn → 回删到 k` 行高不变，回删不收窄，文字边界完整位于卡片内；点选“可”后正常上屏并隐藏窗口。小鹤双拼的多候选序列也保持宽高。[手机](phone/final-yinxing-floating-kn.png)、[电脑](computer/final-yinxing-floating-kn.png) |
| 7. 浮动候选美化、阴影 | 实际截图确认白色圆角卡片、灰色首选底色、边框和柔和阴影；阴影没有被窗口边缘裁掉。截图同上，视觉判断另经人工检查。 |
| 8. `hfyzxiwh` 排序 | 两端首选“很有希望”，空格上屏正确。本轮未改词库或整句评分。[手机](phone/sentence-hfyzxiwh.png)、[电脑](computer/sentence-retry.png) |
| 9. 句中固定 `up=双拼` | 两端通过“我的词库”实际新增“固顶”规则，`woysupuurufa` 首选并上屏“我用双拼输入法”。手机规则跨本轮覆盖安装/进程重启仍有效；测试结束移除两端临时规则。[手机](phone/final-fixed-middle.png)、[电脑](computer/final-fixed-middle.png) |

最终包小鹤音形浮动卡片量测（像素）：

| 设备 | k | kn | 回删到 k |
| --- | --- | --- | --- |
| 手机，虚拟键盘 | 718×196 | 812×196 | 812×196 |
| 电脑，实体键盘模式 | 391×108 | 442×108 | 442×108 |

## 本轮补修

原包在手机慢滑时，手指达到18 vp下滑阈值之前，300 ms长按计时器已经启动连删，可能从编码继续删到正文。快速滑动能通过，原有只调用控制器动作的测试没有覆盖这个时间关系。

现在检测到6 vp且以竖向为主的移动时，先停止长按和连删计时器，保持等待完整上下滑阈值；轻微手抖仍可正常长按。另在键盘根持有的删除控制器中保留一次点击拦截，防止候选清空、Shift/Esc行重建时，同一手势的尾随点击落到新回删键上。新的按下会重新允许正常回删。

新增4项回归覆盖慢滑与连删互斥、手抖长按、组件重建后的尾随点击及下一次点按。修改前文件在 `before/`，本轮仅修改相关ArkTS手势/删除组件和测试，未改Rust引擎。

## 检查与产物

- ArkTS：**748通过，0失败/错误/忽略**。[结果](arkts-result.txt)、[日志](arkts-tests-final.log)。
- 最终UI证据自动检查：**31通过，0失败**，覆盖表中的关键行为、文本、尺寸及临时词条移除。[机器结果](verification.json)、[复核脚本](verify-evidence.cjs)。阴影视觉检查单独记录，不算作自动像素断言。
- 两端最终开发签名Release包覆盖安装成功，`SIGNATURE_RESET=false`；正式Release HAP构建及资源门禁通过。[安装](install-final.log)、[正式门禁](release-verify-final.log)、[包身份](packages.json)。
- 开发验收包：`device-final-signed.hap`，93,338,881 bytes，SHA-256 `76D085213AB5F805CB1DDE6FE5F10491F7BBE4279D58253253FB97497197793E`。
- 正式签名HAP：`entry/build/release/outputs/default/entry-default-signed.hap`，93,338,611 bytes，SHA-256 `BDFE9196B990020F7C5608565020A04C1394EF8ECC0CE220ABAF82D046109204`。版本保持0.11.0；开发/正式签名包不是相同字节。本轮没有重建客户APP或发布到AGC。

主机测试针对新手势补修重新运行；此前双拼Rust 326项结果见9月14日双拼专项记录，本轮没有把旧记录算成新运行。历史失败/调试截图保留：包含实际慢滑缺陷、未等界面就绪、双拼方案误用音形候选断言以及大小写不敏感匹配误把字母N当编码n等验收脚本问题；上表及 `verification.json` 引用的是复核后的证据。

## 环境与恢复

手机：`127.0.0.1:5555`，Phone模拟器；电脑：`127.0.0.1:5557`，MateBook Pro / 2in1模拟器。宿主为独立包 `com.example.shuangyuime.acceptance` 的聊天输入框。真实USB/蓝牙键盘、客户应用及平板模拟器没有新增实测。

手机47项设置与测试前完全一致。电脑的字号、边距、输入方案、实体键盘模式等已恢复：旧设置版本23升级24，并新增默认右边距10；候选位置旧兼容值`auto`变为设置页可选的`bar`，实体模式仍自动使用浮动候选，其余44个原有字段一致。**未声称电脑设置逐字完全一致。** [恢复核对](settings-restoration.json)。两端个人词库恢复为空，未清学习记录或应用数据；验收宿主保留测试文字。
