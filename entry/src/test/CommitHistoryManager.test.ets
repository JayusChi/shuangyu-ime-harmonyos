import { describe, it, expect } from '@ohos/hypium';
import { CommitHistoryManager } from '../main/ets/application/CommitHistoryManager';

export default function commitHistoryManagerTest() {
  describe('CommitHistoryManager', () => {
    it('应该能添加提交记录', () => {
      const manager = new CommitHistoryManager();
      manager.addCommit('测试文本');

      const last = manager.getLastCommit();
      expect(last).assertEqual('测试文本');
    });

    it('应该限制历史记录数量', () => {
      const manager = new CommitHistoryManager();

      for (let i = 0; i < 15; i++) {
        manager.addCommit(`文本${i}`);
      }

      expect(manager.getHistorySize()).assertEqual(10);
    });

    it('应该能清空历史记录', () => {
      const manager = new CommitHistoryManager();
      manager.addCommit('测试');
      manager.clear();

      expect(manager.getHistorySize()).assertEqual(0);
      expect(manager.getLastCommit()).assertEqual(null);
    });

    it('应该忽略空文本', () => {
      const manager = new CommitHistoryManager();
      manager.addCommit('');

      expect(manager.getHistorySize()).assertEqual(0);
    });

    it('应该按照最新顺序返回记录', () => {
      const manager = new CommitHistoryManager();
      manager.addCommit('第一条');
      manager.addCommit('第二条');
      manager.addCommit('第三条');

      expect(manager.getCommit(0)).assertEqual('第三条');
      expect(manager.getCommit(1)).assertEqual('第二条');
      expect(manager.getCommit(2)).assertEqual('第一条');
    });

    it('应该返回所有历史记录', () => {
      const manager = new CommitHistoryManager();
      manager.addCommit('文本1');
      manager.addCommit('文本2');

      const records = manager.getAllRecords();
      expect(records.length).assertEqual(2);
      expect(records[0].text).assertEqual('文本2');
      expect(records[1].text).assertEqual('文本1');
    });
  });
}
