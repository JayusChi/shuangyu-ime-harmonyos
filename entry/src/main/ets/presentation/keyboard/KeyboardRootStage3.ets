import { KeyboardController } from '../../application/KeyboardController';
import { DeleteRepeatController } from '../../application/DeleteRepeatController';
import { DELETE_ACTION, KeyboardAction, KeyboardMode } from '../../domain/keyboard/KeyboardAction';
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import {
  createUnknownEditorContext,
  EditorContext,
  ShiftState
} from '../../domain/editor/EditorContext';
import {
  CandidateFontSizeMode,
  CandidatePresentationMode,
  KeyboardHeightMode,
  DEFAULT_SCHEME_ID
} from '../../domain/settings/ImeSettings';
import {
  allowsCandidateBrowsing,
  CandidateUiMode,
  resolveCandidateUiMode,
  resolveVisibleCandidates
} from '../../domain/candidate/CandidateUiPolicy';
import { getSharedSettingsStore, SettingsStore } from '../../state/SettingsStore';
import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import {
  KeyboardKeySpec,
  KeyboardKeyKind,
  KeyboardRowKind,
  KeyboardRowSpec
} from './model/KeyboardLayoutSpec';
import { createStage10KeyboardLayout } from './layouts/Stage10KeyboardLayouts';
import { BaseKey } from './components/BaseKey';
import { LetterKey } from './components/LetterKey';
import { DeleteKey } from './components/DeleteKey';
import { InputMethodSwitchKey } from './components/InputMethodSwitchKey';
import { SegmentedKey } from './components/SegmentedKey';
import {
  DEFAULT_SHUANGPIN_KEYBOARD_LAYOUT,
  ShuangpinKeyboardLayout
} from '../../domain/keyboard/ShuangpinKeyboardLayout';
import {
  getSharedKeyboardLayoutPreferenceController,
  KeyboardLayoutPreferenceController
} from '../../application/KeyboardLayoutPreferenceController';
import { getSharedSettingsController, SettingsController } from '../../application/SettingsController';
import {
  DEFAULT_KEYBOARD_PROFILE_ID,
  enabledKeyboardProfiles,
  findKeyboardProfile,
  KeyboardProfile,
  PINYIN_9_PROFILE_ID
} from '../../domain/keyboard/KeyboardProfile';
import { CandidateBar, CandidateBarState } from '../candidate/CandidateBar';
import { PinyinCombinationBar } from '../candidate/PinyinCombinationBar';
import { CandidateExpansionPanel } from '../candidate/CandidateExpansionPanel';
import {
  PORTRAIT_METRICS,
  OrientationMetrics,
  getMetricsForOrientation
} from './design/KeyboardMetrics';
import {
  copyScreenMetrics,
  SAFE_FALLBACK_SCREEN_METRICS_PX,
  ScreenMetricsPx,
  screenMetricsEqual
} from '../../domain/display/ScreenMetrics';
import {
  LIGHT_PALETTE,
  KeyboardColorPalette
} from './design/KeyboardPalette';
import { KeyboardThemeResolver } from './design/KeyboardThemeResolver';
import {
  KeyboardDeviceFormFactor,
  KeyboardAuxiliaryAreaPolicy,
  resolveKeyboardAuxiliaryAreaPolicy
} from '../../domain/display/KeyboardAuxiliaryAreaPolicy';
import {
  CandidateExpansionLayout,
  resolveCandidateExpansionLayout
} from '../../domain/candidate/CandidateExpansionPolicy';

const SELECTABLE_KEYBOARD_PROFILES: KeyboardProfile[] = enabledKeyboardProfiles();

@Entry
@Component
struct KeyboardRoot {
  private readonly controller: KeyboardController = new KeyboardController();
  private readonly deleteRepeatController: DeleteRepeatController =
    new DeleteRepeatController((): void => {
      this.handleDeleteAction();
    });
  private readonly settingsStore: SettingsStore = getSharedSettingsStore();
  private readonly themeResolver: KeyboardThemeResolver = new KeyboardThemeResolver();
  private readonly layoutPreference: KeyboardLayoutPreferenceController =
    getSharedKeyboardLayoutPreferenceController();
  private readonly settingsController: SettingsController = getSharedSettingsController();

  @State private keyboardMode: KeyboardMode = KeyboardMode.ENGLISH;
  @State private editorContext: EditorContext = createUnknownEditorContext();
  @State private shiftState: ShiftState = ShiftState.LOWERCASE;
  @State private chineseCapsLock: boolean = false;
  @State private candidateBarVisible: boolean = false;
  @State private floatingCandidateVisible: boolean = false;
  @State private lastErrorMessage: string = 'success';
  @State private preeditText: string = '';
  @State private rawInput: string = '';
  @State private displaySegments: string[] = [];
  @State private pendingCode: string = '';
  @State private segmentBoundaries: number[] = [];
  @State private currentPinyin: string = '';
  @State private pinyinCombinations: string[] = [];
  @State private keyboardLayoutRawInput: string = '';
  @State private parserState: string = 'empty';
  @State private candidates: Candidate[] = [];
  @State private highlightedIndex: number = -1;
  @State private candidateBarState: CandidateBarState = CandidateBarState.IDLE;
  @State private candidatePanelExpanded: boolean = false;
  @State private candidatePageLoading: boolean = false;
  @State private candidatePage: number = 0;
  @State private hasNextPage: boolean = false;
  @State private hasPreviousPage: boolean = false;
  @State private keyboardHeightMode: KeyboardHeightMode = KeyboardHeightMode.STANDARD;
  @State private candidateFontSize: number = 14;
  @State private candidateUiMode: CandidateUiMode = resolveCandidateUiMode(DEFAULT_SCHEME_ID);
  @State private yinxingHintCandidateCount: number = 9;
  @State private inputMethodSwitchAvailable: boolean = false;
  @State private inputMethodPickerAvailable: boolean = false;
  @State private shuangpinLayout: ShuangpinKeyboardLayout = DEFAULT_SHUANGPIN_KEYBOARD_LAYOUT;
  @State private keyboardProfileId: string = DEFAULT_KEYBOARD_PROFILE_ID;
  @State private layoutSelectorVisible: boolean = false;
  @State private auxiliaryPolicy: KeyboardAuxiliaryAreaPolicy =
    resolveKeyboardAuxiliaryAreaPolicy(SAFE_FALLBACK_SCREEN_METRICS_PX);
  @State private candidatePresentationMode: CandidatePresentationMode = CandidatePresentationMode.BAR;

  @State private metrics: OrientationMetrics = PORTRAIT_METRICS;
  private screenMetrics: ScreenMetricsPx = copyScreenMetrics(SAFE_FALLBACK_SCREEN_METRICS_PX);
  // Replacing this single reactive object makes the whole keyboard render from one palette snapshot.
  @State private palette: KeyboardColorPalette = LIGHT_PALETTE;
  private readonly onSessionStateChanged = (): void => {
    this.refreshState();
  };
  private readonly onSettingsChanged = (): void => {
    this.refreshSettings();
  };
  private readonly onKeyboardLayoutChanged = (layout: ShuangpinKeyboardLayout): void => {
    this.shuangpinLayout = layout;
  };

  aboutToAppear(): void {
    this.controller.subscribe(this.onSessionStateChanged);
    this.settingsStore.subscribe(this.onSettingsChanged);
    this.layoutPreference.subscribe(this.onKeyboardLayoutChanged);
    this.shuangpinLayout = this.layoutPreference.getLayout();
    this.refreshState();
    this.refreshInputMethodSwitchCapabilities();
    this.refreshSettings();
  }

  aboutToDisappear(): void {
    this.deleteRepeatController.destroy();
    this.controller.unsubscribe(this.onSessionStateChanged);
    this.settingsStore.unsubscribe(this.onSettingsChanged);
    this.layoutPreference.unsubscribe(this.onKeyboardLayoutChanged);
    this.controller.dispose();
  }

  private refreshState(): void {
    const state = this.controller.getState();
    this.keyboardMode = state.keyboardMode;
    this.editorContext = state.editorContext;
    this.shiftState = state.shiftState;
    this.chineseCapsLock = state.chineseCapsLock;
    this.candidateBarVisible = state.candidateBarVisible;
    this.floatingCandidateVisible = state.floatingCandidateVisible;
    this.lastErrorMessage = state.lastErrorMessage;
    this.preeditText = state.preeditText;
    this.rawInput = state.rawInput;
    this.displaySegments = state.displaySegments;
    this.pendingCode = state.pendingCode;
    this.segmentBoundaries = state.segmentBoundaries;
    this.currentPinyin = state.currentPinyin;
    this.pinyinCombinations = state.pinyinCombinations;
    if (!this.deleteRepeatController.isActivated()) {
      this.keyboardLayoutRawInput = state.rawInput;
    }
    this.parserState = state.parserState;
    this.candidates = state.candidates;
    this.highlightedIndex = state.highlightedIndex;
    this.candidatePanelExpanded = state.candidatePanelExpanded;
    this.candidatePageLoading = state.candidatePageLoading;
    this.candidatePage = state.candidatePage;
    this.hasNextPage = state.hasNextPage;
    this.hasPreviousPage = state.hasPreviousPage;
    if (!screenMetricsEqual(this.screenMetrics, state.screenMetrics)) {
      this.screenMetrics = copyScreenMetrics(state.screenMetrics);
      this.updateMetrics();
    }
    if (state.lastErrorMessage !== 'success') {
      this.candidateBarState = CandidateBarState.ERROR;
    } else if (state.preeditText.length > 0 || state.candidates.length > 0) {
      this.candidateBarState = CandidateBarState.CANDIDATES;
    } else {
      this.candidateBarState = CandidateBarState.IDLE;
    }
    if (this.candidateBarState !== CandidateBarState.IDLE) {
      this.layoutSelectorVisible = false;
    }
  }

  private updateMetrics(): void {
    this.metrics = getMetricsForOrientation(
      this.screenMetrics.isLandscape,
      this.keyboardHeightMode,
      this.screenMetrics
    );
    this.auxiliaryPolicy = resolveKeyboardAuxiliaryAreaPolicy(
      this.screenMetrics
    );
  }

  private refreshInputMethodSwitchCapabilities(): void {
    const capabilities = this.controller.getInputMethodSwitchCapabilities();
    this.inputMethodPickerAvailable = capabilities.canShowSystemPicker;
    this.inputMethodSwitchAvailable = capabilities.canSwitchToNext || capabilities.canShowSystemPicker;
  }

  private updatePalette(): void {
    this.palette = this.themeResolver.resolve(this.settingsStore.getEffectiveTheme());
  }

  private refreshSettings(): void {
    const settings = this.settingsStore.getSnapshot();
    this.keyboardProfileId = settings.keyboardProfileId;
    this.keyboardHeightMode = settings.keyboardHeightMode;
    this.candidateFontSize = this.resolveCandidateFontSize(settings.candidateFontSizeMode);
    this.candidateUiMode = resolveCandidateUiMode(settings.schemeId);
    this.yinxingHintCandidateCount = settings.xiaoheYinxingHintCandidateCount;
    if (!allowsCandidateBrowsing(this.candidateUiMode) && this.candidatePanelExpanded) {
      this.controller.setCandidatePanelExpanded(false);
      this.candidatePanelExpanded = false;
    }
    this.candidatePresentationMode = settings.candidatePresentationMode;
    this.updateMetrics();
    this.updatePalette();
  }

  private resolveCandidateFontSize(mode: CandidateFontSizeMode): number {
    if (mode === CandidateFontSizeMode.SMALL) {
      return 12;
    }
    if (mode === CandidateFontSizeMode.LARGE) {
      return 17;
    }
    return 14;
  }

  private visibleCandidates(): Candidate[] {
    return resolveVisibleCandidates(
      this.candidateUiMode,
      this.rawInput,
      this.candidates,
      this.yinxingHintCandidateCount
    );
  }

  private isCandidatePanelActive(): boolean {
    return allowsCandidateBrowsing(this.candidateUiMode) && this.candidatePanelExpanded;
  }

  private async dispatchAction(action: KeyboardAction): Promise<void> {
    await this.controller.handleAction(action);
    this.refreshState();
  }

  private async commitCandidate(index: number): Promise<void> {
    await this.controller.commitCandidate(index);
    this.refreshState();
  }

  private async selectPinyinCombination(index: number): Promise<void> {
    await this.controller.selectPinyinCombination(index);
    this.refreshState();
  }

  private isPinyin9Chinese(): boolean {
    return this.keyboardProfileId === PINYIN_9_PROFILE_ID && this.keyboardMode === KeyboardMode.CHINESE;
  }

  private shouldShowPinyinCombinationBar(): boolean {
    return this.isPinyin9Chinese() && this.rawInput.length > 0 &&
      this.currentPinyin.length > 0 && this.pinyinCombinations.length > 0;
  }

  private toggleCandidatePanel(expanded: boolean): void {
    if (expanded && !allowsCandidateBrowsing(this.candidateUiMode)) {
      return;
    }
    this.controller.setCandidatePanelExpanded(expanded);
    this.refreshState();
  }

  private async navigateCandidatePage(next: boolean): Promise<void> {
    if (this.candidatePageLoading) {
      return;
    }
    if (next) {
      await this.controller.nextCandidatePage();
    } else {
      await this.controller.previousCandidatePage();
    }
    this.refreshState();
  }

  private candidateExpansionLayout(): CandidateExpansionLayout {
    return resolveCandidateExpansionLayout(
      this.auxiliaryPolicy.formFactor,
      this.screenMetrics.isLandscape
    );
  }

  private isTabletLayout(): boolean {
    return this.auxiliaryPolicy.formFactor === KeyboardDeviceFormFactor.TABLET;
  }

  private async handleDeleteAction(): Promise<void> {
    await this.dispatchAction(DELETE_ACTION);
  }

  private toggleLayoutSelector(): void {
    if (this.candidateBarState === CandidateBarState.IDLE) {
      this.layoutSelectorVisible = !this.layoutSelectorVisible;
    }
  }

  private async selectKeyboardLayout(layout: ShuangpinKeyboardLayout): Promise<void> {
    this.layoutSelectorVisible = false;
    await this.layoutPreference.select(layout);
    this.shuangpinLayout = this.layoutPreference.getLayout();
  }

  private async selectKeyboardProfile(profileId: string): Promise<void> {
    this.layoutSelectorVisible = false;
    const result = await this.settingsController.setKeyboardProfile(profileId);
    if (!result.success) {
      this.lastErrorMessage = result.message;
      this.candidateBarState = CandidateBarState.ERROR;
      return;
    }
    this.refreshSettings();
    this.shuangpinLayout = this.layoutPreference.getLayout();
  }

  private keyboardProfileName(): string {
    return findKeyboardProfile(this.keyboardProfileId)?.displayName ?? '26 键双拼';
  }

  private async openSettings(): Promise<void> {
    try {
      const hostContext = this.getUIContext().getHostContext();
      if (!hostContext) {
        throw new Error('input method host context unavailable');
      }
      const context = hostContext as InputMethodExtensionContext;
      await context.startAbility({
        bundleName: 'com.corrosion.shuangyuime',
        abilityName: 'EntryAbility'
      });
    } catch (_err) {
      this.lastErrorMessage = '打开设置失败';
      this.candidateBarState = CandidateBarState.ERROR;
    }
  }

  private handleDeletePress(): void {
    this.deleteRepeatController.start();
  }

  private handleDeleteRelease(): void {
    this.deleteRepeatController.stop();
    this.keyboardLayoutRawInput = this.rawInput;
  }

  private handleDeleteClick(): void {
    this.deleteRepeatController.triggerSingleDelete();
  }

  /**
   * 渲染单个按键
   */
  @Builder
  private renderKey(spec: KeyboardKeySpec) {
    if (spec.kind === KeyboardKeyKind.DELETE) {
      DeleteKey({
        spec: spec,
        palette: this.palette,
        metrics: this.metrics,
        keyboardMode: this.keyboardMode,
        shiftState: this.shiftState,
        onDeletePress: () => this.handleDeletePress(),
        onDeleteRelease: () => this.handleDeleteRelease(),
        onDeleteClick: () => this.handleDeleteClick()
      })
    } else if (spec.kind === KeyboardKeyKind.INPUT_METHOD_SWITCH) {
      InputMethodSwitchKey({
        spec: spec,
        palette: this.palette,
        metrics: this.metrics,
        longPressEnabled: this.inputMethodPickerAvailable,
        onAction: (action: KeyboardAction) => this.dispatchAction(action)
      })
    } else if (spec.alternatives && spec.alternatives.length > 0) {
      SegmentedKey({
        spec: spec,
        palette: this.palette,
        metrics: this.metrics,
        keyboardMode: this.keyboardMode,
        shiftState: this.shiftState,
        onAction: (action: KeyboardAction) => this.dispatchAction(action)
      })
    } else if (spec.previewEnabled) {
      LetterKey({
        spec: spec,
        palette: this.palette,
        metrics: this.metrics,
        keyboardMode: this.keyboardMode,
        shiftState: this.shiftState,
        onKeyClick: (s: KeyboardKeySpec) => this.dispatchAction(s.action)
      })
    } else {
      BaseKey({
        spec: spec,
        palette: this.palette,
        metrics: this.metrics,
        keyboardMode: this.keyboardMode,
        shiftState: this.shiftState,
        longPressEnabled: this.inputMethodPickerAvailable,
        onKeyClick: (s: KeyboardKeySpec) => this.dispatchAction(s.action),
        onLongPressAction: (action: KeyboardAction) => this.dispatchAction(action)
      })
    }
  }

  /**
   * 渲染键盘行
   */
  @Builder
  private KeyboardRow(row: KeyboardRowSpec) {
    Row({ space: this.metrics.keySpacing }) {
      ForEach(row.keys, (spec: KeyboardKeySpec) => {
        this.renderKey(spec)
      }, (spec: KeyboardKeySpec) => spec.id)
    }
    .width('100%')
    .padding({
      left: row.kind === KeyboardRowKind.MIDDLE_LETTERS ? this.metrics.secondRowInset : 0,
      right: row.kind === KeyboardRowKind.MIDDLE_LETTERS ? this.metrics.secondRowInset : 0
    })
    // 行高由 layoutWeight 均分面板可用高度，避免固定行高与面板高度不匹配时溢出/拉伸。
    .layoutWeight(1)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
    Column({ space: this.metrics.rowSpacing }) {
      // 3.2：顶部栏始终存在；只有左侧候选内容遵循候选可见性策略。
      CandidateBar({
        palette: this.palette,
        state: this.candidateBarState,
        rawInput: this.rawInput,
        preeditText: this.preeditText,
        preferredPreeditText: this.isPinyin9Chinese() ? this.currentPinyin : '',
        displaySegments: this.displaySegments,
        pendingCode: this.pendingCode,
        segmentBoundaries: this.segmentBoundaries,
        parserState: this.parserState,
        candidates: this.visibleCandidates(),
        highlightedIndex: this.highlightedIndex,
        barHeight: this.metrics.candidateBarHeight,
        actionWidth: this.metrics.statusBarActionWidth,
        contentVisible: this.candidateBarVisible && !this.isCandidatePanelActive() &&
          !this.floatingCandidateVisible &&
          this.candidatePresentationMode !== CandidatePresentationMode.FLOATING,
        expanded: this.isCandidatePanelActive(),
        pageLoading: this.candidatePageLoading,
        candidateUiMode: this.candidateUiMode,
        keyboardLayout: this.shuangpinLayout,
        keyboardProfileName: this.keyboardProfileName(),
        inputMethodPickerAvailable: this.inputMethodPickerAvailable,
        errorMessage: this.lastErrorMessage,
        candidateFontSize: this.candidateFontSize,
        onCandidateClick: (candidate: Candidate, index: number) => this.commitCandidate(index),
        onToggleExpanded: (expanded: boolean) => this.toggleCandidatePanel(expanded),
        onAction: (action: KeyboardAction) => this.dispatchAction(action),
        onOpenKeyboardLayoutSelector: () => this.toggleLayoutSelector(),
        onOpenSettings: () => this.openSettings()
      })

      if (this.shouldShowPinyinCombinationBar() && !this.isCandidatePanelActive()) {
        PinyinCombinationBar({
          palette: this.palette,
          currentPinyin: this.currentPinyin,
          pinyinCombinations: this.pinyinCombinations,
          barHeight: this.metrics.pinyinCombinationBarHeight,
          onCombinationClick: (combinationIndex: number) => this.selectPinyinCombination(combinationIndex)
        })
      }

      if (this.isCandidatePanelActive() && this.candidates.length > 0) {
        if (!this.isTabletLayout()) {
          CandidateExpansionPanel({
            palette: this.palette,
            candidates: this.candidates,
            candidatePage: this.candidatePage,
            hasPreviousPage: this.hasPreviousPage,
            hasNextPage: this.hasNextPage,
            pageLoading: this.candidatePageLoading,
            candidateFontSize: this.candidateFontSize,
            highlightedIndex: this.highlightedIndex,
            layout: this.candidateExpansionLayout(),
            fillAvailableHeight: true,
            onCandidateClick: (candidate: Candidate, index: number) => this.commitCandidate(index),
            onPreviousPage: () => this.navigateCandidatePage(false),
            onNextPage: () => this.navigateCandidatePage(true)
          })
        }
      }

      if (!this.isCandidatePanelActive() || this.isTabletLayout()) {
        Row({ space: this.metrics.keySpacing }) {
          Column({ space: this.metrics.rowSpacing }) {
            ForEach(createStage10KeyboardLayout(
              this.keyboardMode,
              this.editorContext,
              this.shiftState,
              this.rawInput,
              this.chineseCapsLock,
              false,
              this.shuangpinLayout,
              this.keyboardProfileId
            ).rows, (row: KeyboardRowSpec, index: number) => {
              this.KeyboardRow(row)
            }, (row: KeyboardRowSpec, index: number) =>
              `${this.editorContext.kind}-${this.keyboardMode}-${this.shiftState}-${this.keyboardLayoutRawInput}-` +
                `${this.chineseCapsLock}-` +
                `${this.shuangpinLayout}-` +
                `${this.keyboardProfileId}-` +
                `${this.editorContext.numberDecimalAllowed}-${this.editorContext.enterAction}-row-${index}`)
          }
          .layoutWeight(1)
          .height('100%')

          if (this.isCandidatePanelActive() && this.isTabletLayout()) {
            CandidateExpansionPanel({
              palette: this.palette,
              candidates: this.candidates,
              candidatePage: this.candidatePage,
              hasPreviousPage: this.hasPreviousPage,
              hasNextPage: this.hasNextPage,
              pageLoading: this.candidatePageLoading,
              candidateFontSize: this.candidateFontSize,
              highlightedIndex: this.highlightedIndex,
              layout: this.candidateExpansionLayout(),
              panelWidth: '48%',
              fillAvailableHeight: true,
              onCandidateClick: (candidate: Candidate, index: number) => this.commitCandidate(index),
              onPreviousPage: () => this.navigateCandidatePage(false),
              onNextPage: () => this.navigateCandidatePage(true)
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .padding({
      left: this.metrics.horizontalPadding,
      right: this.metrics.horizontalPadding,
      top: this.metrics.topPadding,
      bottom: this.metrics.bottomPadding
    })
    .backgroundColor(this.palette.panelBackground)
    if (this.layoutSelectorVisible && this.candidateBarState === CandidateBarState.IDLE) {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#33000000')
      .onClick((): void => {
        this.layoutSelectorVisible = false;
      })

      Row() {
        Column() {
          ForEach(SELECTABLE_KEYBOARD_PROFILES, (profile: KeyboardProfile, index: number) => {
            this.KeyboardProfileOption(profile)
            if (index < SELECTABLE_KEYBOARD_PROFILES.length - 1) {
              Divider().color(this.palette.candidateDivider)
            }
          }, (profile: KeyboardProfile) => profile.profileId)
        }
        .width('52%')
        .padding({ top: 6, bottom: 6 })
        .backgroundColor(this.palette.candidateBackground)
        .borderRadius(this.metrics.keyBorderRadius)
      }
      .width('100%')
      .padding({
        left: this.metrics.horizontalPadding,
        top: this.metrics.topPadding + this.metrics.candidateBarHeight + 4
      })
      .justifyContent(FlexAlign.Start)
    }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private KeyboardProfileOption(profile: KeyboardProfile) {
    Row({ space: 10 }) {
      Text(this.keyboardProfileId === profile.profileId ? '✓' : '')
        .fontSize(15)
        .fontColor(this.palette.modeKeyTextChinese)
        .width(24)
      Text(profile.displayName)
        .fontSize(13)
        .fontColor(this.palette.candidateText)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`${profile.displayName}${this.keyboardProfileId === profile.profileId ? '，已选择' : ''}`)
    .onClick((): void => {
      this.selectKeyboardProfile(profile.profileId);
    })
  }
}
