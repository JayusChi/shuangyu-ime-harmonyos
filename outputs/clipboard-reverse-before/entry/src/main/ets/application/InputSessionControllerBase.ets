import { inputMethodEngine, InputMethodExtensionContext } from '@kit.IMEKit';
import { Want } from '@kit.AbilityKit';
import { ImeErrorCode } from '../common/error/ImeError';
import { Logger } from '../common/logging/Logger';
import {
  EditorContext,
  EditorKind,
  EnterAction,
  EDITOR_KIND_EXTRA_CONFIG_KEY
} from '../domain/editor/EditorContext';
import { KeyboardMode, isSingleAsciiLetter, isT9PinyinDigit } from '../domain/keyboard/KeyboardAction';
import { transformDirectText } from '../domain/keyboard/DirectTextTransformer';
import {
  ImeSettings,
  PINYIN_9_SCHEME_ID,
  XIAOHE_YINXING_SCHEME_ID
} from '../domain/settings/ImeSettings';
import { EditorAttributeMapper } from '../infrastructure/ime/EditorAttributeMapper';
import { ImeConnectionService } from '../infrastructure/ime/ImeConnectionService';
import {
  getSharedInputSessionStore,
  InputSessionState,
  InputSessionStateListener,
  InputSessionStore
} from '../state/InputSessionStore';
import { EngineCoordinator, getSharedEngineCoordinator } from './EngineCoordinator';
import { inputOperationFailed, inputOperationOk, InputOperationResult } from './InputOperationResult';
import { LexiconResourceInstaller } from '../infrastructure/resource/LexiconResourceInstaller';
import {
  QUANPIN_CONTEXT_MODEL_SHA256,
  QuanpinContextModelResourceInstaller
} from '../infrastructure/resource/QuanpinContextModelResourceInstaller';
import { YinxingBundleInstaller } from '../infrastructure/resource/YinxingBundleInstaller';
import { UserModelPathProvider } from '../infrastructure/storage/UserModelPathProvider';
import { UserLexiconPathProvider } from '../infrastructure/storage/UserLexiconPathProvider';
import { SettingsController, getSharedSettingsController } from './SettingsController';
import { initializeSharedKeySoundBackend } from '../infrastructure/audio/KeySoundService';
import { UserModelCommandRepository } from '../infrastructure/storage/UserModelCommandRepository';
import { UserModelCommandBus } from '../infrastructure/storage/UserModelCommandBus';
import { UserLexiconSyncBus } from '../infrastructure/storage/UserLexiconSyncBus';
import { Candidate, CompositionResult, NativeEngineGatewayContract } from '../infrastructure/native/NativeEngineTypes';
import { UserLexiconImportManager } from './UserLexiconImportManager';
import { NativeEngineGateway } from '../infrastructure/native/NativeEngineGateway';
import {
  ProtocolActionImeService,
  ProtocolActionHandlers,
  ProtocolActionExecutionStatus,
  ProtocolActionExecutor
} from './ProtocolActionExecutor';
import { SystemTimeProvider } from '../infrastructure/time/TimeProvider';
import { ScreenMetricsPx, withBottomSystemInset } from '../domain/display/ScreenMetrics';
import { getEngineInitializationOverride } from './EngineInitializationOverride';
import {
  getSharedInputMethodSwitcher,
  InputMethodSwitchCapabilities,
  InputMethodSwitcher,
  InputMethodSwitchResult,
  InputMethodSwitchResultType
} from '../infrastructure/ime/InputMethodSwitcher';
import { CommitHistoryManager } from './CommitHistoryManager';
import { UndoCommitManager } from './UndoCommitManager';
import { UserLexiconDocumentEditor } from './UserLexiconController';
import { DirectControlService } from './DirectControlService';
import {
  DirectSessionActionResult,
  DirectSessionActionService,
  DirectAbilityLauncher,
  getSharedDirectAbilityLaunchers
} from './DirectSessionActionService';

import { ShapeLookupService } from './ShapeLookupService';
import { SHAPE_LOOKUP_CODE, SHAPE_LOOKUP_TARGET, SHAPE_LOOKUP_LABEL } from '../domain/direct/ShapeLookup';
import { ImeInputService } from './ImeInputService';
import { SmartPeriodController, SmartPeriodInputAction } from './SmartPeriodController';
import { AiAction } from '../domain/ai/AiContracts';
import {
  AssistAvailability,
  InputMethodCapabilityState,
  resolveAssistAvailability
} from '../domain/security/InputMethodCapabilityState';
import { AiProvider } from '../infrastructure/ai/AiProvider';
import { UnavailableAiProvider } from '../infrastructure/ai/UnavailableAiProvider';
import { SpeechRecognitionProvider } from '../infrastructure/speech/SpeechRecognitionProvider';
import { UnavailableSpeechProvider } from '../infrastructure/speech/UnavailableSpeechProvider';
import { AiAssistController } from './AiAssistController';
import { VoiceInputController } from './VoiceInputController';
import { VerifiedTextReplacer } from './VerifiedTextReplacer';
import {
  LocalAssociationSuggestion,
  normalizeLocalAssociations
} from '../domain/ai/LocalAssociationContracts';

const TAG = 'InputSessionController';
const LOGGER = new Logger(TAG);

class SessionProtocolActionHandlers implements ProtocolActionHandlers {
  private readonly repeatHandler: (generation: number) => Promise<boolean>;
  private readonly undoHandler: (generation: number) => Promise<boolean>;
  private readonly directControlHandler: (action: string, target: string, generation: number) => Promise<boolean>;
  private readonly importUserLexiconHandler: (generation: number) => Promise<boolean>;

  constructor(
    repeatHandler: (generation: number) => Promise<boolean>,
    undoHandler: (generation: number) => Promise<boolean>,
    directControlHandler: (action: string, target: string, generation: number) => Promise<boolean>,
    importUserLexiconHandler: (generation: number) => Promise<boolean>
  ) {
    this.repeatHandler = repeatHandler;
    this.undoHandler = undoHandler;
    this.directControlHandler = directControlHandler;
    this.importUserLexiconHandler = importUserLexiconHandler;
  }

  repeatLastCommit(generation: number): Promise<boolean> {
    return this.repeatHandler(generation);
  }

  undoLastCommit(generation: number): Promise<boolean> {
    return this.undoHandler(generation);
  }

  executeDirectControl(action: string, target: string, generation: number): Promise<boolean> {
    return this.directControlHandler(action, target, generation);
  }

  importUserLexicon(generation: number): Promise<boolean> {
    return this.importUserLexiconHandler(generation);
  }
}

class InputMethodDirectAbilityLauncher implements DirectAbilityLauncher {
  private readonly context: InputMethodExtensionContext;

  constructor(context: InputMethodExtensionContext) { this.context = context; }
  async startAbility(want: Want): Promise<void> {
    await this.context.startAbility(want);
  }
}

export class InputSessionControllerBase {
  protected readonly store: InputSessionStore;
  protected readonly imeService: ImeInputService;
  protected readonly engineCoordinator: EngineCoordinator;
  protected readonly lexiconInstaller: LexiconResourceInstaller;
  protected readonly userModelPathProvider: UserModelPathProvider;
  protected readonly userLexiconPathProvider: UserLexiconPathProvider;
  protected readonly editorAttributeMapper: EditorAttributeMapper;
  protected readonly settingsController: SettingsController;
  protected readonly inputMethodSwitcher: InputMethodSwitcher;
  protected readonly quanpinContextModelInstaller: QuanpinContextModelResourceInstaller;
  protected readonly smartPeriodController: SmartPeriodController;
  protected readonly aiAssistController: AiAssistController;
  protected readonly voiceInputController: VoiceInputController;
  protected userModelPath?: string;
  protected userLexiconPath?: string;
  protected abilityContext?: InputMethodExtensionContext;
  private abilityLauncher?: DirectAbilityLauncher;
  protected readonly userModelCommands: UserModelCommandRepository = new UserModelCommandRepository();
  protected readonly userModelCommandBus: UserModelCommandBus = new UserModelCommandBus();
  protected readonly userLexiconSyncBus: UserLexiconSyncBus = new UserLexiconSyncBus();
  protected readonly userLexiconGateway: NativeEngineGatewayContract = new NativeEngineGateway();
  protected isCandidateCommitInProgress: boolean = false;
  protected isHideKeyboardInProgress: boolean = false;
  protected readonly protocolActionExecutor: ProtocolActionExecutor;
  protected readonly commitHistoryManager: CommitHistoryManager = new CommitHistoryManager();
  protected undoCommitManager?: UndoCommitManager;
  protected readonly lexiconImportManager: UserLexiconImportManager = new UserLexiconImportManager();
  protected readonly directControlService: DirectControlService;
  protected readonly directSessionActionService: DirectSessionActionService;
  protected readonly shapeLookupService: ShapeLookupService = new ShapeLookupService();
  private shapeLookupGeneration: number = -1;
  private shapeLookupText: string = '';
  protected readonly onEditorAttributeChanged = (attribute: inputMethodEngine.EditorAttribute): void => {
    this.handleEditorAttributeChanged(attribute);
  };
  protected readonly onAssistSettingsChanged = (): void => {
    this.reconcileAssistAvailability();
  };

  constructor(
    store: InputSessionStore = getSharedInputSessionStore(),
    imeService: ImeInputService = new ImeConnectionService(),
    engineCoordinator: EngineCoordinator = getSharedEngineCoordinator(),
    lexiconInstaller: LexiconResourceInstaller = new LexiconResourceInstaller(),
    userModelPathProvider: UserModelPathProvider = new UserModelPathProvider(),
    editorAttributeMapper: EditorAttributeMapper = new EditorAttributeMapper(),
    settingsController: SettingsController = getSharedSettingsController(),
    userLexiconPathProvider: UserLexiconPathProvider = new UserLexiconPathProvider(),
    inputMethodSwitcher: InputMethodSwitcher = getSharedInputMethodSwitcher(),
    quanpinContextModelInstaller: QuanpinContextModelResourceInstaller =
      new QuanpinContextModelResourceInstaller(),
    smartPeriodController: SmartPeriodController = new SmartPeriodController(),
    aiProvider: AiProvider = new UnavailableAiProvider(),
    speechProvider: SpeechRecognitionProvider = new UnavailableSpeechProvider()
  ) {
    this.store = store;
    this.imeService = imeService;
    this.engineCoordinator = engineCoordinator;
    this.lexiconInstaller = lexiconInstaller;
    this.userModelPathProvider = userModelPathProvider;
    this.editorAttributeMapper = editorAttributeMapper;
    this.settingsController = settingsController;
    this.userLexiconPathProvider = userLexiconPathProvider;
    this.inputMethodSwitcher = inputMethodSwitcher;
    this.quanpinContextModelInstaller = quanpinContextModelInstaller;
    this.smartPeriodController = smartPeriodController;
    this.directControlService = new DirectControlService(settingsController);
    this.directSessionActionService = new DirectSessionActionService(
      (): DirectAbilityLauncher | undefined => getSharedDirectAbilityLaunchers().get()
    );
    const actionHandlers: ProtocolActionHandlers = new SessionProtocolActionHandlers(
      (generation: number): Promise<boolean> => this.repeatLastCommit(generation),
      (generation: number): Promise<boolean> => this.undoLastCommit(generation),
      async (action: string, target: string, generation: number): Promise<boolean> => {
        if (!this.isInputSessionGenerationCurrent(generation)) {
          return false;
        }
        if (action === 'url.open' && target === SHAPE_LOOKUP_TARGET) {
          const state = this.store.getSnapshot();
          if (state.editorContext.isPassword || state.rawInput !== SHAPE_LOOKUP_CODE) { return false; }
          // The oix preedit belongs to the IME. Remove it before reading the committed
          // cursor context or handing focus to the browser/permission UI.
          if (!(await this.imeService.clearPreviewText(generation)) ||
            !this.isInputSessionGenerationCurrent(generation)) { return false; }
          let character = this.shapeLookupGeneration === generation ? this.shapeLookupText : '';
          if (character.length === 0) {
            let before = '';
            try { before = (await this.imeService.getTextBeforeCursor?.(4)) ?? ''; } catch (_) {}
            character = await this.shapeLookupService.resolve(before, '', false);
          }
          if (!this.isInputSessionGenerationCurrent(generation)) { return false; }
          this.store.clearComposition();
          this.shapeLookupGeneration = -1;
          this.shapeLookupText = '';
          return (await this.directSessionActionService.execute(action, target, character)).success;
        }
        if (action === 'editor.delete-line') {
          return target.length === 0 && (await this.deleteCurrentLine(generation)).success;
        }
        const sessionResult: DirectSessionActionResult =
          await this.directSessionActionService.execute(action, target);
        if (sessionResult.handled) {
          return this.isInputSessionGenerationCurrent(generation) && sessionResult.success;
        }
        const result = await this.directControlService.executeRaw(action, target);
        return this.isInputSessionGenerationCurrent(generation) && result.success;
      },
      (generation: number): Promise<boolean> => this.importConfiguredUserLexicon(generation)
    );
    this.protocolActionExecutor = new ProtocolActionExecutor(
      this.imeService,
      new SystemTimeProvider(),
      (generation: number): boolean => this.isInputSessionGenerationCurrent(generation),
      actionHandlers
    );
    this.undoCommitManager = new UndoCommitManager(this.commitHistoryManager);
    const verifiedTextReplacer = new VerifiedTextReplacer(
      this.imeService,
      (generation: number): boolean => this.isInputSessionGenerationCurrent(generation)
    );
    this.aiAssistController = new AiAssistController(
      this.store,
      (): ImeSettings => this.settingsController.getSettings(),
      aiProvider,
      verifiedTextReplacer,
      (): string | null => this.commitHistoryManager.getLastCommit(),
      (originalText: string, replacementText: string): void =>
        this.recordReplacedText(originalText, replacementText),
      8000,
      async (sourceText: string): Promise<boolean> =>
        this.imeService.textBeforeCursorMatches !== undefined &&
          await this.imeService.textBeforeCursorMatches(sourceText),
      async (): Promise<number | undefined> => this.imeService.getCursorIndex !== undefined
        ? await this.imeService.getCursorIndex() : undefined
    );
    this.voiceInputController = new VoiceInputController(
      this.store,
      (): ImeSettings => this.settingsController.getSettings(),
      speechProvider,
      this.imeService,
      (text: string): void => this.recordCommittedText(text)
    );
  }

  protected async refreshShapeLookupCandidate(generation: number): Promise<void> {
    const state = this.store.getSnapshot();
    if (state.rawInput !== SHAPE_LOOKUP_CODE || state.editorContext.isPassword ||
      !state.candidates.some((candidate: Candidate): boolean =>
        candidate.source === 'functional' && candidate.text === SHAPE_LOOKUP_LABEL)) {
      this.shapeLookupGeneration = -1;
      this.shapeLookupText = '';
      return;
    }
    let before = '';
    try { before = (await this.imeService.getTextBeforeCursor?.(8)) ?? ''; } catch (_) {}
    if (!this.isInputSessionGenerationCurrent(generation)) { return; }
    const character = await this.shapeLookupService.resolve(before, state.rawInput,
      this.imeService.isCursorPreviewActive?.() === true);
    if (!this.isInputSessionGenerationCurrent(generation) || this.store.getSnapshot().rawInput !== SHAPE_LOOKUP_CODE) { return; }
    this.shapeLookupText = character;
    this.shapeLookupGeneration = generation;
    this.store.setFunctionalCandidateDisplay(SHAPE_LOOKUP_LABEL,
      character.length > 0 ? '「查」：' + character : '「查」：剪贴板');
  }

  getState(): InputSessionState {
    return this.store.getSnapshot();
  }

  subscribe(listener: InputSessionStateListener): void {
    this.store.subscribe(listener);
  }

  unsubscribe(listener: InputSessionStateListener): void {
    this.store.unsubscribe(listener);
  }

  getInputSessionGeneration(): number {
    return this.store.getSessionGeneration();
  }

  beginInputAction(timestampMs: number = Date.now()): SmartPeriodInputAction {
    this.aiAssistController.invalidateForInput();
    this.voiceInputController.invalidateForInput();
    this.store.clearLocalAssociations();
    return this.smartPeriodController.beginInput(timestampMs);
  }

  isInputSessionGenerationCurrent(generation: number): boolean {
    return generation === this.store.getSessionGeneration();
  }

  canJumpOutPair(generation: number = this.getInputSessionGeneration()): boolean {
    const state = this.store.getSnapshot();
    return this.isInputSessionGenerationCurrent(generation) && state.sessionActive && state.editorConnected &&
      (this.imeService.hasPendingPair?.(generation) ?? false);
  }

  async jumpOutPair(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('pair jump');
    }
    const sessionCheck = this.ensureInputSession('pair jump');
    if (!sessionCheck.success) {
      return sessionCheck;
    }
    if (!this.imeService.jumpOutPair) {
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'pair jump is unavailable');
    }
    const jumped = await this.imeService.jumpOutPair(generation);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('pair jump completion');
    }
    if (jumped) {
      this.store.clearError();
      return inputOperationOk();
    }
    return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'pair jump target changed');
  }

  async handleAbilityCreated(
    context?: InputMethodExtensionContext,
    settingsReady?: Promise<ImeSettings>,
    capabilityState?: InputMethodCapabilityState
  ): Promise<void> {
    this.aiAssistController.cancel(false);
    this.voiceInputController.cancel(false);
    this.commitHistoryManager.clear();
    this.undoCommitManager?.clearUndoState();
    this.imeService.clearDeletionRecovery?.();
    this.inputMethodSwitcher.setSessionActive(false);
    this.abilityContext = context;
    if (context) {
      this.abilityLauncher = new InputMethodDirectAbilityLauncher(context);
      getSharedDirectAbilityLaunchers().bind(this.abilityLauncher);
    }
    this.store.resetAll();
    if (capabilityState) {
      this.store.setInputMethodCapabilityState(capabilityState);
    }
    ImeConnectionService.observeEditorAttributes(this.onEditorAttributeChanged);
    let lexiconPath: string | undefined = undefined;
    let userModelPath: string | undefined = undefined;
    let userLexiconPath: string | undefined = undefined;
    let quanpinContextModelPath: string | undefined = undefined;
    let installError = '';
    let loadedSettings: ImeSettings | undefined = undefined;
    if (context) {
      initializeSharedKeySoundBackend(context);
      const installResult = this.lexiconInstaller.installDefaultLexicon(context);
      if (installResult.success) {
        lexiconPath = installResult.path;
      } else {
        installError = installResult.errorMessage;
      }
      const contextModelResult = this.quanpinContextModelInstaller.install(context);
      if (contextModelResult.success) {
        quanpinContextModelPath = contextModelResult.path;
      } else {
        LOGGER.warn(`context reranking unavailable: ${contextModelResult.errorMessage}`);
      }
      const pathResult = this.userModelPathProvider.getUserModelPath(context);
      if (pathResult.success) {
        userModelPath = pathResult.path;
        this.userModelPath = pathResult.path;
      } else {
        LOGGER.warn(`user model path unavailable: ${pathResult.errorMessage}`);
      }
      const userLexiconResult = this.userLexiconPathProvider.getUserLexiconPath(context);
      if (userLexiconResult.success) {
        userLexiconPath = userLexiconResult.path;
        this.userLexiconPath = userLexiconResult.path;
        await this.mirrorSharedUserLexicon();
      } else {
        LOGGER.warn(`user lexicon path unavailable: ${userLexiconResult.errorMessage}`);
      }
    }

    const settingsTask = settingsReady ?? (context ? this.settingsController.reload(context) : undefined);
    if (settingsTask) {
      try {
        loadedSettings = await settingsTask;
      } catch (err) {
        LOGGER.warn(`settings unavailable before engine initialization; using default scheme: ${JSON.stringify(err)}`);
      }
    }

    const initializationOverride = getEngineInitializationOverride();
    let initialSchemeId = initializationOverride?.schemeId ?? loadedSettings?.schemeId ?? 'xiaohe';
    let initialCodeTableBundlePath = initializationOverride?.codeTableBundlePath;
    if (!initialCodeTableBundlePath && initialSchemeId === XIAOHE_YINXING_SCHEME_ID && context) {
      const bundle = await new YinxingBundleInstaller().installYinxingBundle(context);
      if (bundle.success) {
        initialCodeTableBundlePath = bundle.path;
      } else {
        LOGGER.warn(`persisted xiaohe-yinxing bundle unavailable before engine initialization: ${bundle.errorCode}`);
        initialSchemeId = 'xiaohe';
      }
    }
    this.store.updateComposition(
      await this.engineCoordinator.initializeAsync(
        initialSchemeId,
        lexiconPath,
        initializationOverride?.userLexiconPath ?? userLexiconPath,
        initializationOverride?.candidatePageSize,
        initialCodeTableBundlePath,
        initializationOverride?.codeTableActionFixturePath,
        initializationOverride?.codeTableActionFixtureSha256,
        loadedSettings?.spellingCorrectionEnabled ?? false,
        loadedSettings?.fuzzyOptions ?? [],
        initializationOverride?.quanpinContextModelPath ?? quanpinContextModelPath,
        initializationOverride?.quanpinContextModelSha256 ??
          (quanpinContextModelPath ? QUANPIN_CONTEXT_MODEL_SHA256 : undefined)
      )
    );
    if (userModelPath) {
      const status = this.engineCoordinator.loadUserModel(userModelPath);
      if (status.lastErrorCode.length > 0) {
        LOGGER.warn(`user model load recovered or failed: ${status.lastErrorCode}`);
      }
    }
    if (installError.length > 0) {
      this.store.recordError(ImeErrorCode.LEXICON_LOAD_FAILED, installError);
    }
    this.settingsController.applyCurrentSettingsToEngine();
    if (context) {
      await this.autoLoadLexiconSources(context);
    }
    this.userModelCommandBus.subscribeClear((): void => {
      this.applyUserModelClear('common event');
    }).catch((err: Object) => {
      LOGGER.warn(`user model clear subscription failed: ${JSON.stringify(err)}`);
    });
    this.userLexiconSyncBus.subscribe((): void => {
      this.mirrorSharedUserLexicon().then((mirrored: boolean): void => {
        if (!mirrored || !this.engineCoordinator.isInitialized()) {
          return;
        }
        const result = this.engineCoordinator.reloadUserLexicon();
        if (result.success) {
          this.store.updateComposition(result);
        } else {
          LOGGER.warn('user lexicon reload event was rejected; keeping last valid snapshot');
        }
      }).catch((err: Object): void => {
        LOGGER.warn(`user lexicon mirror failed: ${JSON.stringify(err)}`);
      });
    }).catch((err: Object) => {
      LOGGER.warn(`user lexicon synchronization failed: ${JSON.stringify(err)}`);
    });
    this.settingsController.subscribe(this.onAssistSettingsChanged);
    LOGGER.info('ability created');
  }

  handleInputStart(
    keyboardController: inputMethodEngine.KeyboardController,
    inputClient: inputMethodEngine.InputClient
  ): void {
    this.imeService.clearPairState?.();
    this.imeService.clearDeletionRecovery?.();
    this.commitHistoryManager.clear();
    this.undoCommitManager?.clearUndoState();
    ImeConnectionService.bindSession(keyboardController, inputClient);
    this.store.markSessionStarted();
    this.inputMethodSwitcher.setSessionActive(true);
    this.applyPendingUserModelCommand();
    this.applyEditorAttribute(ImeConnectionService.getEditorAttributeSync());
    this.settingsController.applyCurrentSettingsToEngine();
    LOGGER.info(`input session started: editor=${this.store.getSnapshot().editorContext.kind}`);
  }

  handleInputStop(): void {
    this.imeService.clearPairState?.();
    this.imeService.clearDeletionRecovery?.();
    this.aiAssistController.cancel(false);
    this.voiceInputController.cancel(false);
    this.inputMethodSwitcher.setSessionActive(false);
    this.imeService.clearPreviewText(this.getInputSessionGeneration()).catch((): void => {
      LOGGER.warn('input stop preview cleanup failed');
    });
    if (this.engineCoordinator.isInitialized()) {
      this.engineCoordinator.flushUserModel();
      this.store.updateComposition(this.engineCoordinator.reset());
      this.engineCoordinator.setSessionLearningAllowed(false);
    }
    ImeConnectionService.clearSession();
    this.store.markSessionStopped();
    this.commitHistoryManager.clear();
    this.undoCommitManager?.clearUndoState();
    LOGGER.info('input session stopped');
  }

  handleKeyboardShow(): void {
    this.store.markKeyboardVisible();
    this.inputMethodSwitcher.setSessionActive(true);
    this.settingsController.applyCurrentSettingsToEngine();
    LOGGER.info('keyboard visible');
  }

  handleKeyboardHide(): void {
    this.imeService.clearPairState?.();
    this.aiAssistController.cancel(false);
    this.voiceInputController.cancel(false);
    this.inputMethodSwitcher.setSessionActive(false);
    this.imeService.clearPreviewText(this.getInputSessionGeneration()).catch((): void => {
      LOGGER.warn('keyboard hide preview cleanup failed');
    });
    // CompositionTextManager serializes this clear with any later update and
    // keeps ownership until the host confirms cleanup.
    if (this.engineCoordinator.isInitialized()) {
      this.engineCoordinator.reset();
    }
    this.store.clearComposition();
    this.store.markKeyboardHidden();
    LOGGER.info('keyboard hidden');
  }

  /**
   * Updates only fixed-panel visibility. Unlike handleKeyboardHide(), this is
   * safe for HARDWARE_READY and never clears composition, disconnects the
   * editor, disables the session, or resets the engine.
   */
  handleKeyboardPanelHidden(): void {
    this.cancelAssistForLifecycle();
    this.store.markKeyboardHidden();
    LOGGER.info('keyboard panel hidden; input session preserved');
  }

  cancelAssistForLifecycle(): void {
    this.aiAssistController.cancel(false);
    this.voiceInputController.cancel(false);
  }

  handleDiscardTypingText(): void {
    this.imeService.clearPairState?.();
    this.aiAssistController.cancel(false);
    this.voiceInputController.cancel(false);
    // The editor has already discarded its typing text.  Only reset local
    // ownership/state; writing the old range back could resurrect cleared
    // text or edit a newly focused field.
    this.imeService.resetPreviewState();
    if (this.engineCoordinator.isInitialized()) {
      this.store.updateComposition(this.engineCoordinator.reset());
    }
    this.store.clearComposition();
    LOGGER.info('editor discarded typing text');
  }

  handleAbilityDestroyed(): void {
    this.imeService.clearPairState?.();
    this.imeService.clearDeletionRecovery?.();
    this.aiAssistController.cancel(false);
    this.voiceInputController.cancel(false);
    this.commitHistoryManager.clear();
    this.undoCommitManager?.clearUndoState();
    this.inputMethodSwitcher.setSessionActive(false);
    this.imeService.clearPreviewText(this.getInputSessionGeneration()).catch((): void => {
      LOGGER.warn('ability destroy preview cleanup failed');
    });
    ImeConnectionService.stopObservingEditorAttributes();
    ImeConnectionService.clearSession();
    this.engineCoordinator.dispose();
    this.userModelCommandBus.unsubscribeClear();
    this.userLexiconSyncBus.unsubscribe();
    this.settingsController.unsubscribe(this.onAssistSettingsChanged);
    this.userModelPath = undefined;
    this.userLexiconPath = undefined;
    if (this.abilityLauncher) { getSharedDirectAbilityLaunchers().unbind(this.abilityLauncher); }
    this.abilityLauncher = undefined;
    this.abilityContext = undefined;
    this.store.resetAll();
    LOGGER.info('ability destroyed');
  }
  handleInputControllerRecovery(): void {
    this.store.resetChineseCapsLock();
  }

  applyEditorContext(context: EditorContext): void {
    this.imeService.clearPairState?.();
    this.imeService.clearDeletionRecovery?.();
    this.aiAssistController.cancel(false);
    this.voiceInputController.cancel(false);
    // Attribute changes can already refer to a newly focused editor. Drop the
    // old range locally instead of risking a cleanup write into the new field.
    this.imeService.resetPreviewState();
    if (this.engineCoordinator.isInitialized()) {
      this.store.updateComposition(this.engineCoordinator.reset());
    }
    this.store.clearComposition();
    const globalLearningEnabled = this.settingsController.getSettings().userLearningEnabled;
    const mode = this.store.applyEditorContext(context, globalLearningEnabled);
    if (this.engineCoordinator.isInitialized()) {
      this.engineCoordinator.setSessionLearningAllowed(
        context.learningAllowed && globalLearningEnabled
      );
    }
    LOGGER.info(
      `editor context applied: kind=${context.kind}, mode=${mode}, learning=${context.learningAllowed}`
    );
  }

  handleEditorAttributeChanged(attribute?: inputMethodEngine.EditorAttribute): void {
    if (!this.store.getSnapshot().sessionActive) {
      return;
    }
    this.aiAssistController.cancel(false);
    this.voiceInputController.cancel(false);
    this.commitHistoryManager.clear();
    this.undoCommitManager?.clearUndoState();
    this.store.advanceSessionGeneration();
    this.applyEditorAttribute(attribute);
  }

  protected applyEditorAttribute(attribute?: inputMethodEngine.EditorAttribute): void {
    LOGGER.info(
      `editor attributes received: pattern=${attribute?.inputPattern ?? -1}, ` +
        `enter=${attribute?.enterKeyType ?? -1}, ` +
        `preview=${attribute?.isTextPreviewSupported ?? false}, ` +
        `configured=${attribute?.extraConfig?.customSettings[EDITOR_KIND_EXTRA_CONFIG_KEY] ?? 'none'}`
    );
    this.applyEditorContext(this.editorAttributeMapper.map(attribute));
  }

  recordError(code: ImeErrorCode, message?: string): void {
    this.store.recordError(code, message);
  }

  setSessionLearningAllowed(allowed: boolean): void {
    if (this.engineCoordinator.isInitialized()) {
      this.engineCoordinator.setSessionLearningAllowed(allowed);
    }
  }

  setInputMethodCapabilityState(capabilityState: InputMethodCapabilityState): void {
    this.store.setInputMethodCapabilityState(capabilityState);
    this.reconcileAssistAvailability();
  }

  getAssistAvailability(): AssistAvailability {
    const snapshot = this.store.getSnapshot();
    return resolveAssistAvailability(
      snapshot.capabilityState,
      snapshot.editorContext,
      this.settingsController.getSettings(),
      snapshot.sessionActive,
      snapshot.editorConnected
    );
  }

  requestAiSuggestions(action: AiAction = AiAction.POLITE): Promise<void> {
    return this.aiAssistController.request(action);
  }

  showAiActions(): Promise<void> {
    return this.aiAssistController.showActions();
  }

  acceptAiSuggestion(suggestionId: string): Promise<boolean> {
    return this.aiAssistController.acceptSuggestion(suggestionId);
  }

  async acceptLocalAssociation(associationId: string): Promise<boolean> {
    const snapshot = this.store.getSnapshot();
    const generation = this.store.getSessionGeneration();
    const suggestion = snapshot.localAssociations.find(
      (item: LocalAssociationSuggestion): boolean => item.associationId === associationId
    );
    if (!suggestion || suggestion.sessionGeneration !== generation ||
      !this.settingsController.getSettings().localAssociationEnabled ||
      !snapshot.sessionActive || !snapshot.editorConnected || snapshot.rawInput.length > 0 ||
      snapshot.editorContext.isPassword ||
      (snapshot.editorContext.kind !== EditorKind.NORMAL_TEXT &&
        snapshot.editorContext.kind !== EditorKind.MULTILINE &&
        snapshot.editorContext.kind !== EditorKind.SEARCH)) {
      this.store.clearLocalAssociations();
      return false;
    }
    const result = await this.insertText(suggestion.text, 'local association', generation);
    this.store.clearLocalAssociations();
    return result.success;
  }

  cancelAiRequest(): void {
    this.aiAssistController.cancel(true);
  }

  startVoiceInput(): boolean {
    return this.voiceInputController.start();
  }

  stopVoiceInput(): void {
    this.voiceInputController.stop();
  }

  confirmVoiceResult(): Promise<boolean> {
    return this.voiceInputController.confirm();
  }

  retryVoiceInput(): boolean {
    return this.voiceInputController.retry();
  }

  cancelVoiceInput(): void {
    this.voiceInputController.cancel(true);
  }

  protected reconcileAssistAvailability(): void {
    const availability = this.getAssistAvailability();
    if (!availability.ai.available) {
      this.aiAssistController.cancel(false);
    }
    if (!availability.voice.available) {
      this.voiceInputController.cancel(false);
    }
    if (!this.settingsController.getSettings().localAssociationEnabled) {
      this.store.clearLocalAssociations();
    }
  }

  protected publishLocalAssociations(): void {
    const snapshot = this.store.getSnapshot();
    if (!this.settingsController.getSettings().localAssociationEnabled ||
      !snapshot.sessionActive || !snapshot.editorConnected || snapshot.rawInput.length > 0 ||
      snapshot.editorContext.isPassword ||
      (snapshot.editorContext.kind !== EditorKind.NORMAL_TEXT &&
        snapshot.editorContext.kind !== EditorKind.MULTILINE &&
        snapshot.editorContext.kind !== EditorKind.SEARCH)) {
      this.store.clearLocalAssociations();
      return;
    }
    const generation = this.store.getSessionGeneration();
    const suggestions = normalizeLocalAssociations(
      this.engineCoordinator.getLocalAssociations(), generation
    );
    this.store.updateLocalAssociations(suggestions);
  }

  getUserModelRecordCount(): number {
    if (!this.engineCoordinator.isInitialized()) {
      return -1;
    }
    const status = this.engineCoordinator.flushUserModel();
    if (status.lastErrorCode.length > 0) {
      return -1;
    }
    return status.recordCount;
  }

  clearUserModel(): void {
    if (this.engineCoordinator.isInitialized()) {
      const status = this.engineCoordinator.clearUserModel();
      if (status.lastErrorCode.length > 0) {
        this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'clear user model failed');
      }
    }
  }

  async deleteCurrentLine(
    generation: number = this.getInputSessionGeneration()
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('delete current line');
    }
    const sessionCheck = this.ensureInputSession('delete current line');
    if (!sessionCheck.success) {
      return sessionCheck;
    }
    if (this.imeService.deleteCurrentLine === undefined) {
      return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'delete current line is unavailable');
    }
    const state = this.store.getSnapshot();
    if (state.rawInput.length > 0) {
      const cleared = await this.imeService.clearPreviewText(generation);
      if (!this.isInputSessionGenerationCurrent(generation)) {
        return this.staleInputAction('delete current line preview cleanup');
      }
      if (!cleared) {
        this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, 'delete current line preview cleanup failed');
        return inputOperationFailed(
          ImeErrorCode.ENGINE_INTERNAL_ERROR,
          'delete current line preview cleanup failed'
        );
      }
    }
    this.imeService.resetPreviewState();
    this.imeService.clearPairState?.();
    this.undoCommitManager?.invalidateUndo();
    if (this.engineCoordinator.isInitialized()) {
      this.engineCoordinator.reset();
    }
    this.store.clearComposition();
    const deleted = await this.imeService.deleteCurrentLine();
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction('delete current line completion');
    }
    if (deleted) {
      this.store.clearError();
      return inputOperationOk();
    }
    this.store.recordError(ImeErrorCode.UNSUPPORTED_OPERATION, 'delete current line failed');
    return inputOperationFailed(ImeErrorCode.UNSUPPORTED_OPERATION, 'delete current line failed');
  }

  protected async updateCompositionText(
    text: string,
    previewSupported: boolean,
    generation: number,
    anchorAfterCandidateCommit: boolean = false,
    serializedContinuation: boolean = false
  ): Promise<boolean> {
    const updated = await this.imeService.setPreviewText(
      text,
      previewSupported,
      generation,
      anchorAfterCandidateCommit,
      serializedContinuation
    );
    if (updated && this.isInputSessionGenerationCurrent(generation)) {
      const cursorPreviewActive = this.imeService.isCursorPreviewActive !== undefined
        ? this.imeService.isCursorPreviewActive()
        : previewSupported;
      this.store.setCursorPreeditVisible(text.length > 0 && cursorPreviewActive);
    }
    return updated;
  }

  /** Keep uncommitted codes beside candidates; host preview styling is not controllable. */
  protected shouldUseCursorPreedit(_state: InputSessionState): boolean {
    // Notes may expose the initial preview letter as ordinary text. Candidate-bar
    // composition avoids editor writes until a candidate is actually committed.
    return false;
  }

  protected syncCursorPreeditVisibility(rawInput: string): void {
    const cursorPreviewActive = this.imeService.isCursorPreviewActive !== undefined
      ? this.imeService.isCursorPreviewActive()
      : false;
    this.store.setCursorPreeditVisible(rawInput.length > 0 && cursorPreviewActive);
  }

  protected async insertText(
    text: string,
    reason: string,
    generation: number
  ): Promise<InputOperationResult> {
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction(reason);
    }
    const sessionCheck = this.ensureInputSession(reason);
    if (!sessionCheck.success) {
      return sessionCheck;
    }

    const settings = this.settingsController.getSettings();
    const userDirectReasons: string[] = [
      'letter',
      'chinese uppercase letter',
      'direct character',
      'punctuation after explicit composition action',
      'physical punctuation suffix',
      'space'
    ];
    const committedText = userDirectReasons.indexOf(reason) >= 0 ?
      transformDirectText(text, settings.punctuationMode, settings.fullWidthEnabled) : text;
    const inserted = await this.imeService.insertText(committedText);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction(`${reason} completion`);
    }
    if (inserted) {
      // Record commit history (except for repeat action to avoid infinite loop)
      if (reason !== 'repeat last commit') {
        this.commitHistoryManager.addCommit(committedText);
        if (this.undoCommitManager) {
          this.undoCommitManager.recordCommit(committedText);
        }
      }
      this.store.clearError();
      return inputOperationOk();
    }

    this.store.recordError(ImeErrorCode.ENGINE_INTERNAL_ERROR, `${reason} insert failed`);
    return inputOperationFailed(ImeErrorCode.ENGINE_INTERNAL_ERROR, `${reason} insert failed`);
  }

  protected ensureInputSession(reason: string): InputOperationResult {
    const state = this.store.getSnapshot();
    if (!state.sessionActive || !state.editorConnected) {
      const message = `${reason} requires active editor session`;
      this.store.recordError(ImeErrorCode.ENGINE_NOT_INITIALIZED, message);
      LOGGER.warn(message);
      return inputOperationFailed(ImeErrorCode.ENGINE_NOT_INITIALIZED, message);
    }

    return inputOperationOk();
  }

  protected staleInputAction(reason: string): InputOperationResult {
    LOGGER.info(`stale input action ignored: reason=${reason}`);
    return inputOperationFailed(ImeErrorCode.ENGINE_NOT_INITIALIZED, 'input session is no longer current');
  }

  protected applyPendingUserModelCommand(): void {
    const context = this.abilityContext;
    if (!context || !this.engineCoordinator.isInitialized()) {
      return;
    }
    this.userModelCommands.consumeClearRequest(context).then((requested: boolean) => {
      if (requested) {
        this.applyUserModelClear('pending request');
        return;
      }
      if (this.userModelPath) {
        const reloadStatus = this.engineCoordinator.loadUserModel(this.userModelPath);
        if (reloadStatus.lastErrorCode.length > 0) {
          LOGGER.warn(`user model session reload failed: ${reloadStatus.lastErrorCode}`);
        }
      }
    }).catch((err: Object) => {
      LOGGER.warn(`pending user model command failed: ${JSON.stringify(err)}`);
    });
  }

  protected applyUserModelClear(source: string): void {
    if (!this.engineCoordinator.isInitialized()) {
      LOGGER.warn(`user model clear ignored before engine initialization: ${source}`);
      return;
    }
    const clearStatus = this.engineCoordinator.clearUserModel();
    if (clearStatus.lastErrorCode.length > 0) {
      LOGGER.warn(`user model clear failed (${source}): ${clearStatus.lastErrorCode}`);
      return;
    }
    this.store.clearComposition();
    LOGGER.info(`user model clear applied: ${source}`);
  }

  protected async mirrorSharedUserLexicon(): Promise<boolean> {
    const path = this.userLexiconPath;
    if (!path) {
      return false;
    }
    const content = await this.userLexiconSyncBus.readSnapshot();
    if (content === undefined) {
      return false;
    }
    const current = this.userLexiconGateway.loadUserLexicon(path);
    if (!current.success || current.revision.length <= 0) {
      LOGGER.warn(`user lexicon local mirror load failed: ${current.errorCode}`);
      return false;
    }
    const saved = this.userLexiconGateway.saveUserLexicon(path, current.revision, content);
    if (!saved.success) {
      LOGGER.warn(`user lexicon local mirror save failed: ${saved.errorCode}`);
      return false;
    }
    LOGGER.info(`user lexicon shared snapshot mirrored: entries=${saved.stats.effective}`);
    return true;
  }

  setScreenMetrics(screenMetrics: ScreenMetricsPx): void {
    this.store.setScreenMetrics(screenMetrics);
  }

  setBottomSystemInsetPx(bottomSystemInsetPx: number): void {
    this.store.setScreenMetrics(withBottomSystemInset(this.store.getSnapshot().screenMetrics, bottomSystemInsetPx));
  }

  setFloatingCandidateVisible(visible: boolean): void {
    this.store.setFloatingCandidateVisible(visible);
  }

  setFloatingCandidateExpanded(expanded: boolean): boolean {
    return this.store.setFloatingCandidateExpanded(expanded);
  }

  setCandidatePanelExpanded(expanded: boolean): boolean {
    return this.store.setCandidatePanelExpanded(expanded);
  }

  setCandidatePageLoading(loading: boolean): void {
    this.store.setCandidatePageLoading(loading);
  }

  /**
   * 重复上屏最后一次提交的内容
   */
  async repeatLastCommit(generation: number = this.getInputSessionGeneration()): Promise<boolean> {
    const lastCommit = this.commitHistoryManager.getLastCommit();

    if (!lastCommit) {
      LOGGER.warn('没有可重复的上屏内容');
      return false;
    }

    // 清空当前输入状态
    const state = this.store.getSnapshot();
    if (state.rawInput.length > 0) {
      const cleared = await this.imeService.clearPreviewText(generation);
      if (!cleared || !this.isInputSessionGenerationCurrent(generation)) {
        return false;
      }
      this.engineCoordinator.reset();
      this.store.clearComposition();
    }

    // 直接插入文本(使用特殊reason避免记录历史)
    const result = await this.insertText(lastCommit, 'repeat last commit', generation);

    if (result.success) {
      LOGGER.info(`重复上屏成功: length=${lastCommit.length}`);
      return true;
    }

    return false;
  }

  /**
   * 撤销最后一次上屏
   */
  async undoLastCommit(generation: number = this.getInputSessionGeneration()): Promise<boolean> {
    if (!this.undoCommitManager) {
      return false;
    }

    const undoState = this.undoCommitManager.canUndo();

    if (!undoState.canUndo) {
      LOGGER.warn(`无法撤销: ${undoState.reason}`);
      return false;
    }

    let reverted = false;
    if (undoState.replacementOriginalText !== undefined) {
      if (!this.imeService.replaceTextBeforeCursorIfMatches) {
        LOGGER.warn('无法撤销替换: 当前编辑器连接不支持安全文本替换');
        return false;
      }
      reverted = await this.imeService.replaceTextBeforeCursorIfMatches(
        undoState.lastCommit!,
        undoState.replacementOriginalText
      );
    } else {
      if (!this.imeService.deleteBackwardIfMatches) {
        LOGGER.warn('无法撤销: 当前编辑器连接不支持安全文本核对');
        return false;
      }
      reverted = await this.imeService.deleteBackwardIfMatches(undoState.lastCommit!);
    }

    if (reverted && this.isInputSessionGenerationCurrent(generation)) {
      this.undoCommitManager.clearUndoState();
      LOGGER.info(`撤销上屏成功: length=${undoState.lastCommitLength ?? 0}`);
      return true;
    }

    return false;
  }

  protected recordCommittedText(text: string): void {
    this.commitHistoryManager.addCommit(text);
    this.undoCommitManager?.recordCommit(text);
  }

  protected recordReplacedText(originalText: string, replacementText: string): void {
    this.commitHistoryManager.addCommit(replacementText);
    this.undoCommitManager?.recordReplacement(originalText, replacementText);
  }

  protected async importConfiguredUserLexicon(generation: number): Promise<boolean> {
    const context = this.abilityContext;
    if (!context || !this.isInputSessionGenerationCurrent(generation)) {
      return false;
    }
    const imported = await this.autoLoadLexiconSources(context);
    return imported && this.isInputSessionGenerationCurrent(generation);
  }

  /**
   * 自动加载词库源
   */
  protected async autoLoadLexiconSources(context: InputMethodExtensionContext): Promise<boolean> {
    try {
      const settings = await this.settingsController.getSettings();
      const sources = settings.lexiconSources || [];

      if (sources.length === 0) {
        LOGGER.info('没有配置词库源，跳过自动加载');
        return false;
      }

      const enabledSources = sources.filter((s) => s.enabled);
      if (enabledSources.length === 0) {
        LOGGER.info('没有启用的词库源，跳过自动加载');
        return false;
      }

      const pathResult = this.userLexiconPathProvider.getUserLexiconPath(context);
      if (!pathResult.success) {
        LOGGER.warn(`无法获取用户词库路径: ${pathResult.errorMessage}`);
        return false;
      }
      const targetPath = pathResult.path;
      const result = await this.lexiconImportManager.importFromSources(enabledSources, targetPath);

      if (result.success) {
        LOGGER.info(`自动加载词库源完成: ${result.message}`);
        // 触发同步总线发布更新
        const lexiconContent = UserLexiconDocumentEditor.serialize(result.finalDocument.entries);
        const published = await this.userLexiconSyncBus.publish(lexiconContent);
        if (!published) {
          LOGGER.warn('用户词库已在本机导入，但跨实例同步发布失败');
        }
        if (this.engineCoordinator.isInitialized()) {
          const reloaded = this.engineCoordinator.reloadUserLexicon();
          if (!reloaded.success) {
            LOGGER.warn('用户词库导入成功，但当前引擎重载失败');
            return false;
          }
          this.store.updateComposition(reloaded);
        }
        return true;
      } else {
        LOGGER.warn(`自动加载词库源失败: ${result.message}`);
      }
    } catch (err) {
      LOGGER.error(`自动加载词库源失败: ${JSON.stringify(err)}`);
    }
    return false;
  }
}
