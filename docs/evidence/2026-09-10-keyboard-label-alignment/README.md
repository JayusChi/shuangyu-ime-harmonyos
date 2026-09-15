# 候选态句号标签与上档符号对齐

日期：2026-09-10。

## 改动

- 中文模式有候选时，具备次选动作的句号键显示“次选”；候选清空后恢复默认句号或模板文字。按键标签直接订阅候选状态，独立于结构缓存，无需重建整个键盘。原有点击、长按和上滑动作保留。
- 所有上档标签统一右对齐，右边距 7vp，移除单字符字母上档使用左侧 50% 留白的特殊定位。
- 确认结构解析已经支持在空格同行对调逗号、句号，并补充回归验证：位置、动作、上档符号和候选态标签保持对应，中英文分别使用自己的动作。
- 工坊标点上档预览同步右对齐并将句号键的旧 @ 提示修正为问号；重新生成离线 standalone.html。制作说明补充对调方法和结构包导入说明。

## 验证

- ArkTS 全部单元测试：698 通过，0 失败，0 错误。原始结果：outputs/keyboard-label-alignment-arkts-result.txt。
- 工坊现有导入导出集成检查：10 项通过。
- 修改文件的 git diff --check 通过。
- hdc list targets 为空，未执行真机安装、候选状态刷新或上档标签视觉验收。

用户可在工坊“结构”页拖动逗号与句号交换位置，保留在空格所在行，导出 .sy-layout，然后在“设置 → 数据管理 → 键盘结构与皮肤”导入并选择。只导出 .sy-skin 不保存排列。详见 docs/features/keyboard-customization/TEMPLATE_FORMAT.md。

## 最终安装包

- release 签名构建与资源门禁通过。包含本次标签、对齐修改及前面的实体万能键、ojz、oix、浮动候选修复。
- 编译生成代码已确认候选变化会更新 BaseKey.hasCandidates，上档采用 TextAlign.End 与 right: 7。
- 路径：entry/build/release/outputs/default/entry-default-signed.hap
- 字节数：93135552
- SHA-256：D7F68A540F6641F505B255C00582A407C73D3FAA882B0D7D996AB66944AD7E7A

