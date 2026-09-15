# 下滑符号映射导入/导出实机验收（2026-09-02）

## 环境

- 物理真机：Huawei nova 12（BLK-AL00）
- 连接目标：`192.168.1.136:44621`
- 应用：`com.corrosion.shuangyuime`
- 未使用模拟器

## 实现结果

- 设置页新增“导入映射”和“导出映射”。
- `.sy-swipe` 文件同时保存中文、英文两套 26 键下滑映射。
- 导入成功后立即写入设置并生效，仍可逐键修改、保存及再次导出。
- 导入支持 `.sy-swipe` 和 JSON，限制 64KB；校验版本、文件类型、按键名和符号长度。

## 真机验收步骤与结果

1. 打开“键盘结构与皮肤”，确认“导入映射/导出映射”入口存在：通过。
2. 点击“导出映射”，在系统文件选择器中保存至 Download：通过。
3. 读取导出文件：`schemaVersion=1`，类型为 `shuangyu-letter-swipe-symbols`，中文 26 键、英文 26 键：通过。
4. 分别清空中文和英文映射并保存，页面显示为空：通过。
5. 点击“导入映射”，从系统文件选择器选中刚导出的文件：通过。
6. 英文映射恢复，包括 M=`→`；中文映射恢复，包括 Q=`[`：通过。
7. 导入数据已持久化；测试结束时配置与导出前一致：通过。

## 自动化验证

- ArkTS 单元测试：`hvigorw --no-daemon --mode module -p module=entry@default test`，通过。
- Release HAP：`scripts/build-hap.ps1 -SkipRust -BuildMode release`，构建并签名成功。
- 解析器覆盖：中英文往返、错误版本、错误类型、未知按键、超长符号、无效 JSON。

## 关键证据

- 新设置页：`swipe-section-new.json`
- 系统导出选择器：`swipe-export-picker.json`、`swipe-export-download.json`
- 真机导出文件：`swipe-exported.sy-swipe`
- 两套映射清空：`swipe-cleared-chinese.json`、`swipe-cleared-both.json`
- 系统导入选择器：`swipe-import-picker.json`、`swipe-import-download.json`
- 导入后英文恢复：`swipe-import-result.json`
- 导入后中文恢复：`swipe-import-restored-chinese.json`

## 结论

客户要求的“用户可导入、导出自己的下滑符号预设，并在导入后自行调整”已经实现，并通过物理真机完整往返验收。
