# Phone results

目标：x86_64 Phone 模拟器，OpenHarmony 6.1.1.125，1320×2856 竖屏。

- Stage 10 编辑器链路：在密码场景前的普通中文输入、候选、预编辑删除、候选/空格
  提交、Shift/Caps、数字与符号模式均 PASS。
- 阻断失败：截图只显示受保护的灰色安全键盘表面，`uitest` 布局中没有任何键帽；
  现有系统安全键盘识别依赖键 ID，识别失败后误标为 `APPLICATION_SAFE_LAYOUT`，
  随后断言 `password English layout retains Shift` 失败。不能据此认定产品 Shift 缺失。
- Stage 11 设置复跑：正式设置入口、主题、键盘高度、学习开关、候选字号、触感、
  按键音及强停后的持久化均 PASS；清空用户模型流程因自动化仍假设设置页内有
  Debug 入口而停止。
- signed Release 独立 TextInput：NOT RUN，设备未安装 `com.example.nexttest`。

结论：Phone 发布验收未通过。
