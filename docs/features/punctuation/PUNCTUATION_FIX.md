# 实体键盘标点符号修复说明

## 问题描述

实体键盘中，当有候选词未上屏时打标点符号（如逗号、句号等），原有行为是将标点追加到预览文本后面，不提交候选词。

例如：输入 "bak," 时，原有行为可能是显示预览 "吧," 但不上屏。

## 需求

当候选词未上屏时打标点符号，应该：
1. 先提交第一候选词
2. 然后输入标点符号

例如：输入 "bak," 应该上屏 "吧，"（先提交第一候选"吧"，再输入中文逗号"，"）

## 修改内容

### InputSessionController.ets (第816-835行)

修改了 `insertPhysicalPunctuation` 方法，在插入标点前先检查是否有候选词：

```typescript
// 修改前
async insertPhysicalPunctuation(
  character: string,
  generation: number = this.getInputSessionGeneration()
): Promise<InputOperationResult> {
  if (character.length !== 1) {
    return inputOperationFailed(ImeErrorCode.INVALID_ARGUMENT, 'physical punctuation requires one character');
  }
  return this.insertText(character, 'physical punctuation suffix', generation);
}

// 修改后
async insertPhysicalPunctuation(
  character: string,
  generation: number = this.getInputSessionGeneration()
): Promise<InputOperationResult> {
  if (character.length !== 1) {
    return inputOperationFailed(ImeErrorCode.INVALID_ARGUMENT, 'physical punctuation requires one character');
  }
  // If there are candidates, commit the first one before inserting punctuation
  const state = this.store.getSnapshot();
  if (state.keyboardMode === KeyboardMode.CHINESE && state.rawInput.length > 0 &&
    !state.rawInput.startsWith(';') && state.candidates.length > 0) {
    const confirmed = await this.commitCandidate(0, generation);
    if (!confirmed.success) {
      return confirmed;
    }
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('punctuation candidate commit');
    }
  }
  return this.insertText(character, 'physical punctuation suffix', generation);
}
```

**变更说明**：
1. 检查是否在中文输入模式 (`KeyboardMode.CHINESE`)
2. 检查是否有未提交的输入 (`rawInput.length > 0`)
3. 检查不是引导快符状态 (`!state.rawInput.startsWith(';')`)
4. 检查是否有候选词 (`candidates.length > 0`)
5. 如果以上条件都满足，先提交第一候选词 (`commitCandidate(0)`)
6. 然后再插入标点符号

## 适用的标点符号

此逻辑适用于所有通过物理键盘输入的标点符号，包括但不限于：
- 逗号 `,` → `，`
- 句号 `.` → `。`
- 分号 `;` (非引导快符时)
- 冒号 `:` → `：`
- 感叹号 `!` → `！`
- 问号 `?` → `？`
- 其他标点符号

标点符号会自动转换为中文标点（通过 `normalizeChinesePunctuation` 函数）。

## 使用场景

### 场景1：输入单词后加标点
1. 输入 "bak" → 显示候选词：吧、把、霸...
2. 按逗号键 `,` → 上屏："吧，"（第一候选+中文逗号）

### 场景2：输入句子
1. 输入 "ni" → 显示候选词：你、尼、呢...
2. 按句号键 `.` → 上屏："你。"（第一候选+中文句号）

### 场景3：无候选词时
1. 无输入或无候选词
2. 按标点键 → 直接输入标点符号（行为不变）

### 场景4：引导快符状态
1. 输入 ";" 进入引导快符状态
2. 按其他键 → 不会触发候选提交（因为 `rawInput.startsWith(';')` 为真）

## 相关文件

- `entry/src/main/ets/application/InputSessionController.ets` - 主要修改
- `entry/src/main/ets/domain/keyboard/PhysicalKeyboardRouting.ets` - 标点路由逻辑（未修改）
- `entry/src/main/ets/application/InputMethodLifecycleDispatcher.ets` - 标点处理调用（未修改）

## 技术细节

### 标点追踪机制
原有的标点追踪机制（`PhysicalEditorSuffixTracker`）仍然保留，用于在按退格键时删除标点而不影响输入缓冲区。但是由于标点现在会先提交候选词，所以追踪的标点是在候选词提交之后追加的。

### 与分号键的配合
这个修改与之前的分号键修复是互补的：
- 分号在有多个候选时选择第二候选
- 分号在只有一个候选时选择第一候选并激活引导状态
- 其他标点符号在有候选时选择第一候选并输入标点

两者一起确保了实体键盘的完整体验。

## 验证方法

在DevEco Studio中：
1. 部署应用到设备
2. 连接实体键盘
3. 在文本编辑器中测试：
   - 输入 "bak,"，验证上屏 "吧，"
   - 输入 "ni."，验证上屏 "你。"
   - 输入 "hao!"，验证上屏 "好！"
