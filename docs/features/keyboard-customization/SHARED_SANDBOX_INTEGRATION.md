# 键盘模板共享沙箱接入

## 2026-09-14 后续修复与补验

基础模式设置增加共享文件只读恢复和同步，已读到主 App 的自定义皮肤、结构及展示偏好。三端原生浏览器完成颜色、五类图片、结构编辑和真实文件导出；App 导入、同 ID 结构更新、整机重启后保留均已补验。损坏包失败信息增加页面内持续提示。

市场发布签名包已尝试安装，但模拟器侧载没有生效的 `validDataGroupIds`，签名服务提示来源不受信；需要官方测试渠道继续验证。电脑 BASIC 面板仍报 VSync 29201 / Window 1001，重启和 onCreate 创建时机复验均失败。功能通过证据来自开发签名 release 构建，不能算市场发布签名验收通过。详见 [修复及补验记录](../../../outputs/keyboard-customization-fix-20260914/ACCEPTANCE.md)。

## 2026-09-14 授权接入与复验

华为开放能力已获批，新调试、发布 Profile 均含 `group.1516753898738609081`，包名及对应证书与本地签名链一致。两份 Profile 已归档到 `D:/CompanySecrets/HarmonyOS/shuangyuime/profile/`，文件名分别为 `shuangyuime_debug_shared_20260914Debug.p7b`、`shuangyuime_release_shared_20260914Release.p7b`，副本 SHA-256 校验一致，旧文件保留。本地 default/release 签名配置已切换到归档路径；输入法扩展 `dataGroupIds` 和运行时共享 ID 已配置，default/internalDebug/release 严格授权检查全部通过。

发布产品的双 ABI 原生库、ArkTS、HAP 签名构建及发布包检查已通过，见 [发布签名记录](../../../outputs/keyboard-customization-sharing-20260914/release/RELEASE.md)。该阶段尚未安装发布签名包；后续安装结果见上方补验记录。MatePad Edge 实机验收仍未完成。

授权后的设备验收发现并修复两处问题：共享结构异步加载或同 ID 替换时，ForEach 行标识没有变化导致默认布局残留；沙箱图片路径没有转换为 ArkUI 所需的 file URI，导致只显示底色。现以已加载结构内容变化递增渲染版本，并将图片路径转换为编码后的 file URI。

本次构建、设备及验收边界见 [2026-09-14 验收记录](../../../outputs/keyboard-customization-sharing-20260914/ACCEPTANCE.md)。下面保留 2026-09-09 的历史记录，不代表当前授权状态。

## 当前结论（2026-09-09）

代码已接入 `Context.getGroupDir()`，主 App 将结构、颜色配置和图片写入共享目录，输入法扩展从自己的共享目录挂载读取。旧版 `filesDir/keyboard-customization` 中的合法模板会在主 App 启动时自动迁移；迁移失败保留原文件。

**当前开发和发布构建使用的两份签名 profile 均未包含 `data-group-ids`。因此设备上的共享目录读写、实际自定义键盘显示仍未验收通过，不能按“已彻底修复”交付客户。** 当前构建会明确提示共享能力未开通，拒绝导入和选择不可访问的自定义模板，保留内置模板及原有导入文件。

同日后续复核：`user-lexicon` 源码中的重复定义已经清理，55 项 Rust 测试通过，x86_64 与 arm64-v8a 原生库及 Debug HAP 重新构建、签名通过。另修复构建结束时文件短暂被映射占用导致源码恢复失败的问题，增加有限重试；最终构建正常退出，原始源码恢复及临时目录清理均已确认。Rust 编译不再是阻塞项，剩余共享授权和授权后的设备验收。

这不是浏览器、压缩包或服务器问题。相同的 `filesDir` 路径文字不代表相同的底层文件目录；切换 EL2 或 ApplicationContext 也不能解除输入法独立沙箱隔离。共享小配置的 DataProxy 在当前版本单值默认限制为 4096 字节，不能代替最大 24 MB 的模板图片目录。

## 实现内容

- 主 App 负责创建共享模板目录、迁移旧包、校验压缩包并原子替换安装目录；解压临时文件仍放主 App 私有 cacheDir。
- 输入法扩展只获取共享目录并读取，不创建目录、不迁移、不删除，适配基础模式的共享沙箱只读要求。
- 共享目录异步就绪后，键盘重新读取最新设置并更新结构、皮肤和响应式调色板；组件销毁后的回调不会再更新界面。
- 不回退到扩展自己的 filesDir 读取导入包；共享不可用时，导入返回失败，设置页面显示原因，不能将旧模板标记为已应用。
- 主 App 保留迁移前的文件副本；已存在且有效的共享模板优先，避免覆盖较新的导入。删除模板同时删除旧副本，防止重新启动后再次迁移回来。
- 构建前校验运行时 ID、输入法扩展 dataGroupIds 和所选产品签名 profile 是否匹配。

## 启用所缺的授权

需由应用所有者取得华为签发的输入法共享 `data-group-id`，并重新下载包含该 ID 的开发、发布 profile。不能自行编造 ID，也不能直接编辑签名 profile 的内容。

官方依据：[输入法安全模式及共享沙箱说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ime-kit-security#section4219152220459)。本机 SDK 的 `application/Context.d.ts` 提供异步 `getGroupDir`，`toolchains/modulecheck/module.json` 定义扩展的 `dataGroupIds`。

拿到授权后，在项目根目录使用 DevEco 自带 Node 执行：

```powershell
$customizationNode = 'C:/Program Files/Huawei/DevEco Studio/tools/node/node.exe'
& $customizationNode scripts/configure-keyboard-customization-sharing.cjs --group-id '华为签发的实际ID' --profile '包含该ID的新profile.p7b'
```

脚本先检查 profile 中是否存在该 ID，再同时更新 `KeyboardCustomizationStorageConfig.ets` 和 `module.json5` 中输入法扩展的 `dataGroupIds`。脚本不会修改 profile、证书或密钥。接着将本机 `build-profile.json5` 中各构建产品的签名 profile 路径切换到对应新文件，再执行严格检查：

```powershell
& $customizationNode scripts/configure-keyboard-customization-sharing.cjs --check --product internalDebug --require-shared
& $customizationNode scripts/configure-keyboard-customization-sharing.cjs --check --product release --require-shared
```

未配置 ID 时普通构建允许继续，并打印功能未开通警告；严格检查会失败。配置了 ID 但扩展声明或当前产品签名不匹配时，普通构建也会失败，避免生成看似启用但无法访问共享目录的安装包。

## 验证及剩余验收

主机验证命令：

```powershell
& $customizationNode scripts/test-keyboard-customization-sharing.cjs
& $customizationNode output/playwright/test-customization-host.cjs
& scripts/build-hap.ps1 -SkipRust -BuildMode debug
```

存储测试模拟彼此隔离的 App/IME 私有目录和不同路径的共享挂载，验证真实仓库代码的导入、结构和颜色读取、图片字节一致、只读消费者、并发初始化、旧包迁移、不覆盖新版、删除防复活、损坏包拒绝和失败回滚。配置测试使用明确标注的未签名测试 JSON，不能作为设备授权文件。主机测试不能证明系统实际挂载和 ArkUI 图片渲染。

证据目录：`outputs/keyboard-customization-sharing-20260909/`。原始验收记录保留在 `EDITOR_ACCEPTANCE_20260909.md`。

本次结果：

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 存储契约测试 | 8 项通过 | `storage-tests.log` |
| 既有模板领域测试 | 13 项通过 | `domain-tests.log` |
| 最新源码的 ArkTS 编译 | 通过，`default@CompileArkTS`，39.865 秒 | `arkts-final.log` |
| 首次 Debug 完整构建与平板安装 | 通过，保留数据安装；用于下述缺授权分支检查 | `build-debug.log` |
| 平板缺授权提示、点击导入、选择旧结构 | 显示未开通共享提示；未打开文件选择器、未将旧结构改为已应用 | `tablet-authorization-required.png`、`tablet-selection-blocked.json` |
| 开发及发布配置检查 | 均提示未配置共享 ID；交付严格检查按预期拒绝 | `profile-check-*.log` |
| 首次尝试最终完整 HAP 重打包 | 当时被 `user-lexicon` 重复定义阻塞，保留原失败日志 | `build-debug-final.log` |
| 同日后续 Rust 复核 | 最新源码已无上述重复定义；29 项单元测试和 26 项集成测试通过 | `followup/user-lexicon-tests-final.log` |
| 同日后续完整 Debug HAP 构建 | x86_64、arm64-v8a 原生库重建，ArkTS 编译、签名及源码恢复完成，脚本退出码 0 | `followup/build-debug-final.log` |
| 后续 Debug 包平板安装 | 覆盖安装通过，保留应用数据，未重置签名 | `followup/install-tablet-final.log` |

最初平板截图来自首次完整编译版本；其后的逐模板状态提示细化已纳入后续成功构建的 Debug 包。安装结果与主机测试都不构成共享授权下的键盘显示验收。没有生成可承诺自定义模板正常生效的客户发布包。

只检查 ArkTS（不替代完整构建）的命令：

```powershell
& 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --no-daemon --mode module -p 'product=release' -p 'module=entry@default' -p 'buildMode=release' 'default@CompileArkTS'
```

取得授权并重新安装后，需要继续以下设备验收：

1. 手机上、平板上和电脑模拟器上从文件选择器导入浏览器导出的颜色包、结构包和五种图片槽位的皮肤包。
2. 在外部应用输入框弹出双羽输入法，确认结构换位、宽度、标签、颜色透明度及图片实际显示。
3. 基础模式和完整体验模式分别验证；基础模式不得依赖共享目录写入。
4. 验证旧模板自动迁移、同 ID 覆盖导入、正在运行的键盘刷新、关闭后重新弹出、输入法重启和设备重启。
5. MatePad Edge 实机暂不测试，遵照用户“实机先不管”的要求。
