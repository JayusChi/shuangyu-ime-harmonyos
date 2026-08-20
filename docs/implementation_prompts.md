# 直通编码功能实现提示词模板

## 功能1：重复上屏功能

### 提示词模板：

```
请为 HarmonyOS 输入法添加"重复上屏"功能，要求如下：

【功能需求】
- 用户可以通过特殊编码（如：rqt）或按键触发"重复上屏"
- 重复最后一次上屏的文本
- 支持重复最近N次的上屏内容（可配置，默认10条）

【实现要求】
1. 创建上屏历史管理器 CommitHistoryManager.ets：
   - 维护一个循环缓冲区，存储最近N次上屏记录
   - 每次调用 commitPreviewText / insertText 时自动记录
   - 提供 getLastCommit(index: number) 接口获取历史
   - 提供 clear() 方法清空历史

2. 修改 InputSessionController.ets：
   - 在文本提交成功后，调用 historyManager.addCommit(text)
   - 添加 repeatLastCommit() 方法
   - 该方法调用 imeService.insertText(lastCommit)

3. 添加键盘动作支持：
   - 在 KeyboardAction.ets 中添加 REPEAT_LAST_COMMIT 动作类型
   - 在 KeyboardController.ets 中处理该动作

4. 候选词支持（可选）：
   - 在引擎中添加特殊编码映射（如：rqt → 重复上屏）
   - 返回候选词时，text 为历史记录内容

【技术细节】
- 使用 TypeScript 的 Array 或自定义循环队列
- 考虑内存限制，每条记录最大长度限制为1000字符
- 会话结束时清空历史（隐私保护）

【文件位置】
- 创建：entry/src/main/ets/application/CommitHistoryManager.ets
- 修改：entry/src/main/ets/application/InputSessionController.ets
- 修改：entry/src/main/ets/domain/keyboard/KeyboardAction.ets
- 修改：entry/src/main/ets/application/KeyboardController.ets

请提供完整的实现代码。
```

---

## 功能2：撤销上屏功能

### 提示词模板：

```
请为 HarmonyOS 输入法添加"撤销上屏"功能，要求如下：

【功能需求】
- 用户可以通过特殊按键或编码触发"撤销上屏"
- 删除刚刚上屏的文本
- 只能撤销最近一次上屏，且用户不能移动光标

【技术限制说明】
HarmonyOS InputMethodEngine API 限制：
- 无法直接"撤销"已提交的文本
- 只能通过 deleteForward(length) 删除光标前的文本
- 需要假设用户没有移动光标

【实现要求】
1. 扩展 CommitHistoryManager.ets：
   - 记录每次上屏的文本长度（UTF-16编码单元数）
   - 记录上屏的时间戳
   - 提供 getLastCommitInfo() 返回 { text: string, length: number, timestamp: number }

2. 创建撤销管理器 UndoCommitManager.ets：
   - 提供 canUndo() 方法：检查是否可以撤销
     - 最后一次上屏时间 < 5秒（可配置）
     - 有记录的上屏历史
   - 提供 undoLastCommit() 方法：
     - 调用 imeService.deleteBackward(lastCommitLength)
     - 清除该条历史记录（防止重复撤销）

3. 添加键盘动作支持：
   - 在 KeyboardAction.ets 中添加 UNDO_LAST_COMMIT 动作类型
   - 在 KeyboardController.ets 中处理该动作
   - 处理前检查 canUndo()，失败时给出提示

4. 错误处理：
   - 如果删除失败，不要清除历史记录
   - 用户移动光标后，自动禁用撤销功能
   - 会话切换时清空撤销状态

【注意事项】
- UTF-16长度计算：使用 text.length（不是字符数）
- 表情符号、组合字符可能导致长度不匹配
- 建议增加"验证删除"功能：
  1. 先读取光标前的文本：getForward(length)
  2. 比对是否与记录的文本一致
  3. 一致才执行删除

【文件位置】
- 创建：entry/src/main/ets/application/UndoCommitManager.ets
- 修改：entry/src/main/ets/application/CommitHistoryManager.ets
- 修改：entry/src/main/ets/domain/keyboard/KeyboardAction.ets
- 修改：entry/src/main/ets/application/KeyboardController.ets

请提供完整的实现代码，并包含完善的错误处理。
```

---

## 功能3：直通编码命令系统

### 提示词模板：

```
请为 HarmonyOS 输入法添加"直通编码命令系统"，支持类似 Rime 的 lua 扩展功能。

【功能需求】
用户可以在码表中定义特殊命令编码，例如：
- rqt → $cmd({last_0},[重复]) - 重复上屏
- chxsb → $cmd({last_0},[撤销]) - 撤销上屏  
- sj → $cmd({datetime},[日期时间]) - 插入当前日期时间
- yh → $cmd("",[引号对]) - 插入成对引号，光标居中

【系统架构】
1. 命令语法定义：
   ```
   $cmd(<参数>, <标签>)
   
   参数类型：
   - {last_N}：第N次上屏内容（0=最后一次）
   - {datetime}：当前日期时间
   - {date}：当前日期
   - {time}：当前时间
   - 直接文本：如 ""、''、<>
   ```

2. 实现步骤：

**Step 1: 创建命令解析器**
文件：entry/src/main/ets/domain/command/CommandParser.ets
```typescript
export interface CommandDefinition {
  type: 'REPEAT_COMMIT' | 'UNDO_COMMIT' | 'INSERT_DATETIME' | 'INSERT_PAIR';
  params: Record<string, any>;
  label: string;
}

export class CommandParser {
  parse(commandString: string): CommandDefinition | null;
}
```

功能：
- 正则匹配 $cmd(...) 语法
- 解析参数和标签
- 返回结构化的命令定义

**Step 2: 创建命令执行器**
文件：entry/src/main/ets/domain/command/CommandExecutor.ets
```typescript
export class CommandExecutor {
  async execute(
    command: CommandDefinition,
    context: ExecutionContext
  ): Promise<CommandResult>;
}
```

功能：
- 根据命令类型分发到不同处理器
- REPEAT_COMMIT → 调用 historyManager
- INSERT_DATETIME → 生成时间文本
- INSERT_PAIR → 返回 INSERT_PAIR 协议动作

**Step 3: 集成到引擎**
两种方案：

方案A：在 Native 引擎中实现（推荐）
- 修改 engine-rust/crates/code-table-runtime/src/action.rs
- 解析码表条目时，检测 $cmd() 语法
- 存储为特殊的候选类型
- 返回时携带命令信息

方案B：在 ArkTS 层实现
- 修改 InputSessionController.ets
- 候选词被选择后，检测是否为命令
- 如果是，解析并执行命令，而不是直接上屏

**Step 4: 码表格式扩展**
在用户词库或码表中支持：
```
rqt	$cmd({last_0},[重复])	100
chxsb	$cmd({last_0},[撤销])	100
sj	$cmd({datetime},[时间])	100
```

【实现要求】
1. 命令解析器要健壮：
   - 非法语法返回 null
   - 支持转义字符
   - 参数验证

2. 执行器要安全：
   - 检查权限（避免危险操作）
   - 异步执行，超时保护
   - 错误不能崩溃整个输入法

3. 扩展性：
   - 命令类型可以轻松扩展
   - 支持注册自定义命令处理器

4. 性能：
   - 命令检测不能影响普通候选性能
   - 缓存解析结果

【文件位置】
- 创建：entry/src/main/ets/domain/command/CommandParser.ets
- 创建：entry/src/main/ets/domain/command/CommandExecutor.ets
- 创建：entry/src/main/ets/domain/command/CommandDefinition.ets
- 修改：entry/src/main/ets/application/InputSessionController.ets
- 可选：engine-rust 中的相关文件

请提供完整的设计方案和核心代码实现。
```

---

## 功能4：增强用户词库导入

### 提示词模板：

```
请增强 HarmonyOS 输入法的用户词库导入功能，支持从固定位置自动加载词库。

【当前实现】
- ✅ 已有 loadUserLexicon(path) 接口
- ✅ 已有 saveUserLexicon(path, revision, content) 接口
- ✅ 已有 reloadUserLexicon(handle) 接口

【需要增强】
1. 自动检测和加载：
   - 启动时自动扫描预设路径：
     - /data/storage/el2/base/files/user_lexicon/
     - 用户可配置的自定义路径
   - 支持多个词库文件：
     - user_words.txt（主词库）
     - custom_1.txt, custom_2.txt（自定义词库）

2. 导入策略：
   - 替换模式：清空现有用户词，导入新词库
   - 补充模式：保留现有用户词，追加新词库
   - 合并模式：智能合并，相同编码的词按优先级排序

3. 实时监控（可选）：
   - 监听词库文件变化
   - 文件更新时自动重载
   - 使用 HarmonyOS 的文件监听 API

4. 配置界面：
   - 在设置页面添加"词库管理"菜单
   - 显示当前加载的词库列表
   - 支持启用/禁用特定词库
   - 支持手动触发重载

【实现要求】
1. 创建词库管理器 UserLexiconImportManager.ets：
   ```typescript
   export interface LexiconSource {
     path: string;
     enabled: boolean;
     priority: number;
     mode: 'REPLACE' | 'APPEND' | 'MERGE';
   }
   
   export class UserLexiconImportManager {
     async scanAndLoad(): Promise<void>;
     async importFromPath(source: LexiconSource): Promise<boolean>;
     async reloadAll(): Promise<void>;
     getLoadedSources(): LexiconSource[];
   }
   ```

2. 修改应用启动流程：
   - 在 InputMethodLifecycleDispatcher.ets 中
   - onCreate 时调用 lexiconManager.scanAndLoad()
   - 加载失败时记录日志，但不阻止启动

3. 添加设置界面：
   - 创建 UserLexiconManagerPage.ets（可能已存在，需扩展）
   - 显示词库列表、状态、词条数量
   - 提供刷新按钮
   - 提供导入/导出功能

4. 错误处理：
   - 词库格式错误时，显示具体错误信息
   - 部分词库加载失败，不影响其他词库
   - 提供"恢复默认"功能

【词库文件格式】
支持标准格式：
```
# 注释行
词语<TAB>编码<TAB>权重
示例	sl	100
```

【配置存储】
使用 SettingsRepository 存储配置：
```json
{
  "userLexicon": {
    "sources": [
      {
        "path": "/data/storage/el2/base/files/user_lexicon/main.txt",
        "enabled": true,
        "priority": 100,
        "mode": "APPEND"
      }
    ],
    "autoReload": true
  }
}
```

【文件位置】
- 创建：entry/src/main/ets/application/UserLexiconImportManager.ets
- 修改：entry/src/main/ets/application/InputMethodLifecycleDispatcher.ets
- 修改：entry/src/main/ets/pages/UserLexiconManagerPage.ets
- 修改：entry/src/main/ets/domain/settings/ImeSettings.ets

请提供完整的实现代码。
```

---

## 功能5：分类词库动态切换UI

### 提示词模板：

```
请为 HarmonyOS 输入法添加"分类词库快速切换"界面，让用户可以实时启用/禁用词库分类。

【当前实现】
- ✅ 已有 getCodeTableCategoryConfig(handle) 接口
- ✅ 已有 setCodeTableCategories(handle, ids) 接口
- ✅ 支持词库分类：PRIMARY / EXTENSION / USER / FUNCTIONAL

【功能需求】
1. 设置页面显示词库分类：
   - 显示所有可用的分类
   - 每个分类显示：名称、类型、词条数、状态
   - 用户可以通过开关切换启用状态
   - required=true 的分类不允许关闭

2. 实时生效：
   - 切换开关后立即调用 setCodeTableCategories()
   - 不需要重启输入法
   - 切换后立即影响候选结果

3. 持久化：
   - 保存用户的选择到设置
   - 下次启动时自动恢复

【实现要求】
1. 扩展 SettingsController.ets：
   ```typescript
   async getCodeTableCategories(): Promise<CodeTableCategoryDefinition[]>;
   async toggleCategory(categoryId: string, enabled: boolean): Promise<boolean>;
   async getEnabledCategoryIds(): Promise<string[]>;
   ```

2. 创建设置页面组件：
文件：entry/src/main/ets/presentation/settings/CodeTableCategorySettings.ets
```typescript
@Component
struct CodeTableCategoryList {
  @State categories: CodeTableCategoryDefinition[] = [];
  @State enabledIds: string[] = [];
  
  async onToggle(categoryId: string, enabled: boolean) {
    await this.controller.toggleCategory(categoryId, enabled);
    // 刷新候选
  }
}
```

界面设计：
```
━━━━━━━━━━━━━━━━━━━━
  词库分类设置
━━━━━━━━━━━━━━━━━━━━

基础词库        [✓] 
  10,000 词条 | 必需

扩展词库        [✓]
  5,000 词条

用户词库        [✓]
  120 词条

符号库          [ ]
  500 词条

━━━━━━━━━━━━━━━━━━━━
```

3. 集成到主设置页面：
   - 在 SettingsPage.ets 中添加入口
   - 点击"词库管理"跳转到词库设置页面

4. 实时刷新候选：
   - 切换词库后，清空当前输入状态
   - 重新生成候选词
   - 通知用户"词库已更新"

【交互细节】
- 必需词库的开关显示为禁用状态（灰色）
- 切换开关时显示加载动画
- 失败时显示错误提示并回滚开关状态
- 显示当前生效的词库总数和词条总数

【文件位置】
- 创建：entry/src/main/ets/presentation/settings/CodeTableCategorySettings.ets
- 修改：entry/src/main/ets/application/SettingsController.ets
- 修改：entry/src/main/ets/presentation/settings/SettingsPage.ets

请提供完整的UI组件和控制器代码。
```

---

## 通用注意事项

### 代码规范：
1. 使用 TypeScript 严格模式
2. 所有异步操作使用 async/await
3. 错误处理：try-catch + 日志记录
4. 使用 Logger 记录关键操作
5. 遵循项目现有的代码风格

### 测试要求：
1. 为每个新功能添加单元测试
2. 测试文件放在 entry/src/test/ 目录
3. 使用 @ohos/hypium 测试框架
4. 覆盖正常流程和异常情况

### 性能考虑：
1. 避免阻塞主线程
2. 大量数据使用分页加载
3. 缓存频繁访问的数据
4. 防抖/节流频繁触发的操作

### 兼容性：
1. 支持 HarmonyOS 4.0+
2. 优雅降级：API不可用时不崩溃
3. 保持向后兼容：设置格式支持迁移

---

## 快速参考：相关文件

### 核心控制器：
- `entry/src/main/ets/application/InputSessionController.ets` - 输入会话控制
- `entry/src/main/ets/application/KeyboardController.ets` - 键盘事件处理
- `entry/src/main/ets/application/SettingsController.ets` - 设置管理

### 基础设施：
- `entry/src/main/ets/infrastructure/ime/ImeConnectionService.ets` - IME API封装
- `entry/src/main/ets/infrastructure/native/NativeEngineGateway.ets` - 引擎接口
- `entry/src/main/ets/infrastructure/storage/SettingsRepository.ets` - 设置持久化

### 数据模型：
- `entry/src/main/ets/domain/keyboard/KeyboardAction.ets` - 键盘动作定义
- `entry/src/main/ets/infrastructure/native/NativeEngineTypes.ets` - 引擎类型定义
- `entry/src/main/ets/domain/settings/ImeSettings.ets` - 设置数据模型

### UI组件：
- `entry/src/main/ets/presentation/settings/SettingsPage.ets` - 设置页面
- `entry/src/main/ets/presentation/keyboard/KeyboardRoot.ets` - 键盘根组件
