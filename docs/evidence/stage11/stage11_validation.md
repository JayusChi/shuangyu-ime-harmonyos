# 阶段 11 验证记录

日期：2026-07-10

## 结论

阶段 11 本地总门禁与 x86_64 HarmonyOS API 24 模拟器验收均通过。真实用户模型清空用例先生成非零学习记录，再从设置页二次确认清空，重新唤起输入法后断言记录数为 0。

## 自动化结果

| 项目 | 真实结果 |
| --- | --- |
| ArkTS | `BUILD SUCCESSFUL`；全套 85 个 `it` 声明，Stage 11 新增 17 个 |
| Rust fmt | 通过 |
| Rust clippy | `cargo clippy --workspace --all-targets -- -D warnings` 通过 |
| Rust workspace | 全量通过；重点包 user-model 20、candidate-ranking 10、sentence-decoder 21、ime-engine 32 + 阶段 7/8/9 集成各 1、ime-ffi 16 |
| Native x86_64 | 通过；`libime_ffi.a` 23,909,764 bytes |
| Native arm64-v8a | 通过；`libime_ffi.a` 24,493,554 bytes |
| HAP | 通过；unsigned，7,502,316 bytes |
| Stage 10 设备回归 | `STAGE10_DEVICE_ACCEPTANCE_RESULT=PASS` |
| Stage 11 模拟器 | `STAGE11_DEVICE_ACCEPTANCE_RESULT=PASS` |

完整门禁日志：`verify-stage11.log`。设备日志：`device/stage11_device_acceptance.log`。

## HAP

```text
路径：entry/build/default/outputs/default/entry-default-unsigned.hap
大小：7,502,316 bytes
SHA-256：7AE1BC7023C4310A1FD71DFD518A3DD6884200C8E940F8E366E5D01819AE4CCB
签名：未配置 signingConfigs，unsigned 验证产物
```

最终通过设备验收时安装的同源 HAP SHA-256 为 `46AB357D4DDC198D03E00BB1C1437C24593EA0E14E9C7BA5B5B82F8C6C9661AD`；完整门禁重新打包后的最终产物哈希如上。

## 模拟器覆盖

- 默认正式首页、Debug 入口、小鹤唯一方案与中文本地化。
- 浅色、深色、三档高度、三档候选字号、四档震动选择和按键音开关。
- 所有设置在主进程重启后保持。
- 用户学习开关即时改变；Stage 10 密码/数字密码学习保护回归通过。
- 清空操作有二次确认；确认后通过本包定向 Common Event 通知输入法运行时，复用 Stage 9 Native/Rust 清空接口，模型计数从非零恢复为 0。
- 高度布局转储、主题截图、学习开关和清空前后模型转储均保存在 `device/`。

## 限制与警告

- x86_64 模拟器不能证明真实物理震感；`PHYSICAL_HAPTIC_RESULT=NOT_TESTED_REQUIRES_ARM64_DEVICE`。
- 模拟器未对扬声器输出做客观采集；`PHYSICAL_KEY_SOUND_RESULT=NOT_OBJECTIVELY_CAPTURED`。
- ArkTS 构建存在 SDK 的可抛异常提示及 `ContentType`、`showToast`、`AlertDialog.show`、`router.pushUrl` 弃用警告，但没有编译或测试失败。
- 未配置 HAP signingConfigs。
