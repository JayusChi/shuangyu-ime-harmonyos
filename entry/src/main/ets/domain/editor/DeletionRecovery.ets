export const DELETION_RECOVERY_CONTEXT_UNITS: number = 24;

export interface DeletionRecoveryRecord {
  text: string;
  start: number;
  beforeContext: string;
  afterContext: string;
}

/**
 * Holds one verified editor deletion. Recovery is allowed only while the
 * caret and the text immediately around the deleted range still match.
 */
export class DeletionRecoveryManager {
  private lastDeletion?: DeletionRecoveryRecord;

  record(text: string, start: number, beforeContext: string, afterContext: string): boolean {
    if (text.length === 0 || !Number.isInteger(start) || start < 0) {
      this.clear();
      return false;
    }
    this.lastDeletion = {
      text,
      start,
      beforeContext: this.tail(beforeContext),
      afterContext: this.head(afterContext)
    };
    return true;
  }

  getRecord(): DeletionRecoveryRecord | undefined {
    const record = this.lastDeletion;
    if (record === undefined) {
      return undefined;
    }
    return {
      text: record.text,
      start: record.start,
      beforeContext: record.beforeContext,
      afterContext: record.afterContext
    };
  }

  resolve(cursor: number, beforeContext: string, afterContext: string): string | undefined {
    const record = this.lastDeletion;
    if (record === undefined || cursor !== record.start ||
      beforeContext !== record.beforeContext || afterContext !== record.afterContext) {
      return undefined;
    }
    return record.text;
  }

  clear(): void {
    this.lastDeletion = undefined;
  }

  private head(value: string): string {
    return value.slice(0, DELETION_RECOVERY_CONTEXT_UNITS);
  }

  private tail(value: string): string {
    return value.slice(Math.max(0, value.length - DELETION_RECOVERY_CONTEXT_UNITS));
  }
}
