import { ImeErrorCode } from '../common/error/ImeError';
import { Logger } from '../common/logging/Logger';
import {
  CodeTableCategoryConfig,
  CompositionResult,
  EngineConfig,
  FuzzyOptionId,
  NativeEngineGatewayContract,
  UserModelStatus
} from '../infrastructure/native/NativeEngineTypes';
import { NativeEngineGateway } from '../infrastructure/native/NativeEngineGateway';
import {
  ChineseTextConverter,
  SystemChineseTextConverter
} from '../infrastructure/text/ChineseTextConverter';

const TAG = 'EngineCoordinator';
const LOGGER = new Logger(TAG);
const INTERFACE_VERSION = 11;
const QUANPIN_CONFIG_VERSION = 1;
const QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION = 2;
const DEFAULT_SCHEME_ID = 'xiaohe';
// Keep a desktop page compact enough for every rendered item to remain visible.
// The physical 1-9 selector contract still safely rejects/consumes empty slots.
const DEFAULT_CANDIDATE_PAGE_SIZE = 7;

export class EngineCoordinator {
  private readonly gateway: NativeEngineGatewayContract;
  private handle: number = 0;
  private initialized: boolean = false;
  private activeSchemeId: string = DEFAULT_SCHEME_ID;
  private lastResult: CompositionResult = this.emptyResult();
  private initializationConfig?: EngineConfig;
  // `initializationConfig.codeTableBundlePath` is a requested configuration
  // value, not proof that the current native handle actually loaded the
  // bundle. Rust intentionally ignores the path when a handle is created for
  // a phonetic scheme, so hot switching must track handle ownership
  // separately and recreate the engine when the bundle is not resident.
  private loadedCodeTableBundlePath?: string;
  private userModelPath: string = '';
  private userLearningEnabled: boolean = true;
  private sessionLearningAllowed: boolean = true;
  private initializationTask?: Promise<CompositionResult>;
  private lifecycleGeneration: number = 0;
  private traditionalOutputEnabled: boolean = false;
  private readonly chineseTextConverter: ChineseTextConverter;

  constructor(
    gateway: NativeEngineGatewayContract = new NativeEngineGateway(),
    chineseTextConverter: ChineseTextConverter = new SystemChineseTextConverter()
  ) {
    this.gateway = gateway;
    this.chineseTextConverter = chineseTextConverter;
  }

  setTraditionalOutputEnabled(enabled: boolean): void {
    this.traditionalOutputEnabled = enabled;
    this.lastResult = this.applyOutputMode(this.lastResult);
  }

  initialize(
    schemeId: string = DEFAULT_SCHEME_ID,
    lexiconPath?: string,
    userLexiconPath?: string,
    candidatePageSize: number = DEFAULT_CANDIDATE_PAGE_SIZE,
    codeTableBundlePath?: string,
    codeTableActionFixturePath?: string,
    codeTableActionFixtureSha256?: string,
    spellingCorrectionEnabled: boolean = false,
    fuzzyOptions: FuzzyOptionId[] = [],
    quanpinContextModelPath?: string,
    quanpinContextModelSha256?: string
  ): CompositionResult {
    if (this.initialized && this.handle > 0) {
      return this.lastResult;
    }

    const initializationStartedAt = Date.now();
    try {
      const config: EngineConfig = {
        interfaceVersion: INTERFACE_VERSION,
        schemeId,
        lexiconPath,
        codeTableBundlePath,
        codeTableActionFixturePath,
        codeTableActionFixtureSha256,
        userLexiconPath,
        candidatePageSize,
        quanpinConfigVersion: QUANPIN_CONFIG_VERSION,
        spellingCorrectionEnabled,
        fuzzyOptions: fuzzyOptions.slice(),
        quanpinContextRerankingConfigVersion: QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION,
        quanpinContextRerankingEnabled: quanpinContextModelPath !== undefined &&
          quanpinContextModelSha256 !== undefined,
        quanpinContextModelPath,
        quanpinContextModelSha256
      };
      this.handle = this.gateway.createEngine(config);
      this.initialized = true;
      this.activeSchemeId = schemeId;
      this.initializationConfig = this.copyConfig(config);
      this.loadedCodeTableBundlePath = this.loadedBundlePathForConfig(config);
      this.lastResult = this.emptyResult();
      const engineVersion = this.gateway.getEngineVersion();
      const nativeBuildInfo = this.gateway.getNativeBuildInfo();
      LOGGER.info(
        `engine initialized: schemeId=${schemeId}, ` +
          `initializationMs=${Date.now() - initializationStartedAt}, version=${engineVersion}, ` +
          `interface=${this.gateway.getInterfaceVersion()}, native=${nativeBuildInfo}`
      );
      return this.lastResult;
    } catch (err) {
      const detail = err instanceof Error ? err.message : JSON.stringify(err);
      LOGGER.error(`engine initialize failed: ${detail}`);
      this.handle = 0;
      this.initialized = false;
      this.activeSchemeId = DEFAULT_SCHEME_ID;
      this.initializationConfig = undefined;
      this.loadedCodeTableBundlePath = undefined;
      this.lastResult = this.failure(ImeErrorCode.NATIVE_BRIDGE_ERROR, `engine initialize failed: ${detail}`);
      return this.lastResult;
    }
  }

  async initializeAsync(
    schemeId: string = DEFAULT_SCHEME_ID,
    lexiconPath?: string,
    userLexiconPath?: string,
    candidatePageSize: number = DEFAULT_CANDIDATE_PAGE_SIZE,
    codeTableBundlePath?: string,
    codeTableActionFixturePath?: string,
    codeTableActionFixtureSha256?: string,
    spellingCorrectionEnabled: boolean = false,
    fuzzyOptions: FuzzyOptionId[] = [],
    quanpinContextModelPath?: string,
    quanpinContextModelSha256?: string
  ): Promise<CompositionResult> {
    if (this.initialized && this.handle > 0) {
      return this.lastResult;
    }
    if (this.initializationTask !== undefined) {
      return this.initializationTask;
    }
    if (this.gateway.createEngineAsync === undefined) {
      return this.initialize(
        schemeId,
        lexiconPath,
        userLexiconPath,
        candidatePageSize,
        codeTableBundlePath,
        codeTableActionFixturePath,
        codeTableActionFixtureSha256,
        spellingCorrectionEnabled,
        fuzzyOptions,
        quanpinContextModelPath,
        quanpinContextModelSha256
      );
    }

    const initializationStartedAt = Date.now();
    const config: EngineConfig = {
      interfaceVersion: INTERFACE_VERSION,
      schemeId,
      lexiconPath,
      codeTableBundlePath,
      codeTableActionFixturePath,
      codeTableActionFixtureSha256,
      userLexiconPath,
      candidatePageSize,
      quanpinConfigVersion: QUANPIN_CONFIG_VERSION,
      spellingCorrectionEnabled,
      fuzzyOptions: fuzzyOptions.slice(),
      quanpinContextRerankingConfigVersion: QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION,
      quanpinContextRerankingEnabled: quanpinContextModelPath !== undefined &&
        quanpinContextModelSha256 !== undefined,
      quanpinContextModelPath,
      quanpinContextModelSha256
    };
    const generation = this.lifecycleGeneration;
    const initializationTask = this.initializeThroughAsyncGateway(
      config,
      schemeId,
      initializationStartedAt,
      generation
    );
    this.initializationTask = initializationTask;
    try {
      return await initializationTask;
    } finally {
      if (this.initializationTask === initializationTask) {
        this.initializationTask = undefined;
      }
    }
  }

  private async initializeThroughAsyncGateway(
    config: EngineConfig,
    schemeId: string,
    initializationStartedAt: number,
    generation: number
  ): Promise<CompositionResult> {
    try {
      const handle = await this.gateway.createEngineAsync!(config);
      if (generation !== this.lifecycleGeneration) {
        try {
          this.gateway.destroyEngine(handle);
        } catch (err) {
          LOGGER.warn(`stale asynchronous engine destroy failed: ${JSON.stringify(err)}`);
        }
        return this.lastResult;
      }
      this.handle = handle;
      this.initialized = true;
      this.activeSchemeId = schemeId;
      this.initializationConfig = this.copyConfig(config);
      this.loadedCodeTableBundlePath = this.loadedBundlePathForConfig(config);
      this.lastResult = this.emptyResult();
      const engineVersion = this.gateway.getEngineVersion();
      const nativeBuildInfo = this.gateway.getNativeBuildInfo();
      LOGGER.info(
        `engine initialized asynchronously: schemeId=${schemeId}, ` +
          `initializationMs=${Date.now() - initializationStartedAt}, version=${engineVersion}, ` +
          `interface=${this.gateway.getInterfaceVersion()}, native=${nativeBuildInfo}`
      );
      return this.lastResult;
    } catch (err) {
      if (generation !== this.lifecycleGeneration) {
        return this.lastResult;
      }
      const detail = err instanceof Error ? err.message : JSON.stringify(err);
      LOGGER.error(`asynchronous engine initialize failed: ${detail}`);
      this.handle = 0;
      this.initialized = false;
      this.activeSchemeId = DEFAULT_SCHEME_ID;
      this.initializationConfig = undefined;
      this.loadedCodeTableBundlePath = undefined;
      this.lastResult = this.failure(ImeErrorCode.NATIVE_BRIDGE_ERROR, `engine initialize failed: ${detail}`);
      return this.lastResult;
    }
  }

  dispose(): void {
    this.lifecycleGeneration += 1;
    this.initializationTask = undefined;
    if (!this.initialized || this.handle <= 0) {
      this.handle = 0;
      this.initialized = false;
      this.initializationConfig = undefined;
      this.loadedCodeTableBundlePath = undefined;
      this.userModelPath = '';
      this.lastResult = this.emptyResult();
      return;
    }

    const handleToDestroy = this.handle;
    try {
      this.gateway.flushUserModel(handleToDestroy);
    } catch (err) {
      LOGGER.warn(`engine user model flush before dispose failed: ${JSON.stringify(err)}`);
    }
    this.handle = 0;
    this.initialized = false;
    this.activeSchemeId = DEFAULT_SCHEME_ID;
    this.initializationConfig = undefined;
    this.loadedCodeTableBundlePath = undefined;
    this.userModelPath = '';
    this.lastResult = this.emptyResult();
    try {
      this.gateway.destroyEngine(handleToDestroy);
      LOGGER.info('engine disposed');
    } catch (err) {
      LOGGER.warn(`engine dispose failed: ${JSON.stringify(err)}`);
    }
  }

  processKey(key: string): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    this.lastResult = this.applyOutputMode(this.gateway.processKey(this.handle, key));
    return this.lastResult;
  }

  insertSegmentBoundary(): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    const result = this.applyOutputMode(this.gateway.insertSegmentBoundary(this.handle));
    if (result.success) {
      this.lastResult = result;
    }
    return result;
  }

  backspace(): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    this.lastResult = this.applyOutputMode(this.gateway.backspace(this.handle));
    return this.lastResult;
  }

  reset(): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    this.lastResult = this.applyOutputMode(this.gateway.reset(this.handle));
    return this.lastResult;
  }

  changeScheme(schemeId: string, codeTableBundlePath?: string): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    if (schemeId === 'xiaohe-yinxing' && codeTableBundlePath &&
      this.loadedCodeTableBundlePath !== codeTableBundlePath) {
      return this.recreateWithCodeTableBundle(schemeId, codeTableBundlePath);
    }
    const result = this.applyOutputMode(this.gateway.changeScheme(this.handle, schemeId));
    if (result.success) {
      this.lastResult = result;
      this.activeSchemeId = schemeId;
      if (this.initializationConfig) {
        this.initializationConfig.schemeId = schemeId;
      }
      LOGGER.info(
        `engine scheme active: version=${this.gateway.getEngineVersion()}, schemeId=${schemeId}, ` +
          `interface=${this.gateway.getInterfaceVersion()}, native=${this.gateway.getNativeBuildInfo()}`
      );
    }
    return result;
  }

  selectCandidate(candidateIndex: number): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    this.lastResult = this.applyOutputMode(this.gateway.selectCandidate(this.handle, candidateIndex));
    return this.lastResult;
  }

  selectPinyinCombination(combinationIndex: number): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    const result = this.applyOutputMode(this.gateway.selectPinyinCombination(this.handle, combinationIndex));
    if (result.success) {
      this.lastResult = result;
    }
    return result;
  }

  nextCandidatePage(): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    this.lastResult = this.applyOutputMode(this.gateway.nextCandidatePage(this.handle));
    return this.lastResult;
  }

  previousCandidatePage(): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    this.lastResult = this.applyOutputMode(this.gateway.previousCandidatePage(this.handle));
    return this.lastResult;
  }

  getLocalAssociations(): string[] {
    if (!this.ensureInitialized() || this.gateway.getLocalAssociations === undefined) {
      return [];
    }
    const values = this.gateway.getLocalAssociations(this.handle);
    return this.traditionalOutputEnabled ?
      values.map((value: string): string => this.chineseTextConverter.toTraditional(value)) : values;
  }

  getCodeTableCategoryConfig(): CodeTableCategoryConfig {
    if (!this.ensureInitialized()) {
      throw new Error('Input engine is not initialized');
    }
    return this.gateway.getCodeTableCategoryConfig(this.handle);
  }

  setCodeTableCategories(enabledCategoryIds: string[]): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    const result = this.applyOutputMode(this.gateway.setCodeTableCategories(this.handle, enabledCategoryIds));
    if (result.success) {
      this.lastResult = result;
    }
    return result;
  }

  setCodeTableCommitPolicy(
    autoCommitEnabled: boolean,
    emptyClearLength: number
  ): CompositionResult {
    if (!this.ensureInitialized() || this.gateway.setCodeTableCommitPolicy === undefined) {
      return this.failure(ImeErrorCode.NATIVE_BRIDGE_ERROR, 'commit policy update is unavailable');
    }
    const result = this.applyOutputMode(this.gateway.setCodeTableCommitPolicy(
      this.handle,
      autoCommitEnabled,
      emptyClearLength
    ));
    if (result.success) {
      this.lastResult = result;
    }
    return result;
  }

  reloadUserLexicon(): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    const result = this.applyOutputMode(this.gateway.reloadUserLexicon(this.handle));
    if (result.success) {
      this.lastResult = result;
    }
    return result;
  }

  getActiveSchemeId(): string {
    return this.activeSchemeId;
  }

  loadUserModel(path: string): UserModelStatus {
    if (!this.ensureInitialized()) {
      return this.userModelFailure('engine_not_initialized');
    }
    if (path.length <= 0) {
      return this.userModelFailure('invalid_path');
    }

    const pathStatus = this.gateway.setUserModelPath(this.handle, path);
    if (pathStatus.lastErrorCode.length > 0) {
      return pathStatus;
    }
    const loadStatus = this.gateway.loadUserModel(this.handle);
    if (loadStatus.lastErrorCode.length === 0) {
      this.userModelPath = path;
    }
    LOGGER.info(`user model load status: records=${loadStatus.recordCount}, error=${loadStatus.lastErrorCode}`);
    return loadStatus;
  }

  flushUserModel(): UserModelStatus {
    if (!this.ensureInitialized()) {
      return this.userModelFailure('engine_not_initialized');
    }
    const status = this.gateway.flushUserModel(this.handle);
    if (status.lastErrorCode.length > 0) {
      LOGGER.warn(`user model flush status: error=${status.lastErrorCode}`);
    }
    return status;
  }

  clearUserModel(): UserModelStatus {
    if (!this.ensureInitialized()) {
      return this.userModelFailure('engine_not_initialized');
    }
    return this.gateway.clearUserModel(this.handle);
  }

  setUserLearningEnabled(enabled: boolean): UserModelStatus {
    if (!this.ensureInitialized()) {
      return this.userModelFailure('engine_not_initialized');
    }
    const status = this.gateway.setUserLearningEnabled(this.handle, enabled);
    if (status.lastErrorCode.length === 0) {
      this.userLearningEnabled = enabled;
    }
    return status;
  }

  setSessionLearningAllowed(allowed: boolean): UserModelStatus {
    if (!this.ensureInitialized()) {
      return this.userModelFailure('engine_not_initialized');
    }
    const status = this.gateway.setSessionLearningAllowed(this.handle, allowed);
    if (status.lastErrorCode.length === 0) {
      this.sessionLearningAllowed = allowed;
    }
    return status;
  }

  reconfigureQuanpin(
    spellingCorrectionEnabled: boolean,
    fuzzyOptions: FuzzyOptionId[]
  ): CompositionResult {
    if (!this.ensureInitialized()) {
      return this.lastResult;
    }
    const currentConfig = this.initializationConfig;
    if (!currentConfig) {
      return this.failure(ImeErrorCode.NATIVE_BRIDGE_ERROR, 'engine configuration snapshot is unavailable');
    }
    const nextConfig = this.copyConfig(currentConfig);
    nextConfig.quanpinConfigVersion = QUANPIN_CONFIG_VERSION;
    nextConfig.spellingCorrectionEnabled = spellingCorrectionEnabled;
    nextConfig.fuzzyOptions = fuzzyOptions.slice();
    if (this.activeSchemeId !== 'quanpin') {
      this.initializationConfig = nextConfig;
      return this.lastResult;
    }

    let nextHandle: number = 0;
    try {
      nextHandle = this.gateway.createEngine(nextConfig);
      if (this.userModelPath.length > 0) {
        const pathStatus = this.gateway.setUserModelPath(nextHandle, this.userModelPath);
        if (pathStatus.lastErrorCode.length > 0) {
          throw new Error(`user model path restore failed: ${pathStatus.lastErrorCode}`);
        }
        const loadStatus = this.gateway.loadUserModel(nextHandle);
        if (loadStatus.lastErrorCode.length > 0) {
          throw new Error(`user model restore failed: ${loadStatus.lastErrorCode}`);
        }
      }
      const learning = this.gateway.setUserLearningEnabled(nextHandle, this.userLearningEnabled);
      if (learning.lastErrorCode.length > 0) {
        throw new Error(`learning setting restore failed: ${learning.lastErrorCode}`);
      }
      const session = this.gateway.setSessionLearningAllowed(nextHandle, this.sessionLearningAllowed);
      if (session.lastErrorCode.length > 0) {
        throw new Error(`session learning restore failed: ${session.lastErrorCode}`);
      }
    } catch (err) {
      if (nextHandle > 0) {
        try {
          this.gateway.destroyEngine(nextHandle);
        } catch (_destroyErr) {
        }
      }
      const detail = err instanceof Error ? err.message : JSON.stringify(err);
      LOGGER.warn(`quanpin configuration replacement rejected: ${detail}`);
      return this.failure(ImeErrorCode.NATIVE_BRIDGE_ERROR, `quanpin configuration failed: ${detail}`);
    }

    const previousHandle = this.handle;
    this.handle = nextHandle;
    this.initializationConfig = nextConfig;
    this.loadedCodeTableBundlePath = this.loadedBundlePathForConfig(nextConfig);
    this.lastResult = this.emptyResult();
    try {
      this.gateway.flushUserModel(previousHandle);
    } catch (_flushErr) {
    }
    try {
      this.gateway.destroyEngine(previousHandle);
    } catch (_destroyErr) {
    }
    return this.lastResult;
  }

  getCurrentResult(): CompositionResult {
    return this.lastResult;
  }

  hasComposition(): boolean {
    return this.lastResult.rawInput.length > 0;
  }

  isInitialized(): boolean {
    return this.initialized && this.handle > 0;
  }

  private ensureInitialized(): boolean {
    if (this.initialized && this.handle > 0) {
      return true;
    }
    this.lastResult = this.failure(ImeErrorCode.ENGINE_NOT_INITIALIZED, 'engine is not initialized');
    return false;
  }

  private recreateWithCodeTableBundle(schemeId: string, codeTableBundlePath: string): CompositionResult {
    const currentConfig = this.initializationConfig;
    if (!currentConfig || codeTableBundlePath.length <= 0) {
      return this.failure(ImeErrorCode.INVALID_ARGUMENT, 'code table bundle path is unavailable');
    }

    const nextConfig = this.copyConfig(currentConfig);
    nextConfig.schemeId = schemeId;
    nextConfig.codeTableBundlePath = codeTableBundlePath;
    let nextHandle: number = 0;
    try {
      // Create and fully restore the replacement before releasing the live
      // handle. A load failure therefore leaves the old xiaohe engine usable.
      nextHandle = this.gateway.createEngine(nextConfig);
      if (this.userModelPath.length > 0) {
        const pathStatus = this.gateway.setUserModelPath(nextHandle, this.userModelPath);
        if (pathStatus.lastErrorCode.length > 0) {
          throw new Error(`user model path restore failed: ${pathStatus.lastErrorCode}`);
        }
        const loadStatus = this.gateway.loadUserModel(nextHandle);
        if (loadStatus.lastErrorCode.length > 0) {
          throw new Error(`user model restore failed: ${loadStatus.lastErrorCode}`);
        }
      }
      const learningStatus = this.gateway.setUserLearningEnabled(nextHandle, this.userLearningEnabled);
      if (learningStatus.lastErrorCode.length > 0) {
        throw new Error(`learning setting restore failed: ${learningStatus.lastErrorCode}`);
      }
      const sessionStatus = this.gateway.setSessionLearningAllowed(nextHandle, this.sessionLearningAllowed);
      if (sessionStatus.lastErrorCode.length > 0) {
        throw new Error(`session learning restore failed: ${sessionStatus.lastErrorCode}`);
      }
    } catch (err) {
      if (nextHandle > 0) {
        try {
          this.gateway.destroyEngine(nextHandle);
        } catch (_destroyErr) {
        }
      }
      const detail = err instanceof Error ? err.message : JSON.stringify(err);
      LOGGER.warn(`code table engine replacement rejected: ${detail}`);
      return this.failure(ImeErrorCode.NATIVE_BRIDGE_ERROR, `scheme switch failed: ${detail}`);
    }

    const previousHandle = this.handle;
    try {
      this.gateway.flushUserModel(previousHandle);
    } catch (err) {
      LOGGER.warn(`previous user model flush before scheme replacement failed: ${JSON.stringify(err)}`);
    }
    this.handle = nextHandle;
    this.initializationConfig = nextConfig;
    this.loadedCodeTableBundlePath = codeTableBundlePath;
    this.activeSchemeId = schemeId;
    this.lastResult = this.emptyResult();
    try {
      this.gateway.destroyEngine(previousHandle);
    } catch (err) {
      LOGGER.warn(`previous engine destroy after scheme replacement failed: ${JSON.stringify(err)}`);
    }
    LOGGER.info('engine recreated with production code table bundle');
    return this.lastResult;
  }

  private copyConfig(config: EngineConfig): EngineConfig {
    return {
      interfaceVersion: config.interfaceVersion,
      schemeId: config.schemeId,
      lexiconPath: config.lexiconPath,
      codeTableBundlePath: config.codeTableBundlePath,
      userLexiconPath: config.userLexiconPath,
      codeTableActionFixturePath: config.codeTableActionFixturePath,
      codeTableActionFixtureSha256: config.codeTableActionFixtureSha256,
      candidatePageSize: config.candidatePageSize,
      quanpinConfigVersion: config.quanpinConfigVersion,
      spellingCorrectionEnabled: config.spellingCorrectionEnabled,
      fuzzyOptions: config.fuzzyOptions?.slice(),
      quanpinContextRerankingConfigVersion: config.quanpinContextRerankingConfigVersion,
      quanpinContextRerankingEnabled: config.quanpinContextRerankingEnabled,
      quanpinContextModelPath: config.quanpinContextModelPath,
      quanpinContextModelSha256: config.quanpinContextModelSha256
    };
  }

  private loadedBundlePathForConfig(config: EngineConfig): string | undefined {
    if ((config.schemeId === 'xiaohe-yinxing' || config.schemeId === 'code-table-fixture') &&
      config.codeTableBundlePath && config.codeTableBundlePath.length > 0) {
      return config.codeTableBundlePath;
    }
    return undefined;
  }

  private emptyResult(): CompositionResult {
    return {
      success: true,
      errorCode: ImeErrorCode.SUCCESS,
      errorMessage: '',
      rawInput: '',
      preeditText: '',
      parsedSyllables: [],
      pendingCode: '',
      displaySegments: [],
      segmentBoundaries: [],
      currentPinyin: '',
      pinyinCombinations: [],
      parserState: 'empty',
      candidates: [],
      highlightedIndex: -1,
      hasNextPage: false,
      hasPreviousPage: false,
      candidatePage: 0,
      commitText: '',
      action: null,
      compositionFinished: false
    };
  }

  private applyOutputMode(result: CompositionResult): CompositionResult {
    if (!this.traditionalOutputEnabled || !result.success) {
      return result;
    }
    result.candidates.forEach((candidate): void => {
      if (candidate.source !== 'functional') {
        candidate.text = this.chineseTextConverter.toTraditional(candidate.text);
        if (candidate.displayText !== undefined && candidate.displayText.length > 0) {
          candidate.displayText = this.chineseTextConverter.toTraditional(candidate.displayText);
        }
      }
    });
    if (result.action === null && result.commitText.length > 0) {
      result.commitText = this.chineseTextConverter.toTraditional(result.commitText);
    }
    return result;
  }

  private failure(code: ImeErrorCode, message: string): CompositionResult {
    return {
      success: false,
      errorCode: code,
      errorMessage: message,
      rawInput: '',
      preeditText: '',
      parsedSyllables: [],
      pendingCode: '',
      displaySegments: [],
      segmentBoundaries: [],
      currentPinyin: '',
      pinyinCombinations: [],
      parserState: 'empty',
      candidates: [],
      highlightedIndex: -1,
      hasNextPage: false,
      hasPreviousPage: false,
      candidatePage: 0,
      commitText: '',
      action: null,
      compositionFinished: false
    };
  }

  private userModelFailure(lastErrorCode: string): UserModelStatus {
    return {
      loaded: false,
      enabled: false,
      sessionLearningAllowed: false,
      dirty: false,
      recordCount: 0,
      formatVersion: 0,
      dataVersion: 0,
      lastErrorCode
    };
  }
}

let SHARED_ENGINE_COORDINATOR: EngineCoordinator | undefined = undefined;

export function getSharedEngineCoordinator(): EngineCoordinator {
  if (!SHARED_ENGINE_COORDINATOR) {
    SHARED_ENGINE_COORDINATOR = new EngineCoordinator();
  }
  return SHARED_ENGINE_COORDINATOR;
}
