import { describe, expect, it } from '@ohos/hypium';
import {
  AlternateKeyGestureController,
  KEY_SWIPE_UP_THRESHOLD_VP
} from '../main/ets/application/AlternateKeyGestureController';

function wait(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, ms);
  });
}

export default function keyboardAlternateGestureTest() {
  describe('keyboard alternate gestures', () => {
    it('dispatches a short tap only once', 0, () => {
      const events: string[] = [];
      const controller = new AlternateKeyGestureController(
        (): void => { events.push('tap'); },
        (): void => { events.push('long'); },
        (): void => { events.push('swipe'); }
      );
      controller.start(20, 100);
      controller.release();
      controller.click();
      expect(events.join(',')).assertEqual('tap');
      controller.destroy();
    });

    it('turns a vertical upward move into one alternate action', 0, () => {
      const events: string[] = [];
      const controller = new AlternateKeyGestureController(
        (): void => { events.push('tap'); },
        (): void => { events.push('long'); },
        (): void => { events.push('swipe'); }
      );
      controller.start(20, 100);
      expect(controller.move(22, 100 - KEY_SWIPE_UP_THRESHOLD_VP - 2)).assertTrue();
      controller.release();
      controller.click();
      expect(events.join(',')).assertEqual('swipe');
      controller.destroy();
    });

    it('dispatches long press without the following click', 0, async () => {
      const events: string[] = [];
      const controller = new AlternateKeyGestureController(
        (): void => { events.push('tap'); },
        (): void => { events.push('long'); },
        (): void => { events.push('swipe'); },
        5
      );
      controller.start(20, 100);
      await wait(15);
      controller.release();
      controller.click();
      expect(events.join(',')).assertEqual('long');
      controller.destroy();
    });
  });
}
