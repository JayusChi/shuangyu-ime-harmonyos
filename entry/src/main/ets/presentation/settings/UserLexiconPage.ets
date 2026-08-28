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
import { ChoiceSettingRow } from './SettingsComponents';
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
  private readonly controller: UserLexiconController = getSharedUserLexiconController();
  @State private document: UserLexiconDocument = initialDocument();
  @State private theme: SettingsThemeTokens = resolveSettingsTheme(false);
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
      .fontSize(12)
      .fontColor(danger ? this.theme.danger : this.theme.accent)
      .backgroundColor(this.theme.chipBackground)
      .height(34)
      .enabled(!this.busy)
      .onClick(action)
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.pageBackground)
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
        )

      Column({ space: 12 }) {
        Row({ space: 12 }) {
          Text('‹').fontSize(30).fontColor(this.theme.primaryText).onClick(() => this.goBack())
          Column({ space: 3 }) {
            Text('用户词库').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.theme.primaryText)
            Text(`有效 ${this.document.stats.effective} 条 · 已选 ${this.selectedIds.length} 条`)
              .fontSize(12).fontColor(this.theme.secondaryText)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.width('100%')

        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 12 }) {
              Text('新增或覆盖词条').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.primaryText)
              Row({ space: 8 }) {
                TextInput({ placeholder: '词条', text: this.entryText })
                  .onChange((value: string) => this.entryText = value).layoutWeight(1)
                TextInput({ placeholder: '编码', text: this.entryCode })
                  .type(InputType.Email)
                  .onChange((value: string) => this.entryCode = value).layoutWeight(1)
              }
              ChoiceSettingRow({
                title: '动作',
                values: ['ADD', 'DIRECT', 'DELETE', 'FIXED', 'POSITION'],
                labels: ['添加', '直通', '隐藏系统词', '固顶', '第 N 位'],
                currentValue: this.action,
                primaryTextColor: this.theme.primaryText,
                secondaryTextColor: this.theme.secondaryText,
                chipBackground: this.theme.chipBackground,
                selectedChipBackground: this.theme.selectedChipBackground,
                accentColor: this.theme.accent,
                onValueChange: (value: string) => this.action = value as UserLexiconActionType
              })
              if (this.action === 'DIRECT') {
                TextInput({ placeholder: '候选提示（可选；留空则同上屏内容）', text: this.entryDisplayText })
                  .onChange((value: string) => this.entryDisplayText = value)
              }
              if (this.action === 'POSITION') {
                TextInput({ placeholder: 'N（正整数）', text: this.positionText })
                  .type(InputType.Number)
                  .onChange((value: string) => this.positionText = value)
              }
              Button('保存并立即应用').width('100%').enabled(!this.busy).onClick(() => this.saveEntry())
            }.width('100%').padding(16).borderRadius(16).backgroundColor(this.theme.cardBackground)

            Column({ space: 10 }) {
              TextInput({ placeholder: '搜索词条或编码', text: this.searchText })
                .onChange((value: string) => this.searchText = value)
              Row({ space: 6 }) {
                this.SmallButton('普通', () => this.applyBatch('ADD'))
                this.SmallButton('直通', () => this.applyBatch('DIRECT'))
                this.SmallButton('隐藏', () => this.applyBatch('DELETE'))
                this.SmallButton('固顶', () => this.applyBatch('FIXED'))
              }.width('100%')
              Row({ space: 6 }) {
                this.SmallButton('第 N 位', () => this.applyBatch('POSITION'))
                this.SmallButton('移除', () => this.removeSelected(), true)
              }.width('100%')
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
              }.width('100%').height(320).scrollBar(BarState.Off)
            }.width('100%').padding(16).borderRadius(16).backgroundColor(this.theme.cardBackground)

            Column({ space: 10 }) {
              Text('批量导入 / 导出').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.primaryText)
              Text('每行格式：词条<Tab>编码；支持 #直、#删、#固、#N；直通可写“上屏内容,候选提示<Tab>编码#直”')
                .fontSize(12).fontColor(this.theme.secondaryText)
              TextArea({ placeholder: '在此粘贴或查看词库文本', text: this.transferText })
                .height(180).onChange((value: string) => this.transferText = value)
              Row({ space: 8 }) {
                this.SmallButton('合并导入', () => this.importText(false))
                this.SmallButton('覆盖导入', () => this.importText(true), true)
                this.SmallButton('导出到文本框', () => this.transferText = this.controller.exportText())
              }.width('100%')
            }.width('100%').padding(16).borderRadius(16).backgroundColor(this.theme.cardBackground)

            Column({ space: 10 }) {
              Text('固定位置词库').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.primaryText)
              Text('通过系统文件选择器授权来源；可按优先级在启动时自动合并或覆盖。')
                .fontSize(12).fontColor(this.theme.secondaryText)
              Row({ space: 8 }) {
                this.SmallButton('添加合并来源', () => this.addLexiconSource('MERGE'))
                this.SmallButton('添加覆盖来源', () => this.addLexiconSource('REPLACE'), true)
                this.SmallButton('立即导入', () => this.applyLexiconSources())
              }.width('100%')
              ForEach(this.lexiconSources, (source: LexiconSourceConfig) => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(source.displayName).fontSize(14).fontColor(this.theme.primaryText)
                    Text(`${source.enabled ? '已启用' : '已停用'} · ${source.mode} · ${source.filePath}`)
                      .fontSize(10).fontColor(this.theme.secondaryText).maxLines(2)
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  this.SmallButton(source.enabled ? '停用' : '启用', () => this.toggleLexiconSource(source))
                  this.SmallButton('切换模式', () => this.cycleLexiconSourceMode(source))
                  this.SmallButton('移除', () => this.removeLexiconSource(source), true)
                }.width('100%').padding(8).backgroundColor(this.theme.chipBackground).borderRadius(10)
              }, (source: LexiconSourceConfig) => source.id)
            }.width('100%').padding(16).borderRadius(16).backgroundColor(this.theme.cardBackground)
          }.width('100%').padding({ bottom: 28 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme.pageBackground)
      .padding({
        top: this.safeArea.top + 24,
        bottom: this.safeArea.bottom,
        left: this.safeArea.left + 20,
        right: this.safeArea.right + 20
      })
    }.width('100%').height('100%').backgroundColor(this.theme.pageBackground)
  }
}
