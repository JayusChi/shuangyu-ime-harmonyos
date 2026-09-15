import { isConvenienceInput } from '../keyboard/ConvenienceInput';
import { XIAOHE_YINXING_SCHEME_ID } from '../settings/ImeSettings';
import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import { DEFAULT_CANDIDATE_DISPLAY_COUNT } from '../settings/ImeSettings';

/**
 * 候选 UI 必须按方案显式分流，不能再从候选数量或分页字段反推方案语义。
 */
export enum CandidateUiMode {
  BROWSABLE = 'browsable',
  PRECISE_MATCH = 'preciseMatch'
}

export interface CandidateEmptyFeedback {
  visible: boolean;
  text: string;
  accessibilityText: string;
}

const HIDDEN_EMPTY_FEEDBACK: CandidateEmptyFeedback = {
  visible: false,
  text: '',
  accessibilityText: ''
};

function isGuideInput(rawInput: string): boolean {
  return rawInput.startsWith(';');
}

function isUniversalInput(rawInput: string): boolean {
  return rawInput.indexOf('`') >= 0;
}

/**
 * Rust keeps the guide prefix in rawInput so backspace can return from `;f`
 * to `;`, while guide/action candidates expose their table code as `f`.
 * Candidate matching must therefore compare the same code domain.
 */
function comparableInputCode(rawInput: string): string {
  if (rawInput === ';') {
    return '_';
  }
  return isGuideInput(rawInput) ? rawInput.substring(1) : rawInput;
}

export function resolveCandidateUiMode(schemeId: string): CandidateUiMode {
  return schemeId === XIAOHE_YINXING_SCHEME_ID
    ? CandidateUiMode.PRECISE_MATCH
    : CandidateUiMode.BROWSABLE;
}

/**
 * 所有候选模式都允许浏览。是否真正显示展开入口只由可见候选数决定，
 * 精准模式不能再把普通编码（例如 obh）误判为不可展开。
 */
export function allowsCandidateBrowsing(mode: CandidateUiMode, _rawInput: string = ''): boolean {
  return mode === CandidateUiMode.BROWSABLE || mode === CandidateUiMode.PRECISE_MATCH;
}

export function shouldShowCandidateExpansionAction(
  mode: CandidateUiMode,
  candidateCount: number,
  rawInput: string = '',
  displayCount: number = DEFAULT_CANDIDATE_DISPLAY_COUNT,
  hasNextPage: boolean = false,
  contentOverflow: boolean = false
): boolean {
  return allowsCandidateBrowsing(mode, rawInput) && candidateCount > 0 &&
    (candidateCount > displayCount || hasNextPage || (contentOverflow && candidateCount > 1));
}

export function resolveCollapsedCandidates(candidates: Candidate[], displayCount: number): Candidate[] {
  return candidates.slice(0, Math.max(1, displayCount));
}

export function isPreciseMatchHintCandidate(
  mode: CandidateUiMode,
  rawInput: string,
  candidate: Candidate
): boolean {
  const inputCode = comparableInputCode(rawInput);
  return mode === CandidateUiMode.PRECISE_MATCH && inputCode.length > 0 &&
    candidate.reading.length > inputCode.length && candidate.reading.startsWith(inputCode);
}

export function resolveVisibleCandidates(
  mode: CandidateUiMode,
  rawInput: string,
  candidates: Candidate[]
): Candidate[] {
  // The Rust wildcard query has already applied the sound/shape pattern and
  // category rules. Its candidate reading is the matched complete code, not
  // the literal raw pattern containing backticks, so applying the ordinary
  // exact-code filter again would hide every valid universal-key result.
  if (mode !== CandidateUiMode.PRECISE_MATCH || candidates.length === 0 ||
    isUniversalInput(rawInput)) {
    return candidates;
  }
  const inputCode = comparableInputCode(rawInput);
  const exact = candidates.filter((candidate: Candidate) => candidate.reading === inputCode);
  if (exact.length > 0) {
    return exact;
  }
  return candidates
    .filter((candidate: Candidate) => isPreciseMatchHintCandidate(mode, rawInput, candidate))
    .slice(0, 1);
}

/**
 * Resolves a rendered candidate back to the engine snapshot by stable id.
 * ArkUI may proxy or copy @State array items, so object identity is not a
 * reliable key for numbering, highlighting or committing a candidate.
 */
export function resolveCandidateSourceIndex(candidates: Candidate[], candidate: Candidate): number {
  for (let index = 0; index < candidates.length; index++) {
    if (candidates[index].id === candidate.id) {
      return index;
    }
  }
  return -1;
}

export function resolveCandidateCodeHint(
  mode: CandidateUiMode,
  rawInput: string,
  fullCode: string
): string {
  const inputCode = comparableInputCode(rawInput);
  if (mode !== CandidateUiMode.PRECISE_MATCH || inputCode.length === 0) {
    return '';
  }
  const wildcardIndex = inputCode.indexOf('`');
  if (wildcardIndex >= 0) {
    // 万能键结果的 reading 是实际命中的完整码。展示第一个万能位开始的
    // 实际编码，例如 kj`` 命中 kjtv 时显示 tv，避免只看到汉字却不知道
    // 反引号具体替代了什么。
    return fullCode.length > wildcardIndex ? fullCode.substring(wildcardIndex) : fullCode;
  }
  if (fullCode.length <= inputCode.length || !fullCode.startsWith(inputCode)) {
    return '';
  }
  return fullCode.substring(inputCode.length);
}

/**
 * 精准模式没有候选时仍保留可恢复的编码反馈，但不伪造可提交候选。
 */
export function resolveCandidateEmptyFeedback(
  mode: CandidateUiMode,
  rawInput: string
): CandidateEmptyFeedback {
  if (isConvenienceInput(rawInput)) {
    return {
      visible: true,
      text: rawInput.length === 1 ? '数字、日期、算式或英文' : '请继续输入或检查格式',
      accessibilityText: '便捷输入，可输入金额、年月日期、加减乘除算式或临时英文，退格可修改'
    };
  }
  if (mode !== CandidateUiMode.PRECISE_MATCH || rawInput.length === 0) {
    return HIDDEN_EMPTY_FEEDBACK;
  }
  if (isGuideInput(rawInput)) {
    if (comparableInputCode(rawInput).length === 0) {
      return HIDDEN_EMPTY_FEEDBACK;
    }
    return {
      visible: true,
      text: '无匹配引导项',
      accessibilityText: '当前引导码没有匹配候选，可退格修改'
    };
  }
  const inputCode = comparableInputCode(rawInput);
  if (inputCode.length < 4) {
    return {
      visible: true,
      text: '继续输入形码',
      accessibilityText: `已输入 ${inputCode.length} 码，暂无精确简码候选，请继续输入形码`
    };
  }
  return {
    visible: true,
    text: '无匹配全码',
    accessibilityText: '当前完整码没有匹配候选，可退格修改'
  };
}

export function resolveCandidateAccessibilityText(
  mode: CandidateUiMode,
  rawInput: string,
  index: number,
  text: string,
  fullCode: string
): string {
  if (mode !== CandidateUiMode.PRECISE_MATCH) {
    return `第 ${index + 1} 个候选，${text}`;
  }
  if (isGuideInput(rawInput)) {
    return `引导候选，第 ${index + 1} 个，${text}`;
  }
  const codeHint = resolveCandidateCodeHint(mode, rawInput, fullCode);
  if (codeHint.length > 0) {
    if (isUniversalInput(rawInput)) {
      return `万能键候选，第 ${index + 1} 个，${text}，实际编码 ${codeHint}`;
    }
    return `精准匹配提示，第 ${index + 1} 个，${text}，后续编码 ${codeHint}`;
  }
  const kind = rawInput.length >= 4 ? '完整码候选' : '精确简码候选';
  return `${kind}，第 ${index + 1} 个，${text}`;
}
