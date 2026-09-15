from pathlib import Path
import hashlib, io, json, zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
DELIVERY = ROOT / 'artifacts/0.11.0'
manifest = json.loads((OUT / 'delivery-verification.json').read_text(encoding='utf-8-sig'))
app = DELIVERY / manifest['file']
assert manifest['versionName'] == '0.11.0' and manifest['versionCode'] == 11000000
assert manifest['profileType'] == 'release' and manifest['distribution'] == 'app_gallery'
assert hashlib.sha256(app.read_bytes()).hexdigest().upper() == manifest['sha256']
symbols = {}
with zipfile.ZipFile(app) as archive:
    with zipfile.ZipFile(io.BytesIO(archive.read('entry-default.hap'))) as module:
        for abi in ['arm64-v8a', 'x86_64']:
            data = module.read(f'libs/{abi}/libime_bridge.so')
            found = {name: name.encode() in data for name in ['reverseLookup', 'ime_engine_reverse_lookup', 'clipboard.reverse']}
            assert all(found.values()), (abi, found)
            symbols[abi] = {'sha256': hashlib.sha256(data).hexdigest(), **found}
manifest['clipboardReverseLookup'] = {'code': 'ofi', 'includedInBothAbis': True, 'symbols': symbols}
(OUT / 'delivery-verification.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def write(path, text):
    temporary = path.with_name(path.name + '.update.tmp')
    assert temporary.resolve().is_relative_to(ROOT)
    temporary.write_text(text, encoding='utf-8')
    temporary.replace(path)

notes_path = DELIVERY / 'RELEASE_NOTES_zh-CN.txt'
notes = notes_path.read_text(encoding='utf-8-sig')
notes = notes.replace('本次更新\n', '本次更新\n新增：ofi 复制反查。复制一个汉字后输入 ofi，候选显示本地编码，选中后上屏编码；读取受限时点击候选区的系统“粘贴”按钮。查不到时显示 [复制反查]，选中不输出文字。固定候选栏和浮动候选窗均支持。\n', 1)
notes = notes.replace('剪贴板查形沿用系统', '剪贴板查形和复制反查沿用系统')
notes = notes[:notes.index('验证说明\n')] + '''验证说明
- 本次功能源码通过714项 ArkTS测试、98项码表回归、34项音形引擎回归、5项直通动作回归及3项复制反查专项。
- 保持0.11.0 / 11000000 / build 1，重新构建双 ABI 与正式签名APP，APP/Profile签名、独立及内嵌HAP资源校验通过。
- 既有手机/电脑18项网页与宿主检查属于此前查形功能验收；新增复制反查的设备粘贴授权与实际宿主上屏仍待客户测试。
- 实际宿主应用、真实 USB/蓝牙键盘及客户渠道升级，请在客户设备上继续验收。
'''
write(notes_path, notes)
readme_path = DELIVERY / 'AGC_UPLOAD_README.md'
readme = readme_path.read_text(encoding='utf-8-sig')
readme = readme.replace('24,980,564', f"{manifest['bytes']:,}")
readme = readme.replace('7DCE29688E0CDB3382D278DE0A93B5DBF417DF9C4CB68A3A5E0B247954CD391B', manifest['sha256'])
readme = readme.replace('包含最新键盘、候选、双拼和应用内查形修复', '包含新增 ofi 复制反查及最新键盘、候选、双拼和应用内查形修复')
readme = readme.replace('outputs/release-0.11.0/RELEASE_READINESS.md', 'outputs/release-0.11.0-clipboard-reverse/RELEASE_READINESS.md')
start = readme.index('功能源码刚通过')
end = readme.index('\n\n', start)
readme = readme[:start] + '本次功能源码已通过714项 ArkTS测试及相关Rust回归，包含复制反查。保持 0.11.0 / 11000000 / build 1，重新正式签名打包；未安装本次APP到设备。既有手机/电脑18项网页检查属于此前查形功能验收，新增复制反查的设备授权和宿主上屏仍需客户测试。' + readme[end:]
write(readme_path, readme)
readiness = f'''# 0.11.0 复制反查补充包

2026-09-11：构建与交付检查通过。按用户要求保持 **0.11.0 / 11000000 / build 1**，使用既有正式发布签名。

- 双 ABI Native、clean release 产品 HAP、assembleApp 构建通过。
- APP 与 Profile 签名、有效期、包名和版本通过；正式证书与 APP 标识沿用 0.10.0。
- 独立与内嵌 HAP 资源门禁通过，模块内容一致；两个 ABI 均包含复制反查接口和 clipboard.reverse 动作。
- 沿用刚完成的同源码功能验证：714 项 ArkTS、98 项码表、34 项音形引擎、5 项直通动作与3项复制反查专项通过。[功能证据](../../docs/evidence/2026-09-11-clipboard-reverse/README.md)
- 未安装到设备或上传 AGC，复制反查真实设备授权和上屏待客户验收。既有共享沙箱授权限制保持。

交付：[APP](../../artifacts/0.11.0/{app.name})，{manifest['bytes']:,} bytes，SHA-256 `{manifest['sha256']}`。

[签名、身份及包检查](delivery-verification.json) · [HAP构建](build-release-hap.log) · [APP构建](build-app.log) · [独立HAP门禁](verify-signed-hap.log) · [内嵌HAP门禁](verify-embedded-hap.log)

本次包替换同版本旧交付文件；不含复制反查的旧 APP 已保留在 previous/ 目录。
'''
write(OUT / 'RELEASE_READINESS.md', readiness)
state_path = ROOT / 'PROJECT_STATE.md'
state = state_path.read_text(encoding='utf-8-sig')
state = state.replace('**0.11.0 正式签名 APP RELEASE_APP_BUILT_AND_VERIFIED（2026-09-11）**', '**0.11.0 首次构建（历史，未包含复制反查）RELEASE_APP_BUILT_AND_VERIFIED（2026-09-11）**', 1)
state = state.replace('## 当前阶段\n', f'## 当前阶段\n\n**0.11.0 复制反查补充 APP RELEASE_APP_BUILT_AND_VERIFIED（2026-09-11）** — 按用户要求保持 0.11.0 / 11000000 / build 1，使用正式 release 产品签名重新构建，包含 ofi 复制反查。双 ABI、clean HAP、APP、签名与独立/内嵌 HAP 门禁通过；功能源码714项ArkTS及相关Rust回归通过。交付 artifacts/0.11.0/{app.name}，{manifest["bytes"]:,} bytes，SHA-256 {manifest["sha256"]}。未上传或安装到客户设备，复制反查设备授权/上屏待实测；共享沙箱限制保持。详见 outputs/release-0.11.0-clipboard-reverse/RELEASE_READINESS.md。下方同版本首次构建记录为历史，其旧APP已保留到本次输出目录的 previous/。\n', 1)
write(state_path, state)
print(json.dumps({'version': manifest['versionName'], 'app': str(app), 'bytes': manifest['bytes'], 'sha256': manifest['sha256'], 'clipboardReverse': 'PASS'}, ensure_ascii=False))
