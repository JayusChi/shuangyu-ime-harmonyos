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
