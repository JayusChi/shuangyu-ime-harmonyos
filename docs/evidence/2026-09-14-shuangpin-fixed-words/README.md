# 小鹤双拼整句排序与固定二字简拼

日期：2026-09-14。对应客户 `hfyzxiwh` 智能偏弱，以及不能组成声韵音节的两码简拼在句内固定为自定义二字词的反馈。

## 外部核对与原因

按小鹤双拼映射，`hf / yz / xi / wh` 解析为 `hen / you / xi / wang`。2026-09-14 实际查询 Google Input Tools 的中文拼音服务，`henyouxiwang` 首候选为“很有希望”。这次比较的是展开后的全拼，没有将 Google 的全拼服务当作小鹤双拼键位实现，也未声称已经操作搜狗或微软输入法。产品入口为 <https://www.google.com/intl/zh-CN/inputtools/try/>；小鹤官方说明为 <https://flypy.cc/>。原始查询响应保存在 `outputs/shuangpin-fixed-20260914/google-henyouxiwang.json`。

本工程原解析已经正确，但旧整句评分对词长使用平方奖励。“游戏王”的词频仅 4，却凭三个音节的长度奖励压过“希望”（词频 50277），正式引擎首选为“很游戏王”，且“很有希望”在有界搜索中被剪掉。扩大诊断搜索后能找到目标，证明问题在排序而非缺少整句词条。修改未给“很有希望”添加特例或词库补丁。

`up` 中 `u` 表示 `sh`，与 `p` 韵母不能组成合法音节，解析器已有双声母回退。然而用户词库只对完整输入码做候选覆盖，没有参与句中解码；已有“固顶”功能因而无法约束中间片段。

## 实现与边界

- 小鹤完整音节路径使用有界的近似对数词频成本及线性覆盖分，去掉稀有长词的平方优势。对数区间内保留细分，避免“期间／其间”这类相近词频被合成同分。全拼、九键和含未完成声母的旧评分策略保持原语义；这次没有宣称全面提升所有输入前缀的预测。
- 复用“我的词库 → 固顶”和既有 `#固` 文件格式。仅小鹤两码对齐、不可组成完整音节、恰好二字的规则参与整句图。固定片段替换所有重叠系统词边，避免较长系统词跨过或拆开该片段；同码冲突按源顺序最前的有效二字固顶确定。
- 合法音节、跨两码边界的字母片段、两码中间的显式分音符、其他输入方案不会触发句内替换。句中多个固定片段可以重复使用。部分选词和退格按实际原始码长消费。
- 保存、修改、删除复用原子保存和热重载，重启仍保留。人工规则参与的整句不写入用户词频和上下文学习。
- 两种键盘通过公共 Native 引擎生效。设置页增加简短示例说明，手机模拟器截图确认文字换行完整、输入框和保存按钮可用。

使用说明见 `docs/features/user-lexicon/USER_LEXICON_FORMAT.md`。完整增量 diff、修改前备份、命令日志及设备截图位于 `outputs/shuangpin-fixed-20260914/`，不会将工作区先前修改误算为本轮变化。

## 验证与交付

- 相关 Rust 回归 326/326 PASS：`ime-engine`、`sentence-decoder`、`shuangpin-parser`、`user-lexicon` 的 lib/tests；包含正式生产语料、旧候选顺序和新增 7 项固定简拼集成测试、1 项词频精度测试。首次广泛回归抓出的“期间／其间”退化已修复，原测试预期没有修改；最终完整运行日志为 `rust-tests.log`。
- ArkTS 744/744 PASS，独立结果为 `arkts-result.txt`。修改文件 rustfmt、相关库及新增测试/诊断示例的严格 Clippy 均 PASS。
- `x86_64`、`arm64-v8a` Native 重建 PASS。开发签名 Release HAP 安全覆盖安装到 `127.0.0.1:5555` 的 1320×2856 手机模拟器，没有卸载或重置原沙箱。
- 虚拟键盘通过实际触屏字母键，实体键盘模式通过系统 `uitest keyEvent` 注入；独立验收宿主 `com.example.shuangyuime.acceptance` 的聊天编辑框，两模式均验证 `hfyzxiwh → 很有希望` 首候选和空格上屏，以及 `woysupuurufa → 我用双拼输入法` 的句中固定片段和完整上屏。虚拟模式额外验证 `woysup → 我用双拼`。
- 固顶规则通过实际“我的词库”表单创建，重启输入法进程后仍在实体模式生效。测试结束在管理页移除唯一新增规则，恢复原有空词库；全部 47 项设置恢复一致，见 `settings-restoration.json`。未清除既有学习记录。
- 最终版本保持 0.11.0，正式签名 HAP 为 `entry/build/release/outputs/default/entry-default-signed.hap`，93,331,808 bytes，SHA-256 `443141E71E32956E6A69D77A6F6ED5CA86B67AEDA74D10AFE33E68BE6FAD155B`，Release 实包资源门禁 PASS。开发验收包为本轮目录中的 `device-signed.hap`；本轮未重新构建客户 APP。

设备证据包含 `my-lexicon-before.png`、`lexicon-rule-ready.png`、`lexicon-rule-saved.png`、`touch-hfyzxiwh*.png`、`hardware-hfyzxiwh*.png`、`touch-fixed-middle*.png`、`hardware-fixed-middle*.png` 及配套 UI JSON。截图已目视检查设置说明与实体候选卡片。

验收边界：实体模式为模拟器硬件事件路径，不能替代真实 USB/蓝牙/内置键盘；本轮未在客户宿主、平板或电脑上新增实机验证。此次修复针对已定位的评分偏差与句内固定规则，不等同于完成所有成熟输入法的词库、语言模型和上下文能力。
