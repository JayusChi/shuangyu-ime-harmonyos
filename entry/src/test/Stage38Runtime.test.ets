import { describe, expect, it } from '@ohos/hypium';
import common from '@ohos.app.ability.common';
import { inputMethodEngine } from '@kit.IMEKit';
import {
  FloatingCandidateCapabilityProvider,
  FloatingCandidatePanelBackend,
  FloatingCandidatePanelKind,
  FloatingCandidateWindowController,
  ManagedFloatingCandidatePanel
} from '../main/ets/application/FloatingCandidateWindowController';
import { InputSessionController } from '../main/ets/application/InputSessionController';
import { ImeErrorCode } from '../main/ets/common/error/ImeError';
import { createUnknownEditorContext } from '../main/ets/domain/editor/EditorContext';
import {
  CandidatePresentationMode,
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  XIAOHE_YINXING_SCHEME_ID
} from '../main/ets/domain/settings/ImeSettings';
import { FloatingCandidateSdkCapability } from '../main/ets/infrastructure/ime/FloatingCandidateCapabilityProbe';
import {
  PhysicalKeyboardListener,
  PhysicalKeyboardStateProvider
} from '../main/ets/infrastructure/ime/PhysicalKeyboardMonitor';
import { Candidate, CompositionResult } from '../main/ets/infrastructure/native/NativeEngineTypes';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';
import { SettingsStore } from '../main/ets/state/SettingsStore';
import { InputPresentationMode } from '../main/ets/domain/display/InputPresentationMode';
import { createScreenMetrics } from '../main/ets/domain/display/ScreenMetrics';
import { FloatingCandidateViewStore, isFloatingCandidateViewCurrent } from '../main/ets/state/FloatingCandidateViewStore';

class FakeFloatingPanel implements ManagedFloatingCandidatePanel {
  contentPath: string = '';
  resizeCount: number = 0;
  moveCount: number = 0;
  showCount: number = 0;
  hideCount: number = 0;
  lastX: number = -1;
  lastY: number = -1;
  lastWidth: number = -1;
  lastHeight: number = -1;
  failShow: boolean = false;
  private resizeGate?: Promise<void>;
  private resizeStarted?: () => void;
  private releaseResize?: () => void;

  holdNextResize(): Promise<void> {
    this.resizeGate = new Promise<void>((resolve) => { this.releaseResize = resolve; });
    return new Promise<void>((resolve) => { this.resizeStarted = resolve; });
  }

  resumeResize(): void {
    this.releaseResize?.();
    this.releaseResize = undefined;
  }

  async setUiContent(path: string): Promise<void> {
    this.contentPath = path;
  }

  async resize(width: number, height: number): Promise<void> {
    this.resizeCount += 1;
    const gate = this.resizeGate;
    this.resizeGate = undefined;
    this.resizeStarted?.();
    this.resizeStarted = undefined;
    if (gate) { await gate; }
    this.lastWidth = width;
    this.lastHeight = height;
  }

  async moveTo(x: number, y: number): Promise<void> {
    this.moveCount += 1;
    this.lastX = x;
    this.lastY = y;
  }

  async show(): Promise<void> {
    this.showCount += 1;
    if (this.failShow) {
      throw new Error('expected show failure');
    }
  }

  async hide(): Promise<void> {
    this.hideCount += 1;
  }
}

class FakeFloatingBackend implements FloatingCandidatePanelBackend {
  readonly panel: FakeFloatingPanel = new FakeFloatingPanel();
  createCount: number = 0;
  destroyCount: number = 0;
  createdKinds: FloatingCandidatePanelKind[] = [];

  bindAbility(_imeAbility: inputMethodEngine.InputMethodAbility, _context: common.BaseContext): void {
  }

  async createPanel(kind: FloatingCandidatePanelKind): Promise<ManagedFloatingCandidatePanel | undefined> {
    this.createCount += 1;
    this.createdKinds.push(kind);
    return this.panel;
  }

  async destroyPanel(_panel: ManagedFloatingCandidatePanel): Promise<void> {
    this.destroyCount += 1;
  }
}

class SupportedCapability implements FloatingCandidateCapabilityProvider {
  probe(): FloatingCandidateSdkCapability {
    return {
      sdkApiLevel: 24,
      sdkSupportsPanel: true,
      sdkSupportsCursorEvent: true
    };
  }
}

class FakePhysicalKeyboard implements PhysicalKeyboardStateProvider {
  present: boolean = true;
  private listener?: PhysicalKeyboardListener;

  start(listener: PhysicalKeyboardListener): void {
    this.listener = listener;
  }

  stop(): void {
    this.listener = undefined;
  }

  isPresent(): boolean {
    return this.present;
  }
}

function composition(): CompositionResult {
  const candidates: Candidate[] = [
    { id: '1', text: '你', reading: 'ni', source: 'runtime-test' },
    { id: '2', text: '尼', reading: 'ni', source: 'runtime-test' }
  ];
  return {
    success: true,
    errorCode: ImeErrorCode.SUCCESS,
    errorMessage: '',
    rawInput: 'ni',
    preeditText: 'ni',
    parsedSyllables: ['ni'],
    pendingCode: '',
    parserState: 'complete',
    candidates,
    highlightedIndex: 0,
    hasNextPage: false,
    hasPreviousPage: false,
    candidatePage: 0,
    commitText: '',
    action: null,
    compositionFinished: false
  };
}

interface RuntimeFixture {
  controller: FloatingCandidateWindowController;
  store: InputSessionStore;
  settings: SettingsStore;
  backend: FakeFloatingBackend;
  viewStore: FloatingCandidateViewStore;
}

function createFixture(phone: boolean = false, mode: InputPresentationMode = InputPresentationMode.HARDWARE): RuntimeFixture {
  const store = new InputSessionStore();
  const session = new InputSessionController(store);
  const settings = new SettingsStore();
  const configured = copyImeSettings(DEFAULT_IME_SETTINGS);
  configured.candidatePresentationMode = mode === InputPresentationMode.TOUCH
    ? CandidatePresentationMode.FLOATING : CandidatePresentationMode.AUTO;
  settings.replace(configured);
  const backend = new FakeFloatingBackend();
  const viewStore = new FloatingCandidateViewStore();
  const controller = new FloatingCandidateWindowController(
    session,
    settings,
    backend,
    new SupportedCapability(),
    new FakePhysicalKeyboard(),
    viewStore
  );
  controller.handleInputStart(mode);
  store.markSessionStarted();
  store.applyEditorContext(createUnknownEditorContext());
  if (mode === InputPresentationMode.TOUCH) { store.markKeyboardVisible(); }
  store.setScreenMetrics(phone ? createScreenMetrics({
    widthPx: 1080,
    heightPx: 2340,
    densityPixels: 3
  }) : createScreenMetrics({
    widthPx: 3120,
    heightPx: 2080,
    densityPixels: 2
  }));
  store.updateComposition(composition());
  controller.handleCursorContextChange(120, 400, 40);
  return { controller, store, settings, backend, viewStore };
}

function wideComposition(rawInput: string): CompositionResult {
  const updated = composition();
  updated.rawInput = rawInput;
  updated.preeditText = rawInput;
  updated.candidates = [
    { id: '1', text: '可以看到完整候选文字', reading: rawInput, source: 'runtime-test' },
    { id: '2', text: '快速打字保持窗口稳定', reading: rawInput, source: 'runtime-test' }
  ];
  return updated;
}

async function verifySynchronizedCandidateResize(mode: InputPresentationMode): Promise<void> {
  const fixture = createFixture(false, mode);
  await fixture.controller.waitForIdle();
  const initialWidth = fixture.backend.panel.lastWidth;
  const initialHeight = fixture.backend.panel.lastHeight;
  const published: string[] = [];
  fixture.viewStore.subscribe(() => {
    const view = fixture.viewStore.getSnapshot();
    if (view) { published.push(view.session.rawInput); }
  });
  const resizing = fixture.backend.panel.holdNextResize();
  fixture.store.updateComposition(wideComposition('k'));
  await resizing;
  expect(fixture.backend.panel.lastWidth).assertEqual(initialWidth);
  expect(fixture.viewStore.getSnapshot()?.session.rawInput).assertEqual('ni');
  fixture.store.updateComposition(wideComposition('kn'));
  fixture.store.updateComposition(wideComposition('kni'));
  fixture.backend.panel.resumeResize();
  await fixture.controller.waitForIdle();
  expect(published.join(',')).assertEqual('kni');
  expect(fixture.viewStore.getSnapshot()?.session.rawInput).assertEqual('kni');
  expect(fixture.backend.panel.lastWidth > initialWidth).assertTrue();
  expect(fixture.backend.panel.lastHeight).assertEqual(initialHeight);
  const wideWidth = fixture.backend.panel.lastWidth;
  const resizeCount = fixture.backend.panel.resizeCount;
  const short = composition();
  short.highlightedIndex = 1;
  fixture.store.updateComposition(short);
  fixture.controller.handleCursorContextChange(140, 410, 40);
  await fixture.controller.waitForIdle();
  expect(fixture.viewStore.getSnapshot()?.session.highlightedIndex).assertEqual(1);
  expect(fixture.backend.panel.lastWidth).assertEqual(wideWidth);
  expect(fixture.backend.panel.lastHeight).assertEqual(initialHeight);
  expect(fixture.backend.panel.resizeCount).assertEqual(resizeCount);
  fixture.controller.destroy();
  await fixture.controller.waitForIdle();
}

export default function stage38RuntimeTest() {
  describe('computer remediation stage 4 floating candidate runtime', () => {
    it('waits for geometry and drops obsolete content during rapid HARDWARE typing', 0, async () => {
      await verifySynchronizedCandidateResize(InputPresentationMode.HARDWARE);
    });

    it('waits for geometry and keeps dimensions stable during rapid TOUCH typing', 0, async () => {
      await verifySynchronizedCandidateResize(InputPresentationMode.TOUCH);
    });

    it('clears a pending presentation immediately and restores compact width for the next composition', 0, async () => {
      const fixture = createFixture();
      await fixture.controller.waitForIdle();
      const initialWidth = fixture.backend.panel.lastWidth;
      const resizing = fixture.backend.panel.holdNextResize();
      fixture.store.updateComposition(wideComposition('kn'));
      await resizing;
      fixture.store.clearComposition();
      expect(fixture.viewStore.getSnapshot() === undefined).assertTrue();
      fixture.backend.panel.resumeResize();
      await fixture.controller.waitForIdle();
      expect(fixture.viewStore.getSnapshot() === undefined).assertTrue();
      expect(fixture.backend.panel.hideCount).assertEqual(1);
      fixture.store.updateComposition(composition());
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.lastWidth).assertEqual(initialWidth);
      expect(fixture.viewStore.getSnapshot()?.session.rawInput).assertEqual('ni');
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('applies larger fonts only after the panel has enough line height', 0, async () => {
      const fixture = createFixture();
      await fixture.controller.waitForIdle();
      const initialHeight = fixture.backend.panel.lastHeight;
      const resizing = fixture.backend.panel.holdNextResize();
      const settings = copyImeSettings(fixture.settings.getSnapshot());
      settings.floatingCandidateFontSize = 24;
      fixture.settings.replace(settings);
      await resizing;
      expect(fixture.viewStore.getSnapshot() === undefined).assertTrue();
      fixture.backend.panel.resumeResize();
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.lastHeight > initialHeight).assertTrue();
      expect(fixture.viewStore.getSnapshot()?.settings.floatingCandidateFontSize).assertEqual(24);
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('does not let an older displayed candidate commit a newer item or a new session', 0, async () => {
      const fixture = createFixture();
      await fixture.controller.waitForIdle();
      const view = fixture.viewStore.getSnapshot();
      if (!view) { throw new Error('expected a published view'); }
      expect(isFloatingCandidateViewCurrent(view, fixture.store.getSnapshot(), fixture.store.getSessionGeneration()))
        .assertTrue();
      const replacement = composition();
      replacement.candidates[0].text = '拟';
      fixture.store.updateComposition(replacement);
      expect(isFloatingCandidateViewCurrent(view, fixture.store.getSnapshot(), fixture.store.getSessionGeneration()))
        .assertFalse();
      fixture.store.updateComposition(composition());
      fixture.store.markSessionStarted();
      expect(isFloatingCandidateViewCurrent(view, fixture.store.getSnapshot(), fixture.store.getSessionGeneration()))
        .assertFalse();
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('creates, positions and shows the candidate panel in HARDWARE mode', 0, async () => {
      const fixture = createFixture();
      await fixture.controller.waitForIdle();
      expect(fixture.backend.createCount).assertEqual(1);
      expect(fixture.backend.createdKinds[0]).assertEqual(FloatingCandidatePanelKind.CANDIDATE);
      expect(fixture.backend.panel.contentPath).assertEqual('presentation/candidate/FloatingCandidateRoot');
      expect(fixture.backend.panel.resizeCount > 0).assertTrue();
      expect(fixture.backend.panel.moveCount > 0).assertTrue();
      expect(fixture.backend.panel.showCount).assertEqual(1);
      expect(fixture.backend.panel.lastX >= 0).assertTrue();
      expect(fixture.backend.panel.lastY > 400).assertTrue();
      expect(fixture.store.getSnapshot().floatingCandidateVisible).assertTrue();
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
      expect(fixture.backend.destroyCount).assertEqual(1);
    });

    it('shows the HARDWARE candidate panel on phone form factors', 0, async () => {
      const fixture = createFixture(true);
      await fixture.controller.waitForIdle();
      expect(fixture.backend.createCount).assertEqual(1);
      expect(fixture.backend.createdKinds[0]).assertEqual(FloatingCandidatePanelKind.CANDIDATE);
      expect(fixture.backend.panel.showCount).assertEqual(1);
      expect(fixture.store.getSnapshot().floatingCandidateVisible).assertTrue();
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('keeps a candidate-less three-code composition visible for hardware editing', 0, async () => {
      const fixture = createFixture();
      await fixture.controller.waitForIdle();
      const emptyPrefix = composition();
      emptyPrefix.rawInput = 'jda';
      emptyPrefix.preeditText = 'jda';
      emptyPrefix.parserState = 'invalid';
      emptyPrefix.candidates = [];
      emptyPrefix.highlightedIndex = -1;

      fixture.store.updateComposition(emptyPrefix);
      await fixture.controller.waitForIdle();

      expect(fixture.backend.panel.hideCount).assertEqual(0);
      expect(fixture.store.getSnapshot().rawInput).assertEqual('jda');
      expect(fixture.store.getSnapshot().floatingCandidateVisible).assertTrue();
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('hides immediately when composition is cleared', 0, async () => {
      const fixture = createFixture();
      await fixture.controller.waitForIdle();
      fixture.store.clearComposition();
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.hideCount).assertEqual(1);
      expect(fixture.store.getSnapshot().floatingCandidateVisible).assertFalse();
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('falls back safely for the rest of the session after panel show fails', 0, async () => {
      const fixture = createFixture();
      fixture.backend.panel.failShow = true;
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.showCount).assertEqual(1);
      expect(fixture.store.getSnapshot().floatingCandidateVisible).assertFalse();
      fixture.controller.handleCursorContextChange(140, 420, 40);
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.showCount).assertEqual(1);
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('keeps the formal HARDWARE candidate route active across legacy placement settings', 0, async () => {
      const fixture = createFixture();
      await fixture.controller.waitForIdle();
      const configured = copyImeSettings(DEFAULT_IME_SETTINGS);
      configured.candidatePresentationMode = CandidatePresentationMode.BAR;
      fixture.settings.replace(configured);
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.hideCount).assertEqual(0);
      expect(fixture.store.getSnapshot().floatingCandidateVisible).assertTrue();
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('rejects an invalid anchor instead of reusing its last position', 0, async () => {
      const fixture = createFixture();
      await fixture.controller.waitForIdle();
      const lastX = fixture.backend.panel.lastX;
      const lastY = fixture.backend.panel.lastY;
      fixture.controller.handleCursorContextChange(Number.NaN, 420, 40);
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.hideCount).assertEqual(1);
      expect(fixture.backend.panel.lastX).assertEqual(lastX);
      expect(fixture.backend.panel.lastY).assertEqual(lastY);
      expect(fixture.store.getSnapshot().floatingCandidateVisible).assertFalse();
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('invalidates the anchor on configuration change until the host sends a new one', 0, async () => {
      const fixture = createFixture();
      await fixture.controller.waitForIdle();
      fixture.controller.handleConfigurationUpdate();
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.hideCount).assertEqual(1);
      expect(fixture.store.getSnapshot().floatingCandidateVisible).assertFalse();
      fixture.controller.handleCursorContextChange(200, 500, 36);
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.showCount).assertEqual(2);
      expect(fixture.store.getSnapshot().floatingCandidateVisible).assertTrue();
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('shares the collapsed count with floating panel sizing and expands without opening the keyboard', 0, async () => {
      const fixture = createFixture();
      const updated = composition();
      updated.candidates = [];
      for (let index = 0; index < 8; index += 1) {
        updated.candidates.push({ id: 'limit-' + index, text: '词' + index, reading: 'ni', source: 'runtime-test' });
      }
      fixture.store.updateComposition(updated);
      await fixture.controller.waitForIdle();
      const initialWidth = fixture.backend.panel.lastWidth;
      const initialHeight = fixture.backend.panel.lastHeight;
      const settings = copyImeSettings(fixture.settings.getSnapshot());
      settings.candidateDisplayCount = 2;
      fixture.settings.replace(settings);
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.lastWidth < initialWidth).assertTrue();
      const keyboardVisible = fixture.store.getSnapshot().keyboardVisible;
      expect(fixture.store.setFloatingCandidateExpanded(true)).assertTrue();
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.lastHeight > initialHeight).assertTrue();
      expect(fixture.store.getSnapshot().keyboardVisible).assertEqual(keyboardVisible);
      fixture.store.setFloatingCandidateExpanded(false);
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.lastHeight).assertEqual(initialHeight);
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('resizes and repositions when candidate content grows', 0, async () => {
      const fixture = createFixture();
      await fixture.controller.waitForIdle();
      const initialWidth = fixture.backend.panel.lastWidth;
      const updated = composition();
      updated.candidates = [
        { id: '1', text: '超长候选词一', reading: 'ni', source: 'runtime-test' },
        { id: '2', text: '超长候选词二', reading: 'ni', source: 'runtime-test' },
        { id: '3', text: '超长候选词三', reading: 'ni', source: 'runtime-test' },
        { id: '4', text: '超长候选词四', reading: 'ni', source: 'runtime-test' }
      ];
      fixture.store.updateComposition(updated);
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.lastWidth > initialWidth).assertTrue();
      expect(fixture.backend.panel.resizeCount > 1).assertTrue();
      expect(fixture.backend.panel.moveCount > 1).assertTrue();
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('includes precise continuation hints in the floating window width', 0, async () => {
      const fixture = createFixture();
      const preciseSettings = copyImeSettings(DEFAULT_IME_SETTINGS);
      preciseSettings.candidatePresentationMode = CandidatePresentationMode.AUTO;
      preciseSettings.schemeId = XIAOHE_YINXING_SCHEME_ID;
      fixture.settings.replace(preciseSettings);

      const exact = composition();
      exact.rawInput = 'nam';
      exact.preeditText = 'nam';
      exact.candidates = [
        { id: 'name', text: '那么', reading: 'nam', source: 'runtime-test' }
      ];
      fixture.store.updateComposition(exact);
      await fixture.controller.waitForIdle();
      const exactWidth = fixture.backend.panel.lastWidth;

      const hint = composition();
      hint.rawInput = 'nam';
      hint.preeditText = 'nam';
      hint.candidates = [
        { id: 'name', text: '那么', reading: 'name', source: 'runtime-test' }
      ];
      fixture.store.updateComposition(hint);
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.lastWidth > exactWidth).assertTrue();
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('does not create a candidate panel in TOUCH mode', 0, async () => {
      const fixture = createFixture();
      await fixture.controller.waitForIdle();
      fixture.controller.handleInputStop();
      await fixture.controller.waitForIdle();
      fixture.controller.handleInputStart(InputPresentationMode.TOUCH);
      fixture.store.markSessionStarted();
      fixture.store.applyEditorContext(createUnknownEditorContext());
      fixture.store.updateComposition(composition());
      fixture.controller.handleCursorContextChange(120, 400, 40);
      await fixture.controller.waitForIdle();
      expect(fixture.backend.panel.showCount).assertEqual(1);
      expect(fixture.store.getSnapshot().floatingCandidateVisible).assertFalse();
      fixture.controller.destroy();
      await fixture.controller.waitForIdle();
    });

    it('uses a coexisting STATUS_BAR panel for explicit TOUCH floating mode', 0, async () => {
      const store = new InputSessionStore();
      const session = new InputSessionController(store);
      const settings = new SettingsStore();
      const configured = copyImeSettings(DEFAULT_IME_SETTINGS);
      configured.candidatePresentationMode = CandidatePresentationMode.FLOATING;
      settings.replace(configured);
      const backend = new FakeFloatingBackend();
      const controller = new FloatingCandidateWindowController(
        session,
        settings,
        backend,
        new SupportedCapability(),
        new FakePhysicalKeyboard()
      );
      controller.handleInputStart(InputPresentationMode.TOUCH);
      store.markSessionStarted();
      store.applyEditorContext(createUnknownEditorContext());
      store.markKeyboardVisible();
      store.setScreenMetrics(createScreenMetrics({
        widthPx: 1320,
        heightPx: 2856,
        densityPixels: 3
      }));
      const touchComposition = composition();
      touchComposition.candidates.push({
        id: '3',
        text: '泥',
        reading: 'ni',
        source: 'runtime-test'
      });
      store.updateComposition(touchComposition);
      controller.handleCursorContextChange(120, 400, 40);
      await controller.waitForIdle();
      expect(backend.createCount).assertEqual(1);
      expect(backend.createdKinds[0]).assertEqual(FloatingCandidatePanelKind.STATUS_BAR);
      expect(backend.panel.showCount).assertEqual(1);
      expect(store.getSnapshot().floatingCandidateVisible).assertTrue();

      expect(store.setCandidatePanelExpanded(true)).assertTrue();
      await controller.waitForIdle();
      expect(backend.panel.hideCount).assertEqual(1);
      expect(store.getSnapshot().floatingCandidateVisible).assertFalse();

      store.setCandidatePanelExpanded(false);
      await controller.waitForIdle();
      expect(backend.panel.showCount).assertEqual(2);
      expect(store.getSnapshot().floatingCandidateVisible).assertTrue();

      const barSettings = copyImeSettings(configured);
      barSettings.candidatePresentationMode = CandidatePresentationMode.BAR;
      settings.replace(barSettings);
      await controller.waitForIdle();
      expect(backend.panel.hideCount).assertEqual(2);
      expect(store.getSnapshot().floatingCandidateVisible).assertFalse();
      controller.destroy();
      await controller.waitForIdle();
      expect(backend.destroyCount).assertEqual(1);
    });
  });
}
