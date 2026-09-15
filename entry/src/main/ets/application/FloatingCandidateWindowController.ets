import { CLIPBOARD_REVERSE_CODE, CLIPBOARD_REVERSE_LABEL } from '../domain/direct/ClipboardReverseLookup';
import { isConvenienceInput } from '../domain/keyboard/ConvenienceInput';
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
import { CandidatePresentationMode, ImeSettings } from '../domain/settings/ImeSettings';
import {
  FloatingCandidateSdkCapability,
  getSharedFloatingCandidateCapabilityProbe
} from '../infrastructure/ime/FloatingCandidateCapabilityProbe';
import {
  PhysicalKeyboardMonitor,
  PhysicalKeyboardStateProvider
} from '../infrastructure/ime/PhysicalKeyboardMonitor';
import { getSharedSettingsStore, SettingsStore } from '../state/SettingsStore';
import { InputSessionState } from '../state/InputSessionStore';
import { FloatingCandidateViewStore, getSharedFloatingCandidateViewStore } from '../state/FloatingCandidateViewStore';
import { InputSessionController } from './InputSessionController';
import { InputPresentationMode } from '../domain/display/InputPresentationMode';
import { Candidate } from '../infrastructure/native/NativeEngineTypes';
import { toContextualCandidateDisplayItem } from '../domain/candidate/CandidateDisplayItem';
import {
  CompositionPreeditPlacement,
  resolveCompositionPreeditView
} from '../domain/candidate/CompositionPreeditView';
import {
  resolveCandidateUiMode,
  resolveCollapsedCandidates,
  shouldShowCandidateExpansionAction,
  resolveVisibleCandidates
} from '../domain/candidate/CandidateUiPolicy';
import { estimateFloatingCandidateWidthVp, FLOATING_CANDIDATE_SHADOW_INSET_VP,
  floatingCandidateExpandedWidthVp, floatingCandidateCardHeightVp, resolveFloatingCandidateExpansionLayout,
  FLOATING_CANDIDATE_EXPAND_WIDTH_VP, FLOATING_CANDIDATE_ITEM_GAP_VP } from '../domain/candidate/FloatingCandidateLayout';
import { getSharedFloatingCandidateTextMeasurer } from '../infrastructure/display/FloatingCandidateTextMeasurer';
import { panelHeightForMode } from '../presentation/keyboard/design/KeyboardMetrics';
import {
  ManagedSoftKeyboardPanel,
  SoftKeyboardPanelOwner,
  SoftKeyboardPanelOwnershipCoordinator
} from './SoftKeyboardPanelOwnershipCoordinator';

const TAG = 'FloatingCandidateWindow';
const LOGGER = new Logger(TAG);
const FLOATING_CANDIDATE_PAGE = 'presentation/candidate/FloatingCandidateRoot';
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
  private updateRevision: number = 0;
  private lastPosition?: FloatingCandidatePositionPx;
  private layoutKey: string = '';
  private compositionWidthVp: number = 0;
  private readonly sessionController: InputSessionController;
  private readonly settingsStore: SettingsStore;
  private readonly backend: FloatingCandidatePanelBackend;
  private readonly capabilityProvider: FloatingCandidateCapabilityProvider;
  private readonly physicalKeyboard: PhysicalKeyboardStateProvider;
  private readonly viewStore: FloatingCandidateViewStore;
  private ownershipCoordinator: SoftKeyboardPanelOwnershipCoordinator =
    new SoftKeyboardPanelOwnershipCoordinator();
  private presentationMode: InputPresentationMode = InputPresentationMode.TOUCH;
  private readonly onStateChanged = (): void => {
    if (!this.updatingStoreVisibility) {
      this.reconcile('session');
    }
  };
  private readonly textMeasurer = getSharedFloatingCandidateTextMeasurer();
  private readonly onTextMeasurerReady = (): void => this.reconcile('font metrics');
  private readonly onSettingsChanged = (): void => this.reconcile('settings');
  private readonly onPhysicalKeyboardChanged = (_present: boolean): void => this.reconcile('physicalKeyboard');

  constructor(
    sessionController: InputSessionController = new InputSessionController(),
    settingsStore: SettingsStore = getSharedSettingsStore(),
    backend: FloatingCandidatePanelBackend = new HarmonyFloatingCandidatePanelBackend(),
    capabilityProvider: FloatingCandidateCapabilityProvider = getSharedFloatingCandidateCapabilityProbe(),
    physicalKeyboard: PhysicalKeyboardStateProvider = new PhysicalKeyboardMonitor(),
    viewStore: FloatingCandidateViewStore = getSharedFloatingCandidateViewStore()
  ) {
    this.sessionController = sessionController;
    this.settingsStore = settingsStore;
    this.backend = backend;
    this.capabilityProvider = capabilityProvider;
    this.physicalKeyboard = physicalKeyboard;
    this.viewStore = viewStore;
    this.sessionController.subscribe(this.onStateChanged);
    this.settingsStore.subscribe(this.onSettingsChanged);
    this.textMeasurer.subscribe(this.onTextMeasurerReady);
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
    this.textMeasurer.unsubscribe(this.onTextMeasurerReady);
    this.physicalKeyboard.stop();
    this.queue = this.queue.then(async (): Promise<void> => {
      this.setStoreVisible(false);
      await this.releasePanel();
    }).catch((err: Object): void => LOGGER.warn(`destroy failed: ${JSON.stringify(err)}`));
  }

  async waitForIdle(): Promise<void> {
    let pending: Promise<void>;
    do {
      pending = this.queue;
      await pending;
    } while (pending !== this.queue);
  }

  private reconcile(source: string): void {
    const revision = ++this.updateRevision;
    const state = this.sessionController.getState();
    if (!state.sessionActive || !state.editorConnected || state.rawInput.length === 0 || !this.cursorRect) {
      this.viewStore.clear();
      this.compositionWidthVp = 0;
      this.layoutKey = '';
    }
    this.queue = this.queue.then(async (): Promise<void> => {
      if (revision === this.updateRevision) { await this.applyLatest(source, revision); }
    }).catch(async (err: Object): Promise<void> => {
      if (!this.isUpdateCurrent(revision)) { return; }
      this.failedForSession = true;
      LOGGER.warn(`floating candidate fallback: source=${source}, error=${JSON.stringify(err)}`);
      await this.hidePanel();
    });
  }

  private async applyLatest(source: string, revision: number): Promise<void> {
    if (!this.shouldShowFloating()) {
      await this.hidePanel();
      return;
    }
    const state = this.sessionController.getState();
    const settings = this.settingsStore.getSnapshot();
    const theme = this.settingsStore.getEffectiveTheme();
    const generation = this.sessionController.getInputSessionGeneration();
    const nextLayoutKey = `${generation}:${state.floatingCandidateExpanded}:${settings.floatingCandidateFontSize}:` +
      `${settings.candidateDisplayCount}:${settings.schemeId}:` +
      `${state.screenMetrics.widthPx}:${state.screenMetrics.heightPx}:${state.screenMetrics.densityPixels}`;
    if (this.layoutKey !== nextLayoutKey) {
      this.viewStore.clear();
      this.layoutKey = nextLayoutKey;
      this.compositionWidthVp = 0;
    }
    const position = this.currentPosition(state, settings);
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
    if (!this.isUpdateCurrent(revision)) { return; }
    if (!this.lastPosition || Math.round(position.widthPx) !== Math.round(this.lastPosition.widthPx) ||
      Math.round(position.heightPx) !== Math.round(this.lastPosition.heightPx)) {
      await panel.resize(Math.round(position.widthPx), Math.round(position.heightPx));
      this.lastPosition = undefined;
    }
    if (!this.isUpdateCurrent(revision)) { return; }
    if (!this.lastPosition || Math.round(position.x) !== Math.round(this.lastPosition.x) ||
      Math.round(position.y) !== Math.round(this.lastPosition.y)) {
      await panel.moveTo(Math.round(position.x), Math.round(position.y));
    }
    this.lastPosition = position;
    if (!this.isUpdateCurrent(revision)) { return; }
    this.viewStore.publish({ session: state, settings, theme, generation });
    if (!this.isUpdateCurrent(revision)) { return; }
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
    if (!this.isUpdateCurrent(revision)) { return; }
    this.setStoreVisible(true);
    LOGGER.debug(`floating candidate visible: source=${source}, x=${position.x}, y=${position.y}`);
  }

  private isUpdateCurrent(revision: number): boolean {
    return !this.disposed && revision === this.updateRevision;
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
    // A composing code remains user-editable even when its current prefix has
    // no candidate. Requiring candidates here made the hardware floating
    // window disappear on three-code empty prefixes such as `jda`, which
    // looked like an early clear although the engine still owned rawInput.
    const sessionAllowsPanel = state.sessionActive && state.editorConnected && state.candidateBarVisible &&
      !state.candidatePanelExpanded &&
      (state.keyboardMode === KeyboardMode.CHINESE || isConvenienceInput(state.rawInput)) && state.rawInput.length > 0;
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
    if (state.rawInput.length > 0 && decisionSignature !== this.lastDecisionSignature) {
      this.lastDecisionSignature = decisionSignature;
      LOGGER.info(
        `presentation decision: inputMode=${this.presentationMode}, preference=${preference}, ` +
          `requested=${requestedMode}, effective=${effective}, ` +
          `sessionAllows=${sessionAllowsPanel}, formFactor=${formFactor}, physical=${physicalKeyboardPresent}`
      );
    }
    return effective === CandidatePresentationMode.FLOATING;
  }

  private currentPosition(state: InputSessionState, settings: ImeSettings): FloatingCandidatePositionPx | undefined {
    if (!this.cursorRect) {
      return undefined;
    }
    const metrics = state.screenMetrics;
    const density = metrics.densityPixels > 0 ? metrics.densityPixels : 1;
    const margin = WINDOW_MARGIN_VP * density;
    let desiredWidthVp = state.floatingCandidateExpanded ? floatingCandidateExpandedWidthVp(metrics.widthPx / density)
      : this.estimateWindowWidthVp(state, settings);
    if (!state.floatingCandidateExpanded) {
      // Do not squeeze a visible composition when candidates shorten or font
      // measurement becomes available. Reset once the panel actually hides.
      this.compositionWidthVp = Math.max(this.compositionWidthVp, desiredWidthVp);
      desiredWidthVp = this.compositionWidthVp;
    }
    const touchKeyboardInset = this.presentationMode === InputPresentationMode.TOUCH
      ? panelHeightForMode(
        settings.keyboardHeightMode,
        metrics,
        false,
        settings.keyboardLiftLayerEnabled,
        settings.candidatePresentationMode !== CandidatePresentationMode.FLOATING
      )
      : 0;
    return computeFloatingCandidatePosition({
      cursorRect: this.cursorRect,
      hostWindowRect: { left: 0, top: 0, right: metrics.widthPx, bottom: metrics.heightPx },
      candidateWindowSize: {
        widthPx: Math.min(desiredWidthVp * density, Math.max(0, metrics.widthPx - margin * 2)),
        heightPx: ((state.floatingCandidateExpanded ? resolveFloatingCandidateExpansionLayout(
          metrics.widthPx / density,
          resolveVisibleCandidates(resolveCandidateUiMode(settings.schemeId), state.rawInput, state.candidates).length,
          settings.floatingCandidateFontSize).panelHeight : floatingCandidateCardHeightVp(settings.floatingCandidateFontSize)) +
          FLOATING_CANDIDATE_SHADOW_INSET_VP * 2) * density
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
  private estimateWindowWidthVp(state: InputSessionState, settings: ImeSettings): number {
    const uiMode = resolveCandidateUiMode(settings.schemeId);
    const visible = resolveVisibleCandidates(
      uiMode,
      state.rawInput,
      state.candidates
    );
    const labels = resolveCollapsedCandidates(visible, settings.candidateDisplayCount).map((candidate: Candidate): string => {
      const sourceIndex = Math.max(0, state.candidates.indexOf(candidate));
      const item = toContextualCandidateDisplayItem(candidate, sourceIndex, uiMode, state.rawInput);
      return `${sourceIndex + 1}. ${item.displayText}`;
    });
    const preedit = resolveCompositionPreeditView({
      rawInput: state.rawInput,
      preeditText: state.preeditText,
      cursorPreeditVisible: state.cursorPreeditVisible,
      placement: CompositionPreeditPlacement.FLOATING_WINDOW,
      displaySegments: state.displaySegments,
      pendingCode: state.pendingCode,
      segmentBoundaries: state.segmentBoundaries
    });
    if (preedit.visible) {
      labels.unshift(preedit.displayText);
    }
    const fontSize = settings.floatingCandidateFontSize;
    const pageStatus = state.hasNextPage || state.hasPreviousPage || state.candidatePage > 0
      ? `第 ${state.candidatePage + 1} 页`
      : '';
    const baseWidth = estimateFloatingCandidateWidthVp({
      hardwareCandidatePaging: state.hardwareCandidatePaging,
      screenWidthVp: state.screenMetrics.widthPx / Math.max(1, state.screenMetrics.densityPixels),
      preeditLabelCount: preedit.visible ? 1 : 0,
      clipboardReverseVisible: state.rawInput === CLIPBOARD_REVERSE_CODE && state.candidates.some((candidate: Candidate): boolean =>
        candidate.source === 'functional' && candidate.text === CLIPBOARD_REVERSE_LABEL),
      candidateLabels: labels,
      candidateFontSizeVp: fontSize,
      measuredTextWidthsVp: labels.map((label: string): number =>
        this.textMeasurer.widthVp(label, fontSize, state.screenMetrics.densityPixels)),
      pageStatus
    });
    const availableWidth = state.screenMetrics.widthPx / Math.max(1, state.screenMetrics.densityPixels) - WINDOW_MARGIN_VP * 2;
    const canExpand = state.hardwareCandidatePaging !== true && shouldShowCandidateExpansionAction(uiMode, visible.length, state.rawInput,
      settings.candidateDisplayCount, state.hasNextPage, baseWidth > availableWidth);
    return baseWidth + (canExpand ? FLOATING_CANDIDATE_EXPAND_WIDTH_VP + FLOATING_CANDIDATE_ITEM_GAP_VP : 0);
  }

  private async hidePanel(): Promise<void> {
    this.viewStore.clear();
    this.compositionWidthVp = 0;
    this.layoutKey = '';
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
    this.viewStore.clear();
    this.lastPosition = undefined;
    this.compositionWidthVp = 0;
    this.layoutKey = '';
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
    this.updateRevision += 1;
    this.viewStore.clear();
    this.lastPosition = undefined;
    this.compositionWidthVp = 0;
    this.layoutKey = '';
    this.panel = undefined;
    this.panelKind = undefined;
    this.contentReady = false;
    this.visible = false;
    this.setStoreVisible(false);
  }
}
