import { Logger } from '../common/logging/Logger';

const LOGGER = new Logger('SoftKeyboardPanelOwner');

export enum SoftKeyboardPanelOwner {
  FIXED_KEYBOARD = 'FIXED_KEYBOARD',
  CANDIDATE_WINDOW = 'CANDIDATE_WINDOW'
}

export interface ManagedSoftKeyboardPanel {
}

type PanelFactory = () => Promise<ManagedSoftKeyboardPanel | undefined>;
type PanelDestroyer = (panel: ManagedSoftKeyboardPanel) => Promise<void>;
type OwnershipRevokedListener = () => void;

interface ActivePanelOwnership {
  owner: SoftKeyboardPanelOwner;
  panel: ManagedSoftKeyboardPanel;
  destroyer: PanelDestroyer;
  onRevoked: OwnershipRevokedListener;
}

/**
 * Serializes ownership of PanelType.SOFT_KEYBOARD. A new owner first destroys
 * the previous owner's panel, so FLAG_FIXED and FLAG_CANDIDATE can never be
 * alive at the same time in the formal runtime.
 */
export class SoftKeyboardPanelOwnershipCoordinator {
  private active?: ActivePanelOwnership;
  private queue: Promise<void> = Promise.resolve();

  acquire(
    owner: SoftKeyboardPanelOwner,
    factory: PanelFactory,
    destroyer: PanelDestroyer,
    onRevoked: OwnershipRevokedListener
  ): Promise<ManagedSoftKeyboardPanel | undefined> {
    let acquired: ManagedSoftKeyboardPanel | undefined = undefined;
    const operation = this.queue.then(async (): Promise<void> => {
      if (this.active?.owner === owner) {
        acquired = this.active.panel;
        return;
      }
      await this.releaseActive(`switchTo:${owner}`, true);
      const panel = await factory();
      if (!panel) {
        return;
      }
      this.active = { owner, panel, destroyer, onRevoked };
      acquired = panel;
      LOGGER.info(`soft keyboard panel acquired: owner=${owner}`);
    });
    this.queue = operation.catch((err: Object): void => {
      LOGGER.warn(`panel acquire failed: owner=${owner}, error=${JSON.stringify(err)}`);
    });
    return operation.then((): ManagedSoftKeyboardPanel | undefined => acquired);
  }

  release(owner: SoftKeyboardPanelOwner, panel: ManagedSoftKeyboardPanel): Promise<void> {
    const operation = this.queue.then(async (): Promise<void> => {
      if (this.active?.owner !== owner || this.active.panel !== panel) {
        return;
      }
      await this.releaseActive(`release:${owner}`, false);
    });
    this.queue = operation.catch((err: Object): void => {
      LOGGER.warn(`panel release failed: owner=${owner}, error=${JSON.stringify(err)}`);
    });
    return operation;
  }

  getActiveOwner(): SoftKeyboardPanelOwner | undefined {
    return this.active?.owner;
  }

  async waitForIdle(): Promise<void> {
    await this.queue;
  }

  private async releaseActive(source: string, notifyRevoked: boolean): Promise<void> {
    const current = this.active;
    if (!current) {
      return;
    }
    this.active = undefined;
    try {
      await current.destroyer(current.panel);
      LOGGER.info(`soft keyboard panel released: owner=${current.owner}, source=${source}`);
    } finally {
      if (notifyRevoked) {
        current.onRevoked();
      }
    }
  }
}
