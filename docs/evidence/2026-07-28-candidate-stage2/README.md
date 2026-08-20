# 候选词改进阶段 2 证据

日期：2026-07-28  
状态：`COMPLETED`（主机、构建与 x86_64 Phone/Pad 模拟器范围）

## 结论

阶段 2 已为现有候选栏接入独立、可发现的“展开候选”入口，并复用阶段 1 的当前页协议完成 Phone/Pad 网格、上一页/下一页、候选提交和生命周期收口。右侧“收起键盘”仍保留原动作、ID 和语义，未被候选展开复用。

本阶段没有修改 Rust 查询、音形/双拼召回与排序、用户规则、正式词库、C++/FFI 或候选提交 ABI。展开面板始终只持有当前页，候选点击继续把当前页索引传给既有 `commitCandidate(index)`。

## 实现

- `CandidateExpansionPolicy.ets` 集中定义展开/翻页可用性与响应式布局：
  - Phone 竖屏：5 列、4 个可见行；
  - Phone 横屏：8 列、3 个可见行；
  - Pad：10 列、5 个可见行，正式 50 项当前页可在单屏容纳。
- `CandidateBar.ets` 增加独立“展开/收起”候选动作；普通 Phone 状态仍是原单行候选栏。
- `CandidateExpansionPanel.ets` 只渲染当前页，提供页码、上一页和下一页；展开/收起统一使用候选栏中的单一入口，避免面板内出现重复“收起”按钮。
- Phone 展开时在固定输入法窗口内以候选页替换字母键页，避免面板覆盖或裁切键区；收起即恢复完整键区。
- Pad 展开时使用约 48% 宽的右侧候选网格，左侧完整键区保持可见、可点击。
- `KeyboardController` 对翻页做同步 in-flight 防重入，失败时不替换当前候选；`InputSessionStore` 在空候选、会话结束、隐藏键盘、切换输入框、方案/模式切换、错误与销毁时关闭展开和加载状态。
- 第 2 页“上一页”按钮曾因 ArkUI Builder 接收计算参数后未刷新而保持禁用；最终实现改为让专用 Builder 直接读取响应式 `@Prop`，Phone/Pad 最终设备证据均验证已修复。

## 分页与节点边界

```text
当前页 CompositionResult
  → candidatePage / hasPreviousPage / hasNextPage
  → 当前页网格
  → 上一页或下一页（禁止重复请求）
  → 成功：原子替换当前页
  → 失败：保留当前候选并进入错误收口
```

- 普通栏和展开面板不会同时创建两套候选内容：展开时普通栏候选内容隐藏。
- 正式配置每页 50，展开节点上限仍为当前页 50，不会随翻页累计；Pad 的首屏容量为 10×5＝50。
- internalDebug 为了稳定制造两页回归，继续显式使用 8 项 fixture 页；因此截图中的“8 项”不是正式页大小回退。

## 自动测试与构建

- ArkTS 单元测试：330/330 PASS；阶段 2 新增 6 项，覆盖空候选、非空刷新、隐藏/输入框切换/错误清理、翻页防重、Phone/Pad 布局和无障碍动作隔离。
- Rust：`cargo fmt --all -- --check` PASS；`cargo test --workspace` 403/403 PASS。Rust 代码未修改。
- internalDebug HAP：40,909,750 bytes，SHA-256 `4116C46349AA4C2301C3CC97D6AEB4582F73B1C2A71EACE98648D81008F9DCFC`。
- unsigned Release HAP：37,635,864 bytes，SHA-256 `4425ADF11427673ECCB51035558C6F4C1566456D85264F0A880DB13E1553DA3B`。
- 相对阶段 1 证据产物，Debug/Release 分别增加 74,862/29,936 bytes；当前页 JSON、Rust 快照和正式 bundle 未改变。
- ArkTS 与 HAP 构建仍输出项目既有的异常处理/废弃 API 警告，本阶段没有新增构建失败。

## 修改文件

产品代码：

- 新增 `entry/src/main/ets/domain/candidate/CandidateExpansionPolicy.ets`
- 新增 `entry/src/main/ets/presentation/candidate/CandidateExpansionPanel.ets`
- 修改 `entry/src/main/ets/presentation/candidate/CandidateBar.ets`
- 修改 `entry/src/main/ets/presentation/keyboard/KeyboardRootStage3.ets`
- 修改 `entry/src/main/ets/state/InputSessionStore.ets`
- 修改 `entry/src/main/ets/application/InputSessionController.ets`
- 修改 `entry/src/main/ets/application/KeyboardController.ets`

测试与文档：

- 新增 `entry/src/test/CandidateExpansion.test.ets`，修改 `entry/src/test/List.test.ets`
- 新增本证据目录及 Phone/Pad 布局、翻页、提交和计时证据
- 更新 `CHANGELOG.md`、`PROJECT_STATE.md` 与 `候选词改进.md`

## 设备证据

### Phone：x86_64，1320×2856

最终安装包验证了：

1. 普通栏中的“展开”和“收起键盘”入口并存；
2. [第 1 页多行网格，只有候选栏中的一个“收起”入口](phone-verified/11-single-collapse.png)；
3. [第 2 页且上一页已启用，面板内无重复“收起”按钮](phone-verified/12-single-collapse-page2.png)；
4. [返回第 1 页，仍只有候选栏中的单一收起入口](phone-verified/14-single-collapse-back-page1.png)；
5. [通过候选栏“收起”后完整键区恢复](phone-verified/13-single-collapse-collapsed.png)。

最终第 1、2 页布局 JSON 中 `originalText="收起"` 的节点数均为 1。机器摘要见 [phone-verified/result.json](phone-verified/result.json)。

### Pad：x86_64，2880×1920

最终安装包验证了：

1. [第 1 页右侧网格与左侧完整 27 个字母键同时可见](pad-verified/06-page1.png)；
2. [第 2 页且上一页已启用](pad-verified/07-page2.png)；
3. [提交第 2 页候选“海边”后面板关闭、键盘保持、编辑框得到提交文本](pad-verified/08-after-page2-commit.png)。

机器摘要见 [pad-verified/result.json](pad-verified/result.json)。

`phone/`、`phone-final/` 与 `pad-final/` 保存了实现过程中的诊断快照，不作为最终 PASS 依据；最终依据仅为 `phone-verified/` 与 `pad-verified/`。

## 性能与限制

- 引擎查询性能沿用阶段 1 结果，因为本阶段没有修改查询或跨语言结果；UI 节点由“当前页 N 项”变为“当前页 N 项”，没有跨页累积。
- Phone internalDebug 的控制器侧 hilog 计时为：展开状态写入 0 ms、下一页操作 2 ms、上一页操作 1 ms、收起状态写入 1 ms；当页为 8 个 fixture 候选。原始摘要见 [phone-verified/timing.json](phone-verified/timing.json)。这些数值不包含 ArkUI 绘制/首帧，不作为正式 50 项设备帧时延。
- 普通候选栏更新时间、ArkUI 展开首帧、Pad 首帧、Store 独立更新时间和展开前后设备内存没有专用插桩，状态为 `NOT_RUN`，不以截图或主观观感替代性能数据。
- ARM64 物理真机、旋转/分屏完整矩阵、signed Release 第三方输入框、快速连续触键与长时压力为 `NOT_RUN`。
- 因此阶段 2 的完成结论只覆盖主机、构建和两台 x86_64 模拟器，不等同于最终发布验收。
