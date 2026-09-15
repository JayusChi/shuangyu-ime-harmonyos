# 2026-09-14 设置修复与三端补验

## 结论与边界

基础模式读默认设置的问题已修复；手机、电脑、平板原生浏览器的颜色、图片、结构、导出及同 ID 结构更新已通过。三台模拟器整机重启后，自定义图片皮肤和更新结构仍生效。电脑基础模式面板创建仍失败，发布签名包的受信运行验收也仍被分发方式阻塞，不能宣布四项全部完成。

用户已明确授权清空三台模拟器中的双羽输入法数据。先按授权卸载调试签名并安装市场发布签名包；发现系统未承认其 Profile 授权后，恢复同一修复源码的开发签名包继续功能验收。以下功能截图来自开发签名、release 构建模式，不能代替市场发布签名运行证据。

| 设备 | HDC 地址 | 环境 | 功能回归模式 |
| --- | --- | --- | --- |
| 手机 | 127.0.0.1:5555 | HarmonyOS 6.1.1.125 模拟器 | FULL |
| 电脑 | 127.0.0.1:5557 | HarmonyOS 6.1.1.125 2in1 模拟器 | FULL；另测 BASIC |
| 平板 | 127.0.0.1:5559 | HarmonyOS 6.1.1.125 模拟器 | FULL |

MatePad Edge 实机不在本次范围。

## 修复内容

1. BASIC 中 DataProxy 和公共事件被系统限制。原逻辑回退到 IME 私有 Preferences，与主 App 隔离，读取成默认值。新增 `SharedSettingsFile`：主 App 写入共享组内的设置快照，使用临时文件、fsync、原子替换；IME 只读。读取校验大小及结构，无效文件不参与设置恢复。
2. BASIC 改用共享文件轮询同步，避免调用被禁止的公共事件订阅；销毁时停掉轮询，并阻止异步初始化结束后重新订阅。FULL 保留原同步路径。
3. 损坏模板导入失败时增加页面内持续错误信息，补足文件选择器退出时短暂 Toast 可能不可见的问题；导入失败不改变当前模板。
4. 安装脚本新增设备端 `validDataGroupIds` 校验，拒绝将“声明了共享组、但授权没有生效”的安装标为通过。

## 原生 HTML 编辑器回归

使用设备自带华为浏览器运行仓库 `standalone.html`，通过本机 HDC 转发提供相同文件。浏览器控制经 CDP 操作真实页面，不是桌面浏览器尺寸模拟。五个图片输入槽通过浏览器文件输入 API 注入本地测试图片，本轮未逐一验收系统相册选择器。导出经过各端真实浏览器下载并从设备取回。

| 场景 | 手机 | 电脑 | 平板 | 核对内容 |
| --- | --- | --- | --- | --- |
| 颜色修改与皮肤导出 | PASS | PASS | PASS | 樱花粉预设、面板 `#12345680`、字母底色 `#FFFAFC` |
| 五类图片替换与导出 | PASS | PASS | PASS | 面板、字母、功能、空格、回车；逐字节核对图片 |
| 结构编辑与导出 | PASS | PASS | PASS | W/Q 交换、空格宽 6.3、设备名标签 |
| 同 ID 更新包 | PASS | PASS | PASS | 原 ID 不变，空格宽 5.9、标签 UPDATED |
| 同 ID 图片路径下替换图片字节 | PASS | PASS | 未完成 | 平板宿主进程退出，恢复启动崩溃，详见 FINAL_CHECKS.md |
| 原生 App 导入及跨应用键盘 | PASS | PASS | PASS | 图片皮肤、W/Q、新空格标签在独立验收 App 中显示 |
| 整机重启恢复 | PASS | PASS | PASS | `hdc target boot`，断线重连后保留图片和 UPDATED |
| 损坏包拒绝与持续错误提示 | PASS | PASS | PASS | 非 ZIP 文件报 900003，原皮肤仍选中 |

12 个真实导出包及 SHA-256 见 `fixtures/` 和 `native-export-results.json`。核验命令：

```powershell
node outputs/keyboard-customization-fix-20260914/verify-native-exports.cjs
```

重启前后截图分别为 `device-evidence/<设备地址>/*-updated-before-reboot.png`、`*-post-reboot-ready.png`；对应 UI 树可检索 `UPDATED`、W/Q。重启后日志为 `phone-post-reboot.log`、`pc-post-reboot.log`、`tablet-post-reboot.log`。读取 `/proc` 的 boot_id/uptime 被系统拒绝，因此不将该读取作为重启证据。

## 电脑 BASIC 面板剩余问题

修复后日志明确读取到 `keyboardStructureId=native.pc.layout`、`keyboardSkinId=native.pc.images`、`inputPresentationPreference=TOUCH`，且启用只读共享文件订阅。证据：`pc-trusted-basic.log`、`pc-oncreate-probe.log`。

面板失败链：VSync `GetReceiveFd Failed, res = 29201` → Window `CreateWindowWithSession error:1001` → IME `create window failed:1001` → JS `code:1, error is out of definition`。当前扩展上下文和 `SOFT_KEYBOARD/FLG_FIXED` 参数有效；FULL 可以创建并显示。重启后仍复现。在官方建议的 onCreate 阶段直接创建同一面板也失败，见 `BASIC_ONCREATE_PROBE failed`。诊断代码不应进入交付包。

证据指向当前模拟器 BASIC 进程的系统图形/窗口调用失败，尚不能仅凭日志断言厂商根因。下一步需要在受支持真机/其他系统镜像复现并提交系统日志，不能以强制切换 FULL 或放宽系统限制充当修复。

官方说明 BASIC 允许 IME、ArkUI 和窗口能力，并建议在 onCreate 中创建面板：[输入法扩展文档](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-inputmethod-extension-ability)。

## 发布签名运行验收剩余问题

市场发布 HAP 的签名验证通过，提取 Profile 包含 release 类型、正确 appIdentifier 及共享组。三端侧载的 `bm install` 表面成功，但设备 `bm dump` 中 appIdentifier 为空、有效共享组为空，运行时 `getGroupDir` 不可用。

电脑安装时签名服务日志记录：`untrusted source app with release profile distributionType: 1`、`VerifyProfileInfo failed`、`APP source is not trusted`、`UnSignatureHap checkIgnore`。证据：`reinstall-verifier.log`、`pc-release-bundle.json`、`install-existing-release-all.log`。安装记录中旧的 RESULT=PASS 仅代表旧脚本检查，已被上述设备授权证据推翻。新增安装门禁会拒绝这类结果，开发签名安装已实际通过新门禁。

应通过与发布证书匹配的 AppGallery Connect 邀测/公测渠道安装后再验收。没有修改 Profile、跳过系统签名校验或发布至外部测试渠道。官方依据：[发布证书侧载限制](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-package-structure-65)、[AGC 测试服务](https://developer.huawei.com/consumer/cn/agconnect/open-test/)。

## 主机验证

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 共享设置与 BASIC 只读同步 | 5 项 PASS | settings-tests-final.log |
| 模板共享存储、损坏拒绝、替换回滚 | 8 项 PASS | storage-tests.log |
| 模板领域规则 | 14 项 PASS | domain-tests.log |
| 编辑器格式/包集成 | 10 项 PASS | editor-package-tests.log |
| 安装授权正反例 | PASS | installed-sharing-tests.log |
| 原生导出内容解析 | 12 包 PASS | native-export-results.json |

本次未改动 Rust 引擎；构建使用已完成的双 ABI 原生库，重新编译 ArkTS 并签名。最终构建、包哈希及错误提示复验补充在同目录的 RELEASE.md 和 FINAL_CHECKS.md。
