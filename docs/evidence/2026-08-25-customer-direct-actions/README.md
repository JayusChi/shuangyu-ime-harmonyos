# 0.5.0 客户 44 条直通确认实施与验收

日期：2026-08-25

## 结论

- 客户回填：33 条正向选择、6 条“不需要”、5 条未填写。
- 已交付：31 条功能项；另有 1 条按客户确认保持 HTTP 安全拒绝。
- 未交付：`ofi` 复制单字反查 1 条，受平台权限等级限制；6 条“不需要”和 5 条未填写项保持不变。
- 最终 Release 未包含 `READ_PASTEBOARD`，不会显示失效的 `[复制反查]` 候选。

## 已交付范围

| 范围 | 编码/动作 |
| --- | --- |
| 日期与时间 | `orq` 两种日期、`onl` 农历、`ouj` 两种时间 |
| 固定页面与文本 | `xhgw` 小鹤官网、`xhg` 插入 HTTPS、`xhrm`/`orm` 固定帮助页 |
| 本地入口 | `ocd` 设置页、`oyh` 用户词库、`odr` 授权导入 |
| 编辑与输出 | `oui`/`oiu` 删当前行、`ojf` 简繁、`ovy` 中英标点、`oqb` 全半角、`jysi` 多行《静夜思》 |
| 标点与码长 | `ovn` 600/0 ms、`osz` 数字句点开关、`oqma` 空码 4/12、`odp` 四码后顶/唯一自动上屏 |
| 分类 | `ojj` 熟手/常规/初学三预设、`oej` 二简次选开关 |

词库预设只改变 `full-code-word`、`full-code-character`、`rare-character`，不会覆盖客户其他分类开关。用户词库入口只打开本应用沙箱内的管理页，不执行外部任意路径。

## 平台边界：`ofi`

客户选择的语义是“读取已经复制的单个汉字用于反查，但不执行粘贴”。设备验证显示：

- 应用 `appPrivilegeLevel=normal`；
- `ohos.permission.READ_PASTEBOARD` 为 `availableLevel=SYSTEM_BASIC`；
- 权限状态 `grantStatus=-1`，请求不会产生可用授权；
- 点击试验入口会失败。

因此正式包撤下了该候选、实现接口和权限声明。后续需要客户二选一：改成用户显式粘贴/对当前输入字符反查，或由客户提供可用于分发的系统级签名与授权条件。

## 主机验证

- ArkTS 全量单测：PASS。
- Rust：`code-table-runtime`、`engine-protocol`、`ime-engine`、`ime-ffi` 全量 PASS；fmt PASS。
- x86_64 与 arm64-v8a OHOS Release Native：PASS。
- Release 构建、实包校验、资源正负门禁：PASS。
- signed HAP：`entry/build/default/outputs/default/entry-default-signed.hap`
- 大小：71,255,985 bytes
- SHA-256：`39DA69D38C4BD5F0BCFE9358F8E2487BCFF6DF2A766DAD4581345DDF1749B4E9`

## 三设备验收

| 设备 | 最终包结果 |
| --- | --- |
| Phone | `0.5.0 / 5000000`、Release；26 键音形输入 `orq` 显示两条日期候选，点击后上屏 `2026-08-25`；`ofi` 入口及失败提示不存在 |
| Pad | `0.5.0 / 5000000`、Release；26 键音形输入 `orq` 显示两条日期候选，无方案切换失败提示 |
| 2in1 | `0.5.0 / 5000000`、Release；26 键音形实体键输入 `orq` 显示两条日期候选，点击后上屏 `2026-08-25` |

本轮使用同一份 SHA-256 如上的 x86_64 signed Release。26 键音形热切换、Pad/2in1 T9 冷启动及 2in1 实体智能句号的完整失败路径证据分别保留在同日既有专项目录；本轮代表性直通证据位于 `phone/`、`pad/`、`2in1/`。
