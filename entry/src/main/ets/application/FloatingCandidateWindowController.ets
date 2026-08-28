import common from '@ohos.app.ability.common';
import { inputMethodEngine } from '@kit.IMEKit';
import { Logger } from '../common/logging/Logger';
import {
  computeFloatingCandidatePosition,
  CursorRectPx,
  FloatingCandidatePositionPx,
  isCursorRectUsable
} from '../domain/candidate/FloatingCandidatePosition';
import { resolveEffectivePresentationMode } from '../domain/candidate/FloatingCandidatePolicy';
import { resolveKeyboardAuxiliaryAreaPolicy } from '../domain/display/KeyboardAuxiliaryAreaPolicy';
import { KeyboardMode } from '../domain/keyboard/KeyboardAction';
import { CandidatePresentationMode } from '../domain/settings/ImeSettings';
import {
  FloatingCandidateSdkCapability,
  getSharedFloatingCandidateCapabilityProbe
} from '../infrastructure/ime/FloatingCandidateCapabilityProbe';
import {
  PhysicalKeyboardMonitor,
  PhysicalKeyboardStateProvider
} from '../infrastructure/ime/PhysicalKeyboardMonitor';
import { getSharedSettingsStore, SettingsStore } from '../state/SettingsStore';
import { InputSessionController } from './InputSessionController';
import { InputPresentationMode } from '../domain/display/InputPresentationMode';
import { Candidate } from '../infrastructure/native/NativeEngineTypes';
import { toContextualCandidateDisplayItem } from '../domain/candidate/CandidateDisplayItem';
import { resolveCompositionPreeditView } from '../domain/candidate/CompositionPreeditView';
import {
  resolveCandidateUiMode,
  resolveVisibleCandidates
} from '../domain/candidate/CandidateUiPolicy';
import { estimateFloatingCandidateWidthVp } from '../domain/candidate/FloatingCandidateLayout';
import { CandidateFontSizeMode } from '../domain/settings/ImeSettings';
import { panelHeightForMode } from '../presentation/keyboard/design/KeyboardMetrics';
import {
  ManagedSoftKeyboardPanel,
  SoftKeyboardPanelOwner,
  SoftKeyboardPanelOwnershipCoordinator
} from './SoftKeyboardPanelOwnershipCoordinator';

const TAG = 'FloatingCandidateWindow';
const LOGGER = new Logger(TAG);
const FLOATING_CANDIDATE_PAGE = 'presentation/candidate/FloatingCandidateRoot';
const WINDOW_HEIGHT_VP = 56;
const WINDOW_MARGIN_VP = 8;
const CURSOR_GAP_VP = 6;

export interface ManagedFloatingCandidatePanel {
  setUiContent(path: string): Promise<void>;
  resize(width: number, height: number): Promise<void>;
  moveTo(x: number, y: number): Promise<void>;
  show(): Promise<void>;
  hide(): Promise<void>;
}

export enum FloatingCandidatePanelKind {
  CANDIDATE = 'CANDIDATE',
  STATUS_BAR = 'STATUS_BAR'
}

export interface FloatingCandidatePanelBackend {
  bindAbility(imeAbility: inputMethodEngine.InputMethodAbility, context: common.BaseContext): void;
  createPanel(kind: FloatingCandidatePanelKind): Promise<ManagedFloatingCandidatePanel | undefined>;
  destroyPanel(panel: ManagedFloatingCandidatePanel): Promise<void>;
}

export interface FloatingCandidateCapabilityProvider {
  probe(): FloatingCandidateSdkCapability;
}

class HarmonyFloatingCandidatePanelBackend implements FloatingCandidatePanelBackend {
  private imeAbility?: inputMethodEngine.InputMethodAbility;
  private context?: common.BaseContext;

  bindAbility(imeAbility: inputMethodEngine.InputMethodAbility, context: common.BaseContext): void {
    this.imeAbility = imeAbility;
    this.context = context;
  }

  async createPanel(kind: FloatingCandidatePanelKind): Promise<ManagedFloatingCandidatePanel | undefined> {
    if (!this.imeAbility || !this.context) {
      return undefined;
    }
    try {
      if (kind === FloatingCandidatePanelKind.STATUS_BAR) {
        return this.imeAbility.createPanel(this.context, {
          type: inputMethodEngine.PanelType.STATUS_BAR
        });
      }
      return this.imeAbility.createPanel(this.context, {
        type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
        flag: inputMethodEngine.PanelFlag.FLAG_CANDIDATE
      });
    } catch (err) {
      throw new Error(`candidate panel creation failed: ${JSON.stringify(err)}`);
    }
  }

  async destroyPanel(panel: ManagedFloatingCandidatePanel): Promise<void> {
    if (this.imeAbility) {
      try {
        await this.imeAbility.destroyPanel(panel as inputMethodEngine.Panel);
      } catch (err) {
        throw new Error(`candidate panel destruction failed: ${JSON.stringify(err)}`);
      }
    }
  }
}

/** Owns cursor-following candidate panels and falls back to the fixed top bar on any failure. */
export class FloatingCandidateWindowController {
  private panel?: ManagedFloatingCandidatePanel;
  private panelKind?: FloatingCandidatePanelKind;
  private contentReady: boolean = false;
  private visible: boolean = false;
  private disposed: boolean = false;
  private failedForSession: boolean = false;
  private updatingStoreVisibility: boolean = false;
  private lastDecisionSignature: string = '';
  private cursorRect?: CursorRectPx;
  private queue: Promise<void> = Promise.resolve();
  private readonly sessionController: InputSessionController;
  private readonly settingsStore: SettingsStore;
  private readonly backend: FloatingCandidatePanelBackend;
  private readonly capabilityProvider: FloatingCandidateCapabilityProvider;
  private readonly physicalKeyboard: PhysicalKeyboardStateProvider;
  private ownershipCoordinator: SoftKeyboardPanelOwnershipCoordinator =
    new SoftKeyboardPanelOwnershipCoordinator();
  private presentationMode: InputPresentationMode = InputPresentationMode.TOUCH;
  private readonly onStateChanged = (): void => {
    if (!this.updatingStoreVisibility) {
      this.reconcile('session');
    }
  };
  private readonly onSettingsChanged = (): void => this.reconcile('settings');
  private readonly onPhysicalKeyboardChanged = (_present: boolean): void => this.reconcile('physicalKeyboard');

  constructor(
    sessionController: InputSessionController = new InputSessionController(),
    settingsStore: SettingsStore = getSharedSettingsStore(),
    backend: FloatingCandidatePanelBackend = new HarmonyFloatingCandidatePanelBackend(),
    capabilityProvider: FloatingCandidateCapabilityProvider = getSharedFloatingCandidateCapabilityProbe(),
    physicalKeyboard: PhysicalKeyboardStateProvider = new PhysicalKeyboardMonitor()
  ) {
    this.sessionController = sessionController;
    this.settingsStore = settingsStore;
    this.backend = backend;
    this.capabilityProvider = capabilityProvider;
    this.physicalKeyboard = physicalKeyboard;
    this.sessionController.subscribe(this.onStateChanged);
    this.settingsStore.subscribe(this.onSettingsChanged);
  }

  bindAbility(imeAbility: inputMethodEngine.InputMethodAbility, context: common.BaseContext): void {
    this.backend.bindAbility(imeAbility, context);
    this.disposed = false;
    this.physicalKeyboard.start(this.onPhysicalKeyboardChanged);
  }

  bindOwnershipCoordinator(coordinator: SoftKeyboardPanelOwnershipCoordinator): void {
    if (!this.panel) {
      this.ownershipCoordinator = coordinator;
    }
  }

  handleInputStart(mode: InputPresentationMode = InputPresentationMode.TOUCH): void {
    this.cursorRect = undefined;
    this.presentationMode = mode;
    this.failedForSession = false;
    this.lastDecisionSignature = '';
    this.reconcile('inputStart');
  }

  handlePresentationModeChange(mode: InputPresentationMode): void {
    if (this.presentationMode === mode) {
      return;
    }
    this.presentationMode = mode;
    this.failedForSession = false;
    this.lastDecisionSignature = '';
    this.reconcile('presentationMode');
  }

  handleInputStop(): void {
    this.cursorRect = undefined;
    this.reconcile('inputStop');
  }

  handleKeyboardShow(): void {
    this.reconcile('keyboardShow');
  }

  handleKeyboardHide(): void {
    this.reconcile('keyboardHide');
  }

  handleCursorContextChange(x: number, y: number, height: number): void {
    const next: CursorRectPx = { x, y, height };
    this.cursorRect = isCursorRectUsable(next) ? next : undefined;
    LOGGER.info(`cursor anchor ${this.cursorRect ? 'updated' : 'rejected'}: x=${x}, y=${y}, height=${height}`);
    this.reconcile('cursor');
  }

  handleConfigurationUpdate(): void {
    // The cursor coordinates are physical-screen absolute. Rotation, window
    // resize or desktop layout changes invalidate the old anchor; keeping it
    // would leave the panel at a stale position while waiting for the host.
    this.cursorRect = undefined;
    this.reconcile('configuration');
  }

  destroy(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.cursorRect = undefined;
    this.sessionController.unsubscribe(this.onStateChanged);
    this.settingsStore.unsubscribe(this.onSettingsChanged);
    this.physicalKeyboard.stop();
    this.queue = this.queue.then(async (): Promise<void> => {
      this.setStoreVisible(false);
      await this.releasePanel();
    }).catch((err: Object): void => LOGGER.warn(`destroy failed: ${JSON.stringify(err)}`));
  }

  async waitForIdle(): Promise<void> {
    await this.queue;
  }

  private reconcile(source: string): void {
    this.queue = this.queue.then(async (): Promise<void> => {
      await this.applyLatest(source);
    }).catch(async (err: Object): Promise<void> => {
      this.failedForSession = true;
      LOGGER.warn(`floating candidate fallback: source=${source}, error=${JSON.stringify(err)}`);
      await this.hidePanel();
    });
  }

  private async applyLatest(source: string): Promise<void> {
    if (!this.shouldShowFloating()) {
      await this.hidePanel();
      return;
    }
    const position = this.currentPosition();
    if (!position || position.widthPx <= 0 || position.heightPx <= 0) {
      await this.hidePanel();
      return;
    }
    const desiredKind = this.desiredPanelKind();
    if (this.panel && this.panelKind !== desiredKind) {
      await this.releasePanel();
    }
    let panel = this.panel;
    if (!panel) {
      if (desiredKind === FloatingCandidatePanelKind.CANDIDATE) {
        const acquired = await this.ownershipCoordinator.acquire(
          SoftKeyboardPanelOwner.CANDIDATE_WINDOW,
          async (): Promise<ManagedSoftKeyboardPanel | undefined> => this.backend.createPanel(desiredKind),
          async (owned: ManagedSoftKeyboardPanel): Promise<void> => {
            await this.backend.destroyPanel(owned as ManagedFloatingCandidatePanel);
          },
          (): void => this.handleOwnershipRevoked()
        );
        panel = acquired as ManagedFloatingCandidatePanel | undefined;
      } else {
        // STATUS_BAR is a different PanelType and can coexist with the fixed
        // SOFT_KEYBOARD. It must not enter the soft-keyboard ownership queue.
        panel = await this.backend.createPanel(desiredKind);
      }
      if (!panel) {
        throw new Error('candidate panel creation returned no panel');
      }
      this.panel = panel;
      this.panelKind = desiredKind;
      this.contentReady = false;
      LOGGER.info(`candidate panel created: kind=${desiredKind}`);
    }
    if (!this.contentReady) {
      await panel.setUiContent(FLOATING_CANDIDATE_PAGE);
      this.contentReady = true;
      LOGGER.info(`candidate panel content ready: page=${FLOATING_CANDIDATE_PAGE}`);
    }
    await panel.resize(Math.round(position.widthPx), Math.round(position.heightPx));
    await panel.moveTo(Math.round(position.x), Math.round(position.y));
    LOGGER.debug(
      `candidate panel positioned: x=${Math.round(position.x)}, y=${Math.round(position.y)}, ` +
        `width=${Math.round(position.widthPx)}, height=${Math.round(position.heightPx)}, ` +
        `placement=${position.placement}`
    );
    if (!this.visible) {
      await panel.show();
      this.visible = true;
      LOGGER.info('candidate panel shown');
    }
    this.setStoreVisible(true);
    LOGGER.debug(`floating candidate visible: source=${source}, x=${position.x}, y=${position.y}`);
  }

  private shouldShowFloating(): boolean {
    if (this.disposed || this.failedForSession || !this.cursorRect) {
      return false;
    }
    const state = this.sessionController.getState();
    if (this.presentationMode === InputPresentationMode.TOUCH && !state.keyboardVisible) {
      return false;
    }
    const sdk = this.capabilityProvider.probe();
    const preference = this.settingsStore.getSnapshot().candidatePresentationMode;
    // HARDWARE always needs an independent candidate panel because no fixed
    // keyboard candidate bar exists. This applies to phones as well as Pad and
    // computer form factors. The user setting controls TOUCH mode only.
    const requestedMode = this.presentationMode === InputPresentationMode.HARDWARE
      ? CandidatePresentationMode.FLOATING
      : (preference === CandidatePresentationMode.FLOATING
        ? CandidatePresentationMode.FLOATING
        : CandidatePresentationMode.BAR);
    const physicalKeyboardPresent = this.presentationMode === InputPresentationMode.HARDWARE ||
      this.physicalKeyboard.isPresent();
    const formFactor = resolveKeyboardAuxiliaryAreaPolicy(state.screenMetrics).formFactor;
    const sessionAllowsPanel = state.sessionActive && state.editorConnected && state.candidateBarVisible &&
      state.keyboardMode === KeyboardMode.CHINESE && state.rawInput.length > 0 && state.candidates.length > 0;
    const effective = resolveEffectivePresentationMode(
      requestedMode,
      {
        sdkSupportsPanel: sdk.sdkSupportsPanel,
        sdkSupportsCursorEvent: sdk.sdkSupportsCursorEvent,
        sessionAllowsPanel,
        hasReceivedCursorAnchor: this.cursorRect !== undefined,
        hasPhysicalKeyboard: physicalKeyboardPresent,
        formFactor
      }
    );
    const decisionSignature = `${this.presentationMode}|${preference}|${requestedMode}|${effective}|` +
      `${sessionAllowsPanel}|${formFactor}|${physicalKeyboardPresent}`;
    if (state.rawInput.length > 0 && state.candidates.length > 0 &&
      decisionSignature !== this.lastDecisionSignature) {
      this.lastDecisionSignature = decisionSignature;
      LOGGER.info(
        `presentation decision: inputMode=${this.presentationMode}, preference=${preference}, ` +
          `requested=${requestedMode}, effective=${effective}, ` +
          `sessionAllows=${sessionAllowsPanel}, formFactor=${formFactor}, physical=${physicalKeyboardPresent}`
      );
    }
    return effective === CandidatePresentationMode.FLOATING;
  }

  private currentPosition(): FloatingCandidatePositionPx | undefined {
    if (!this.cursorRect) {
      return undefined;
    }
    const metrics = this.sessionController.getState().screenMetrics;
    const density = metrics.densityPixels > 0 ? metrics.densityPixels : 1;
    const margin = WINDOW_MARGIN_VP * density;
    const desiredWidthVp = this.estimateWindowWidthVp();
    const settings = this.settingsStore.getSnapshot();
    const touchKeyboardInset = this.presentationMode === InputPresentationMode.TOUCH
      ? panelHeightForMode(settings.keyboardHeightMode, metrics, false, settings.keyboardLiftLayerEnabled)
      : 0;
    return computeFloatingCandidatePosition({
      cursorRect: this.cursorRect,
      hostWindowRect: { left: 0, top: 0, right: metrics.widthPx, bottom: metrics.heightPx },
      candidateWindowSize: {
        widthPx: Math.min(desiredWidthVp * density, Math.max(0, metrics.widthPx - margin * 2)),
        heightPx: WINDOW_HEIGHT_VP * density
      },
      safeInsets: {
        top: margin,
        bottom: (metrics.bottomSystemInsetPx ?? 0) + touchKeyboardInset + margin,
        left: margin,
        right: margin
      },
      preferredGapPx: CURSOR_GAP_VP * density
    });
  }

  /**
   * ArkUI does not expose candidate-root measured size before the panel exists.
   * Estimate from the same session snapshot instead, so composition/page/content
   * changes resize and reposition the panel without a second window callback.
   */
  private estimateWindowWidthVp(): number {
    const state = this.sessionController.getState();
    const settings = this.settingsStore.getSnapshot();
    const uiMode = resolveCandidateUiMode(settings.schemeId);
    const visible = resolveVisibleCandidates(
      uiMode,
      state.rawInput,
      state.candidates
    );
    const labels = visible.map((candidate: Candidate): string => {
      const sourceIndex = Math.max(0, state.candidates.indexOf(candidate));
      const item = toContextualCandidateDisplayItem(candidate, sourceIndex, uiMode, state.rawInput);
      return `${sourceIndex + 1}. ${item.displayText}`;
    });
    const preedit = resolveCompositionPreeditView({
      rawInput: state.rawInput,
      preeditText: state.preeditText,
      cursorPreeditVisible: state.cursorPreeditVisible,
      displaySegments: state.displaySegments,
      pendingCode: state.pendingCode,
      segmentBoundaries: state.segmentBoundaries
    });
    if (preedit.visible) {
      labels.unshift(preedit.displayText);
    }
    let fontSize = 14;
    if (settings.candidateFontSizeMode === CandidateFontSizeMode.SMALL) {
      fontSize = 12;
    } else if (settings.candidateFontSizeMode === CandidateFontSizeMode.LARGE) {
      fontSize = 17;
    }
    const pageStatus = state.hasNextPage || state.hasPreviousPage || state.candidatePage > 0
      ? `第 ${state.candidatePage + 1} 页`
      : '';
    return estimateFloatingCandidateWidthVp({
      candidateLabels: labels,
      candidateFontSizeVp: fontSize,
      pageStatus
    });
  }

  private async hidePanel(): Promise<void> {
    if (this.panel && this.visible) {
      await this.panel.hide();
      LOGGER.info('candidate panel hidden');
    }
    this.visible = false;
    this.setStoreVisible(false);
  }

  private desiredPanelKind(): FloatingCandidatePanelKind {
    return this.presentationMode === InputPresentationMode.TOUCH
      ? FloatingCandidatePanelKind.STATUS_BAR
      : FloatingCandidatePanelKind.CANDIDATE;
  }

  private async releasePanel(): Promise<void> {
    const panel = this.panel;
    const kind = this.panelKind;
    this.panel = undefined;
    this.panelKind = undefined;
    this.contentReady = false;
    this.visible = false;
    if (!panel) {
      return;
    }
    if (kind === FloatingCandidatePanelKind.CANDIDATE) {
      await this.ownershipCoordinator.release(
        SoftKeyboardPanelOwner.CANDIDATE_WINDOW,
        panel as ManagedSoftKeyboardPanel
      );
    } else {
      await this.backend.destroyPanel(panel);
    }
  }

  private setStoreVisible(visible: boolean): void {
    const store = this.sessionController.getState();
    if (store.floatingCandidateVisible !== visible) {
      // InputSessionController intentionally exposes state mutation only for
      // lifecycle operations; this dedicated method keeps mutual exclusion in
      // the single session store.
      this.updatingStoreVisibility = true;
      try {
        this.sessionController.setFloatingCandidateVisible(visible);
      } finally {
        this.updatingStoreVisibility = false;
      }
    }
  }

  private handleOwnershipRevoked(): void {
    this.panel = undefined;
    this.panelKind = undefined;
    this.contentReady = false;
    this.visible = false;
    this.setStoreVisible(false);
  }
}
