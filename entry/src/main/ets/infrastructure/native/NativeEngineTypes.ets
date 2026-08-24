export type ParserState =
  'empty' |
  'incomplete' |
  'complete' |
  'invalid' |
  'ambiguous';

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
  fuzzyOptions?: FuzzyOptionId[];
  quanpinContextRerankingConfigVersion?: number;
  quanpinContextRerankingEnabled?: boolean;
  quanpinContextModelPath?: string;
  quanpinContextModelSha256?: string;
}

export type FuzzyOptionId = 'n_l' | 'z_zh' | 'c_ch' | 's_sh' |
  'in_ing' | 'en_eng' | 'an_ang' | 'ian_iang';

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
  displaySegments?: string[];
  segmentBoundaries?: number[];
  currentPinyin?: string;
  pinyinCombinations?: string[];
  parserState: ParserState;
  candidates: Candidate[];
  highlightedIndex: number;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  candidatePage: number;
  commitText: string;
  action: ProtocolAction | null;
  compositionFinished: boolean;
}

export type DateTimeFormatId = 'DATE_ISO' | 'DATE_LOCAL' | 'DATE_LOCAL_UNPADDED' | 'TIME_HM' | 'TIME_HMS' |
  'TIME_LOCAL_HMS' | 'DATETIME_LOCAL' | 'UNIX_TIMESTAMP';

export interface DateTimeTextAction {
  type: 'DATE_TIME_TEXT';
  formatId: DateTimeFormatId;
  text: '';
  cursorOffsetUtf16: 0;
}

export interface InsertPairAction {
  type: 'INSERT_PAIR';
  formatId: '';
  text: string;
  cursorOffsetUtf16: number;
}

export interface RepeatCommitAction {
  type: 'REPEAT_COMMIT';
  formatId: '';
  text: '';
  cursorOffsetUtf16: 0;
}

export interface UndoCommitAction {
  type: 'UNDO_COMMIT';
  formatId: '';
  text: '';
  cursorOffsetUtf16: 0;
}

export interface MoveLineEndAction {
  type: 'MOVE_LINE_END';
  formatId: '';
  text: '';
  cursorOffsetUtf16: 0;
}

export interface DirectControlAction {
  type: 'DIRECT_CONTROL';
  formatId: string;
  text: string;
  cursorOffsetUtf16: 0;
}

export interface ImportUserLexiconAction {
  type: 'IMPORT_USER_LEXICON';
  formatId: '';
  text: '';
  cursorOffsetUtf16: 0;
}

export type ProtocolAction = DateTimeTextAction | InsertPairAction | RepeatCommitAction |
  UndoCommitAction | MoveLineEndAction | DirectControlAction | ImportUserLexiconAction;

export type CodeTableCategoryKind =
  'PRIMARY' |
  'PRIMARY_EQUIVALENT' |
  'EXTENSION' |
  'USER' |
  'FUNCTIONAL';

export interface CodeTableCategoryDefinition {
  id: string;
  displayName: string;
  kind: CodeTableCategoryKind;
  order: number;
  defaultEnabled: boolean;
  required: boolean;
  userToggleable: boolean;
  authoritativeFile: string;
  entryCount: number;
  sha256: string;
}

export interface CodeTableCategoryConfig {
  schemaVersion: number;
  categories: CodeTableCategoryDefinition[];
  enabledCategoryIds: string[];
}

export type UserLexiconActionType = 'ADD' | 'DELETE' | 'FIXED' | 'POSITION';

export interface UserLexiconEntryRecord {
  id: string;
  text: string;
  code: string;
  action: UserLexiconActionType;
  position: number;
  sourceOrder: number;
}

export interface UserLexiconStatsRecord {
  accepted: number;
  effective: number;
  added: number;
  deleted: number;
  fixed: number;
  positioned: number;
}

export interface UserLexiconDocument {
  success: boolean;
  errorCode: string;
  errorLine: number;
  errorField: string;
  message: string;
  warningCode: string;
  revision: string;
  entries: UserLexiconEntryRecord[];
  stats: UserLexiconStatsRecord;
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

export interface NativeEngineGatewayContract {
  getInterfaceVersion(): number;
  getEngineVersion(): string;
  getNativeBuildInfo(): string;
  createEngine(config: EngineConfig): number;
  destroyEngine(handle: number): void;
  processKey(handle: number, key: string): CompositionResult;
  insertSegmentBoundary(handle: number): CompositionResult;
  backspace(handle: number): CompositionResult;
  reset(handle: number): CompositionResult;
  changeScheme(handle: number, schemeId: string): CompositionResult;
  selectCandidate(handle: number, candidateIndex: number): CompositionResult;
  selectPinyinCombination(handle: number, combinationIndex: number): CompositionResult;
  nextCandidatePage(handle: number): CompositionResult;
  previousCandidatePage(handle: number): CompositionResult;
  getLocalAssociations?(handle: number): string[];
  getCodeTableCategoryConfig(handle: number): CodeTableCategoryConfig;
  setCodeTableCategories(handle: number, enabledCategoryIds: string[]): CompositionResult;
  reloadUserLexicon(handle: number): CompositionResult;
  loadUserLexicon(path: string): UserLexiconDocument;
  saveUserLexicon(path: string, expectedRevision: string, content: string): UserLexiconDocument;
  setUserModelPath(handle: number, path: string): UserModelStatus;
  loadUserModel(handle: number): UserModelStatus;
  flushUserModel(handle: number): UserModelStatus;
  clearUserModel(handle: number): UserModelStatus;
  setUserLearningEnabled(handle: number, enabled: boolean): UserModelStatus;
  setSessionLearningAllowed(handle: number, allowed: boolean): UserModelStatus;
}
