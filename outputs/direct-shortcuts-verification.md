# 网页、目录直通与 ofa 验证

- ArkTS：680 项，0 失败，见 direct-shortcuts-arkts-result.txt。
- Rust user-lexicon：29 单元测试 + 26 集成测试通过。
- Rust code-table-runtime：5 项动作表测试通过。
- Rust ime-engine：30 项正式音形及方案切换测试通过，包含网页/目录动作和两种拼音方案 ofa 分页。
- Native Gateway：18 项显示设置动作及网页、目录 payload 校验通过（模拟原生桥）。
- x86_64 / arm64 原生库编译完成，复制后的 SHA-256 与编译产物一致。初次 arm64 复制遇到文件占用，使用临时文件原子替换后完成。
- Release assembleHap / SignHap 成功。
- 模拟器 127.0.0.1:5559 覆盖安装未成功，平台返回 9568332 / install sign info inconsistent。未卸载旧包或清除数据；没有宣称设备验证完成。

说明：一次扩大范围的 Rust 测试包含无关的完整资源损坏矩阵，运行时间较长，已终止；随后运行并通过上述针对性测试。早期旧断言仍拒绝全拼、动作数仍为 50/17，已按新菜单更新；最终测试结果以上述日志为准。
