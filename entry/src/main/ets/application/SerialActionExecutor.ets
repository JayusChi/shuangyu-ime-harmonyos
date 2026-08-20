export type SerialActionTask<T> = () => Promise<T>;

/**
 * Runs input actions one at a time in enqueue order.
 *
 * The promise returned to a caller keeps that action's result, while the
 * internal tail always recovers so one rejected action cannot block later
 * input.
 */
export class SerialActionExecutor {
  private tail: Promise<void> = Promise.resolve();

  enqueue<T>(task: SerialActionTask<T>): Promise<T> {
    const currentTask = this.tail.then(task);
    this.tail = currentTask.then(
      (): void => {
      },
      (): void => {
      }
    );
    return currentTask;
  }

  async waitForIdle(): Promise<void> {
    await this.tail;
  }
}

const SHARED_INPUT_ACTION_EXECUTOR = new SerialActionExecutor();

export function getSharedInputActionExecutor(): SerialActionExecutor {
  return SHARED_INPUT_ACTION_EXECUTOR;
}
