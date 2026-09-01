import { XIAOHE_YINXING_SCHEME_ID } from '../settings/ImeSettings';
import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import { MIN_CANDIDATES_FOR_EXPANSION } from './CandidateExpansionPolicy';

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
 * 小鹤双拼保留分页和展开浏览；小鹤音形通常只显示当前精确快照，
 * 但万能键查询会产生一组可浏览的单字候选，因此允许展开。
 */
export function allowsCandidateBrowsing(mode: CandidateUiMode, rawInput: string = ''): boolean {
  return mode === CandidateUiMode.BROWSABLE ||
    (mode === CandidateUiMode.PRECISE_MATCH && isUniversalInput(rawInput));
}

export function shouldShowCandidateExpansionAction(
  mode: CandidateUiMode,
  candidateCount: number,
  rawInput: string = ''
): boolean {
  return allowsCandidateBrowsing(mode, rawInput) &&
    candidateCount >= MIN_CANDIDATES_FOR_EXPANSION;
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
  if (mode !== CandidateUiMode.PRECISE_MATCH || inputCode.length === 0 ||
    fullCode.length <= inputCode.length || !fullCode.startsWith(inputCode)) {
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
    return `精准匹配提示，第 ${index + 1} 个，${text}，后续编码 ${codeHint}`;
  }
  const kind = rawInput.length >= 4 ? '完整码候选' : '精确简码候选';
  return `${kind}，第 ${index + 1} 个，${text}`;
}
