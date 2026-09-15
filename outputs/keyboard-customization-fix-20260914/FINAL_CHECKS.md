# 最终复核

## 损坏包拒绝

三端均从系统文件选择器选取 22 字节、非 ZIP 的 `rejected.sy-skin`。最终安装版本显示持续错误：`无法解压模板包：{"code":900003}`，原来的“我的纯色皮肤”仍选中，没有新增无效模板。

- 手机：`device-evidence/127.0.0.1_5555/phone-final-reject.png` 及同名 UI 树。
- 电脑：`device-evidence/127.0.0.1_5557/pc-final-reject.png` 及同名 UI 树。
- 平板：`device-evidence/127.0.0.1_5559/tablet-final-reject.png` 及同名 UI 树。

`settings-import-error` 是页面内错误组件，截图与 UI 树均确认可见；下一次导入开始时清除旧错误。有效包重新导入成功后也恢复正常模板列表。

## 同 ID 图片覆盖补测

`create-same-id-skins.cjs` 从三端实际导出的图片皮肤包生成覆盖素材，保留皮肤 ID 和五个图片相对路径，只替换 PNG 字节为仓库深色键帽，并改白色文字便于观察。此项使用编辑器的真实包读写代码生成 QA 素材，不计入 12 个原生浏览器导出包。

手机与电脑在无需重启设备的情况下重新导入后显示深色键帽，确认相同文件名没有留下旧图片。截图：`phone-same-id-skin-keyboard.png`、`pc-same-id-skin-keyboard.png`，均位于各设备证据子目录。UPDATED 结构同时保留。

平板在这一额外图片覆盖测试开始前，宿主 Emulator 进程于约 18:06 退出。18:10、18:12 两次恢复同一虚拟设备均在系统启动时产生 Minidump，未恢复 HDC 连接；没有重置虚拟设备数据。故平板的同 ID **图片内容覆盖**不计为通过；之前的同 ID **结构更新**、五类图片初次导入、整机重启保留和最终损坏包提示已完成并有独立证据。宿主日志：`tablet-host-restart.log`、`tablet-host-retry.log`、`tablet-host-qemu.log`。

## 交付核对

- 最终三端开发签名安装及设备有效共享组检查通过，未再次清空数据。
- 最终市场发布签名构建、包内容门禁及签名验证通过；受信安装验收仍待官方测试分发。
- 临时 onCreate 面板诊断已移除，最终源码检索不到 `BASIC_ONCREATE_PROBE`。
- 共享设置 5 项、安装授权正反例和 12 个原生导出包的最终核验通过。
- 本次改动相关文件 `git diff --check` 通过；仓库中已有其他未提交工作已保留。
