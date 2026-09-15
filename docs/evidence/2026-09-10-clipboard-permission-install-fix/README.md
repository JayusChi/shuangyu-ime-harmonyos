# 三端 READ_PASTEBOARD 安装失败修复

日期：2026-09-10。Phone、Tablet、2in1 本地模拟器均已覆盖安装 0.10.0，启动与粘贴查形页切换通过。

## 原因与修复

新增 oix 查形功能在共用的 `entry/src/main/module.json5` 中声明了 `ohos.permission.READ_PASTEBOARD`。当前应用使用 normal APL，安装时不能授予该权限，导致 `9568289 / grant request permissions failed`。运行时请求权限不能解决发生在安装阶段的失败。

- 移除三端共用清单中的剪贴板读取权限、未使用的权限说明资源和运行时权限申请。包内仅保留 `ohos.permission.VIBRATE`。
- 光标前有汉字时保留直接查形；无法直接读取复制内容时进入「粘贴查形」页，由系统 `PasteButton` 点击成功后临时授权读取。拒绝授权时不读取、不打开网页；只取开头一个完整汉字并进行 URL 编码。
- 在默认与内部调试目标中注册新页面。修复手机窗口在 `loadContent` 前返回 `1300002` 时路由未初始化的问题，在页面加载完成后重新取得路由并处理待切换页面。
- 发布检查同时校验源码清单和 HAP 内清单，新增 `REL_INSTALL_CLIPBOARD_PERMISSION`；负例验证重新加入该权限会被拦截。

系统粘贴组件的临时授权行为依据本机 SDK 的 `openharmony/ets/component/paste_button.d.ts`。编译器仍可能对 `pasteboard.getData()` 给出通用权限提示；不能据此把受限权限重新加入清单。

## 验证

证据原件位于 `outputs/clipboard-permission-fix-20260910/`。

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| ArkTS 单元测试 | 705 通过，0 失败，0 错误 | `arkts-result.txt`、`arkts-tests.log` |
| 开发签名构建 default/debug | PASS | `build-development-final.log` |
| 发布签名构建 release/release | PASS | `build-release-final.log` |
| 正式 HAP 检查 | PASS | `verify-release-final.log` |
| 发布资源检查正负例（含剪贴板权限负例） | PASS | `resource-gate-tests.log` |
| Phone / 127.0.0.1:5555 | 覆盖安装、设置启动、已运行应用切换查形页 PASS | `install-three-devices-final.log`、`page-verification-final.log` |
| 2in1 / 127.0.0.1:5557 | 同上 | 同上 |
| Tablet / 127.0.0.1:5559 | 同上 | 同上 |

三端均为 `SIGNATURE_RESET=false`，未卸载或清除应用数据。最终包版本均为 0.10.0、APL 为 normal、声明权限仅为 VIBRATE；原有输入法选择保留。设备信息见 `devices-before.json`、`devices-after.json`，页面证据见 `*-shape-lookup-final.json/png`。

测试范围为三台本地模拟器及单元测试，没有执行物理设备验收或点击按钮读取用户现有剪贴板、访问真实查形网页；临时授权后的读取、空剪贴板、拒绝授权和 URL 路径由单元测试验证。

## 最终安装包

- 日常 DevEco 部署：`entry/build/default/outputs/default/entry-default-signed.hap`，SHA-256 `AB017D50592F5E5C5DD954069DE48D06EB76C6C67B412153D27128260146E560`。本次三端安装使用此包。
- 正式发布包：`entry/build/release/outputs/default/entry-default-signed.hap`，SHA-256 `2A9854B04B19877E3343C459D5A2983DE5B45A730D73761F61913009C3520591`。仅构建和校验，未发布。

两种签名继续使用既有独立产品配置。
