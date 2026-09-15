import { getSharedSettingsController, SettingsController, SettingsOperationResult } from '../../application/SettingsController';
import {
  CandidatePresentationMode,
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  HapticLevel,
  ImeSettings,
  keyboardHeightScale,
  MIN_CANDIDATE_FONT_SIZE,
  MAX_CANDIDATE_FONT_SIZE,
  LONG_PRESS_DURATION_OPTIONS_MS,
  SMART_PERIOD_TIMEOUT_OPTIONS_MS,
  QUANPIN_SCHEME_ID,
  QuanpinFuzzyOption,
  ThemeMode,
  XIAOHE_YINXING_SCHEME_ID
} from '../../domain/settings/ImeSettings';
import { enabledKeyboardProfiles, KeyboardProfile } from '../../domain/keyboard/KeyboardProfile';
import {
  SMART_PUNCTUATION_OPTIONS,
  SmartPunctuationOption
} from '../../domain/keyboard/SmartPunctuation';
import { SettingsStateListener } from '../../state/SettingsStore';
import {
  ActionSettingRow,
  ChoiceSettingRow,
  MultiChoiceSettingRow,
  SliderSettingRow,
  SwitchSettingRow
} from './SettingsComponents';
import { resolveSettingsTheme, SettingsThemeTokens } from './SettingsTheme';
import {
  EMPTY_SETTINGS_SAFE_AREA,
  getSharedSettingsWindowCoordinator,
  SettingsSafeAreaInsets,
  SettingsSafeAreaListener,
  SettingsWindowCoordinator
} from '../../application/SettingsWindowCoordinator';
import { InputPresentationPreference } from '../../domain/display/InputPresentationMode';
import { CodeTableCategoryDefinition } from '../../infrastructure/native/NativeEngineTypes';

interface CategoryOption {
  id: string;
  name: string;
  description: string;
}

interface FuzzyOptionView {
  id: QuanpinFuzzyOption;
  title: string;
}

const FUZZY_OPTION_VIEWS: FuzzyOptionView[] = [
  { id: 'n_l', title: 'n / l' },
  { id: 'z_zh', title: 'z / zh' },
  { id: 'c_ch', title: 'c / ch' },
  { id: 's_sh', title: 's / sh' },
  { id: 'in_ing', title: 'in / ing' },
  { id: 'en_eng', title: 'en / eng' },
  { id: 'an_ang', title: 'an / ang' },
  { id: 'ian_iang', title: 'ian / iang' }
];

const AVAILABLE_KEYBOARD_PROFILES: KeyboardProfile[] = enabledKeyboardProfiles();

@Component
export struct SettingsPage {
  private readonly controller: SettingsController = getSharedSettingsController();
  @State private settings: ImeSettings = copyImeSettings(DEFAULT_IME_SETTINGS);
  @State private theme: SettingsThemeTokens = resolveSettingsTheme(false);
  @State private busy: boolean = false;
  @State private safeArea: SettingsSafeAreaInsets = EMPTY_SETTINGS_SAFE_AREA;
  @State private categoryOptions: CategoryOption[] = [];
  private windowCoordinator?: SettingsWindowCoordinator;
  private readonly onSettingsChanged: SettingsStateListener = (): void => this.refresh();
  private readonly onSafeAreaChanged: SettingsSafeAreaListener = (insets: SettingsSafeAreaInsets): void => {
    this.safeArea = insets;
  };

  aboutToAppear(): void {
    this.controller.subscribe(this.onSettingsChanged);
    this.windowCoordinator = getSharedSettingsWindowCoordinator();
    this.windowCoordinator?.subscribeSafeArea(this.onSafeAreaChanged);
    this.refresh();
  }

  aboutToDisappear(): void {
    this.controller.unsubscribe(this.onSettingsChanged);
    this.windowCoordinator?.unsubscribeSafeArea(this.onSafeAreaChanged);
    this.windowCoordinator = undefined;
  }

  private refresh(): void {
    this.settings = this.controller.getSettings();
    this.theme = resolveSettingsTheme(this.controller.isDarkMode());
    if (this.settings.schemeId === XIAOHE_YINXING_SCHEME_ID) {
      const categories = this.controller.getCodeTableCategories();
      const symbolGroup = categories.find((cat: CodeTableCategoryDefinition): boolean => cat.id === 'symbol-group');
      this.categoryOptions = categories
        .filter((cat: CodeTableCategoryDefinition): boolean => cat.id !== 'symbol-group')
        .sort((a: CodeTableCategoryDefinition, b: CodeTableCategoryDefinition) => a.order - b.order)
        .map((cat: CodeTableCategoryDefinition): CategoryOption => ({
          id: cat.id,
          name: cat.displayName,
          description: `${cat.entryCount + (cat.id === 'symbol' ? symbolGroup?.entryCount ?? 0 : 0)} 条`
        }));
    } else {
      this.categoryOptions = [];
    }
  }

  private finish(result: SettingsOperationResult): void {
    this.busy = false;
    this.refresh();
    this.showToast(result.success ? $r('app.string.settings_saved') : result.message);
  }

  private openPage(url: string): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url }).catch((err: Object): void => {
        this.showToast(`页面打开失败：${JSON.stringify(err)}`);
      });
    } catch (err) {
      this.showToast(`页面打开失败：${JSON.stringify(err)}`);
    }
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (_) {}
  }

  private setCategory(categoryId: string, enabled: boolean): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    if (categoryId === 'symbol') {
      const ids = this.settings.xiaoheYinxingEnabledCategoryIds.filter(
        (id: string): boolean => id !== 'symbol' && id !== 'symbol-group'
      );
      if (enabled) {
        ids.push('symbol', 'symbol-group');
      }
      this.controller.setXiaoheYinxingEnabledCategoryIds(ids).then((result) => this.finish(result));
      return;
    }
    this.controller.toggleCategory(categoryId, enabled).then((result) => this.finish(result));
  }

  @Builder
  private SectionHeader(title: ResourceStr) {
    Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.theme.accent).width('100%')
  }

  private confirmClearUserModel(): void {
    try {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.clear_user_model'),
        message: $r('app.string.clear_user_model_confirm'),
        primaryButton: { value: $r('app.string.cancel'), action: () => {} },
        secondaryButton: {
          value: $r('app.string.clear'),
          fontColor: this.theme.danger,
          action: () => {
            if (this.busy) return;
            this.busy = true;
            this.controller.clearUserModel().then((result: SettingsOperationResult) => this.finish(result));
          }
        }
      });
    } catch (err) {
      this.showToast(`确认框打开失败：${JSON.stringify(err)}`);
    }
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

      Column() {
        Scroll() {
          Column({ space: 18 }) {
        Column({ space: 5 }) {
          Text($r('app.string.settings_title')).fontSize(28).fontWeight(FontWeight.Bold)
            .fontColor(this.theme.primaryText)
        }.width('100%').alignItems(HorizontalAlign.Start)

        this.SectionHeader($r('app.string.input_settings'))
        Column({ space: 22 }) {
          ChoiceSettingRow({
            title: '输入方案',
            description: '自动识别会随实体键盘的连接或断开切换',
            values: [
              InputPresentationPreference.AUTO,
              InputPresentationPreference.TOUCH,
              InputPresentationPreference.HARDWARE
            ],
            labels: ['自动识别', '虚拟键盘', '实体键盘'],
            currentValue: this.settings.inputPresentationPreference,
            primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText,
            chipBackground: this.theme.chipBackground,
            selectedChipBackground: this.theme.selectedChipBackground,
            accentColor: this.theme.accent,
            onValueChange: (value: string) => this.controller.setInputPresentationPreference(
              value as InputPresentationPreference
            ).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          ChoiceSettingRow({
            title: '键盘方案', description: '',
            values: AVAILABLE_KEYBOARD_PROFILES.map((item: KeyboardProfile) => item.profileId),
            labels: AVAILABLE_KEYBOARD_PROFILES.map((item: KeyboardProfile) => item.displayName),
            currentValue: this.settings.keyboardProfileId, primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText, chipBackground: this.theme.chipBackground,
            selectedChipBackground: this.theme.selectedChipBackground, accentColor: this.theme.accent,
            onValueChange: (value: string) => this.controller.setKeyboardProfile(value).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          SwitchSettingRow({
            title: $r('app.string.user_learning'), description: '',
            checked: this.settings.userLearningEnabled, primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText,
            onCheckedChange: (value: boolean) => this.controller.setUserLearningEnabled(value).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          ChoiceSettingRow({
            title: '智能标点',
            description: '时间窗内双击已选中的中文标点，替换为单个英文标点；虚拟和实体键盘均生效',
            values: SMART_PERIOD_TIMEOUT_OPTIONS_MS.map((value: number): string => `${value}`),
            labels: ['关闭', '300 毫秒', '500 毫秒', '800 毫秒', '1 秒'],
            currentValue: `${this.settings.smartPeriodTimeoutMs}`,
            primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText,
            chipBackground: this.theme.chipBackground,
            selectedChipBackground: this.theme.selectedChipBackground,
            accentColor: this.theme.accent,
            onValueChange: (value: string) => this.controller.setSmartPeriodTimeoutMs(
              Number.parseInt(value)
            ).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          MultiChoiceSettingRow({
            title: '智能标点范围',
            description: '可按需选择，对应配置项 intelligsymbol',
            values: SMART_PUNCTUATION_OPTIONS.map((item: SmartPunctuationOption): string => item.symbol),
            labels: SMART_PUNCTUATION_OPTIONS.map((item: SmartPunctuationOption): string => item.label),
            selectedValues: this.settings.smartPunctuationSymbols,
            primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText,
            chipBackground: this.theme.chipBackground,
            selectedChipBackground: this.theme.selectedChipBackground,
            accentColor: this.theme.accent,
            onSelectionChange: (symbols: string) => this.controller.setSmartPunctuationSymbols(symbols)
              .then((r) => this.finish(r))
          })
        }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)

        this.SectionHeader('AI 输入（AI-1）')
        Column({ space: 16 }) {
          SwitchSettingRow({
            title: 'AI 总开关',
            description: '五个生成动作仅在完整体验模式、明确同意且生产代理已配置时可用',
            checked: this.settings.aiEnabled,
            disabled: this.busy,
            primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText,
            onCheckedChange: (value: boolean) => {
              this.busy = true;
              this.controller.setAiEnabled(value).then((r) => this.finish(r));
            }
          })
          Divider().color(this.theme.divider)
          SwitchSettingRow({
            title: '上屏后本地关联词',
            description: '纯本地、确定性、最多 3 条；关闭后立即恢复原有候选行为',
            checked: this.settings.localAssociationEnabled,
            disabled: this.busy,
            primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText,
            onCheckedChange: (value: boolean) => {
              this.busy = true;
              this.controller.setLocalAssociationEnabled(value).then((r) => this.finish(r));
            }
          })
          Divider().color(this.theme.divider)
          Text('当前 Release 未配置获批的自有云端代理，因此云 AI 保持关闭。不上传编辑器全文、选区、剪贴板、宿主标识、用户词库或按键序列；日志不记录正文。')
            .fontSize(12)
            .fontColor(this.theme.secondaryText)
            .width('100%')
        }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)

        if (this.settings.schemeId === XIAOHE_YINXING_SCHEME_ID) {
          this.SectionHeader('音形输入')
          Column({ space: 16 }) {
            SwitchSettingRow({
              title: '切分模式',
              description: '默认传统；开启后四码空码自动按 2+2 切分，也可输入 oit 切换',
              checked: this.settings.codeTableReverseSplitEnabled,
              disabled: this.busy,
              primaryTextColor: this.theme.primaryText,
              secondaryTextColor: this.theme.secondaryText,
              onCheckedChange: (value: boolean) => {
                this.busy = true;
                this.controller.setCodeTableReverseSplitEnabled(value).then((r) => this.finish(r));
              }
            })
          }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
          this.SectionHeader('音形分类词库')
          Column({ space: 16 }) {
            ForEach(this.categoryOptions, (option: CategoryOption, index: number) => {
              SwitchSettingRow({
                title: option.name,
                description: option.description,
                checked: this.settings.xiaoheYinxingEnabledCategoryIds.indexOf(option.id) >= 0,
                disabled: this.busy,
                primaryTextColor: this.theme.primaryText,
                secondaryTextColor: this.theme.secondaryText,
                onCheckedChange: (value: boolean) => this.setCategory(option.id, value)
              })
              if (index < this.categoryOptions.length - 1) {
                Divider().color(this.theme.divider)
              }
            }, (option: CategoryOption) => option.id)
          }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
        }

        if (this.settings.schemeId === QUANPIN_SCHEME_ID) {
          this.SectionHeader('全拼容错')
          Column({ space: 16 }) {
            SwitchSettingRow({
              title: '拼写纠错',
              description: '仅修正一次多键、少键、邻键误按或相邻字母颠倒',
              checked: this.settings.spellingCorrectionEnabled,
              disabled: this.busy,
              primaryTextColor: this.theme.primaryText,
              secondaryTextColor: this.theme.secondaryText,
              onCheckedChange: (value: boolean) => {
                this.busy = true;
                this.controller.setSpellingCorrectionEnabled(value).then((r) => this.finish(r));
              }
            })
            ForEach(FUZZY_OPTION_VIEWS, (option: FuzzyOptionView) => {
              Divider().color(this.theme.divider)
              SwitchSettingRow({
                title: option.title,
                description: '独立开关，仅扩展合法拼音音节',
                checked: this.settings.fuzzyOptions.indexOf(option.id) >= 0,
                disabled: this.busy,
                primaryTextColor: this.theme.primaryText,
                secondaryTextColor: this.theme.secondaryText,
                onCheckedChange: (value: boolean) => {
                  this.busy = true;
                  this.controller.setFuzzyOption(option.id, value).then((r) => this.finish(r));
                }
              })
            }, (option: FuzzyOptionView): string => option.id)
          }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
        }

        this.SectionHeader($r('app.string.appearance'))
        Column({ space: 22 }) {
          ChoiceSettingRow({
            title: $r('app.string.theme'), description: '',
            values: [ThemeMode.FOLLOW_SYSTEM, ThemeMode.LIGHT, ThemeMode.DARK],
            labels: ['跟随系统', '浅色', '深色'], currentValue: this.settings.themeMode,
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            chipBackground: this.theme.chipBackground, selectedChipBackground: this.theme.selectedChipBackground,
            accentColor: this.theme.accent,
            onValueChange: (value: string) => this.controller.setThemeMode(value as ThemeMode).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          SliderSettingRow({
            title: $r('app.string.keyboard_height'), description: '每次调整 0.05 倍，直通码 ojg',
            value: keyboardHeightScale(this.settings.keyboardHeightMode), min: 0.8, max: 1.2, step: 0.05,
            decimals: 2, suffix: '×', primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText, accentColor: this.theme.accent,
            onValueChange: (value: number) => this.controller.setKeyboardHeightScale(value).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          SwitchSettingRow({
            title: '键盘架高层',
            description: '底部显示输入法选择、标点、左右移光标和收起键；设备已有系统底栏时可关闭',
            checked: this.settings.keyboardLiftLayerEnabled,
            disabled: this.busy,
            primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText,
            onCheckedChange: (value: boolean) => {
              this.busy = true;
              this.controller.setKeyboardLiftLayerEnabled(value).then((r) => this.finish(r));
            }
          })
          Divider().color(this.theme.divider)
          SliderSettingRow({
            title: '固定候选字号', description: '默认 15 号，直通码 ohz',
            value: this.settings.candidateFontSize, min: MIN_CANDIDATE_FONT_SIZE, max: MAX_CANDIDATE_FONT_SIZE,
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            accentColor: this.theme.accent,
            onValueChange: (value: number) => this.controller.setCandidateFontSize(value).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          SliderSettingRow({
            title: '浮动候选字号', description: '默认 17 号，直通码 ofz，与固定候选字号分别保存',
            value: this.settings.floatingCandidateFontSize, min: MIN_CANDIDATE_FONT_SIZE, max: MAX_CANDIDATE_FONT_SIZE,
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            accentColor: this.theme.accent,
            onValueChange: (value: number) => this.controller.setCandidateFontSize(value, true).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          ChoiceSettingRow({
            title: $r('app.string.candidate_presentation'),
            description: '选择“输入框下方”时，固定候选栏整行会自动隐藏',
            values: [
              CandidatePresentationMode.BAR,
              CandidatePresentationMode.FLOATING
            ],
            labels: ['候选栏', '输入框下方'],
            disabledValues: [],
            currentValue: this.settings.candidatePresentationMode === CandidatePresentationMode.FLOATING
              ? CandidatePresentationMode.FLOATING
              : CandidatePresentationMode.BAR,
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            chipBackground: this.theme.chipBackground, selectedChipBackground: this.theme.selectedChipBackground,
            accentColor: this.theme.accent,
            onValueChange: (value: string) => this.controller.setCandidatePresentationMode(
              value as CandidatePresentationMode
            ).then((r) => this.finish(r))
          })
        }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)

        this.SectionHeader($r('app.string.feedback'))
        Column({ space: 22 }) {
          ChoiceSettingRow({
            title: '长按时间',
            description: '控制长按符号、输入法切换和连续删除的触发速度',
            values: LONG_PRESS_DURATION_OPTIONS_MS.map((value: number): string => `${value}`),
            labels: ['200 毫秒', '300 毫秒', '500 毫秒', '700 毫秒'],
            currentValue: `${this.settings.longPressDurationMs}`,
            primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText,
            chipBackground: this.theme.chipBackground,
            selectedChipBackground: this.theme.selectedChipBackground,
            accentColor: this.theme.accent,
            onValueChange: (value: string) => this.controller.setLongPressDurationMs(
              Number.parseInt(value)
            ).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          ChoiceSettingRow({
            title: $r('app.string.haptic'), description: '',
            values: [HapticLevel.OFF, HapticLevel.LIGHT, HapticLevel.MEDIUM, HapticLevel.STRONG],
            labels: ['关闭', '轻', '中', '强'], currentValue: this.settings.hapticLevel,
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            chipBackground: this.theme.chipBackground, selectedChipBackground: this.theme.selectedChipBackground,
            accentColor: this.theme.accent,
            onValueChange: (value: string) => this.controller.setHapticLevel(value as HapticLevel).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          SwitchSettingRow({
            title: $r('app.string.key_sound'), description: '',
            checked: this.settings.keySoundEnabled, primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText,
            onCheckedChange: (value: boolean) => this.controller.setKeySoundEnabled(value).then((r) => this.finish(r))
          })
          SliderSettingRow({
            title: '按键音量', description: '默认 16%，实际音量同时受系统媒体音量影响',
            value: this.settings.keySoundVolume, min: 0, max: 100, suffix: '%',
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            accentColor: this.theme.accent,
            onValueChange: (value: number) => this.controller.setKeySoundVolume(value).then((r) => this.finish(r))
          })
        }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)

        this.SectionHeader($r('app.string.data_management'))
        Column({ space: 18 }) {
          ActionSettingRow({
            title: '键盘结构与皮肤', description: '导入并自由组合自定义键盘结构、颜色和皮肤图片',
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            actionColor: this.theme.accent, disabled: this.busy,
            onAction: () => this.openPage('pages/KeyboardCustomization')
          })
          Divider().color(this.theme.divider)
          ActionSettingRow({
            title: '用户词库', description: '添加常用词、隐藏系统词，并设置固顶或指定第 N 位；支持批量操作',
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            actionColor: this.theme.accent, disabled: this.busy,
            onAction: () => this.openPage('pages/UserLexicon')
          })
          if (this.settings.schemeId === XIAOHE_YINXING_SCHEME_ID) {
            Divider().color(this.theme.divider)
            ActionSettingRow({
              title: '码表分类管理', description: '管理小鹤音形码表分类的启用状态',
              primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
              actionColor: this.theme.accent, disabled: this.busy,
              onAction: () => this.openPage('pages/XiaoheYinxingCategoryManagerPage')
            })
          }
          Divider().color(this.theme.divider)
          ActionSettingRow({
            title: $r('app.string.clear_user_model'), description: $r('app.string.clear_user_model_desc'),
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            actionColor: this.theme.danger, disabled: this.busy,
            onAction: () => this.confirmClearUserModel()
          })
        }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)

          }
          .width('100%').padding({ left: 20, right: 20, top: 28, bottom: 36 })
          .alignItems(HorizontalAlign.Start).backgroundColor(this.theme.pageBackground)
        }.width('100%').height('100%').backgroundColor(this.theme.pageBackground)
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.safeArea.top,
        bottom: this.safeArea.bottom,
        left: this.safeArea.left,
        right: this.safeArea.right
      })
    }.width('100%').height('100%').backgroundColor(this.theme.pageBackground)
  }
}
