import { describe, expect, it } from '@ohos/hypium';
import { resolveCurrentLineRange } from '../main/ets/domain/editor/CurrentLineRange';

export default function currentLineRangeTest() {
  describe('CurrentLineRange', () => {
    it('deletes a middle line together with its following CRLF', 0, () => {
      const range = resolveCurrentLineRange(8, 'first\r\nA', 'BC\r\nthird', false, false);
      expect(range?.start).assertEqual(7);
      expect(range?.end).assertEqual(12);
    });

    it('deletes only the final non-empty line content', 0, () => {
      const range = resolveCurrentLineRange(8, 'first\r\nA', 'BC', false, false);
      expect(range?.start).assertEqual(7);
      expect(range?.end).assertEqual(10);
    });

    it('removes the previous separator for an empty final line', 0, () => {
      const range = resolveCurrentLineRange(7, 'first\r\n', '', false, false);
      expect(range?.start).assertEqual(5);
      expect(range?.end).assertEqual(7);
    });

    it('refuses to guess when either line boundary was truncated', 0, () => {
      expect(resolveCurrentLineRange(4096, 'a'.repeat(4096), '', true, false)).assertUndefined();
      expect(resolveCurrentLineRange(0, '', 'b'.repeat(4096), false, true)).assertUndefined();
    });
  });
}
