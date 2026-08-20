# 阶段 11.6.8 复验

结论：**x86_64 主机、HAP 和模拟器范围 PASS**。

## 设备与产物

- 设备：HarmonyOS 6.1 x86_64 Phone 模拟器，`1320x2856`，`127.0.0.1:5557`。
- 正式 bundle：25,397,952 bytes，SHA-256
  `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30`。
- unsigned Release HAP：37,572,616 bytes，SHA-256
  `a9f84a9e83d6b60792bfafa6f8d887284f08b97133663e912a15668df8a05295`。
- 设备安装的 signed Release HAP：37,707,165 bytes，SHA-256
  `3c86b29ed6c36e8ac706333c0a286aa63b4fc6837129343953cad2adb2a5137d`。
- internalDebug HAP：40,801,306 bytes，SHA-256
  `44a583e51852549bb792d3057dbaf99968c4622a86b8a243a0a0dd7bcc2630c1`。

## A～L 结果

| 用例 | 真实验证 | 结果 |
| --- | --- | --- |
| A 默认方案 | 清数据后设置页选中小鹤；独立 TextInput 输入 `nihc` 输出“你好” | PASS |
| B 正式方案展示 | Release 设置页仅有小鹤双拼、小鹤音形；无 fixture | PASS |
| C 首次切换音形 | Native 校验后选中；独立 TextInput 输入正式码 `aaba` 自动提交“阿爸” | PASS |
| D 持久化 | 强停主进程和输入法进程后仍加载银杏；`aaba` 再次输出“阿爸” | PASS |
| E 切回双拼 | 带未完成银杏组合切回；冷启动后 `nihc` 输出“你好” | PASS |
| F 再切音形 | 已安装 bundle 幂等复用；强停后 `aaba` 输出“阿爸” | PASS |
| G 缺失资源 | Debug 注入不存在路径，拒绝激活；回退小鹤仍输出“你好” | PASS ×2 |
| H 损坏资源 | Debug 注入首字节损坏，拒绝激活且不使用 fixture | PASS ×2 |
| I 不兼容版本 | Debug 注入 bundle major 9，稳定拒绝并回退小鹤 | PASS ×2 |
| J 设置迁移 | Debug 真链路注入重复、未知、旧 schema、乱序设置 | PASS ×2 |
| K 临时文件恢复 | 产品安装器清理自己的 `.tmp`，正式已安装版本继续可用 | PASS ×2 |
| L HAP 内容 | 实包精确白名单、大小+SHA、篡改/fixture/raw/report/network 负例 | PASS |

正向 signed Release 证据见 `positive-device/device-acceptance.json`；G/H/I/J/K 两轮证据见
`negative-device-j/device-acceptance.json` 和同目录快照；设备日志均在对应目录。

## 主机门禁

- Rust workspace：387/387 PASS；fmt、全 target/feature Clippy PASS。
- FFI 专项：26/26 PASS。
- ArkTS：323/323 PASS。
- x86_64、arm64-v8a Native 构建 PASS。
- internalDebug、Release HAP 构建 PASS。
- Release 实包正向校验 PASS。
- 负向门禁：fixture、原始文件、trace、build report、大小不变但哈希篡改、网络权限全部按预期拒绝。
- 正式来源 28/28 路径、大小、SHA-256 不可变 PASS。

ARM64 物理真机、Phone/Pad 全场景和性能发布验收未执行，属于 11.6.9；本文件没有将其写成通过。
