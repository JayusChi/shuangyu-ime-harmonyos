import { inputMethodEngine, InputMethodExtensionContext } from '@kit.IMEKit';
import { ImeErrorCode } from '../common/error/ImeError';
import { Logger } from '../common/logging/Logger';
import {
  EditorContext,
  EnterAction,
  EDITOR_KIND_EXTRA_CONFIG_KEY
} from '../domain/editor/EditorContext';
import { KeyboardMode, isSingleAsciiLetter, isT9PinyinDigit } from '../domain/keyboard/KeyboardAction';
import { ImeSettings, PINYIN_9_SCHEME_ID, XIAOHE_YINXING_SCHEME_ID } from '../domain/settings/ImeSettings';
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
import { CompositionResult, NativeEngineGatewayContract } from '../infrastructure/native/NativeEngineTypes';
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

import { ImeInputService } from './ImeInputService';
import { SmartPeriodController, SmartPeriodInputAction } from './SmartPeriodController';

const TAG = 'InputSessionController';
const LOGGER = new Logger(TAG);

class SessionProtocolActionHandlers implements ProtocolActionHandlers {
  private readonly repeatHandler: (generation: number) => Promise<boolean>;
  private readonly undoHandler: (generation: number) => Promise<boolean>;

  constructor(
    repeatHandler: (generation: number) => Promise<boolean>,
    undoHandler: (generation: number) => Promise<boolean>
  ) {
    this.repeatHandler = repeatHandler;
    this.undoHandler = undoHandler;
  }

  repeatLastCommit(generation: number): Promise<boolean> {
    return this.repeatHandler(generation);
  }

  undoLastCommit(generation: number): Promise<boolean> {
    return this.undoHandler(generation);
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
  protected userModelPath?: string;
  protected userLexiconPath?: string;
  protected abilityContext?: InputMethodExtensionContext;
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
  protected readonly onEditorAttributeChanged = (attribute: inputMethodEngine.EditorAttribute): void => {
    this.handleEditorAttributeChanged(attribute);
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
    smartPeriodController: SmartPeriodController = new SmartPeriodController()
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
    const actionHandlers: ProtocolActionHandlers = new SessionProtocolActionHandlers(
      (generation: number): Promise<boolean> => this.repeatLastCommit(generation),
      (generation: number): Promise<boolean> => this.undoLastCommit(generation)
    );
    this.protocolActionExecutor = new ProtocolActionExecutor(
      this.imeService,
      new SystemTimeProvider(),
      (generation: number): boolean => this.isInputSessionGenerationCurrent(generation),
      actionHandlers
    );
    this.undoCommitManager = new UndoCommitManager(this.commitHistoryManager);
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
    return this.smartPeriodController.beginInput(timestampMs);
  }

  isInputSessionGenerationCurrent(generation: number): boolean {
    return generation === this.store.getSessionGeneration();
  }

  async handleAbilityCreated(
    context?: InputMethodExtensionContext,
    settingsReady?: Promise<ImeSettings>
  ): Promise<void> {
    this.inputMethodSwitcher.setSessionActive(false);
    this.abilityContext = context;
    this.store.resetAll();
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
      this.engineCoordinator.initialize(
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
    LOGGER.info('ability created');
  }

  handleInputStart(
    keyboardController: inputMethodEngine.KeyboardController,
    inputClient: inputMethodEngine.InputClient
  ): void {
    ImeConnectionService.bindSession(keyboardController, inputClient);
    this.store.markSessionStarted();
    this.inputMethodSwitcher.setSessionActive(true);
    this.applyPendingUserModelCommand();
    this.applyEditorAttribute(ImeConnectionService.getEditorAttributeSync());
    this.settingsController.applyCurrentSettingsToEngine();
    LOGGER.info(`input session started: editor=${this.store.getSnapshot().editorContext.kind}`);
  }

  handleInputStop(): void {
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
    LOGGER.info('input session stopped');
  }

  handleKeyboardShow(): void {
    this.store.markKeyboardVisible();
    this.inputMethodSwitcher.setSessionActive(true);
    this.settingsController.applyCurrentSettingsToEngine();
    LOGGER.info('keyboard visible');
  }

  handleKeyboardHide(): void {
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
    this.store.markKeyboardHidden();
    LOGGER.info('keyboard panel hidden; input session preserved');
  }

  handleDiscardTypingText(): void {
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
    this.inputMethodSwitcher.setSessionActive(false);
    this.imeService.clearPreviewText(this.getInputSessionGeneration()).catch((): void => {
      LOGGER.warn('ability destroy preview cleanup failed');
    });
    ImeConnectionService.stopObservingEditorAttributes();
    ImeConnectionService.clearSession();
    this.engineCoordinator.dispose();
    this.userModelCommandBus.unsubscribeClear();
    this.userLexiconSyncBus.unsubscribe();
    this.userModelPath = undefined;
    this.userLexiconPath = undefined;
    this.abilityContext = undefined;
    this.store.resetAll();
    LOGGER.info('ability destroyed');
  }
  handleInputControllerRecovery(): void {
    this.store.resetChineseCapsLock();
  }

  applyEditorContext(context: EditorContext): void {
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

    const inserted = await this.imeService.insertText(text);
    if (!this.isInputSessionGenerationCurrent(generation)) {
      return this.staleInputAction(`${reason} completion`);
    }
    if (inserted) {
      // Record commit history (except for repeat action to avoid infinite loop)
      if (reason !== 'repeat last commit') {
        this.commitHistoryManager.addCommit(text);
        if (this.undoCommitManager) {
          this.undoCommitManager.recordCommit(text);
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
      LOGGER.info(`重复上屏成功: ${lastCommit}`);
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

    const verifier = this.imeService.deleteBackwardIfMatches;
    if (!verifier) {
      LOGGER.warn('无法撤销: 当前编辑器连接不支持安全文本核对');
      return false;
    }
    const deleted = await verifier(undoState.lastCommit!);

    if (deleted) {
      this.undoCommitManager.clearUndoState();
      LOGGER.info(`撤销上屏成功: ${undoState.lastCommit}`);
      return true;
    }

    return false;
  }

  protected recordCommittedText(text: string): void {
    this.commitHistoryManager.addCommit(text);
    this.undoCommitManager?.recordCommit(text);
  }

  /**
   * 自动加载词库源
   */
  protected async autoLoadLexiconSources(context: InputMethodExtensionContext): Promise<void> {
    try {
      const settings = await this.settingsController.getSettings();
      const sources = settings.lexiconSources || [];

      if (sources.length === 0) {
        LOGGER.info('没有配置词库源，跳过自动加载');
        return;
      }

      const enabledSources = sources.filter((s) => s.enabled);
      if (enabledSources.length === 0) {
        LOGGER.info('没有启用的词库源，跳过自动加载');
        return;
      }

      const pathResult = this.userLexiconPathProvider.getUserLexiconPath(context);
      if (!pathResult.success) {
        LOGGER.warn(`无法获取用户词库路径: ${pathResult.errorMessage}`);
        return;
      }
      const targetPath = pathResult.path;
      const result = await this.lexiconImportManager.importFromSources(enabledSources, targetPath);

      if (result.success) {
        LOGGER.info(`自动加载词库源完成: ${result.message}`);
        // 触发同步总线发布更新
        const lexiconContent = UserLexiconDocumentEditor.serialize(result.finalDocument.entries);
        await this.userLexiconSyncBus.publish(lexiconContent);
      } else {
        LOGGER.warn(`自动加载词库源失败: ${result.message}`);
      }
    } catch (err) {
      LOGGER.error(`自动加载词库源失败: ${JSON.stringify(err)}`);
    }
  }
}
