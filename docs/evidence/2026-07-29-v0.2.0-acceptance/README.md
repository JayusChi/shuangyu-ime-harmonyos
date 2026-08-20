# 0.2.0 发布验收摘要

## 结论

截至 2026-07-29，0.2.0 在主机、构建、签名和现有 x86_64 模拟器范围内没有发现发布阻断级缺陷。仍不能宣称已完成正式发布验收，因为当前没有 ARM64 物理设备，模拟器也没有可靠的系统分屏和同机旋转自动化入口。

## 本次变更

- 应用版本升级为 `versionName=0.2.0`、`versionCode=2000000`。
- 删除不参与 HarmonyOS 码表转换和运行时的 `小鹤音形/ime.android.ini`；门禁要求该敏感文件必须缺失，并继续核验其余 27 个客户源文件。
- 双拼 `production.lex` 安装器增加固定 SHA-256 校验、临时文件写入、`fsync`、临时文件复验和同目录重命名发布。
- 新增独立验收客户端 `com.example.shuangyuime.acceptance`，包含聊天发送、浏览器 URL、搜索、多行和长期输入编辑器。
- 新增可重复执行的 `scripts/device-accept-v0_2_0.ps1`。

## 自动门禁

- Host：9 PASS / 0 FAIL，证据为 `../2026-07-29-stage-11.6.9-final-acceptance/runs/20260729-114517-a269d110/`。
- Build：9 PASS / 0 FAIL，证据为 `../2026-07-29-stage-11.6.9-final-acceptance/runs/20260729-115216-3aa17059/`。
- ArkTS：332 PASS / 0 FAIL。
- x86_64 与 arm64-v8a 原生构建通过。
- 生产音形 bundle 双构建的 15 个文件完全一致；正式 bundle SHA-256 为 `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`。
- Release signed/unsigned 正门禁、资源/网络/篡改负门禁、证书和 Profile 复核全部通过。

## 覆盖升级

Phone 模拟器上的已安装基线为 0.1.0/1000000。升级前设置为小鹤音形、深色、紧凑键盘、小号候选、用户学习开启，并确认用户模型有 2 条记录。

使用同一签名的 signed 0.2.0 HAP 执行覆盖安装后：

- 包管理器报告 0.2.0/2000000；
- 方案和全部上述设置保持不变；
- 输入法进程重新加载后仍报告 2 条用户学习记录。

原始日志为 `phone/pre_upgrade_runtime_state.log` 和 `phone/post_upgrade_runtime_state.log`。

## 设备范围

- Phone x86_64，1320×2856 竖屏：聊天发送、URL、搜索、多行、Home 后恢复、快速输入均 PASS；见 `phone/automated-final/acceptance-summary.json`。
- Phone 1 分钟 soak：初始 100 轮 A/B 物理按键注入，随后 5 个持续 burst；无 fatal/panic/SIGSEGV，RSS 从 304,888 KiB 降至 298,212 KiB；见 `phone/stress-soak-final/acceptance-summary.json`。
- Pad x86_64，2880×1920 横屏：同一完整编辑器矩阵 PASS，RSS 增长 0 KiB；见 `pad/automated/acceptance-summary.json`。

这些“聊天/浏览器”场景使用独立包名的代表性编辑器属性，不等同于在某个真实聊天或浏览器产品中完成兼容性认证。

## 正式产物

- signed HAP：`entry/build/default/outputs/default/entry-default-signed.hap`
  - 37,886,028 bytes
  - SHA-256 `f1123df13f0c7aa281b17efb91db0449e3afa9b756e13de2be192f156fc9f706`
- signed APP：`build/outputs/default/HarmonyOS_Input-default-signed.app`
  - 10,133,398 bytes
  - SHA-256 `0fefdff2bbdc058ad7dea25f0d9fa4507bd811b2055e5ed23fbace41ed3c857c`
  - `pack.info` 为 0.2.0/2000000，签名摘要验证通过。

## 发布前仍需完成

- ARM64 物理手机/平板安装、输入、内存、功耗和温升验收。
- 同一设备上的横竖屏切换与系统分屏。
- 真实聊天、浏览器和系统搜索应用兼容性抽测。
- 小时级或过夜长期输入 soak；当前只完成 1 分钟自动 soak。
- 在 AGC 核对 2000000 高于线上版本、应用身份一致，并完成软件包基础检测和上架材料。
