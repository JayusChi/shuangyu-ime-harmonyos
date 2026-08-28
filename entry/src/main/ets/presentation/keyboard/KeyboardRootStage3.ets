import { KeyboardController } from '../../application/KeyboardController';
import common from '@ohos.app.ability.common';
import { InputMethodListDialog } from '@kit.IMEKit';
import { DeleteRepeatController } from '../../application/DeleteRepeatController';
import {
  DELETE_ACTION,
  HIDE_KEYBOARD_ACTION,
  KeyboardAction,
  KeyboardMode,
  SHOW_INPUT_METHOD_PICKER_ACTION,
  SWITCH_INPUT_METHOD_ACTION,
  TOGGLE_LANGUAGE_ACTION,
  TOGGLE_SYMBOL_ACTION
} from '../../domain/keyboard/KeyboardAction';
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
  KeyboardLayoutSpec,
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
  KEYBOARD_LIFT_LAYER_HEIGHT,
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
import {
  AiAction,
  AiPresentationState,
  createIdleAiPresentationState
} from '../../domain/ai/AiContracts';
import {
  createIdleVoicePresentationState,
  VoicePresentationState
} from '../../domain/voice/VoiceContracts';
import { LocalAssociationSuggestion } from '../../domain/ai/LocalAssociationContracts';
import {
  BUILTIN_KEYBOARD_SKIN_ID,
  BUILTIN_KEYBOARD_STRUCTURE_ID,
  KeyboardCustomizationOption,
  KeyboardCustomizationShortcut,
  KeyboardSkinDefinition,
  KeyboardStructureDefinition,
  resolveKeyboardCustomizationShortcut
} from '../../domain/customization/KeyboardCustomization';
import {
  getSharedKeyboardCustomizationRepository,
  InstalledKeyboardSkin,
  KeyboardCustomizationRepository
} from '../../infrastructure/customization/KeyboardCustomizationRepository';
import { applyKeyboardStructure } from './customization/KeyboardStructureResolver';
import { applyLetterSwipeSymbols } from './customization/LetterSwipeSymbolResolver';
import {
  registerSystemInputMethodPickerOpener,
  unregisterSystemInputMethodPickerOpener
} from '../../infrastructure/ime/InputMethodSwitcher';

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
  private readonly customizationRepository: KeyboardCustomizationRepository =
    getSharedKeyboardCustomizationRepository();
  private readonly openSystemInputMethodPicker = (): boolean => {
    try {
      this.inputMethodPickerDialogController.open();
      return true;
    } catch (_) {
      return false;
    }
  };

  private inputMethodPickerDialogController: CustomDialogController = new CustomDialogController({
    builder: this.SystemInputMethodPickerDialog,
    autoCancel: true
  });

  @State private keyboardMode: KeyboardMode = KeyboardMode.ENGLISH;
  @State private languageMode: KeyboardMode = KeyboardMode.ENGLISH;
  @State private editorContext: EditorContext = createUnknownEditorContext();
  @State private shiftState: ShiftState = ShiftState.LOWERCASE;
  @State private chineseCapsLock: boolean = false;
  @State private candidateBarVisible: boolean = false;
  @State private floatingCandidateVisible: boolean = false;
  @State private cursorPreeditVisible: boolean = false;
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
  @State private keyboardLiftLayerEnabled: boolean = true;
  @State private candidateFontSize: number = 14;
  @State private candidateUiMode: CandidateUiMode = resolveCandidateUiMode(DEFAULT_SCHEME_ID);
  @State private inputMethodSwitchAvailable: boolean = false;
  @State private inputMethodNextAvailable: boolean = false;
  @State private inputMethodPickerAvailable: boolean = false;
  @State private shuangpinLayout: ShuangpinKeyboardLayout = DEFAULT_SHUANGPIN_KEYBOARD_LAYOUT;
  @State private keyboardProfileId: string = DEFAULT_KEYBOARD_PROFILE_ID;
  @State private keyboardStructureId: string = BUILTIN_KEYBOARD_STRUCTURE_ID;
  @State private keyboardSkinId: string = BUILTIN_KEYBOARD_SKIN_ID;
  @State private chineseLetterSwipeSymbols: string = '';
  @State private englishLetterSwipeSymbols: string = '';
  @State private layoutSelectorVisible: boolean = false;
  @State private auxiliaryPolicy: KeyboardAuxiliaryAreaPolicy =
    resolveKeyboardAuxiliaryAreaPolicy(SAFE_FALLBACK_SCREEN_METRICS_PX);
  @State private candidatePresentationMode: CandidatePresentationMode = CandidatePresentationMode.BAR;
  @State private aiEntryVisible: boolean = false;
  @State private aiEntryEnabled: boolean = false;
  @State private aiUnavailableReason: string = '';
  @State private voiceEntryVisible: boolean = false;
  @State private voiceEntryEnabled: boolean = false;
  @State private voiceUnavailableReason: string = '';
  @State private aiPresentation: AiPresentationState = createIdleAiPresentationState();
  @State private voicePresentation: VoicePresentationState = createIdleVoicePresentationState();
  @State private localAssociations: LocalAssociationSuggestion[] = [];

  @State private metrics: OrientationMetrics = PORTRAIT_METRICS;
  private screenMetrics: ScreenMetricsPx = copyScreenMetrics(SAFE_FALLBACK_SCREEN_METRICS_PX);
  // Replacing this single reactive object makes the whole keyboard render from one palette snapshot.
  @State private palette: KeyboardColorPalette = LIGHT_PALETTE;
  private keyboardStructure?: KeyboardStructureDefinition;
  private keyboardSkin?: KeyboardSkinDefinition;
  private keyboardSkinAssetRoot: string = '';
  private pressedShortcutKeyIds: string[] = [];
  private consumedShortcutKeyIds: string[] = [];
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
    this.customizationRepository.initialize(this.getUIContext().getHostContext() as common.Context);
    this.controller.subscribe(this.onSessionStateChanged);
    this.settingsStore.subscribe(this.onSettingsChanged);
    this.layoutPreference.subscribe(this.onKeyboardLayoutChanged);
    registerSystemInputMethodPickerOpener(this.openSystemInputMethodPicker);
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
    unregisterSystemInputMethodPickerOpener(this.openSystemInputMethodPicker);
    this.controller.dispose();
  }

  private refreshState(): void {
    const state = this.controller.getState();
    this.keyboardMode = state.keyboardMode;
    this.languageMode = state.keyboardMode === KeyboardMode.CHINESE ||
      state.keyboardMode === KeyboardMode.ENGLISH
      ? state.keyboardMode
      : state.modeBeforeTransient;
    this.editorContext = state.editorContext;
    this.shiftState = state.shiftState;
    this.chineseCapsLock = state.chineseCapsLock;
    this.candidateBarVisible = state.candidateBarVisible;
    this.floatingCandidateVisible = state.floatingCandidateVisible;
    this.cursorPreeditVisible = state.cursorPreeditVisible === true;
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
    this.aiPresentation = state.aiPresentation;
    this.voicePresentation = state.voicePresentation;
    this.localAssociations = state.localAssociations;
    this.refreshAssistAvailability();
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
    this.inputMethodNextAvailable = capabilities.canSwitchToNext;
    this.inputMethodSwitchAvailable = capabilities.canSwitchToNext || capabilities.canShowSystemPicker;
  }

  @Builder
  private SystemInputMethodPickerDialog() {
    InputMethodListDialog({
      controller: this.inputMethodPickerDialogController
    })
  }

  private updatePalette(): void {
    this.palette = this.themeResolver.resolve(
      this.settingsStore.getEffectiveTheme(),
      this.keyboardSkin,
      this.keyboardSkinAssetRoot
    );
  }

  private refreshSettings(): void {
    const settings = this.settingsStore.getSnapshot();
    this.keyboardProfileId = settings.keyboardProfileId;
    this.keyboardStructureId = settings.keyboardStructureId;
    this.keyboardSkinId = settings.keyboardSkinId;
    this.chineseLetterSwipeSymbols = settings.chineseLetterSwipeSymbols;
    this.englishLetterSwipeSymbols = settings.englishLetterSwipeSymbols;
    this.keyboardStructure = this.customizationRepository.loadStructure(this.keyboardStructureId);
    const installedSkin: InstalledKeyboardSkin | undefined =
      this.customizationRepository.loadSkin(this.keyboardSkinId);
    this.keyboardSkin = installedSkin?.definition;
    this.keyboardSkinAssetRoot = installedSkin?.assetRoot ?? '';
    this.keyboardHeightMode = settings.keyboardHeightMode;
    this.keyboardLiftLayerEnabled = settings.keyboardLiftLayerEnabled;
    this.candidateFontSize = this.resolveCandidateFontSize(settings.candidateFontSizeMode);
    this.candidateUiMode = resolveCandidateUiMode(settings.schemeId);
    if (!allowsCandidateBrowsing(this.candidateUiMode) && this.candidatePanelExpanded) {
      this.controller.setCandidatePanelExpanded(false);
      this.candidatePanelExpanded = false;
    }
    this.candidatePresentationMode = settings.candidatePresentationMode;
    this.aiEntryVisible = settings.aiEnabled;
    this.voiceEntryVisible = settings.voiceInputEnabled;
    this.refreshAssistAvailability();
    this.updateMetrics();
    this.updatePalette();
  }

  private refreshAssistAvailability(): void {
    const availability = this.controller.getAssistAvailability();
    this.aiEntryEnabled = availability.ai.available;
    this.aiUnavailableReason = availability.ai.message;
    this.voiceEntryEnabled = availability.voice.available;
    this.voiceUnavailableReason = availability.voice.message;
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
      this.candidates
    );
  }

  private isCandidatePanelActive(): boolean {
    return allowsCandidateBrowsing(this.candidateUiMode) && this.candidatePanelExpanded;
  }

  private async dispatchAction(action: KeyboardAction): Promise<void> {
    await this.controller.handleAction(action);
  }

  private currentKeyboardLayout(): KeyboardLayoutSpec {
    const base = createStage10KeyboardLayout(
      this.keyboardMode,
      this.editorContext,
      this.shiftState,
      this.rawInput,
      this.chineseCapsLock,
      false,
      this.shuangpinLayout,
      this.keyboardProfileId
    );
    return applyLetterSwipeSymbols(
      applyKeyboardStructure(base, this.keyboardStructure),
      this.keyboardMode,
      this.chineseLetterSwipeSymbols,
      this.englishLetterSwipeSymbols
    );
  }

  private handleCustomizationKeyPress(spec: KeyboardKeySpec): void {
    if (this.pressedShortcutKeyIds.indexOf(spec.id) < 0) {
      this.pressedShortcutKeyIds = this.pressedShortcutKeyIds.concat([spec.id]);
    }
    const shortcut = resolveKeyboardCustomizationShortcut(this.pressedShortcutKeyIds);
    if (shortcut === KeyboardCustomizationShortcut.NONE) {
      return;
    }
    const chordIds = shortcut === KeyboardCustomizationShortcut.CYCLE_SKIN
      ? ['number', 'space']
      : (this.pressedShortcutKeyIds.indexOf('punctuation-period') >= 0
        ? ['punctuation-period', 'space']
        : ['symbol', 'space']);
    if (chordIds.every((id: string): boolean => this.consumedShortcutKeyIds.indexOf(id) >= 0)) {
      return;
    }
    chordIds.forEach((id: string): void => {
      if (this.consumedShortcutKeyIds.indexOf(id) < 0) {
        this.consumedShortcutKeyIds.push(id);
      }
    });
    this.cycleCustomization(shortcut);
  }

  private handleCustomizationKeyRelease(spec: KeyboardKeySpec): void {
    this.pressedShortcutKeyIds = this.pressedShortcutKeyIds.filter((id: string): boolean => id !== spec.id);
  }

  private handleCustomizationKeyClick(spec: KeyboardKeySpec): void {
    const consumedIndex = this.consumedShortcutKeyIds.indexOf(spec.id);
    if (consumedIndex >= 0) {
      this.consumedShortcutKeyIds.splice(consumedIndex, 1);
      return;
    }
    this.dispatchAction(spec.action);
  }

  private async cycleCustomization(shortcut: KeyboardCustomizationShortcut): Promise<void> {
    const options: KeyboardCustomizationOption[] = shortcut === KeyboardCustomizationShortcut.CYCLE_SKIN
      ? this.customizationRepository.listSkins()
      : this.customizationRepository.listStructures();
    if (options.length <= 1) {
      this.showToast('暂无其他可切换模板');
      return;
    }
    const currentId = shortcut === KeyboardCustomizationShortcut.CYCLE_SKIN
      ? this.keyboardSkinId
      : this.keyboardStructureId;
    const currentIndex = options.findIndex((option: KeyboardCustomizationOption): boolean => option.id === currentId);
    const next = options[(currentIndex + 1 + options.length) % options.length];
    const result = shortcut === KeyboardCustomizationShortcut.CYCLE_SKIN
      ? await this.settingsController.setKeyboardSkinId(next.id)
      : await this.settingsController.setKeyboardStructureId(next.id);
    if (!result.success) {
      this.lastErrorMessage = result.message;
      this.candidateBarState = CandidateBarState.ERROR;
      return;
    }
    this.refreshSettings();
    this.showToast(shortcut === KeyboardCustomizationShortcut.CYCLE_SKIN
      ? `已切换皮肤：${next.name}`
      : `已切换结构：${next.name}`);
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (_) {}
  }

  private async commitCandidate(index: number): Promise<void> {
    await this.controller.commitCandidate(index);
  }

  private async selectPinyinCombination(index: number): Promise<void> {
    await this.controller.selectPinyinCombination(index);
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

  private liftLayerLanguageLabel(): string {
    return this.languageMode === KeyboardMode.CHINESE ? '中→英' : '英→中';
  }

  private switchInputMethodFromLiftLayer(): void {
    if (!this.inputMethodSwitchAvailable) {
      return;
    }
    this.dispatchAction(this.inputMethodNextAvailable
      ? SWITCH_INPUT_METHOD_ACTION
      : SHOW_INPUT_METHOD_PICKER_ACTION);
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
        onDeleteClick: () => this.handleDeleteClick(),
        onAlternateAction: (action: KeyboardAction) => this.dispatchAction(action)
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
        onKeyClick: (s: KeyboardKeySpec) => this.dispatchAction(s.action),
        onAlternateAction: (action: KeyboardAction) => this.dispatchAction(action)
      })
    } else {
      BaseKey({
        spec: spec,
        palette: this.palette,
        metrics: this.metrics,
        keyboardMode: this.keyboardMode,
        shiftState: this.shiftState,
        longPressEnabled: true,
        onKeyPress: (s: KeyboardKeySpec) => this.handleCustomizationKeyPress(s),
        onKeyRelease: (s: KeyboardKeySpec) => this.handleCustomizationKeyRelease(s),
        onKeyClick: (s: KeyboardKeySpec) => this.handleCustomizationKeyClick(s),
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

  @Builder
  private KeyboardLiftLayer() {
    Row() {
      Row() {
        Image($r('app.media.input_method_switcher'))
          .width(22)
          .height(22)
          .fillColor(this.palette.functionKeyText)
          .objectFit(ImageFit.Contain)
      }
      .width(54)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .opacity(this.inputMethodSwitchAvailable ? 1 : 0.4)
      .enabled(this.inputMethodSwitchAvailable)
      .accessibilityText('切换输入法')
      .onClick((): void => this.switchInputMethodFromLiftLayer())

      Row() {
        Text(this.liftLayerLanguageLabel())
          .fontSize(11)
          .fontColor(this.palette.functionKeyText)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height('100%')
          .opacity(this.editorContext.chineseModeAllowed && this.editorContext.englishModeAllowed ? 1 : 0.4)
          .enabled(this.editorContext.chineseModeAllowed && this.editorContext.englishModeAllowed)
          .accessibilityText('切换中英文键盘')
          .onClick((): void => {
            this.dispatchAction(TOGGLE_LANGUAGE_ACTION);
          })
        Text('符号')
          .fontSize(11)
          .fontColor(this.keyboardMode === KeyboardMode.SYMBOL
            ? this.palette.modeKeyTextChinese
            : this.palette.functionKeyText)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height('100%')
          .opacity(this.editorContext.symbolModeAllowed ? 1 : 0.4)
          .enabled(this.editorContext.symbolModeAllowed)
          .accessibilityText(this.keyboardMode === KeyboardMode.SYMBOL ? '返回文字键盘' : '切换到符号键盘')
          .onClick((): void => {
            this.dispatchAction(TOGGLE_SYMBOL_ACTION);
          })
        Text('键盘')
          .fontSize(11)
          .fontColor(this.palette.functionKeyText)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height('100%')
          .accessibilityText(`${this.keyboardProfileName()}，选择其他键盘`)
          .onClick((): void => this.toggleLayoutSelector())
      }
      .height('100%')
      .layoutWeight(1)

      Row() {
        Image($r('app.media.keyboard_hide_chevron'))
          .width(22)
          .height(22)
          .fillColor(this.palette.functionKeyText)
          .objectFit(ImageFit.Contain)
      }
      .width(54)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .accessibilityText('隐藏键盘')
      .onClick((): void => {
        this.dispatchAction(HIDE_KEYBOARD_ACTION);
      })
    }
    .width('100%')
    .height(KEYBOARD_LIFT_LAYER_HEIGHT)
    .backgroundColor(this.palette.candidateBackground)
    .border({ width: { top: 1 }, color: this.palette.candidateDivider })
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
        cursorPreeditVisible: this.cursorPreeditVisible,
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
        bottomLiftLayerVisible: this.keyboardLiftLayerEnabled,
        aiEntryVisible: this.aiEntryVisible,
        aiEntryEnabled: this.aiEntryEnabled,
        aiUnavailableReason: this.aiUnavailableReason,
        voiceEntryVisible: this.voiceEntryVisible,
        voiceEntryEnabled: this.voiceEntryEnabled,
        voiceUnavailableReason: this.voiceUnavailableReason,
        aiPresentation: this.aiPresentation,
        voicePresentation: this.voicePresentation,
        localAssociations: this.localAssociations,
        errorMessage: this.lastErrorMessage,
        candidateFontSize: this.candidateFontSize,
        onCandidateClick: (candidate: Candidate, index: number) => this.commitCandidate(index),
        onToggleExpanded: (expanded: boolean) => this.toggleCandidatePanel(expanded),
        onAction: (action: KeyboardAction) => this.dispatchAction(action),
        onOpenKeyboardLayoutSelector: () => this.toggleLayoutSelector(),
        onOpenSettings: () => this.openSettings(),
        onAiEntry: () => this.controller.showAiActions(),
        onAiAction: (action: AiAction) => this.controller.requestAiSuggestions(action),
        onAiSuggestionClick: (suggestionId: string) => {
          this.controller.acceptAiSuggestion(suggestionId);
        },
        onAiCancel: () => this.controller.cancelAiRequest(),
        onLocalAssociationClick: (associationId: string) => {
          this.controller.acceptLocalAssociation(associationId);
        },
        onVoiceEntry: () => this.controller.startVoiceInput(),
        onVoiceStop: () => this.controller.stopVoiceInput(),
        onVoiceConfirm: () => {
          this.controller.confirmVoiceResult();
        },
        onVoiceRetry: () => this.controller.retryVoiceInput(),
        onVoiceCancel: () => this.controller.cancelVoiceInput()
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
            rawInput: this.rawInput,
            preeditText: this.preeditText,
            cursorPreeditVisible: this.cursorPreeditVisible,
            displaySegments: this.displaySegments,
            pendingCode: this.pendingCode,
            segmentBoundaries: this.segmentBoundaries,
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
            ForEach(this.currentKeyboardLayout().rows, (row: KeyboardRowSpec, index: number) => {
              this.KeyboardRow(row)
            }, (row: KeyboardRowSpec, index: number) =>
              `${this.editorContext.kind}-${this.keyboardMode}-${this.shiftState}-${this.keyboardLayoutRawInput}-` +
                `${this.chineseCapsLock}-` +
                `${this.shuangpinLayout}-` +
                `${this.keyboardProfileId}-` +
                `${this.keyboardStructureId}-` +
                `${this.editorContext.numberDecimalAllowed}-${this.editorContext.enterAction}-row-${index}`)
          }
          .layoutWeight(1)
          .height('100%')

          if (this.isCandidatePanelActive() && this.isTabletLayout()) {
            CandidateExpansionPanel({
              palette: this.palette,
              rawInput: this.rawInput,
              preeditText: this.preeditText,
              cursorPreeditVisible: this.cursorPreeditVisible,
              displaySegments: this.displaySegments,
              pendingCode: this.pendingCode,
              segmentBoundaries: this.segmentBoundaries,
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

      if (this.keyboardLiftLayerEnabled) {
        this.KeyboardLiftLayer()
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
    .backgroundImage(this.palette.panelBackgroundImage, ImageRepeat.NoRepeat)
    .backgroundImageSize({ width: '100%', height: '100%' })
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
