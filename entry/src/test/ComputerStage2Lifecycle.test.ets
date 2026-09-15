import { describe, expect, it } from '@ohos/hypium';
import common from '@ohos.app.ability.common';
import { inputMethodEngine } from '@kit.IMEKit';
import {
  InputPresentationMode,
  InputPresentationPreference,
  InputPresentationState,
  resolveInputPresentationMode
} from '../main/ets/domain/display/InputPresentationMode';
import {
  ManagedSoftKeyboardPanel,
  SoftKeyboardPanelOwner,
  SoftKeyboardPanelOwnershipCoordinator
} from '../main/ets/application/SoftKeyboardPanelOwnershipCoordinator';
import {
  InputPanelController,
  KeyboardPanelBackend,
  ManagedKeyboardPanel,
  PanelCreationResult,
  PanelLifecycleState
} from '../main/ets/application/InputPanelController';
import { InputSessionController } from '../main/ets/application/InputSessionController';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';
import { SettingsStore } from '../main/ets/state/SettingsStore';
import { ImeErrorCode } from '../main/ets/common/error/ImeError';
import { InputMethodLifecycleDispatcher } from '../main/ets/application/InputMethodLifecycleDispatcher';
import { InputPresentationModeProvider } from '../main/ets/infrastructure/ime/InputPresentationModeProvider';

class Stage2Panel implements ManagedKeyboardPanel, ManagedSoftKeyboardPanel {
  showCount: number = 0;
  hideCount: number = 0;

  async setUiContent(_path: string): Promise<void> {
  }

  async resize(_width: number, _height: number): Promise<void> {
  }

  async show(): Promise<void> {
    this.showCount += 1;
  }

  async hide(): Promise<void> {
    this.hideCount += 1;
  }
}

class Stage2PanelBackend implements KeyboardPanelBackend {
  readonly panel: Stage2Panel = new Stage2Panel();
  createCount: number = 0;
  destroyCount: number = 0;

  bindAbility(_imeAbility: inputMethodEngine.InputMethodAbility, _context: common.BaseContext): void {
  }

  async createPanel(): Promise<PanelCreationResult> {
    this.createCount += 1;
    return { panel: this.panel, abilityReady: true, errorMessage: '' };
  }

  async destroyPanel(_panel: ManagedKeyboardPanel): Promise<void> {
    this.destroyCount += 1;
  }
}

class Stage2SessionController extends InputSessionController {
  panelHiddenCount: number = 0;
  destructiveHideCount: number = 0;
  private readonly stage2Store: InputSessionStore;

  constructor(store: InputSessionStore = new InputSessionStore()) {
    super(store);
    this.stage2Store = store;
  }

  handleInputStart(
    _keyboardController: inputMethodEngine.KeyboardController,
    _inputClient: inputMethodEngine.InputClient
  ): void {
    this.getStateStore().markSessionStarted();
  }

  handleKeyboardHide(): void {
    this.destructiveHideCount += 1;
  }

  handleKeyboardPanelHidden(): void {
    this.panelHiddenCount += 1;
  }

  recordError(_code: ImeErrorCode, _message: string): void {
  }

  private getStateStore(): InputSessionStore {
    return this.stage2Store;
  }
}

class HardwareModeProvider implements InputPresentationModeProvider {
  resolve(): InputPresentationMode {
    return InputPresentationMode.HARDWARE;
  }
}

class OwnershipPanel implements ManagedSoftKeyboardPanel {
}

export default function computerStage2LifecycleTest() {
  describe('computer remediation stage 2 lifecycle', () => {
    it('AUTO resolves 2in1 and connected-keyboard Tablet to hardware mode', 0, () => {
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, '2in1'))
        .assertEqual(InputPresentationMode.HARDWARE);
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, 'phone'))
        .assertEqual(InputPresentationMode.TOUCH);
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, 'tablet'))
        .assertEqual(InputPresentationMode.TOUCH);
      expect(resolveInputPresentationMode(InputPresentationPreference.AUTO, 'tablet', true))
        .assertEqual(InputPresentationMode.HARDWARE);
      expect(resolveInputPresentationMode(InputPresentationPreference.TOUCH, '2in1'))
        .assertEqual(InputPresentationMode.TOUCH);
      expect(resolveInputPresentationMode(InputPresentationPreference.HARDWARE, 'phone'))
        .assertEqual(InputPresentationMode.HARDWARE);
    });

    it('switches a live controller back to touch mode through the same serialized owner', 0, async () => {
      const session = new Stage2SessionController();
      const backend = new Stage2PanelBackend();
      const panel = new InputPanelController(session, new SettingsStore(), backend);

      panel.handleInputStart(InputPresentationMode.HARDWARE);
      panel.showKeyboardPanel();
      await panel.waitForLifecycleIdle();
      expect(backend.createCount).assertEqual(0);
      panel.handlePresentationModeChange(InputPresentationMode.TOUCH);
      await panel.waitForLifecycleIdle();

      expect(backend.createCount).assertEqual(1);
      expect(backend.panel.showCount).assertEqual(1);
      expect(panel.getLifecycleState()).assertEqual(PanelLifecycleState.VISIBLE);
      expect(session.destructiveHideCount).assertEqual(0);
    });

    it('hardware inputStart reaches HARDWARE_READY without creating a fixed panel', 0, async () => {
      const store = new InputSessionStore();
      const session = new Stage2SessionController(store);
      const backend = new Stage2PanelBackend();
      const panel = new InputPanelController(session, new SettingsStore(), backend);
      const dispatcher = new InputMethodLifecycleDispatcher(
        session,
        panel,
        undefined,
        undefined,
        new HardwareModeProvider()
      );

      dispatcher.handleInputStart(
        {} as inputMethodEngine.KeyboardController,
        {} as inputMethodEngine.InputClient
      );
      await panel.waitForLifecycleIdle();

      expect(dispatcher.getPresentationState()).assertEqual(InputPresentationState.HARDWARE_READY);
      expect(backend.createCount).assertEqual(0);
      expect(store.getSnapshot().sessionActive).assertTrue();
      expect(store.getSnapshot().editorConnected).assertTrue();
      expect(store.getSnapshot().keyboardVisible).assertFalse();

      dispatcher.handleKeyboardHide();
      expect(session.destructiveHideCount).assertEqual(0);
      expect(store.getSnapshot().sessionActive).assertTrue();
      expect(store.getSnapshot().editorConnected).assertTrue();
    });

    it('switching a live touch controller to hardware destroys fixed panel without destructive hide', 0, async () => {
      const session = new Stage2SessionController();
      const backend = new Stage2PanelBackend();
      const panel = new InputPanelController(session, new SettingsStore(), backend);

      panel.handleInputStart(InputPresentationMode.TOUCH);
      panel.showKeyboardPanel();
      await panel.waitForLifecycleIdle();
      panel.handleInputStart(InputPresentationMode.HARDWARE);
      await panel.waitForLifecycleIdle();

      expect(backend.createCount).assertEqual(1);
      expect(backend.destroyCount).assertEqual(1);
      expect(panel.getLifecycleState()).assertEqual(PanelLifecycleState.HIDDEN);
      expect(session.destructiveHideCount).assertEqual(0);
      expect(session.panelHiddenCount > 0).assertTrue();
    });

    it('serial ownership switch destroys and revokes fixed panel before candidate acquisition', 0, async () => {
      const coordinator = new SoftKeyboardPanelOwnershipCoordinator();
      const fixed = new OwnershipPanel();
      const candidate = new OwnershipPanel();
      let fixedDestroyed = false;
      let fixedRevoked = false;

      await coordinator.acquire(
        SoftKeyboardPanelOwner.FIXED_KEYBOARD,
        async (): Promise<ManagedSoftKeyboardPanel> => fixed,
        async (_panel: ManagedSoftKeyboardPanel): Promise<void> => {
          fixedDestroyed = true;
        },
        (): void => {
          fixedRevoked = true;
        }
      );
      await coordinator.acquire(
        SoftKeyboardPanelOwner.CANDIDATE_WINDOW,
        async (): Promise<ManagedSoftKeyboardPanel> => candidate,
        async (_panel: ManagedSoftKeyboardPanel): Promise<void> => {
        },
        (): void => {
        }
      );

      expect(fixedDestroyed).assertTrue();
      expect(fixedRevoked).assertTrue();
      expect(coordinator.getActiveOwner()).assertEqual(SoftKeyboardPanelOwner.CANDIDATE_WINDOW);
    });
  });
}
