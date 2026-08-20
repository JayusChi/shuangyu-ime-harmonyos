# 阶段 12：直通控制与用户词库管理

日期：2026-08-10

## 完成范围

### 直通控制

封闭命令合同如下：

| action | target | 效果 |
| --- | --- | --- |
| `scheme.set` | `xiaohe` / `xiaohe-yinxing` | 切换方案 |
| `category.enable` | 八类之一 | 启用分类 |
| `category.disable` | 八类之一 | 禁用分类；`core` 拒绝 |
| `category.toggle` | 八类之一 | 切换分类；`core` 拒绝 |
| `category.all` | 空 | 启用全部分类 |
| `category.core` | 空 | 仅保留核心分类 |
| `status.get` | 空 | 返回当前方案和分类 |

命令行通过已导出的 `EntryAbility` Want 参数执行，例如：

```text
hdc shell aa start -a EntryAbility -b com.corrosion.shuangyuime -m entry --ps imeAction scheme.set --ps imeTarget xiaohe-yinxing
hdc shell aa start -a EntryAbility -b com.corrosion.shuangyuime -m entry --ps imeAction category.disable --ps imeTarget rare-character
hdc shell aa start -a EntryAbility -b com.corrosion.shuangyuime -m entry --ps imeAction category.all
hdc shell aa start -a EntryAbility -b com.corrosion.shuangyuime -m entry --ps imeAction status.get
```

实体键盘预设使用严格 `Ctrl+Alt+数字`，Logo 键参与时不触发：

| 快捷键 | 动作 |
| --- | --- |
| `Ctrl+Alt+1` / `2` | 小鹤双拼 / 小鹤音形 |
| `Ctrl+Alt+3` / `4` | 仅核心 / 全部分类 |
| `Ctrl+Alt+5` | 切换分类二级词库 |
| `Ctrl+Alt+6` | 切换一键二级 |
| `Ctrl+Alt+7` | 切换二键二级 |
| `Ctrl+Alt+8` | 切换生僻字 |
| `Ctrl+Alt+9` | 切换全码词 |
| `Ctrl+Alt+0` | 切换表外字 |

所有分类均可通过命令行和正式设置页独立控制；快捷键是高频预设，不改变宿主应用的其他 Ctrl/Alt 快捷键路由。

### 用户词库

正式设置页新增“用户词库”页面，支持：

- 新增或覆盖普通词、精确隐藏系统词、固顶、指定第 N 位；
- 搜索、多选、批量改为普通/隐藏/固顶/第 N 位、批量移除；
- 多行文本合并导入、覆盖导入和导出；
- 保存成功后当前引擎及其他输入法进程立即热重载，并在输入法进程冷启动时恢复。

页面复用设置窗口的系统/挖孔安全区，标题与返回按钮不会进入状态栏；外层 Scroll 和词条 List 均隐藏视觉滚动条，但保持触摸、鼠标和触控板滚动。

设置主页按产品反馈移除页头辅助说明、双拼方案辅助说明和用户学习辅助说明，保留对应标题与全部交互控件。

Rust 管理接口返回结构化文档、统计、物理行错误和稳定 revision。保存先完整解析，再用 revision CAS 和既有 `.tmp/.bak/.old` 原子流程落盘。revision 冲突会刷新最新内容并要求用户重试。双损坏或运行时无有效恢复来源时不替换当前内存快照。

设置 Ability 与 InputMethodExtensionAbility 使用独立进程和独立文件沙箱。主进程保存成功后，将规范化文本按 `900` 个 UTF-16 code unit 分块（每块不超过 DataProxy `4096 bytes` 上限），以唯一版本 URI 发布，全部块成功后最后发布 manifest，再回收上一版本分块。输入法进程读取完整 manifest 和全部分块，先通过同一 Native CAS 接口更新自己的沙箱副本，再热重载引擎。Common Event 只作为热更新唤醒信号，不承载批量词库正文；冷启动直接读取 manifest。因此大批量内容不会受单条事件/DataProxy 值上限影响，也不会读取到半发布版本。

输入法 onCreate 会立即注册 `inputStart/inputStop/keyboardShow/keyEvent` 等系统监听；到达初始化完成前的生命周期事件按同一初始化 Promise 顺序回放，物理按键在运行时未就绪前不消费，避免较快设备丢失首个输入会话。

## 跨层合同

- ArkTS interface version：`5`
- Rust ABI version：`5`
- engine version：`0.0.1-stage12`
- 新增 C ABI / Node-API：`reloadUserLexicon`、`loadUserLexicon`、`saveUserLexicon`
- `CompositionResult` 字段和输入候选排序合同不变。

## 验证

- Rust user-lexicon：`23/23 PASS`。
- Rust ime-engine lib：`42/42 PASS`。
- Rust ime-ffi：`29/29 PASS`，包含读取、CAS 保存、revision 冲突和运行时热重载真链路。
- ArkTS：`395/395 PASS`，包含直通解析/快捷键、批量编辑和离线分类持久化。
- Rust workspace tests、`cargo fmt --check`、全 workspace/target/feature Clippy `-D warnings`：PASS。
- x86_64 与 arm64-v8a Native Release：PASS。
- default unsigned Release HAP 与内容门禁：PASS，`37,984,852 bytes`，SHA-256 `42c92678ddeffde84ec2ea72f5a04203c95db2a474435ac87e5d38103daa36d9`。
- default signed Release HAP：PASS，`38,123,521 bytes`，SHA-256 `f2302e707882e6ebc3e30841382b80dde11db7c790b802f4ab25a3cb00f78c40`。
- HarmonyOS 6.1 / API 24 / x86_64 Phone `1320×2856`、2in1 `3120×2080`、Tablet `2880×1920`：真实 `aa` 命令、物理 `Ctrl+Alt+数字`、强停持久化、正式用户词库 UI、跨进程热重载和冷启动均 PASS。
- 三设备最终候选验收：输入 `ni` 后固顶词为第 1、普通用户词为第 2、`#3` 词严格位于第 3，系统词“你”被 `#删` 隐藏。证据见 `docs/evidence/2026-08-10-stage12-three-device/README.md`。
- Phone 用户词库页面 Release 视觉回归：标题安全区、无滚动条及手势滚动 PASS。
- Phone 设置主页 Release 视觉回归：三处指定辅助说明均不可见，标题和交互控件保持正常。

最终门禁数以本阶段完成时的 `CHANGELOG.md` 和 `PROJECT_STATE.md` 为准。
