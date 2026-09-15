# 0.6.0 两项实机缺陷修复验证

## 结论

上一轮验收发现的两个缺陷均已修复，并在同一台实体设备上回归通过。

## 修复内容

### 1. 单次 `o` 间歇性变成 `oo`

- 将现代/旧版实体键回调的默认跨通道去重窗从 80ms 调整为 160ms。
- 跨通道重复事件改为按最早未配对事件优先配对，避免快速真实连击被延迟镜像错误配对。
- 增加重复事件抑制日志，记录通道、按下/抬起阶段和键码。
- 新增 96ms 延迟回调和快速同键连击的回归测试。

### 2. 架空行左右光标键无效

- 在生产使用的 `ImeConnectionService` 中补齐 `moveCursor`。
- 动作现在调用当前绑定编辑器的 `InputClient.moveCursor`，并检查会话所有权。
- 成功移动后清除已失效的删除恢复状态；无会话或编辑器拒绝时显式失败。
- 新增生产服务接口存在性和无会话失败路径测试；既有上层双方向路由测试继续通过。

## 自动验证

- `hvigorw --no-daemon --mode module -p module=entry@default test`：成功。
- `hvigorw --no-daemon --mode module -p module=entry@default assembleHap`：成功。
- 新签名 HAP：94,804,611 字节。
- SHA-256：`B1CBE793B632DAD00119DEB7E9BCC915DA33A255EC3A1C7753DE08CF0F8D7D55`。

## 实机回归

- 设备：HUAWEI nova 12（BLK-AL00）。
- 系统：HarmonyOS `BLK-AL00 6.1.0.135(SP8C00E120R2P6)`。
- 安装：覆盖安装成功，无签名重置、无数据清除。
- 输入法：`com.corrosion.shuangyuime`，`FULL_EXPERIENCE_MODE`。
- 未启动或使用模拟器。

### 实体键 `o`

- 连续执行 12 轮“清码 → 单次 `o`”。
- 结果：12/12 的输入码均为单个 `o`，没有出现 `oo`。
- 每轮日志只有一次 `physical key consumed`；延迟到达的 legacy down/up 均记录为 `physical key duplicate suppressed`。
- 证据：`fix_o_1.json`～`fix_o_12.json`。

### 浏览器输入框左右移动

- 初始文本 `AB`。
- 操作：左移 → 输入 `C` → 右移 → 输入 `D`。
- 最终文本：`ACBD`，符合预期。
- 日志：`move_cursor_left ... success=true`、`move_cursor_right ... success=true`。
- 证据：`fix_cursor_ab.json`、`fix_cursor_browser_result.json`。

### 原生 ArkUI TextInput 左右移动

- 在应用内用户词库搜索框重复相同操作。
- 最终文本：`ACBD`，符合预期。
- ArkUI 与输入法日志均确认左右移动成功。
- 证据：`fix_native_ab.json`、`fix_cursor_native_result.json`。

## 收尾

- 测试网页服务与 HDC 端口转发已关闭。
- 设置恢复为虚拟键盘、26 键全拼、候选栏、300ms、1.0 倍高度、架空行关闭。
- 搜索框测试内容未保存为用户词条。
- 当前 hilog 缓冲区未检出本应用的 fatal、panic、SIGSEGV、SIGABRT 或内部引擎错误。
- 实体键路径仍使用真机系统按键注入；外接 USB/蓝牙键盘型号兼容性可在客户现场补充确认。
