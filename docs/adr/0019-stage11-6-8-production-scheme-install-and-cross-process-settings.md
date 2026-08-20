# ADR 0019：阶段 11.6.8 正式方案安装与跨进程设置

状态：接受（2026-07-27）。

## 背景

HarmonyOS 设置 Ability 与 InputMethodExtensionAbility 分属
`com.corrosion.shuangyuime` 和 `com.corrosion.shuangyuime:inputMethod` 进程。复验发现旧实现只在设置进程安装正式 bundle 并更新本进程 Native handle；输入法进程读取到隔离的旧 Preferences 后仍使用 `xiaohe`。因此设置页虽然显示“小鹤音形”，独立 TextInput 实际仍走小鹤双拼。

## 决策

1. 主进程 Preferences 是设置的 canonical 持久化存储。
2. 主进程每次成功持久化后，把 schema 2 的规范化快照发布到本包
   `SHARED_CONFIG` DataProxy；输入法进程启动时优先读取该快照。
3. 输入法进程不写 canonical Preferences；DataProxy 不可用时只读本进程 Preferences 作为兼容回退。
4. 主进程保存采用事务语义：Preferences 或共享快照任一步失败，恢复上一个规范化快照，不发布新的 `SettingsStore` 状态。
5. 切换到 `xiaohe-yinxing` 时先原子安装并校验正式 bundle，再创建带正式路径的新 Native handle；成功后才交换 handle、保存设置并广播。任何失败保留旧 handle、旧持久化值和旧 UI 选择。
6. 新 handle 继承当前配置、用户词库路径、用户学习开关和用户模型；旧 handle 只在交换成功后销毁。
7. 输入法冷启动先创建安全的 `xiaohe` handle，设置快照就绪后再安装/校验并切换正式方案；fixture 永远不是生产回退。
8. bundle 写入应用 EL2 沙箱，使用版本化目标和安装器自有 `.tmp`；只清理精确属于安装器的临时文件，相同版本且哈希正确时复用。
9. Release HAP 对正式 bundle 同时校验冻结大小和 SHA-256；仅扩展名或大小相同不能通过门禁。

## 后果

- 两进程看到相同的规范化方案和分类设置，强停/冷启动后仍一致。
- 设置页不会先显示成功再异步失败；Native、文件与持久化失败均回到可用的 `xiaohe`。
- interface/ABI 仍为 4，设置 schema 仍为 2；没有把业务决策移入 C++。
- 正式 bundle 进入批准的 Release rawfile 白名单；原始 TXT/INI、fixture、审计材料、凭据和网络权限继续被拒绝。
- ARM64 物理真机和全量发布性能仍由 11.6.9 验收。
