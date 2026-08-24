import { CommitHistoryManager } from './CommitHistoryManager';
import { Logger } from '../common/logging/Logger';

const TAG = 'UndoCommitManager';
const LOGGER = new Logger(TAG);

export interface UndoState {
  canUndo: boolean;
  reason?: string;
  lastCommit?: string;
  lastCommitLength?: number;
  replacementOriginalText?: string;
}

/**
 * 撤销上屏管理器
 */
export class UndoCommitManager {
  private readonly historyManager: CommitHistoryManager;
  private readonly maxUndoTimeMs: number = 5000; // 5秒内可撤销
  private lastUndoableCommit: string | null = null;
  private lastUndoableLength: number = 0;
  private lastCommitTime: number = 0;
  private replacementOriginalText?: string;

  constructor(historyManager: CommitHistoryManager) {
    this.historyManager = historyManager;
  }

  /**
   * 记录一次可撤销的提交
   */
  recordCommit(text: string): void {
    this.lastUndoableCommit = text;
    this.lastUndoableLength = text.length;
    this.lastCommitTime = Date.now();
    this.replacementOriginalText = undefined;
  }

  recordReplacement(originalText: string, replacementText: string): void {
    this.lastUndoableCommit = replacementText;
    this.lastUndoableLength = replacementText.length;
    this.lastCommitTime = Date.now();
    this.replacementOriginalText = originalText;
  }

  /**
   * 检查是否可以撤销
   */
  canUndo(): UndoState {
    if (!this.lastUndoableCommit) {
      return {
        canUndo: false,
        reason: '没有可撤销的内容'
      };
    }

    const elapsed = Date.now() - this.lastCommitTime;
    if (elapsed > this.maxUndoTimeMs) {
      return {
        canUndo: false,
        reason: '撤销时间窗口已过期'
      };
    }

    return {
      canUndo: true,
      lastCommit: this.lastUndoableCommit,
      lastCommitLength: this.lastUndoableLength,
      replacementOriginalText: this.replacementOriginalText
    };
  }

  /**
   * 清除撤销状态
   */
  clearUndoState(): void {
    this.lastUndoableCommit = null;
    this.lastUndoableLength = 0;
    this.lastCommitTime = 0;
    this.replacementOriginalText = undefined;
  }

  /**
   * 用户移动光标后,禁用撤销
   */
  invalidateUndo(): void {
    this.clearUndoState();
  }
}
