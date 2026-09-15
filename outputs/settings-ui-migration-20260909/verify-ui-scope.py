from pathlib import Path
import hashlib, json

evidence=Path(__file__).resolve().parent
root=evidence.parents[1]
baseline=json.loads((evidence/'source-baseline.json').read_text(encoding='utf-8-sig'))
allowed={
 'entry/src/main/ets/presentation/settings/SettingsPage.ets',
 'entry/src/main/ets/presentation/settings/UserLexiconPage.ets',
 'entry/src/main/ets/pages/XiaoheYinxingCategoryManagerPage.ets'
}
changed=[]
for item in baseline:
    relative=item['Path'].replace('\\','/')
    path=root/relative
    assert path.is_file(),f'Missing existing source: {relative}'
    if hashlib.sha256(path.read_bytes()).hexdigest()!=item['Sha256'].lower():
        assert relative in allowed,f'Non-UI source modified: {relative}'
        changed.append(relative)
assert set(changed)==allowed,changed

category=(evidence/'XiaoheYinxingCategoryManagerPage.ets.route-before').read_text(encoding='utf-8')
expected=category.replace("Text('码表分类')", "Text('内置词库分类')").replace("Text('小鹤音形分类词库')", "Text('小鹤音形')")
assert expected==(root/'entry/src/main/ets/pages/XiaoheYinxingCategoryManagerPage.ets').read_text(encoding='utf-8')

lexicon=(evidence/'UserLexiconPage.ets.route-before').read_text(encoding='utf-8')
expected=lexicon.replace('function initialDocument(): UserLexiconDocument {',
 'interface UserLexiconRouteParams { initialAction?: string; }\n\nfunction initialDocument(): UserLexiconDocument {')
expected=expected.replace('export struct UserLexiconPage {', "export struct UserLexiconPage {\n  @State private pageTitle: string = '我的词库';")
expected=expected.replace('  aboutToAppear(): void {', "  aboutToAppear(): void {\n    const params = this.getUIContext().getRouter().getParams() as UserLexiconRouteParams;\n    if (params?.initialAction === 'DIRECT') {\n      this.action = 'DIRECT';\n      this.pageTitle = '自定义直通';\n    }")
expected=expected.replace("Text('用户词库').fontSize(24)", 'Text(this.pageTitle).fontSize(24)')
assert expected==(root/'entry/src/main/ets/presentation/settings/UserLexiconPage.ets').read_text(encoding='utf-8')

report={
 'result':'PASS', 'baselineFiles':len(baseline), 'unchangedExistingFiles':len(baseline)-len(changed),
 'changedExistingFiles':changed,
 'newUiComponent':'entry/src/main/ets/presentation/settings/SettingsNavigationComponents.ets',
 'categoryLogicUnchanged':True, 'lexiconLogicUnchanged':True,
 'controllersModelsStorageNativeAndRustUnchanged':True, 'routeManifestsUnchanged':True
}
(evidence/'ui-scope-result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
