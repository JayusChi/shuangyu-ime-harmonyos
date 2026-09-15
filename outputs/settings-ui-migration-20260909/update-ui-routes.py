from pathlib import Path
root = Path(__file__).resolve().parents[2]
changes = {
 'entry/src/main/ets/presentation/settings/UserLexiconPage.ets': [
   ('export struct UserLexiconPage {', "export struct UserLexiconPage {\n  @Prop initialAction: UserLexiconActionType = 'ADD';\n  @Prop pageTitle: string = '我的词库';"),
   ('  aboutToAppear(): void {', '  aboutToAppear(): void {\n    this.action = this.initialAction;'),
   ("Text('用户词库').fontSize(24)", 'Text(this.pageTitle).fontSize(24)')
 ],
 'entry/src/main/ets/pages/XiaoheYinxingCategoryManagerPage.ets': [
   ("Text('码表分类')", "Text('内置词库分类')"),
   ("Text('小鹤音形分类词库')", "Text('小鹤音形')")
 ],
 'entry/src/main/resources/base/profile/main_pages.json': [
   ('"pages/UserLexicon",', '"pages/UserLexicon",\n    "pages/UserShortcuts",')
 ],
 'entry/src/internalDebug/resources/base/profile/main_pages.json': [
   ('"pages/UserLexicon",', '"pages/UserLexicon",\n    "pages/UserShortcuts",')
 ]
}
for relative, replacements in changes.items():
    path=root / relative
    text=path.read_text(encoding='utf-8')
    backup=Path(__file__).parent / (path.name+'.route-before')
    if not backup.exists(): backup.write_text(text,encoding='utf-8')
    for before,after in replacements:
        assert text.count(before)==1, (relative,before,text.count(before))
        text=text.replace(before,after)
    path.with_suffix(path.suffix+'.ui-next').write_text(text,encoding='utf-8')
    print(relative)
