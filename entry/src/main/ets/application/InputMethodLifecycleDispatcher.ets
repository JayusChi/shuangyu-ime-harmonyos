import { inputMethodEngine, InputMethodExtensionContext } from '@kit.IMEKit';
import { Logger } from '../common/logging/Logger';
import { InputPanelController } from './InputPanelController';
import { InputSessionController } from './InputSessionController';
import { ImeSettings } from '../domain/settings/ImeSettings';
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
  private presentationMode: InputPresentationMode = InputPresentationMode.TOUCH;
  private presentationState: InputPresentationState = InputPresentationState.INACTIVE;
  private readonly physicalKeyConsumption = new PhysicalKeyConsumptionTracker();
  private readonly physicalEditorSuffix = new PhysicalEditorSuffixTracker();
  private pendingPhysicalOperationCount: number = 0;
  private physicalOperationGeneration: number = 0;
  private inputActive: boolean = false;
  private symbolGuideActive: boolean = false;
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
    directControl: DirectControlService = getSharedDirectControlService()
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
    this.physicalKeyboardController = new KeyboardController(sessionController);
  }

  async handleAbilityCreate(
    imeAbility: inputMethodEngine.InputMethodAbility,
    context: InputMethodExtensionContext,
    settingsReady?: Promise<ImeSettings>
  ): Promise<void> {
    await this.sessionController.handleAbilityCreated(context, settingsReady);
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
    if (event.action !== Action.DOWN) {
      return this.physicalKeyConsumption.consumeRelease(event.key.code);
    }
    const directCommand = resolveDirectControlHotkey(
      event.key.code,
      event.ctrlKey,
      event.altKey,
      event.logoKey
    );
    if (directCommand !== undefined) {
      this.physicalKeyConsumption.recordConsumedDown(event.key.code);
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
    if (state.rawInput.length === 0 && this.pendingPhysicalOperationCount === 0) {
      this.physicalEditorSuffix.reset();
    }
    const command = resolvePhysicalKeyCommand({
      isDown: event.action === Action.DOWN,
      unicodeChar: event.unicodeChar,
      keyCode: event.key.code,
      ctrlKey: event.ctrlKey,
      altKey: event.altKey,
      logoKey: event.logoKey
    }, {
      sessionActive: state.sessionActive,
      editorConnected: state.editorConnected,
      chineseInputAllowed: state.editorContext.chineseModeAllowed && !state.editorContext.isPassword,
      candidateBarVisible: state.candidateBarVisible,
      keyboardMode: state.keyboardMode,
      rawInput: state.rawInput,
      candidateCount: state.candidates.length,
      compositionPending: rapidPhysicalContinuation
    });

    if (command.type === PhysicalKeyCommandType.NONE) {
      this.symbolGuideActive = false;
      return false;
    }
    if (command.type === PhysicalKeyCommandType.DELETE &&
      this.physicalEditorSuffix.consumePunctuationDelete()) {
      LOGGER.info(`physical punctuation delete consumed: keyCode=${event.key.code}`);
      this.physicalKeyConsumption.recordConsumedDown(event.key.code);
      this.observePhysicalOperation(this.physicalKeyboardController.deletePhysicalPunctuationSuffix());
      return true;
    }
    LOGGER.debug(`physical key consumed: type=${command.type}, keyCode=${event.key.code}`);
    this.physicalKeyConsumption.recordConsumedDown(event.key.code);
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
      const isSemicolonSingleCandidate = event.unicodeChar === 59 && state.candidates.length === 1;
      this.observePhysicalOperation(this.physicalKeyboardController.commitCandidate(command.candidateIndex ?? 0));
      if (isSemicolonSingleCandidate) {
        this.symbolGuideActive = true;
        LOGGER.info('symbol guide mode activated after semicolon single-candidate commit');
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
      this.symbolGuideActive = true;
      LOGGER.info('symbol guide mode activated');
      return true;
    }
    if (command.type === PhysicalKeyCommandType.CANCEL) {
      this.observePhysicalOperation(this.physicalKeyboardController.cancelPhysicalComposition());
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
      this.physicalEditorSuffix.recordPunctuation();
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
    this.pendingPhysicalOperationCount = 0;
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
