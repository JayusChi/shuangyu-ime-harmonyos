import { describe, expect, it } from '@ohos/hypium';
import {
  LegacyPhysicalKeyState,
  PhysicalKeyEventChannel,
  PhysicalKeyEventDeduplicator
} from '../main/ets/domain/keyboard/PhysicalKeyEventCompatibility';
import { PhysicalKeySnapshot } from '../main/ets/domain/keyboard/PhysicalKeyboardRouting';

function key(keyCode: number, isDown: boolean = true): PhysicalKeySnapshot {
  return {
    isDown,
    unicodeChar: 0,
    keyCode,
    ctrlKey: false,
    altKey: false,
    logoKey: false,
    shiftKey: false
  };
}

export default function pcHostInputCompatibilityTest() {
  describe('PC host input-method event compatibility', () => {
    it('converts the legacy key callback into the shared physical-key shape', 0, () => {
      const state = new LegacyPhysicalKeyState();
      const letter = state.snapshot(2030, true);
      expect(letter.isDown).assertTrue();
      expect(letter.keyCode).assertEqual(2030);
      expect(letter.unicodeChar).assertEqual(0);
      expect(letter.ctrlKey).assertFalse();
      expect(letter.altKey).assertFalse();
      expect(letter.logoKey).assertFalse();
      expect(letter.shiftKey).assertFalse();
    });

    it('reconstructs legacy modifier state without swallowing shortcuts', 0, () => {
      const state = new LegacyPhysicalKeyState();
      state.snapshot(2072, true);
      state.snapshot(2045, true);
      state.snapshot(2047, true);
      state.snapshot(2076, true);
      const modified = state.snapshot(2031, true);
      expect(modified.ctrlKey).assertTrue();
      expect(modified.altKey).assertTrue();
      expect(modified.logoKey).assertTrue();
      expect(modified.shiftKey).assertTrue();

      state.snapshot(2072, false);
      state.snapshot(2045, false);
      state.snapshot(2047, false);
      state.snapshot(2076, false);
      const released = state.snapshot(2031, true);
      expect(released.ctrlKey).assertFalse();
      expect(released.altKey).assertFalse();
      expect(released.logoKey).assertFalse();
      expect(released.shiftKey).assertFalse();
    });

    it('keeps either left or right modifier active until both are released', 0, () => {
      const state = new LegacyPhysicalKeyState();
      state.snapshot(2072, true);
      state.snapshot(2073, true);
      state.snapshot(2072, false);
      expect(state.snapshot(2032, true).ctrlKey).assertTrue();
      state.snapshot(2073, false);
      expect(state.snapshot(2032, true).ctrlKey).assertFalse();
    });

    it('returns one consumed decision when a host emits both event APIs', 0, () => {
      const deduplicator = new PhysicalKeyEventDeduplicator();
      const down = key(2030);
      deduplicator.record(PhysicalKeyEventChannel.MODERN, down, true, 1000);
      expect(deduplicator.findDuplicateDecision(PhysicalKeyEventChannel.LEGACY, down, 1001))
        .assertTrue();

      const up = key(2030, false);
      deduplicator.record(PhysicalKeyEventChannel.LEGACY, up, false, 1100);
      expect(deduplicator.findDuplicateDecision(PhysicalKeyEventChannel.MODERN, up, 1102))
        .assertFalse();
    });

    it('deduplicates a complete modern pair followed by the legacy pair', 0, () => {
      const deduplicator = new PhysicalKeyEventDeduplicator();
      const oDown = key(2031);
      const oUp = key(2031, false);
      deduplicator.record(PhysicalKeyEventChannel.MODERN, oDown, true, 1000);
      deduplicator.record(PhysicalKeyEventChannel.MODERN, oUp, true, 1004);

      expect(deduplicator.findDuplicateDecision(PhysicalKeyEventChannel.LEGACY, oDown, 1030))
        .assertTrue();
      expect(deduplicator.findDuplicateDecision(PhysicalKeyEventChannel.LEGACY, oUp, 1034))
        .assertTrue();
      // Both records were consumed. A later real O press is not mistaken for
      // a third delivery of the original key.
      expect(deduplicator.findDuplicateDecision(PhysicalKeyEventChannel.LEGACY, oDown, 1040))
        .assertUndefined();
    });

    it('covers the delayed 96 ms mirror observed on a HarmonyOS 6.1 phone', 0, () => {
      const deduplicator = new PhysicalKeyEventDeduplicator();
      const oDown = key(2031);
      deduplicator.record(PhysicalKeyEventChannel.MODERN, oDown, true, 1000);

      expect(deduplicator.findDuplicateDecision(PhysicalKeyEventChannel.LEGACY, oDown, 1096))
        .assertTrue();
    });

    it('pairs delayed mirrors FIFO without suppressing rapid real repeats', 0, () => {
      const deduplicator = new PhysicalKeyEventDeduplicator();
      const oDown = key(2031);
      const accepted: number[] = [];
      const deliver = (channel: PhysicalKeyEventChannel, timestampMs: number): void => {
        if (deduplicator.findDuplicateDecision(channel, oDown, timestampMs) !== undefined) {
          return;
        }
        accepted.push(timestampMs);
        deduplicator.record(channel, oDown, true, timestampMs);
      };

      deliver(PhysicalKeyEventChannel.MODERN, 2000);
      deliver(PhysicalKeyEventChannel.MODERN, 2040);
      deliver(PhysicalKeyEventChannel.LEGACY, 2096);
      deliver(PhysicalKeyEventChannel.LEGACY, 2136);

      expect(accepted.length).assertEqual(2);
      expect(accepted[0]).assertEqual(2000);
      expect(accepted[1]).assertEqual(2040);
    });

    it('dispatches o then k once when each physical key arrives on both APIs', 0, () => {
      const deduplicator = new PhysicalKeyEventDeduplicator();
      const accepted: string[] = [];
      const deliver = (
        channel: PhysicalKeyEventChannel,
        snapshot: PhysicalKeySnapshot,
        timestampMs: number,
        letter: string
      ): void => {
        const duplicate = deduplicator.findDuplicateDecision(channel, snapshot, timestampMs);
        if (duplicate !== undefined) {
          return;
        }
        accepted.push(letter);
        deduplicator.record(channel, snapshot, true, timestampMs);
      };

      deliver(PhysicalKeyEventChannel.MODERN, key(2031), 2000, 'o');
      deliver(PhysicalKeyEventChannel.LEGACY, key(2031), 2030, 'o');
      deliver(PhysicalKeyEventChannel.MODERN, key(2027), 2100, 'k');
      deliver(PhysicalKeyEventChannel.LEGACY, key(2027), 2130, 'k');

      expect(accepted.join('')).assertEqual('ok');
    });

    it('does not suppress same-channel repeats or later real events', 0, () => {
      const deduplicator = new PhysicalKeyEventDeduplicator(24);
      const down = key(2030);
      deduplicator.record(PhysicalKeyEventChannel.MODERN, down, true, 1000);
      expect(deduplicator.findDuplicateDecision(PhysicalKeyEventChannel.MODERN, down, 1001))
        .assertUndefined();
      expect(deduplicator.findDuplicateDecision(PhysicalKeyEventChannel.LEGACY, down, 1025))
        .assertUndefined();
    });
  });
}
