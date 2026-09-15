# 2026-09-11 查形全屏空白修复验收

**PHONE_AND_COMPUTER_WEB_PASS**。经用户批准，将小鹤网页接入应用内独立 ArkWeb 窗口。手机和电脑模拟器均通过官网直通、光标查形、重复查询、刷新、换字查询和剪贴板查形；18 项页面及宿主文本检查全部通过。最终开发签名 Release HAP 已无重置覆盖安装到两台设备。

## 结果与证据

| 流程 | 手机 | 电脑 |
| --- | --- | --- |
| 完全关闭输入法应用及系统浏览器后，xhgw 四码直达官网 | PASS | PASS |
| 冷启动：先输入“你”，再选 oix | PASS，显示“汉字：你” | PASS，显示“汉字：你” |
| 网页留在后台，再次查询相同字 | PASS | PASS |
| 点击刷新 | PASS | PASS |
| 已有网页窗口接收新的“鹤”查询 | PASS，更新为“汉字：鹤” | PASS，更新为“汉字：鹤” |
| 冷启动：复制“鹤”，oix → 系统粘贴按钮 | PASS，完整显示鹤、hedn 及拆分 | PASS，完整显示鹤、hedn 及拆分 |
| 官网关闭返回宿主 | 空文本保持 | 空文本保持 |
| 光标查形切回宿主 | “你”保持，无 oix/标签泄漏 | 同左 |
| 换字查形关闭返回宿主 | “你鹤”保持 | 同左 |

手机查形 Web 区域为 `[0,346][1320,2758]`。机器检查要求网页、查询结果与原生 `flypy.cc` 标识属于同一窗口，并校验网页非零尺寸和截图存在；没有把标签缩略图算作通过。已人工查看手机官网、手机完整查形及电脑完整查形截图。

- [手机：完整查形截图](phone/cold-clipboard.png)、[官网截图](phone/cold-home.png)、[光标“你”截图](phone/cold-cursor.png)
- [电脑：完整查形截图](computer/cold-clipboard.png)
- [18 项机器检查](device-checks.json)、[验收脚本](accept-web.ps1)、[证据检查脚本](verify-evidence.cjs)
- [手机运行记录](phone-acceptance.log)、[电脑运行记录](computer-acceptance.log)

## 修复内容

oix 的两种文字来源和小鹤官网/帮助直通统一进入非导出的 `FlypyWebAbility`。该窗口拥有自己的 LocalStorage 和网页区域，不经过故障浏览器的标签恢复流程。请求序号使相同网址也能重新载入，新字查询能更新已经打开的窗口。提供返回、刷新、关闭和载入失败重试。

初始网址严格限于 `https://flypy.cc` 的精确域名，保留路径、查询参数和片段；其他自定义网址仍通过系统浏览器打开。应用内网页不提供原生 JavaScript 桥接或文件访问。

用户在本次任务中明确批准：“允许接入应用内查形页并增加联网权限”。采用 `flypy-web-v1` 发布权限配置，权限恰为 VIBRATE + INTERNET；INTERNET 属于应用级权限。源码与最终 HAP 门禁要求批准的配置及非导出网页能力，仍拒绝麦克风、额外权限、未批准配置和其他源码中的联网声明。详见 [权限配置](../../docs/features/direct-control/FLYPY_WEB_PERMISSION_PROFILE.md)。

实际设备测试还发现构建目标的独立页面清单会排除未列出的新页面，已同步 default/internalDebug 清单，并新增最终 HAP 的 `pages/FlypyWeb` 检查。[缺页旧包被新门禁拒绝](missing-page-negative.log)。

## 定位结论

手机系统浏览器 5.1.9.315 在冷启动直接接收网址时能够复现全屏空白；脱离输入法、从系统命令直接打开同一网址也会失败。先打开无网址首页再暖启动网址则可显示完整页面。日志显示网址请求送达、标签恢复发生，但没有建立正常全屏网页区域；这是对启动阶段故障的定位，未声称查明浏览器闭源实现的具体缺陷。

重启手机模拟器、调整缩放选项、不同标准启动方式、连续启动或延时启动均未形成稳定修复。失败的预热兼容代码已撤除。浏览器“强制缩放网页”恢复原值；只关闭了本轮测试产生的 8 个重复小鹤标签，未清浏览器数据。原故障截图和实验记录保留在本目录；独立网页原型仅供定位，不是交付包，独立验收宿主源码和安装包已恢复。

本次解决的是应用的查形及小鹤网页使用路径，没有替换或修改系统浏览器本体。

## 构建、回归与环境

- 最终源码 ArkTS：708 通过，0 失败，0 错误。[结果](arkts-final-source-result.txt)、[日志](arkts-final-source.log)
- 发布资源/权限正负向测试 PASS；包括未知配置、额外权限、导出网页能力、无配置联网、麦克风与原有资源污染测试。[资源门禁](resource-gate-tests.log)、[正式资源负向测试](formal-gate-tests.log)
- 最终 clean Release 构建 PASS；页面代码编译成功，最终设备包含网页路由。[构建](build-web-ready.log)、[HAP 门禁](verify-web-ready-hap.log)
- 两台安全覆盖安装，均 `SIGNATURE_RESET=false`。[安装](install-web-ready.log)
- Phone `127.0.0.1:5555`：1320×2856；2in1 `127.0.0.1:5557`：3120×2080。手机使用触屏键盘，电脑使用系统注入按键；独立宿主包名为 `com.example.shuangyuime.acceptance`。
- 两端所有 46 项字符串设置与上一轮恢复基线一致。[设置比对](settings-preserved.json)
- 本轮没有修改 Rust 或重生成词库；此前键盘/双拼验收保留在 [原报告](../feedback-acceptance-20260911/ACCEPTANCE_REPORT.md)。该报告内 3 条手机网页未完成项由本次新包验收补齐，旧包及原始失败记录保持历史身份。

## 最终设备包

[entry-device-release-signed.hap](entry-device-release-signed.hap)

- 版本：0.10.0 / 10000000，开发签名 Release，已安装到两台模拟器。
- 大小：93,264,261 bytes。
- SHA-256：`441EBBE6C4A21B4BB3D0E35180247623CB32100DD85ABDEDCDDB8F9CFF174A33`。
- 尚未重打正式客户 APP 或上传 AGC；历史 0.10.0 客户 APP 不含本次网页修复。
