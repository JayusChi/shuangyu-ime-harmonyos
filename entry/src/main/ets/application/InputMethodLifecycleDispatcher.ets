import { inputMethodEngine, InputMethodExtensionContext } from '@kit.IMEKit';
import { Logger } from '../common/logging/Logger';
import { InputPanelController } from './InputPanelController';
import { InputSessionController } from './InputSessionController';
import {
  ImeSettings,
  PunctuationMode,
  XIAOHE_YINXING_SCHEME_ID
} from '../domain/settings/ImeSettings';
import {
  DeviceMetricsProvider,
  HarmonyDeviceMetricsProvider
} from '../infrastructure/display/DeviceMetricsProvider';
import { FloatingCandidateWindowController } from './FloatingCandidateWindowController';
import { Action, KeyEvent } from '@kit.InputKit';
import { KeyboardController } from './KeyboardController';
import {
  PhysicalKeyCommandType,
  PhysicalKeyConsumptionTracker,
  PhysicalEditorSuffixTracker,
  PhysicalKeySnapshot,
  resolveUnmodifiedPhysicalLetter,
  resolvePhysicalKeyCommand
} from '../domain/keyboard/PhysicalKeyboardRouting';
import {
  DELETE_ACTION,
  INSERT_SEGMENT_BOUNDARY_ACTION,
  KeyboardAction,
  KeyboardActionType
} from '../domain/keyboard/KeyboardAction';
import { resolveSymbolGuide } from '../domain/keyboard/SymbolGuideMap';
import {
  InputPresentationMode,
  InputPresentationPreference,
  InputPresentationState,
  readyStateForMode
} from '../domain/display/InputPresentationMode';
import {
  HarmonyInputPresentationModeProvider,
  InputPresentationModeProvider
} from '../infrastructure/ime/InputPresentationModeProvider';
import { SoftKeyboardPanelOwnershipCoordinator } from './SoftKeyboardPanelOwnershipCoordinator';
import {
  PhysicalKeyboardMonitor,
  PhysicalKeyboardStateProvider
} from '../infrastructure/ime/PhysicalKeyboardMonitor';
import { getSharedSettingsStore, SettingsStore } from '../state/SettingsStore';
import { DirectControlService, getSharedDirectControlService } from './DirectControlService';
import { resolveDirectControlHotkey } from '../domain/direct/DirectControlCommand';
import { InputMethodSecurityModeProvider } from '../infrastructure/security/InputMethodSecurityModeProvider';
import {
  isSmartPunctuationEnabled,
  smartPunctuationTarget
} from '../domain/keyboard/SmartPunctuation';

const TAG = 'InputMethodLifecycle';
const LOGGER = new Logger(TAG);

export class InputMethodLifecycleDispatcher {
  private readonly sessionController: InputSessionController;
  private readonly panelController: InputPanelController;
  private readonly deviceMetricsProvider: DeviceMetricsProvider;
  private readonly floatingCandidateController: FloatingCandidateWindowController;
  private readonly physicalKeyboardController: KeyboardController;
  private readonly presentationModeProvider: InputPresentationModeProvider;
  private readonly settingsStore: SettingsStore;
  private readonly physicalKeyboard: PhysicalKeyboardStateProvider;
  private readonly directControl: DirectControlService;
  private readonly securityModeProvider: InputMethodSecurityModeProvider;
  private imeAbility?: inputMethodEngine.InputMethodAbility;
  private presentationMode: InputPresentationMode = InputPresentationMode.TOUCH;
  private presentationState: InputPresentationState = InputPresentationState.INACTIVE;
  private readonly physicalKeyConsumption = new PhysicalKeyConsumptionTracker();
  private readonly physicalEditorSuffix = new PhysicalEditorSuffixTracker();
  private pendingPhysicalOperationCount: number = 0;
  private physicalOperationGeneration: number = 0;
  private inputActive: boolean = false;
  private symbolGuideActive: boolean = false;
  private lastPhysicalSmartPunctuationTarget?: string;
  private lastPhysicalSmartPunctuationTimestampMs?: number;
  private readonly onSettingsChanged = (): void => this.reconcilePresentationMode('settings');
  private readonly onPhysicalKeyboardChanged = (_present: boolean): void => {
    this.reconcilePresentationMode('physicalKeyboard');
  };

  constructor(
    sessionController: InputSessionController = new InputSessionController(),
    panelController?: InputPanelController,
    deviceMetricsProvider: DeviceMetricsProvider = new HarmonyDeviceMetricsProvider(),
    floatingCandidateController?: FloatingCandidateWindowController,
    presentationModeProvider: InputPresentationModeProvider = new HarmonyInputPresentationModeProvider(),
    panelOwnershipCoordinator: SoftKeyboardPanelOwnershipCoordinator =
      new SoftKeyboardPanelOwnershipCoordinator(),
    settingsStore: SettingsStore = getSharedSettingsStore(),
    physicalKeyboard: PhysicalKeyboardStateProvider = new PhysicalKeyboardMonitor(),
    directControl: DirectControlService = getSharedDirectControlService(),
    securityModeProvider: InputMethodSecurityModeProvider = new InputMethodSecurityModeProvider()
  ) {
    this.sessionController = sessionController;
    this.panelController = panelController ?? new InputPanelController(sessionController);
    this.deviceMetricsProvider = deviceMetricsProvider;
    this.floatingCandidateController = floatingCandidateController ??
      new FloatingCandidateWindowController(sessionController);
    this.panelController.bindOwnershipCoordinator(panelOwnershipCoordinator);
    this.floatingCandidateController.bindOwnershipCoordinator(panelOwnershipCoordinator);
    this.presentationModeProvider = presentationModeProvider;
    this.settingsStore = settingsStore;
    this.physicalKeyboard = physicalKeyboard;
    this.directControl = directControl;
    this.securityModeProvider = securityModeProvider;
    this.physicalKeyboardController = new KeyboardController(sessionController);
  }

  async handleAbilityCreate(
    imeAbility: inputMethodEngine.InputMethodAbility,
    context: InputMethodExtensionContext,
    settingsReady?: Promise<ImeSettings>
  ): Promise<void> {
    this.imeAbility = imeAbility;
    const capabilityState = this.securityModeProvider.probe(imeAbility, false, false);
    await this.sessionController.handleAbilityCreated(context, settingsReady, capabilityState);
    this.refreshScreenMetrics(undefined, 'abilityCreate');
    this.panelController.bindAbility(imeAbility, context, settingsReady);
    this.floatingCandidateController.bindAbility(imeAbility, context);
    this.settingsStore.subscribe(this.onSettingsChanged);
    this.physicalKeyboard.start(this.onPhysicalKeyboardChanged);
    LOGGER.info('ability lifecycle created');
  }

  handleInputStart(
    keyboardController: inputMethodEngine.KeyboardController,
    inputClient: inputMethodEngine.InputClient
  ): void {
    if (this.imeAbility) {
      this.sessionController.setInputMethodCapabilityState(
        this.securityModeProvider.probe(this.imeAbility, false, false)
      );
    }
    this.resetPhysicalKeyState();
    this.refreshScreenMetrics(undefined, 'inputStart');
    this.sessionController.handleInputStart(keyboardController, inputClient);
    this.inputActive = true;
    this.presentationMode = this.resolvePresentationMode();
    this.presentationState = readyStateForMode(this.presentationMode);
    this.panelController.handleInputStart(this.presentationMode);
    this.floatingCandidateController.handleInputStart(this.presentationMode);
    const state = this.sessionController.getState();
    LOGGER.info(
      `input presentation ready: mode=${this.presentationMode}, state=${this.presentationState}, ` +
        `sessionActive=${state.sessionActive}, editorConnected=${state.editorConnected}, ` +
        `keyboardVisible=${state.keyboardVisible}`
    );
  }

  handleInputStop(): void {
    this.resetPhysicalKeyState();
    this.sessionController.handleInputStop();
    this.panelController.handleInputStop();
    this.floatingCandidateController.handleInputStop();
    this.inputActive = false;
    this.presentationState = InputPresentationState.INACTIVE;
  }

  handleKeyboardShow(): void {
    if (this.presentationMode === InputPresentationMode.HARDWARE) {
      LOGGER.info('keyboardShow ignored in HARDWARE_READY');
      return;
    }
    this.panelController.showKeyboardPanel();
    this.floatingCandidateController.handleKeyboardShow();
  }

  handleKeyboardHide(): void {
    if (this.presentationMode === InputPresentationMode.HARDWARE) {
      // The fixed panel is intentionally non-destructive in hardware mode, but
      // assist results must never survive a platform keyboard-hide boundary.
      this.sessionController.cancelAssistForLifecycle();
      LOGGER.info('keyboardHide ignored in HARDWARE_READY; composition preserved');
      return;
    }
    this.sessionController.handleKeyboardHide();
    this.panelController.hideKeyboardPanel();
    this.floatingCandidateController.handleKeyboardHide();
  }

  handleDiscardTypingText(): void {
    this.sessionController.handleDiscardTypingText();
  }

  handleAbilityDestroy(): void {
    this.resetPhysicalKeyState();
    this.panelController.destroyPanel();
    this.floatingCandidateController.destroy();
    this.settingsStore.unsubscribe(this.onSettingsChanged);
    this.physicalKeyboard.stop();
    this.physicalKeyboardController.dispose();
    this.sessionController.handleAbilityDestroyed();
    this.imeAbility = undefined;
    this.inputActive = false;
    this.presentationState = InputPresentationState.INACTIVE;
    LOGGER.info('ability lifecycle destroyed');
  }

  handleConfigurationUpdate(preferredIsLandscape?: boolean): void {
    this.refreshScreenMetrics(preferredIsLandscape, 'configurationUpdate');
    this.floatingCandidateController.handleConfigurationUpdate();
  }

  handleCursorContextChange(x: number, y: number, height: number): void {
    this.floatingCandidateController.handleCursorContextChange(x, y, height);
  }

  handlePhysicalKeyEvent(event: KeyEvent): boolean {
    return this.handlePhysicalKeySnapshot({
      isDown: event.action === Action.DOWN,
      unicodeChar: event.unicodeChar,
      keyCode: event.key.code,
      ctrlKey: event.ctrlKey,
      altKey: event.altKey,
      logoKey: event.logoKey,
      shiftKey: event.shiftKey
    });
  }

  handleDeferredPhysicalKeyEvent(key: PhysicalKeySnapshot): void {
    const handled = this.handlePhysicalKeySnapshot(key);
    if (handled || !key.isDown) {
      return;
    }
    // The letter was synchronously consumed while the runtime was cold. If the
    // bound editor later resolves to English/password passthrough, explicitly
    // restore that literal once instead of losing it.
    const character = resolveUnmodifiedPhysicalLetter(key);
    if (character !== undefined) {
      this.observePhysicalOperation(
        this.physicalKeyboardController.insertDeferredPhysicalCharacter(character)
      );
    }
  }

  handlePhysicalKeySnapshot(key: PhysicalKeySnapshot): boolean {
    if (!key.isDown) {
      return this.physicalKeyConsumption.consumeRelease(key.keyCode);
    }
    const directCommand = resolveDirectControlHotkey(
      key.keyCode,
      key.ctrlKey,
      key.altKey,
      key.logoKey
    );
    if (directCommand !== undefined) {
      this.clearPhysicalSmartPunctuation();
      this.physicalKeyboardController.noteExternalInputAction();
      this.physicalKeyConsumption.recordConsumedDown(key.keyCode);
      LOGGER.info(`direct hotkey consumed: action=${directCommand.action}, target=${directCommand.target}`);
      this.observePhysicalOperation(this.directControl.execute(directCommand).then((result): Object => {
        if (!result.success) {
          LOGGER.warn(`direct hotkey failed: ${result.message}`);
        }
        return result;
      }));
      return true;
    }
    const state = this.sessionController.getState();
    const rapidPhysicalContinuation = this.pendingPhysicalOperationCount > 0;
    const keyTimestampMs = Date.now();
    if (state.rawInput.length === 0 && this.pendingPhysicalOperationCount === 0) {
      this.physicalEditorSuffix.reset();
    }
    const command = resolvePhysicalKeyCommand(key, {
      sessionActive: state.sessionActive,
      editorConnected: state.editorConnected,
      chineseInputAllowed: state.editorContext.chineseModeAllowed && !state.editorContext.isPassword,
      candidateBarVisible: state.candidateBarVisible,
      keyboardMode: state.keyboardMode,
      rawInput: state.rawInput,
      candidateCount: state.candidates.length,
      compositionPending: rapidPhysicalContinuation,
      pairJumpAvailable: this.sessionController.canJumpOutPair(),
      smartPunctuationContinuation: this.continuingPhysicalSmartPunctuation(keyTimestampMs)
    });

    if (command.type === PhysicalKeyCommandType.NONE) {
      this.symbolGuideActive = false;
      this.clearPhysicalSmartPunctuation();
      this.physicalKeyboardController.noteExternalInputAction();
      return false;
    }
    const physicalPunctuationWillReplace = command.type === PhysicalKeyCommandType.PUNCTUATION
      ? this.willReplacePhysicalSmartPunctuation(command.character ?? '', keyTimestampMs)
      : false;
    if (command.type !== PhysicalKeyCommandType.PUNCTUATION) {
      this.clearPhysicalSmartPunctuation();
    }
    if (command.type === PhysicalKeyCommandType.DELETE &&
      this.physicalEditorSuffix.consumePunctuationDelete()) {
      LOGGER.info(`physical punctuation delete consumed: keyCode=${key.keyCode}`);
      this.physicalKeyConsumption.recordConsumedDown(key.keyCode);
      this.observePhysicalOperation(this.physicalKeyboardController.deletePhysicalPunctuationSuffix());
      return true;
    }
    LOGGER.debug(`physical key consumed: type=${command.type}, keyCode=${key.keyCode}`);
    this.physicalKeyConsumption.recordConsumedDown(key.keyCode);
    const isPlainSemicolon = key.unicodeChar === 59 ||
      (key.unicodeChar === 0 && key.keyCode === 2062 && key.shiftKey !== true);
    const isSemicolonCommand = command.type === PhysicalKeyCommandType.CANDIDATE ||
      command.type === PhysicalKeyCommandType.SECOND_CANDIDATE ||
      command.type === PhysicalKeyCommandType.SYMBOL_GUIDE;
    if (isPlainSemicolon && isSemicolonCommand &&
      this.settingsStore.getSnapshot().schemeId === XIAOHE_YINXING_SCHEME_ID) {
      this.symbolGuideActive = false;
      this.observePhysicalOperation(this.physicalKeyboardController.handlePhysicalCodeTableSemicolon());
      LOGGER.info('code-table semicolon queued for live candidate resolution');
      return true;
    }
    // Symbol guide: if active, the next LETTER resolves to a symbol
    if (this.symbolGuideActive && command.type === PhysicalKeyCommandType.LETTER) {
      this.symbolGuideActive = false;
      const symbol = resolveSymbolGuide(command.letter ?? '');
      if (symbol) {
        LOGGER.info(`symbol guide resolved: letter=${command.letter}, symbol=${symbol}`);
        this.observePhysicalOperation(this.physicalKeyboardController.insertSymbol(symbol));
        return true;
      }
      // No mapping found: fall through to normal letter handling
      this.observePhysicalOperation(
        this.physicalKeyboardController.handlePhysicalLetter(command.letter, rapidPhysicalContinuation)
      );
      return true;
    }
    if (command.type !== PhysicalKeyCommandType.SYMBOL_GUIDE) {
      this.symbolGuideActive = false;
    }
    if (command.type === PhysicalKeyCommandType.CANDIDATE) {
      // Semicolon with a single candidate: commit it and arm the symbol guide
      const isSemicolonSingleCandidate = isPlainSemicolon &&
        state.candidates.length === 1;
      this.observePhysicalOperation(this.physicalKeyboardController.commitCandidate(command.candidateIndex ?? 0));
      if (isSemicolonSingleCandidate) {
        if (this.settingsStore.getSnapshot().schemeId === XIAOHE_YINXING_SCHEME_ID) {
          this.observePhysicalOperation(this.physicalKeyboardController.handlePhysicalGuideSemicolon());
          LOGGER.info('code-table symbol guide activated after semicolon single-candidate commit');
        } else {
          this.symbolGuideActive = true;
          LOGGER.info('symbol guide mode activated after semicolon single-candidate commit');
        }
      }
      return true;
    }
    if (command.type === PhysicalKeyCommandType.SECOND_CANDIDATE) {
      this.observePhysicalOperation(this.physicalKeyboardController.commitCandidate(command.candidateIndex ?? 1));
      return true;
    }
    if (command.type === PhysicalKeyCommandType.THIRD_CANDIDATE) {
      this.observePhysicalOperation(this.physicalKeyboardController.commitCandidate(command.candidateIndex ?? 2));
      return true;
    }
    if (command.type === PhysicalKeyCommandType.SYMBOL_GUIDE) {
      if (this.settingsStore.getSnapshot().schemeId === XIAOHE_YINXING_SCHEME_ID) {
        this.symbolGuideActive = false;
        this.observePhysicalOperation(this.physicalKeyboardController.handlePhysicalGuideSemicolon());
        LOGGER.info('code-table symbol guide key routed to engine');
      } else {
        this.symbolGuideActive = true;
        LOGGER.info('symbol guide mode activated');
      }
      return true;
    }
    if (command.type === PhysicalKeyCommandType.CANCEL) {
      this.observePhysicalOperation(this.physicalKeyboardController.cancelPhysicalComposition());
      return true;
    }
    if (command.type === PhysicalKeyCommandType.JUMP_OUT_PAIR) {
      this.observePhysicalOperation(this.physicalKeyboardController.jumpOutPhysicalPair());
      return true;
    }
    if (command.type === PhysicalKeyCommandType.SELECT_PREVIOUS) {
      this.observePhysicalOperation(this.physicalKeyboardController.selectPreviousHardwareCandidate());
      return true;
    }
    if (command.type === PhysicalKeyCommandType.SELECT_NEXT) {
      this.observePhysicalOperation(this.physicalKeyboardController.selectNextHardwareCandidate());
      return true;
    }
    if (command.type === PhysicalKeyCommandType.PREVIOUS_PAGE) {
      this.observePhysicalOperation(this.physicalKeyboardController.previousHardwareCandidatePage());
      return true;
    }
    if (command.type === PhysicalKeyCommandType.NEXT_PAGE) {
      this.observePhysicalOperation(this.physicalKeyboardController.nextHardwareCandidatePage());
      return true;
    }
    if (command.type === PhysicalKeyCommandType.PUNCTUATION) {
      if (!physicalPunctuationWillReplace) {
        this.physicalEditorSuffix.recordPunctuation();
      }
      this.observePhysicalOperation(
        this.physicalKeyboardController.insertPhysicalPunctuation(command.character ?? '')
      );
      return true;
    }
    let action: KeyboardAction;
    if (command.type === PhysicalKeyCommandType.LETTER) {
      this.observePhysicalOperation(
        this.physicalKeyboardController.handlePhysicalLetter(command.letter, rapidPhysicalContinuation)
      );
      return true;
    } else if (command.type === PhysicalKeyCommandType.DELETE) {
      action = DELETE_ACTION;
    } else if (command.type === PhysicalKeyCommandType.SPACE) {
      this.observePhysicalOperation(this.physicalKeyboardController.handlePhysicalSpace());
      return true;
    } else if (command.type === PhysicalKeyCommandType.ENTER) {
      this.observePhysicalOperation(this.physicalKeyboardController.handlePhysicalEnter());
      return true;
    } else {
      action = INSERT_SEGMENT_BOUNDARY_ACTION;
    }
    this.observePhysicalOperation(this.physicalKeyboardController.handleAction(action));
    return true;
  }

  getPresentationMode(): InputPresentationMode {
    return this.presentationMode;
  }

  getPresentationState(): InputPresentationState {
    return this.presentationState;
  }

  private observePhysicalOperation(operation: Promise<Object>): void {
    const generation = this.physicalOperationGeneration;
    this.pendingPhysicalOperationCount += 1;
    operation.then((): void => {
      this.completePhysicalOperation(generation);
    }, (err: Object): void => {
      this.completePhysicalOperation(generation);
      LOGGER.warn(`physical keyboard operation failed: ${JSON.stringify(err)}`);
    });
  }

  private completePhysicalOperation(generation: number): void {
    if (generation === this.physicalOperationGeneration) {
      this.pendingPhysicalOperationCount = Math.max(0, this.pendingPhysicalOperationCount - 1);
    }
  }

  private resetPhysicalKeyState(): void {
    this.physicalOperationGeneration += 1;
    this.physicalKeyConsumption.reset();
    this.physicalEditorSuffix.reset();
    this.clearPhysicalSmartPunctuation();
    this.pendingPhysicalOperationCount = 0;
  }

  private willReplacePhysicalSmartPunctuation(character: string, timestampMs: number): boolean {
    const settings = this.settingsStore.getSnapshot();
    const target = smartPunctuationTarget(character);
    if (target === undefined || settings.punctuationMode !== PunctuationMode.CHINESE ||
      settings.smartPeriodTimeoutMs <= 0 ||
      !isSmartPunctuationEnabled(settings.smartPunctuationSymbols, target)) {
      this.clearPhysicalSmartPunctuation();
      return false;
    }
    const previousTimestamp = this.lastPhysicalSmartPunctuationTimestampMs;
    if (this.lastPhysicalSmartPunctuationTarget === target && previousTimestamp !== undefined &&
      timestampMs >= previousTimestamp && timestampMs - previousTimestamp <= settings.smartPeriodTimeoutMs) {
      this.clearPhysicalSmartPunctuation();
      return true;
    }
    this.lastPhysicalSmartPunctuationTarget = target;
    this.lastPhysicalSmartPunctuationTimestampMs = timestampMs;
    return false;
  }

  private continuingPhysicalSmartPunctuation(timestampMs: number): string | undefined {
    const settings = this.settingsStore.getSnapshot();
    const previousTimestamp = this.lastPhysicalSmartPunctuationTimestampMs;
    const target = this.lastPhysicalSmartPunctuationTarget;
    if (target === undefined || previousTimestamp === undefined ||
      settings.punctuationMode !== PunctuationMode.CHINESE || settings.smartPeriodTimeoutMs <= 0 ||
      !isSmartPunctuationEnabled(settings.smartPunctuationSymbols, target) ||
      timestampMs < previousTimestamp || timestampMs - previousTimestamp > settings.smartPeriodTimeoutMs) {
      return undefined;
    }
    return target;
  }

  private clearPhysicalSmartPunctuation(): void {
    this.lastPhysicalSmartPunctuationTarget = undefined;
    this.lastPhysicalSmartPunctuationTimestampMs = undefined;
  }

  private resolvePresentationMode(): InputPresentationMode {
    const preference = this.settingsStore.getSnapshot().inputPresentationPreference ??
      InputPresentationPreference.AUTO;
    return this.presentationModeProvider.resolve(preference, this.physicalKeyboard.isPresent());
  }

  private reconcilePresentationMode(source: string): void {
    if (!this.inputActive) {
      return;
    }
    const next = this.resolvePresentationMode();
    if (next === this.presentationMode) {
      return;
    }
    const previous = this.presentationMode;
    this.presentationMode = next;
    this.presentationState = readyStateForMode(next);
    this.panelController.handlePresentationModeChange(next);
    this.floatingCandidateController.handlePresentationModeChange(next);
    LOGGER.info(
      `input presentation switched: source=${source}, previous=${previous}, mode=${next}, ` +
        `state=${this.presentationState}, physicalKeyboard=${this.physicalKeyboard.isPresent()}`
    );
  }

  private refreshScreenMetrics(preferredIsLandscape: boolean | undefined, source: string): void {
    const metrics = this.deviceMetricsProvider.getMetrics(preferredIsLandscape);
    this.sessionController.setScreenMetrics(metrics);
    LOGGER.info(
      `screen metrics updated: source=${source}, isLandscape=${metrics.isLandscape}, ` +
      `widthPx=${metrics.widthPx}, heightPx=${metrics.heightPx}, density=${metrics.densityPixels}`
    );
  }
}
