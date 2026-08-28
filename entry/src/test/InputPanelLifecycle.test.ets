import { describe, it, expect } from '@ohos/hypium';
import common from '@ohos.app.ability.common';
import { inputMethodEngine } from '@kit.IMEKit';
import {
  InputPanelController,
  KeyboardPanelBackend,
  ManagedKeyboardPanel,
  PanelCreationResult,
  PanelLifecycleState
} from '../main/ets/application/InputPanelController';
import { InputSessionController } from '../main/ets/application/InputSessionController';
import { SettingsStore } from '../main/ets/state/SettingsStore';
import { ImeErrorCode } from '../main/ets/common/error/ImeError';
import { copyImeSettings, DEFAULT_IME_SETTINGS, KeyboardHeightMode } from '../main/ets/domain/settings/ImeSettings';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';
import { createScreenMetrics, ScreenMetricsPx } from '../main/ets/domain/display/ScreenMetrics';
import { DeviceMetricsProvider } from '../main/ets/infrastructure/display/DeviceMetricsProvider';
import { InputMethodLifecycleDispatcher } from '../main/ets/application/InputMethodLifecycleDispatcher';

class Deferred {
  private resolver?: () => void;
  readonly promise: Promise<void> = new Promise<void>((resolve: () => void) => {
    this.resolver = resolve;
  });

  resolve(): void {
    this.resolver?.();
  }
}

class FakePanel implements ManagedKeyboardPanel {
  setContentCount: number = 0;
  resizeCount: number = 0;
  showCount: number = 0;
  hideCount: number = 0;
  resizeHeights: number[] = [];
  resizeWidths: number[] = [];
  showGate?: Deferred;
  hideGate?: Deferred;
  bottomSystemInsetPx: number = 0;
  rejectResize: boolean = false;

  async setUiContent(path: string): Promise<void> {
    this.setContentCount += 1;
  }

  async resize(width: number, height: number): Promise<void> {
    this.resizeCount += 1;
    this.resizeWidths.push(width);
    this.resizeHeights.push(height);
    if (this.rejectResize) {
      throw new Error('resize rejected');
    }
  }

  async show(): Promise<void> {
    this.showCount += 1;
    await this.showGate?.promise;
  }

  async hide(): Promise<void> {
    this.hideCount += 1;
    await this.hideGate?.promise;
  }

  async getDisplayId(): Promise<number> {
    return 0;
  }

  async getSystemPanelCurrentInsets(displayId: number): Promise<inputMethodEngine.SystemPanelInsets> {
    return { left: 0, right: 0, bottom: this.bottomSystemInsetPx };
  }
}

class FakePanelBackend implements KeyboardPanelBackend {
  readonly panel: FakePanel = new FakePanel();
  createCount: number = 0;
  destroyCount: number = 0;
  createGate?: Deferred;

  bindAbility(imeAbility: inputMethodEngine.InputMethodAbility, context: common.BaseContext): void {
  }

  async createPanel(): Promise<PanelCreationResult> {
    this.createCount += 1;
    await this.createGate?.promise;
    return {
      panel: this.panel,
      abilityReady: true,
      errorMessage: ''
    };
  }

  async destroyPanel(panel: ManagedKeyboardPanel): Promise<void> {
    this.destroyCount += 1;
  }
}

class FakeDeviceMetricsProvider implements DeviceMetricsProvider {
  readonly rawWidthPx: number;
  readonly rawHeightPx: number;
  readonly densityPixels: number;

  constructor(rawWidthPx: number, rawHeightPx: number, densityPixels: number) {
    this.rawWidthPx = rawWidthPx;
    this.rawHeightPx = rawHeightPx;
    this.densityPixels = densityPixels;
  }

  getMetrics(preferredIsLandscape?: boolean): ScreenMetricsPx {
    return createScreenMetrics({
      widthPx: this.rawWidthPx,
      heightPx: this.rawHeightPx,
      densityPixels: this.densityPixels
    }, preferredIsLandscape);
  }
}

class FakeSessionController extends InputSessionController {
  visibleCount: number = 0;
  hiddenCount: number = 0;
  destructiveHideCount: number = 0;
  errorCount: number = 0;

  constructor() {
    super(new InputSessionStore());
  }

  handleKeyboardShow(): void {
    this.visibleCount += 1;
  }

  handleKeyboardHide(): void {
    this.hiddenCount += 1;
    this.destructiveHideCount += 1;
  }

  handleKeyboardPanelHidden(): void {
    this.hiddenCount += 1;
  }

  recordError(code: ImeErrorCode, message: string): void {
    this.errorCount += 1;
  }
}

function nextTask(): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, 0);
  });
}

function createController(
  backend: FakePanelBackend,
  settingsStore: SettingsStore = new SettingsStore(),
  screenMetrics?: ScreenMetricsPx
): InputPanelController {
  const sessionController = new FakeSessionController();
  if (screenMetrics) {
    sessionController.setScreenMetrics(screenMetrics);
  }
  return new InputPanelController(sessionController, settingsStore, backend);
}

export default function inputPanelLifecycleTest() {
  describe('Input panel lifecycle serialization', () => {
    it('quick inputStart inputStop leaves panel hidden', 0, async () => {
      const backend = new FakePanelBackend();
      const controller = createController(backend);

      controller.handleInputStart();
      controller.handleInputStop();
      await controller.waitForLifecycleIdle();

      expect(controller.getLifecycleState()).assertEqual(PanelLifecycleState.HIDDEN);
      expect(backend.panel.showCount).assertEqual(0);
    });

    it('stop during create invalidates old show and latest start wins', 0, async () => {
      const backend = new FakePanelBackend();
      backend.createGate = new Deferred();
      const controller = createController(backend);

      controller.handleInputStart();
      await nextTask();
      controller.handleInputStop();
      controller.handleInputStart();
      backend.createGate.resolve();
      await controller.waitForLifecycleIdle();

      expect(backend.createCount).assertEqual(1);
      expect(backend.panel.showCount).assertEqual(1);
      expect(controller.getLifecycleState()).assertEqual(PanelLifecycleState.VISIBLE);
    });

    it('stop during create without restart never shows panel', 0, async () => {
      const backend = new FakePanelBackend();
      backend.createGate = new Deferred();
      const controller = createController(backend);

      controller.handleInputStart();
      await nextTask();
      controller.handleInputStop();
      backend.createGate.resolve();
      await controller.waitForLifecycleIdle();

      expect(backend.createCount).assertEqual(1);
      expect(backend.panel.showCount).assertEqual(0);
      expect(controller.getLifecycleState()).assertEqual(PanelLifecycleState.HIDDEN);
    });

    it('duplicate keyboardShow shares one show operation', 0, async () => {
      const backend = new FakePanelBackend();
      const controller = createController(backend);

      controller.handleInputStart();
      controller.showKeyboardPanel();
      controller.showKeyboardPanel();
      await controller.waitForLifecycleIdle();

      expect(backend.createCount).assertEqual(1);
      expect(backend.panel.showCount).assertEqual(1);
      expect(controller.getLifecycleState()).assertEqual(PanelLifecycleState.VISIBLE);
    });

    it('duplicate keyboardHide shares one hide operation', 0, async () => {
      const backend = new FakePanelBackend();
      const controller = createController(backend);
      controller.handleInputStart();
      await controller.waitForLifecycleIdle();

      controller.handleInputStop();
      controller.hideKeyboardPanel();
      controller.hideKeyboardPanel();
      await controller.waitForLifecycleIdle();

      expect(backend.panel.hideCount).assertEqual(1);
      expect(controller.getLifecycleState()).assertEqual(PanelLifecycleState.HIDDEN);
    });

    it('late keyboardShow after inputStop cannot resurrect panel', 0, async () => {
      const backend = new FakePanelBackend();
      const controller = createController(backend);
      controller.handleInputStart();
      await controller.waitForLifecycleIdle();

      controller.handleInputStop();
      controller.showKeyboardPanel();
      await controller.waitForLifecycleIdle();

      expect(backend.panel.showCount).assertEqual(1);
      expect(backend.panel.hideCount).assertEqual(1);
      expect(controller.getLifecycleState()).assertEqual(PanelLifecycleState.HIDDEN);
    });

    it('stop while panel show is pending corrects stale visibility', 0, async () => {
      const backend = new FakePanelBackend();
      backend.panel.showGate = new Deferred();
      const controller = createController(backend);

      controller.handleInputStart();
      await nextTask();
      controller.handleInputStop();
      backend.panel.showGate.resolve();
      await controller.waitForLifecycleIdle();

      expect(backend.panel.showCount).assertEqual(1);
      expect(backend.panel.hideCount >= 1).assertTrue();
      expect(controller.getLifecycleState()).assertEqual(PanelLifecycleState.HIDDEN);
    });

    it('ability destroy invalidates create and destroys without showing', 0, async () => {
      const backend = new FakePanelBackend();
      backend.createGate = new Deferred();
      const controller = createController(backend);

      controller.handleInputStart();
      await nextTask();
      controller.destroyPanel();
      backend.createGate.resolve();
      await controller.waitForLifecycleIdle();

      expect(backend.panel.showCount).assertEqual(0);
      expect(backend.destroyCount).assertEqual(1);
      expect(controller.getLifecycleState()).assertEqual(PanelLifecycleState.DESTROYED);
    });

    it('panel created before settings load performs one compensating resize', 0, async () => {
      const backend = new FakePanelBackend();
      const settingsStore = new SettingsStore();
      const controller = createController(backend, settingsStore);

      controller.handleInputStart();
      await controller.waitForLifecycleIdle();
      expect(backend.panel.resizeCount).assertEqual(1);
      expect(backend.panel.resizeHeights[0]).assertEqual(1032);

      const loaded = copyImeSettings(DEFAULT_IME_SETTINGS);
      loaded.keyboardHeightMode = KeyboardHeightMode.TALL;
      settingsStore.replace(loaded);
      await controller.waitForLifecycleIdle();

      expect(backend.panel.resizeCount).assertEqual(2);
      expect(backend.panel.resizeHeights[1]).assertEqual(1134);
    });

    it('settings readiness barrier applies loaded height before first panel creation', 0, async () => {
      const backend = new FakePanelBackend();
      const settingsStore = new SettingsStore();
      const controller = createController(backend, settingsStore);
      const gate = new Deferred();
      const loaded = copyImeSettings(DEFAULT_IME_SETTINGS);
      loaded.keyboardHeightMode = KeyboardHeightMode.TALL;
      const settingsReady = gate.promise.then(() => loaded);

      controller.bindAbility(
        {} as inputMethodEngine.InputMethodAbility,
        {} as common.BaseContext,
        settingsReady
      );
      controller.handleInputStart();
      await nextTask();
      expect(backend.createCount).assertEqual(0);

      settingsStore.replace(loaded);
      gate.resolve();
      await controller.waitForLifecycleIdle();
      expect(backend.createCount).assertEqual(1);
      expect(backend.panel.resizeCount).assertEqual(1);
      expect(backend.panel.resizeHeights[0]).assertEqual(1134);
    });

    it('duplicate and rapid settings notifications coalesce stale resize work', 0, async () => {
      const backend = new FakePanelBackend();
      const settingsStore = new SettingsStore();
      const controller = createController(backend, settingsStore);
      controller.handleInputStart();
      await controller.waitForLifecycleIdle();

      const compact = copyImeSettings(DEFAULT_IME_SETTINGS);
      compact.keyboardHeightMode = KeyboardHeightMode.COMPACT;
      const tall = copyImeSettings(DEFAULT_IME_SETTINGS);
      tall.keyboardHeightMode = KeyboardHeightMode.TALL;
      settingsStore.replace(compact);
      settingsStore.replace(tall);
      settingsStore.replace(copyImeSettings(tall));
      await controller.waitForLifecycleIdle();

      expect(backend.panel.resizeCount).assertEqual(2);
      expect(backend.panel.resizeHeights[1]).assertEqual(1134);
    });

    it('lift layer setting resizes the visible panel without restarting the input session', 0, async () => {
      const backend = new FakePanelBackend();
      const settingsStore = new SettingsStore();
      const controller = createController(backend, settingsStore);
      controller.handleInputStart();
      await controller.waitForLifecycleIdle();
      expect(backend.panel.resizeHeights[0]).assertEqual(1032);

      const withoutLiftLayer = copyImeSettings(DEFAULT_IME_SETTINGS);
      withoutLiftLayer.keyboardLiftLayerEnabled = false;
      settingsStore.replace(withoutLiftLayer);
      await controller.waitForLifecycleIdle();

      expect(backend.panel.resizeCount).assertEqual(2);
      expect(backend.panel.resizeHeights[1]).assertEqual(894);
    });

    it('does not retry forever after the platform rejects a resize', 0, async () => {
      const backend = new FakePanelBackend();
      const settingsStore = new SettingsStore();
      const controller = createController(backend, settingsStore);
      controller.handleInputStart();
      await controller.waitForLifecycleIdle();

      backend.panel.rejectResize = true;
      const tall = copyImeSettings(DEFAULT_IME_SETTINGS);
      tall.keyboardHeightMode = KeyboardHeightMode.TALL;
      settingsStore.replace(tall);
      await controller.waitForLifecycleIdle();

      expect(backend.panel.resizeCount).assertEqual(2);
    });

    it('first landscape panel resize uses the injected 2880x1920 snapshot', 0, async () => {
      const backend = new FakePanelBackend();
      const landscape = createScreenMetrics({ widthPx: 2880, heightPx: 1920, densityPixels: 2 }, true);
      const controller = createController(backend, new SettingsStore(), landscape);

      controller.handleInputStart();
      await controller.waitForLifecycleIdle();

      expect(backend.panel.resizeCount).assertEqual(1);
      expect(backend.panel.resizeWidths[0]).assertEqual(2880);
      expect(backend.panel.resizeHeights[0]).assertEqual(1144);
    });

    it('rotation publishes width and height together and duplicate snapshots do not resize', 0, async () => {
      const backend = new FakePanelBackend();
      const sessionController = new FakeSessionController();
      const portrait = createScreenMetrics({ widthPx: 1920, heightPx: 2880, densityPixels: 2 }, false);
      const landscape = createScreenMetrics({ widthPx: 2880, heightPx: 1920, densityPixels: 2 }, true);
      sessionController.setScreenMetrics(portrait);
      const controller = new InputPanelController(sessionController, new SettingsStore(), backend);
      controller.handleInputStart();
      await controller.waitForLifecycleIdle();

      sessionController.setScreenMetrics(landscape);
      await controller.waitForLifecycleIdle();
      sessionController.setScreenMetrics(landscape);
      await controller.waitForLifecycleIdle();

      expect(backend.panel.resizeCount).assertEqual(2);
      expect(backend.panel.resizeWidths[0]).assertEqual(1920);
      expect(backend.panel.resizeHeights[0]).assertEqual(1190);
      expect(backend.panel.resizeWidths[1]).assertEqual(2880);
      expect(backend.panel.resizeHeights[1]).assertEqual(1144);
    });

    it('publishes API 21 system panel bottom insets before sizing the keyboard panel', 0, async () => {
      const backend = new FakePanelBackend();
      backend.panel.bottomSystemInsetPx = 900;
      const sessionController = new FakeSessionController();
      const controller = new InputPanelController(sessionController, new SettingsStore(), backend);

      controller.handleInputStart();
      await controller.waitForLifecycleIdle();

      expect(sessionController.getState().screenMetrics.bottomSystemInsetPx).assertEqual(900);
      expect(backend.panel.resizeCount).assertEqual(1);
      // The system inset reduces the available height without adding a custom phone auxiliary row.
      expect(backend.panel.resizeHeights[0] < 1032).assertTrue();
    });

    it('lifecycle accepts an injected metrics provider and trusts configuration direction', 0, () => {
      const backend = new FakePanelBackend();
      const sessionController = new FakeSessionController();
      const panelController = new InputPanelController(sessionController, new SettingsStore(), backend);
      const provider = new FakeDeviceMetricsProvider(1920, 2880, 2);
      const dispatcher = new InputMethodLifecycleDispatcher(sessionController, panelController, provider);

      dispatcher.handleConfigurationUpdate(true);

      const screen = sessionController.getState().screenMetrics;
      expect(screen.isLandscape).assertTrue();
      expect(screen.widthPx).assertEqual(2880);
      expect(screen.heightPx).assertEqual(1920);
    });
  });
}
