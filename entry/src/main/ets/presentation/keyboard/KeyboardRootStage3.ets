import { KeyboardController } from '../../application/KeyboardController';
import common from '@ohos.app.ability.common';
import { InputMethodAppPickerDialog } from './components/InputMethodAppPickerDialog';
import { DeleteRepeatController } from '../../application/DeleteRepeatController';
import {
  createCharacterInputAction,
  DELETE_ACTION,
  HIDE_KEYBOARD_ACTION,
  KeyboardAction,
  KeyboardActionType,
  KeyboardMode,
  MOVE_CURSOR_LEFT_ACTION,
  MOVE_CURSOR_RIGHT_ACTION,
  SECOND_CANDIDATE_OR_PERIOD_ACTION,
  SHOW_INPUT_METHOD_PICKER_ACTION,
  THIRD_CANDIDATE_OR_COMMA_ACTION,
  TOGGLE_NUMBER_ACTION,
  TOGGLE_SYMBOL_ACTION
} from '../../domain/keyboard/KeyboardAction';
import InputMethodExtensionContext from '@ohos.InputMethodExtensionContext';
import {
  createUnknownEditorContext,
  EditorContext,
  ShiftState
} from '../../domain/editor/EditorContext';
import {
  CandidatePresentationMode,
  DEFAULT_CANDIDATE_FONT_SIZE,
  DEFAULT_KEYBOARD_FONT_SIZE,
  DEFAULT_UPPER_LABEL_RIGHT_MARGIN,
  DEFAULT_LONG_PRESS_DURATION_MS,
  KeyboardHeightMode,
  DEFAULT_SCHEME_ID
} from '../../domain/settings/ImeSettings';
import {
  allowsCandidateBrowsing,
  CandidateUiMode,
  resolveCandidateSourceIndex,
  resolveCandidateUiMode,
  resolveVisibleCandidates,
  shouldShowCandidateExpansionAction
} from '../../domain/candidate/CandidateUiPolicy';
import { getSharedSettingsStore, SettingsStore } from '../../state/SettingsStore';
import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import {
  KeyboardKeySpec,
  KeyboardKeyKind,
  KeyboardLayoutSpec,
  KeyboardRowKind,
  KeyboardRowSpec,
  keyboardRowRenderIdentity
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
  KEY_WEIGHTS,
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
      this.layoutSelectorVisible = false;
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
  @State private symbolLanguageMode: KeyboardMode = KeyboardMode.CHINESE;
  @State private longPressDurationMs: number = DEFAULT_LONG_PRESS_DURATION_MS;
  @State private candidateFontSize: number = DEFAULT_CANDIDATE_FONT_SIZE;
  @State private candidateDisplayCount: number = 5;
  @State private keyboardFontSize: number = DEFAULT_KEYBOARD_FONT_SIZE;
  @State private upperLabelRightMargin: number = DEFAULT_UPPER_LABEL_RIGHT_MARGIN;
  @State private candidateUiMode: CandidateUiMode = resolveCandidateUiMode(DEFAULT_SCHEME_ID);
  @State private inputMethodSwitchAvailable: boolean = false;
  @State private inputMethodPickerAvailable: boolean = false;
  @State private shuangpinLayout: ShuangpinKeyboardLayout = DEFAULT_SHUANGPIN_KEYBOARD_LAYOUT;
  @State private keyboardProfileId: string = DEFAULT_KEYBOARD_PROFILE_ID;
  @State private keyboardStructureId: string = BUILTIN_KEYBOARD_STRUCTURE_ID;
  @State private keyboardStructureRevision: number = 0;
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
  private keyboardStructureSignature: string = '';
  private keyboardSkin?: KeyboardSkinDefinition;
  private keyboardSkinAssetRoot: string = '';
  private customizationLoadGeneration: number = 0;
  private cachedKeyboardLayoutKey: string = '';
  private cachedKeyboardLayout?: KeyboardLayoutSpec;
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
    const generation = ++this.customizationLoadGeneration;
    this.customizationRepository.initialize(this.getUIContext().getHostContext() as common.Context)
      .then((): void => {
        if (generation === this.customizationLoadGeneration) {
          // Settings may arrive before getGroupDir resolves. Reload the latest
          // selection and replace the reactive palette after storage is ready.
          this.refreshSettings();
        }
      });
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
    this.customizationLoadGeneration++;
    this.deleteRepeatController.destroy();
    this.controller.unsubscribe(this.onSessionStateChanged);
    this.settingsStore.unsubscribe(this.onSettingsChanged);
    this.layoutPreference.unsubscribe(this.onKeyboardLayoutChanged);
    unregisterSystemInputMethodPickerOpener(this.openSystemInputMethodPicker);
    this.inputMethodPickerDialogController.close();
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
    this.parserState = state.parserState;
    this.candidates = state.candidates;
    this.highlightedIndex = state.highlightedIndex;
    this.candidatePanelExpanded = state.candidatePanelExpanded;
    this.candidatePageLoading = state.candidatePageLoading;
    this.candidatePage = state.candidatePage;
    this.hasNextPage = state.hasNextPage;
    this.hasPreviousPage = state.hasPreviousPage;
    if (this.candidatePanelExpanded &&
      !allowsCandidateBrowsing(this.candidateUiMode, this.rawInput)) {
      this.candidatePanelExpanded = false;
      this.controller.setCandidatePanelExpanded(false);
    }
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
      this.screenMetrics,
      this.keyboardFontSize,
      this.upperLabelRightMargin
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

  @Builder
  private SystemInputMethodPickerDialog() {
    InputMethodAppPickerDialog({
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
    // A customization package may be replaced in place while keeping its ID.
    // Drop the cache on every settings snapshot so that the next render reads
    // the newly loaded structure exactly once.
    this.cachedKeyboardLayoutKey = '';
    this.cachedKeyboardLayout = undefined;
    const settings = this.settingsStore.getSnapshot();
    this.keyboardProfileId = settings.keyboardProfileId;
    this.keyboardStructureId = settings.keyboardStructureId;
    this.keyboardSkinId = settings.keyboardSkinId;
    this.chineseLetterSwipeSymbols = settings.chineseLetterSwipeSymbols;
    this.englishLetterSwipeSymbols = settings.englishLetterSwipeSymbols;
    this.keyboardStructure = this.customizationRepository.loadStructure(this.keyboardStructureId);
    // The same selected ID can first resolve to nothing while getGroupDir is
    // pending, or later resolve to a replacement package. ForEach must recreate
    // its rows when the loaded definition changes, even if the ID stays equal.
    const structureSignature = this.keyboardStructure ? JSON.stringify(this.keyboardStructure) : '';
    if (structureSignature !== this.keyboardStructureSignature) {
      this.keyboardStructureSignature = structureSignature;
      this.keyboardStructureRevision++;
    }
    const installedSkin: InstalledKeyboardSkin | undefined =
      this.customizationRepository.loadSkin(this.keyboardSkinId);
    this.keyboardSkin = installedSkin?.definition;
    this.keyboardSkinAssetRoot = installedSkin?.assetRoot ?? '';
    this.keyboardHeightMode = settings.keyboardHeightMode;
    this.keyboardFontSize = settings.keyboardFontSize;
    this.upperLabelRightMargin = settings.upperLabelRightMargin;
    this.keyboardLiftLayerEnabled = settings.keyboardLiftLayerEnabled;
    this.longPressDurationMs = settings.longPressDurationMs;
    this.deleteRepeatController.setLongPressDelayMs(settings.longPressDurationMs);
    this.candidateFontSize = settings.candidateFontSize;
    this.candidateDisplayCount = settings.candidateDisplayCount;
    this.candidateUiMode = resolveCandidateUiMode(settings.schemeId);
    if (!allowsCandidateBrowsing(this.candidateUiMode, this.rawInput) && this.candidatePanelExpanded) {
      this.controller.setCandidatePanelExpanded(false);
      this.candidatePanelExpanded = false;
    }
    if (settings.candidatePresentationMode === CandidatePresentationMode.FLOATING) {
      this.layoutSelectorVisible = false;
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

  private visibleCandidates(): Candidate[] {
    return resolveVisibleCandidates(
      this.candidateUiMode,
      this.rawInput,
      this.candidates
    );
  }

  private candidateSourceIndex(candidate: Candidate): number {
    return resolveCandidateSourceIndex(this.candidates, candidate);
  }

  private isCandidatePanelActive(): boolean {
    return allowsCandidateBrowsing(this.candidateUiMode, this.rawInput) && this.candidatePanelExpanded;
  }

  private async dispatchAction(action: KeyboardAction): Promise<void> {
    if (action.type === KeyboardActionType.EXPAND_CANDIDATES) {
      this.toggleCandidatePanel(true);
      return;
    }
    if (action.type === KeyboardActionType.TOGGLE_SYMBOL && this.keyboardMode !== KeyboardMode.SYMBOL) {
      this.symbolLanguageMode = this.languageMode;
    }
    await this.controller.handleAction(action);
  }

  private currentKeyboardLayout(): KeyboardLayoutSpec {
    // Candidate/preedit state changes on every Chinese key, but the key grid
    // only changes once when the Chinese left key swaps between Shift and Esc.
    // Keep the exact composition text out of the cache key so subsequent
    // candidate refreshes do not allocate and diff the entire keyboard.
    const chineseCompositionActive = this.keyboardMode === KeyboardMode.CHINESE && this.rawInput.length > 0;
    const cacheKey = `${this.editorContext.kind}-${this.editorContext.enterAction}-` +
      `${this.editorContext.chineseModeAllowed}-${this.editorContext.englishModeAllowed}-` +
      `${this.editorContext.numberModeAllowed}-${this.editorContext.symbolModeAllowed}-` +
      `${this.editorContext.numberDecimalAllowed}-${this.keyboardMode}-${this.shiftState}-` +
      `${this.chineseCapsLock}-${this.shuangpinLayout}-${this.keyboardProfileId}-` +
      `${this.keyboardStructureId}-${this.keyboardStructureRevision}-${chineseCompositionActive}-${this.symbolLanguageMode}-` +
      `${this.chineseLetterSwipeSymbols}-${this.englishLetterSwipeSymbols}`;
    if (this.cachedKeyboardLayout !== undefined && this.cachedKeyboardLayoutKey === cacheKey) {
      return this.cachedKeyboardLayout;
    }
    const base = createStage10KeyboardLayout(
      this.keyboardMode,
      this.editorContext,
      this.shiftState,
      chineseCompositionActive ? this.rawInput : '',
      this.chineseCapsLock,
      !this.keyboardLiftLayerEnabled,
      this.shuangpinLayout,
      this.keyboardProfileId,
      this.symbolLanguageMode
    );
    const layout = applyLetterSwipeSymbols(
      applyKeyboardStructure(base, this.keyboardStructure),
      this.keyboardMode,
      this.chineseLetterSwipeSymbols,
      this.englishLetterSwipeSymbols
    );
    this.cachedKeyboardLayoutKey = cacheKey;
    this.cachedKeyboardLayout = layout;
    return layout;
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
    if (expanded && !allowsCandidateBrowsing(this.candidateUiMode, this.rawInput)) {
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

  private liftLayerPunctuationLabel(comma: boolean): string {
    if (this.languageMode === KeyboardMode.CHINESE) {
      return comma ? '，' : '。';
    }
    return comma ? ',' : '.';
  }

  private liftLayerPunctuationAction(comma: boolean): KeyboardAction {
    if (this.languageMode === KeyboardMode.CHINESE) {
      return comma ? THIRD_CANDIDATE_OR_COMMA_ACTION : SECOND_CANDIDATE_OR_PERIOD_ACTION;
    }
    return createCharacterInputAction(comma ? ',' : '.');
  }

  private liftLayerKeyWeight(keyId: string, fallback: number): number {
    const rows = this.currentKeyboardLayout().rows;
    for (let rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
      if (rows[rowIndex].kind !== KeyboardRowKind.BOTTOM_ACTIONS) {
        continue;
      }
      const keys = rows[rowIndex].keys;
      for (let keyIndex = 0; keyIndex < keys.length; keyIndex += 1) {
        if (keys[keyIndex].id === keyId) {
          return keys[keyIndex].weight;
        }
      }
    }
    return fallback;
  }

  private showInputMethodPickerFromLiftLayer(): void {
    if (!this.inputMethodPickerAvailable) {
      return;
    }
    // The lift-layer icon is the system IME entry, never the keyboard-profile selector.
    this.layoutSelectorVisible = false;
    this.dispatchAction(SHOW_INPUT_METHOD_PICKER_ACTION);
  }

  private returnFromTransientKeyboard(): void {
    if (this.keyboardMode === KeyboardMode.NUMBER) {
      this.dispatchAction(TOGGLE_NUMBER_ACTION);
    } else if (this.keyboardMode === KeyboardMode.SYMBOL) {
      this.dispatchAction(TOGGLE_SYMBOL_ACTION);
    }
  }

  private showNumberKeyboard(): void {
    if (this.keyboardMode !== KeyboardMode.NUMBER) {
      this.dispatchAction(TOGGLE_NUMBER_ACTION);
    }
  }

  private showSymbolKeyboard(languageMode: KeyboardMode): void {
    this.symbolLanguageMode = languageMode;
    if (this.keyboardMode !== KeyboardMode.SYMBOL) {
      this.controller.handleAction(TOGGLE_SYMBOL_ACTION);
    }
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
  }

  private handleDeleteClick(): void {
    this.deleteRepeatController.triggerSingleDelete();
  }

  private handleDeleteAlternateAction(action: KeyboardAction): void {
    this.deleteRepeatController.cancelForAlternateGesture();
    this.dispatchAction(action);
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
        longPressDurationMs: this.longPressDurationMs,
        onDeletePress: () => this.handleDeletePress(),
        onDeleteRelease: () => this.handleDeleteRelease(),
        onDeleteClick: () => this.handleDeleteClick(),
        onAlternateAction: (action: KeyboardAction) => this.handleDeleteAlternateAction(action)
      })
    } else if (spec.kind === KeyboardKeyKind.INPUT_METHOD_SWITCH) {
      InputMethodSwitchKey({
        spec: spec,
        palette: this.palette,
        metrics: this.metrics,
        longPressEnabled: this.inputMethodPickerAvailable,
        longPressDurationMs: this.longPressDurationMs,
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
        longPressDurationMs: this.longPressDurationMs,
        onKeyClick: (s: KeyboardKeySpec) => this.dispatchAction(s.action),
        onAlternateAction: (action: KeyboardAction) => this.dispatchAction(action)
      })
    } else {
      BaseKey({
        spec: spec,
        hasCandidates: this.candidates.length > 0,
        palette: this.palette,
        metrics: this.metrics,
        keyboardMode: this.keyboardMode,
        shiftState: this.shiftState,
        longPressEnabled: true,
        longPressDurationMs: this.longPressDurationMs,
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
  private rowHorizontalInset(row: KeyboardRowSpec): Length {
    const columns = row.uniformKeyColumns ?? 0;
    if (columns > row.keys.length) {
      // Include the missing inter-key gap so all three rows have identical key widths.
      return `calc((100% + ${this.metrics.keySpacing}vp) * ${columns - row.keys.length} / ${2 * columns})`;
    }
    return row.kind === KeyboardRowKind.MIDDLE_LETTERS ? this.metrics.secondRowInset : 0;
  }

  @Builder
  private KeyboardRow(row: KeyboardRowSpec) {
    Row({ space: this.metrics.keySpacing }) {
      ForEach(row.keys, (spec: KeyboardKeySpec) => {
        this.renderKey(spec)
      }, (spec: KeyboardKeySpec) => spec.id)
    }
    .width('100%')
    .padding({
      left: this.rowHorizontalInset(row),
      right: this.rowHorizontalInset(row)
    })
    // 行高由 layoutWeight 均分面板可用高度，避免固定行高与面板高度不匹配时溢出/拉伸。
    .layoutWeight(1)
  }

  @Builder
  private KeyboardLiftLayer() {
    Row({ space: this.metrics.keySpacing }) {
      Row() {
        Image($r('app.media.input_method_switcher'))
          .width(22)
          .height(22)
          .fillColor(this.palette.functionKeyText)
          .objectFit(ImageFit.Contain)
      }
      .layoutWeight(this.liftLayerKeyWeight('number', KEY_WEIGHTS.MODE_SWITCH))
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .opacity(this.inputMethodPickerAvailable ? 1 : 0.4)
      .enabled(this.inputMethodPickerAvailable)
      .accessibilityText('选择输入法')
      .id('system-input-method-picker')
      .onClick((): void => this.showInputMethodPickerFromLiftLayer())

      Text(this.liftLayerPunctuationLabel(true))
        .fontSize(this.metrics.functionFontSize + 2)
        .fontColor(this.palette.panelBackground)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .layoutWeight(this.liftLayerKeyWeight('punctuation-comma', 0.9))
        .height('100%')
        .accessibilityText('输入逗号')
        .onClick((): void => {
          this.dispatchAction(this.liftLayerPunctuationAction(true));
        })

      Row() {
        Text('左移')
          .fontSize(this.metrics.functionFontSize)
          .fontColor(this.palette.panelBackground)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height('100%')
          .accessibilityText('向左移动光标')
          .onClick((): void => {
            this.dispatchAction(MOVE_CURSOR_LEFT_ACTION);
          })
        Text('右移')
          .fontSize(this.metrics.functionFontSize)
          .fontColor(this.palette.panelBackground)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height('100%')
          .accessibilityText('向右移动光标')
          .onClick((): void => {
            this.dispatchAction(MOVE_CURSOR_RIGHT_ACTION);
          })
      }
      .height('100%')
      .layoutWeight(this.liftLayerKeyWeight('space', KEY_WEIGHTS.SPACE))

      Text(this.liftLayerPunctuationLabel(false))
        .fontSize(this.metrics.functionFontSize + 2)
        .fontColor(this.palette.panelBackground)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .layoutWeight(this.liftLayerKeyWeight('punctuation-period', 0.9))
        .height('100%')
        .accessibilityText('输入句号')
        .onClick((): void => {
          this.dispatchAction(this.liftLayerPunctuationAction(false));
        })

      Row() {
        Image($r('app.media.keyboard_hide_chevron'))
          .width(22)
          .height(22)
          .fillColor(this.palette.functionKeyText)
          .objectFit(ImageFit.Contain)
      }
      .layoutWeight(this.liftLayerKeyWeight('enter', KEY_WEIGHTS.ENTER))
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .accessibilityText('隐藏键盘')
      .onClick((): void => {
        this.dispatchAction(HIDE_KEYBOARD_ACTION);
      })
    }
    .width('100%')
    .height(this.metrics.letterKeyHeight)
    .backgroundColor(this.palette.panelBackground)
  }

  @Builder
  private TransientKeyboardLiftLayer() {
    Row({ space: this.metrics.keySpacing }) {
      Text('返回')
        .fontSize(this.metrics.functionFontSize)
        .fontColor(this.palette.functionKeyText)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height('100%')
        .accessibilityText('返回文字键盘')
        .onClick((): void => this.returnFromTransientKeyboard())
      Text('数字')
        .fontSize(this.metrics.functionFontSize)
        .fontColor(this.keyboardMode === KeyboardMode.NUMBER
          ? this.palette.modeKeyTextChinese
          : this.palette.functionKeyText)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height('100%')
        .accessibilityText('数字键盘')
        .onClick((): void => this.showNumberKeyboard())
      Text('中文')
        .fontSize(this.metrics.functionFontSize)
        .fontColor(this.keyboardMode === KeyboardMode.SYMBOL &&
          this.symbolLanguageMode === KeyboardMode.CHINESE
          ? this.palette.modeKeyTextChinese
          : this.palette.functionKeyText)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height('100%')
        .accessibilityText('中文符号键盘')
        .onClick((): void => this.showSymbolKeyboard(KeyboardMode.CHINESE))
      Text('英文')
        .fontSize(this.metrics.functionFontSize)
        .fontColor(this.keyboardMode === KeyboardMode.SYMBOL &&
          this.symbolLanguageMode === KeyboardMode.ENGLISH
          ? this.palette.modeKeyTextChinese
          : this.palette.functionKeyText)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height('100%')
        .accessibilityText('英文符号键盘')
        .onClick((): void => this.showSymbolKeyboard(KeyboardMode.ENGLISH))
      Row() {
        Image($r('app.media.keyboard_hide_chevron'))
          .width(22)
          .height(22)
          .fillColor(this.palette.functionKeyText)
          .objectFit(ImageFit.Contain)
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .accessibilityText('隐藏键盘')
      .onClick((): void => {
        this.dispatchAction(HIDE_KEYBOARD_ACTION);
      })
    }
    .width('100%')
    .height(this.metrics.letterKeyHeight)
    .backgroundColor(this.palette.panelBackground)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
    Column({ space: this.metrics.rowSpacing }) {
      // 输入框下方浮窗承担候选展示时，固定候选栏整行不再占用键盘高度。
      if (this.candidatePresentationMode !== CandidatePresentationMode.FLOATING &&
        !this.isCandidatePanelActive()) {
        CandidateBar({
        onClipboardReversePaste: (): void => { this.controller.refreshClipboardReverseCandidate(); },
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
          !this.floatingCandidateVisible,
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
        candidateDisplayCount: this.candidateDisplayCount,
        hasNextPage: this.hasNextPage,
        onCandidateClick: (candidate: Candidate, index: number) =>
          this.commitCandidate(this.candidateSourceIndex(candidate)),
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
      }

      if (this.shouldShowPinyinCombinationBar() && !this.isCandidatePanelActive()) {
        PinyinCombinationBar({
          palette: this.palette,
          currentPinyin: this.currentPinyin,
          pinyinCombinations: this.pinyinCombinations,
          barHeight: this.metrics.pinyinCombinationBarHeight,
          onCombinationClick: (combinationIndex: number) => this.selectPinyinCombination(combinationIndex)
        })
      }

      if (this.isCandidatePanelActive() && this.visibleCandidates().length > 0) {
        CandidateExpansionPanel({
          palette: this.palette,
          rawInput: this.rawInput,
          preeditText: this.preeditText,
          cursorPreeditVisible: this.cursorPreeditVisible,
          displaySegments: this.displaySegments,
          pendingCode: this.pendingCode,
          segmentBoundaries: this.segmentBoundaries,
          candidates: this.visibleCandidates(),
          candidatePage: this.candidatePage,
          hasPreviousPage: this.hasPreviousPage,
          hasNextPage: this.hasNextPage,
          pageLoading: this.candidatePageLoading,
          candidateFontSize: this.candidateFontSize,
          candidateUiMode: this.candidateUiMode,
          highlightedIndex: this.highlightedIndex,
          layout: this.candidateExpansionLayout(),
          fillAvailableHeight: true,
          collapseActionVisible: true,
          onCandidateClick: (candidate: Candidate, index: number) =>
            this.commitCandidate(this.candidateSourceIndex(candidate)),
          onPreviousPage: () => this.navigateCandidatePage(false),
          onNextPage: () => this.navigateCandidatePage(true),
          onCollapse: () => this.toggleCandidatePanel(false)
        })
      }

      if (!this.isCandidatePanelActive()) {
        Row({ space: this.metrics.keySpacing }) {
          Column({ space: this.metrics.rowSpacing }) {
            ForEach(this.currentKeyboardLayout().rows, (row: KeyboardRowSpec, index: number) => {
              this.KeyboardRow(row)
            }, (row: KeyboardRowSpec, index: number) => keyboardRowRenderIdentity({
              editorKind: this.editorContext.kind,
              keyboardMode: this.keyboardMode,
              symbolLanguageMode: this.symbolLanguageMode,
              shiftState: this.shiftState,
              rawInput: this.rawInput,
              chineseCapsLock: this.chineseCapsLock,
              shuangpinLayout: this.shuangpinLayout,
              keyboardProfileId: this.keyboardProfileId,
              keyboardStructureId: this.keyboardStructureId,
              numberDecimalAllowed: this.editorContext.numberDecimalAllowed,
              enterAction: this.editorContext.enterAction
            }, index) + ':' + this.keyboardStructureRevision)
          }
          .layoutWeight(1)
          .height('100%')

        }
        .width('100%')
        .layoutWeight(1)
      }

      if (this.keyboardLiftLayerEnabled && !this.isCandidatePanelActive()) {
        if (this.keyboardMode === KeyboardMode.NUMBER || this.keyboardMode === KeyboardMode.SYMBOL) {
          this.TransientKeyboardLiftLayer()
        } else {
          this.KeyboardLiftLayer()
        }
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
