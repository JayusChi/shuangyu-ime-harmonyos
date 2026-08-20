# 编码规则

## ArkTS

- 扩展能力仅调度生命周期。
- UI 组件调用控制器或服务，而不是直接调用原生模块。
- IME Kit 调用保留在 `infrastructure/ime` 中。
- 原生调用保留在 `infrastructure/native` 中。
- 日志不得包含完整的用户输入、密码、编辑器文本或可重建的候选词上下文。
- 异步 IME 操作必须检查成功值和异常。

## C++

- C++ 桥接代码必须保持无输入法业务逻辑。
- Rust 缓冲区必须由 Rust 提供的释放函数释放。
- 长期所有权必须使用 RAII。
- Node-API 函数必须验证参数并返回稳定的错误码。
- 错误语义来自统一契约，而不是分散的魔术数字。

## Rust

- 工作空间 crate 保持狭窄的职责。
- `engine-protocol` 定义跨层数据和错误语义。
- `ime-engine` 拥有输入引擎行为。
- `ime-ffi` 拥有 C ABI、panic 捕获、UTF-8/C 字符串处理以及 Rust 缓冲区分配/释放。
- `user-model` 拥有用户学习记录、用户评分、持久化、原子保存、恢复、清空和容量控制。
- 候选查询和短句解码只能获得只读用户分，不得直接读写用户模型文件。
- `unsafe` 应保持在 FFI 边界附近。

## 测试

- 不要删除测试以使构建通过。
- 不要将未执行的命令报告为通过。
- 阶段 1 Rust 门禁是 `scripts/test-rust.ps1`。
- 阶段 1 完整本地门禁是 `scripts/verify-stage1.ps1`。
