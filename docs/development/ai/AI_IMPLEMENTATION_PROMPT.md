# HarmonyOS 输入法直通编码功能实现任务

## 任务概述

请为这个 HarmonyOS 输入法项目实现"直通编码"相关的6个功能。项目使用 ArkTS（TypeScript）+ Rust 混合架构，输入法引擎在 Rust 侧，UI和业务逻辑在 ArkTS 侧。

**项目结构**：
- `entry/src/main/ets/` - ArkTS 代码（UI和业务逻辑）
- `engine-rust/` - Rust 输入法引擎

---

## 功能需求清单

### ✅ 功能1：重复上屏 【必须实现】

**用户场景**：
用户想快速重复输入刚才上屏的内容，比如输入"测试"后，想再输入一遍"测试"。

**触发方式**：
- 方式1：通过特殊编码触发（建议用 `cfsb` = 重复上屏）
- 方式2：长按空格键触发（可选）

**实现要求**：

#### Step 1: 创建上屏历史管理器

**文件**：`entry/src/main/ets/application/CommitHistoryManager.ets`

```typescript
/**
 * 上屏历史管理器 - 维护最近N次上屏记录
 */
export interface CommitRecord {
  text: string;
  timestamp: number;
  length: number; // UTF-16 长度
}

export class CommitHistoryManager {
  private history: CommitRecord[] = [];
  private readonly maxSize: number = 10;

  /**
   * 添加一条上屏记录
   */
  addCommit(text: string): void {
    if (text.length === 0) {
      return;
    }
    
    const record: CommitRecord = {
      text: text,
      timestamp: Date.now(),
      length: text.length
    };
    
    this.history.unshift(record);
    
    if (this.history.length > this.maxSize) {
      this.history.pop();
    }
  }

  /**
   * 获取最后一次上屏内容
   */
  getLastCommit(): string | null {
    return this.getCommit(0);
  }

  /**
   * 获取第N次上屏内容（0=最近一次）
   */
  getCommit(index: number): string | null {
    if (index < 0 || index >= this.history.length) {
      return null;
    }
    return this.history[index].text;
  }

  /**
   * 获取历史记录数量
   */
  getHistorySize(): number {
    return this.history.length;
  }

  /**
   * 清空历史记录
   */
  clear(): void {
    this.history = [];
  }

  /**
   * 获取所有历史记录（用于UI展示）
   */
  getAllRecords(): CommitRecord[] {
    return [...this.history];
  }
}
```

#### Step 2: 集成到输入会话控制器

**修改文件**：`entry/src/main/ets/application/InputSessionController.ets`

**修改点1**：添加历史管理器实例

在类中添加字段：
```typescript
private readonly commitHistoryManager: CommitHistoryManager = new CommitHistoryManager();
```

**修改点2**：在所有文本提交点记录历史

找到所有调用 `imeService.commitPreviewText()` 和 `imeService.insertText()` 的地方，在成功后添加：

```typescript
// 示例：在提交候选词后
const committed = await this.imeService.commitPreviewText(text, generation);
if (committed) {
  this.commitHistoryManager.addCommit(text); // 添加这一行
  // ... 其他逻辑
}
```

**修改点3**：添加重复上屏方法

在 `InputSessionController` 类中添加：

```typescript
/**
 * 重复上屏最后一次提交的内容
 */
async repeatLastCommit(): Promise<boolean> {
  const lastCommit = this.commitHistoryManager.getLastCommit();
  
  if (!lastCommit) {
    Logger.warn('没有可重复的上屏内容');
    return false;
  }

  // 清空当前输入状态
  await this.reset();

  // 直接插入文本
  const inserted = await this.imeService.insertText(lastCommit);
  
  if (inserted) {
    // 注意：这次不要再记录到历史，避免无限重复
    Logger.info(`重复上屏成功: ${lastCommit}`);
    return true;
  }

  return false;
}
```

**修改点4**：会话结束时清空历史

在 `onSessionEnd()` 或类似的会话结束方法中添加：
```typescript
this.commitHistoryManager.clear();
```

#### Step 3: 添加键盘动作支持

**修改文件**：`entry/src/main/ets/domain/keyboard/KeyboardAction.ets`

添加新的动作类型：
```typescript
export enum KeyboardActionType {
  // ... 现有的动作类型
  REPEAT_LAST_COMMIT = 'repeat_last_commit',  // 添加这一行
}

// 添加常量
export const REPEAT_LAST_COMMIT_ACTION: KeyboardAction = {
  type: KeyboardActionType.REPEAT_LAST_COMMIT
};
```

#### Step 4: 处理键盘动作

**修改文件**：`entry/src/main/ets/application/KeyboardController.ets`

在 `handleAction()` 或处理键盘动作的方法中添加：

```typescript
case KeyboardActionType.REPEAT_LAST_COMMIT:
  await this.inputSessionController.repeatLastCommit();
  break;
```

#### Step 5: （可选）在引擎侧添加触发编码

**修改文件**：根据项目的码表配置方式

如果有用户词库或码表文件，添加一行：
```
重复上屏	cfsb	1
```

或者在代码中添加逻辑：当用户输入 `cfsb` 时，返回一个特殊候选，选中后触发 `REPEAT_LAST_COMMIT` 动作。

---

### ✅ 功能2：撤销上屏 【必须实现，但要处理限制】

**用户场景**：
用户刚上屏了一个词，发现选错了，想立刻撤回。

**触发方式**：
- 通过特殊编码触发（建议用 `cxsb` = 撤销上屏）

**技术限制**：
- HarmonyOS API 没有直接的"撤销"功能
- 只能通过删除光标前的文本实现
- 必须假设用户没有移动光标
- 表情符号等可能导致长度计算错误

**实现要求**：

#### Step 1: 创建撤销管理器

**文件**：`entry/src/main/ets/application/UndoCommitManager.ets`

```typescript
import { CommitHistoryManager } from './CommitHistoryManager';
import { Logger } from '../common/logging/Logger';

const TAG = 'UndoCommitManager';
const LOGGER = new Logger(TAG);

export interface UndoState {
  canUndo: boolean;
  reason?: string;
  lastCommit?: string;
  lastCommitLength?: number;
}

/**
 * 撤销上屏管理器
 */
export class UndoCommitManager {
  private readonly historyManager: CommitHistoryManager;
  private readonly maxUndoTimeMs: number = 5000; // 5秒内可撤销
  private lastUndoableCommit: string | null = null;
  private lastUndoableLength: number = 0;
  private lastCommitTime: number = 0;

  constructor(historyManager: CommitHistoryManager) {
    this.historyManager = historyManager;
  }

  /**
   * 记录一次可撤销的提交
   */
  recordCommit(text: string): void {
    this.lastUndoableCommit = text;
    this.lastUndoableLength = text.length;
    this.lastCommitTime = Date.now();
  }

  /**
   * 检查是否可以撤销
   */
  canUndo(): UndoState {
    if (!this.lastUndoableCommit) {
      return {
        canUndo: false,
        reason: '没有可撤销的内容'
      };
    }

    const elapsed = Date.now() - this.lastCommitTime;
    if (elapsed > this.maxUndoTimeMs) {
      return {
        canUndo: false,
        reason: '撤销时间窗口已过期'
      };
    }

    return {
      canUndo: true,
      lastCommit: this.lastUndoableCommit,
      lastCommitLength: this.lastUndoableLength
    };
  }

  /**
   * 清除撤销状态
   */
  clearUndoState(): void {
    this.lastUndoableCommit = null;
    this.lastUndoableLength = 0;
    this.lastCommitTime = 0;
  }

  /**
   * 用户移动光标后，禁用撤销
   */
  invalidateUndo(): void {
    this.clearUndoState();
  }
}
```

#### Step 2: 集成到输入会话控制器

**修改文件**：`entry/src/main/ets/application/InputSessionController.ets`

**修改点1**：添加撤销管理器

```typescript
private undoCommitManager?: UndoCommitManager;

// 在构造函数或初始化方法中
this.undoCommitManager = new UndoCommitManager(this.commitHistoryManager);
```

**修改点2**：记录可撤销的提交

在成功提交文本后：
```typescript
const committed = await this.imeService.commitPreviewText(text, generation);
if (committed) {
  this.commitHistoryManager.addCommit(text);
  this.undoCommitManager.recordCommit(text); // 添加这一行
}
```

**修改点3**：添加撤销方法

```typescript
/**
 * 撤销最后一次上屏
 */
async undoLastCommit(): Promise<boolean> {
  if (!this.undoCommitManager) {
    return false;
  }

  const undoState = this.undoCommitManager.canUndo();
  
  if (!undoState.canUndo) {
    LOGGER.warn(`无法撤销: ${undoState.reason}`);
    return false;
  }

  const length = undoState.lastCommitLength!;
  
  // 方案A：直接删除（快速但可能不准确）
  // const deleted = await this.imeService.deleteBackward(length);
  
  // 方案B：先验证再删除（推荐）
  const deleted = await this.deleteWithVerification(
    undoState.lastCommit!,
    length
  );

  if (deleted) {
    this.undoCommitManager.clearUndoState();
    LOGGER.info(`撤销上屏成功: ${undoState.lastCommit}`);
    return true;
  }

  return false;
}

/**
 * 验证后删除 - 确保删除的是正确的内容
 */
private async deleteWithVerification(
  expectedText: string,
  length: number
): Promise<boolean> {
  try {
    // 1. 获取当前光标位置
    const inputClient = this.getInputClient(); // 需要提供访问 inputClient 的方法
    if (!inputClient) {
      return false;
    }

    const cursor = await inputClient.getTextIndexAtCursor();
    if (cursor < length) {
      LOGGER.warn(`光标位置不足，无法删除 length=${length}, cursor=${cursor}`);
      return false;
    }

    // 2. 读取光标前的文本
    const textBeforeCursor = await inputClient.getForward(length);
    
    // 3. 验证是否匹配
    if (textBeforeCursor !== expectedText) {
      LOGGER.warn(
        `文本不匹配，无法撤销。期望: "${expectedText}", 实际: "${textBeforeCursor}"`
      );
      return false;
    }

    // 4. 执行删除
    const deleted = await this.imeService.deleteBackward(length);
    return deleted;

  } catch (err) {
    LOGGER.error(`撤销验证失败: ${err}`);
    return false;
  }
}

/**
 * 提供访问 inputClient 的方法
 */
private getInputClient(): any {
  // 根据你的实际代码结构返回 inputClient
  // 可能需要从 ImeConnectionService 获取
  return null; // 替换为实际实现
}
```

**修改点4**：用户输入时清除撤销状态

在用户输入任何字符时（`processKey` 等方法）：
```typescript
if (this.undoCommitManager) {
  this.undoCommitManager.invalidateUndo();
}
```

#### Step 3: 添加键盘动作

**修改文件**：`entry/src/main/ets/domain/keyboard/KeyboardAction.ets`

```typescript
export enum KeyboardActionType {
  // ...
  UNDO_LAST_COMMIT = 'undo_last_commit',
}

export const UNDO_LAST_COMMIT_ACTION: KeyboardAction = {
  type: KeyboardActionType.UNDO_LAST_COMMIT
};
```

#### Step 4: 处理键盘动作

**修改文件**：`entry/src/main/ets/application/KeyboardController.ets`

```typescript
case KeyboardActionType.UNDO_LAST_COMMIT:
  await this.inputSessionController.undoLastCommit();
  break;
```

---

### ✅ 功能3：成对符号光标居中 【已实现，需要文档说明】

**状态**：✅ 已完整实现

**实现位置**：
- `entry/src/main/ets/application/ProtocolActionExecutor.ets`
- `entry/src/main/ets/infrastructure/ime/ImeConnectionService.ets`

**任务**：

#### 创建使用文档

**文件**：`docs/features/direct-control/PAIR_INSERTION_GUIDE.md`

```markdown
# 成对符号光标居中功能使用指南

## 功能说明

该功能已经完整实现。当引擎返回 `INSERT_PAIR` 协议动作时，系统会自动：
1. 插入成对符号（如 `""`、`''`、`<>`）
2. 将光标定位到符号中间

## 使用方法

### 方式1：在码表中定义

在用户词库或码表文件中添加触发条件：

```
编码	候选词	权重
yh	""	100
dyh	''	100
```

然后在引擎逻辑中，当选中这些候选时，返回 `InsertPairAction`。

### 方式2：在引擎代码中实现

当检测到特定编码或候选时，返回：

```json
{
  "type": "INSERT_PAIR",
  "text": "\"\"",
  "cursorOffsetUtf16": 1
}
```

- `text`: 要插入的完整文本
- `cursorOffsetUtf16`: 光标应该在文本中的位置（UTF-16偏移）

### 示例

| 符号对 | text | cursorOffsetUtf16 |
|--------|------|-------------------|
| `""` | `""` | 1 |
| `''` | `''` | 1 |
| `<>` | `<>` | 1 |
| `()` | `()` | 1 |
| `[]` | `[]` | 1 |
| `{}` | `{}` | 1 |

## 技术细节

- 支持任意长度的成对文本（最大64字符）
- 使用 UTF-16 编码计算偏移量
- 自动处理光标定位
- 支持复杂符号对，如 `<!--  -->`（偏移量为5）

## API 接口

引擎返回的数据结构：

```typescript
interface InsertPairAction {
  type: 'INSERT_PAIR';
  formatId: '';
  text: string;              // 要插入的文本
  cursorOffsetUtf16: number; // 光标偏移（从文本开头计算）
}
```

## 限制

- `cursorOffsetUtf16` 必须在 1 到 16 之间
- `text` 长度必须在 2 到 64 之间
- 偏移量必须在文本范围内
```

**无需修改代码，只需创建文档即可。**

---

### ✅ 功能4：模拟End键 【无法实现，需要说明】

**状态**：❌ 技术上无法实现

**原因**：HarmonyOS InputMethodEngine API 不支持模拟物理按键

**任务**：

#### 创建技术限制说明文档

**文件**：`docs/features/direct-control/KEY_SIMULATION_LIMITATION.md`

```markdown
# 按键模拟功能技术限制说明

## 问题

客户需求：通过直通编码模拟 End、Home、方向键等功能键。

例如：`$cmd(keyboard(<123>),[End])` 模拟 End 键

## 结论

**无法实现** - HarmonyOS 输入法 API 根本不支持模拟物理按键。

## 技术原因

### HarmonyOS API 支持的功能键

`inputClient.sendKeyFunction(keyType)` 仅支持以下回车键变体：

- `ENTER_KEY_TYPE_NEWLINE` - 换行
- `ENTER_KEY_TYPE_SEARCH` - 搜索
- `ENTER_KEY_TYPE_DONE` - 完成
- `ENTER_KEY_TYPE_NEXT` - 下一个
- `ENTER_KEY_TYPE_GO` - 前往
- `ENTER_KEY_TYPE_SEND` - 发送

### 不支持的按键

❌ 方向键（↑↓←→）
❌ Home / End
❌ PageUp / PageDown
❌ Esc
❌ Tab
❌ 功能键（F1-F12）
❌ 组合键（Ctrl+X、Alt+Tab等）

### 替代方案

**部分功能可以通过文本操作间接实现**：

1. **退格键** - ✅ 可通过 `deleteForward(length)` 实现
2. **Enter键** - ✅ 可通过 `sendKeyFunction(ENTER_KEY_TYPE_NEWLINE)` 实现
3. **光标定位** - ✅ 可通过 `selectByRange({start, end})` 实现
   - 但需要知道绝对位置，无法相对移动

4. **End键** - ❌ 无法实现
   - 需要"光标移动到行尾"的API，但不存在
   - 无法获取当前行的长度
   
5. **Home键** - ❌ 无法实现
   - 需要"光标移动到行首"的API，但不存在

6. **方向键** - ❌ 无法实现
   - 无法相对移动光标

## 对比其他平台

- **Android**: 同样的限制，输入法无法模拟按键
- **iOS**: 同样的限制
- **Windows**: IME API 也不支持模拟系统级按键

## 结论

这是操作系统 API 的固有限制，不是实现问题。

如果客户坚持需要此功能，需要：
1. 向华为提交 API 增强请求
2. 或者通过系统辅助功能（Accessibility）实现（需要额外权限，且不适用于输入法）
```

**无需修改代码，只需创建说明文档即可。**

---

### ✅ 功能5：分类词库启用/关闭 【已实现，需要UI优化】

**状态**：✅ 后端API已实现，需要添加用户界面

**实现要求**：

#### Step 1: 扩展设置控制器

**修改文件**：`entry/src/main/ets/application/SettingsController.ets`

添加以下方法：

```typescript
/**
 * 获取所有词库分类
 */
async getCodeTableCategories(): Promise<CodeTableCategoryDefinition[]> {
  // 调用 native 引擎获取分类配置
  const config = this.nativeEngine.getCodeTableCategoryConfig(this.engineHandle);
  return config.categories;
}

/**
 * 获取当前启用的分类ID列表
 */
async getEnabledCategoryIds(): Promise<string[]> {
  const config = this.nativeEngine.getCodeTableCategoryConfig(this.engineHandle);
  return config.enabledCategoryIds;
}

/**
 * 切换词库分类启用状态
 */
async toggleCategory(categoryId: string, enabled: boolean): Promise<boolean> {
  try {
    const currentIds = await this.getEnabledCategoryIds();
    let newIds: string[];

    if (enabled) {
      // 添加到启用列表
      if (!currentIds.includes(categoryId)) {
        newIds = [...currentIds, categoryId];
      } else {
        newIds = currentIds;
      }
    } else {
      // 从启用列表移除
      newIds = currentIds.filter(id => id !== categoryId);
    }

    // 调用引擎设置
    const result = this.nativeEngine.setCodeTableCategories(
      this.engineHandle,
      newIds
    );

    if (result.success) {
      // 保存到设置
      await this.settingsRepository.updateCodeTableCategories(newIds);
      return true;
    }

    return false;
  } catch (err) {
    Logger.error(`切换词库分类失败: ${err}`);
    return false;
  }
}
```

#### Step 2: 创建词库分类设置页面

**文件**：`entry/src/main/ets/presentation/settings/CodeTableCategorySettings.ets`

```typescript
import { CodeTableCategoryDefinition, CodeTableCategoryKind } from '../../infrastructure/native/NativeEngineTypes';
import { SettingsController } from '../../application/SettingsController';

@Entry
@Component
struct CodeTableCategorySettings {
  @State categories: CodeTableCategoryDefinition[] = [];
  @State enabledIds: string[] = [];
  @State isLoading: boolean = false;
  
  private settingsController: SettingsController = new SettingsController();

  async aboutToAppear() {
    await this.loadCategories();
  }

  async loadCategories() {
    this.isLoading = true;
    try {
      this.categories = await this.settingsController.getCodeTableCategories();
      this.enabledIds = await this.settingsController.getEnabledCategoryIds();
    } catch (err) {
      console.error('加载词库分类失败', err);
    } finally {
      this.isLoading = false;
    }
  }

  async onToggle(categoryId: string, enabled: boolean) {
    const success = await this.settingsController.toggleCategory(categoryId, enabled);
    
    if (success) {
      // 刷新启用列表
      this.enabledIds = await this.settingsController.getEnabledCategoryIds();
      
      // 显示提示
      promptAction.showToast({
        message: enabled ? '词库已启用' : '词库已禁用',
        duration: 2000
      });
    } else {
      promptAction.showToast({
        message: '操作失败',
        duration: 2000
      });
    }
  }

  getCategoryKindText(kind: CodeTableCategoryKind): string {
    switch (kind) {
      case 'PRIMARY':
        return '主词库';
      case 'PRIMARY_EQUIVALENT':
        return '等价主词库';
      case 'EXTENSION':
        return '扩展词库';
      case 'USER':
        return '用户词库';
      case 'FUNCTIONAL':
        return '功能词库';
      default:
        return '未知';
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('词库分类设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .padding(16)

      if (this.isLoading) {
        LoadingProgress()
          .width(50)
          .height(50)
          .margin({ top: 100 })
      } else {
        // 词库列表
        List() {
          ForEach(this.categories, (category: CodeTableCategoryDefinition) => {
            ListItem() {
              this.CategoryItem(category)
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
      }

      // 底部统计信息
      Row() {
        Text(`已启用 ${this.enabledIds.length}/${this.categories.length} 个词库`)
          .fontSize(14)
          .fontColor('#999999')
      }
      .width('100%')
      .padding(16)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  CategoryItem(category: CodeTableCategoryDefinition) {
    Row() {
      Column() {
        // 词库名称
        Text(category.displayName)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)

        // 词库信息
        Row() {
          Text(`${this.getCategoryKindText(category.kind)}`)
            .fontSize(12)
            .fontColor('#666666')
            .margin({ right: 8 })

          Text(`${category.entryCount} 词条`)
            .fontSize(12)
            .fontColor('#666666')

          if (category.required) {
            Text('必需')
              .fontSize(12)
              .fontColor('#FF6B6B')
              .margin({ left: 8 })
          }
        }
        .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 开关
      Toggle({ type: ToggleType.Switch, isOn: this.enabledIds.includes(category.id) })
        .enabled(category.userToggleable && !category.required)
        .onChange(async (isOn: boolean) => {
          await this.onToggle(category.id, isOn);
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .margin({ left: 12, right: 12, top: 8 })
  }
}
```

#### Step 3: 在设置页面添加入口

**修改文件**：`entry/src/main/ets/presentation/settings/SettingsPage.ets`

在设置列表中添加一项：

```typescript
ListItem() {
  Row() {
    Text('词库管理')
      .fontSize(16)
    
    Blank()
    
    Text('>')
      .fontSize(16)
      .fontColor('#CCCCCC')
  }
  .width('100%')
  .padding(16)
  .onClick(() => {
    // 跳转到词库分类设置页面
    router.pushUrl({
      url: 'pages/settings/CodeTableCategorySettings'
    });
  })
}
```

#### Step 4: 持久化设置

**修改文件**：`entry/src/main/ets/infrastructure/storage/SettingsRepository.ets`

添加方法：

```typescript
async updateCodeTableCategories(enabledIds: string[]): Promise<void> {
  const settings = await this.loadSettings();
  settings.codeTableCategories = {
    enabledIds: enabledIds
  };
  await this.saveSettings(settings);
}
```

**修改文件**：`entry/src/main/ets/domain/settings/ImeSettings.ets`

添加字段：

```typescript
export interface ImeSettings {
  // ... 现有字段
  
  codeTableCategories?: {
    enabledIds: string[];
  };
}
```

---

### ✅ 功能6：用户词库导入增强 【需要优化】

**状态**：✅ 基础功能已实现，需要增强自动导入和UI

**实现要求**：

#### Step 1: 创建词库导入管理器

**文件**：`entry/src/main/ets/application/UserLexiconImportManager.ets`

```typescript
import { UserLexiconController } from './UserLexiconController';
import { Logger } from '../common/logging/Logger';
import fs from '@ohos.file.fs';

const TAG = 'UserLexiconImportManager';
const LOGGER = new Logger(TAG);

export enum LexiconImportMode {
  REPLACE = 'REPLACE',   // 替换现有词库
  APPEND = 'APPEND',     // 追加到现有词库
  MERGE = 'MERGE'        // 智能合并
}

export interface LexiconSource {
  path: string;
  enabled: boolean;
  priority: number;
  mode: LexiconImportMode;
  name: string;
}

export interface ImportResult {
  success: boolean;
  source: LexiconSource;
  entriesImported: number;
  errorMessage?: string;
}

/**
 * 用户词库导入管理器
 */
export class UserLexiconImportManager {
  private readonly lexiconController: UserLexiconController;
  private sources: LexiconSource[] = [];
  private readonly defaultPaths = [
    '/data/storage/el2/base/files/user_lexicon/main.txt',
    '/data/storage/el2/base/files/user_lexicon/custom.txt',
  ];

  constructor(lexiconController: UserLexiconController) {
    this.lexiconController = lexiconController;
  }

  /**
   * 扫描并加载所有配置的词库
   */
  async scanAndLoad(): Promise<ImportResult[]> {
    const results: ImportResult[] = [];

    // 先加载配置的词库源
    await this.loadSourcesFromConfig();

    // 如果没有配置，使用默认路径
    if (this.sources.length === 0) {
      this.sources = this.defaultPaths.map((path, index) => ({
        path: path,
        enabled: true,
        priority: 100 - index * 10,
        mode: LexiconImportMode.APPEND,
        name: `词库${index + 1}`
      }));
    }

    // 按优先级排序
    this.sources.sort((a, b) => b.priority - a.priority);

    // 逐个导入
    for (const source of this.sources) {
      if (!source.enabled) {
        continue;
      }

      const result = await this.importFromSource(source);
      results.push(result);
    }

    return results;
  }

  /**
   * 从单个源导入词库
   */
  async importFromSource(source: LexiconSource): Promise<ImportResult> {
    try {
      // 检查文件是否存在
      const exists = await this.fileExists(source.path);
      if (!exists) {
        LOGGER.warn(`词库文件不存在: ${source.path}`);
        return {
          success: false,
          source: source,
          entriesImported: 0,
          errorMessage: '文件不存在'
        };
      }

      // 读取文件内容
      const content = await this.readFile(source.path);

      // 根据模式处理
      let finalContent: string;
      switch (source.mode) {
        case LexiconImportMode.REPLACE:
          finalContent = content;
          break;
        case LexiconImportMode.APPEND:
          finalContent = await this.appendContent(content);
          break;
        case LexiconImportMode.MERGE:
          finalContent = await this.mergeContent(content);
          break;
        default:
          finalContent = content;
      }

      // 调用原有的导入逻辑
      const document = await this.lexiconController.importLexicon(finalContent);

      if (document.success) {
        LOGGER.info(
          `导入词库成功: ${source.name}, 有效词条: ${document.stats.effective}`
        );
        return {
          success: true,
          source: source,
          entriesImported: document.stats.effective
        };
      } else {
        LOGGER.warn(`导入词库失败: ${source.name}, ${document.message}`);
        return {
          success: false,
          source: source,
          entriesImported: 0,
          errorMessage: document.message
        };
      }

    } catch (err) {
      LOGGER.error(`导入词库异常: ${source.name}, ${err}`);
      return {
        success: false,
        source: source,
        entriesImported: 0,
        errorMessage: String(err)
      };
    }
  }

  /**
   * 追加模式：合并现有词库和新词库
   */
  private async appendContent(newContent: string): Promise<string> {
    const currentContent = await this.lexiconController.exportCurrentLexicon();
    return currentContent + '\n' + newContent;
  }

  /**
   * 合并模式：智能去重和排序
   */
  private async mergeContent(newContent: string): Promise<string> {
    const currentContent = await this.lexiconController.exportCurrentLexicon();
    
    // 解析为词条列表
    const currentEntries = this.parseEntries(currentContent);
    const newEntries = this.parseEntries(newContent);

    // 合并：新词条优先
    const merged = new Map<string, string>(); // key: 编码, value: 词条行

    currentEntries.forEach(entry => {
      merged.set(entry.key, entry.line);
    });

    newEntries.forEach(entry => {
      merged.set(entry.key, entry.line); // 覆盖同编码的旧词条
    });

    // 转回文本
    return Array.from(merged.values()).join('\n');
  }

  /**
   * 解析词库内容为词条列表
   */
  private parseEntries(content: string): Array<{ key: string, line: string }> {
    const lines = content.split('\n');
    const entries: Array<{ key: string, line: string }> = [];

    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }

      const parts = trimmed.split('\t');
      if (parts.length >= 2) {
        const text = parts[0];
        const code = parts[1];
        const key = `${code}:${text}`;
        entries.push({ key, line: trimmed });
      }
    }

    return entries;
  }

  /**
   * 重新加载所有词库
   */
  async reloadAll(): Promise<void> {
    await this.lexiconController.reloadLexicon();
  }

  /**
   * 获取已加载的词库源列表
   */
  getLoadedSources(): LexiconSource[] {
    return [...this.sources];
  }

  /**
   * 添加词库源
   */
  addSource(source: LexiconSource): void {
    this.sources.push(source);
    this.saveSourcesConfig();
  }

  /**
   * 移除词库源
   */
  removeSource(path: string): void {
    this.sources = this.sources.filter(s => s.path !== path);
    this.saveSourcesConfig();
  }

  /**
   * 从配置加载词库源列表
   */
  private async loadSourcesFromConfig(): Promise<void> {
    // 从 SettingsRepository 加载配置
    // 实现细节根据实际的配置存储方式调整
  }

  /**
   * 保存词库源配置
   */
  private async saveSourcesConfig(): Promise<void> {
    // 保存到 SettingsRepository
    // 实现细节根据实际的配置存储方式调整
  }

  /**
   * 检查文件是否存在
   */
  private async fileExists(path: string): Promise<boolean> {
    try {
      const stat = await fs.stat(path);
      return stat.isFile();
    } catch {
      return false;
    }
  }

  /**
   * 读取文件内容
   */
  private async readFile(path: string): Promise<string> {
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    const buffer = new ArrayBuffer(1024 * 1024); // 最大1MB
    const readLen = await fs.read(file.fd, buffer);
    await fs.close(file);

    const uint8Array = new Uint8Array(buffer, 0, readLen);
    const decoder = new TextDecoder('utf-8');
    return decoder.decode(uint8Array);
  }
}
```

#### Step 2: 在应用启动时自动加载

**修改文件**：`entry/src/main/ets/application/InputMethodLifecycleDispatcher.ets`

在 `onCreate()` 或初始化方法中：

```typescript
import { UserLexiconImportManager } from './UserLexiconImportManager';

// 在类中添加字段
private lexiconImportManager?: UserLexiconImportManager;

// 在初始化方法中
async onEngineInitialized() {
  // ... 其他初始化逻辑

  // 初始化词库导入管理器
  this.lexiconImportManager = new UserLexiconImportManager(
    this.userLexiconController
  );

  // 自动扫描和加载词库
  try {
    const results = await this.lexiconImportManager.scanAndLoad();
    const successCount = results.filter(r => r.success).length;
    LOGGER.info(`词库自动加载完成: ${successCount}/${results.length} 成功`);
  } catch (err) {
    LOGGER.error(`词库自动加载失败: ${err}`);
    // 失败不阻止启动
  }
}
```

#### Step 3: 扩展词库管理页面

**修改文件**：`entry/src/main/ets/pages/UserLexiconManagerPage.ets`

添加以下功能：

1. **显示词库源列表**
2. **显示每个词库的状态和词条数**
3. **手动触发重载按钮**
4. **添加/删除词库源**

```typescript
@Entry
@Component
struct UserLexiconManagerPage {
  @State sources: LexiconSource[] = [];
  @State isLoading: boolean = false;
  
  private importManager: UserLexiconImportManager = ...; // 获取实例

  async aboutToAppear() {
    await this.loadSources();
  }

  async loadSources() {
    this.sources = this.importManager.getLoadedSources();
  }

  async onReloadAll() {
    this.isLoading = true;
    try {
      const results = await this.importManager.scanAndLoad();
      
      promptAction.showToast({
        message: `重载完成: ${results.filter(r => r.success).length} 个成功`,
        duration: 2000
      });
      
      await this.loadSources();
    } catch (err) {
      promptAction.showToast({
        message: '重载失败',
        duration: 2000
      });
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('用户词库管理')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        
        Blank()
        
        Button('重新加载')
          .onClick(() => this.onReloadAll())
      }
      .width('100%')
      .padding(16)

      // 词库源列表
      List() {
        ForEach(this.sources, (source: LexiconSource) => {
          ListItem() {
            Row() {
              Column() {
                Text(source.name)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                
                Text(source.path)
                  .fontSize(12)
                  .fontColor('#999999')
                  .margin({ top: 4 })
                
                Text(`优先级: ${source.priority} | 模式: ${source.mode}`)
                  .fontSize(12)
                  .fontColor('#999999')
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              
              Toggle({ type: ToggleType.Switch, isOn: source.enabled })
                .onChange((isOn: boolean) => {
                  source.enabled = isOn;
                  // 保存配置
                })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.White)
            .borderRadius(8)
            .margin({ left: 12, right: 12, top: 8 })
          }
        })
      }
      .layoutWeight(1)

      // 添加词库按钮
      Button('添加词库源')
        .width('90%')
        .margin({ bottom: 16 })
        .onClick(() => {
          // 打开文件选择器或输入对话框
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
```

---

## 通用实现要求

### 代码规范

1. **类型安全**：
   - 使用 TypeScript 严格模式
   - 所有公共方法都要有类型注解
   - 避免使用 `any` 类型

2. **异步处理**：
   - 使用 `async/await` 而不是回调
   - 所有 Promise 都要 `await` 或 `.catch()`

3. **错误处理**：
   - 所有可能失败的操作都用 `try-catch` 包裹
   - 使用 `Logger` 记录错误和关键操作
   - 不要让异常导致应用崩溃

4. **命名规范**：
   - 类名：PascalCase
   - 方法名：camelCase
   - 常量：UPPER_SNAKE_CASE
   - 私有成员：以 `private` 标记

### 测试要求

为每个新功能创建测试文件：

**文件位置**：`entry/src/test/<功能名>.test.ets`

**示例**：`entry/src/test/CommitHistoryManager.test.ets`

```typescript
import { describe, it, expect } from '@ohos/hypium';
import { CommitHistoryManager } from '../main/ets/application/CommitHistoryManager';

export default function commitHistoryManagerTest() {
  describe('CommitHistoryManager', () => {
    it('应该能添加提交记录', () => {
      const manager = new CommitHistoryManager();
      manager.addCommit('测试文本');
      
      const last = manager.getLastCommit();
      expect(last).assertEqual('测试文本');
    });

    it('应该限制历史记录数量', () => {
      const manager = new CommitHistoryManager();
      
      for (let i = 0; i < 15; i++) {
        manager.addCommit(`文本${i}`);
      }
      
      expect(manager.getHistorySize()).assertEqual(10);
    });

    it('应该能清空历史记录', () => {
      const manager = new CommitHistoryManager();
      manager.addCommit('测试');
      manager.clear();
      
      expect(manager.getHistorySize()).assertEqual(0);
      expect(manager.getLastCommit()).assertEqual(null);
    });
  });
}
```

### 日志要求

使用统一的 Logger：

```typescript
import { Logger } from '../common/logging/Logger';

const TAG = 'YourClassName';
const LOGGER = new Logger(TAG);

// 日志级别
LOGGER.debug('调试信息');    // 开发调试
LOGGER.info('操作成功');     // 正常操作
LOGGER.warn('潜在问题');     // 警告
LOGGER.error('操作失败');    // 错误
```

### 性能要求

1. **避免阻塞主线程**：
   - 文件IO使用异步方法
   - 大量计算考虑放到 Worker

2. **内存管理**：
   - 历史记录设置合理上限
   - 及时清理不用的对象
   - 避免内存泄漏

3. **响应速度**：
   - 用户操作应在100ms内响应
   - 加载操作显示进度指示

### 兼容性要求

1. **HarmonyOS 版本**：
   - 最低支持 HarmonyOS 4.0
   - 使用的API都要检查版本兼容性

2. **降级处理**：
   - API 不可用时优雅降级
   - 不能因为功能不可用而崩溃

3. **配置迁移**：
   - 新增配置项提供默认值
   - 兼容旧版本的配置格式

---

## 实现优先级

按以下顺序实现：

1. **第一阶段（核心功能）**：
   - ✅ 功能1：重复上屏
   - ✅ 功能2：撤销上屏
   - ✅ 功能3：完善文档（成对符号）

2. **第二阶段（UI优化）**：
   - ✅ 功能5：分类词库UI
   - ✅ 功能6：用户词库导入UI

3. **第三阶段（文档完善）**：
   - ✅ 功能4：技术限制说明

---

## 验收标准

每个功能完成后，需要满足：

1. ✅ 代码编译通过，无 TypeScript 错误
2. ✅ 单元测试通过
3. ✅ 功能测试通过（手动测试或自动化测试）
4. ✅ 代码已提交，commit 信息清晰
5. ✅ 添加必要的注释和文档

---

## 提交规范

使用语义化提交信息：

```bash
feat: 实现重复上屏功能
feat: 添加撤销上屏功能
feat: 添加分类词库UI
docs: 完善成对符号使用文档
docs: 添加按键模拟限制说明
fix: 修复撤销上屏的边界问题
refactor: 重构词库导入逻辑
test: 添加CommitHistoryManager测试
```

---

## 需要注意的现有代码

### 不要修改的文件（只读）：

- `entry/src/main/ets/infrastructure/ime/ImeConnectionService.ets`（除非必要）
- `entry/src/main/ets/infrastructure/native/NativeEngineGateway.ets`
- `engine-rust/` 目录下的 Rust 代码（除非必要）

### 需要小心修改的文件：

- `entry/src/main/ets/application/InputSessionController.ets` - 核心控制器，修改要谨慎
- `entry/src/main/ets/application/KeyboardController.ets` - 添加动作处理即可

### 可以自由创建的文件：

- `entry/src/main/ets/application/` 下的新管理器类
- `entry/src/main/ets/presentation/settings/` 下的新页面
- `entry/src/test/` 下的测试文件
- `docs/` 下的文档文件

---

## 遇到问题怎么办

1. **编译错误**：
   - 检查 import 路径
   - 检查类型定义
   - 查看错误提示的行号

2. **运行时错误**：
   - 查看日志输出
   - 使用调试器断点调试
   - 检查 API 调用是否正确

3. **功能不生效**：
   - 确认代码路径被执行（添加日志）
   - 检查条件判断是否正确
   - 验证配置是否正确加载

4. **性能问题**：
   - 使用 profiler 分析性能
   - 检查是否有不必要的循环或递归
   - 优化频繁调用的方法

---

## 最后检查清单

完成所有功能后，进行最终检查：

- [ ] 所有代码编译通过
- [ ] 所有测试通过
- [ ] 功能手动测试通过
- [ ] 日志输出正常，无敏感信息
- [ ] 错误处理完善，不会崩溃
- [ ] 代码格式统一，符合规范
- [ ] 注释清晰，关键逻辑有说明
- [ ] 文档完整，使用说明清楚
- [ ] 提交信息规范，描述准确
- [ ] 性能测试通过，无明显卡顿

---

## 开始实现

现在请按照上述要求，逐个实现这6个功能。

遇到任何问题随时报告，我会提供帮助。

祝开发顺利！🚀
