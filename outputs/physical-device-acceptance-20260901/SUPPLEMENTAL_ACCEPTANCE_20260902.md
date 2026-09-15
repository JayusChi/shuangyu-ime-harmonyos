# 补充实机验收报告（2026-09-02）

## 验收环境

- 设备：Huawei nova 12（BLK-AL00）
- 连接目标：`192.168.1.136:44621`
- 输入法：`com.corrosion.shuangyuime`
- 验收方式：仅使用物理真机；未使用模拟器

## 验收结论

| 项目 | 结论 | 实机结果 |
| --- | --- | --- |
| 分类词库直通完整生命周期及 `orq` | 通过 | 新增临时直通词条“验证/oba”后立即出现在候选并可上屏；删除后 `oba` 恢复为系统候选“横_一、鱼”。`orq` 修复后重新验证，可显示日期直通候选并正确提交日期。 |
| `oba–obz`、`oxa–oxz` 穷举 | 通过 | 52 个编码逐一使用真机虚拟键盘输入，并与 `小鹤音形/2.6.符号.txt` 比对，最终 52/52 通过。`oxo` 的词库定义为空，实机无候选，与源数据一致。 |
| 下滑符号映射导入/导出 | 通过 | 已新增“导入映射/导出映射”。真机导出文件包含中文、英文各 26 键；将两套配置清空保存后，从系统文件选择器重新导入，中文和英文映射均立即恢复。导入后仍可逐键修改、保存并再次导出。 |
| 淡然皮肤素材包完整导入 | 通过（项目格式） | 使用淡然实际图片构建项目支持的 `.sy-skin` 包，经系统文件选择器完成导入、选用并在真机键盘显示；随后恢复默认皮肤并删除测试皮肤。当前键盘尺寸下图片显示正常。 |

## 关键说明

1. 分类词库直通验证使用临时用户词条，验收结束后用户词库恢复为“有效 0 条”，没有残留测试词条。
2. 52 编码首次自动横向翻页时，`oxu`、`oxy` 因一次超长滑动没有覆盖末页；随后用真机候选栏分段滑动复验，分别完整取得 23、29 个候选，顺序及内容均与源词库一致，因此最终结果为 52/52。
3. 淡然原始目录内的旧格式 `0_淡然.ini` 不能被当前项目直接导入；必须转换/封装为根目录包含 `skin.json` 的 `.sy-skin` 包。本次通过的是当前项目正式支持的完整导入流程。
4. 导入皮肤在本次实机尺寸下显示正常；当前自定义皮肤渲染使用普通拉伸，不等同于内置淡然皮肤的可拉伸分区配置，因此不据此宣称所有尺寸下均具备通用 `.9` 分区拉伸语义。
5. 本轮按要求不验收客户实际 USB/蓝牙实体键盘。

## 证据索引

- 52 编码最终结果：`symbols-52-final.csv`、`symbols-52-final.json`
- 直通新增与恢复：`direct-oba-added.json`、`direct-oba-committed.json`、`userlex-removed.json`、`direct-oba-restored.json`
- `orq` 复验：`direct-orq.json`、`direct-orq-committed.json`
- 下滑符号导入/导出：`swipe-section-new.json`、`swipe-export-picker.json`、`swipe-exported.sy-swipe`、`swipe-cleared-both.json`、`swipe-import-result.json`、`swipe-import-restored-chinese.json`
- 淡然导入与显示：`skin-import-list2.json`、`danran-import-keyboard.jpeg`
- 清理与恢复：`skin-deleted-confirmed.json`、`final-settings-top.json`

## 最终判定

本次要求关闭的四个验证缺口全部通过：分类词库直通、52 个符号编码、下滑符号映射导入/导出、淡然 `.sy-skin` 完整导入流程均已在物理真机完成验收。
