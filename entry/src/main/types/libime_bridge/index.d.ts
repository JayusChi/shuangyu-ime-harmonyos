export type ParserState = 'empty' | 'incomplete' | 'complete' | 'invalid' | 'ambiguous';

export interface EngineConfig {
  interfaceVersion: number;
  schemeId: string;
  lexiconPath?: string;
  codeTableBundlePath?: string;
  userLexiconPath?: string;
  codeTableActionFixturePath?: string;
  codeTableActionFixtureSha256?: string;
  candidatePageSize?: number;
  quanpinConfigVersion?: number;
  spellingCorrectionEnabled?: boolean;
  fuzzyOptions?: Array<'n_l' | 'z_zh' | 'c_ch' | 's_sh' | 'in_ing' | 'en_eng' | 'an_ang' | 'ian_iang'>;
}

export interface Candidate {
  id: string;
  text: string;
  reading: string;
  source: string;
  consumedRawLen?: number;
}

export interface CompositionResult {
  success: boolean;
  errorCode: number;
  errorMessage: string;
  rawInput: string;
  preeditText: string;
  parsedSyllables: string[];
  pendingCode: string;
  displaySegments: string[];
  segmentBoundaries: number[];
  currentPinyin: string;
  pinyinCombinations: string[];
  parserState: ParserState;
  candidates: Candidate[];
  highlightedIndex: number;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  candidatePage: number;
  commitText: string;
  action: {
    type: 'DATE_TIME_TEXT' | 'INSERT_PAIR';
    formatId: '' | 'DATE_ISO' | 'DATE_LOCAL' | 'TIME_HM' | 'DATETIME_LOCAL';
    text: string;
    cursorOffsetUtf16: number;
  } | null;
  compositionFinished: boolean;
}

export interface UserModelStatus {
  loaded: boolean;
  enabled: boolean;
  sessionLearningAllowed: boolean;
  dirty: boolean;
  recordCount: number;
  formatVersion: number;
  dataVersion: number;
  lastErrorCode: string;
}

export interface CodeTableCategoryConfig {
  schemaVersion: number;
  categories: Array<{
    id: string;
    displayName: string;
    kind: 'PRIMARY' | 'PRIMARY_EQUIVALENT' | 'EXTENSION' | 'USER' | 'FUNCTIONAL';
    order: number;
    defaultEnabled: boolean;
    required: boolean;
    userToggleable: boolean;
    authoritativeFile: string;
    entryCount: number;
    sha256: string;
  }>;
  enabledCategoryIds: string[];
}

export interface UserLexiconDocumentJson {
  success: boolean;
  errorCode: string;
  errorLine: number;
  errorField: string;
  message: string;
  warningCode: string;
  revision: string;
  entries: Array<{
    id: string;
    text: string;
    code: string;
    action: 'ADD' | 'DELETE' | 'FIXED' | 'POSITION';
    position: number;
    sourceOrder: number;
  }>;
  stats: {
    accepted: number;
    effective: number;
    added: number;
    deleted: number;
    fixed: number;
    positioned: number;
  };
}

declare const imeBridge: {
  getInterfaceVersion(): number;
  getEngineVersion(): string;
  getNativeBuildInfo(): string;
  createEngine(config: EngineConfig): number;
  createEngineAsync(config: EngineConfig): Promise<number>;
  destroyEngine(handle: number): void;
  processKey(handle: number, key: string): CompositionResult;
  processKeyAsync(handle: number, key: string): Promise<CompositionResult>;
  insertSegmentBoundary(handle: number): CompositionResult;
  backspace(handle: number): CompositionResult;
  reset(handle: number): CompositionResult;
  changeScheme(handle: number, schemeId: string): CompositionResult;
  selectCandidate(handle: number, candidateIndex: number): CompositionResult;
  selectPinyinCombination(handle: number, combinationIndex: number): CompositionResult;
  nextCandidatePage(handle: number): CompositionResult;
  previousCandidatePage(handle: number): CompositionResult;
  getLocalAssociations(handle: number): string;
  reverseLookup(handle: number, text: string): string;
  getCodeTableCategoryConfig(handle: number): string;
  setCodeTableCategories(handle: number, enabledCategoryIds: string[]): CompositionResult;
  setCodeTableCommitPolicy(handle: number, policyJson: string): CompositionResult;
  reloadUserLexicon(handle: number): CompositionResult;
  loadUserLexicon(path: string): string;
  saveUserLexicon(path: string, expectedRevision: string, content: string): string;
  setUserModelPath(handle: number, path: string): UserModelStatus;
  loadUserModel(handle: number): UserModelStatus;
  flushUserModel(handle: number): UserModelStatus;
  clearUserModel(handle: number): UserModelStatus;
  setUserLearningEnabled(handle: number, enabled: boolean): UserModelStatus;
  setSessionLearningAllowed(handle: number, allowed: boolean): UserModelStatus;
};

export const getInterfaceVersion: () => number;
export const getEngineVersion: () => string;
export const getNativeBuildInfo: () => string;
export const createEngine: (config: EngineConfig) => number;
export const createEngineAsync: (config: EngineConfig) => Promise<number>;
export const destroyEngine: (handle: number) => void;
export const processKey: (handle: number, key: string) => CompositionResult;
export const processKeyAsync: (handle: number, key: string) => Promise<CompositionResult>;
export const insertSegmentBoundary: (handle: number) => CompositionResult;
export const backspace: (handle: number) => CompositionResult;
export const reset: (handle: number) => CompositionResult;
export const changeScheme: (handle: number, schemeId: string) => CompositionResult;
export const selectCandidate: (handle: number, candidateIndex: number) => CompositionResult;
export const selectPinyinCombination: (handle: number, combinationIndex: number) => CompositionResult;
export const nextCandidatePage: (handle: number) => CompositionResult;
export const previousCandidatePage: (handle: number) => CompositionResult;
export const getLocalAssociations: (handle: number) => string;
export const reverseLookup: (handle: number, text: string) => string;
export const getCodeTableCategoryConfig: (handle: number) => string;
export const setCodeTableCategories: (handle: number, enabledCategoryIds: string[]) => CompositionResult;
export const setCodeTableCommitPolicy: (handle: number, policyJson: string) => CompositionResult;
export const reloadUserLexicon: (handle: number) => CompositionResult;
export const loadUserLexicon: (path: string) => string;
export const saveUserLexicon: (path: string, expectedRevision: string, content: string) => string;
export const setUserModelPath: (handle: number, path: string) => UserModelStatus;
export const loadUserModel: (handle: number) => UserModelStatus;
export const flushUserModel: (handle: number) => UserModelStatus;
export const clearUserModel: (handle: number) => UserModelStatus;
export const setUserLearningEnabled: (handle: number, enabled: boolean) => UserModelStatus;
export const setSessionLearningAllowed: (handle: number, allowed: boolean) => UserModelStatus;
export default imeBridge;
