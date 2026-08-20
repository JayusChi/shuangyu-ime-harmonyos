# 阶段 3.4 验证记录

日期：2026-07-21

## 审查与实现结论

- 正式中文布局由 `createChineseLetterRows` 统一创建，并强制使用大写显示状态；手机竖屏、手机横屏和 Pad 只改变度量，不复制字母布局。
- `KeyboardKeySpec.label` 是键帽、按键预览和字母无障碍文案的显示来源；`KeyboardAction.letter` 独立保存小写输入值。
- `InputSessionController.insertLetter` 在中文引擎调用前执行 `toLowerCase()`，Rust 引擎、系统词库、用户词库和学习记录仍使用原有小写编码。
- 英文布局继续按 `LOWERCASE / ONE_SHOT_UPPERCASE / CAPS_LOCK` 生成标签和输入值，中文固定大写显示没有进入英文公共状态机。
- 原文本字符 `⌄` 依赖设备字体基线，固定偏移无法同时覆盖手机和 Pad。现改用 `24vp` SVG，由固定操作 Row 以 `justifyContent/alignItems = Center` 做几何居中。
- 字母字号由静态竖屏 `18→16vp`、横屏 `16→15vp`；动态度量由键高 `0.42` 调整为 `0.36`，范围收敛到 `13–21vp`。预览字号同步限制为 `20–32vp`。按键尺寸、权重、间距、ID 和热区没有改变。

## 自动化结果

| 门禁 | 结果 |
| --- | --- |
| ArkTS 全量单测 | PASS，Hvigor `BUILD SUCCESSFUL` |
| 中文三行 A-Z 显示、a-z 动作、ID、预览和无障碍合同 | PASS |
| 大写动作 `N` 到引擎、`rawInput` 与编辑器预览均归一化为 `n` | PASS |
| 英文 lowercase、one-shot uppercase、Caps Lock 回归 | PASS |
| 手机/横屏/Pad 字号上限合同 | PASS |
| SVG 资源与 ArkUI Debug 编译 | PASS |
| Debug HAP 双 ABI Native 构建 | PASS，x86_64 与 arm64-v8a |
| Debug HAP | PASS，14,614,179 bytes，SHA-256 `3365325EB77DC6A4C4E6BCBFAB2C80898049BB217989C9419884DD12913CD501` |

执行命令：

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-hap.ps1 -SkipRust -BuildMode debug
```

## 模拟器验收

验收脚本：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\device-accept-stage3_3.ps1 -Target 127.0.0.1:5555 -EvidenceStage stage3.4
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\device-accept-stage3_3.ps1 -Target 127.0.0.1:5557 -EvidenceStage stage3.4
```

| 目标 | 形态 | 结果 |
| --- | --- | --- |
| `127.0.0.1:5555` | 1320×2856，竖屏手机，x86_64 | PASS |
| `127.0.0.1:5557` | 2880×1920，横屏平板，x86_64 | PASS |

两端均验证：

- 中文三行 26 个字母节点全部显示大写；
- 普通中文点击 `N`、`I` 后组合与候选链路正常，输入码保持 `ni`；
- 大写直输开启/关闭不造成键帽跳变，分词键切换不造成第三行跳位；
- 隐藏键 SVG 位于固定按键区域几何中心，中心坐标误差不超过 `2px`；
- 缩小后的字母在三行键帽内无裁切、重叠或对齐变化；
- 两端 idle 截图均人工复核通过。

手机布局树中 SVG 为 `[1170,1677][1254,1761]`，父按键为 `[1128,1638][1293,1800]`；平板 SVG 为 `[2733,915][2781,963]`，父按键为 `[2704,880][2808,998]`。两组 Y 中心完全一致，X 中心因奇数像素宽度相差不超过 `1.5px`。

证据位于：

- `docs/evidence/stage3.4/device/127_0_0_1_5555`
- `docs/evidence/stage3.4/device/127_0_0_1_5557`

## 未完成项与风险

- 未执行 ARM64 物理真机验收；当前 ARM64 覆盖为交叉构建。
- 未取得可稳定旋转的独立手机横屏模拟器截图；手机横屏使用与已通过的动态度量测试相同的布局代码，并有字号边界自动化覆盖，但仍应在发布前补一次设备验收。
- 暗色主题和系统超大字体未在本轮设备脚本中自动切换；颜色沿用现有主题 palette，SVG 使用同一 `functionKeyText` 着色，动态字体上限已有自动化约束。

在当前已声明的模拟器范围内，阶段 3.4 验收标准满足，状态标记为 `COMPLETED`。
