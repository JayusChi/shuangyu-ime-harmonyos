import imeBridge from 'libime_bridge.so';
import { ImeErrorCode } from '../../common/error/ImeError';
import { Logger } from '../../common/logging/Logger';
import {
  Candidate,
  CodeTableCategoryConfig,
  CodeTableCategoryDefinition,
  CompositionResult,
  EngineConfig,
  NativeEngineGatewayContract,
  ParserState,
  ProtocolAction,
  UserLexiconDocument,
  UserLexiconEntryRecord,
  UserLexiconStatsRecord,
  UserModelStatus
} from './NativeEngineTypes';

const TAG = 'Stage0NativeGateway';
const LOGGER = new Logger(TAG);
const EXPECTED_INTERFACE_VERSION = 10;

export class NativeEngineGateway implements NativeEngineGatewayContract {
  getInterfaceVersion(): number {
    try {
      const version: number = imeBridge.getInterfaceVersion();
      if (!Number.isInteger(version) || version <= 0) {
        return 0;
      }
      return version;
    } catch (err) {
      LOGGER.error(`getInterfaceVersion failed: ${JSON.stringify(err)}`);
      return 0;
    }
  }

  getEngineVersion(): string {
    try {
      const version: string = imeBridge.getEngineVersion();
      LOGGER.info(`getEngineVersion ok: ${version}`);
      return version;
    } catch (err) {
      LOGGER.error(`getEngineVersion failed: ${JSON.stringify(err)}`);
      return '';
    }
  }

  getNativeBuildInfo(): string {
    try {
      const buildInfo: string = imeBridge.getNativeBuildInfo();
      LOGGER.info(`getNativeBuildInfo ok: ${buildInfo}`);
      return buildInfo;
    } catch (err) {
      LOGGER.error(`getNativeBuildInfo failed: ${JSON.stringify(err)}`);
      return '';
    }
  }

  createEngine(config: EngineConfig): number {
    const nativeVersion = this.getInterfaceVersion();
    if (nativeVersion !== EXPECTED_INTERFACE_VERSION || config.interfaceVersion !== EXPECTED_INTERFACE_VERSION) {
      throw new Error('Native interface version mismatch');
    }

    const handle: number = imeBridge.createEngine(config);
    if (!Number.isInteger(handle) || handle <= 0) {
      throw new Error('Native returned invalid engine handle');
    }
    return handle;
  }

  destroyEngine(handle: number): void {
    imeBridge.destroyEngine(handle);
  }

  processKey(handle: number, key: string): CompositionResult {
    try {
      const nativeResult = imeBridge.processKey(handle, key) as CompositionResult;
      return this.normalizeCompositionResult(nativeResult);
    } catch (err) {
      LOGGER.error(`processKey failed: ${JSON.stringify(err)}`);
      return this.createCompositionFailure(ImeErrorCode.NATIVE_BRIDGE_ERROR, 'Native processKey failed');
    }
  }

  insertSegmentBoundary(handle: number): CompositionResult {
    try {
      const nativeResult = imeBridge.insertSegmentBoundary(handle) as CompositionResult;
      return this.normalizeCompositionResult(nativeResult);
    } catch (err) {
      LOGGER.error(`insertSegmentBoundary failed: ${JSON.stringify(err)}`);
      return this.createCompositionFailure(
        ImeErrorCode.NATIVE_BRIDGE_ERROR,
        'Native insertSegmentBoundary failed'
      );
    }
  }

  backspace(handle: number): CompositionResult {
    try {
      const nativeResult = imeBridge.backspace(handle) as CompositionResult;
      return this.normalizeCompositionResult(nativeResult);
    } catch (err) {
      LOGGER.error(`backspace failed: ${JSON.stringify(err)}`);
      return this.createCompositionFailure(ImeErrorCode.NATIVE_BRIDGE_ERROR, 'Native backspace failed');
    }
  }

  reset(handle: number): CompositionResult {
    try {
      const nativeResult = imeBridge.reset(handle) as CompositionResult;
      return this.normalizeCompositionResult(nativeResult);
    } catch (err) {
      LOGGER.error(`reset failed: ${JSON.stringify(err)}`);
      return this.createCompositionFailure(ImeErrorCode.NATIVE_BRIDGE_ERROR, 'Native reset failed');
    }
  }

  changeScheme(handle: number, schemeId: string): CompositionResult {
    try {
      const nativeResult = imeBridge.changeScheme(handle, schemeId) as CompositionResult;
      return this.normalizeCompositionResult(nativeResult);
    } catch (err) {
      LOGGER.error(`changeScheme failed: ${JSON.stringify(err)}`);
      return this.createCompositionFailure(ImeErrorCode.NATIVE_BRIDGE_ERROR, 'Native changeScheme failed');
    }
  }

  selectCandidate(handle: number, candidateIndex: number): CompositionResult {
    try {
      const nativeResult = imeBridge.selectCandidate(handle, candidateIndex) as CompositionResult;
      return this.normalizeCompositionResult(nativeResult);
    } catch (err) {
      LOGGER.error(`selectCandidate failed: ${JSON.stringify(err)}`);
      return this.createCompositionFailure(ImeErrorCode.NATIVE_BRIDGE_ERROR, 'Native selectCandidate failed');
    }
  }

  selectPinyinCombination(handle: number, combinationIndex: number): CompositionResult {
    try {
      const nativeResult = imeBridge.selectPinyinCombination(handle, combinationIndex) as CompositionResult;
      return this.normalizeCompositionResult(nativeResult);
    } catch (err) {
      LOGGER.error(`selectPinyinCombination failed: ${JSON.stringify(err)}`);
      return this.createCompositionFailure(
        ImeErrorCode.NATIVE_BRIDGE_ERROR,
        'Native pinyin combination selection failed'
      );
    }
  }

  nextCandidatePage(handle: number): CompositionResult {
    try {
      const nativeResult = imeBridge.nextCandidatePage(handle) as CompositionResult;
      return this.normalizeCompositionResult(nativeResult);
    } catch (err) {
      LOGGER.error(`nextCandidatePage failed: ${JSON.stringify(err)}`);
      return this.createCompositionFailure(ImeErrorCode.NATIVE_BRIDGE_ERROR, 'Native nextCandidatePage failed');
    }
  }

  previousCandidatePage(handle: number): CompositionResult {
    try {
      const nativeResult = imeBridge.previousCandidatePage(handle) as CompositionResult;
      return this.normalizeCompositionResult(nativeResult);
    } catch (err) {
      LOGGER.error(`previousCandidatePage failed: ${JSON.stringify(err)}`);
      return this.createCompositionFailure(ImeErrorCode.NATIVE_BRIDGE_ERROR, 'Native previousCandidatePage failed');
    }
  }

  getLocalAssociations(handle: number): string[] {
    try {
      const json: string = imeBridge.getLocalAssociations(handle);
      const parsed = JSON.parse(json) as string[];
      if (!Array.isArray(parsed) || parsed.length > 3) {
        return [];
      }
      const output: string[] = [];
      parsed.forEach((text: string): void => {
        if (typeof text === 'string' && text.length > 0 && text.length <= 48 &&
          output.indexOf(text) < 0) {
          output.push(text);
        }
      });
      return output.length === parsed.length ? output : [];
    } catch (err) {
      LOGGER.warn(`getLocalAssociations failed: ${JSON.stringify(err)}`);
      return [];
    }
  }

  getCodeTableCategoryConfig(handle: number): CodeTableCategoryConfig {
    try {
      const json: string = imeBridge.getCodeTableCategoryConfig(handle);
      return this.normalizeCodeTableCategoryConfig(JSON.parse(json) as CodeTableCategoryConfig);
    } catch (err) {
      LOGGER.error(`getCodeTableCategoryConfig failed: ${JSON.stringify(err)}`);
      throw new Error('Native category configuration unavailable');
    }
  }

  setCodeTableCategories(handle: number, enabledCategoryIds: string[]): CompositionResult {
    try {
      const nativeResult = imeBridge.setCodeTableCategories(handle, enabledCategoryIds) as CompositionResult;
      return this.normalizeCompositionResult(nativeResult);
    } catch (err) {
      LOGGER.error(`setCodeTableCategories failed: ${JSON.stringify(err)}`);
      return this.createCompositionFailure(
        ImeErrorCode.NATIVE_BRIDGE_ERROR,
        'Native category update failed'
      );
    }
  }

  reloadUserLexicon(handle: number): CompositionResult {
    try {
      const nativeResult = imeBridge.reloadUserLexicon(handle) as CompositionResult;
      return this.normalizeCompositionResult(nativeResult);
    } catch (err) {
      LOGGER.error(`reloadUserLexicon failed: ${JSON.stringify(err)}`);
      return this.createCompositionFailure(
        ImeErrorCode.NATIVE_BRIDGE_ERROR,
        'Native user lexicon reload failed'
      );
    }
  }

  loadUserLexicon(path: string): UserLexiconDocument {
    try {
      const json: string = imeBridge.loadUserLexicon(path);
      return this.normalizeUserLexiconDocument(JSON.parse(json) as UserLexiconDocument);
    } catch (err) {
      LOGGER.error(`loadUserLexicon failed: ${JSON.stringify(err)}`);
      return this.userLexiconFailure('native_bridge_error', '用户词库读取失败');
    }
  }

  saveUserLexicon(path: string, expectedRevision: string, content: string): UserLexiconDocument {
    try {
      const json: string = imeBridge.saveUserLexicon(path, expectedRevision, content);
      return this.normalizeUserLexiconDocument(JSON.parse(json) as UserLexiconDocument);
    } catch (err) {
      LOGGER.error(`saveUserLexicon failed: ${JSON.stringify(err)}`);
      return this.userLexiconFailure('native_bridge_error', '用户词库保存失败');
    }
  }

  setUserModelPath(handle: number, path: string): UserModelStatus {
    try {
      const nativeResult = imeBridge.setUserModelPath(handle, path) as UserModelStatus;
      return this.normalizeUserModelStatus(nativeResult);
    } catch (err) {
      LOGGER.error(`setUserModelPath failed: ${JSON.stringify(err)}`);
      return this.createUserModelStatusFailure('native_bridge_error');
    }
  }

  loadUserModel(handle: number): UserModelStatus {
    try {
      const nativeResult = imeBridge.loadUserModel(handle) as UserModelStatus;
      return this.normalizeUserModelStatus(nativeResult);
    } catch (err) {
      LOGGER.error(`loadUserModel failed: ${JSON.stringify(err)}`);
      return this.createUserModelStatusFailure('native_bridge_error');
    }
  }

  flushUserModel(handle: number): UserModelStatus {
    try {
      const nativeResult = imeBridge.flushUserModel(handle) as UserModelStatus;
      return this.normalizeUserModelStatus(nativeResult);
    } catch (err) {
      LOGGER.error(`flushUserModel failed: ${JSON.stringify(err)}`);
      return this.createUserModelStatusFailure('native_bridge_error');
    }
  }

  clearUserModel(handle: number): UserModelStatus {
    try {
      const nativeResult = imeBridge.clearUserModel(handle) as UserModelStatus;
      return this.normalizeUserModelStatus(nativeResult);
    } catch (err) {
      LOGGER.error(`clearUserModel failed: ${JSON.stringify(err)}`);
      return this.createUserModelStatusFailure('native_bridge_error');
    }
  }

  setUserLearningEnabled(handle: number, enabled: boolean): UserModelStatus {
    try {
      const nativeResult = imeBridge.setUserLearningEnabled(handle, enabled) as UserModelStatus;
      return this.normalizeUserModelStatus(nativeResult);
    } catch (err) {
      LOGGER.error(`setUserLearningEnabled failed: ${JSON.stringify(err)}`);
      return this.createUserModelStatusFailure('native_bridge_error');
    }
  }

  setSessionLearningAllowed(handle: number, allowed: boolean): UserModelStatus {
    try {
      const nativeResult = imeBridge.setSessionLearningAllowed(handle, allowed) as UserModelStatus;
      return this.normalizeUserModelStatus(nativeResult);
    } catch (err) {
      LOGGER.error(`setSessionLearningAllowed failed: ${JSON.stringify(err)}`);
      return this.createUserModelStatusFailure('native_bridge_error');
    }
  }

  private normalizeCompositionResult(nativeResult: CompositionResult): CompositionResult {
    if (typeof nativeResult.success !== 'boolean' ||
      typeof nativeResult.errorCode !== 'number' ||
      typeof nativeResult.errorMessage !== 'string' ||
      typeof nativeResult.rawInput !== 'string' ||
      typeof nativeResult.preeditText !== 'string' ||
      typeof nativeResult.pendingCode !== 'string' ||
      typeof nativeResult.currentPinyin !== 'string' ||
      typeof nativeResult.parserState !== 'string' ||
      typeof nativeResult.highlightedIndex !== 'number' ||
      typeof nativeResult.hasNextPage !== 'boolean' ||
      typeof nativeResult.hasPreviousPage !== 'boolean' ||
      typeof nativeResult.candidatePage !== 'number' ||
      typeof nativeResult.commitText !== 'string' ||
      typeof nativeResult.compositionFinished !== 'boolean') {
      return this.createCompositionFailure(ImeErrorCode.SERIALIZATION_ERROR, 'Native composition fields are invalid');
    }
    if (!this.isParserState(nativeResult.parserState)) {
      return this.createCompositionFailure(ImeErrorCode.SERIALIZATION_ERROR, 'Native parserState is invalid');
    }

    if (nativeResult.action === undefined) {
      return this.createCompositionFailure(ImeErrorCode.SERIALIZATION_ERROR, 'Native action field is missing');
    }
    const action: ProtocolAction | null = this.normalizeProtocolAction(nativeResult.action);
    if (nativeResult.action !== null && action === null) {
      return this.createCompositionFailure(ImeErrorCode.SERIALIZATION_ERROR, 'Native action is invalid');
    }
    if (action !== null && nativeResult.commitText.length > 0) {
      return this.createCompositionFailure(ImeErrorCode.SERIALIZATION_ERROR, 'Native commitText and action conflict');
    }

    const parsedSyllables: string[] = [];
    nativeResult.parsedSyllables.forEach((syllable: string) => {
      if (typeof syllable === 'string') {
        parsedSyllables.push(syllable);
      }
    });

    const displaySegments: string[] = [];
    nativeResult.displaySegments?.forEach((segment: string) => {
      if (typeof segment === 'string' && segment.length > 0) {
        displaySegments.push(segment);
      }
    });

    const pinyinCombinations: string[] = [];
    nativeResult.pinyinCombinations?.forEach((combination: string) => {
      if (typeof combination === 'string' && combination.length > 0) {
        pinyinCombinations.push(combination);
      }
    });

    const candidates: Candidate[] = [];
    nativeResult.candidates.forEach((candidate: Candidate) => {
      if (typeof candidate.id === 'string' &&
        typeof candidate.text === 'string' &&
        typeof candidate.reading === 'string' &&
        typeof candidate.source === 'string') {
        candidates.push({
          id: candidate.id,
          text: candidate.text,
          reading: candidate.reading,
          source: candidate.source,
          consumedRawLen: Number.isInteger(candidate.consumedRawLen) &&
            (candidate.consumedRawLen ?? 0) >= 0 ? candidate.consumedRawLen : 0
        });
      }
    });

    const segmentBoundaries: number[] = [];
    nativeResult.segmentBoundaries?.forEach((boundary: number) => {
      if (Number.isInteger(boundary) && boundary >= 0) {
        segmentBoundaries.push(boundary);
      }
    });

    return {
      success: nativeResult.success,
      errorCode: nativeResult.errorCode,
      errorMessage: nativeResult.errorMessage,
      rawInput: nativeResult.rawInput,
      preeditText: nativeResult.preeditText,
      parsedSyllables,
      pendingCode: nativeResult.pendingCode,
      displaySegments,
      segmentBoundaries,
      currentPinyin: nativeResult.currentPinyin,
      pinyinCombinations,
      parserState: nativeResult.parserState as ParserState,
      candidates,
      highlightedIndex: nativeResult.highlightedIndex,
      hasNextPage: nativeResult.hasNextPage,
      hasPreviousPage: nativeResult.hasPreviousPage,
      candidatePage: nativeResult.candidatePage,
      commitText: nativeResult.commitText,
      action,
      compositionFinished: nativeResult.compositionFinished
    };
  }

  private normalizeProtocolAction(value: ProtocolAction | null): ProtocolAction | null {
    if (value === null || typeof value !== 'object') {
      return null;
    }
    if (value.type === 'DATE_TIME_TEXT') {
      if ((value.formatId === 'DATE_ISO' || value.formatId === 'DATE_LOCAL' ||
        value.formatId === 'DATE_LOCAL_UNPADDED' ||
        value.formatId === 'TIME_HM' || value.formatId === 'TIME_HMS' ||
        value.formatId === 'TIME_LOCAL_HMS' || value.formatId === 'DATETIME_LOCAL' ||
        value.formatId === 'UNIX_TIMESTAMP') &&
        value.text === '' && value.cursorOffsetUtf16 === 0) {
        return {
          type: 'DATE_TIME_TEXT',
          formatId: value.formatId,
          text: '',
          cursorOffsetUtf16: 0
        };
      }
      return null;
    }
    if (value.type === 'INSERT_PAIR' && value.formatId === '' &&
      typeof value.text === 'string' && value.text.length > 1 && value.text.length <= 64 &&
      Number.isInteger(value.cursorOffsetUtf16) && value.cursorOffsetUtf16 > 0 &&
      value.cursorOffsetUtf16 <= 16 && value.cursorOffsetUtf16 < value.text.length) {
      return {
        type: 'INSERT_PAIR',
        formatId: '',
        text: value.text,
        cursorOffsetUtf16: value.cursorOffsetUtf16
      };
    }
    if ((value.type === 'REPEAT_COMMIT' || value.type === 'UNDO_COMMIT' ||
      value.type === 'MOVE_LINE_END') && value.formatId === '' && value.text === '' &&
      value.cursorOffsetUtf16 === 0) {
      return {
        type: value.type,
        formatId: '',
        text: '',
        cursorOffsetUtf16: 0
      };
    }
    if (value.type === 'DIRECT_CONTROL' && value.cursorOffsetUtf16 === 0 &&
      (value.formatId === 'category.enable' || value.formatId === 'category.disable' ||
        value.formatId === 'category.toggle' || value.formatId === 'category.set' ||
        value.formatId === 'category.all' || value.formatId === 'category.core') &&
      typeof value.text === 'string' && value.text.length <= 512 && /^[a-z0-9,-]*$/.test(value.text)) {
      return {
        type: 'DIRECT_CONTROL',
        formatId: value.formatId,
        text: value.text,
        cursorOffsetUtf16: 0
      };
    }
    if (value.type === 'IMPORT_USER_LEXICON' && value.formatId === '' && value.text === '' &&
      value.cursorOffsetUtf16 === 0) {
      return {
        type: 'IMPORT_USER_LEXICON',
        formatId: '',
        text: '',
        cursorOffsetUtf16: 0
      };
    }
    return null;
  }

  private isParserState(value: string): boolean {
    return value === 'empty' ||
      value === 'incomplete' ||
      value === 'complete' ||
      value === 'invalid' ||
      value === 'ambiguous';
  }

  private normalizeUserModelStatus(nativeResult: UserModelStatus): UserModelStatus {
    if (typeof nativeResult.loaded !== 'boolean' ||
      typeof nativeResult.enabled !== 'boolean' ||
      typeof nativeResult.sessionLearningAllowed !== 'boolean' ||
      typeof nativeResult.dirty !== 'boolean' ||
      typeof nativeResult.recordCount !== 'number' ||
      typeof nativeResult.formatVersion !== 'number' ||
      typeof nativeResult.dataVersion !== 'number' ||
      typeof nativeResult.lastErrorCode !== 'string') {
      return this.createUserModelStatusFailure('serialization_error');
    }
    return {
      loaded: nativeResult.loaded,
      enabled: nativeResult.enabled,
      sessionLearningAllowed: nativeResult.sessionLearningAllowed,
      dirty: nativeResult.dirty,
      recordCount: nativeResult.recordCount,
      formatVersion: nativeResult.formatVersion,
      dataVersion: nativeResult.dataVersion,
      lastErrorCode: nativeResult.lastErrorCode
    };
  }

  private normalizeCodeTableCategoryConfig(nativeConfig: CodeTableCategoryConfig): CodeTableCategoryConfig {
    if (!Number.isInteger(nativeConfig.schemaVersion) ||
      !Array.isArray(nativeConfig.categories) ||
      !Array.isArray(nativeConfig.enabledCategoryIds)) {
      throw new Error('Invalid category configuration');
    }
    const categories: CodeTableCategoryDefinition[] = [];
    nativeConfig.categories.forEach((category: CodeTableCategoryDefinition) => {
      if (typeof category.id !== 'string' ||
        typeof category.displayName !== 'string' ||
        !this.isCategoryKind(category.kind) ||
        !Number.isInteger(category.order) ||
        typeof category.defaultEnabled !== 'boolean' ||
        typeof category.required !== 'boolean' ||
        typeof category.userToggleable !== 'boolean' ||
        typeof category.authoritativeFile !== 'string' ||
        !Number.isInteger(category.entryCount) ||
        typeof category.sha256 !== 'string') {
        throw new Error('Invalid category definition');
      }
      categories.push({
        id: category.id,
        displayName: category.displayName,
        kind: category.kind,
        order: category.order,
        defaultEnabled: category.defaultEnabled,
        required: category.required,
        userToggleable: category.userToggleable,
        authoritativeFile: category.authoritativeFile,
        entryCount: category.entryCount,
        sha256: category.sha256
      });
    });
    const enabledCategoryIds: string[] = [];
    nativeConfig.enabledCategoryIds.forEach((id: string) => {
      if (typeof id !== 'string') {
        throw new Error('Invalid enabled category id');
      }
      enabledCategoryIds.push(id);
    });
    return {
      schemaVersion: nativeConfig.schemaVersion,
      categories,
      enabledCategoryIds
    };
  }

  private normalizeUserLexiconDocument(nativeDocument: UserLexiconDocument): UserLexiconDocument {
    if (typeof nativeDocument.success !== 'boolean' ||
      typeof nativeDocument.errorCode !== 'string' ||
      !Number.isInteger(nativeDocument.errorLine) ||
      typeof nativeDocument.errorField !== 'string' ||
      typeof nativeDocument.message !== 'string' ||
      typeof nativeDocument.warningCode !== 'string' ||
      typeof nativeDocument.revision !== 'string' ||
      !Array.isArray(nativeDocument.entries) ||
      typeof nativeDocument.stats !== 'object' || nativeDocument.stats === null) {
      return this.userLexiconFailure('serialization_error', '用户词库数据格式无效');
    }
    const entries: UserLexiconEntryRecord[] = [];
    nativeDocument.entries.forEach((entry: UserLexiconEntryRecord) => {
      if (typeof entry.id !== 'string' || typeof entry.text !== 'string' ||
        typeof entry.code !== 'string' || !this.isUserLexiconAction(entry.action) ||
        !Number.isInteger(entry.position) || !Number.isInteger(entry.sourceOrder)) {
        throw new Error('Invalid user lexicon entry');
      }
      entries.push({
        id: entry.id,
        text: entry.text,
        code: entry.code,
        action: entry.action,
        position: entry.position,
        sourceOrder: entry.sourceOrder
      });
    });
    const stats = nativeDocument.stats as UserLexiconStatsRecord;
    if (!Number.isInteger(stats.accepted) || !Number.isInteger(stats.effective) ||
      !Number.isInteger(stats.added) || !Number.isInteger(stats.deleted) ||
      !Number.isInteger(stats.fixed) || !Number.isInteger(stats.positioned)) {
      return this.userLexiconFailure('serialization_error', '用户词库统计格式无效');
    }
    return {
      success: nativeDocument.success,
      errorCode: nativeDocument.errorCode,
      errorLine: nativeDocument.errorLine,
      errorField: nativeDocument.errorField,
      message: nativeDocument.message,
      warningCode: nativeDocument.warningCode,
      revision: nativeDocument.revision,
      entries,
      stats: {
        accepted: stats.accepted,
        effective: stats.effective,
        added: stats.added,
        deleted: stats.deleted,
        fixed: stats.fixed,
        positioned: stats.positioned
      }
    };
  }

  private isUserLexiconAction(value: string): boolean {
    return value === 'ADD' || value === 'DELETE' || value === 'FIXED' || value === 'POSITION';
  }

  private isCategoryKind(value: string): boolean {
    return value === 'PRIMARY' ||
      value === 'PRIMARY_EQUIVALENT' ||
      value === 'EXTENSION' ||
      value === 'USER' ||
      value === 'FUNCTIONAL';
  }

  private createUserModelStatusFailure(lastErrorCode: string): UserModelStatus {
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

  private userLexiconFailure(errorCode: string, message: string): UserLexiconDocument {
    return {
      success: false,
      errorCode,
      errorLine: 0,
      errorField: '',
      message,
      warningCode: '',
      revision: '',
      entries: [],
      stats: { accepted: 0, effective: 0, added: 0, deleted: 0, fixed: 0, positioned: 0 }
    };
  }

  private createCompositionFailure(code: ImeErrorCode, message: string): CompositionResult {
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
}
