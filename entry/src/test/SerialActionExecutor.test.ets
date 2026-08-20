import { describe, it, expect } from '@ohos/hypium';
import { SerialActionExecutor } from '../main/ets/application/SerialActionExecutor';

class Deferred {
  private resolver?: () => void;
  readonly promise: Promise<void> = new Promise<void>((resolve: () => void) => {
    this.resolver = resolve;
  });

  resolve(): void {
    this.resolver?.();
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, milliseconds);
  });
}

export default function serialActionExecutorTest() {
  describe('SerialActionExecutor', () => {
    it('runs slow and fast asynchronous tasks in strict FIFO order', 0, async () => {
      const executor = new SerialActionExecutor();
      const firstGate = new Deferred();
      const events: string[] = [];
      const first = executor.enqueue(async (): Promise<void> => {
        events.push('A-start');
        await firstGate.promise;
        events.push('A-end');
      });
      const second = executor.enqueue(async (): Promise<void> => {
        events.push('B-start');
        events.push('B-end');
      });

      await delay(0);
      expect(events.join(',')).assertEqual('A-start');
      firstGate.resolve();
      await first;
      await second;
      expect(events.join(',')).assertEqual('A-start,A-end,B-start,B-end');
    });

    it('preserves rapid character order despite different task delays', 0, async () => {
      const executor = new SerialActionExecutor();
      const events: string[] = [];
      const first = executor.enqueue(async (): Promise<void> => {
        await delay(12);
        events.push('a');
      });
      const second = executor.enqueue(async (): Promise<void> => {
        await delay(1);
        events.push('b');
      });
      const third = executor.enqueue(async (): Promise<void> => {
        await delay(4);
        events.push('c');
      });

      await first;
      await second;
      await third;
      expect(events.join(',')).assertEqual('a,b,c');
    });

    it('keeps input delete and following input in event order', 0, async () => {
      const executor = new SerialActionExecutor();
      const events: string[] = [];
      const insertA = executor.enqueue(async (): Promise<void> => {
        await delay(4);
        events.push('insert-a');
      });
      const deleteAction = executor.enqueue(async (): Promise<void> => {
        events.push('delete');
      });
      const insertB = executor.enqueue(async (): Promise<void> => {
        events.push('insert-b');
      });

      await insertA;
      await deleteAction;
      await insertB;
      expect(events.join(',')).assertEqual('insert-a,delete,insert-b');
    });

    it('continues after a task rejects while preserving caller failure', 0, async () => {
      const executor = new SerialActionExecutor();
      const events: string[] = [];
      let firstFailed = false;
      const failed = executor.enqueue(async (): Promise<void> => {
        events.push('failed-start');
        throw new Error('simulated failure');
      });
      const continued = executor.enqueue(async (): Promise<void> => {
        events.push('continued');
      });

      await failed.catch((err: Object): void => {
        firstFailed = true;
      });
      await continued;
      expect(firstFailed).assertTrue();
      expect(events.join(',')).assertEqual('failed-start,continued');
    });

    it('serializes candidate commit mode switch and new-mode input', 0, async () => {
      const executor = new SerialActionExecutor();
      const events: string[] = [];
      const candidate = executor.enqueue(async (): Promise<void> => {
        events.push('candidate-start');
        await delay(5);
        events.push('candidate-end');
      });
      const mode = executor.enqueue(async (): Promise<void> => {
        events.push('mode-switch');
      });
      const input = executor.enqueue(async (): Promise<void> => {
        events.push('new-mode-input');
      });

      await candidate;
      await mode;
      await input;
      expect(events.join(',')).assertEqual('candidate-start,candidate-end,mode-switch,new-mode-input');
    });

    it('orders synchronous and asynchronous actions through one tail', 0, async () => {
      const executor = new SerialActionExecutor();
      const events: string[] = [];
      const chinese = executor.enqueue(async (): Promise<void> => {
        events.push('chinese-code');
      });
      const english = executor.enqueue(async (): Promise<void> => {
        await delay(3);
        events.push('english-insert');
      });
      const mode = executor.enqueue(async (): Promise<void> => {
        events.push('mode-switch');
      });
      const deletion = executor.enqueue(async (): Promise<void> => {
        await delay(1);
        events.push('delete');
      });

      await chinese;
      await english;
      await mode;
      await deletion;
      expect(events.join(',')).assertEqual('chinese-code,english-insert,mode-switch,delete');
    });

    it('compound tasks call internal work directly without nested enqueue deadlock', 0, async () => {
      const executor = new SerialActionExecutor();
      const events: string[] = [];
      const internalCommit = async (): Promise<void> => {
        await delay(2);
        events.push('internal-commit');
      };
      const compound = executor.enqueue(async (): Promise<void> => {
        events.push('compound-start');
        await internalCommit();
        events.push('compound-end');
      });
      const next = executor.enqueue(async (): Promise<void> => {
        events.push('next');
      });

      await compound;
      await next;
      expect(events.join(',')).assertEqual('compound-start,internal-commit,compound-end,next');
    });
  });
}
