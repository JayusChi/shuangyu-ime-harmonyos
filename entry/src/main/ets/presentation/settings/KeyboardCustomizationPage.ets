import common from '@ohos.app.ability.common';
import picker from '@ohos.file.picker';
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
  MAX_LETTER_SWIPE_SYMBOL_UNITS,
  normalizeLetterSwipeSymbol,
  parseLetterSwipeSymbols,
  RECOMMENDED_LETTER_SWIPE_SYMBOLS
} from '../../domain/keyboard/LetterSwipeSymbols';

type CustomizationKind = 'structure' | 'skin';
type SwipeSymbolMode = 'chinese' | 'english';

@Component
export struct KeyboardCustomizationPage {
  private readonly settingsController: SettingsController = getSharedSettingsController();
  private readonly repository: KeyboardCustomizationRepository = getSharedKeyboardCustomizationRepository();
  @State private structures: KeyboardCustomizationOption[] = [];
  @State private skins: KeyboardCustomizationOption[] = [];
  @State private selectedStructureId: string = BUILTIN_KEYBOARD_STRUCTURE_ID;
  @State private selectedSkinId: string = BUILTIN_KEYBOARD_SKIN_ID;
  @State private swipeSymbolMode: SwipeSymbolMode = 'chinese';
  @State private chineseSwipeSymbols: string[] = [];
  @State private englishSwipeSymbols: string[] = [];
  @State private theme: SettingsThemeTokens = resolveSettingsTheme(false);
  @State private busy: boolean = false;
  @State private safeArea: SettingsSafeAreaInsets = EMPTY_SETTINGS_SAFE_AREA;
  private windowCoordinator?: SettingsWindowCoordinator;
  private readonly onSafeAreaChanged: SettingsSafeAreaListener = (insets: SettingsSafeAreaInsets): void => {
    this.safeArea = insets;
  };

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.repository.initialize(context);
    this.windowCoordinator = getSharedSettingsWindowCoordinator();
    this.windowCoordinator?.subscribeSafeArea(this.onSafeAreaChanged);
    this.refresh();
  }

  aboutToDisappear(): void {
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
        selectedResult.success ? `${imported.name ?? '模板'}已导入并应用` : selectedResult.message
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
    symbols[index] = normalizeLetterSwipeSymbol(value);
    if (this.swipeSymbolMode === 'chinese') {
      this.chineseSwipeSymbols = symbols;
    } else {
      this.englishSwipeSymbols = symbols;
    }
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
    const recommended = parseLetterSwipeSymbols(RECOMMENDED_LETTER_SWIPE_SYMBOLS);
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
        Text(option.id).fontSize(11).fontColor(this.theme.secondaryText)
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
    .borderRadius(12)
    .backgroundColor(
      this.isOptionSelected(kind, option.id) ? this.theme.selectedChipBackground : this.theme.chipBackground
    )
    .onClick((): void => {
      if (!this.isOptionSelected(kind, option.id)) {
        this.selectOption(kind, option.id);
      }
    })
  }

  private isOptionSelected(kind: CustomizationKind, id: string): boolean {
    return kind === 'structure' ? id === this.selectedStructureId : id === this.selectedSkinId;
  }

  build() {
    Stack() {
      Column() {
        Row({ space: 12 }) {
          Button('‹')
            .fontSize(28)
            .fontColor(this.theme.primaryText)
            .backgroundColor(Color.Transparent)
            .onClick((): void => this.goBack())
          Text('键盘结构与皮肤')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.primaryText)
            .layoutWeight(1)
        }
        .height(56)
        .width('100%')
        .padding({ left: 8, right: 18 })

        Scroll() {
          Column({ space: 18 }) {
            this.SectionTitle('键盘结构', '结构只负责按键排列、宽度和显示文字，不改变输入引擎')
            Button('导入结构包')
              .width('100%')
              .enabled(!this.busy)
              .fontColor(Color.White)
              .backgroundColor(this.theme.accent)
              .onClick((): void => {
                this.importPackage('structure');
              })
            ForEach(this.structures, (option: KeyboardCustomizationOption) => {
              this.OptionRow('structure', option)
            }, (option: KeyboardCustomizationOption): string =>
              `${option.id}:${option.id === this.selectedStructureId ? 'selected' : 'idle'}`)

            Divider().color(this.theme.divider).margin({ top: 4, bottom: 4 })

            this.SectionTitle('键盘皮肤', '皮肤只负责颜色和本地图片，可与任意已安装结构自由组合')
            Button('导入皮肤包')
              .width('100%')
              .enabled(!this.busy)
              .fontColor(Color.White)
              .backgroundColor(this.theme.accent)
              .onClick((): void => {
                this.importPackage('skin');
              })
            ForEach(this.skins, (option: KeyboardCustomizationOption) => {
              this.OptionRow('skin', option)
            }, (option: KeyboardCustomizationOption): string =>
              `${option.id}:${option.id === this.selectedSkinId ? 'selected' : 'idle'}`)

            Divider().color(this.theme.divider).margin({ top: 4, bottom: 4 })

            this.SectionTitle('字母键下滑符号', '中英文键盘分别设置；符号只在此页显示，不会标在键面上')
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
                    text: this.currentSwipeSymbols()[index],
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
            .borderRadius(14)
            .backgroundColor(this.theme.cardBackground)

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
                .fontColor(Color.White)
                .backgroundColor(this.theme.accent)
                .onClick((): void => { this.saveSwipeSymbols(); })
            }
            .width('100%')

            Column({ space: 8 }) {
              Text('键盘内快捷切换').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.theme.primaryText)
              Text('同时按“ϟ12 + 空格”切换皮肤；同时按“符 + 空格”切换结构。')
                .fontSize(12)
                .fontColor(this.theme.secondaryText)
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start)
            .borderRadius(14)
            .backgroundColor(this.theme.cardBackground)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 36 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.safeArea.top,
        bottom: this.safeArea.bottom,
        left: this.safeArea.left,
        right: this.safeArea.right
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
  }
}
