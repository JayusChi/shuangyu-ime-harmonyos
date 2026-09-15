from pathlib import Path

root = Path.cwd()
base = root / 'outputs/settings-details-unification-20260909/before'
ets = 'entry/src/main/ets/'

def old(path):
    return (base / (ets + path)).read_text(encoding='utf-8')

def write(path, text):
    target = root / (ets + path)
    temp = target.with_suffix('.ui-next')
    temp.write_text(text, encoding='utf-8')
    temp.replace(target)

# Existing routes remain valid entry points, now opening the same settings shell.
for wrapper, struct, destination, section in [
    ('KeyboardCustomization', 'KeyboardCustomization', 'customization', 'appearance'),
    ('XiaoheYinxingCategoryManagerPage', 'XiaoheYinxingCategoryManagerPage', 'categories', 'lexicon')
]:
    write(f'pages/{wrapper}.ets', f'''import {{ SettingsPage }} from '../presentation/settings/SettingsPage';

@Entry
@Component
struct {struct} {{
  build() {{
    SettingsPage({{ initialDestination: '{destination}', initialSection: '{section}' }})
  }}
}}
''')

write('pages/UserLexicon.ets', '''import { SettingsPage } from '../presentation/settings/SettingsPage';

interface UserLexiconRouteParams { initialAction?: string; }

@Entry
@Component
struct UserLexicon {
  @State private destination: string = 'user-lexicon';

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as UserLexiconRouteParams;
    this.destination = params?.initialAction === 'DIRECT' ? 'user-shortcuts' : 'user-lexicon';
  }

  build() {
    SettingsPage({ initialDestination: this.destination, initialSection: 'lexicon' })
  }
}
''')

# Settings root owns every destination and the only detail header.
s = old('presentation/settings/SettingsPage.ets')
s = """import { KeyboardCustomizationPage } from './KeyboardCustomizationPage';
import { UserLexiconPage } from './UserLexiconPage';
import { YinxingCategorySettings } from './YinxingCategorySettings';
import { SettingsDetailHeader, SettingsLeaveGuard } from './SettingsDetailComponents';
""" + s
s = s.replace('export struct SettingsPage {', '''export struct SettingsPage {
  @Prop initialDestination: string = '';
  @Prop initialSection: string = '';
  private detailLeaveGuard?: SettingsLeaveGuard;''')
s = s.replace('    this.refresh();\n    try {', '''    this.refresh();
    if (this.initialDestination.length > 0 && this.pageStack.size() === 0) {
      this.activeSection = this.initialSection;
      this.pageStack.pushPathByName(this.initialSection, undefined, false);
      this.pageStack.pushPathByName(this.initialDestination, undefined, false);
    }
    try {''', 1)
start=s.index('  private openPage('); end=s.index('  private showToast',start)
s=s[:start]+s[end:]
start=s.index('  private openSection(');end=s.index('  private currentProfile',start)
s=s[:start]+'''  private requestNavigation(proceed: () => void): void {
    if (this.detailLeaveGuard) this.detailLeaveGuard(proceed);
    else proceed();
  }

  private openSection(name: string): void {
    this.requestNavigation((): void => {
      this.activeSection = name;
      if (this.wideLayout) this.pageStack.clear();
      this.pageStack.pushPathByName(name, undefined);
    });
  }

  private openDetail(name: string): void {
    this.requestNavigation((): void => { this.pageStack.pushPathByName(name, undefined); });
  }

  private goBack(): void {
    this.requestNavigation((): void => { this.pageStack.pop(); });
  }

'''+s[end:]
s=s.replace("this.openPage('pages/KeyboardCustomization')", "this.openDetail('customization')")
s=s.replace("this.openPage('pages/UserLexicon', 'DIRECT')", "this.openDetail('user-shortcuts')")
s=s.replace("this.openPage('pages/UserLexicon')", "this.openDetail('user-lexicon')")
s=s.replace("this.openPage('pages/XiaoheYinxingCategoryManagerPage')", "this.openDetail('categories')")
s=s.replace("      case 'input': return '输入设置';", """      case 'customization': return '键盘结构与皮肤';
      case 'customization-structure': return '键盘结构';
      case 'customization-skin': return '键盘皮肤';
      case 'customization-swipe': return '字母键下滑符号';
      case 'user-lexicon': return '我的词库';
      case 'user-shortcuts': return '自定义直通';
      case 'categories': return '小鹤音形词库分类';
      case 'input': return '输入设置';""")
start=s.index('        Row({ space: 8 }) {', s.index('  private Destination('))
end=s.index('        Scroll() {', start)
s=s[:start]+'''        SettingsDetailHeader({ title: this.pageTitle(name), theme: this.theme, onBack: () => this.goBack() })
        if (name === 'customization' || name.startsWith('customization-')) {
          KeyboardCustomizationPage({ section: name === 'customization' ? 'overview' : name.substring(14),
            onNavigate: (destination: string): void => this.openDetail(destination) }).layoutWeight(1)
        } else if (name === 'user-lexicon' || name === 'user-shortcuts') {
          UserLexiconPage({ initialAction: name === 'user-shortcuts' ? 'DIRECT' : 'ADD' }).layoutWeight(1)
        } else if (name === 'categories') {
          YinxingCategorySettings({
            onRegisterLeave: (guard?: SettingsLeaveGuard): void => { this.detailLeaveGuard = guard; },
            onNavigateBack: (): void => { this.pageStack.pop(); }
          }).layoutWeight(1)
        } else {
'''+s[end:]
needle="        }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)\n      }.width('100%').height('100%').backgroundColor(this.theme.pageBackground)"
assert needle in s
s=s.replace(needle, needle.replace('\n      }','\n        }\n      }'),1)
s=s.replace("    }.hideTitleBar(true).backgroundColor(this.theme.pageBackground)", """    }.hideTitleBar(true).backgroundColor(this.theme.pageBackground)
      .onBackPressed((): boolean => { this.goBack(); return true; })""")
write('presentation/settings/SettingsPage.ets',s)

# Customization business methods are preserved. Only the builders are reorganized.
s=old('presentation/settings/KeyboardCustomizationPage.ets')
s="import { SettingsNavigationRow } from './SettingsNavigationComponents';\n"+s
s=s.replace('export struct KeyboardCustomizationPage {', '''export struct KeyboardCustomizationPage {
  @Prop section: string = 'overview';
  onNavigate: (destination: string) => void = () => {};''')
start=s.index('  build() {')
swipe=s[s.index('            Row({ space: 10 }) {', start):s.index("            Column({ space: 8 }) {\n              Text('键盘内快捷切换')",start)]
swipe=swipe.replace('.borderRadius(14)', '.borderRadius(18)')
swipe=swipe.replace(".fontColor(Color.White)", ".fontColor('#FFFFFF')")
swipe=swipe.replace('.backgroundColor(this.theme.accent)\n', '.backgroundColor(this.theme.accent)\n                .height(44).borderRadius(14)\n')
# Move preset controls ahead of the long 26-key list without changing callbacks.
gridstart=swipe.index('            Column({ space: 8 }) {')
controls=swipe.index('            Row({ space: 8 }) {',gridstart)
swipe=swipe[:gridstart]+swipe[controls:]+swipe[gridstart:controls]
s=s[:start]+'''  @Builder
  private Overview() {
    Column() {
      SettingsNavigationRow({ title: '键盘结构', description: '选择按键布局，或导入自己的结构包', theme: this.theme,
        controlId: 'settings-open-customization-structure', onOpen: () => this.onNavigate('customization-structure') })
      Divider().color(this.theme.divider).margin({ left: 16, right: 16 })
      SettingsNavigationRow({ title: '键盘皮肤', description: '选择配色与图片，或导入皮肤包', theme: this.theme,
        controlId: 'settings-open-customization-skin', onOpen: () => this.onNavigate('customization-skin') })
      Divider().color(this.theme.divider).margin({ left: 16, right: 16 })
      SettingsNavigationRow({ title: '字母键下滑符号', description: '中英文分别设置，支持导入、导出映射', theme: this.theme,
        controlId: 'settings-open-customization-swipe', onOpen: () => this.onNavigate('customization-swipe') })
    }.width('100%').borderRadius(18).clip(true)
    Column({ space: 8 }) {
      Text('键盘内快捷切换').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.primaryText)
      Text('同时按“ϟ12 + 空格”切换皮肤；同时按“符 + 空格”切换结构。')
        .fontSize(14).fontColor(this.theme.secondaryText)
    }.width('100%').padding(18).alignItems(HorizontalAlign.Start)
      .borderRadius(18).backgroundColor(this.theme.cardBackground)
  }

  @Builder
  private TemplateList(kind: CustomizationKind) {
    Column({ space: 16 }) {
      this.SectionTitle(kind === 'structure' ? '已安装结构' : '已安装皮肤',
        kind === 'structure' ? '选择按键排列与宽度' : '皮肤可与已安装的键盘结构自由组合')
      ForEach(kind === 'structure' ? this.structures : this.skins, (option: KeyboardCustomizationOption) => {
        this.OptionRow(kind, option)
      }, (option: KeyboardCustomizationOption): string =>
        `${option.id}:${option.id === (kind === 'structure' ? this.selectedStructureId : this.selectedSkinId) ? 'selected' : 'idle'}`)
    }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
    Button(kind === 'structure' ? '导入结构包' : '导入皮肤包')
      .width('100%').height(48).borderRadius(14).fontSize(16).enabled(!this.busy)
      .fontColor('#FFFFFF').backgroundColor(this.theme.accent)
      .id('settings-import-' + kind).onClick((): void => { this.importPackage(kind); })
  }

  @Builder
  private SwipeSymbols() {
    this.SectionTitle('下滑符号映射', '中英文分别设置；制表符显示为 \\\\t。修改后点击保存。')
'''+swipe+'''  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.storageMessage.length > 0 && this.section !== 'swipe') {
          Text(this.storageMessage).fontSize(13).fontColor(this.theme.danger)
            .width('100%').padding(18).backgroundColor(this.theme.cardBackground).borderRadius(18)
        }
        if (this.section === 'overview') { this.Overview() }
        else if (this.section === 'structure') { this.TemplateList('structure') }
        else if (this.section === 'skin') { this.TemplateList('skin') }
        else { this.SwipeSymbols() }
      }.width('100%').constraintSize({ maxWidth: 720 })
        .padding({ left: 20, right: 20, top: 8, bottom: 32 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Auto)
      .backgroundColor(this.theme.pageBackground)
  }
}
'''
# Match row shape to the new cards; retain selection and delete handlers.
s=s.replace('.borderRadius(12)\n    .backgroundColor(', '.borderRadius(14)\n    .backgroundColor(')
s=s.replace('this.theme.selectedChipBackground : this.theme.chipBackground', 'this.theme.selectedChipBackground : this.theme.pageBackground')
write('presentation/settings/KeyboardCustomizationPage.ets',s)

# Keep the whole lexicon editing state together: position and selected entries are shared
# by the existing form and batch handlers. Rearranging those into separate instances
# would change their behavior, so the same component owns all of them.
s=old('presentation/settings/UserLexiconPage.ets')
s=s.replace("interface UserLexiconRouteParams { initialAction?: string; }\n",'')
s=s.replace('export struct UserLexiconPage {', "export struct UserLexiconPage {\n  @Prop initialAction: string = 'ADD';")
s=s.replace("    const params = this.getUIContext().getRouter().getParams() as UserLexiconRouteParams;\n    if (params?.initialAction === 'DIRECT') {", "    if (this.initialAction === 'DIRECT') {")
start=s.index('  build() {')
contentstart=s.index('            Column({ space: 12 }) {',start)
contentend=s.index("          }.width('100%').padding({ bottom: 28 })",contentstart)
content=s[contentstart:contentend]
content=content.replace('.padding(16).borderRadius(16)', '.padding(18).borderRadius(18)')
# Explicit theme tokens prevent native input fields from following a different theme.
import re
content=re.sub(r'(TextInput\(\{[^\n]+\}\)|TextArea\(\{[^\n]+\}\))',r"\1\n                  .fontColor(this.theme.primaryText).placeholderColor(this.theme.secondaryText)\n                  .backgroundColor(this.theme.pageBackground).borderRadius(12)",content)
content=content.replace("Button('保存并立即应用').width('100%').enabled(!this.busy)", "Button('保存并立即应用').width('100%').height(48).borderRadius(14)\n                .fontColor('#FFFFFF').backgroundColor(this.theme.accent).enabled(!this.busy)")
# Wrap action buttons rather than compressing their text in narrow detail panes.
content=content.replace('Row({ space: 6 }) {', 'Flex({ wrap: FlexWrap.Wrap }) {')
content=content.replace('Row({ space: 8 }) {\n                this.SmallButton', 'Flex({ wrap: FlexWrap.Wrap }) {\n                this.SmallButton')
content=content.replace("            Column({ space: 10 }) {\n              TextInput({ placeholder: '搜索词条或编码'", "            Column({ space: 10 }) {\n              Text('词条管理').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.primaryText)\n              TextInput({ placeholder: '搜索词条或编码'")
content=content.replace("              List({ space: 6 }) {", """              if (this.document.entries.length === 0) {
                Text('暂无词条，可在上方添加或从文本导入').fontSize(14)
                  .fontColor(this.theme.secondaryText).width('100%').padding({ top: 20, bottom: 20 })
              }
              List({ space: 6 }) {""")
content=content.replace(".height(320).scrollBar(BarState.Off)", ".height(this.document.entries.length > 0 ? 320 : 0).scrollBar(BarState.Auto)")
# Source metadata takes a full row and actions wrap beneath it.
content=content.replace('                Row({ space: 8 }) {\n                  Column({ space: 2 }) {', '                Column({ space: 10 }) {\n                  Column({ space: 4 }) {')
content=content.replace("                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)\n                  this.SmallButton(source.enabled", "                  }.width('100%').alignItems(HorizontalAlign.Start)\n                  Flex({ wrap: FlexWrap.Wrap }) {\n                  this.SmallButton(source.enabled")
content=content.replace("this.SmallButton('移除', () => this.removeLexiconSource(source), true)\n                }", "this.SmallButton('移除', () => this.removeLexiconSource(source), true)\n                  }.width('100%')\n                }")
s=s[:start]+'''  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text(`有效 ${this.document.stats.effective} 条 · 已选 ${this.selectedIds.length} 条`)
          .fontSize(13).fontColor(this.theme.secondaryText).width('100%').padding({ left: 8 })
'''+content+'''      }.width('100%').constraintSize({ maxWidth: 720 })
        .padding({ left: 20, right: 20, top: 8, bottom: 32 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Auto)
      .backgroundColor(this.theme.pageBackground)
  }
}
'''
s=s.replace('.fontSize(12)\n      .fontColor(danger', '.fontSize(14)\n      .fontColor(danger')
s=s.replace('.height(34)\n      .enabled', ".height(40).borderRadius(12).margin({ right: 8, bottom: 8 })\n      .padding({ left: 14, right: 14 })\n      .enabled")
write('presentation/settings/UserLexiconPage.ets',s)

# Relocate the existing category component behind a route wrapper. Navigation adapts,
# while category mutation/save/reset and the original confirmation remain unchanged.
s=old('pages/XiaoheYinxingCategoryManagerPage.ets')
s=s.replace("from '../application/", "from '../../application/").replace("from '../domain/", "from '../../domain/")
s=s.replace("from '../common/", "from '../../common/").replace("from '../state/", "from '../../state/")
s=s.replace("from '../presentation/settings/SettingsTheme'", "from './SettingsTheme'")
s="import { SettingsLeaveGuard } from './SettingsDetailComponents';\n"+s
s=s.replace('@Entry\n@Component\nstruct XiaoheYinxingCategoryManagerPage {', '''@Component
export struct YinxingCategorySettings {
  onRegisterLeave: (guard?: SettingsLeaveGuard) => void = () => {};
  onNavigateBack: () => void = () => {};
  private pendingNavigation?: () => void;''')
s=s.replace('  aboutToAppear(): void {', '''  aboutToAppear(): void {
    this.onRegisterLeave((proceed: () => void): void => {
      this.pendingNavigation = proceed;
      this.goBack();
    });''')
s=s.replace('  aboutToDisappear(): void {', '''  aboutToDisappear(): void {
    this.onRegisterLeave(undefined);''')
s=s.replace('      this.getUIContext().getRouter().back();', '''      const proceed = this.pendingNavigation;
      this.pendingNavigation = undefined;
      if (proceed) proceed();
      else this.onNavigateBack();''')
start=s.index('  build() {'); bodystart=s.index('        Scroll() {',start)
bodyend=s.index("      }\n      .width('100%')\n      .height('100%')",bodystart)
body=s[bodystart:bodyend]
body=body.replace("          .width('100%')\n          .padding({ left: 20, right: 20, top: 4, bottom: 14 })", "          .width('100%').constraintSize({ maxWidth: 720 })\n          .padding({ left: 20, right: 20, top: 8, bottom: 24 })")
body=body.replace('.scrollBar(BarState.Off)', ".width('100%').align(Alignment.Top).scrollBar(BarState.Auto)")
body=body.replace("        .width('100%')\n        .padding({ left: 20, right: 20, top: 12, bottom: 12 })", "        .width('100%').constraintSize({ maxWidth: 720 })\n        .padding({ left: 20, right: 20, top: 12, bottom: 12 })")
body=body.replace("        .backgroundColor(this.theme.cardBackground)\n        .border({ width: { top: 0.5 }, color: this.theme.divider })", "        .backgroundColor(this.theme.pageBackground)")
tail=s[s.index('@Component\nstruct CategoryItem',bodyend):]
s=s[:start]+'''  build() {
    Column() {
'''+body+'''    }.width('100%').height('100%').backgroundColor(this.theme.pageBackground)
  }
}

'''+tail
write('presentation/settings/YinxingCategorySettings.ets',s)
print('Unified settings destinations and legacy detail UI written.')
