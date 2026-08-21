# 直通编码功能支持分析

## 客户需求分析

客户询问是否支持以下"直通编码"功能：

1. **重复上屏**：`$cmd({last_0},[重复])` - 重复上次上屏的内容
2. **撤销上屏**：刚上屏的字词立刻撤回
3. **成对符号光标居中**：`$cmd(""keyboard(<21>),"")` - 插入`""`后光标在中间
4. **模拟End键**：`$cmd(keyboard(<123>),[End])` - 模拟键盘End键
5. **启用同时关闭不同的分类词库**
6. **导入固定位置的用户词库（替换或补充用户词）**

---

## 当前支持情况

### ✅ 已支持的功能

#### 1. 成对符号光标居中 ✅
- **实现位置**：`ProtocolActionExecutor.ets` + `ImeConnectionService.ets`
- **实现方式**：通过 `INSERT_PAIR` 协议动作
- **代码位置**：
  - `entry/src/main/ets/application/ProtocolActionExecutor.ets:75-100`
  - `entry/src/main/ets/infrastructure/ime/ImeConnectionService.ets:1493-1546`
- **使用方式**：引擎返回 `InsertPairAction`，系统自动执行插入+光标定位

#### 2. 分类词库管理 ✅
- **实现位置**：`NativeEngineTypes.ets` + Native引擎
- **支持功能**：
  - 定义多个词库分类（PRIMARY / EXTENSION / USER / FUNCTIONAL）
  - 动态启用/禁用词库分类
  - 词库分类元数据管理（名称、顺序、默认状态）
- **相关接口**：
  ```typescript
  getCodeTableCategoryConfig(handle: number): CodeTableCategoryConfig;
  setCodeTableCategories(handle: number, enabledCategoryIds: string[]): CompositionResult;
  ```

#### 3. 用户词库导入/管理 ✅
- **实现位置**：`UserLexiconController.ets` + Native引擎
- **支持功能**：
  - 加载用户词库：`loadUserLexicon(path: string)`
  - 保存用户词库：`saveUserLexicon(path, revision, content)`
  - 重载用户词库：`reloadUserLexicon(handle: number)`
  - 支持动作类型：ADD（添加）、DELETE（删除）、FIXED（固定）、POSITION（位置）
- **词库格式**：有完整的解析和验证系统

---

### ❌ 不支持的功能

#### 1. 重复上屏 ❌
**原因**：
- 没有"上屏历史记录"机制
- 没有保存最后一次提交文本的状态
- 无法追溯已提交的内容

**需要添加**：
- 上屏历史缓冲区（至少记录最近N次上屏）
- 历史记录管理器
- 重复上屏命令处理

#### 2. 撤销上屏 ❌
**原因**：
- HarmonyOS InputMethodEngine API 不支持"撤销已提交文本"
- 已上屏的文本已经提交给编辑器，输入法无法删除
- 需要编辑器配合（获取光标位置+删除文本）

**技术限制**：
- `inputClient.insertText()` 和 `commitPreviewText()` 是单向操作
- 没有 `undoCommit()` 或类似API
- 只能通过 `deleteForward(length)` 间接实现，但需要：
  1. 记住上屏文本的长度
  2. 假设用户没有移动光标
  3. 编辑器支持删除操作

#### 3. 模拟物理键盘按键（End/Home等）❌
**原因**：
- `inputClient.sendKeyFunction()` 仅支持回车键类型：
  ```typescript
  ENTER_KEY_TYPE_NEWLINE
  ENTER_KEY_TYPE_SEARCH
  ENTER_KEY_TYPE_DONE
  ENTER_KEY_TYPE_NEXT
  ENTER_KEY_TYPE_GO
  ENTER_KEY_TYPE_SEND
  ```
- HarmonyOS API 未提供通用的"模拟按键"接口
- 没有 `sendKey(keyCode)` 类似的API

**可能的替代方案**：
- 部分功能可通过文本操作模拟：
  - End键 → 无法模拟（需要编辑器API支持移动光标到行尾）
  - 方向键 → 无法模拟
  - 退格键 → 可通过 `deleteForward()` 实现

#### 4. 直通编码语法系统 `$cmd(...)` ❌
**原因**：
- 当前引擎没有"命令解析器"
- 码表中的编码直接映射到候选词，没有"指令"概念
- 没有类似 Rime lua 脚本的扩展机制

**需要添加**：
- 命令语法解析器
- 命令执行框架
- 扩展引擎的候选生成逻辑

---

## 实现难度评估

| 功能 | 支持状态 | 实现难度 | 技术可行性 |
|------|---------|---------|-----------|
| 成对符号光标居中 | ✅ 已支持 | - | ✅ 完全可行 |
| 分类词库管理 | ✅ 已支持 | - | ✅ 完全可行 |
| 用户词库导入 | ✅ 已支持 | - | ✅ 完全可行 |
| 重复上屏 | ❌ 不支持 | 🟡 中等 | ✅ 完全可行 |
| 撤销上屏 | ❌ 不支持 | 🔴 困难 | 🟡 部分可行（有限制）|
| 模拟End/方向键 | ❌ 不支持 | 🔴 困难 | ❌ API不支持 |
| 直通编码系统 | ❌ 不支持 | 🔴 非常困难 | ✅ 可行但工程量大 |

---

## 技术限制说明

### HarmonyOS InputMethodEngine API 限制：

1. **只能输入，不能控制光标移动**：
   - ❌ 没有 `moveCursor(offset)` 类似API
   - ❌ 无法模拟方向键、Home/End键
   - ✅ 只能通过 `selectByRange()` 间接设置光标位置（需要知道绝对位置）

2. **已提交文本无法直接撤销**：
   - ✅ 可以删除指定长度：`deleteForward(length)`
   - ❌ 但需要手动记录长度，且假设用户没有移动光标

3. **只支持有限的功能键**：
   - ✅ 回车键的各种变体（搜索、完成、下一个等）
   - ❌ 不支持其他功能键（Esc、Tab、方向键、End等）

---

## 建议

### 对客户的答复：

**您好，根据代码分析：**

**✅ 已支持的功能：**
- ✅ **成对符号光标居中** - 已完整实现，通过引擎协议支持
- ✅ **分类词库管理** - 支持启用/禁用不同词库分类
- ✅ **用户词库导入** - 支持从固定路径加载、保存、重载用户词库

**❌ 不支持的功能：**
- ❌ **重复上屏** - 需要添加上屏历史记录功能
- ❌ **撤销上屏** - 可以实现，但有技术限制（需假设用户未移动光标）
- ❌ **模拟End/方向键** - HarmonyOS API不支持，无法实现
- ❌ **$cmd()直通编码语法** - 需要大幅改造引擎，添加命令解析和执行系统

**技术限制：**
HarmonyOS的输入法API比较基础，只能：
- ✅ 输入文本
- ✅ 删除文本（需要知道长度）
- ✅ 设置光标位置（需要知道绝对位置）
- ❌ 不能模拟物理按键
- ❌ 不能相对移动光标

**如果要支持更多功能，建议优先实现：**
1. 🟢 重复上屏（可行性高，工程量中等）
2. 🟡 撤销上屏（可行但有限制）
3. 🔴 直通编码系统（工程量大，需要改造引擎架构）

