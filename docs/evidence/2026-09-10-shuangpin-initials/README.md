# 双拼声母回退与方案选项对齐

日期：2026-09-10。

## 行为

- 小鹤双拼保持合法声韵组合优先。不能组成合法声韵、且两键都是合法声母键时，拆为两个声母约束；例如 jd → j + d。
- 完整音节后的单个尾键作为声母参与整句词库匹配；u/i/v 分别按 sh/ch/zh 匹配。补入下一键后重新按正常双拼解析，退格可恢复声母候选。
- 正式词库首选：hduihfhcd / hd'ui'hf'hc'd → 还是很好的；qiuihfjdd / qi'ui'hf'jd'd → 其实很简单的。
- 按实际原始键数记录整句和部分候选的覆盖范围及候选 ID，声母槽各消耗 1 键。部分候选只在完整双键边界结束，避免把声声拆开后改变剩余输入的配对。整句上屏消耗全部 9 键。
- 声母检索使用复用的词库声母序列索引，在小鹤方案加载时预热，保留查询、图规模、路径及候选上限。没有词库匹配的声母不拼接成英文上屏候选。含声母的整句查询在搜索过程中约束碎片化分词，保留“其实”“简单”等词的路径；纯完整音节、全拼与九键保留原评分。
- 输入方案选项使用统一按钮宽度、圆点宽度和标签宽度，使小鹤双拼与拼音的两列圆点及键数标签对齐。

## 自动验证

- shuangpin-parser 与 sentence-decoder：73 项通过，覆盖 676 种双键合法读音映射、非法声韵的声声回退、回退后退格、未匹配声母、编码覆盖和查询预算。
- ime-engine 核心及候选/整句/用户学习回归、新增声母测试：70 项通过。包含正式词库、无整句词条的合成词库、整句上屏、部分上屏、补韵母、退格及 u/i/v。
- ArkTS：705 项通过，0 失败，0 错误。
- arm64-v8a 与 x86_64 原生库 release 编译并同步成功。
- 正式 release 签名包构建和资源门禁通过。
- 正式包：outputs/shuangpin-initials/entry-release-signed.hap
- 字节数：93242887
- SHA-256：8901E5DF67540A983C1EB64A30F210EFCB5C7929A8F79E03F995AFEF06039D8E

日志：outputs/shuangpin-initials-parser-decoder.log、shuangpin-initials-engine.log、shuangpin-initials-arkts-result.txt、shuangpin-initials-native-build.log、shuangpin-initials-release-build.log、shuangpin-initials-release-verify.log。

## 模拟器验证

手机 127.0.0.1:5555 与平板 127.0.0.1:5559 已连接。现有安装使用开发证书，正式发布证书覆盖安装返回 9568332；保留现有应用数据，另构建相同 release 代码的 default 产品以沿用开发签名。沿用开发签名覆盖安装成功，两台均 SIGNATURE_RESET=false。

- 手机（1320×2856）和平板（2880×1920）截图已目视检查；实际 UI 节点验证两列按钮、圆点、键数标签的左右边界逐像素一致，alignment-check.json 结果 PASS。
- 手机保持小鹤音形选中，平板保持小鹤双拼 26 键选中；更换选中状态不会移动圆点或文字。
- 截图与 UI 布局：phone.png、pad.png、phone-layout.json、pad-layout.json。
- 模拟器更新包：outputs/shuangpin-initials/entry-device-signed.hap（release 代码、现有开发签名）。
- 未进行实体手机或平板测试；两条整句输入由正式词库原生引擎回归验证。
