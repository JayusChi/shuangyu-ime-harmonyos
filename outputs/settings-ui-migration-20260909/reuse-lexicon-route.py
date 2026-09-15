from pathlib import Path
import json, hashlib
root=Path(__file__).resolve().parents[2]
baseline=json.loads((Path(__file__).parent/'source-baseline.json').read_text(encoding='utf-8-sig'))
hashes={x['Path'].replace('\\','/'):x['Sha256'].lower() for x in baseline}
for relative in ['entry/src/main/resources/base/profile/main_pages.json','entry/src/internalDebug/resources/base/profile/main_pages.json']:
    path=root/relative
    content=path.read_text(encoding='utf-8').replace('    "pages/UserShortcuts",\n','')
    options=[content.encode(),content.replace('\n','\r\n').encode()]
    matches=[b for b in options if hashlib.sha256(b).hexdigest()==hashes[relative]]
    assert len(matches)==1,relative
    path.with_suffix('.json.ui-next').write_bytes(matches[0])
path=root/'entry/src/main/ets/presentation/settings/SettingsPage.ets'
text=path.read_text(encoding='utf-8')
text=text.replace('private openPage(url: string): void {', "private openPage(url: string, initialAction: string = 'ADD'): void {")
text=text.replace('pushUrl({ url })','pushUrl({ url, params: { initialAction } })')
text=text.replace("this.openPage('pages/UserShortcuts')", "this.openPage('pages/UserLexicon', 'DIRECT')")
path.with_suffix('.ets.ui-next').write_text(text,encoding='utf-8')
path=root/'entry/src/main/ets/presentation/settings/UserLexiconPage.ets'
text=path.read_text(encoding='utf-8')
text=text.replace('function initialDocument(): UserLexiconDocument {', 'interface UserLexiconRouteParams { initialAction?: string; }\n\nfunction initialDocument(): UserLexiconDocument {')
text=text.replace("  @Prop initialAction: UserLexiconActionType = 'ADD';\n  @Prop pageTitle: string = '我的词库';", "  @State private pageTitle: string = '我的词库';")
text=text.replace('    this.action = this.initialAction;', "    const params = this.getUIContext().getRouter().getParams() as UserLexiconRouteParams;\n    if (params?.initialAction === 'DIRECT') {\n      this.action = 'DIRECT';\n      this.pageTitle = '自定义直通';\n    }")
path.with_suffix('.ets.ui-next').write_text(text,encoding='utf-8')
