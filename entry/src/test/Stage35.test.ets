import { describe, it, expect } from '@ohos/hypium';
import { ShortLongPressController } from '../main/ets/application/ShortLongPressController';
import { createUnknownEditorContext, ShiftState } from '../main/ets/domain/editor/EditorContext';
import {
  KeyboardDeviceFormFactor,
  resolveKeyboardAuxiliaryAreaPolicy
} from '../main/ets/domain/display/KeyboardAuxiliaryAreaPolicy';
import { createScreenMetrics } from '../main/ets/domain/display/ScreenMetrics';
import { KeyboardActionType, KeyboardMode } from '../main/ets/domain/keyboard/KeyboardAction';
import {
  InputMethodDescriptor,
  InputMethodSwitchCapabilities,
  InputMethodSwitcher,
  InputMethodSwitchResultType,
  InputMethodSystemBackend
} from '../main/ets/infrastructure/ime/InputMethodSwitcher';
import { createStage10KeyboardLayout } from '../main/ets/presentation/keyboard/layouts/Stage10KeyboardLayouts';
import { KEYBOARD_STATUS_BAR_LAYOUT } from '../main/ets/presentation/candidate/CandidateBar';

const FULL_CAPABILITIES: InputMethodSwitchCapabilities = {
  canSwitchToNext: true,
  canShowSystemPicker: true,
  canListInputMethods: true,
  canSwitchToSpecified: true,
  minimumListApi: 9,
  minimumCurrentImeSwitchApi: 11,
  minimumPickerApi: 9
};

class Deferred {
  private resolver?: () => void;
  readonly promise: Promise<void> = new Promise<void>((resolve: () => void) => {
    this.resolver = resolve;
  });

  resolve(): void {
    this.resolver?.();
  }
}

class FakeInputMethodBackend implements InputMethodSystemBackend {
  capabilities: InputMethodSwitchCapabilities = FULL_CAPABILITIES;
  enabled: InputMethodDescriptor[] = [
    { name: 'first.bundle', id: 'FirstIme' },
    { name: 'second.bundle', id: 'SecondIme' }
  ];
  current: InputMethodDescriptor = { name: 'first.bundle', id: 'FirstIme' };
  switchResult: boolean = true;
  pickerResults: boolean[] = [true];
  switchCount: number = 0;
  pickerCount: number = 0;
  switchedTarget?: InputMethodDescriptor;
  listGate?: Deferred;
  pickerGate?: Deferred;

  getCapabilities(): InputMethodSwitchCapabilities {
    return this.capabilities;
  }

  async listEnabledInputMethods(): Promise<InputMethodDescriptor[]> {
    await this.listGate?.promise;
    return this.enabled;
  }

  getCurrentInputMethod(): InputMethodDescriptor {
    return this.current;
  }

  async switchToInputMethod(target: InputMethodDescriptor): Promise<boolean> {
    this.switchCount += 1;
    this.switchedTarget = target;
    return this.switchResult;
  }

  async showSystemPicker(): Promise<boolean> {
    this.pickerCount += 1;
    await this.pickerGate?.promise;
    if (this.pickerResults.length === 0) {
      return false;
    }
    return this.pickerResults.shift() ?? false;
  }
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
}

export default function stage35Test() {
  describe('customer stage 3.5 input method switcher and auxiliary area', () => {
    it('uses an inline switch only for tablets and special phone layouts', 0, () => {
      const phonePortrait = createScreenMetrics({
        widthPx: 1080, heightPx: 2340, densityPixels: 3, bottomSystemInsetPx: 120
      });
      const narrowPhonePortrait = createScreenMetrics({
        widthPx: 900, heightPx: 2100, densityPixels: 3, bottomSystemInsetPx: 120
      });
      const widePhonePortrait = createScreenMetrics({
        widthPx: 1500, heightPx: 2700, densityPixels: 3, bottomSystemInsetPx: 120
      });
      const phoneLandscape = createScreenMetrics({
        widthPx: 2340, heightPx: 1080, densityPixels: 3, bottomSystemInsetPx: 120
      }, true);
      const tabletPortrait = createScreenMetrics({ widthPx: 1920, heightPx: 2880, densityPixels: 2 }, false);
      const tabletLandscape = createScreenMetrics({ widthPx: 2880, heightPx: 1920, densityPixels: 2 }, true);

      const phonePolicy = resolveKeyboardAuxiliaryAreaPolicy(phonePortrait);
      expect(phonePolicy.formFactor).assertEqual(KeyboardDeviceFormFactor.PHONE);
      expect(phonePolicy.showInlineInputMethodKey).assertFalse();
      expect(resolveKeyboardAuxiliaryAreaPolicy(narrowPhonePortrait).showInlineInputMethodKey).assertTrue();
      expect(resolveKeyboardAuxiliaryAreaPolicy(widePhonePortrait).showInlineInputMethodKey).assertTrue();
      expect(resolveKeyboardAuxiliaryAreaPolicy(phoneLandscape).showInlineInputMethodKey).assertTrue();
      expect(resolveKeyboardAuxiliaryAreaPolicy(tabletPortrait).showInlineInputMethodKey).assertTrue();
      expect(resolveKeyboardAuxiliaryAreaPolicy(tabletLandscape).showInlineInputMethodKey).assertTrue();
    });

    it('shows an inline fallback when the system input method area is absent', 0, () => {
      const zeroInset = createScreenMetrics({
        widthPx: 1080, heightPx: 2340, densityPixels: 3, bottomSystemInsetPx: 0
      });
      const systemArea = createScreenMetrics({
        widthPx: 1080, heightPx: 2340, densityPixels: 3, bottomSystemInsetPx: 120
      });

      const fallbackPolicy = resolveKeyboardAuxiliaryAreaPolicy(zeroInset);
      const systemAreaPolicy = resolveKeyboardAuxiliaryAreaPolicy(systemArea);
      expect(fallbackPolicy.hasSystemInputMethodArea).assertFalse();
      expect(fallbackPolicy.showInlineInputMethodKey).assertTrue();
      expect(systemAreaPolicy.hasSystemInputMethodArea).assertTrue();
      expect(systemAreaPolicy.showInlineInputMethodKey).assertFalse();
      expect(systemAreaPolicy.bottomSystemInsetVp).assertEqual(40);
    });

    it('adds the Pad switch key only to the text bottom row without changing letter rows', 0, () => {
      const context = createUnknownEditorContext();
      const phone = createStage10KeyboardLayout(KeyboardMode.CHINESE, context, ShiftState.LOWERCASE, '', false, false);
      const tablet = createStage10KeyboardLayout(KeyboardMode.CHINESE, context, ShiftState.LOWERCASE, '', false, true);
      const phoneIds = phone.rows[3].keys.map((key) => key.id);
      const tabletIds = tablet.rows[3].keys.map((key) => key.id);
      expect(phoneIds.indexOf('input-method-switch')).assertEqual(-1);
      expect(tabletIds.indexOf('input-method-switch') > -1).assertTrue();
      expect(tablet.rows[3].keys[1].action.type).assertEqual(KeyboardActionType.SWITCH_INPUT_METHOD);
      expect(tablet.rows[3].keys[1].longPressAction?.type)
        .assertEqual(KeyboardActionType.SHOW_INPUT_METHOD_PICKER);
      expect(phone.rows[0].keys.map((key) => key.id).join(','))
        .assertEqual(tablet.rows[0].keys.map((key) => key.id).join(','));
      const phoneWeight = phone.rows[3].keys.reduce((sum: number, key) => sum + key.weight, 0);
      const tabletWeight = tablet.rows[3].keys.reduce((sum: number, key) => sum + key.weight, 0);
      expect(tabletWeight).assertEqual(phoneWeight);
      const languageKey = phone.rows[3].keys.find((key) => key.id === 'language');
      expect(languageKey?.action.type).assertEqual(KeyboardActionType.TOGGLE_LANGUAGE);
      expect(languageKey?.longPressAction === undefined).assertTrue();
    });

    it('keeps the inline fallback reachable in numeric phone and symbol layouts', 0, () => {
      const context = createUnknownEditorContext();
      [KeyboardMode.NUMBER, KeyboardMode.PHONE, KeyboardMode.SYMBOL].forEach((mode: KeyboardMode): void => {
        const layout = createStage10KeyboardLayout(mode, context, ShiftState.LOWERCASE, '', false, true);
        const bottom = layout.rows[layout.rows.length - 1].keys;
        const switchKey = bottom.find((key) => key.id === 'input-method-switch');
        expect(switchKey?.action.type).assertEqual(KeyboardActionType.SWITCH_INPUT_METHOD);
        expect(switchKey?.longPressAction?.type).assertEqual(KeyboardActionType.SHOW_INPUT_METHOD_PICKER);
      });
    });

    it('keeps the candidate bar as the only custom hide affordance', 0, () => {
      expect(KEYBOARD_STATUS_BAR_LAYOUT.action.type).assertEqual(KeyboardActionType.HIDE_KEYBOARD);
    });

    it('switches to the next enabled input method through the current-IME API path', 0, async () => {
      const backend = new FakeInputMethodBackend();
      const switcher = new InputMethodSwitcher(backend, 0);
      switcher.setSessionActive(true);
      const result = await switcher.requestSwitchToNext();
      expect(result.type).assertEqual(InputMethodSwitchResultType.SWITCHED_TO_NEXT);
      expect(backend.switchCount).assertEqual(1);
      expect(backend.switchedTarget?.name).assertEqual('second.bundle');
      expect(backend.pickerCount).assertEqual(0);
    });

    it('falls back to the system picker when direct switching fails', 0, async () => {
      const backend = new FakeInputMethodBackend();
      backend.switchResult = false;
      const switcher = new InputMethodSwitcher(backend, 0);
      switcher.setSessionActive(true);
      const result = await switcher.requestSwitchToNext();
      expect(result.type).assertEqual(InputMethodSwitchResultType.FALLBACK_PICKER_OPENED);
      expect(backend.switchCount).assertEqual(1);
      expect(backend.pickerCount).assertEqual(1);
    });

    it('does not expose a silent operation when both system capabilities are absent', 0, async () => {
      const backend = new FakeInputMethodBackend();
      backend.capabilities = {
        canSwitchToNext: false,
        canShowSystemPicker: false,
        canListInputMethods: false,
        canSwitchToSpecified: false,
        minimumListApi: 9,
        minimumCurrentImeSwitchApi: 11,
        minimumPickerApi: 9
      };
      const switcher = new InputMethodSwitcher(backend, 0);
      switcher.setSessionActive(true);
      const result = await switcher.requestSwitchToNext();
      expect(result.type).assertEqual(InputMethodSwitchResultType.UNAVAILABLE);
      expect(result.success).assertFalse();
      expect(backend.switchCount).assertEqual(0);
      expect(backend.pickerCount).assertEqual(0);
    });

    it('suppresses concurrent picker requests and releases the guard after completion', 0, async () => {
      const backend = new FakeInputMethodBackend();
      backend.pickerGate = new Deferred();
      const switcher = new InputMethodSwitcher(backend, 0);
      switcher.setSessionActive(true);
      const first = switcher.requestShowSystemPicker();
      const duplicate = await switcher.requestShowSystemPicker();
      expect(duplicate.type).assertEqual(InputMethodSwitchResultType.REQUEST_ALREADY_IN_PROGRESS);
      backend.pickerGate.resolve();
      expect((await first).type).assertEqual(InputMethodSwitchResultType.SYSTEM_PICKER_OPENED);
      backend.pickerGate = undefined;
      backend.pickerResults.push(true);
      expect((await switcher.requestShowSystemPicker()).success).assertTrue();
      expect(backend.pickerCount).assertEqual(2);
    });

    it('invalidates an in-flight switch when the input session ends', 0, async () => {
      const backend = new FakeInputMethodBackend();
      backend.listGate = new Deferred();
      const switcher = new InputMethodSwitcher(backend, 0);
      switcher.setSessionActive(true);
      const pending = switcher.requestSwitchToNext();
      switcher.setSessionActive(false);
      backend.listGate.resolve();
      const result = await pending;
      expect(result.type).assertEqual(InputMethodSwitchResultType.SESSION_INVALID);
      expect(backend.switchCount).assertEqual(0);
    });

    it('recovers after a failed picker call instead of remaining locked', 0, async () => {
      const backend = new FakeInputMethodBackend();
      backend.pickerResults = [false, true];
      const switcher = new InputMethodSwitcher(backend, 0);
      switcher.setSessionActive(true);
      expect((await switcher.requestShowSystemPicker()).success).assertFalse();
      expect((await switcher.requestShowSystemPicker()).success).assertTrue();
      expect(backend.pickerCount).assertEqual(2);
    });

    it('fires one short press and suppresses short press after long press', 0, async () => {
      let shortCount = 0;
      let longCount = 0;
      const controller = new ShortLongPressController(
        (): void => { shortCount += 1; },
        (): void => { longCount += 1; },
        5
      );
      controller.start();
      controller.release();
      controller.click();
      expect(shortCount).assertEqual(1);
      expect(longCount).assertEqual(0);

      controller.start();
      await delay(15);
      controller.release();
      controller.click();
      expect(shortCount).assertEqual(1);
      expect(longCount).assertEqual(1);

      // A fresh tap immediately after the long press is independent and fires exactly once.
      controller.start();
      controller.release();
      controller.click();
      controller.start();
      controller.release();
      controller.click();
      expect(shortCount).assertEqual(3);
      expect(longCount).assertEqual(1);
      controller.destroy();
    });

    it('accepts ArkUI click-before-up and accessibility click ordering', 0, () => {
      let shortCount = 0;
      const controller = new ShortLongPressController(
        (): void => { shortCount += 1; },
        (): void => {},
        1000
      );
      controller.start();
      controller.click();
      controller.release();
      expect(shortCount).assertEqual(1);

      controller.click();
      expect(shortCount).assertEqual(2);
      controller.destroy();
    });

    it('cancels moved or hidden long presses without firing either action', 0, async () => {
      let shortCount = 0;
      let longCount = 0;
      const controller = new ShortLongPressController(
        (): void => { shortCount += 1; },
        (): void => { longCount += 1; },
        5
      );
      controller.start();
      controller.cancel();
      await delay(15);
      controller.click();
      expect(shortCount).assertEqual(0);
      expect(longCount).assertEqual(0);
      controller.destroy();
    });
  });
}
