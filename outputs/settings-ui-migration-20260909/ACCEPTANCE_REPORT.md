# 设置 UI 改版验收记录

日期：2026-09-09。版本：0.9.0。

本次按确认方案完成设置界面重组。现有设置、词库和直通入口逐项迁移；控制器、设置模型、存储与迁移、键盘行为、原生桥接和 Rust 输入引擎均未修改。

## 界面结果

- 首页分为输入设置、键盘与外观、候选设置、按键与反馈、词库与个性化、帮助与关于。
- 手机使用逐级页面；宽屏使用左侧分类、右侧详情。
- 用户学习移到“词库与个性化 → 学习输入习惯”，清除记录仍保留原确认流程。
- 移除原设置首页的空分类区域，以“小鹤音形词库分类”入口复用已有分类管理页；原分类、首选必选、保存、重置与未保存退出逻辑保持原样。
- 我的词库、自定义直通分别提供入口，使用同一个原词库编辑器；直通入口仅默认选中原有 DIRECT 操作。
- 固定与浮动候选字号分别展示，增加静态效果预览；高度、字号、音量增加便于精调的加减按钮，使用原设置方法与范围。
- 设置摘要随状态更新；浅色、深色与跟随系统保留。深色模式状态栏文字使用原生导航组件的显示样式匹配主题。

逐项功能位置与原调用对应关系见 [MIGRATION_MAP.md](MIGRATION_MAP.md)。

## 内部逻辑未修改的核对

改动前为 625 个源文件建立 SHA-256 基线。最终核对结果：622 个既有文件完全一致，仅以下三个既有 UI 文件改变，并新增一个 UI 组件文件。

| 文件 | 本次改动 |
| --- | --- |
| `SettingsPage.ets` | 设置导航、分组、展示绑定、说明文字、预览与原回调连接 |
| `UserLexiconPage.ets` | 进入直通时的初始 UI 选项及页面标题 |
| `XiaoheYinxingCategoryManagerPage.ets` | 两处标题文字 |
| 新增 `SettingsNavigationComponents.ets` | 设置导航行、单选列表、数值调整行与静态候选预览 |

校验脚本额外检查分类页与词库页：除上述明确允许的 UI 差异外，原内容保持一致。两套路由清单也与基线一致。原主设置页 20 个非分类修改方法继续调用原控制器；分类操作使用原分类管理页。

证据：[ui-scope-result.json](ui-scope-result.json)、[verify-ui-scope.py](verify-ui-scope.py)、[source-baseline.json](source-baseline.json)。此基线用于区分本次 UI 改版与工作区中此前已经存在的修改。

## 验证结果

| 验证项 | 结果与覆盖范围 |
| --- | --- |
| 原有 ArkTS 测试 | 686 项通过，失败 0、错误 0、忽略 0 |
| Phone 模拟器 | 五种键盘方案、三种设备使用方式、音形切分、全拼纠错、模糊音入口、关联词、AI 入口、智能标点时间选项通过 |
| 显示与反馈设置 | 候选位置、两套独立字号、键盘高度、底部工具栏、三种主题、四档震动、四档长按时间、声音开关和音量调整通过 |
| 词库与个性化 | 学习开关、清除确认后取消、分类启停并保存、重置预览后放弃更改通过；词库、直通、导入导出与固定来源管理入口可达 |
| 自定义直通 | 进入时选中原 DIRECT 操作；文字、网页和目录类型以及对应输入控件可达 |
| 2in1 模拟器 | 分栏导航、候选控件、分类、直通、词库、皮肤结构、帮助入口与返回操作通过 |
| 最终显示复核 | 手机浅色首页、候选页、深色首页及状态栏，2in1 分栏页面截图复核通过 |
| 设置恢复 | Phone 与 2in1 各 44 个持久化设置，最终逐项与验收前基线一致；2in1 恢复原 500 毫秒后重启再次确认保留 |
| 安装 | 两台模拟器使用开发签名包覆盖安装成功，`SIGNATURE_RESET=false`，未卸载或清空应用数据 |
| 交付构建 | release 构建成功，签名 HAP 资源校验通过 |

模拟器安装包与交付包使用同一份最终业务源码；模拟器使用开发签名产品构建，交付包使用 release 产品构建。最后的 UI 显示微调后再次完成构建和显示验证；686 项测试在本轮迁移过程中完成。

验证边界：AI 的原服务可用性限制保留；没有调用云端 AI，也没有执行实际清除学习记录、覆盖导入或删除用户词库。上述数据操作复用原实现，验证入口及确认流程。本次没有重新跑此前输入行为的整套验收，也没有重跑 Rust 测试；输入引擎及其调用逻辑与本次改版前一致。

主要日志：[arkts-test-result.txt](arkts-test-result.txt)、[accept-phone-input-final.log](accept-phone-input-final.log)、[accept-phone-display.log](accept-phone-display.log)、[accept-phone-finish.log](accept-phone-finish.log)、[accept-phone-lexicon-rest.log](accept-phone-lexicon-rest.log)、[accept-computer-navigation-final.log](accept-computer-navigation-final.log)、[settings-restoration-result.txt](settings-restoration-result.txt)、[install-statusbar.log](install-statusbar.log)、[release-gate-statusbar.log](release-gate-statusbar.log)。显示、反馈和词库检查由连续日志合并覆盖。

## 最终截图

- [手机设置首页](phone/home-final.png)
- [词库与个性化](phone/lexicon-final.png)
- [候选设置](phone/candidates-final.png)
- [按键与反馈](phone/feedback-final.png)
- [深色模式及状态栏](phone/dark-home-native.png)
- [2in1 分栏界面](computer/split-final.png)
- [自定义直通](computer/shortcuts.png)

## 安装包

路径：`entry/build/release/outputs/default/entry-default-signed.hap`

大小：93,085,590 字节。

SHA-256：`F9FD3CF102A903C7DBA6F3489978D2131F14FE3120054412A8821FB7C5117FBE`

包名和版本保持原样：`com.corrosion.shuangyuime`，`0.9.0`。
