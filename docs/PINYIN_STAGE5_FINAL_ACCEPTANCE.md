# 26 键全拼和 9 键拼音阶段 5 联合验收

日期：2026-08-13

结论：`IMPLEMENTED / HOST_VALIDATION_COMPLETED / DEVICE_VALIDATION_PARTIAL`

本轮不能标记 `COMPLETED`：x86_64 Phone/Pad 模拟器完成了 signed Release 的核心联合链路，但 ARM64 物理真机、同一设备横竖屏旋转、真实浏览器/聊天应用、数字/电话设备专项、设备性能与长时内存增长仍为 `NOT_RUN`。仓库 `.git` 目录为空，无法用 Git diff/提交历史核验本轮之前已经存在的候选基线刷新来源。

## 1. 正式档案与迁移

| profile | Rust scheme | 布局 | 联合结果 |
| --- | --- | --- | --- |
| `xiaohe-17` | `xiaohe` | 17 键 | ArkTS 切换、持久化、同 scheme 清组合 PASS；Pad signed Release 显示 PASS |
| `xiaohe-26` | `xiaohe` | QWERTY 26 键 | 默认值、迁移、切换、持久化 PASS；Pad `nihc → 你好` PASS |
| `quanpin-26` | `quanpin` | QWERTY 26 键 | 主机专项 PASS；Phone/Pad `nihao → 你好` PASS |
| `pinyin-9` | `pinyin-9` | 中文九宫格 | 主机专项 PASS；Phone/Pad `64426 → ni'hao/你好` PASS |

另外回归了 `xiaohe-yinxing` 的 Rust/FFI/ArkTS 全套既有测试和正式 bundle 身份；未改变其候选语义。

迁移规则仍只有既有 schema 5 机制：旧 17 键映射 `xiaohe-17`，旧 26 键映射 `xiaohe-26`，合法新 profile 保持不变，未知/损坏值回退 `xiaohe-26`。新增测试确认迁移幂等、保留无关合法设置。人工词库字段和用户模型文件不参与该迁移。

## 2. 本轮修复

1. `SettingsController` 原来在 `xiaohe-17 ↔ xiaohe-26` 这类同 Rust scheme 的布局切换中不 reset，可能保留旧组合；跨进程同步也只比较 scheme。现在任何 profile 变化都先 reset，再清理 Store，Native 或持久化失败时运行态、UI 与配置回滚到旧档案。
2. 全拼单字母 `n` 原来遇到词库精确读音“嗯/唔”便停止前缀召回，后续排序修正实际无效。现在 Rust 为单字母全拼建立有界、预计算的前缀池，`你` 可召回并排在“嗯”前；没有把规则放入 ArkTS/C++。
3. 两项 ArkTS 历史测试仍断言旧逗号/实体标点行为，与 2026-08-12/13 已冻结产品合同冲突；只更新测试以验证“虚拟逗号独立动作”和“实体标点先单次提交首候选再插入后缀”，未回退产品实现。

## 3. 自动化结果

| 门禁 | 结果 |
| --- | --- |
| `cargo fmt --check` | PASS |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` | PASS |
| `cargo test --workspace` | 505/505 PASS（含 candidate baseline 4/4、T9 6/6、FFI 31/31） |
| ArkTS unit test | 440/440 PASS，Failure 0，Error 0 |
| x86_64 Native Release | PASS；26,934,248 bytes，SHA-256 `9E6F65B9834941382AC077E4B282C5B73D195E148C5651607A1D0BF39D7114FC` |
| arm64-v8a Native Release | PASS；27,432,150 bytes，SHA-256 `5A0C9E9F8777FA0C6FF2F016746770DFC8E625948F1D8D24A4E272F24DAB0BA9` |

阶段三遗留的 `committed_candidate_snapshots_match_current_production_behavior` 当前真实通过。当前 production lexicon 为 3,741,328 bytes、SHA-256 `6A5F0567CA52C3E0AE539C9753109652C3C98218A0BFBA1AD492D4EC494D6FF4`。但候选基线文件在本轮开始前已有 2026-08-13 时间戳，且 Git 元数据不可用；因此这里只能确认“当前代码/数据/快照一致”，不能替代产品对基线刷新来源的审计。

## 4. 专项覆盖

- 全拼：Rust 覆盖 `ni`、`nihao`、`zhongguo`、`zhon`、`xian`、`xi'an`，歧义路径、显式分音、逐字删除、部分提交、分页及长输入无隐式提交；Phone/Pad signed Release 覆盖 `nihao → 你好`。
- T9：Rust 覆盖 `64 → ni/你`、`64426 → ni'hao/你好`、未完成数字前缀、高碰撞 64 位输入、组合选择、显式分音、逐位删除、分页、重置和 scheme 切换；Phone/Pad signed Release 覆盖 `64426` 和组合栏。
- 用户数据：`xiaohe`、`quanpin`、`pinyin-9`、`xiaohe-yinxing` 的学习/人工规则键隔离测试 PASS；T9 学习键使用最终候选和标准拼音，不保存 raw digits；主/备份损坏恢复与跨 scheme 清理测试 PASS。
- 编辑器/生命周期：ArkTS 覆盖普通、搜索、聊天、多行、邮箱、URL、密码、数字、电话策略；密码关闭学习和候选，URL 在当前 `pinyin-9` profile 下仍显示直接英文 URL 键盘而不是 T9。Phone 覆盖隐藏/恢复：`64` 的 `ni` 组合隐藏后重新聚焦不残留，profile 仍恢复为 `pinyin-9`。

## 5. 主机性能（Windows x86_64 Release）

这些是 2026-08-13 实测主机结果，不代表设备性能。

| 场景 | P50 | P95 | 备注 |
| --- | ---: | ---: | --- |
| 全拼逐键完整引擎，四组 1,620 键 | 5.144 ms/键 | 58.495 ms/键 | 平均 13.805 ms/键，0 failure，0 automatic/ASCII commit |
| T9 `64` parser | 5.7 µs | 7.3 µs | 5,000 次 |
| T9 `64426` parser | 47.1 µs | 84.7 µs | 5,000 次 |
| T9 64 个连续 `6` | 404.921 ms/串 | 429.584 ms/串 | 200 次，约 6.33/6.71 ms/键 |
| T9 删除恢复 | 68.3 µs | 120.9 µs | 5,000 次 |
| T9 组合切换 | 7.6 µs | 11.7 µs | 5,000 次 |
| T9 `64426` 完整候选刷新 | 0.273 ms | 0.460 ms | 5,000 次 |

T9 索引为 250 个节点，构建平均 233.299 µs；raw 64、路径/状态、组合、候选快照和 cache 均有代码硬上限，不存在 `3^n/4^n` 展开。全拼当前完整引擎长输入 P95 相对历史 quality2 的 2.027 ms/键基线明显变慢，主要来自后续取消自动上屏并增加全拼 lattice/正式长句质量路径；本轮未降低门槛，也未借收口阶段重写排序。设备 P50/P95 与设备内存变化均为 `NOT_RUN`。主机长期 RSS 稳定性本轮也未形成可靠测量，记为 `NOT_RUN`。

## 6. Release HAP

最终产物在所有 Rust 修复后重新构建；填写值以最终 `verify-release-hap.ps1` 输出为准：

- unsigned：`entry/build/artifacts/entry-release-unsigned.hap`，38,818,364 bytes，SHA-256 `C61282C8BC00372469C05D5F1257529B8BB9CE57A0C6B746DBEFA6898A8CBB7A`
- signed：`entry/build/default/outputs/default/entry-default-signed.hap`，38,951,540 bytes，SHA-256 `151A06D69C853691FD903D653BE80FEAF9F08A3549F3D4E83015D7852F413E50`
- build mode `release`，`debug=false`，version `0.3.1/3000001`
- HAP 实包 21 个条目；只有 `production.lex`、`xiaohe-yinxing-production.hsyx` 两个 rawfile，并含 x86_64/arm64-v8a `libime_bridge.so`
- 正式词库 3,741,328 bytes/SHA-256 `6A5F0567CA52C3E0AE539C9753109652C3C98218A0BFBA1AD492D4EC494D6FF4`
- 正式音形 bundle 25,397,952 bytes/SHA-256 `00C7D5A9D6B74A079A7434DF23F510AA348FE8FEE5BF1EAF72E691D68BCD1E30`
- 内容门禁拒绝 fixture/synthetic/test/benchmark/debug/raw txt/csv/临时 bundle/审计报告/凭据名和 `ohos.permission.INTERNET`；最终 unsigned 与 signed HAP 均实际解包校验 PASS

## 7. 设备结果

| 项目 | 结果 |
| --- | --- |
| x86_64 Phone 1320×2856 竖屏 | PARTIAL PASS：signed Release、独立第三方包、档案入口、全拼、T9、隐藏恢复、深色、URL 策略；最终 signed HAP 已覆盖安装 |
| x86_64 Pad 2880×1920 横屏 | PARTIAL PASS：signed Release、强制虚拟键盘、四档案切换、双拼 `nihc`、全拼 `nihao`、T9 `64426`；最终 signed HAP 已覆盖安装 |
| x86_64 2in1 3120×2080 | 仅连接/ABI/分辨率确认；本轮交互 `NOT_RUN` |
| 同一设备横竖屏旋转 | `NOT_RUN` |
| ARM64 PHYSICAL DEVICE | `NOT_RUN`（连接目标全为 x86_64 emulator） |
| 真实浏览器/聊天应用 | `NOT_RUN`；已跑独立包名 ArkUI 验收客户端，不冒充真实应用 |
| 设备性能/内存/soak | `NOT_RUN` |

设备 JSON 证据位于 `docs/evidence/2026-08-13-pinyin-stage5-final-acceptance/device-phone/` 和 `device-pad/`。这些目录含本轮探索性自动化的中间布局；只有本文明确列为 PASS 的断言可作为结论。

## 8. 剩余发布阻塞

1. ARM64 物理 Phone/Pad 与真实第三方应用矩阵未运行。
2. 同一设备旋转、分屏、前后台/应用切换的完整四 profile 组合矩阵未全部运行。
3. 数字/电话设备实测、完整密码安全日志审计、设备性能、设备 RSS 和长时 soak 未运行。
4. 全拼当前主机长输入性能相对历史质量修订前冻结值有明显回退，需要在不恢复自动上屏、不改变候选语义的前提下单独审查；本阶段只如实记录。
5. Git 元数据缺失，无法审计本轮开始前已有的候选快照更新来源，也无法给出可靠 Git diff。

因此该版本已达到主机自动化和 Release 包内容收口，但尚不能判断为“全部必要门禁已通过、可直接发布”。
