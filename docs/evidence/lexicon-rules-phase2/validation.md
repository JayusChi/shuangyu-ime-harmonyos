# 词库规则增强第二阶段验证记录

日期：2026-07-14  
环境：Windows 11、PowerShell、Rust workspace、DevEco Studio OpenHarmony SDK、
x86_64 HarmonyOS API 24 模拟器

## 结论

第二阶段全部完成。用户词库解析、四类硬规则、确定性合并、原子保存/恢复、
引擎/FFI/ArkTS 可选路径接入、双 ABI、Release HAP 与 x86_64 模拟器正式输入
链路均已验证。针对 HDC 与普通 UIAbility 不能写 IME 扩展独立沙箱的问题，
验收时由扩展自身在真实 `InputMethodExtensionContext.filesDir` 建立临时规则文件；
四规则、普通候选提交、进程重启保留和空文件恢复全部 PASS。验收写入器随后
从源码移除，最终 Release HAP 不含用户 fixture 或该写入器。

## 自动化总门禁

执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-lexicon-rules-phase2.ps1
```

结果：`LEXICON_RULES_PHASE2_VERIFY_RESULT=PASS`

该脚本覆盖：

- `cargo fmt --check`、workspace check/clippy/test；
- `user-lexicon` 解析、重复覆盖、硬规则、精确删除后的前缀回退、持久化、
  崩溃恢复、并发保存和确定性字节；
- `ime-engine` 硬规则晚于学习软排序、早于分页，自定义候选可提交；
- FFI 可选 `userLexiconPath` 与旧配置兼容；
- CLI `validate/import` 成功与非法标记失败码；
- 第一阶段码表顺序与生产词库重建；
- ArkTS 单元测试、x86_64/arm64-v8a Native 构建；
- Release HAP 构建、元数据/资源检查以及用户 fixture 禁止入包。

关键结果：

| 项目 | 结果 |
| --- | --- |
| 用户词库专项测试 | PASS；含新增精确删除后长前缀回退用例 |
| 引擎覆盖层集成测试 | 4/4 PASS |
| FFI 配置专项 | 17/17 PASS |
| 生产词库 | 3,734,484 bytes；SHA-256 `765E2B0BD90244192A4C1BB6B2EC501ED28E0DBD731CBAB4C326534F091ECA10` |
| 第一阶段确定性 fixture | 两次均 496 bytes；SHA-256 `13610B57B8A1BEB1EE12643552DC5873EE17F8BC9DCB66997D824D37F527B50C` |
| x86_64 Native 静态库 | 24,439,108 bytes；SHA-256 `3F802E11EDB283DA70611FFDD9DC9ED3ECA7EA847EB94459A191401A1619CCEE` |
| arm64-v8a Native 静态库 | 25,000,580 bytes；SHA-256 `1736B013E296B9348EE0A06746EBECA2CFF4707263E48C3C3D2EE9C3CE654E62` |
| Release HAP | 10,979,174 bytes；SHA-256 `2752A4762D075FD6CC44FFDB786562CADFE23FCAEBA979DE3C24461CDAE5503F` |
| 用户词库 fixture 入 HAP | 0 |
| x86_64 模拟器四规则/重启/空文件恢复 | PASS |

完整转录：`verify-phase2.log`。

## CLI 冒烟

有效 fixture 的 `validate`、`import` 和导入产物二次 `validate` 均成功，汇总
为 accepted/effective 4，普通、删除、固顶、指定位置各 1 条。非法多标记
fixture 返回退出码 1，并报告路径、物理行号、`field=marker` 与明确原因，
未回显整行用户内容。

## 模拟器执行记录

目标：`127.0.0.1:5555`，包名：`com.example.harmonyos_input`。

已执行：

1. 构建、安装 Debug HAP，清理应用数据并启用/切换本输入法；
2. 由 `InputMethodExtensionAbility` 验收写入器在其真实 `filesDir` 创建：
   `自定义词<TAB>ni`、`你<TAB>ni#删`、`泥<TAB>ni#固`、`尼<TAB>ni#2`；
3. 打开 Debug 验收页普通中文输入框，在正式键盘输入 `ni`；
4. 断言候选全局顺序为“泥、尼、自定义词、拟…”，即 `#固` 第 1、`#2`
   第 2，“你”被精确删除；点击“自定义词”后真实 TextInput 内容变为该词；
5. 强停并重启应用进程，不重写已存在规则文件，再次输入 `ni`，四规则顺序
   与删除结果保持；
6. 将同一路径截断为空文件并重建引擎，再次输入 `ni`，系统“你”恢复，
   “自定义词”消失，泥/尼不再占据受保护位置；
7. 移除验收写入器，重跑全量第二阶段门禁并重新构建 Release HAP。
8. 扫描 Release 编译字节无验收字符串后，将干净 Release HAP 覆盖安装回同一
   模拟器；最终设置页布局不含 Debug 验收入口或验收自定义词。

结果：`PHASE2_OVERLAY_AND_RESTART_RESULT=PASS`、
`PHASE2_EMPTY_RESTORE_RESULT=PASS`。布局树和截图位于 `device/`，摘要转录为
`device/phase2_device_acceptance.log`。该方法只负责把已知验收数据送入此前
无法由 HDC 到达的真实扩展沙箱；解析、候选生成、分页、点击提交与重启加载
仍全部经过正式 `ArkTS -> C++ Node-API -> Rust C ABI -> ime-engine` 链路。

## 边界检查

- `.git` 目录在本工作区为空，无法执行 `git status`/`git diff`；本轮使用
  源码残留扫描、构建产物哈希、设备布局/截图与完整自动化转录留证。
- 未新增第三方依赖、权限、网络能力、管理 UI 或文件选择器。
- 验收写入器及其 fixture 已从最终源码移除，Release HAP 内容检查确认用户
  fixture 数量为 0。
- C ABI/Node-API 函数签名和 interface/ABI version 保持 2。
- `production.lex`、系统词条 ID、用户模型格式及正式默认排序未改变。
