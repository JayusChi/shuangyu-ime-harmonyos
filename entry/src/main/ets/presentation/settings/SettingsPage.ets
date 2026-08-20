import { promptAction, router } from '@kit.ArkUI';
import { getSharedSettingsController, SettingsController, SettingsOperationResult } from '../../application/SettingsController';
import {
  CandidateFontSizeMode,
  CandidatePresentationMode,
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  HapticLevel,
  ImeSettings,
  KeyboardHeightMode,
  MAX_XIAOHE_YINXING_HINT_CANDIDATE_COUNT,
  MIN_XIAOHE_YINXING_HINT_CANDIDATE_COUNT,
  QUANPIN_SCHEME_ID,
  QuanpinFuzzyOption,
  ThemeMode,
  XIAOHE_YINXING_SCHEME_ID
} from '../../domain/settings/ImeSettings';
import { enabledKeyboardProfiles, KeyboardProfile } from '../../domain/keyboard/KeyboardProfile';
import { SettingsStateListener } from '../../state/SettingsStore';
import { ActionSettingRow, ChoiceSettingRow, NumberSettingRow, SwitchSettingRow } from './SettingsComponents';
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
    promptAction.showToast({ message: result.success ? $r('app.string.settings_saved') : result.message });
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
    AlertDialog.show({
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
            description: '',
            values: [
              InputPresentationPreference.TOUCH,
              InputPresentationPreference.HARDWARE
            ],
            labels: ['虚拟键盘', '实体键盘'],
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
          NumberSettingRow({
            title: $r('app.string.yinxing_hint_candidate_count'),
            description: $r('app.string.yinxing_hint_candidate_count_desc'),
            value: this.settings.xiaoheYinxingHintCandidateCount,
            minValue: MIN_XIAOHE_YINXING_HINT_CANDIDATE_COUNT,
            maxValue: MAX_XIAOHE_YINXING_HINT_CANDIDATE_COUNT,
            primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText,
            chipBackground: this.theme.chipBackground,
            accentColor: this.theme.accent,
            onValueChange: (value: number) => this.controller.setXiaoheYinxingHintCandidateCount(
              value
            ).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          SwitchSettingRow({
            title: $r('app.string.user_learning'), description: '',
            checked: this.settings.userLearningEnabled, primaryTextColor: this.theme.primaryText,
            secondaryTextColor: this.theme.secondaryText,
            onCheckedChange: (value: boolean) => this.controller.setUserLearningEnabled(value).then((r) => this.finish(r))
          })
        }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)

        if (this.settings.schemeId === XIAOHE_YINXING_SCHEME_ID) {
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
          ChoiceSettingRow({
            title: $r('app.string.keyboard_height'), description: '',
            values: [KeyboardHeightMode.COMPACT, KeyboardHeightMode.STANDARD, KeyboardHeightMode.TALL],
            labels: ['紧凑', '标准', '较高'], currentValue: this.settings.keyboardHeightMode,
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            chipBackground: this.theme.chipBackground, selectedChipBackground: this.theme.selectedChipBackground,
            accentColor: this.theme.accent,
            onValueChange: (value: string) => this.controller.setKeyboardHeightMode(value as KeyboardHeightMode).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          ChoiceSettingRow({
            title: $r('app.string.candidate_font'), description: '',
            values: [CandidateFontSizeMode.SMALL, CandidateFontSizeMode.STANDARD, CandidateFontSizeMode.LARGE],
            labels: ['小', '标准', '大'], currentValue: this.settings.candidateFontSizeMode,
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            chipBackground: this.theme.chipBackground, selectedChipBackground: this.theme.selectedChipBackground,
            accentColor: this.theme.accent,
            onValueChange: (value: string) => this.controller.setCandidateFontSizeMode(value as CandidateFontSizeMode).then((r) => this.finish(r))
          })
          Divider().color(this.theme.divider)
          ChoiceSettingRow({
            title: $r('app.string.candidate_presentation'),
            description: '',
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
        }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)

        this.SectionHeader($r('app.string.data_management'))
        Column({ space: 18 }) {
          ActionSettingRow({
            title: '用户词库', description: '添加常用词、隐藏系统词，并设置固顶或指定第 N 位；支持批量操作',
            primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
            actionColor: this.theme.accent, disabled: this.busy,
            onAction: () => router.pushUrl({ url: 'pages/UserLexicon' })
          })
          if (this.settings.schemeId === XIAOHE_YINXING_SCHEME_ID) {
            Divider().color(this.theme.divider)
            ActionSettingRow({
              title: '码表分类管理', description: '管理小鹤音形码表分类的启用状态',
              primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
              actionColor: this.theme.accent, disabled: this.busy,
              onAction: () => router.pushUrl({ url: 'pages/XiaoheYinxingCategoryManagerPage' })
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
