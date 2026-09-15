from pathlib import Path
import zipfile, json, hashlib
exec((Path(__file__).parent / 'implement-clipboard-reverse.py').read_text(encoding='utf-8').split("replace('engine-rust/crates/code-table-runtime/src/state.rs'")[0])
edit('docs/API_CONTRACT.md', lambda text: text + '''
## 复制反查（ofi）

新增只读 N-API `reverseLookup(handle, text): string`，返回 JSON 编码数组。C ABI 对应 `ime_engine_reverse_lookup(handle, text_utf8, text_len, out_buffer)`；输入为单个 UTF-8 汉字（最多 4 字节），无匹配或非码表方案返回 `[]`，非法 UTF-8、超限输入和无效句柄返回既有错误码。输出 buffer 仍由 `ime_engine_free_buffer` 释放。此为增量接口，既有结构和函数签名不变，版本继续为 11。

内置 `ofi` 候选使用 `DIRECT_CONTROL`，`formatId=clipboard.reverse`、`text=''`、`cursorOffsetUtf16=0`。ArkTS 在剪贴板读取后调用只读反查接口，并在同一输入会话中保存显示／上屏快照；选择动作不将原始表达式或 `[复制反查]` 上屏。详情见 [复制反查直通](features/direct-control/CLIPBOARD_REVERSE_LOOKUP.md)。
''')
edit('docs/features/direct-control/ACTION_PROTOCOL.md', lambda text: text + '''
### 复制反查

`ofi` 的旧 `querycode` 记录及客户 `$CC(default(dict.rev(clip()), "[复制反查]"), type(dict.rev(clip())))` 表达式转换为 `clipboard.reverse`，目标仅允许空字符串。候选保留 `[复制反查]` 作为稳定标识，展示内容来自会话内的本地反查结果；无结果时选中不输出文字。受限剪贴板通过候选区 `PasteButton` 授权后刷新，见 [复制反查说明](CLIPBOARD_REVERSE_LOOKUP.md)。
''')
hap = ROOT / 'entry/build/default/outputs/default/entry-default-signed.hap'
libraries = {}
with zipfile.ZipFile(hap) as archive:
    for name in archive.namelist():
        if name.endswith('/libime_bridge.so'):
            data = archive.read(name)
            checks = {key: key.encode() in data for key in ['reverseLookup', 'ime_engine_reverse_lookup', 'clipboard.reverse']}
            assert all(checks.values()), (name, checks)
            libraries[name] = {'sha256': hashlib.sha256(data).hexdigest(), **checks}
assert len(libraries) == 2, libraries
actions = json.loads((ROOT / 'engine-rust/crates/code-table-runtime/data/production-direct-actions.json').read_text(encoding='utf-8'))
ofi = [record for record in actions['records'] if record['code'] == 'ofi']
assert len(ofi) == 1 and ofi[0]['action'] == 'clipboard.reverse'
result = {'hap': str(hap), 'nativeLibraries': libraries, 'ofi': ofi[0], 'acceptedActions': len(actions['records'])}
(ROOT / 'outputs/clipboard-reverse-package-check.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print('PACKAGE_CHECK=PASS; both native libraries include reverse lookup; exactly one ofi action')
