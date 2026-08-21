# 直通编码功能实现进度

本文档记录6个直通编码相关功能的实现进度。

## 功能实现状态

### ✅ 功能1：重复上屏 (已完成)

**实现内容**：
- ✅ 创建 `CommitHistoryManager.ets` - 上屏历史管理器
- ✅ 创建 `UndoCommitManager.ets` - 撤销上屏管理器(为功能2准备)
- ✅ 集成到 `InputSessionController.ets`
  - 添加历史管理器实例
  - 在提交点记录历史
  - 添加 `repeatLastCommit()` 方法
- ✅ 添加键盘动作类型 `REPEAT_LAST_COMMIT` 到 `KeyboardAction.ets`
- ✅ 在 `KeyboardController.ets` 中处理动作
- ✅ 创建单元测试 `CommitHistoryManager.test.ets`

**触发方式**：
- 通过特殊编码触发（建议用 `cfsb` = 重复上屏）
- 在码表或引擎中配置，返回 `REPEAT_LAST_COMMIT` 动作

**已记录上屏历史的位置**：
- 自动提交时（`insertLetter` 中的 `result.commitText`）
- 候选词提交时（`commitCandidate` 中的 `candidate.text`）

---

### ✅ 功能2：撤销上屏 (已完成)

**实现内容**：
- ✅ 使用 `UndoCommitManager.ets`（在功能1中已创建）
- ✅ 集成到 `InputSessionController.ets`
  - 初始化撤销管理器
  - 在提交点记录可撤销状态
  - 添加 `undoLastCommit()` 方法
  - 添加 `deleteWithVerification()` 验证删除方法
- ✅ 添加键盘动作类型 `UNDO_LAST_COMMIT` 到 `KeyboardAction.ets`
- ✅ 在 `KeyboardController.ets` 中处理动作
- ✅ 创建单元测试 `UndoCommitManager.test.ets`

**触发方式**：
- 通过特殊编码触发（建议用 `cxsb` = 撤销上屏）

**技术限制**：
- 只能删除光标前的文本
- 假设用户没有移动光标
- 5秒时间窗口限制
- 表情符号可能导致长度计算错误

---

### ✅ 功能3：成对符号光标居中 (已完成-仅文档)

**状态**：✅ 功能已在 `ProtocolActionExecutor.ets` 中完整实现

**实现内容**：
- ✅ 创建使用文档 `docs/features/direct-control/PAIR_INSERTION_GUIDE.md`

**说明**：
该功能已经完整实现，当引擎返回 `INSERT_PAIR` 协议动作时自动处理。无需修改代码。

---

### ✅ 功能4：模拟End键 (已完成-技术限制说明)

**状态**：❌ 技术上无法实现

**实现内容**：
- ✅ 创建技术限制说明文档 `docs/features/direct-control/KEY_SIMULATION_LIMITATION.md`

**说明**：
HarmonyOS InputMethodEngine API 不支持模拟物理按键。这是操作系统 API 的固有限制。

---

### ⏳ 功能5：分类词库启用/关闭 (待实现)

**状态**：后端API已实现，需要添加用户界面

**待实现内容**：
- [ ] 扩展 `SettingsController.ets`
  - 添加 `getCodeTableCategories()` 方法
  - 添加 `getEnabledCategoryIds()` 方法
  - 添加 `toggleCategory()` 方法
- [ ] 创建 `CodeTableCategorySettings.ets` 页面
- [ ] 在设置页面添加入口
- [ ] 更新 `SettingsRepository.ets` 持久化设置
- [ ] 更新 `ImeSettings.ets` 数据模型

---

### ⏳ 功能6：用户词库导入增强 (待实现)

**状态**：基础功能已实现，需要增强自动导入和UI

**待实现内容**：
- [ ] 创建 `UserLexiconImportManager.ets`
- [ ] 在 `InputMethodLifecycleDispatcher.ets` 中集成自动加载
- [ ] 扩展词库管理页面 `UserLexiconManagerPage.ets`

---

## 已创建的文件

### 应用层代码
- `entry/src/main/ets/application/CommitHistoryManager.ets`
- `entry/src/main/ets/application/UndoCommitManager.ets`

### 领域模型
- `entry/src/main/ets/domain/keyboard/KeyboardAction.ets` (已修改)

### 应用控制器
- `entry/src/main/ets/application/InputSessionController.ets` (已修改)
- `entry/src/main/ets/application/KeyboardController.ets` (已修改)

### 文档
- `docs/features/direct-control/PAIR_INSERTION_GUIDE.md`
- `docs/features/direct-control/KEY_SIMULATION_LIMITATION.md`

### 测试
- `entry/src/test/CommitHistoryManager.test.ets`
- `entry/src/test/UndoCommitManager.test.ets`

---

## 下一步工作

1. **功能5：分类词库UI** - 实现用户界面，让用户可以启用/禁用词库分类
2. **功能6：词库导入增强** - 实现自动扫描和导入，优化用户体验
3. **集成测试** - 测试重复上屏和撤销上屏功能
4. **引擎侧集成** - 在Rust引擎中配置触发编码

---

## 使用说明

### 重复上屏

在引擎中配置触发编码，当用户输入 `cfsb` 时，返回以下候选：

```typescript
{
  text: "重复上屏",
  source: "functional",
  // 配置为触发 REPEAT_LAST_COMMIT 动作
}
```

### 撤销上屏

在引擎中配置触发编码，当用户输入 `cxsb` 时，返回以下候选：

```typescript
{
  text: "撤销上屏",
  source: "functional",
  // 配置为触发 UNDO_LAST_COMMIT 动作
}
```

---

## 注意事项

1. **历史记录管理**：
   - 最多保留10条历史记录
   - 会话结束时自动清空

2. **撤销时间限制**：
   - 只能撤销5秒内的上屏
   - 用户输入其他内容后撤销状态失效

3. **线程安全**：
   - 所有操作都在主线程序列化执行
   - 通过 `InputSessionGeneration` 保证一致性

4. **错误处理**：
   - 所有可能失败的操作都有 try-catch 包裹
   - 使用 Logger 记录关键操作和错误

---

## 测试建议

### 单元测试
```bash
# 运行测试
hvigor test
```

### 手动测试场景

**重复上屏**：
1. 输入"测试"并上屏
2. 输入 `cfsb`（或配置的触发编码）
3. 验证"测试"再次上屏

**撤销上屏**：
1. 输入"错误"并上屏
2. 立即输入 `cxsb`（或配置的触发编码）
3. 验证"错误"被删除
4. 等待6秒后再次尝试，验证无法撤销

**成对符号**：
1. 输入 `yh`（或配置的触发编码）
2. 选择 `""` 候选
3. 验证双引号插入且光标在中间

---

## 版本历史

- **2026-08-12**: 完成功能1和2的实现，创建功能3和4的文档
