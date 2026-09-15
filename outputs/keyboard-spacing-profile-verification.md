# 字母上档符号与18键修复

- 字母键的单字符上档符号置于键宽75%的水平位置；文字功能提示保留足够宽度。
- 18键所有字母键统一权重1，第二行按7列网格居中；Shift/Esc和删除键同宽，以保持三行字母实际宽度相等。
- 双拼系统子类型回调保留当前18键选择，避免从全拼或音形切换后被覆盖为26键。
- ArkTS：686项通过，0失败、0错误；既有预览时序用例首轮偶发失败，复跑通过。
- Release签名HAP构建成功。
- HAP SHA-256：7d7ed5fd6274469e7aaa972d93ae586a3e895d85e40ae1ac58ca02a93e7b60dc
- 未进行真机视觉和触控验收。

布局长度计算依据：[OpenHarmony ArkUI尺寸设置](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-size.md)。
