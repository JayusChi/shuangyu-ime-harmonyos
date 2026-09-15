import { describe, expect, it } from '@ohos/hypium';
import {
  AlternateKeyGestureController,
  KEY_SWIPE_VERTICAL_DOMINANCE_RATIO,
  KEY_SWIPE_DOWN_THRESHOLD_VP,
  KEY_SWIPE_UP_THRESHOLD_VP,
  LETTER_KEY_SWIPE_THRESHOLD_VP
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

    it('turns a vertical downward move into one alternate action', 0, () => {
      const events: string[] = [];
      const controller = new AlternateKeyGestureController(
        (): void => { events.push('tap'); },
        (): void => { events.push('long'); },
        (): void => { events.push('up'); },
        undefined,
        (): void => { events.push('down'); }
      );
      controller.start(20, 100);
      expect(controller.move(18, 100 + KEY_SWIPE_DOWN_THRESHOLD_VP + 2)).assertTrue();
      controller.release();
      controller.click();
      expect(events.join(',')).assertEqual('down');
      controller.destroy();
    });

    it('keeps a fast diagonal letter-key movement as a tap', 0, () => {
      const events: string[] = [];
      const controller = new AlternateKeyGestureController(
        (): void => { events.push('tap'); },
        (): void => { events.push('long'); },
        (): void => { events.push('swipe'); },
        undefined,
        (): void => {},
        LETTER_KEY_SWIPE_THRESHOLD_VP
      );
      controller.start(20, 100);
      expect(controller.move(39, 100 - LETTER_KEY_SWIPE_THRESHOLD_VP + 2)).assertFalse();
      controller.release();
      controller.click();
      expect(events.join(',')).assertEqual('tap');
      controller.destroy();
    });

    it('requires clear vertical dominance before a letter-key swipe', 0, () => {
      const events: string[] = [];
      const controller = new AlternateKeyGestureController(
        (): void => { events.push('tap'); },
        (): void => { events.push('long'); },
        (): void => { events.push('swipe'); },
        undefined,
        (): void => {},
        LETTER_KEY_SWIPE_THRESHOLD_VP
      );
      controller.start(20, 100);
      const verticalDistance = LETTER_KEY_SWIPE_THRESHOLD_VP + 4;
      const ambiguousHorizontalDistance = verticalDistance / KEY_SWIPE_VERTICAL_DOMINANCE_RATIO + 1;
      expect(controller.move(20 + ambiguousHorizontalDistance, 100 - verticalDistance)).assertFalse();
      expect(controller.move(23, 100 - verticalDistance)).assertTrue();
      controller.release();
      controller.click();
      expect(events.join(',')).assertEqual('swipe');
      controller.destroy();
    });
  });
}
