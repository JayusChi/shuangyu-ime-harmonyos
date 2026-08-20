# 设备 A～J 验收

设备：`127.0.0.1:5555`，x86_64 HarmonyOS 6.1 模拟器  
入口：Debug-only `pages/DebugCodeTable`  
数据：构建期临时注入的项目原创 `code-table-fixture`，以及页面写入应用沙箱的测试用户文件

## 结果

| 用例 | 结果 | 关键实际值 |
| --- | --- | --- |
| A 基线系统候选 | PASS | `ab -> 核心丁000004 / 短语戊000004 / 扩展己000004` |
| B 普通用户词 | PASS | `调试用户词` 进入完整候选，系统候选保留 |
| C 精确删除 | PASS | 删除 `aowk + 测`；`dzqc` 下同名 `测` 保留 |
| D 多个固顶 | PASS | `固顶甲 / 固顶乙` 为稳定保护前缀 |
| E `#2` 与固顶保护 | PASS | `保护词 / 位置词 / ...`，位置词不越过固顶 |
| F 后规则覆盖 | PASS | 普通→固顶→`#2` 后仅最后规则生效，`覆盖词` 恰好一次且位于第二 |
| G 完整列表后分页 | PASS | 第一页前缀 `分页固顶/分页位置`；第二页连续稳定 |
| H 进程/句柄重建 | PASS | 首次 `reusedExisting=false`；强停并重启应用后 `true`，首选仍为 `重启固顶` |
| I 损坏与备份恢复 | PASS | 损坏主文件后从备份恢复 `恢复固顶`，系统候选仍可用 |
| J 切回小鹤双拼 | PASS | `nihc -> 你好`，`uurufa -> 输入法`，码表规则不串入 |

## 关键证据文件

- `stage1164_restart_first_top.json`：首次启动总结果及 A～E。
- `stage1164_restart_first_lower.json` / `.jpeg`：首次启动 F～I，H 记录 `reusedExisting=false`。
- `stage1164_restart_second_top.json`：应用强停重启后总结果及 A～E。
- `stage1164_restart_second_lower.json` / `.jpeg`：第二次启动 F～H，H 记录 `reusedExisting=true`。
- `stage1164_restart_second_bottom.json` / `.jpeg`：第二次启动 H～J 均 PASS。

目录中 `stage1164_result*`、`stage1164_lower*` 是增加跨进程哨兵前的同日初次 A～J 截图；`stage1164_initial.json`、`stage1164_restart_first.json` 和两个 `*_index/scrolled.json` 是设置页导航布局记录，不作为跨进程结论的替代。
