/**
 * 上屏历史管理器 - 维护最近N次上屏记录
 */
export interface CommitRecord {
  text: string;
  timestamp: number;
  length: number; // UTF-16 长度
}

export class CommitHistoryManager {
  private history: CommitRecord[] = [];
  private readonly maxSize: number = 10;

  /**
   * 添加一条上屏记录
   */
  addCommit(text: string): void {
    if (text.length === 0) {
      return;
    }

    const record: CommitRecord = {
      text: text,
      timestamp: Date.now(),
      length: text.length
    };

    this.history.unshift(record);

    if (this.history.length > this.maxSize) {
      this.history.pop();
    }
  }

  /**
   * 获取最后一次上屏内容
   */
  getLastCommit(): string | null {
    return this.getCommit(0);
  }

  /**
   * 获取第N次上屏内容(0=最近一次)
   */
  getCommit(index: number): string | null {
    if (index < 0 || index >= this.history.length) {
      return null;
    }
    return this.history[index].text;
  }

  /**
   * 获取历史记录数量
   */
  getHistorySize(): number {
    return this.history.length;
  }

  /**
   * 清空历史记录
   */
  clear(): void {
    this.history = [];
  }

  /**
   * 获取所有历史记录(用于UI展示)
   */
  getAllRecords(): CommitRecord[] {
    return [...this.history];
  }
}
