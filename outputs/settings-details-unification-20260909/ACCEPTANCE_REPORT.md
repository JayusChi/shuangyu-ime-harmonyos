# 全部设置详情页统一验收

日期：2026-09-09。版本：0.9.0。

本次完成旧设置详情页与子页面的 UI、导航统一。手机使用逐级详情页；平板和电脑宽屏始终保留左侧分类，详情及其子页在右侧切换。

## 页面覆盖

| 入口 | 详情与子页 | 处理结果 |
| --- | --- | --- |
| 输入设置、候选设置、按键与反馈、帮助与关于 | 原有输入方案、布局、主题、候选位置、智能标点、模糊音、震动、长按、指南等全部详情 | 使用统一导航容器与详情标题栏 |
| 键盘与外观 → 键盘结构与皮肤 | 总览 → 键盘结构 / 键盘皮肤 / 字母键下滑符号 | 全部纳入同一导航栈，宽屏保持左栏；统一背景、卡片、行、间距和按钮 |
| 词库与个性化 → 我的词库 | 词条编辑、动作选择、管理与批量操作、文本导入导出、固定来源 | 同一详情容器；表单颜色适配主题，动作与按钮在窄屏换行，避免挤压 |
| 词库与个性化 → 自定义直通 | 上屏文字 / 网页 / 目录及对应表单 | 沿用原词库编辑状态和业务方法，统一界面与导航 |
| 词库与个性化 → 小鹤音形词库分类 | 分类列表、保存、重置、未保存退出确认 | 纳入同一导航栈，原确认流程也用于左侧分类切换和系统返回 |
| 原有独立页面路由 | `pages/KeyboardCustomization`、`pages/UserLexicon`、`pages/XiaoheYinxingCategoryManagerPage` | 保留原路由，通过兼容入口打开统一设置容器；直接打开词库也保留宽屏左栏 |

系统文件、目录选择器仍调用原生系统界面。未注册、没有设置入口引用的旧 `UserLexiconManagerPage.ets` 不属于当前安装包的可达设置页面，未引入或改写它的业务功能。

## 功能逻辑保护

在本轮修改前建立了 599 个文件的 SHA-256 基线。最终 593 个既有文件保持一致，仅修改 6 个 UI 文件，并新增公共详情组件及迁出的分类 UI 组件。

控制器、存储、设置模型、原生接口、键盘行为、Rust 引擎及路由清单均未改变。

对旧详情页的方法逐一比对：

- 键盘结构与皮肤：17 个方法原样保留，包括选择、包导入、删除确认、删除、下滑符号编辑、保存、导入与导出。
- 词库与直通：17 个方法原样保留，包括校验、保存、目录选择、批量操作、文本导入、来源管理与结果处理。
- 音形分类：9 个方法原样保留，包括分类映射、启停、保存、重置与统计；原未保存退出确认方法也完全一致。

导航方法、页面生命周期中的导航注册、UI 属性和视图构建按本次任务调整。词库的表单与批量操作继续共用原页面状态，保留选中词条、位置输入及导入文本之间的原关系。

证据：[preservation-result.json](preservation-result.json)、[verify-preservation.py](verify-preservation.py)、[source-baseline.json](source-baseline.json)。

## 模拟器验收

Phone、Tablet、2in1 三台模拟器均使用最终源码的开发签名包覆盖安装，未卸载、未重置签名、未清空应用数据。

| 验证项 | 结果 |
| --- | --- |
| 全部迁移页面与结构、皮肤、符号子页 | 三端通过；平板和电脑检测到左侧分类，详情区域位于其右侧 |
| 逐级返回 | 标题栏返回与系统返回通过；深层页面返回上一层详情 |
| 内置结构与皮肤选择 | 实际切换宽空格结构、柔和蓝皮肤，读取持久化值确认，再恢复原值 |
| 下滑符号 | 中英文切换、保存、导入文件选择器打开并取消通过 |
| 词库与直通 | 动作、网页和目录类型及对应字段可达；全部文本导入导出和固定来源按钮可达；导出到文本框调用通过 |
| 分类保存 | 切换分类、保存并恢复原值通过 |
| 未保存确认 | 手机返回取消、重置后系统返回确认退出通过；电脑点击其他左侧分类，取消留在原页、确认后切换通过 |
| 深色模式 | 手机结构皮肤总览、皮肤子页、直通表单、词库导入导出与来源界面截图复核通过 |
| 原词库直达入口 | 电脑通过 `entryPage=pages/UserLexicon` 打开词库后保持分栏，并能返回词库分类页 |
| 设置恢复 | 三台设备各 44 项设置，最终逐项与验收前基线一致 |
| 签名安装包 | release 构建及 HAP 资源校验通过 |

验证边界：没有执行覆盖导入、删除已有用户内容、清除学习记录或实际新增来源。模板共享未开通时的原限制和提示保留，未改变导入能力的业务条件。源码比对与模拟器操作共同用于确认迁移范围；本次没有重跑输入引擎的完整功能验收。

主要日志：[accept-phone.log](accept-phone.log)、[accept-tablet.log](accept-tablet.log)、[accept-computer.log](accept-computer.log)、[accept-phone-final.log](accept-phone-final.log)、[category-phone-result.txt](category-phone-result.txt)、[category-computer-result.txt](category-computer-result.txt)、[computer-final-result.txt](computer-final-result.txt)、[tablet-final-result.txt](tablet-final-result.txt)、[settings-restoration-result.txt](settings-restoration-result.txt)。平板切换方案后的首次 UI 定位遇到过渡帧，等待页面稳定后续验通过。

## 自动测试限制

本轮两次运行原有 ArkTS 测试，测试源码编译完成，但 SDK Previewer 均在创建 OpenGL 窗口时崩溃，堆栈包含 AMD `atio6axx` / `atig6pxx`、`wglChoosePixelFormat` 和 `glfwCreateWindow`。本轮没有生成新的测试结果，不能将上轮的 686 项通过报告算作本轮结果。未修改应用业务代码或系统显卡配置来绕过此问题。

证据：[arkts-tests.log](arkts-tests.log)、[arkts-tests-retry.log](arkts-tests-retry.log)、[arkts-previewer-first.log](arkts-previewer-first.log)、[arkts-previewer-retry.log](arkts-previewer-retry.log)。本轮可确认的验证结果为构建与安装包校验通过、源码及业务方法保护核对通过，以及上述三端模拟器验收通过。

## 最终截图

- [平板结构与皮肤总览](tablet/customization-final.png)
- [平板下滑符号子页](tablet/swipe-final.png)
- [平板音形分类](tablet/categories-final.png)
- [电脑皮肤子页](computer/skin-final.png)
- [电脑直接打开词库](computer/direct-entry-final.png)
- [手机结构子页](phone/structure-final.png)
- [手机深色皮肤子页](phone/skin-dark.png)
- [手机深色直通表单](phone/shortcuts-dark.png)
- [手机深色导入导出与来源管理](phone/words-transfer-sources-dark.png)

## 安装包

`entry/build/release/outputs/default/entry-default-signed.hap`

版本和包名不变：`0.9.0`、`com.corrosion.shuangyuime`。

大小：93,105,127 字节。

SHA-256：`CCF66A06893CD1FDF902D75F09D1056029B027DEFBB26933C508ECAF7C2ED3D5`

见 [release-gate.log](release-gate.log) 与 [install-final.log](install-final.log)。
