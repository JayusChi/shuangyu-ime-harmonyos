import { describe, it, expect } from '@ohos/hypium';
import {
  DEFAULT_CANDIDATE_PRESENTATION_MODE,
  FloatingCandidateCapability,
  resolveEffectivePresentationMode
} from '../main/ets/domain/candidate/FloatingCandidatePolicy';
import {
  computeFloatingCandidatePosition,
  CandidateWindowSizePx,
  FloatingCandidatePlacement,
  isCursorRectUsable,
  SafeInsetsPx,
  WindowRectPx
} from '../main/ets/domain/candidate/FloatingCandidatePosition';
import { KeyboardDeviceFormFactor } from '../main/ets/domain/display/KeyboardAuxiliaryAreaPolicy';
import {
  CandidatePresentationMode,
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  imeSettingsEqual,
  isCandidatePresentationMode,
  settingsToRaw
} from '../main/ets/domain/settings/ImeSettings';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';
import {
  PhysicalKeyCommandType,
  PhysicalKeySessionSnapshot,
  resolvePhysicalKeyCommand
} from '../main/ets/domain/keyboard/PhysicalKeyboardRouting';
import { KeyboardMode } from '../main/ets/domain/keyboard/KeyboardAction';

interface CapabilityOverride {
  sdkSupportsPanel?: boolean;
  sdkSupportsCursorEvent?: boolean;
  sessionAllowsPanel?: boolean;
  hasReceivedCursorAnchor?: boolean;
  hasPhysicalKeyboard?: boolean;
  formFactor?: KeyboardDeviceFormFactor;
}

function padCapability(overrides: CapabilityOverride): FloatingCandidateCapability {
  return {
    sdkSupportsPanel: overrides.sdkSupportsPanel ?? true,
    sdkSupportsCursorEvent: overrides.sdkSupportsCursorEvent ?? true,
    sessionAllowsPanel: overrides.sessionAllowsPanel ?? true,
    hasReceivedCursorAnchor: overrides.hasReceivedCursorAnchor ?? true,
    hasPhysicalKeyboard: overrides.hasPhysicalKeyboard ?? true,
    formFactor: overrides.formFactor ?? KeyboardDeviceFormFactor.TABLET
  };
}

function phoneCapability(overrides: CapabilityOverride): FloatingCandidateCapability {
  return {
    sdkSupportsPanel: overrides.sdkSupportsPanel ?? true,
    sdkSupportsCursorEvent: overrides.sdkSupportsCursorEvent ?? true,
    sessionAllowsPanel: overrides.sessionAllowsPanel ?? true,
    hasReceivedCursorAnchor: overrides.hasReceivedCursorAnchor ?? true,
    hasPhysicalKeyboard: overrides.hasPhysicalKeyboard ?? false,
    formFactor: overrides.formFactor ?? KeyboardDeviceFormFactor.PHONE
  };
}

function physicalSession(rawInput: string, mode: KeyboardMode = KeyboardMode.CHINESE): PhysicalKeySessionSnapshot {
  return {
    sessionActive: true,
    editorConnected: true,
    candidateBarVisible: true,
    keyboardMode: mode,
    rawInput,
    candidateCount: 5
  };
}

export default function stage38Test() {
  describe('customer stage 3.8 floating candidate policy', () => {
    it('exposes AUTO as default presentation mode', 0, () => {
      expect(DEFAULT_CANDIDATE_PRESENTATION_MODE).assertEqual(CandidatePresentationMode.AUTO);
      expect(DEFAULT_IME_SETTINGS.candidatePresentationMode).assertEqual(CandidatePresentationMode.AUTO);
      expect(isCandidatePresentationMode(CandidatePresentationMode.BAR)).assertTrue();
      expect(isCandidatePresentationMode(CandidatePresentationMode.FLOATING)).assertTrue();
      expect(isCandidatePresentationMode(CandidatePresentationMode.AUTO)).assertTrue();
      expect(isCandidatePresentationMode('unknown')).assertFalse();
    });

    it('BAR always resolves to BAR even when floating is supported', 0, () => {
      const resolved = resolveEffectivePresentationMode(CandidatePresentationMode.BAR, padCapability({}));
      expect(resolved).assertEqual(CandidatePresentationMode.BAR);
    });

    it('FLOATING falls back to BAR when SDK cannot create the panel', 0, () => {
      const resolved = resolveEffectivePresentationMode(
        CandidatePresentationMode.FLOATING,
        padCapability({ sdkSupportsPanel: false })
      );
      expect(resolved).assertEqual(CandidatePresentationMode.BAR);
    });

    it('FLOATING falls back to BAR when SDK cannot subscribe cursor events', 0, () => {
      const resolved = resolveEffectivePresentationMode(
        CandidatePresentationMode.FLOATING,
        padCapability({ sdkSupportsCursorEvent: false })
      );
      expect(resolved).assertEqual(CandidatePresentationMode.BAR);
    });

    it('FLOATING falls back to BAR when session does not allow candidate panel', 0, () => {
      const resolved = resolveEffectivePresentationMode(
        CandidatePresentationMode.FLOATING,
        padCapability({ sessionAllowsPanel: false })
      );
      expect(resolved).assertEqual(CandidatePresentationMode.BAR);
    });

    it('FLOATING falls back to BAR when no cursor anchor has arrived yet', 0, () => {
      const resolved = resolveEffectivePresentationMode(
        CandidatePresentationMode.FLOATING,
        padCapability({ hasReceivedCursorAnchor: false })
      );
      expect(resolved).assertEqual(CandidatePresentationMode.BAR);
    });

    it('AUTO on phone always uses BAR', 0, () => {
      const resolved = resolveEffectivePresentationMode(CandidatePresentationMode.AUTO, phoneCapability({}));
      expect(resolved).assertEqual(CandidatePresentationMode.BAR);
    });

    it('AUTO on Pad without physical keyboard uses BAR', 0, () => {
      const resolved = resolveEffectivePresentationMode(
        CandidatePresentationMode.AUTO,
        padCapability({ hasPhysicalKeyboard: false })
      );
      expect(resolved).assertEqual(CandidatePresentationMode.BAR);
    });

    it('AUTO on Pad with physical keyboard and anchor uses the verified candidate panel', 0, () => {
      const resolved = resolveEffectivePresentationMode(CandidatePresentationMode.AUTO, padCapability({}));
      expect(resolved).assertEqual(CandidatePresentationMode.FLOATING);
    });

    it('AUTO on Pad with physical keyboard but no anchor still uses BAR', 0, () => {
      const resolved = resolveEffectivePresentationMode(
        CandidatePresentationMode.AUTO,
        padCapability({ hasReceivedCursorAnchor: false })
      );
      expect(resolved).assertEqual(CandidatePresentationMode.BAR);
    });

    it('explicit FLOATING resolves to an independent candidate panel when all gates pass', 0, () => {
      const resolved = resolveEffectivePresentationMode(CandidatePresentationMode.FLOATING, padCapability({}));
      expect(resolved).assertEqual(CandidatePresentationMode.FLOATING);
    });

    it('explicit FLOATING enables the touch candidate window on Phone', 0, () => {
      const resolved = resolveEffectivePresentationMode(CandidatePresentationMode.FLOATING, phoneCapability({}));
      expect(resolved).assertEqual(CandidatePresentationMode.FLOATING);
    });

    it('explicit FLOATING enables the touch candidate window on Pad without hardware', 0, () => {
      const resolved = resolveEffectivePresentationMode(
        CandidatePresentationMode.FLOATING,
        padCapability({ hasPhysicalKeyboard: false })
      );
      expect(resolved).assertEqual(CandidatePresentationMode.FLOATING);
    });

    it('explicit BAR remains the safe fallback on computer hardware', 0, () => {
      const resolved = resolveEffectivePresentationMode(CandidatePresentationMode.BAR, padCapability({}));
      expect(resolved).assertEqual(CandidatePresentationMode.BAR);
    });

  });

  describe('customer stage 3.8 floating candidate position calculator', () => {
    const HOST: WindowRectPx = { left: 0, top: 0, right: 1000, bottom: 2000 };
    const INSETS: SafeInsetsPx = { top: 0, bottom: 0, left: 0, right: 0 };
    const SIZE: CandidateWindowSizePx = { widthPx: 400, heightPx: 120 };

    it('places candidate below the cursor when there is room', 0, () => {
      const pos = computeFloatingCandidatePosition({
        cursorRect: { x: 100, y: 500, height: 40 },
        hostWindowRect: HOST,
        candidateWindowSize: SIZE,
        safeInsets: INSETS,
        preferredGapPx: 8
      });
      expect(pos.placement).assertEqual(FloatingCandidatePlacement.BELOW);
      expect(pos.y).assertEqual(548);
      expect(pos.x).assertEqual(100);
      expect(pos.heightPx).assertEqual(120);
      expect(pos.widthPx).assertEqual(400);
    });

    it('flips above the cursor when below space is insufficient', 0, () => {
      const pos = computeFloatingCandidatePosition({
        cursorRect: { x: 100, y: 1950, height: 40 },
        hostWindowRect: HOST,
        candidateWindowSize: SIZE,
        safeInsets: INSETS,
        preferredGapPx: 8
      });
      expect(pos.placement).assertEqual(FloatingCandidatePlacement.ABOVE);
      expect(pos.y).assertEqual(1950 - 8 - 120);
    });

    it('clamps left when the cursor sits near the right host edge', 0, () => {
      const pos = computeFloatingCandidatePosition({
        cursorRect: { x: 950, y: 500, height: 40 },
        hostWindowRect: HOST,
        candidateWindowSize: SIZE,
        safeInsets: INSETS,
        preferredGapPx: 8
      });
      expect(pos.x).assertEqual(600);
    });

    it('clamps right when the cursor sits near the left host edge', 0, () => {
      const pos = computeFloatingCandidatePosition({
        cursorRect: { x: -50, y: 500, height: 40 },
        hostWindowRect: HOST,
        candidateWindowSize: SIZE,
        safeInsets: INSETS,
        preferredGapPx: 8
      });
      expect(pos.x).assertEqual(0);
    });

    it('honors safe insets on all edges', 0, () => {
      const pos = computeFloatingCandidatePosition({
        cursorRect: { x: 970, y: 500, height: 40 },
        hostWindowRect: HOST,
        candidateWindowSize: SIZE,
        safeInsets: { top: 40, bottom: 60, left: 20, right: 30 },
        preferredGapPx: 8
      });
      expect(pos.x).assertEqual(1000 - 30 - 400);
    });

    it('shrinks candidate height when neither above nor below has enough room', 0, () => {
      const tinyHost: WindowRectPx = { left: 0, top: 0, right: 1000, bottom: 200 };
      const pos = computeFloatingCandidatePosition({
        cursorRect: { x: 100, y: 60, height: 40 },
        hostWindowRect: tinyHost,
        candidateWindowSize: { widthPx: 400, heightPx: 500 },
        safeInsets: INSETS,
        preferredGapPx: 8
      });
      // 60 + 40 + 8 = 108; below space = 200 - 108 = 92; above space = 60 - 8 = 52
      // below is larger, so placement=below with clamped height 92.
      expect(pos.placement).assertEqual(FloatingCandidatePlacement.BELOW);
      expect(pos.heightPx).assertEqual(92);
      expect(pos.y).assertEqual(108);
    });

    it('rejects invalid cursor rect via isCursorRectUsable', 0, () => {
      expect(isCursorRectUsable({ x: Number.NaN, y: 0, height: 20 })).assertFalse();
      expect(isCursorRectUsable({ x: 0, y: 0, height: -5 })).assertFalse();
      expect(isCursorRectUsable({ x: 0, y: 0, height: 20 })).assertTrue();
    });

    it('respects host window offset', 0, () => {
      const offsetHost: WindowRectPx = { left: 200, top: 300, right: 900, bottom: 1500 };
      const pos = computeFloatingCandidatePosition({
        cursorRect: { x: 350, y: 400, height: 30 },
        hostWindowRect: offsetHost,
        candidateWindowSize: { widthPx: 300, heightPx: 100 },
        safeInsets: INSETS,
        preferredGapPx: 4
      });
      expect(pos.x).assertEqual(350);
      expect(pos.y).assertEqual(434);
      expect(pos.placement).assertEqual(FloatingCandidatePlacement.BELOW);
    });

    it('handles zero-height cursor', 0, () => {
      const pos = computeFloatingCandidatePosition({
        cursorRect: { x: 100, y: 500, height: 0 },
        hostWindowRect: HOST,
        candidateWindowSize: SIZE,
        safeInsets: INSETS,
        preferredGapPx: 8
      });
      expect(pos.y).assertEqual(508);
    });

    it('never exceeds a host whose usable height is below the old 24px minimum', 0, () => {
      const pos = computeFloatingCandidatePosition({
        cursorRect: { x: 0, y: 4, height: 0 },
        hostWindowRect: { left: 0, top: 0, right: 100, bottom: 10 },
        candidateWindowSize: { widthPx: 80, heightPx: 120 },
        safeInsets: { top: 0, bottom: 0, left: 0, right: 0 },
        preferredGapPx: 0
      });
      expect(pos.heightPx <= 10).assertTrue();
      expect(pos.y >= 0).assertTrue();
      expect(pos.y + pos.heightPx <= 10).assertTrue();
    });
  });

  describe('customer stage 3.8 settings integration', () => {
    it('DEFAULT_IME_SETTINGS carries candidatePresentationMode AUTO', 0, () => {
      expect(DEFAULT_IME_SETTINGS.candidatePresentationMode).assertEqual(CandidatePresentationMode.AUTO);
    });

    it('copyImeSettings preserves candidatePresentationMode', 0, () => {
      const custom = copyImeSettings(DEFAULT_IME_SETTINGS);
      custom.candidatePresentationMode = CandidatePresentationMode.FLOATING;
      const cloned = copyImeSettings(custom);
      expect(cloned.candidatePresentationMode).assertEqual(CandidatePresentationMode.FLOATING);
    });

    it('imeSettingsEqual detects candidatePresentationMode change', 0, () => {
      const left = copyImeSettings(DEFAULT_IME_SETTINGS);
      const right = copyImeSettings(DEFAULT_IME_SETTINGS);
      right.candidatePresentationMode = CandidatePresentationMode.BAR;
      expect(imeSettingsEqual(left, right)).assertFalse();
    });

    it('settingsToRaw serializes candidatePresentationMode', 0, () => {
      const custom = copyImeSettings(DEFAULT_IME_SETTINGS);
      custom.candidatePresentationMode = CandidatePresentationMode.FLOATING;
      const raw = settingsToRaw(custom);
      expect(raw.candidatePresentationMode).assertEqual(CandidatePresentationMode.FLOATING);
    });

    it('SettingsValidator maps invalid candidatePresentationMode to default', 0, () => {
      const validator = new SettingsValidator();
      const result = validator.validate({
        schemaVersion: '1',
        candidatePresentationMode: 'not-a-mode'
      });
      expect(result.candidatePresentationMode).assertEqual(CandidatePresentationMode.AUTO);
    });

    it('SettingsValidator accepts BAR/FLOATING/AUTO', 0, () => {
      const validator = new SettingsValidator();
      const values: CandidatePresentationMode[] = [
        CandidatePresentationMode.BAR,
        CandidatePresentationMode.FLOATING,
        CandidatePresentationMode.AUTO
      ];
      values.forEach((value: CandidatePresentationMode): void => {
        const result = validator.validate({ schemaVersion: '1', candidatePresentationMode: value });
        expect(result.candidatePresentationMode).assertEqual(value);
      });
    });

    it('SettingsValidator falls back to AUTO when field is absent', 0, () => {
      const validator = new SettingsValidator();
      const result = validator.validate({ schemaVersion: '1' });
      expect(result.candidatePresentationMode).assertEqual(CandidatePresentationMode.AUTO);
    });
  });

  describe('customer stage 3.8 physical keyboard routing', () => {
    const activeSession: PhysicalKeySessionSnapshot = {
      sessionActive: true,
      editorConnected: true,
      candidateBarVisible: true,
      keyboardMode: KeyboardMode.CHINESE,
      rawInput: 'ni',
      candidateCount: 5
    };

    it('routes an ASCII hardware letter into Chinese composition', 0, () => {
      const command = resolvePhysicalKeyCommand({
        isDown: true, unicodeChar: 78, keyCode: 0, ctrlKey: false, altKey: false, logoKey: false
      }, physicalSession(''));
      expect(command.type).assertEqual(PhysicalKeyCommandType.LETTER);
      expect(command.letter).assertEqual('n');
    });

    it('maps a standard letter keyCode when a driver omits unicodeChar', 0, () => {
      const command = resolvePhysicalKeyCommand({
        isDown: true, unicodeChar: 0, keyCode: 2030, ctrlKey: false, altKey: false, logoKey: false
      }, physicalSession(''));
      expect(command.type).assertEqual(PhysicalKeyCommandType.LETTER);
      expect(command.letter).assertEqual('n');
    });

    it('routes space, delete and enter only while composition exists', 0, () => {
      expect(resolvePhysicalKeyCommand({
        isDown: true, unicodeChar: 32, keyCode: 2050, ctrlKey: false, altKey: false, logoKey: false
      }, activeSession).type).assertEqual(PhysicalKeyCommandType.SPACE);
      expect(resolvePhysicalKeyCommand({
        isDown: true, unicodeChar: 0, keyCode: 2055, ctrlKey: false, altKey: false, logoKey: false
      }, activeSession).type).assertEqual(PhysicalKeyCommandType.DELETE);
      expect(resolvePhysicalKeyCommand({
        isDown: true, unicodeChar: 10, keyCode: 2054, ctrlKey: false, altKey: false, logoKey: false
      }, activeSession).type).assertEqual(PhysicalKeyCommandType.ENTER);
    });

    it('routes 1-9 to an existing candidate and ignores shortcuts', 0, () => {
      const candidate = resolvePhysicalKeyCommand({
        isDown: true, unicodeChar: 50, keyCode: 2002, ctrlKey: false, altKey: false, logoKey: false
      }, activeSession);
      expect(candidate.type).assertEqual(PhysicalKeyCommandType.CANDIDATE);
      expect(candidate.candidateIndex).assertEqual(1);
      expect(resolvePhysicalKeyCommand({
        isDown: true, unicodeChar: 78, keyCode: 0, ctrlKey: true, altKey: false, logoKey: false
      }, activeSession).type).assertEqual(PhysicalKeyCommandType.NONE);
    });

    it('does not consume hardware keys outside an active Chinese session', 0, () => {
      const command = resolvePhysicalKeyCommand({
        isDown: true, unicodeChar: 78, keyCode: 0, ctrlKey: false, altKey: false, logoKey: false
      }, physicalSession('ni', KeyboardMode.ENGLISH));
      expect(command.type).assertEqual(PhysicalKeyCommandType.NONE);
    });
  });
}
