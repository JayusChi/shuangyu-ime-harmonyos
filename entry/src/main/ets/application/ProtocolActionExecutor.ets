import { ProtocolAction } from '../infrastructure/native/NativeEngineTypes';
import { TimeProvider, SystemTimeProvider } from '../infrastructure/time/TimeProvider';
import { SerialActionExecutor } from './SerialActionExecutor';
import { PairInsertResult } from '../infrastructure/ime/ImeConnectionService';

export interface ProtocolActionImeService {
  commitPreviewText(text: string, generation?: number): Promise<boolean>;
  insertPairText?(
    text: string,
    cursorOffsetUtf16: number,
    generation?: number
  ): Promise<PairInsertResult>;
  repeatLastCommit?(): Promise<boolean>;
  undoLastCommit?(): Promise<boolean>;
  moveToLineEnd?(): Promise<boolean>;
}

export interface ProtocolActionHandlers {
  repeatLastCommit?(generation: number): Promise<boolean>;
  undoLastCommit?(generation: number): Promise<boolean>;
  executeDirectControl?(action: string, target: string, generation: number): Promise<boolean>;
  importUserLexicon?(generation: number): Promise<boolean>;
}

class EmptyProtocolActionHandlers implements ProtocolActionHandlers {
}

export enum ProtocolActionExecutionStatus {
  SUCCESS = 'success',
  FAILED = 'failed',
  SESSION_INVALID = 'session_invalid'
}

export interface ProtocolActionExecutionResult {
  status: ProtocolActionExecutionStatus;
  textInserted: boolean;
  committedText: string;
}

export class ProtocolActionExecutor {
  private readonly serial: SerialActionExecutor = new SerialActionExecutor();
  private readonly imeService: ProtocolActionImeService;
  private readonly timeProvider: TimeProvider;
  private readonly isGenerationCurrent: (generation: number) => boolean;
  private readonly handlers: ProtocolActionHandlers;

  constructor(
    imeService: ProtocolActionImeService,
    timeProvider: TimeProvider = new SystemTimeProvider(),
    isGenerationCurrent: (generation: number) => boolean = (): boolean => true,
    handlers: ProtocolActionHandlers = new EmptyProtocolActionHandlers()
  ) {
    this.imeService = imeService;
    this.timeProvider = timeProvider;
    this.isGenerationCurrent = isGenerationCurrent;
    this.handlers = handlers;
  }

  execute(action: ProtocolAction, generation: number): Promise<ProtocolActionExecutionResult> {
    return this.serial.enqueue(async (): Promise<ProtocolActionExecutionResult> => {
      if (!this.isGenerationCurrent(generation)) {
        return this.result(ProtocolActionExecutionStatus.SESSION_INVALID, false);
      }
      if (action.type === 'DATE_TIME_TEXT') {
        let snapshot: Date;
        try {
          snapshot = this.timeProvider.now();
        } catch (err) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        const text = this.formatDateTime(action.formatId, snapshot);
        if (text.length === 0) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        if (!this.isGenerationCurrent(generation)) {
          return this.result(ProtocolActionExecutionStatus.SESSION_INVALID, false);
        }
        let inserted: boolean = false;
        try {
          inserted = await this.imeService.commitPreviewText(text, generation);
        } catch (err) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        if (!this.isGenerationCurrent(generation)) {
          return this.result(ProtocolActionExecutionStatus.SESSION_INVALID, inserted);
        }
        return this.result(
          inserted ? ProtocolActionExecutionStatus.SUCCESS : ProtocolActionExecutionStatus.FAILED,
          inserted,
          inserted ? text : ''
        );
      }
      if (action.type === 'REPEAT_COMMIT') {
        if (!this.handlers.repeatLastCommit && !this.imeService.repeatLastCommit) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        let success: boolean = false;
        try {
          success = this.handlers.repeatLastCommit ?
            await this.handlers.repeatLastCommit(generation) :
            await this.imeService.repeatLastCommit!();
        } catch (err) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        if (!this.isGenerationCurrent(generation)) {
          return this.result(ProtocolActionExecutionStatus.SESSION_INVALID, success);
        }
        return this.result(
          success ? ProtocolActionExecutionStatus.SUCCESS : ProtocolActionExecutionStatus.FAILED,
          success
        );
      }
      if (action.type === 'UNDO_COMMIT') {
        if (!this.handlers.undoLastCommit && !this.imeService.undoLastCommit) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        let success: boolean = false;
        try {
          success = this.handlers.undoLastCommit ?
            await this.handlers.undoLastCommit(generation) :
            await this.imeService.undoLastCommit!();
        } catch (err) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        if (!this.isGenerationCurrent(generation)) {
          return this.result(ProtocolActionExecutionStatus.SESSION_INVALID, success);
        }
        return this.result(
          success ? ProtocolActionExecutionStatus.SUCCESS : ProtocolActionExecutionStatus.FAILED,
          success
        );
      }
      if (action.type === 'MOVE_LINE_END') {
        if (!this.imeService.moveToLineEnd) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        let success: boolean = false;
        try {
          success = await this.imeService.moveToLineEnd();
        } catch (err) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        if (!this.isGenerationCurrent(generation)) {
          return this.result(ProtocolActionExecutionStatus.SESSION_INVALID, false);
        }
        return this.result(
          success ? ProtocolActionExecutionStatus.SUCCESS : ProtocolActionExecutionStatus.FAILED,
          false
        );
      }
      if (action.type === 'DIRECT_CONTROL') {
        if (!this.handlers.executeDirectControl) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        let success: boolean = false;
        try {
          success = await this.handlers.executeDirectControl(action.formatId, action.text, generation);
        } catch (err) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        if (!this.isGenerationCurrent(generation)) {
          return this.result(ProtocolActionExecutionStatus.SESSION_INVALID, false);
        }
        return this.result(
          success ? ProtocolActionExecutionStatus.SUCCESS : ProtocolActionExecutionStatus.FAILED,
          false
        );
      }
      if (action.type === 'IMPORT_USER_LEXICON') {
        if (!this.handlers.importUserLexicon) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        let success: boolean = false;
        try {
          success = await this.handlers.importUserLexicon(generation);
        } catch (err) {
          return this.result(ProtocolActionExecutionStatus.FAILED, false);
        }
        if (!this.isGenerationCurrent(generation)) {
          return this.result(ProtocolActionExecutionStatus.SESSION_INVALID, false);
        }
        return this.result(
          success ? ProtocolActionExecutionStatus.SUCCESS : ProtocolActionExecutionStatus.FAILED,
          false
        );
      }
      if (action.type !== 'INSERT_PAIR' ||
        !this.validPair(action.text, action.cursorOffsetUtf16) ||
        !this.imeService.insertPairText) {
        return this.result(ProtocolActionExecutionStatus.FAILED, false);
      }
      let pairResult: PairInsertResult;
      try {
        pairResult = await this.imeService.insertPairText(
          action.text,
          action.cursorOffsetUtf16,
          generation
        );
      } catch (err) {
        return this.result(ProtocolActionExecutionStatus.FAILED, false);
      }
      if (!this.isGenerationCurrent(generation)) {
        return this.result(
          ProtocolActionExecutionStatus.SESSION_INVALID,
          pairResult !== PairInsertResult.INSERT_FAILED
        );
      }
      return this.result(
        pairResult === PairInsertResult.SUCCESS ?
          ProtocolActionExecutionStatus.SUCCESS : ProtocolActionExecutionStatus.FAILED,
        pairResult !== PairInsertResult.INSERT_FAILED,
        pairResult !== PairInsertResult.INSERT_FAILED ? action.text : ''
      );
    });
  }

  private formatDateTime(formatId: string, snapshot: Date): string {
    if (Number.isNaN(snapshot.getTime())) {
      return '';
    }
    const year = snapshot.getFullYear().toString().padStart(4, '0');
    const month = (snapshot.getMonth() + 1).toString().padStart(2, '0');
    const day = snapshot.getDate().toString().padStart(2, '0');
    const hour = snapshot.getHours().toString().padStart(2, '0');
    const minute = snapshot.getMinutes().toString().padStart(2, '0');
    const second = snapshot.getSeconds().toString().padStart(2, '0');
    switch (formatId) {
      case 'DATE_ISO':
        return `${year}-${month}-${day}`;
      case 'DATE_LOCAL':
        return `${year}年${month}月${day}日`;
      case 'DATE_LOCAL_UNPADDED':
        return `${year}年${snapshot.getMonth() + 1}月${snapshot.getDate()}日`;
      case 'TIME_HM':
        return `${hour}:${minute}`;
      case 'TIME_HMS':
        return `${hour}:${minute}:${second}`;
      case 'TIME_LOCAL_HMS':
        return `${hour}时${minute}分${second}秒`;
      case 'DATETIME_LOCAL':
        return `${year}年${month}月${day}日 ${hour}:${minute}`;
      case 'UNIX_TIMESTAMP':
        return Math.floor(snapshot.getTime() / 1000).toString();
      default:
        return '';
    }
  }

  private validPair(text: string, offset: number): boolean {
    return text.length > 1 && text.length <= 64 && !this.hasControlCharacter(text) &&
      Number.isInteger(offset) &&
      offset > 0 && offset < text.length && offset <= 16;
  }

  private hasControlCharacter(text: string): boolean {
    for (let index = 0; index < text.length; index++) {
      const unit = text.charCodeAt(index);
      if (unit < 0x20 || unit === 0x7F) {
        return true;
      }
    }
    return false;
  }

  private result(
    status: ProtocolActionExecutionStatus,
    textInserted: boolean,
    committedText: string = ''
  ): ProtocolActionExecutionResult {
    return { status, textInserted, committedText };
  }
}
