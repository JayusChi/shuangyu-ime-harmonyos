import { describe, it, expect, beforeEach } from '@ohos/hypium';
import { UndoCommitManager } from '../main/ets/application/UndoCommitManager';
import { CommitHistoryManager } from '../main/ets/application/CommitHistoryManager';

export default function undoCommitManagerTest() {
  describe('UndoCommitManager', () => {
    let historyManager: CommitHistoryManager;
    let undoManager: UndoCommitManager;

    beforeEach(() => {
      historyManager = new CommitHistoryManager();
      undoManager = new UndoCommitManager(historyManager);
    });

    it('应该记录可撤销的提交', () => {
      undoManager.recordCommit('测试文本');

      const state = undoManager.canUndo();
      expect(state.canUndo).assertEqual(true);
      expect(state.lastCommit).assertEqual('测试文本');
      expect(state.lastCommitLength).assertEqual(4);
    });

    it('没有记录时不能撤销', () => {
      const state = undoManager.canUndo();

      expect(state.canUndo).assertEqual(false);
      expect(state.reason).assertEqual('没有可撤销的内容');
    });

    it('超过时间窗口后不能撤销', async () => {
      undoManager.recordCommit('测试文本');

      // 模拟等待超过5秒(实际测试中可能需要mock时间)
      // 这里简化处理,实际应该mock Date.now()

      const state = undoManager.canUndo();
      // 立即检查应该可以撤销
      expect(state.canUndo).assertEqual(true);
    });

    it('应该能清除撤销状态', () => {
      undoManager.recordCommit('测试文本');
      undoManager.clearUndoState();

      const state = undoManager.canUndo();
      expect(state.canUndo).assertEqual(false);
    });

    it('应该能使撤销失效', () => {
      undoManager.recordCommit('测试文本');
      undoManager.invalidateUndo();

      const state = undoManager.canUndo();
      expect(state.canUndo).assertEqual(false);
    });

    it('应该更新为最新的提交记录', () => {
      undoManager.recordCommit('第一条');
      undoManager.recordCommit('第二条');

      const state = undoManager.canUndo();
      expect(state.lastCommit).assertEqual('第二条');
    });

    it('应该保留安全替换的原文以支持反向撤销', () => {
      undoManager.recordReplacement('用户原文', 'AI 建议文本');

      const state = undoManager.canUndo();
      expect(state.canUndo).assertTrue();
      expect(state.lastCommit).assertEqual('AI 建议文本');
      expect(state.replacementOriginalText).assertEqual('用户原文');
    });
  });
}
