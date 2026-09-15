import common from '@ohos.app.ability.common';
import { inputMethodEngine } from '@kit.IMEKit';
import { ImeErrorCode } from '../common/error/ImeError';
import { Logger } from '../common/logging/Logger';
import { InputSessionController } from './InputSessionController';
import { getSharedSettingsStore, SettingsStore } from '../state/SettingsStore';
import { panelHeightForMode } from '../presentation/keyboard/design/KeyboardMetrics';
import { CandidatePresentationMode, ImeSettings } from '../domain/settings/ImeSettings';
import { InputPresentationMode } from '../domain/display/InputPresentationMode';
import { KeyboardMode } from '../domain/keyboard/KeyboardAction';
import { PINYIN_9_PROFILE_ID } from '../domain/keyboard/KeyboardProfile';
import {
  ManagedSoftKeyboardPanel,
  SoftKeyboardPanelOwner,
  SoftKeyboardPanelOwnershipCoordinator
} from './SoftKeyboardPanelOwnershipCoordinator';

const TAG = 'InputPanelController';
const LOGGER = new Logger(TAG);
const STAGE3_KEYBOARD_PAGE = 'presentation/keyboard/KeyboardRootStage3';

interface PanelSizePx {
  widthPx: number;
  heightPx: number;
}

function panelSizeEqual(left: PanelSizePx | undefined, right: PanelSizePx): boolean {
  return left !== undefined && left.widthPx === right.widthPx && left.heightPx === right.heightPx;
}

export enum PanelLifecycleState {
  UNINITIALIZED = 'UNINITIALIZED',
  CREATING = 'CREATING',
  HIDDEN = 'HIDDEN',
  SHOWING = 'SHOWING',
  VISIBLE = 'VISIBLE',
  HIDING = 'HIDING',
  DESTROYED = 'DESTROYED'
}

export interface ManagedKeyboardPanel {
  setUiContent(path: string): Promise<void>;
  resize(width: number, height: number): Promise<void>;
  show(): Promise<void>;
  hide(): Promise<void>;
  getDisplayId?(): Promise<number>;
  getSystemPanelCurrentInsets?(displayId: number): Promise<inputMethodEngine.SystemPanelInsets>;
}

export interface PanelCreationResult {
  panel?: ManagedKeyboardPanel;
  abilityReady: boolean;
  errorMessage: string;
}

export interface KeyboardPanelBackend {
  bindAbility(imeAbility: inputMethodEngine.InputMethodAbility, context: common.BaseContext): void;
  createPanel(): Promise<PanelCreationResult>;
  destroyPanel(panel: ManagedKeyboardPanel): Promise<void>;
}

class HarmonyKeyboardPanelBackend implements KeyboardPanelBackend {
  private imeAbility?: inputMethodEngine.InputMethodAbility;
  private context?: common.BaseContext;

  bindAbility(imeAbility: inputMethodEngine.InputMethodAbility, context: common.BaseContext): void {
    this.imeAbility = imeAbility;
    this.context = context;
  }

  async createPanel(): Promise<PanelCreationResult> {
    if (!this.imeAbility || !this.context) {
      return {
        abilityReady: false,
        errorMessage: 'input method ability is not ready'
      };
    }
    try {
      const panel = await this.imeAbility.createPanel(this.context, {
        type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
        flag: inputMethodEngine.PanelFlag.FLG_FIXED
      });
      return {
        panel,
        abilityReady: true,
        errorMessage: ''
      };
    } catch (err) {
      return {
        abilityReady: true,
        errorMessage: JSON.stringify(err)
      };
    }
  }

  async destroyPanel(panel: ManagedKeyboardPanel): Promise<void> {
    if (this.imeAbility) {
      await this.imeAbility.destroyPanel(panel as inputMethodEngine.Panel);
    }
  }
}

export class InputPanelController {
  private panel?: ManagedKeyboardPanel;
  private panelContentReady: boolean = false;
  private lifecycleGeneration: number = 0;
  private inputSessionActive: boolean = false;
  private targetVisible: boolean = false;
  private lifecycleState: PanelLifecycleState = PanelLifecycleState.UNINITIALIZED;
  private lifecycleQueue: Promise<void> = Promise.resolve();
  private scheduledShowGeneration?: number;
  private scheduledHideGeneration?: number;
  private scheduledResizeGeneration?: number;
  private lastAppliedPanelSize?: PanelSizePx;
  private settingsReady: Promise<void> = Promise.resolve();
  private disposed: boolean = false;
  private settingsSubscribed: boolean = false;
  private sessionSubscribed: boolean = false;
  private readonly sessionController: InputSessionController;
  private readonly settingsStore: SettingsStore;
  private readonly backend: KeyboardPanelBackend;
  private ownershipCoordinator: SoftKeyboardPanelOwnershipCoordinator =
    new SoftKeyboardPanelOwnershipCoordinator();
  private presentationMode: InputPresentationMode = InputPresentationMode.TOUCH;
  private readonly onSettingsChanged = (): void => {
    this.queueSettingsResize();
  };
  private readonly onSessionStateChanged = (): void => {
    this.queueSessionResize();
  };

  constructor(
    sessionController: InputSessionController = new InputSessionController(),
    settingsStore: SettingsStore = getSharedSettingsStore(),
    backend: KeyboardPanelBackend = new HarmonyKeyboardPanelBackend()
  ) {
    this.sessionController = sessionController;
    this.settingsStore = settingsStore;
    this.backend = backend;
    this.subscribeToSettings();
    this.subscribeToSession();
  }

  bindAbility(
    imeAbility: inputMethodEngine.InputMethodAbility,
    context: common.BaseContext,
    settingsReady?: Promise<ImeSettings>
  ): void {
    this.backend.bindAbility(imeAbility, context);
    this.settingsReady = settingsReady ? settingsReady.then((): void => {
    }).catch((err: Object): void => {
      LOGGER.warn(`settings readiness failed; continuing with current snapshot: ${JSON.stringify(err)}`);
    }) : Promise.resolve();
    this.disposed = false;
    this.inputSessionActive = false;
    this.targetVisible = false;
    this.lifecycleGeneration += 1;
    this.lifecycleState = this.panel ? PanelLifecycleState.HIDDEN : PanelLifecycleState.UNINITIALIZED;
    this.subscribeToSettings();
    this.subscribeToSession();
  }

  bindOwnershipCoordinator(coordinator: SoftKeyboardPanelOwnershipCoordinator): void {
    if (!this.panel) {
      this.ownershipCoordinator = coordinator;
    }
  }

  handleInputStart(mode: InputPresentationMode = InputPresentationMode.TOUCH): void {
    if (this.disposed) {
      return;
    }
    this.lifecycleGeneration += 1;
    this.inputSessionActive = true;
    this.presentationMode = mode;
    this.targetVisible = mode === InputPresentationMode.TOUCH;
    if (this.targetVisible) {
      this.queueShow(this.lifecycleGeneration, 'inputStart');
    } else {
      this.queueReleaseForHardware(this.lifecycleGeneration);
    }
  }

  handlePresentationModeChange(mode: InputPresentationMode): void {
    if (this.disposed || !this.inputSessionActive || this.presentationMode === mode) {
      return;
    }
    this.presentationMode = mode;
    this.targetVisible = mode === InputPresentationMode.TOUCH;
    this.lifecycleGeneration += 1;
    if (this.targetVisible) {
      this.queueShow(this.lifecycleGeneration, 'presentationMode');
    } else {
      this.queueReleaseForHardware(this.lifecycleGeneration);
    }
  }

  handleInputStop(): void {
    if (this.disposed) {
      return;
    }
    this.inputSessionActive = false;
    this.targetVisible = false;
    this.lifecycleGeneration += 1;
    this.queueHide(this.lifecycleGeneration, 'inputStop');
  }

  showKeyboardPanel(): void {
    if (this.disposed || !this.inputSessionActive || this.presentationMode !== InputPresentationMode.TOUCH) {
      return;
    }
    if (!this.targetVisible) {
      this.targetVisible = true;
      this.lifecycleGeneration += 1;
    }
    this.queueShow(this.lifecycleGeneration, 'keyboardShow');
  }

  hideKeyboardPanel(): void {
    if (this.disposed) {
      return;
    }
    if (this.targetVisible) {
      this.targetVisible = false;
      this.lifecycleGeneration += 1;
    }
    this.queueHide(this.lifecycleGeneration, 'keyboardHide');
  }

  destroyPanel(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.inputSessionActive = false;
    this.targetVisible = false;
    this.lifecycleGeneration += 1;
    const generation = this.lifecycleGeneration;
    this.settingsStore.unsubscribe(this.onSettingsChanged);
    this.settingsSubscribed = false;
    this.sessionController.unsubscribe(this.onSessionStateChanged);
    this.sessionSubscribed = false;
    this.enqueue('destroy', generation, async (): Promise<void> => {
      await this.runDestroy(generation);
    });
  }

  getLifecycleState(): PanelLifecycleState {
    return this.lifecycleState;
  }

  getLifecycleGeneration(): number {
    return this.lifecycleGeneration;
  }

  getPresentationMode(): InputPresentationMode {
    return this.presentationMode;
  }

  async waitForLifecycleIdle(): Promise<void> {
    await this.lifecycleQueue;
  }

  private queueShow(generation: number, source: string): void {
    if (this.lifecycleState === PanelLifecycleState.VISIBLE &&
      generation === this.lifecycleGeneration && this.targetVisible) {
      return;
    }
    if (this.scheduledShowGeneration === generation) {
      return;
    }
    this.scheduledShowGeneration = generation;
    this.enqueue(`show:${source}`, generation, async (): Promise<void> => {
      try {
        await this.runShow(generation);
      } finally {
        if (this.scheduledShowGeneration === generation) {
          this.scheduledShowGeneration = undefined;
        }
      }
    });
  }

  private queueHide(generation: number, source: string): void {
    if ((this.lifecycleState === PanelLifecycleState.HIDDEN ||
      this.lifecycleState === PanelLifecycleState.UNINITIALIZED) && !this.panel) {
      this.lifecycleState = PanelLifecycleState.HIDDEN;
      this.sessionController.handleKeyboardPanelHidden();
      return;
    }
    if (this.scheduledHideGeneration === generation) {
      return;
    }
    this.scheduledHideGeneration = generation;
    this.enqueue(`hide:${source}`, generation, async (): Promise<void> => {
      try {
        await this.runHide(generation);
      } finally {
        if (this.scheduledHideGeneration === generation) {
          this.scheduledHideGeneration = undefined;
        }
      }
    });
  }

  private queueReleaseForHardware(generation: number): void {
    this.enqueue('hardwareReady', generation, async (): Promise<void> => {
      await this.runReleasePanel(generation, 'hardwareReady');
    });
  }

  private enqueue(operation: string, generation: number, task: () => Promise<void>): void {
    this.lifecycleQueue = this.lifecycleQueue.then(async (): Promise<void> => {
      try {
        await task();
      } catch (err) {
        LOGGER.error(
          `${operation} failed: generation=${generation}, state=${this.lifecycleState}, error=${JSON.stringify(err)}`
        );
        this.sessionController.recordError(
          ImeErrorCode.ENGINE_INTERNAL_ERROR,
          `${operation} keyboard panel failed`
        );
      }
    });
  }

  private async runShow(generation: number): Promise<void> {
    if (!this.isCurrentShow(generation)) {
      return;
    }
    try {
      await this.settingsReady;
      if (!this.isCurrentShow(generation)) {
        this.normalizeAbortedShow();
        return;
      }
      const panel = await this.ensurePanel(generation);
      if (!panel || !this.isCurrentShow(generation)) {
        this.normalizeAbortedShow();
        return;
      }

      await this.refreshSystemPanelInsets(panel, generation);
      if (!this.isCurrentShow(generation)) {
        this.normalizeAbortedShow();
        return;
      }

      if (!this.panelContentReady) {
        await panel.setUiContent(STAGE3_KEYBOARD_PAGE);
        this.panelContentReady = true;
        if (!this.isCurrentShow(generation)) {
          this.normalizeAbortedShow();
          return;
        }
      }

      await this.resizeToCurrent(panel, generation, 'show');
      if (!this.isCurrentShow(generation)) {
        this.normalizeAbortedShow();
        return;
      }

      this.lifecycleState = PanelLifecycleState.SHOWING;
      if (!this.isCurrentShow(generation)) {
        this.normalizeAbortedShow();
        return;
      }
      await panel.show();
      if (!this.isCurrentShow(generation)) {
        await this.correctStaleShow(panel, generation);
        return;
      }

      this.lifecycleState = PanelLifecycleState.VISIBLE;
      this.sessionController.handleKeyboardShow();
      LOGGER.info(`keyboard panel visible: generation=${generation}, state=${this.lifecycleState}`);
    } catch (err) {
      if (this.isCurrentShow(generation)) {
        this.lifecycleState = this.panel ? PanelLifecycleState.HIDDEN : PanelLifecycleState.UNINITIALIZED;
      }
      LOGGER.error(
        `show failed: generation=${generation}, state=${this.lifecycleState}, error=${JSON.stringify(err)}`
      );
      this.sessionController.recordError(
        ImeErrorCode.ENGINE_INTERNAL_ERROR,
        'show keyboard panel failed'
      );
    }
  }

  private async ensurePanel(generation: number): Promise<ManagedKeyboardPanel | undefined> {
    if (this.panel) {
      return this.panel;
    }
    if (!this.isCurrentShow(generation)) {
      return undefined;
    }

    this.lifecycleState = PanelLifecycleState.CREATING;
    let result: PanelCreationResult = {
      abilityReady: true,
      errorMessage: ''
    };
    const acquired = await this.ownershipCoordinator.acquire(
      SoftKeyboardPanelOwner.FIXED_KEYBOARD,
      async (): Promise<ManagedSoftKeyboardPanel | undefined> => {
        result = await this.backend.createPanel();
        return result.panel;
      },
      async (owned: ManagedSoftKeyboardPanel): Promise<void> => {
        await this.backend.destroyPanel(owned as ManagedKeyboardPanel);
      },
      (): void => this.handleOwnershipRevoked()
    );
    const panel = acquired as ManagedKeyboardPanel | undefined;
    if (!panel) {
      this.lifecycleState = PanelLifecycleState.UNINITIALIZED;
      const errorCode = result.abilityReady
        ? ImeErrorCode.ENGINE_INTERNAL_ERROR
        : ImeErrorCode.ENGINE_NOT_INITIALIZED;
      LOGGER.error(
        `create failed: generation=${generation}, state=${this.lifecycleState}, error=${result.errorMessage}`
      );
      this.sessionController.recordError(errorCode, 'create keyboard panel failed');
      return undefined;
    }
    this.panel = panel;
    this.panelContentReady = false;
    this.lastAppliedPanelSize = undefined;
    LOGGER.info(`keyboard panel created: generation=${generation}, state=${this.lifecycleState}`);
    if (!this.isCurrentShow(generation)) {
      this.normalizeAbortedShow();
      return undefined;
    }
    this.lifecycleState = PanelLifecycleState.HIDDEN;
    return panel;
  }

  private async runHide(generation: number): Promise<void> {
    if (!this.isCurrentHide(generation)) {
      return;
    }
    const panel = this.panel;
    if (!panel) {
      this.lifecycleState = PanelLifecycleState.HIDDEN;
      this.sessionController.handleKeyboardPanelHidden();
      return;
    }
    if (this.lifecycleState === PanelLifecycleState.HIDDEN) {
      this.sessionController.handleKeyboardPanelHidden();
      return;
    }

    this.lifecycleState = PanelLifecycleState.HIDING;
    try {
      await panel.hide();
      if (!this.isCurrentHide(generation)) {
        return;
      }
      this.lifecycleState = PanelLifecycleState.HIDDEN;
      this.sessionController.handleKeyboardPanelHidden();
      LOGGER.info(`keyboard panel hidden: generation=${generation}, state=${this.lifecycleState}`);
    } catch (err) {
      if (this.isCurrentHide(generation)) {
        this.lifecycleState = PanelLifecycleState.VISIBLE;
      }
      LOGGER.error(
        `hide failed: generation=${generation}, state=${this.lifecycleState}, error=${JSON.stringify(err)}`
      );
      this.sessionController.recordError(
        ImeErrorCode.ENGINE_INTERNAL_ERROR,
        'hide keyboard panel failed'
      );
    }
  }

  private async correctStaleShow(panel: ManagedKeyboardPanel, generation: number): Promise<void> {
    try {
      await panel.hide();
      if (!this.disposed) {
        this.lifecycleState = PanelLifecycleState.HIDDEN;
      }
      LOGGER.info(
        `stale show corrected: generation=${generation}, currentGeneration=${this.lifecycleGeneration}, ` +
        `state=${this.lifecycleState}`
      );
    } catch (err) {
      LOGGER.warn(
        `stale show correction failed: generation=${generation}, state=${this.lifecycleState}, ` +
        `error=${JSON.stringify(err)}`
      );
    }
  }

  private async runDestroy(generation: number): Promise<void> {
    const panel = this.panel;
    try {
      if (panel) {
        await this.ownershipCoordinator.release(
          SoftKeyboardPanelOwner.FIXED_KEYBOARD,
          panel as ManagedSoftKeyboardPanel
        );
      }
      LOGGER.info(`keyboard panel destroyed: generation=${generation}`);
    } finally {
      this.panel = undefined;
      this.panelContentReady = false;
      this.lastAppliedPanelSize = undefined;
      this.scheduledResizeGeneration = undefined;
      this.lifecycleState = PanelLifecycleState.DESTROYED;
    }
  }

  private async runReleasePanel(generation: number, source: string): Promise<void> {
    const panel = this.panel;
    if (panel) {
      await this.ownershipCoordinator.release(
        SoftKeyboardPanelOwner.FIXED_KEYBOARD,
        panel as ManagedSoftKeyboardPanel
      );
    }
    if (generation !== this.lifecycleGeneration || this.targetVisible || this.disposed) {
      return;
    }
    this.panel = undefined;
    this.panelContentReady = false;
    this.lastAppliedPanelSize = undefined;
    this.lifecycleState = PanelLifecycleState.HIDDEN;
    this.sessionController.handleKeyboardPanelHidden();
    LOGGER.info(`fixed keyboard released: source=${source}, generation=${generation}`);
  }

  private handleOwnershipRevoked(): void {
    this.panel = undefined;
    this.panelContentReady = false;
    this.lastAppliedPanelSize = undefined;
    this.lifecycleState = PanelLifecycleState.HIDDEN;
    this.sessionController.handleKeyboardPanelHidden();
  }

  private queueSettingsResize(): void {
    this.queueResize('settings');
  }

  private queueSessionResize(): void {
    this.queueResize('session');
  }

  private queueResize(source: string): void {
    if (this.disposed || !this.targetVisible || !this.panel) {
      return;
    }
    if (panelSizeEqual(this.lastAppliedPanelSize, this.currentPanelSize())) {
      return;
    }
    const generation = this.lifecycleGeneration;
    if (this.scheduledResizeGeneration === generation) {
      return;
    }
    this.scheduledResizeGeneration = generation;
    this.enqueue(`resize:${source}`, generation, async (): Promise<void> => {
      let resizeCompleted = false;
      try {
        if (!this.isCurrentShow(generation) || !this.panel) {
          return;
        }
        await this.refreshSystemPanelInsets(this.panel, generation);
        if (!this.isCurrentShow(generation) || !this.panel) {
          return;
        }
        await this.resizeToCurrent(this.panel, generation, source);
        resizeCompleted = true;
      } finally {
        if (this.scheduledResizeGeneration === generation) {
          this.scheduledResizeGeneration = undefined;
        }
        // Only coalesce changes that arrived during a successful resize. A
        // rejected platform resize leaves lastAppliedPanelSize unchanged; an
        // unconditional retry here otherwise creates an unbounded error loop.
        if (resizeCompleted && this.isCurrentShow(generation) && this.panel &&
          !panelSizeEqual(this.lastAppliedPanelSize, this.currentPanelSize())) {
          this.queueResize('coalesced');
        }
      }
    });
  }

  private async resizeToCurrent(
    panel: ManagedKeyboardPanel,
    generation: number,
    source: string
  ): Promise<void> {
    const settings = this.settingsStore.getSnapshot();
    const sessionState = this.sessionController.getState();
    const screenMetrics = sessionState.screenMetrics;
    const width = screenMetrics.widthPx;
    const height = panelHeightForMode(
      settings.keyboardHeightMode,
      screenMetrics,
      settings.keyboardProfileId === PINYIN_9_PROFILE_ID && sessionState.keyboardMode === KeyboardMode.CHINESE,
      settings.keyboardLiftLayerEnabled,
      settings.candidatePresentationMode !== CandidatePresentationMode.FLOATING
    );
    const targetSize: PanelSizePx = { widthPx: width, heightPx: height };
    if (panelSizeEqual(this.lastAppliedPanelSize, targetSize)) {
      return;
    }
    LOGGER.info(
      `panel resize requested: source=${source}, generation=${generation}, ` +
      `keyboardHeightMode=${settings.keyboardHeightMode}, ` +
      `candidateBarVisible=${settings.candidatePresentationMode !== CandidatePresentationMode.FLOATING}, ` +
      `isLandscape=${screenMetrics.isLandscape}, widthPx=${width}, heightPx=${height}, ` +
      `screenHeightPx=${screenMetrics.heightPx}, density=${screenMetrics.densityPixels}`
    );
    await panel.resize(width, height);
    if (this.isCurrentShow(generation) && this.panel === panel) {
      this.lastAppliedPanelSize = targetSize;
      LOGGER.info(
        `panel resize complete: source=${source}, generation=${generation}, widthPx=${width}, heightPx=${height}`
      );
    }
  }

  private async refreshSystemPanelInsets(panel: ManagedKeyboardPanel, generation: number): Promise<void> {
    if (!panel.getDisplayId || !panel.getSystemPanelCurrentInsets) {
      return;
    }
    try {
      const displayId = await panel.getDisplayId();
      if (!this.isCurrentShow(generation)) {
        return;
      }
      const insets = await panel.getSystemPanelCurrentInsets(displayId);
      if (!this.isCurrentShow(generation)) {
        return;
      }
      this.sessionController.setBottomSystemInsetPx(insets.bottom);
      LOGGER.info(
        `system panel insets updated: displayId=${displayId}, leftPx=${insets.left}, ` +
          `rightPx=${insets.right}, bottomPx=${insets.bottom}`
      );
    } catch (err) {
      LOGGER.warn(`system panel insets unavailable; using zero fallback: ${JSON.stringify(err)}`);
      this.sessionController.setBottomSystemInsetPx(0);
    }
  }

  private isCurrentShow(generation: number): boolean {
    return !this.disposed && this.targetVisible && generation === this.lifecycleGeneration;
  }

  private isCurrentHide(generation: number): boolean {
    return !this.disposed && !this.targetVisible && generation === this.lifecycleGeneration;
  }

  private normalizeAbortedShow(): void {
    if (!this.disposed && this.lifecycleState !== PanelLifecycleState.VISIBLE) {
      this.lifecycleState = this.panel ? PanelLifecycleState.HIDDEN : PanelLifecycleState.UNINITIALIZED;
    }
  }

  private currentPanelSize(): PanelSizePx {
    const sessionState = this.sessionController.getState();
    const settings = this.settingsStore.getSnapshot();
    return {
      widthPx: sessionState.screenMetrics.widthPx,
      heightPx: panelHeightForMode(
        settings.keyboardHeightMode,
        sessionState.screenMetrics,
        settings.keyboardProfileId === PINYIN_9_PROFILE_ID && sessionState.keyboardMode === KeyboardMode.CHINESE,
        settings.keyboardLiftLayerEnabled,
        settings.candidatePresentationMode !== CandidatePresentationMode.FLOATING
      )
    };
  }

  private subscribeToSettings(): void {
    if (!this.settingsSubscribed) {
      this.settingsStore.subscribe(this.onSettingsChanged);
      this.settingsSubscribed = true;
    }
  }

  private subscribeToSession(): void {
    if (!this.sessionSubscribed) {
      this.sessionController.subscribe(this.onSessionStateChanged);
      this.sessionSubscribed = true;
    }
  }
}

// 阶段2兼容性常量（保留用于验证脚本）
export const STAGE2_PANEL_HEIGHT = 1100;
