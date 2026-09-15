import { SettingsNavigationRow } from './SettingsNavigationComponents';
import common from '@ohos.app.ability.common';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import {
  getSharedSettingsController,
  SettingsController,
  SettingsOperationResult
} from '../../application/SettingsController';
import {
  BUILTIN_KEYBOARD_SKIN_ID,
  BUILTIN_KEYBOARD_STRUCTURE_ID,
  KeyboardCustomizationOption
} from '../../domain/customization/KeyboardCustomization';
import {
  getSharedKeyboardCustomizationRepository,
  KeyboardCustomizationImportResult,
  KeyboardCustomizationRepository
} from '../../infrastructure/customization/KeyboardCustomizationRepository';
import { resolveSettingsTheme, SettingsThemeTokens } from './SettingsTheme';
import {
  EMPTY_SETTINGS_SAFE_AREA,
  getSharedSettingsWindowCoordinator,
  SettingsSafeAreaInsets,
  SettingsSafeAreaListener,
  SettingsWindowCoordinator
} from '../../application/SettingsWindowCoordinator';
import {
  LETTER_SWIPE_KEYS,
  LETTER_SWIPE_TAB_SYMBOL,
  LetterSwipeSymbolProfileParseResult,
  MAX_LETTER_SWIPE_SYMBOL_UNITS,
  normalizeLetterSwipeSymbol,
  parseLetterSwipeSymbolProfile,
  parseLetterSwipeSymbols,
  RECOMMENDED_CHINESE_LETTER_SWIPE_SYMBOLS,
  RECOMMENDED_ENGLISH_LETTER_SWIPE_SYMBOLS,
  serializeLetterSwipeSymbolProfile
} from '../../domain/keyboard/LetterSwipeSymbols';

type CustomizationKind = 'structure' | 'skin';
type SwipeSymbolMode = 'chinese' | 'english';
const MAX_SWIPE_SYMBOL_PROFILE_BYTES: number = 64 * 1024;
const SWIPE_SYMBOL_PROFILE_FILE_NAME: string = 'shuangyu_letter_swipe_symbols.sy-swipe';

@Component
export struct KeyboardCustomizationPage {
  @Prop section: string = 'overview';
  onNavigate: (destination: string) => void = () => {};
  private readonly settingsController: SettingsController = getSharedSettingsController();
  private readonly repository: KeyboardCustomizationRepository = getSharedKeyboardCustomizationRepository();
  @State private structures: KeyboardCustomizationOption[] = [];
  @State private skins: KeyboardCustomizationOption[] = [];
  @State private selectedStructureId: string = BUILTIN_KEYBOARD_STRUCTURE_ID;
  @State private selectedSkinId: string = BUILTIN_KEYBOARD_SKIN_ID;
  @State private swipeSymbolMode: SwipeSymbolMode = 'chinese';
  @State private chineseSwipeSymbols: string[] = [];
  @State private englishSwipeSymbols: string[] = [];
  @Prop theme: SettingsThemeTokens = resolveSettingsTheme(false);
  @State private busy: boolean = false;
  @State private storageMessage: string = '';
  @State private unavailableOptions: string[] = [];
  private pageGeneration: number = 0;
  @State private safeArea: SettingsSafeAreaInsets = EMPTY_SETTINGS_SAFE_AREA;
  private windowCoordinator?: SettingsWindowCoordinator;
  private readonly onSafeAreaChanged: SettingsSafeAreaListener = (insets: SettingsSafeAreaInsets): void => {
    this.safeArea = insets;
  };

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const generation = ++this.pageGeneration;
    this.busy = true;
    this.repository.initialize(context, true).then((): void => {
      if (generation === this.pageGeneration) {
        this.busy = false;
        this.refresh();
      }
    });
    this.windowCoordinator = getSharedSettingsWindowCoordinator();
    this.windowCoordinator?.subscribeSafeArea(this.onSafeAreaChanged);
    this.refresh();
  }

  aboutToDisappear(): void {
    this.pageGeneration++;
    this.windowCoordinator?.unsubscribeSafeArea(this.onSafeAreaChanged);
    this.windowCoordinator = undefined;
  }

  private refresh(): void {
    const settings = this.settingsController.getSettings();
    this.selectedStructureId = settings.keyboardStructureId;
    this.selectedSkinId = settings.keyboardSkinId;
    this.chineseSwipeSymbols = parseLetterSwipeSymbols(settings.chineseLetterSwipeSymbols);
    this.englishSwipeSymbols = parseLetterSwipeSymbols(settings.englishLetterSwipeSymbols);
    this.structures = this.repository.listStructures();
    this.skins = this.repository.listSkins();
    this.storageMessage = this.repository.getStorageMessage();
    this.unavailableOptions = this.structures
      .filter((option: KeyboardCustomizationOption): boolean =>
        this.repository.selectionError('structure', option.id).length > 0)
      .map((option: KeyboardCustomizationOption): string => `structure:${option.id}`)
      .concat(this.skins
        .filter((option: KeyboardCustomizationOption): boolean =>
          this.repository.selectionError('skin', option.id).length > 0)
        .map((option: KeyboardCustomizationOption): string => `skin:${option.id}`));
    this.theme = resolveSettingsTheme(this.settingsController.isDarkMode());
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

  private async selectOption(kind: CustomizationKind, id: string): Promise<void> {
    if (this.busy) {
      return;
    }
    const selectionError = this.repository.selectionError(kind, id);
    if (selectionError.length > 0) {
      this.showToast(selectionError);
      return;
    }
    this.busy = true;
    const result = kind === 'structure'
      ? await this.settingsController.setKeyboardStructureId(id)
      : await this.settingsController.setKeyboardSkinId(id);
    this.finish(result, result.success ? '已应用' : result.message);
  }

  private async importPackage(kind: CustomizationKind): Promise<void> {
    if (this.busy) {
      return;
    }
    if (!this.repository.canImport()) {
      this.showToast(this.repository.getStorageMessage());
      return;
    }
    try {
      const selected = await new picker.DocumentViewPicker().select({ maxSelectNumber: 1 });
      if (selected.length <= 0) {
        return;
      }
      this.busy = true;
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const imported: KeyboardCustomizationImportResult = kind === 'structure'
        ? await this.repository.importStructurePackage(context, selected[0])
        : await this.repository.importSkinPackage(context, selected[0]);
      if (!imported.success || !imported.id) {
        this.busy = false;
        this.showToast(imported.message);
        return;
      }
      const selectedResult = kind === 'structure'
        ? await this.settingsController.setKeyboardStructureId(imported.id)
        : await this.settingsController.setKeyboardSkinId(imported.id);
      this.finish(
        selectedResult,
        selectedResult.success ? `${imported.name ?? '模板'}已导入并设为当前模板` : selectedResult.message
      );
    } catch (err) {
      this.busy = false;
      this.showToast(`选择模板包失败：${JSON.stringify(err)}`);
    }
  }

  private removeOption(kind: CustomizationKind, option: KeyboardCustomizationOption): void {
    if (this.busy || option.builtIn) {
      return;
    }
    try {
      this.getUIContext().showAlertDialog({
        title: '删除模板',
        message: `确定删除“${option.name}”吗？`,
        primaryButton: { value: '取消', action: (): void => {} },
        secondaryButton: {
          value: '删除',
          fontColor: this.theme.danger,
          action: (): void => {
            this.removeOptionConfirmed(kind, option);
          }
        }
      });
    } catch (err) {
      this.showToast(`删除确认框打开失败：${JSON.stringify(err)}`);
    }
  }

  private async removeOptionConfirmed(kind: CustomizationKind, option: KeyboardCustomizationOption): Promise<void> {
    if (!this.repository.canImport()) {
      this.showToast(this.repository.getStorageMessage());
      return;
    }
    this.busy = true;
    const selected = kind === 'structure' ? this.selectedStructureId : this.selectedSkinId;
    if (selected === option.id) {
      const fallbackResult = kind === 'structure'
        ? await this.settingsController.setKeyboardStructureId(BUILTIN_KEYBOARD_STRUCTURE_ID)
        : await this.settingsController.setKeyboardSkinId(BUILTIN_KEYBOARD_SKIN_ID);
      if (!fallbackResult.success) {
        this.finish(fallbackResult, fallbackResult.message);
        return;
      }
    }
    const removed = kind === 'structure'
      ? this.repository.removeStructure(option.id)
      : this.repository.removeSkin(option.id);
    this.busy = false;
    this.refresh();
    this.showToast(removed ? '模板已删除' : '模板删除失败');
  }

  private finish(result: SettingsOperationResult, successMessage: string): void {
    this.busy = false;
    this.refresh();
    this.showToast(result.success ? successMessage : result.message);
  }

  private currentSwipeSymbols(): string[] {
    return this.swipeSymbolMode === 'chinese' ? this.chineseSwipeSymbols : this.englishSwipeSymbols;
  }

  private updateSwipeSymbol(index: number, value: string): void {
    const symbols = this.currentSwipeSymbols().slice();
    symbols[index] = value === '\\t' ? LETTER_SWIPE_TAB_SYMBOL : normalizeLetterSwipeSymbol(value);
    if (this.swipeSymbolMode === 'chinese') {
      this.chineseSwipeSymbols = symbols;
    } else {
      this.englishSwipeSymbols = symbols;
    }
  }

  private swipeSymbolInputText(index: number): string {
    const symbol = this.currentSwipeSymbols()[index] ?? '';
    return symbol === LETTER_SWIPE_TAB_SYMBOL ? '\\t' : symbol;
  }

  private clearSwipeSymbols(): void {
    const cleared = LETTER_SWIPE_KEYS.map((): string => '');
    if (this.swipeSymbolMode === 'chinese') {
      this.chineseSwipeSymbols = cleared;
    } else {
      this.englishSwipeSymbols = cleared;
    }
  }

  private applyRecommendedSwipeSymbols(): void {
    const recommended = parseLetterSwipeSymbols(
      this.swipeSymbolMode === 'chinese'
        ? RECOMMENDED_CHINESE_LETTER_SWIPE_SYMBOLS
        : RECOMMENDED_ENGLISH_LETTER_SWIPE_SYMBOLS
    );
    if (this.swipeSymbolMode === 'chinese') {
      this.chineseSwipeSymbols = recommended;
    } else {
      this.englishSwipeSymbols = recommended;
    }
  }

  private async saveSwipeSymbols(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const result = await this.settingsController.setLetterSwipeSymbols(
      JSON.stringify(this.chineseSwipeSymbols),
      JSON.stringify(this.englishSwipeSymbols)
    );
    this.finish(result, result.success ? '中英文下滑符号已保存' : result.message);
  }

  private readSwipeSymbolProfile(uri: string): string {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const size = fs.statSync(file.fd).size;
      if (size <= 0 || size > MAX_SWIPE_SYMBOL_PROFILE_BYTES) {
        throw new Error('文件大小必须在 1B～64KB 之间');
      }
      const buffer = new ArrayBuffer(size);
      const bytesRead = fs.readSync(file.fd, buffer);
      if (bytesRead !== size) {
        throw new Error('文件读取不完整');
      }
      return new util.TextDecoder('utf-8').decode(new Uint8Array(buffer, 0, bytesRead));
    } finally {
      fs.closeSync(file);
    }
  }

  private async importSwipeSymbolProfile(): Promise<void> {
    if (this.busy) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const selected = await new picker.DocumentViewPicker(context).select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['双羽下滑符号|.sy-swipe,.json']
      });
      if (selected.length <= 0) {
        return;
      }
      this.busy = true;
      const parsed: LetterSwipeSymbolProfileParseResult = parseLetterSwipeSymbolProfile(
        this.readSwipeSymbolProfile(selected[0])
      );
      if (!parsed.success || !parsed.value) {
        this.busy = false;
        this.showToast(parsed.message);
        return;
      }
      const result = await this.settingsController.setLetterSwipeSymbols(
        JSON.stringify(parsed.value.chineseSymbols),
        JSON.stringify(parsed.value.englishSymbols)
      );
      this.finish(result, result.success ? '下滑符号已导入并保存，可继续修改' : result.message);
    } catch (err) {
      this.busy = false;
      this.showToast(`下滑符号导入失败：${JSON.stringify(err)}`);
    }
  }

  private async exportSwipeSymbolProfile(): Promise<void> {
    if (this.busy) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const selected = await new picker.DocumentViewPicker(context).save({
        newFileNames: [SWIPE_SYMBOL_PROFILE_FILE_NAME],
        fileSuffixChoices: ['双羽下滑符号|.sy-swipe']
      });
      if (selected.length <= 0) {
        return;
      }
      this.busy = true;
      const content = serializeLetterSwipeSymbolProfile(this.chineseSwipeSymbols, this.englishSwipeSymbols);
      const file = fs.openSync(
        selected[0],
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
      );
      try {
        fs.writeSync(file.fd, content);
      } finally {
        fs.closeSync(file);
      }
      this.busy = false;
      this.showToast('当前中英文下滑符号已导出');
    } catch (err) {
      this.busy = false;
      this.showToast(`下滑符号导出失败：${JSON.stringify(err)}`);
    }
  }

  @Builder
  private SectionTitle(title: string, description: string) {
    Column({ space: 5 }) {
      Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.theme.primaryText)
      Text(description).fontSize(12).fontColor(this.theme.secondaryText)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private OptionRow(kind: CustomizationKind, option: KeyboardCustomizationOption) {
    Row({ space: 10 }) {
      Text(this.isOptionSelected(kind, option.id) ? '✓' : '')
        .fontSize(17)
        .fontColor(this.theme.accent)
        .width(22)
      Column({ space: 3 }) {
        Text(option.name).fontSize(15).fontColor(this.theme.primaryText).fontWeight(FontWeight.Medium)
        Text(option.builtIn ? (kind === 'structure' ? '内置结构' : '内置皮肤') : '已导入').fontSize(12).fontColor(this.theme.secondaryText)
        if (this.unavailableOptions.indexOf(`${kind}:${option.id}`) >= 0) {
          Text('尚未同步到输入法，请更新安装包后重新导入').fontSize(11).fontColor(this.theme.secondaryText)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (!option.builtIn) {
        Button('删除')
          .fontSize(12)
          .fontColor(this.theme.danger)
          .backgroundColor(Color.Transparent)
          .enabled(!this.busy)
          .onClick((): void => this.removeOption(kind, option))
      }
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor(
      this.isOptionSelected(kind, option.id) ? this.theme.selectedChipBackground : this.theme.pageBackground
    )
    .onClick((): void => {
      if (!this.isOptionSelected(kind, option.id)) {
        this.selectOption(kind, option.id);
      }
    })
  }

  private isOptionSelected(kind: CustomizationKind, id: string): boolean {
    if (this.unavailableOptions.indexOf(`${kind}:${id}`) >= 0) {
      return false;
    }
    return kind === 'structure' ? id === this.selectedStructureId : id === this.selectedSkinId;
  }

  @Builder
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
    this.SectionTitle('下滑符号映射', '中英文分别设置；制表符显示为 \\t。修改后点击保存。')
            Row({ space: 10 }) {
              Button('中文键盘')
                .layoutWeight(1)
                .fontColor(this.swipeSymbolMode === 'chinese' ? Color.White : this.theme.primaryText)
                .backgroundColor(this.swipeSymbolMode === 'chinese' ? this.theme.accent : this.theme.chipBackground)
                .onClick((): void => { this.swipeSymbolMode = 'chinese'; })
              Button('英文键盘')
                .layoutWeight(1)
                .fontColor(this.swipeSymbolMode === 'english' ? Color.White : this.theme.primaryText)
                .backgroundColor(this.swipeSymbolMode === 'english' ? this.theme.accent : this.theme.chipBackground)
                .onClick((): void => { this.swipeSymbolMode = 'english'; })
            }
            .width('100%')

            Row({ space: 8 }) {
              Button('导入映射')
                .layoutWeight(1)
                .enabled(!this.busy)
                .fontColor(this.theme.primaryText)
                .backgroundColor(this.theme.chipBackground)
                .onClick((): void => { this.importSwipeSymbolProfile(); })
              Button('导出映射')
                .layoutWeight(1)
                .enabled(!this.busy)
                .fontColor(this.theme.primaryText)
                .backgroundColor(this.theme.chipBackground)
                .onClick((): void => { this.exportSwipeSymbolProfile(); })
            }
            .width('100%')

            Row({ space: 8 }) {
              Button('推荐预设')
                .layoutWeight(1)
                .enabled(!this.busy)
                .fontColor(this.theme.primaryText)
                .backgroundColor(this.theme.chipBackground)
                .onClick((): void => this.applyRecommendedSwipeSymbols())
              Button('清空')
                .layoutWeight(1)
                .enabled(!this.busy)
                .fontColor(this.theme.danger)
                .backgroundColor(this.theme.chipBackground)
                .onClick((): void => this.clearSwipeSymbols())
              Button('保存')
                .layoutWeight(1)
                .enabled(!this.busy)
                .fontColor('#FFFFFF')
                .backgroundColor(this.theme.accent)
                .height(44).borderRadius(14)
                .onClick((): void => { this.saveSwipeSymbols(); })
            }
            .width('100%')

            Column({ space: 8 }) {
              ForEach(LETTER_SWIPE_KEYS, (letter: string, index: number) => {
                Row({ space: 12 }) {
                  Text(letter.toUpperCase())
                    .width(34)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.theme.primaryText)
                    .textAlign(TextAlign.Center)
                  TextInput({
                    text: this.swipeSymbolInputText(index),
                    placeholder: '未设置'
                  })
                    .layoutWeight(1)
                    .height(40)
                    .maxLength(MAX_LETTER_SWIPE_SYMBOL_UNITS)
                    .fontColor(this.theme.primaryText)
                    .placeholderColor(this.theme.secondaryText)
                    .backgroundColor(this.theme.chipBackground)
                    .onChange((value: string): void => this.updateSwipeSymbol(index, value))
                }
                .width('100%')
              }, (letter: string): string => `${this.swipeSymbolMode}-${letter}`)
            }
            .width('100%')
            .padding(14)
            .borderRadius(18)
            .backgroundColor(this.theme.cardBackground)

  }

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
