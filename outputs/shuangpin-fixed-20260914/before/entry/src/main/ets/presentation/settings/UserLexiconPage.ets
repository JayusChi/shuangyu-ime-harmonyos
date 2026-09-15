import { isExternalDirectTarget } from '../../domain/direct/ExternalDirectTarget';
import common from '@ohos.app.ability.common';
import picker from '@ohos.file.picker';
import {
  getSharedUserLexiconController,
  UserLexiconController,
  UserLexiconListener,
  UserLexiconOperationResult
} from '../../application/UserLexiconController';
import {
  UserLexiconActionType,
  UserLexiconDocument,
  UserLexiconEntryRecord
} from '../../infrastructure/native/NativeEngineTypes';
import { getSharedSettingsController } from '../../application/SettingsController';
import { LexiconImportMode, LexiconSourceConfig } from '../../domain/settings/ImeSettings';
import { resolveSettingsTheme, SettingsThemeTokens } from './SettingsTheme';
import { SettingsChoiceChips } from './SettingsDetailComponents';
import {
  EMPTY_SETTINGS_SAFE_AREA,
  getSharedSettingsWindowCoordinator,
  SettingsSafeAreaInsets,
  SettingsSafeAreaListener,
  SettingsWindowCoordinator
} from '../../application/SettingsWindowCoordinator';


function initialDocument(): UserLexiconDocument {
  return {
    success: true,
    errorCode: '',
    errorLine: 0,
    errorField: '',
    message: '',
    warningCode: '',
    revision: '',
    entries: [],
    stats: { accepted: 0, effective: 0, added: 0, deleted: 0, fixed: 0, positioned: 0 }
  };
}

@Component
export struct UserLexiconPage {
  @Prop initialAction: string = 'ADD';
  @State private pageTitle: string = '我的词库';
  private readonly controller: UserLexiconController = getSharedUserLexiconController();
  @State private document: UserLexiconDocument = initialDocument();
  @Prop theme: SettingsThemeTokens = resolveSettingsTheme(false);
  @State private busy: boolean = true;
  @State private searchText: string = '';
  @State private entryText: string = '';
  @State private entryDisplayText: string = '';
  @State private entryCode: string = '';
  @State private action: UserLexiconActionType = 'ADD';
  @State private positionText: string = '1';
  @State private selectedIds: string[] = [];
  @State private transferText: string = '';
  @State private lexiconSources: LexiconSourceConfig[] = [];
  @State private safeArea: SettingsSafeAreaInsets = EMPTY_SETTINGS_SAFE_AREA;
  private windowCoordinator?: SettingsWindowCoordinator;
  private readonly onDocumentChanged: UserLexiconListener = (document: UserLexiconDocument): void => {
    this.document = document;
  };
  private readonly onSafeAreaChanged: SettingsSafeAreaListener = (insets: SettingsSafeAreaInsets): void => {
    this.safeArea = insets;
  };

  aboutToAppear(): void {
    if (this.initialAction === 'DIRECT') {
      this.action = 'DIRECT';
      this.pageTitle = '自定义直通';
    }
    this.controller.subscribe(this.onDocumentChanged);
    this.windowCoordinator = getSharedSettingsWindowCoordinator();
    this.windowCoordinator?.subscribeSafeArea(this.onSafeAreaChanged);
    this.theme = resolveSettingsTheme(getSharedSettingsController().isDarkMode());
    this.reloadLexiconSources();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.controller.initialize(context).then((document: UserLexiconDocument): void => {
      this.document = document;
      this.busy = false;
      if (!document.success) {
        this.showToast(document.message);
      }
    }).catch((err: Object): void => {
      this.busy = false;
      this.showToast(`用户词库加载失败：${JSON.stringify(err)}`);
    });
  }

  aboutToDisappear(): void {
    this.controller.unsubscribe(this.onDocumentChanged);
    this.windowCoordinator?.unsubscribeSafeArea(this.onSafeAreaChanged);
    this.windowCoordinator = undefined;
  }

  private parsePosition(): number {
    const parsed = Number.parseInt(this.positionText);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : 0;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (_) {}
  }

  private goBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (err) {
      this.showToast(`返回失败：${JSON.stringify(err)}`);
    }
  }

  private saveEntry(): void {
    const text = this.entryText.trim();
    const displayText = this.entryDisplayText.trim();
    const code = this.entryCode.trim().toLowerCase();
    const position = this.parsePosition();
    if (text.length <= 0 || code.length <= 0) {
      this.showToast('请输入词条和编码');
      return;
    }
    if (this.action === 'OPEN_URL' || this.action === 'OPEN_DIRECTORY') {
      const action = this.action === 'OPEN_URL' ? 'url.open' : 'directory.open';
      if (!isExternalDirectTarget(action, text)) {
        this.showToast(this.action === 'OPEN_URL' ? '请输入完整的 http:// 或 https:// 网址' : '请使用“选择目录”保存鸿蒙目录');
        return;
      }
    }
    if (this.action === 'POSITION' && position <= 0) {
      this.showToast('指定位置必须是正整数');
      return;
    }
    this.busy = true;
    this.controller.upsert(text, code, this.action, position, displayText).then((result) => {
      this.finish(result);
      if (result.success) {
        this.entryText = '';
        this.entryDisplayText = '';
        this.entryCode = '';
      }
    });
  }

  private async chooseShortcutDirectory(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const selected = await new picker.DocumentViewPicker(context).select({
        maxSelectNumber: 1, selectMode: picker.DocumentSelectMode.FOLDER
      });
      if (selected.length > 0) {
        this.entryText = selected[0];
      }
    } catch (_) {
      this.showToast('未能选择目录，请重试');
    }
  }

  private toggleSelection(id: string): void {
    const ids = this.selectedIds.slice();
    const index = ids.indexOf(id);
    if (index >= 0) {
      ids.splice(index, 1);
    } else {
      ids.push(id);
    }
    this.selectedIds = ids;
  }

  private applyBatch(action: UserLexiconActionType): void {
    if (this.selectedIds.length <= 0) {
      this.showToast('请先选择词条');
      return;
    }
    const position = this.parsePosition();
    if (action === 'POSITION' && position <= 0) {
      this.showToast('指定位置必须是正整数');
      return;
    }
    this.busy = true;
    this.controller.applyAction(this.selectedIds, action, position).then((result) => this.finish(result));
  }

  private removeSelected(): void {
    if (this.selectedIds.length <= 0) {
      this.showToast('请先选择词条');
      return;
    }
    this.busy = true;
    this.controller.remove(this.selectedIds).then((result) => this.finish(result));
  }

  private importText(replace: boolean): void {
    if (this.transferText.trim().length <= 0) {
      this.showToast('请粘贴待导入词库文本');
      return;
    }
    this.busy = true;
    this.controller.importText(this.transferText, replace).then((result) => this.finish(result));
  }

  private reloadLexiconSources(): void {
    this.lexiconSources = getSharedSettingsController().getLexiconSources();
  }

  private async addLexiconSource(mode: LexiconImportMode): Promise<void> {
    try {
      const selected = await new picker.DocumentViewPicker().select({ maxSelectNumber: 1 });
      if (selected.length <= 0) {
        return;
      }
      const uri = selected[0];
      const displayName = uri.split('/').pop() || '用户词库';
      const source: LexiconSourceConfig = {
        id: `lexicon-${Date.now()}`,
        displayName,
        filePath: uri,
        enabled: true,
        priority: this.lexiconSources.length,
        mode
      };
      this.busy = true;
      const result = await getSharedSettingsController().addLexiconSource(source);
      this.busy = false;
      if (result.success) {
        this.reloadLexiconSources();
      }
      this.showToast(result.success ? '固定词库来源已保存' : result.message);
    } catch (err) {
      this.busy = false;
      this.showToast(`选择词库失败：${JSON.stringify(err)}`);
    }
  }

  private async toggleLexiconSource(source: LexiconSourceConfig): Promise<void> {
    this.busy = true;
    const result = await getSharedSettingsController().updateLexiconSource(
      source.id,
      { enabled: !source.enabled }
    );
    this.busy = false;
    if (result.success) {
      this.reloadLexiconSources();
    }
    this.showToast(result.success ? '词库来源设置已更新' : result.message);
  }

  private async cycleLexiconSourceMode(source: LexiconSourceConfig): Promise<void> {
    let mode: LexiconImportMode = 'MERGE';
    if (source.mode === 'MERGE') {
      mode = 'APPEND';
    } else if (source.mode === 'APPEND') {
      mode = 'REPLACE';
    }
    this.busy = true;
    const result = await getSharedSettingsController().updateLexiconSource(source.id, { mode });
    this.busy = false;
    if (result.success) {
      this.reloadLexiconSources();
    }
    this.showToast(result.success ? `导入模式：${mode}` : result.message);
  }

  private async removeLexiconSource(source: LexiconSourceConfig): Promise<void> {
    this.busy = true;
    const result = await getSharedSettingsController().removeLexiconSource(source.id);
    this.busy = false;
    if (result.success) {
      this.reloadLexiconSources();
    }
    this.showToast(result.success ? '固定词库来源已移除' : result.message);
  }

  private applyLexiconSources(): void {
    if (this.lexiconSources.filter((source: LexiconSourceConfig): boolean => source.enabled).length === 0) {
      this.showToast('没有启用的固定词库来源');
      return;
    }
    this.busy = true;
    this.controller.importSources(this.lexiconSources).then((result: UserLexiconOperationResult): void =>
      this.finish(result));
  }

  private finish(result: UserLexiconOperationResult): void {
    this.busy = false;
    this.document = result.document;
    if (result.success) {
      this.selectedIds = [];
    }
    this.showToast(result.success ? '用户词库已应用' : result.message);
  }

  private actionLabel(entry: UserLexiconEntryRecord): string {
    if (entry.action === 'OPEN_URL' || entry.action === 'OPEN_DIRECTORY') {
      return (entry.action === 'OPEN_URL' ? '打开网页' : '打开目录') +
        (entry.displayText.length > 0 ? ' · ' + entry.displayText : '');
    }
    if (entry.action === 'DIRECT') {
      return entry.displayText.length > 0 ? `直通 · 候选显示“${entry.displayText}”` : '直通';
    }
    if (entry.action === 'DELETE') return '隐藏系统词';
    if (entry.action === 'FIXED') return '固顶';
    if (entry.action === 'POSITION') return `第 ${entry.position} 位`;
    return '添加';
  }

  private isVisible(entry: UserLexiconEntryRecord): boolean {
    const query = this.searchText.trim().toLowerCase();
    return query.length <= 0 || entry.text.toLowerCase().indexOf(query) >= 0 ||
      entry.code.toLowerCase().indexOf(query) >= 0;
  }

  @Builder
  private SmallButton(label: string, action: () => void, danger: boolean = false) {
    Button(label)
      .fontSize(14)
      .fontColor(danger ? this.theme.danger : this.theme.accent)
      .backgroundColor(this.theme.chipBackground)
      .height(40).borderRadius(12).margin({ right: 8, bottom: 8 })
      .padding({ left: 14, right: 14 })
      .enabled(!this.busy)
      .onClick(action)
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text(`有效 ${this.document.stats.effective} 条 · 已选 ${this.selectedIds.length} 条`)
          .fontSize(13).fontColor(this.theme.secondaryText).width('100%').padding({ left: 8 })
            Column({ space: 12 }) {
              Text('新增或覆盖词条').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.primaryText)
              Column({ space: 10 }) {
                TextInput({ placeholder: this.action === 'OPEN_URL' ? '完整网址' : this.action === 'OPEN_DIRECTORY' ? '目录 URI' : '词条', text: this.entryText })
                  .fontColor(this.theme.primaryText).placeholderColor(this.theme.secondaryText)
                  .backgroundColor(this.theme.pageBackground).borderRadius(12)
                  .type(this.action === 'OPEN_URL' ? InputType.URL : InputType.Normal)
                  .onChange((value: string) => this.entryText = value).width('100%')
                TextInput({ placeholder: '编码', text: this.entryCode })
                  .fontColor(this.theme.primaryText).placeholderColor(this.theme.secondaryText)
                  .backgroundColor(this.theme.pageBackground).borderRadius(12)
                  .type(InputType.Email)
                  .onChange((value: string) => this.entryCode = value).width('100%')
              }
              SettingsChoiceChips({
                title: '动作',
                values: ['ADD', 'DIRECT', 'DELETE', 'FIXED', 'POSITION'],
                labels: ['添加', '直通', '隐藏系统词', '固顶', '第 N 位'],
                currentValue: this.action === 'OPEN_URL' || this.action === 'OPEN_DIRECTORY' ? 'DIRECT' : this.action,
                primaryTextColor: this.theme.primaryText,
                secondaryTextColor: this.theme.secondaryText,
                chipBackground: this.theme.chipBackground,
                selectedChipBackground: this.theme.selectedChipBackground,
                accentColor: this.theme.accent,
                onValueChange: (value: string) => this.action = value as UserLexiconActionType
              })
              if (this.action === 'DIRECT' || this.action === 'OPEN_URL' || this.action === 'OPEN_DIRECTORY') {
                SettingsChoiceChips({
                  title: '直通类型', values: ['DIRECT', 'OPEN_URL', 'OPEN_DIRECTORY'],
                  labels: ['上屏文字', '打开网页', '打开目录'], currentValue: this.action,
                  primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
                  chipBackground: this.theme.chipBackground, selectedChipBackground: this.theme.selectedChipBackground,
                  accentColor: this.theme.accent,
                  onValueChange: (value: string) => this.action = value as UserLexiconActionType
                })
              }
              if (this.action === 'OPEN_DIRECTORY') {
                this.SmallButton('选择目录', () => { this.chooseShortcutDirectory(); })
              }
              if (this.action === 'DIRECT' || this.action === 'OPEN_URL' || this.action === 'OPEN_DIRECTORY') {
                TextInput({ placeholder: '候选提示（可选）', text: this.entryDisplayText })
                  .fontColor(this.theme.primaryText).placeholderColor(this.theme.secondaryText)
                  .backgroundColor(this.theme.pageBackground).borderRadius(12)
                  .onChange((value: string) => this.entryDisplayText = value)
              }
              if (this.action === 'POSITION') {
                TextInput({ placeholder: 'N（正整数）', text: this.positionText })
                  .fontColor(this.theme.primaryText).placeholderColor(this.theme.secondaryText)
                  .backgroundColor(this.theme.pageBackground).borderRadius(12)
                  .type(InputType.Number)
                  .onChange((value: string) => this.positionText = value)
              }
              Button('保存并立即应用').width('100%').height(48).borderRadius(14)
                .fontColor('#FFFFFF').backgroundColor(this.theme.accent).enabled(!this.busy).onClick(() => this.saveEntry())
            }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground).alignItems(HorizontalAlign.Start)

            Column({ space: 10 }) {
              Text('词条管理').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.primaryText)
              TextInput({ placeholder: '搜索词条或编码', text: this.searchText })
                  .fontColor(this.theme.primaryText).placeholderColor(this.theme.secondaryText)
                  .backgroundColor(this.theme.pageBackground).borderRadius(12)
                .onChange((value: string) => this.searchText = value)
              Flex({ wrap: FlexWrap.Wrap }) {
                this.SmallButton('普通', () => this.applyBatch('ADD'))
                this.SmallButton('直通', () => this.applyBatch('DIRECT'))
                this.SmallButton('隐藏', () => this.applyBatch('DELETE'))
                this.SmallButton('固顶', () => this.applyBatch('FIXED'))
              }.width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                this.SmallButton('第 N 位', () => this.applyBatch('POSITION'))
                this.SmallButton('移除', () => this.removeSelected(), true)
              }.width('100%')
              if (this.document.entries.length === 0) {
                Text('暂无词条，可在上方添加或从文本导入').fontSize(14)
                  .fontColor(this.theme.secondaryText).width('100%').padding({ top: 20, bottom: 20 })
              }
              List({ space: 6 }) {
                ForEach(this.document.entries, (entry: UserLexiconEntryRecord) => {
                  if (this.isVisible(entry)) {
                    ListItem() {
                      Row({ space: 10 }) {
                        Text(this.selectedIds.indexOf(entry.id) >= 0 ? '✓' : '○')
                          .fontSize(20).fontColor(this.theme.accent)
                        Column({ space: 3 }) {
                          Text(`${entry.text}${entry.displayText.length > 0 ? ` → ${entry.displayText}` : ''}  ${entry.code}`)
                            .fontSize(15).fontColor(this.theme.primaryText)
                          Text(this.actionLabel(entry)).fontSize(11).fontColor(this.theme.secondaryText)
                        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      }.width('100%').padding(10).backgroundColor(this.theme.chipBackground)
                        .borderRadius(10).onClick(() => this.toggleSelection(entry.id))
                    }
                  }
                }, (entry: UserLexiconEntryRecord) => entry.id)
              }.width('100%').height(this.document.entries.length > 0 ? 320 : 0).scrollBar(BarState.Auto)
            }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground).alignItems(HorizontalAlign.Start)

            Column({ space: 10 }) {
              Text('批量导入 / 导出').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.primaryText)
              Text('每行格式：词条<Tab>编码；支持 #直、#删、#固、#N。网页或目录：目标<Tab>编码#网页（或 #目录）<Tab>候选提示')
                .fontSize(12).fontColor(this.theme.secondaryText)
              TextArea({ placeholder: '在此粘贴或查看词库文本', text: this.transferText })
                  .fontColor(this.theme.primaryText).placeholderColor(this.theme.secondaryText)
                  .backgroundColor(this.theme.pageBackground).borderRadius(12)
                .height(180).onChange((value: string) => this.transferText = value)
              Flex({ wrap: FlexWrap.Wrap }) {
                this.SmallButton('合并导入', () => this.importText(false))
                this.SmallButton('覆盖导入', () => this.importText(true), true)
                this.SmallButton('导出到文本框', () => this.transferText = this.controller.exportText())
              }.width('100%')
            }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground).alignItems(HorizontalAlign.Start)

            Column({ space: 10 }) {
              Text('固定位置词库').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.primaryText)
              Text('通过系统文件选择器授权来源；可按优先级在启动时自动合并或覆盖。')
                .fontSize(12).fontColor(this.theme.secondaryText)
              Flex({ wrap: FlexWrap.Wrap }) {
                this.SmallButton('添加合并来源', () => this.addLexiconSource('MERGE'))
                this.SmallButton('添加覆盖来源', () => this.addLexiconSource('REPLACE'), true)
                this.SmallButton('立即导入', () => this.applyLexiconSources())
              }.width('100%')
              ForEach(this.lexiconSources, (source: LexiconSourceConfig) => {
                Column({ space: 10 }) {
                  Column({ space: 4 }) {
                    Text(source.displayName).fontSize(14).fontColor(this.theme.primaryText)
                    Text(`${source.enabled ? '已启用' : '已停用'} · ${source.mode} · ${source.filePath}`)
                      .fontSize(10).fontColor(this.theme.secondaryText).maxLines(2)
                  }.width('100%').alignItems(HorizontalAlign.Start)
                  Flex({ wrap: FlexWrap.Wrap }) {
                  this.SmallButton(source.enabled ? '停用' : '启用', () => this.toggleLexiconSource(source))
                  this.SmallButton('切换模式', () => this.cycleLexiconSourceMode(source))
                  this.SmallButton('移除', () => this.removeLexiconSource(source), true)
                  }.width('100%')
                }.width('100%').padding(8).backgroundColor(this.theme.chipBackground).borderRadius(10)
              }, (source: LexiconSourceConfig) => source.id)
            }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground).alignItems(HorizontalAlign.Start)
      }.width('100%').constraintSize({ maxWidth: 720 })
        .padding({ left: 20, right: 20, top: 8, bottom: 32 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Auto)
      .backgroundColor(this.theme.pageBackground)
  }
}
