# 浏览器无文本预览中文输入验证

日期：2026-07-14  
设备：x86_64 HarmonyOS API 24 模拟器（`127.0.0.1:5555`）  
输入框：系统浏览器搜索框“搜索或输入网址”

## 结果

- 输入 `ni`：浏览器输入框保持空白，候选栏显示“你、拟、尼、呢、泥”等候选。
- 候选阶段未出现 `text preview update failed`。
- 点击首选“你”：浏览器输入框内容变为“你”。
- hilog 显示一次 `insertText ok: length=1`，随后 Native 候选确认完成。

## 证据

- `browser_fix_before.json`：修复版键盘初始布局。
- `browser_fix_ni.json` / `browser_fix_ni.png`：无预览组合与候选。
- `browser_fix_committed.json` / `browser_fix_committed.png`：中文提交结果。
