import { describe, expect, it } from '@ohos/hypium';
import { inputMethodEngine } from '@kit.IMEKit';
import { ImeConnectionLifecycle } from '../main/ets/infrastructure/ime/ImeConnectionLifecycle';
import { ImeConnectionService } from '../main/ets/infrastructure/ime/ImeConnectionService';

export default function cursorMovementServiceTest() {
  describe('CursorMovementService', () => {
    it('exposes production cursor movement and rejects it without an editor session', 0, async () => {
      ImeConnectionLifecycle.clearSession();
      let rejected = false;
      try {
        await new ImeConnectionService().moveCursor(inputMethodEngine.Direction.CURSOR_LEFT);
      } catch (_err) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });
}
