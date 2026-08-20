import { describe, it, expect } from '@ohos/hypium';
import {
  ProtocolActionExecutionStatus,
  ProtocolActionExecutor,
  ProtocolActionImeService
} from '../main/ets/application/ProtocolActionExecutor';
import { PairInsertResult } from '../main/ets/infrastructure/ime/ImeConnectionService';
import { ProtocolAction } from '../main/ets/infrastructure/native/NativeEngineTypes';
import { TimeProvider } from '../main/ets/infrastructure/time/TimeProvider';

class FixedTimeProvider implements TimeProvider {
  calls: number = 0;
  private readonly value: Date;

  constructor(value: Date) {
    this.value = value;
  }

  now(): Date {
    this.calls += 1;
    return this.value;
  }
}

class FakeActionImeService implements ProtocolActionImeService {
  committed: string[] = [];
  pairs: string[] = [];
  commitResult: boolean = true;
  pairResult: PairInsertResult = PairInsertResult.SUCCESS;
  repeatCount: number = 0;
  undoCount: number = 0;
  moveLineEndCount: number = 0;

  async commitPreviewText(text: string, _generation?: number): Promise<boolean> {
    this.committed.push(text);
    return this.commitResult;
  }

  async insertPairText(
    text: string,
    cursorOffsetUtf16: number,
    _generation?: number
  ): Promise<PairInsertResult> {
    this.pairs.push(`${text}:${cursorOffsetUtf16}`);
    return this.pairResult;
  }

  async repeatLastCommit(): Promise<boolean> {
    this.repeatCount += 1;
    return true;
  }

  async undoLastCommit(): Promise<boolean> {
    this.undoCount += 1;
    return true;
  }

  async moveToLineEnd(): Promise<boolean> {
    this.moveLineEndCount += 1;
    return true;
  }
}

function dateAction(formatId: 'DATE_ISO' | 'DATE_LOCAL' | 'TIME_HM' | 'DATETIME_LOCAL'): ProtocolAction {
  return { type: 'DATE_TIME_TEXT', formatId, text: '', cursorOffsetUtf16: 0 };
}

export default function protocolActionExecutorTest() {
  describe('ProtocolActionExecutor', () => {
    it('formats leap-day values from one fixed local-time snapshot', 0, async () => {
      const service = new FakeActionImeService();
      const time = new FixedTimeProvider(new Date(2024, 1, 29, 7, 5, 59));
      const executor = new ProtocolActionExecutor(service, time);

      const iso = await executor.execute(dateAction('DATE_ISO'), 1);
      const local = await executor.execute(dateAction('DATE_LOCAL'), 1);
      const hm = await executor.execute(dateAction('TIME_HM'), 1);
      const datetime = await executor.execute(dateAction('DATETIME_LOCAL'), 1);

      expect(iso.status).assertEqual(ProtocolActionExecutionStatus.SUCCESS);
      expect(local.status).assertEqual(ProtocolActionExecutionStatus.SUCCESS);
      expect(hm.status).assertEqual(ProtocolActionExecutionStatus.SUCCESS);
      expect(datetime.status).assertEqual(ProtocolActionExecutionStatus.SUCCESS);
      expect(service.committed.join('|')).assertEqual(
        '2024-02-29|2024年02月29日|07:05|2024年02月29日 07:05'
      );
      expect(time.calls).assertEqual(4);
    });

    it('does not submit when time acquisition is invalid', 0, async () => {
      const service = new FakeActionImeService();
      const executor = new ProtocolActionExecutor(
        service,
        new FixedTimeProvider(new Date(Number.NaN))
      );
      const result = await executor.execute(dateAction('DATE_ISO'), 2);
      expect(result.status).assertEqual(ProtocolActionExecutionStatus.FAILED);
      expect(service.committed.length).assertEqual(0);
    });

    it('executes a pair as one insert with a bounded UTF-16 offset', 0, async () => {
      const service = new FakeActionImeService();
      const executor = new ProtocolActionExecutor(service);
      const result = await executor.execute({
        type: 'INSERT_PAIR',
        formatId: '',
        text: '🧑‍💻🧑‍💻',
        cursorOffsetUtf16: 5
      }, 3);
      expect(result.status).assertEqual(ProtocolActionExecutionStatus.SUCCESS);
      expect(service.pairs.join(',')).assertEqual('🧑‍💻🧑‍💻:5');
    });

    it('never retries when pair insertion succeeds but cursor placement fails', 0, async () => {
      const service = new FakeActionImeService();
      service.pairResult = PairInsertResult.CURSOR_FAILED;
      const executor = new ProtocolActionExecutor(service);
      const result = await executor.execute({
        type: 'INSERT_PAIR',
        formatId: '',
        text: '()',
        cursorOffsetUtf16: 1
      }, 4);
      expect(result.status).assertEqual(ProtocolActionExecutionStatus.FAILED);
      expect(result.textInserted).assertTrue();
      expect(service.pairs.length).assertEqual(1);
    });

    it('executes repeat undo and line-end as closed editor actions', 0, async () => {
      const service = new FakeActionImeService();
      const executor = new ProtocolActionExecutor(service);
      const repeat = await executor.execute({
        type: 'REPEAT_COMMIT', formatId: '', text: '', cursorOffsetUtf16: 0
      }, 5);
      const undo = await executor.execute({
        type: 'UNDO_COMMIT', formatId: '', text: '', cursorOffsetUtf16: 0
      }, 5);
      const lineEnd = await executor.execute({
        type: 'MOVE_LINE_END', formatId: '', text: '', cursorOffsetUtf16: 0
      }, 5);
      expect(repeat.status).assertEqual(ProtocolActionExecutionStatus.SUCCESS);
      expect(undo.status).assertEqual(ProtocolActionExecutionStatus.SUCCESS);
      expect(lineEnd.status).assertEqual(ProtocolActionExecutionStatus.SUCCESS);
      expect(service.repeatCount).assertEqual(1);
      expect(service.undoCount).assertEqual(1);
      expect(service.moveLineEndCount).assertEqual(1);
    });

    it('rejects stale generations before any visible edit', 0, async () => {
      const service = new FakeActionImeService();
      const executor = new ProtocolActionExecutor(
        service,
        new FixedTimeProvider(new Date(2024, 0, 1)),
        (_generation: number): boolean => false
      );
      const result = await executor.execute(dateAction('DATE_ISO'), 9);
      expect(result.status).assertEqual(ProtocolActionExecutionStatus.SESSION_INVALID);
      expect(service.committed.length).assertEqual(0);
    });
  });
}
