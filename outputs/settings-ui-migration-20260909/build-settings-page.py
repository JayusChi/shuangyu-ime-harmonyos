from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
old = (Path(__file__).parent / 'SettingsPage.before.ets').read_text(encoding='utf-8')

def component(anchor):
    position = old.index(anchor)
    start = old.rfind('SwitchSettingRow({', 0, position)
    cursor, depth, quote = start + len('SwitchSettingRow'), 0, ''
    while cursor < len(old):
        ch = old[cursor]
        if quote:
            if ch == '\\':
                cursor += 2
                continue
            if ch == quote:
                quote = ''
        elif ch in "'\"`":
            quote = ch
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return old[start:cursor + 1]
        cursor += 1
    raise ValueError(anchor)

switches = {
    'LEARNING': component("title: $r('app.string.user_learning')").replace("title: $r('app.string.user_learning'), description: ''", "title: '学习输入习惯', description: '根据选词习惯优化候选排序'"),
    'ASSOCIATION': component("title: '上屏后本地关联词'").replace("title: '上屏后本地关联词'", "title: '上屏后联想'").replace("纯本地、确定性、最多 3 条；关闭后立即恢复原有候选行为", "在本机推荐相关词，每次最多 3 条"),
    'AI': component("title: 'AI 总开关'").replace("title: 'AI 总开关'", "title: 'AI 辅助输入'").replace("五个生成动作仅在完整体验模式、明确同意且生产代理已配置时可用", "需在完整体验模式下同意使用，且当前版本已开通服务"),
    'SPLIT': component("title: '切分模式'").replace("默认传统；开启后四码空码自动按 2+2 切分，也可输入 oit 切换", "空码时尝试拆分编码生成候选；直通码 oit"),
    'CORRECTION': component("title: '拼写纠错'"),
    'FUZZY': component('title: option.title'),
    'LIFT': component("title: '键盘架高层'").replace("title: '键盘架高层'", "title: '底部工具栏'").replace("底部显示输入法选择、标点、左右移光标和收起键；设备已有系统底栏时可关闭", "原键盘架高层：显示输入法选择、标点、光标移动和收起键"),
    'SOUND': component("title: $r('app.string.key_sound')"),
}
helpers = old[old.index('  private finish('):old.index('  private setCategory(')]
confirm = old[old.index('  private confirmClearUserModel('):old.index('  build()')]
template = '''import { bundleManager } from '@kit.AbilityKit';
import { getSharedSettingsController, SettingsController, SettingsOperationResult } from '../../application/SettingsController';
import {
  CandidatePresentationMode, copyImeSettings, DEFAULT_IME_SETTINGS, HapticLevel, ImeSettings,
  keyboardHeightScale, MIN_CANDIDATE_FONT_SIZE, MAX_CANDIDATE_FONT_SIZE,
  LONG_PRESS_DURATION_OPTIONS_MS, SMART_PERIOD_TIMEOUT_OPTIONS_MS,
  QUANPIN_SCHEME_ID, QuanpinFuzzyOption, ThemeMode, XIAOHE_YINXING_SCHEME_ID
} from '../../domain/settings/ImeSettings';
import { enabledKeyboardProfiles, KeyboardProfile } from '../../domain/keyboard/KeyboardProfile';
import { SMART_PUNCTUATION_OPTIONS, SmartPunctuationOption } from '../../domain/keyboard/SmartPunctuation';
import { InputPresentationPreference } from '../../domain/display/InputPresentationMode';
import { SettingsStateListener } from '../../state/SettingsStore';
import { MultiChoiceSettingRow, SwitchSettingRow } from './SettingsComponents';
import { resolveSettingsTheme, SettingsThemeTokens } from './SettingsTheme';
import { SettingsNavigationRow, SettingsOptionList, SettingsAdjustmentRow, SettingsCandidatePreview } from './SettingsNavigationComponents';
import {
  EMPTY_SETTINGS_SAFE_AREA, getSharedSettingsWindowCoordinator, SettingsSafeAreaInsets,
  SettingsSafeAreaListener, SettingsWindowCoordinator
} from '../../application/SettingsWindowCoordinator';

interface FuzzyOptionView { id: QuanpinFuzzyOption; title: string; }
const FUZZY_OPTION_VIEWS: FuzzyOptionView[] = [
  { id: 'n_l', title: 'n / l' }, { id: 'z_zh', title: 'z / zh' },
  { id: 'c_ch', title: 'c / ch' }, { id: 's_sh', title: 's / sh' },
  { id: 'in_ing', title: 'in / ing' }, { id: 'en_eng', title: 'en / eng' },
  { id: 'an_ang', title: 'an / ang' }, { id: 'ian_iang', title: 'ian / iang' }
];
const AVAILABLE_KEYBOARD_PROFILES: KeyboardProfile[] = enabledKeyboardProfiles();

@Component
export struct SettingsPage {
  private readonly controller: SettingsController = getSharedSettingsController();
  private readonly pageStack: NavPathStack = new NavPathStack();
  @State private settings: ImeSettings = copyImeSettings(DEFAULT_IME_SETTINGS);
  @State private theme: SettingsThemeTokens = resolveSettingsTheme(false);
  @State private busy: boolean = false;
  @State private safeArea: SettingsSafeAreaInsets = EMPTY_SETTINGS_SAFE_AREA;
  @State private wideLayout: boolean = false;
  @State private activeSection: string = '';
  @State private previewFixedSize: number = DEFAULT_IME_SETTINGS.candidateFontSize;
  @State private previewFloatingSize: number = DEFAULT_IME_SETTINGS.floatingCandidateFontSize;
  @State private versionName: string = '';
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
    try {
      this.versionName = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (_) {}
  }

  aboutToDisappear(): void {
    this.controller.unsubscribe(this.onSettingsChanged);
    this.windowCoordinator?.unsubscribeSafeArea(this.onSafeAreaChanged);
    this.windowCoordinator = undefined;
  }

  private refresh(): void {
    this.settings = this.controller.getSettings();
    this.theme = resolveSettingsTheme(this.controller.isDarkMode());
    this.previewFixedSize = this.settings.candidateFontSize;
    this.previewFloatingSize = this.settings.floatingCandidateFontSize;
  }

__HELPERS__
__CONFIRM__
  private openSection(name: string): void {
    this.activeSection = name;
    if (this.wideLayout) this.pageStack.clear();
    this.pageStack.pushPathByName(name, undefined);
  }

  private openDetail(name: string): void { this.pageStack.pushPathByName(name, undefined); }

  private currentProfile(): KeyboardProfile | undefined {
    return AVAILABLE_KEYBOARD_PROFILES.find((profile: KeyboardProfile): boolean =>
      profile.profileId === this.settings.keyboardProfileId);
  }

  // These groups only arrange the existing enabled profiles on screen.
  // Selecting a layout still submits the original profile ID in one operation.
  private profileGroup(): string {
    if (this.settings.schemeId === XIAOHE_YINXING_SCHEME_ID) return 'yinxing';
    if (this.settings.schemeId === 'xiaohe') return 'shuangpin';
    return 'pinyin';
  }

  private profilesFor(group: string): KeyboardProfile[] {
    return AVAILABLE_KEYBOARD_PROFILES.filter((profile: KeyboardProfile): boolean => {
      if (group === 'yinxing') return profile.engineSchemeId === XIAOHE_YINXING_SCHEME_ID;
      if (group === 'shuangpin') return profile.engineSchemeId === 'xiaohe';
      return profile.engineSchemeId === QUANPIN_SCHEME_ID || profile.engineSchemeId === 'pinyin-9';
    });
  }

  private schemeSummary(): string {
    if (this.profileGroup() === 'yinxing') return '小鹤音形';
    if (this.profileGroup() === 'shuangpin') return '小鹤双拼';
    return '拼音';
  }

  private layoutSummary(): string {
    const layout = this.currentProfile()?.layoutKind;
    return layout === 'eighteen-key' ? '18 键' : layout === 't9-9-key' ? '9 键' : '26 键';
  }

  private deviceSummary(): string {
    return this.settings.inputPresentationPreference === InputPresentationPreference.TOUCH ? '虚拟键盘' :
      this.settings.inputPresentationPreference === InputPresentationPreference.HARDWARE ? '实体键盘' : '自动识别';
  }

  private themeSummary(): string {
    return this.settings.themeMode === ThemeMode.DARK ? '深色' :
      this.settings.themeMode === ThemeMode.LIGHT ? '浅色' : '跟随系统';
  }

  private candidateSummary(): string {
    return this.settings.candidatePresentationMode === CandidatePresentationMode.FLOATING ?
      `输入框下方 · ${this.settings.floatingCandidateFontSize} 号` : `固定候选栏 · ${this.settings.candidateFontSize} 号`;
  }

  private hapticSummary(): string {
    switch (this.settings.hapticLevel) {
      case HapticLevel.OFF: return '关闭';
      case HapticLevel.MEDIUM: return '中';
      case HapticLevel.STRONG: return '强';
      default: return '轻';
    }
  }

  private timeoutSummary(): string {
    return this.settings.smartPeriodTimeoutMs === 0 ? '关闭' : `${this.settings.smartPeriodTimeoutMs} 毫秒`;
  }

  private pageTitle(name: string): string {
    switch (name) {
      case 'input': return '输入设置';
      case 'scheme': return '输入方案';
      case 'profiles-yinxing': return '小鹤音形布局';
      case 'profiles-shuangpin': return '双拼布局';
      case 'profiles-pinyin': return '拼音布局';
      case 'device': return '键盘使用方式';
      case 'punctuation': return '智能标点';
      case 'fuzzy': return '模糊音';
      case 'appearance': return '键盘与外观';
      case 'theme': return '主题';
      case 'candidates': return '候选设置';
      case 'candidate-position': return '候选位置';
      case 'feedback': return '按键与反馈';
      case 'haptic': return '按键震动';
      case 'long-press': return '长按时间';
      case 'lexicon': return '词库与个性化';
      case 'ai': return 'AI 辅助输入';
      case 'guide': return '快捷操作指南';
      case 'privacy': return '本地数据说明';
      default: return '帮助与关于';
    }
  }

  @Builder
  private SectionHeader(title: string) {
    Text(title).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.theme.secondaryText)
      .width('100%').padding({ left: 8, top: 6 })
  }

  @Builder
  private Note(text: string) {
    Text(text).fontSize(12).fontColor(this.theme.secondaryText).width('100%')
      .padding({ left: 8, right: 8 })
  }

  @Builder
  private Line() { Divider().color(this.theme.divider).margin({ left: 16, right: 16 }) }

  @Builder
  private Link(title: string, value: string, page: string, description: string = '') {
    SettingsNavigationRow({ title, value, description, theme: this.theme,
      controlId: `settings-open-${page}`, onOpen: () => this.openDetail(page) })
  }

  @Builder
  private HomeItem(title: string, description: string, page: string, marker: string) {
    SettingsNavigationRow({ title, description, marker, theme: this.theme,
      selected: this.wideLayout && this.activeSection === page,
      controlId: `settings-section-${page}`, onOpen: () => this.openSection(page) })
  }

  @Builder
  private Home() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 5 }) {
          Text('双羽输入法').fontSize(14).fontColor(this.theme.secondaryText)
          Text('设置').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.theme.primaryText)
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 8, left: 4 })
        this.SectionHeader('输入体验')
        Column() {
          this.HomeItem('输入设置', this.currentProfile()?.displayName ?? '', 'input', '⌨')
          this.Line()
          this.HomeItem('键盘与外观', `${this.themeSummary()} · 高度 ${keyboardHeightScale(this.settings.keyboardHeightMode).toFixed(2)}×`, 'appearance', '◐')
          this.Line()
          this.HomeItem('候选设置', this.candidateSummary(), 'candidates', '字')
          this.Line()
          this.HomeItem('按键与反馈', `震动${this.hapticSummary()} · 音效${this.settings.keySoundEnabled ? '开' : '关'}`, 'feedback', '♪')
        }.width('100%').borderRadius(18).clip(true)
        this.SectionHeader('词库与数据')
        Column() {
          this.HomeItem('词库与个性化', '学习习惯、我的词库、自定义直通', 'lexicon', '词')
        }.width('100%').borderRadius(18).clip(true)
        this.SectionHeader('更多')
        Column() {
          this.HomeItem('帮助与关于', '快捷操作、数据说明、版本信息', 'about', '?')
        }.width('100%').borderRadius(18).clip(true)
      }.width('100%').padding({ left: 20, right: 20, top: 24, bottom: 28 })
        .alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Auto)
  }

  @Builder
  private InputSettings() {
    Column() {
      this.Link('输入方案', this.schemeSummary(), 'scheme')
      this.Line()
      this.Link('键盘布局', this.layoutSummary(), `profiles-${this.profileGroup()}`)
      this.Line()
      this.Link('键盘使用方式', this.deviceSummary(), 'device')
    }.width('100%').borderRadius(18).clip(true)
    this.SectionHeader('输入辅助')
    Column({ space: 18 }) {
      __ASSOCIATION__
    }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
    Column() {
      this.Link('智能标点', this.timeoutSummary(), 'punctuation', '双击中文标点，替换为单个英文标点')
      this.Line()
      this.Link('AI 辅助输入', this.settings.aiEnabled ? '已开启' : '已关闭', 'ai')
    }.width('100%').borderRadius(18).clip(true)
    if (this.settings.schemeId === XIAOHE_YINXING_SCHEME_ID) {
      this.SectionHeader('小鹤音形选项')
      Column() { __SPLIT__ }
        .width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
    }
    if (this.settings.schemeId === QUANPIN_SCHEME_ID) {
      this.SectionHeader('全拼容错')
      Column() { __CORRECTION__ }
        .width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
      Column() {
        this.Link('模糊音', `已开启 ${this.settings.fuzzyOptions.length} 组`, 'fuzzy', '分别设置易混淆的声母和韵母')
      }.width('100%').borderRadius(18).clip(true)
    }
  }

  @Builder
  private SchemeSettings() {
    Column() {
      this.Link('小鹤音形', this.profileGroup() === 'yinxing' ? '使用中' : '', 'profiles-yinxing', '26 键音形输入')
      this.Line()
      this.Link('小鹤双拼', this.profileGroup() === 'shuangpin' ? '使用中' : '', 'profiles-shuangpin', '18 键、26 键')
      this.Line()
      this.Link('拼音', this.profileGroup() === 'pinyin' ? '使用中' : '', 'profiles-pinyin', '26 键全拼、9 键拼音')
    }.width('100%').borderRadius(18).clip(true)
    this.Note('选择方案后选择键盘布局，即可应用。直通码 ofa 可切换三种 26 键方案。')
  }

  @Builder
  private ProfileSettings(group: string) {
    SettingsOptionList({
      values: this.profilesFor(group).map((item: KeyboardProfile) => item.profileId),
      labels: this.profilesFor(group).map((item: KeyboardProfile) => item.displayName),
      currentValue: this.settings.keyboardProfileId, theme: this.theme,
      onValueChange: (value: string) => this.controller.setKeyboardProfile(value).then((r) => this.finish(r))
    })
    this.Note('仅显示该方案支持的键盘布局。')
  }

  @Builder
  private DeviceSettings() {
    SettingsOptionList({ values: [InputPresentationPreference.AUTO, InputPresentationPreference.TOUCH, InputPresentationPreference.HARDWARE],
      labels: ['自动识别', '虚拟键盘', '实体键盘'],
      currentValue: this.settings.inputPresentationPreference, theme: this.theme,
      onValueChange: (value: string) => this.controller.setInputPresentationPreference(
        value as InputPresentationPreference).then((r) => this.finish(r)) })
    this.Note('自动识别会随实体键盘的连接或断开切换。')
  }

  @Builder
  private PunctuationSettings() {
    SettingsOptionList({ values: SMART_PERIOD_TIMEOUT_OPTIONS_MS.map((value: number): string => `${value}`),
      labels: ['关闭', '300 毫秒', '500 毫秒', '800 毫秒', '1 秒'],
      currentValue: `${this.settings.smartPeriodTimeoutMs}`, theme: this.theme,
      onValueChange: (value: string) => this.controller.setSmartPeriodTimeoutMs(Number.parseInt(value)).then((r) => this.finish(r)) })
    this.Note('在所选时间内双击已勾选的中文标点，替换为单个英文标点；虚拟和实体键盘均生效。默认 300 毫秒。')
    Column() {
      MultiChoiceSettingRow({ title: '生效标点', description: '点击选择需要启用的标点',
        values: SMART_PUNCTUATION_OPTIONS.map((item: SmartPunctuationOption): string => item.symbol),
        labels: SMART_PUNCTUATION_OPTIONS.map((item: SmartPunctuationOption): string => item.label),
        selectedValues: this.settings.smartPunctuationSymbols,
        primaryTextColor: this.theme.primaryText, secondaryTextColor: this.theme.secondaryText,
        chipBackground: this.theme.chipBackground, selectedChipBackground: this.theme.selectedChipBackground,
        accentColor: this.theme.accent,
        onSelectionChange: (symbols: string) => this.controller.setSmartPunctuationSymbols(symbols).then((r) => this.finish(r)) })
    }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
  }

  @Builder
  private FuzzySettings() {
    Column({ space: 16 }) {
      ForEach(FUZZY_OPTION_VIEWS, (option: FuzzyOptionView, index: number) => {
        if (index > 0) { Divider().color(this.theme.divider) }
        __FUZZY__
      }, (option: FuzzyOptionView): string => option.id)
    }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
  }

  @Builder
  private AppearanceSettings() {
    Column() {
      this.Link('主题', this.themeSummary(), 'theme')
      this.Line()
      SettingsNavigationRow({ title: '键盘结构与皮肤', description: '选择、导入或组合自定义键盘外观',
        theme: this.theme, disabled: this.busy, controlId: 'settings-customization',
        onOpen: () => this.openPage('pages/KeyboardCustomization') })
    }.width('100%').borderRadius(18).clip(true)
    this.SectionHeader('键盘尺寸')
    Column({ space: 20 }) {
      SettingsAdjustmentRow({ title: $r('app.string.keyboard_height'), description: '每次调整 0.05 倍；直通码 ojg',
        value: keyboardHeightScale(this.settings.keyboardHeightMode), min: 0.8, max: 1.2, step: 0.05, decimals: 2,
        suffix: '×', theme: this.theme,
        onValueChange: (value: number) => this.controller.setKeyboardHeightScale(value).then((r) => this.finish(r)) })
      Divider().color(this.theme.divider)
      __LIFT__
    }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
  }

  @Builder
  private ThemeSettings() {
    SettingsOptionList({ values: [ThemeMode.FOLLOW_SYSTEM, ThemeMode.LIGHT, ThemeMode.DARK],
      labels: ['跟随系统', '浅色', '深色'], currentValue: this.settings.themeMode, theme: this.theme,
      onValueChange: (value: string) => this.controller.setThemeMode(value as ThemeMode).then((r) => this.finish(r)) })
  }

  @Builder
  private CandidateSettings() {
    SettingsCandidatePreview({ floating: this.settings.candidatePresentationMode === CandidatePresentationMode.FLOATING,
      fontSize: this.settings.candidatePresentationMode === CandidatePresentationMode.FLOATING ?
        this.previewFloatingSize : this.previewFixedSize, theme: this.theme })
    Column() { this.Link('候选位置', this.settings.candidatePresentationMode === CandidatePresentationMode.FLOATING ? '输入框下方' : '固定候选栏', 'candidate-position') }
      .width('100%').borderRadius(18).clip(true)
    Column({ space: 20 }) {
      SettingsAdjustmentRow({ title: '固定候选字号', description: '默认 15 号；直通码 ohz',
        value: this.settings.candidateFontSize, min: MIN_CANDIDATE_FONT_SIZE, max: MAX_CANDIDATE_FONT_SIZE,
        suffix: ' 号', theme: this.theme,
        onPreview: (value: number) => this.previewFixedSize = value,
        onValueChange: (value: number) => this.controller.setCandidateFontSize(value).then((r) => this.finish(r)) })
      Divider().color(this.theme.divider)
      SettingsAdjustmentRow({ title: '浮动候选字号', description: '默认 17 号；直通码 ofz',
        value: this.settings.floatingCandidateFontSize, min: MIN_CANDIDATE_FONT_SIZE, max: MAX_CANDIDATE_FONT_SIZE,
        suffix: ' 号', theme: this.theme,
        onPreview: (value: number) => this.previewFloatingSize = value,
        onValueChange: (value: number) => this.controller.setCandidateFontSize(value, true).then((r) => this.finish(r)) })
    }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
    this.Note('固定与浮动字号分别保存，切换候选位置不会覆盖另一套字号。')
  }

  @Builder
  private CandidatePositionSettings() {
    SettingsOptionList({ values: [CandidatePresentationMode.BAR, CandidatePresentationMode.FLOATING],
      labels: ['固定候选栏', '输入框下方'], descriptions: ['显示在键盘上方', '浮动显示在输入框下方'],
      currentValue: this.settings.candidatePresentationMode === CandidatePresentationMode.FLOATING ?
        CandidatePresentationMode.FLOATING : CandidatePresentationMode.BAR, theme: this.theme,
      onValueChange: (value: string) => this.controller.setCandidatePresentationMode(value as CandidatePresentationMode)
        .then((r) => this.finish(r)) })
    this.Note('选择“输入框下方”时，固定候选栏整行隐藏。直通码 ohx。')
  }

  @Builder
  private FeedbackSettings() {
    Column() {
      this.Link('按键震动', this.hapticSummary(), 'haptic')
      this.Line()
      this.Link('长按时间', `${this.settings.longPressDurationMs} 毫秒`, 'long-press')
    }.width('100%').borderRadius(18).clip(true)
    this.SectionHeader('声音')
    Column({ space: 20 }) {
      __SOUND__
      Divider().color(this.theme.divider)
      SettingsAdjustmentRow({ title: '按键音量', description: '默认 16%，实际音量同时受系统媒体音量影响',
        value: this.settings.keySoundVolume, min: 0, max: 100, suffix: '%', theme: this.theme,
        onValueChange: (value: number) => this.controller.setKeySoundVolume(value).then((r) => this.finish(r)) })
    }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
    Column() { this.Link('手势与实体键盘操作', '', 'guide', '重复、撤销、跳出成对符号与便捷输入') }
      .width('100%').borderRadius(18).clip(true)
  }

  @Builder
  private HapticSettings() {
    SettingsOptionList({ values: [HapticLevel.OFF, HapticLevel.LIGHT, HapticLevel.MEDIUM, HapticLevel.STRONG],
      labels: ['关闭', '轻', '中', '强'], currentValue: this.settings.hapticLevel, theme: this.theme,
      onValueChange: (value: string) => this.controller.setHapticLevel(value as HapticLevel).then((r) => this.finish(r)) })
    this.Note('直通码 ovd 可切换震动开关。')
  }

  @Builder
  private LongPressSettings() {
    SettingsOptionList({ values: LONG_PRESS_DURATION_OPTIONS_MS.map((value: number): string => `${value}`),
      labels: ['200 毫秒', '300 毫秒', '500 毫秒', '700 毫秒'],
      currentValue: `${this.settings.longPressDurationMs}`, theme: this.theme,
      onValueChange: (value: string) => this.controller.setLongPressDurationMs(Number.parseInt(value)).then((r) => this.finish(r)) })
    this.Note('控制长按符号、输入法切换和连续删除的触发速度。')
  }

  @Builder
  private LexiconSettings() {
    this.SectionHeader('个性化学习')
    Column() { __LEARNING__ }
      .width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
    Column() {
      SettingsNavigationRow({ title: '清除学习记录', description: '重新开始学习选词习惯', theme: this.theme,
        disabled: this.busy, controlId: 'settings-clear-learning', onOpen: () => this.confirmClearUserModel() })
    }.width('100%').borderRadius(18).clip(true)
    this.Note('学习记录保存在本机。关闭学习不会删除已有记录。')
    this.SectionHeader('我的内容')
    Column() {
      SettingsNavigationRow({ title: '我的词库', description: '常用词、候选排序、导入导出与固定位置词库', theme: this.theme,
        disabled: this.busy, controlId: 'settings-user-lexicon', onOpen: () => this.openPage('pages/UserLexicon') })
      this.Line()
      SettingsNavigationRow({ title: '自定义直通', description: '快捷文字、打开网页或目录', theme: this.theme,
        disabled: this.busy, controlId: 'settings-user-shortcuts', onOpen: () => this.openPage('pages/UserShortcuts') })
    }.width('100%').borderRadius(18).clip(true)
    if (this.settings.schemeId === XIAOHE_YINXING_SCHEME_ID) {
      this.SectionHeader('内置词库')
      Column() {
        SettingsNavigationRow({ title: '小鹤音形词库分类', description: '快符、简码次选、符号与生僻字等', theme: this.theme,
          disabled: this.busy, controlId: 'settings-category-manager',
          onOpen: () => this.openPage('pages/XiaoheYinxingCategoryManagerPage') })
      }.width('100%').borderRadius(18).clip(true)
    }
  }

  @Builder
  private AiSettings() {
    Column() { __AI__ }
      .width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
    this.Note('当前版本尚未开通云端 AI 服务，云端功能保持关闭。')
    this.Note('不上传输入框全文、选区、剪贴板、应用标识、用户词库或按键序列；日志不记录正文。')
  }

  @Builder
  private AboutSettings() {
    Column() {
      this.Link('快捷操作指南', '', 'guide', '直通码、上滑手势、实体键盘')
      this.Line()
      this.Link('本地数据说明', '', 'privacy', '学习记录与手动添加的词库')
    }.width('100%').borderRadius(18).clip(true)
    Text(`双羽输入法${this.versionName.length > 0 ? ' · ' + this.versionName : ''}`)
      .fontSize(13).fontColor(this.theme.secondaryText).width('100%').textAlign(TextAlign.Center)
      .padding({ top: 20 })
  }

  @Builder
  private GuideCard(title: string, text: string) {
    Column({ space: 10 }) {
      Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.primaryText).width('100%')
      Text(text).fontSize(14).fontColor(this.theme.secondaryText).width('100%')
    }.width('100%').padding(18).borderRadius(18).backgroundColor(this.theme.cardBackground)
  }

  @Builder
  private GuideSettings() {
    this.GuideCard('常用直通码', 'ofa：三种 26 键输入方案\\nohx：候选位置\\nojg：键盘高度\\nohz / ofz：固定 / 浮动候选字号\\novd / oyx：震动 / 音效开关\\noit：音形切分模式')
    this.GuideCard('上滑手势', '上滑回车：重复上屏；有候选时先上屏，再重复。\\n上滑回删：撤销上屏；有候选时先上屏，再撤销。')
    this.GuideCard('便捷输入', '数字键盘以 = 引导，实体键盘以单引号引导。可输入金额、年月、日期、算式和临时英文。\\n例如：=1234.5、=2026.5.5、=123+5*6。')
    this.GuideCard('实体键盘与成对符号', '快符以分号引导。分号 n 模拟 End；Tab 和回车可用于跳出成对符号。')
    this.GuideCard('自定义直通', '进入“词库与个性化 → 自定义直通”，选择上屏文字、打开网页或打开目录，填写编码后保存并立即应用。目录请使用系统目录选择器。')
  }

  @Builder
  private PrivacySettings() {
    this.GuideCard('学习记录', '记录选词习惯，用于优化候选排序。可在“词库与个性化”中关闭学习或清除已有学习记录。')
    this.GuideCard('我的词库与直通', '手动添加的常用词、候选排序规则和网页／目录直通在词库管理页面维护，支持导入和导出。')
  }

  @Builder
  private Destination(name: string) {
    NavDestination() {
      Column() {
        Row({ space: 8 }) {
          Button('‹', { type: ButtonType.Normal }).fontSize(32).fontColor(this.theme.accent)
            .width(44).height(44).borderRadius(14).backgroundColor(this.theme.pageBackground)
            .id('settings-back').accessibilityText('返回').onClick(() => this.pageStack.pop())
          Text(this.pageTitle(name)).fontSize(21).fontWeight(FontWeight.Bold)
            .fontColor(this.theme.primaryText).layoutWeight(1)
        }.width('100%').padding({ left: 12, right: 20, top: 8, bottom: 8 })
        Scroll() {
          Column({ space: 16 }) {
            if (name === 'input') { this.InputSettings() }
            else if (name === 'scheme') { this.SchemeSettings() }
            else if (name.startsWith('profiles-')) { this.ProfileSettings(name.substring(9)) }
            else if (name === 'device') { this.DeviceSettings() }
            else if (name === 'punctuation') { this.PunctuationSettings() }
            else if (name === 'fuzzy') { this.FuzzySettings() }
            else if (name === 'appearance') { this.AppearanceSettings() }
            else if (name === 'theme') { this.ThemeSettings() }
            else if (name === 'candidates') { this.CandidateSettings() }
            else if (name === 'candidate-position') { this.CandidatePositionSettings() }
            else if (name === 'feedback') { this.FeedbackSettings() }
            else if (name === 'haptic') { this.HapticSettings() }
            else if (name === 'long-press') { this.LongPressSettings() }
            else if (name === 'lexicon') { this.LexiconSettings() }
            else if (name === 'ai') { this.AiSettings() }
            else if (name === 'guide') { this.GuideSettings() }
            else if (name === 'privacy') { this.PrivacySettings() }
            else { this.AboutSettings() }
          }.width('100%').constraintSize({ maxWidth: 720 })
            .padding({ left: 20, right: 20, top: 8, bottom: 32 })
            .alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      }.width('100%').height('100%').backgroundColor(this.theme.pageBackground)
    }.hideTitleBar(true).backgroundColor(this.theme.pageBackground)
  }

  build() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor(this.theme.pageBackground)
        .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
      Navigation(this.pageStack) { this.Home() }
        .navDestination(this.Destination).hideTitleBar(true).navBarWidth(310)
        .mode(this.wideLayout ? NavigationMode.Split : NavigationMode.Stack)
        .backgroundColor(this.theme.pageBackground).width('100%').height('100%')
        .padding({ top: this.safeArea.top, bottom: this.safeArea.bottom,
          left: this.safeArea.left, right: this.safeArea.right })
        .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
          this.wideLayout = Number(size.width) >= 840;
          if (this.wideLayout && this.pageStack.size() === 0) {
            this.activeSection = 'input';
            this.pageStack.pushPathByName('input', undefined, false);
          }
        })
    }.width('100%').height('100%').backgroundColor(this.theme.pageBackground)
  }
}
'''
template = template.replace('__HELPERS__', helpers).replace('__CONFIRM__', confirm)
for key, content in switches.items():
    template = template.replace(f'__{key}__', content)
assert not re.search(r'__[A-Z]+__', template)
target = root / 'entry/src/main/ets/presentation/settings/SettingsPage.ets'
target.with_suffix('.ets.ui-next').write_text(template, encoding='utf-8')
print('Generated settings page; migrated', len(switches), 'switch callback blocks verbatim except labels.')
