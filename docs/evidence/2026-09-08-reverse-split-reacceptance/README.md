# 逆切分模式重新验收（2026-09-08）

结论：当前工作区已实现本次要求的“逆切分 → 自动切分”，此次代码核查、主机测试和已连接鸿蒙模拟器的输入链路验收通过。未发现需要修改功能逻辑的问题；新增 3 项正式词库回归测试。

## 本次执行结果

| 层级 | 结果 | 证据（仓库根目录下） |
| --- | --- | --- |
| Rust：code-table-runtime / ime-engine / ime-ffi 原有测试 | 318 通过，0 失败 | `outputs/reverse-split-reaccept-20260908-rust.log` |
| 正式词库切分专项（含新增 3 项） | 5 通过，0 失败；其中 2 项已包含于上述 318 项 | `outputs/reverse-split-reaccept-20260908-formal.log` |
| ArkTS 全量 | 639 通过，0 失败/错误/忽略 | `outputs/reverse-split-reaccept-20260908/arkts-test-result.txt`、`outputs/reverse-split-reaccept-20260908-arkts.log` |
| Native gateway 主机适配层 | 通过；Native bridge 为模拟 | `outputs/reverse-split-reaccept-20260908/gateway-result.txt` |
| Rust 格式检查 | 通过 | `outputs/reverse-split-reaccept-20260908-fmt.log` |
| 模拟器独立编辑器主流程 | 14 个检查点通过 | `outputs/reverse-split-reaccept-20260908/results.json` |
| 设置页、跨进程同步、重启保留 | 通过；结束恢复传统模式 | `outputs/reverse-split-reaccept-20260908/restart-results.txt`、`settings-final-toggles.txt` |

## 需求对应

- 独立开关，默认传统：默认设置和旧版本迁移测试通过；设置页存在“切分模式”开关，实测可开启。默认值属于主机测试，本次没有清空模拟器用户设置来模拟首次安装。
- `oit`：显示 `1. [传统]`、`2. [切分]`，选择不把标签上屏；与设置页共用持久化状态。设置页开启后独立编辑器立即可切分；结束通过 `oit1` 关闭后设置页开关为关闭。
- 只在四码空码且无有效长码续码时做精确 `2+2`：已有四码词、长码、功能直通仍优先；任一半无二简沿用原空码清除/保留规则。运行时边界测试通过。
- 前半首选＋后半唯一：运行时覆盖前半唯一和重码；正式词库验证自动提交、普通符号在前/后半均可拼接（`hfoi → 很😊`、`oihf → 😊很`）。
- 后半重码：模拟器 `hfkn` 显示 `hf'kn`、`1. 很可能`、`2. 困难`；数字 2 实际提交 `很困难`，没有丢失或提前提交“很”。
- 第五码：模拟器 `hfknn` 提交 `很可能` 并保留新码 `n`；正式词库页大小 1、2、5、9 均验证，翻到第二页后继续输入也顶全局首选。
- 候选数：页大小为 1 仍保留重码状态，不会误自动提交；翻页选择次选提交完整组合。
- 分类：关闭后半次选所属分类会变为唯一自动提交，重新开启恢复重码。注意正式客户词库 `困难/kn` 属于“分类”(`category-secondary`)，并非“二简次选”分类。
- 符号分类关闭导致二简缺失时，四码清除阈值为 4/12 分别清空/保留，均不产生拼接提交。
- 退格：模拟器 `hf'kn → hfk → hf'kn` 正常，编辑器文字不变。
- 四组连续编码均在正式词库测试和模拟器中得到预期：`alyghfry → 按理应该很容易`、`gmycxnta → 干嘛要笑她`、`xtupjdma → 学双拼简单吗`、`nivtsmne → 你折腾什么呢`。最后一组仍有候选时正常确认首选，未将重码当作唯一自动上屏。

## 新增回归测试

文件：`engine-rust/crates/ime-engine/tests/xiaohe_yinxing_production.rs`

- `reverse_split_formal_page_sizes_preserve_ambiguity_and_fifth_key`
- `reverse_split_formal_category_switch_changes_unique_commit`
- `reverse_split_formal_symbol_halves_and_missing_category_fallback`

## 模拟器范围与截图

设备连接为 `127.0.0.1:5555`，桌面窗口形态，安装版本 `com.corrosion.shuangyuime` 0.8.0。使用 HDC 注入实体按键路径，在不同包名的独立验收应用中验证编辑器实际文字；设置开关使用 UI 点击。此处验收的是现有安装包，未重新构建或安装 HAP，未证明其与当前源码逐字节一致。

- 候选显示：`outputs/reverse-split-reaccept-20260908/04-split-candidates.png`
- 次选完整提交：`outputs/reverse-split-reaccept-20260908/05-second-commits-full.png`
- 第五码保留新码：`outputs/reverse-split-reaccept-20260908/06-fifth-keeps-next-code.png`
- 设置开启：`outputs/reverse-split-reaccept-20260908/settings-enabled.png`
- 进程重启后保持：`outputs/reverse-split-reaccept-20260908/restart-persisted.png`
- 恢复传统：`outputs/reverse-split-reaccept-20260908/settings-split-off.png`

本次未连接手机真机，未执行虚拟字母键盘的触屏全流程；不把模拟器实体按键结果写成手机真机/触屏验收通过。手动逆切分不属于本次需求。

## 执行中修正的测试环境与脚本问题

- ArkTS 首次因 `DEVECO_SDK_HOME` 无效失败，设为本机 DevEco Studio SDK 路径后重跑通过。
- 新增 Rust 专项初次链接时旧全量测试仍占用 Windows 测试可执行文件；待其完成后重跑。
- 新增分类用例最初误将 `困难/kn` 归为二简次选；核对真实源表后按“分类”测试，通过。
- 初版设备脚本在空组合状态发送 Esc，触发宿主隐藏/脱离输入法；改为按已知组合长度退格，主流程 14 点全部通过。最初失败保留于 `initial-script-results.json`。
- 设置页返回宿主时，第一次点到文字编辑菜单而未建立预期输入状态；重新聚焦空白搜索框并以候选出现为条件等待后通过，再实际强制停止输入法进程、重新连接验证设置保留。原始失败记录保留于 `settings-results.txt`。
