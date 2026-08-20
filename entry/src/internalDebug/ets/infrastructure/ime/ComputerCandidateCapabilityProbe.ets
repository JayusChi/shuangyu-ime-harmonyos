import display from '@ohos.display';
import deviceInfo from '@ohos.deviceInfo';
import inputDevice from '@ohos.multimodalInput.inputDevice';
import common from '@ohos.app.ability.common';
import { inputMethodEngine } from '@kit.IMEKit';
import { Action, KeyEvent } from '@kit.InputKit';
import { Logger } from '../../common/logging/Logger';
import { isComputerCapabilityProbeTarget } from '../../domain/display/ComputerCapabilityProbePolicy';
import { getComputerCandidateProbeBus, ComputerProbePanelKind } from './ComputerCandidateProbeBus';

const LOGGER = new Logger('ComputerStage1Probe');
const PROBE_PAGE = 'presentation/candidate/ComputerCandidateProbeRoot';

interface ProbePanelSize {
  width: number;
  height: number;
}

interface ProbePanelPosition {
  x: number;
  y: number;
}

export class ComputerCandidateCapabilityProbe {
  private readonly context: common.BaseContext;
  private readonly imeAbility: inputMethodEngine.InputMethodAbility;
  private readonly keyboardDelegate: inputMethodEngine.KeyboardDelegate;
  private panel?: inputMethodEngine.Panel;
  private panelKind?: ComputerProbePanelKind;
  private generation: number = 0;
  private queue: Promise<void> = Promise.resolve();
  private lastCursorX: number = -1;
  private lastCursorY: number = -1;
  private lastCursorHeight: number = -1;
  private observedClickCount: number = 0;
  private registered: boolean = false;

  private readonly onInputStart = (
    _keyboardController: inputMethodEngine.KeyboardController,
    _inputClient: inputMethodEngine.InputClient
  ): void => {
    this.generation += 1;
    const generation = this.generation;
    LOGGER.info(
      `stage1 event=inputStart generation=${generation} fixedPanelCreateCount=0 deviceType=${deviceInfo.deviceType} ` +
        `sdkApiVersion=${deviceInfo.sdkApiVersion}`
    );
    this.logPhysicalKeyboardInventory();
    this.enqueue(async (): Promise<void> => {
      await this.destroyCurrentPanel('newInputStart');
      if (generation === this.generation) {
        await this.runCandidateThenFallback(generation);
      }
    });
  };

  private readonly onInputStop = (): void => {
    this.generation += 1;
    LOGGER.info(`stage1 event=inputStop generation=${this.generation}`);
    this.enqueue(async (): Promise<void> => this.destroyCurrentPanel('inputStop'));
  };

  private readonly onKeyboardShow = (): void => {
    LOGGER.info('stage1 event=keyboardShow fixedPanelCreateCount=0');
  };

  private readonly onKeyboardHide = (): void => {
    LOGGER.info('stage1 event=keyboardHide fixedPanelCreateCount=0');
  };

  private readonly onCursorContextChange = (x: number, y: number, height: number): void => {
    this.lastCursorX = x;
    this.lastCursorY = y;
    this.lastCursorHeight = height;
    LOGGER.info(`stage1 event=cursorContextChange x=${x} y=${y} height=${height}`);
    const panel = this.panel;
    if (panel) {
      const target = this.resolvePanelPosition();
      this.enqueue(async (): Promise<void> => {
        if (this.panel === panel) {
          await panel.moveTo(target.x, target.y);
          LOGGER.info(`stage1 event=moveTo panel=${this.panelKind} source=cursor x=${target.x} y=${target.y} result=PASS`);
        }
      });
    }
  };

  private readonly onPhysicalKeyEvent = (event: KeyEvent): boolean => {
    const clickCount = getComputerCandidateProbeBus().getClickCount();
    const focusRetained = clickCount > this.observedClickCount;
    if (focusRetained) {
      this.observedClickCount = clickCount;
    }
    LOGGER.info(
      `stage1 event=keyEvent action=${event.action === Action.DOWN ? 'DOWN' : 'UP'} keyCode=${event.key.code} ` +
        `unicodeChar=${event.unicodeChar} ctrl=${event.ctrlKey} alt=${event.altKey} logo=${event.logoKey} ` +
        `afterPanelClick=${focusRetained} result=PASS`
    );
    // This is a capability probe, not the formal composition path. Returning false
    // lets the host continue receiving text while proving that the IME still sees keys.
    return false;
  };

  constructor(context: common.BaseContext) {
    this.context = context;
    this.imeAbility = inputMethodEngine.getInputMethodAbility();
    this.keyboardDelegate = inputMethodEngine.getKeyboardDelegate();
  }

  static shouldActivate(): boolean {
    return isComputerCapabilityProbeTarget(deviceInfo.deviceType);
  }

  activate(): void {
    if (this.registered) {
      return;
    }
    this.imeAbility.on('inputStart', this.onInputStart);
    this.imeAbility.on('inputStop', this.onInputStop);
    this.imeAbility.on('keyboardShow', this.onKeyboardShow);
    this.imeAbility.on('keyboardHide', this.onKeyboardHide);
    this.keyboardDelegate.on('cursorContextChange', this.onCursorContextChange);
    this.keyboardDelegate.on('keyEvent', this.onPhysicalKeyEvent);
    this.registered = true;
    LOGGER.info(
      `stage1 event=abilityCreate mode=ISOLATED_CANDIDATE_PROBE deviceType=${deviceInfo.deviceType} ` +
        `sdkApiVersion=${deviceInfo.sdkApiVersion} fixedPanelCreateCount=0`
    );
  }

  deactivate(): void {
    if (this.registered) {
      this.imeAbility.off('inputStart', this.onInputStart);
      this.imeAbility.off('inputStop', this.onInputStop);
      this.imeAbility.off('keyboardShow', this.onKeyboardShow);
      this.imeAbility.off('keyboardHide', this.onKeyboardHide);
      this.keyboardDelegate.off('cursorContextChange', this.onCursorContextChange);
      this.keyboardDelegate.off('keyEvent', this.onPhysicalKeyEvent);
    }
    this.registered = false;
    this.generation += 1;
    this.enqueue(async (): Promise<void> => this.destroyCurrentPanel('abilityDestroy'));
  }

  async waitForIdle(): Promise<void> {
    await this.queue;
  }

  private enqueue(task: () => Promise<void>): void {
    this.queue = this.queue.then(task).catch((err: Object): void => {
      LOGGER.error(`stage1 event=unhandled result=FAIL error=${JSON.stringify(err)}`);
    });
  }

  private async runCandidateThenFallback(generation: number): Promise<void> {
    const candidatePassed = await this.tryPanel('CANDIDATE', generation);
    if (!candidatePassed && generation === this.generation) {
      LOGGER.warn('stage1 event=routeFallback from=CANDIDATE to=STATUS_BAR');
      await this.tryPanel('STATUS_BAR', generation);
    }
  }

  private async tryPanel(kind: ComputerProbePanelKind, generation: number): Promise<boolean> {
    getComputerCandidateProbeBus().setActivePanel(kind);
    try {
      const panelInfo: inputMethodEngine.PanelInfo = kind === 'CANDIDATE'
        ? {
          type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
          flag: inputMethodEngine.PanelFlag.FLAG_CANDIDATE
        }
        : { type: inputMethodEngine.PanelType.STATUS_BAR };
      LOGGER.info(`stage1 event=createPanel panel=${kind} fixedPanelCreateCount=0`);
      const panel = await this.imeAbility.createPanel(this.context, panelInfo);
      if (generation !== this.generation) {
        await this.imeAbility.destroyPanel(panel);
        return false;
      }
      this.panel = panel;
      this.panelKind = kind;
      LOGGER.info(`stage1 event=createPanel panel=${kind} result=PASS`);

      await panel.setUiContent(PROBE_PAGE);
      LOGGER.info(`stage1 event=setUiContent panel=${kind} result=PASS path=${PROBE_PAGE}`);

      const size = this.resolvePanelSize();
      await panel.resize(size.width, size.height);
      LOGGER.info(`stage1 event=resize panel=${kind} width=${size.width} height=${size.height} result=PASS`);

      const position = this.resolvePanelPosition();
      await panel.moveTo(position.x, position.y);
      LOGGER.info(`stage1 event=moveTo panel=${kind} source=initial x=${position.x} y=${position.y} result=PASS`);

      await panel.show();
      LOGGER.info(`stage1 event=show panel=${kind} pass=1 result=PASS`);
      await panel.hide();
      LOGGER.info(`stage1 event=hide panel=${kind} result=PASS`);
      await panel.show();
      LOGGER.info(`stage1 event=show panel=${kind} pass=2 result=PASS awaitingMouseClick=true`);
      return true;
    } catch (err) {
      LOGGER.warn(`stage1 event=panelLifecycle panel=${kind} result=FAIL error=${JSON.stringify(err)}`);
      await this.destroyCurrentPanel(`${kind}Failure`);
      return false;
    }
  }

  private async destroyCurrentPanel(source: string): Promise<void> {
    const panel = this.panel;
    const kind = this.panelKind;
    this.panel = undefined;
    this.panelKind = undefined;
    if (!panel) {
      return;
    }
    try {
      await this.imeAbility.destroyPanel(panel);
      LOGGER.info(`stage1 event=destroyPanel panel=${kind} source=${source} result=PASS`);
    } catch (err) {
      LOGGER.warn(
        `stage1 event=destroyPanel panel=${kind} source=${source} result=FAIL error=${JSON.stringify(err)}`
      );
    }
  }

  private resolvePanelSize(): ProbePanelSize {
    const displayInfo = display.getDefaultDisplaySync();
    const density = displayInfo.densityPixels > 0 ? displayInfo.densityPixels : 1;
    return {
      width: Math.round(Math.min(520 * density, displayInfo.width - 48 * density)),
      height: Math.round(64 * density)
    };
  }

  private resolvePanelPosition(): ProbePanelPosition {
    const displayInfo = display.getDefaultDisplaySync();
    const size = this.resolvePanelSize();
    const density = displayInfo.densityPixels > 0 ? displayInfo.densityPixels : 1;
    const margin = Math.round(12 * density);
    let x = this.lastCursorX >= 0 ? Math.round(this.lastCursorX) : margin;
    let y = this.lastCursorY >= 0
      ? Math.round(this.lastCursorY + Math.max(0, this.lastCursorHeight) + 6 * density)
      : Math.round(displayInfo.height / 3);
    x = Math.max(margin, Math.min(x, displayInfo.width - size.width - margin));
    y = Math.max(margin, Math.min(y, displayInfo.height - size.height - margin));
    return { x, y };
  }

  private logPhysicalKeyboardInventory(): void {
    inputDevice.getDeviceList().then(async (deviceIds: number[]): Promise<void> => {
      let alphabeticCount = 0;
      const details: string[] = [];
      for (let index = 0; index < deviceIds.length; index += 1) {
        const deviceId = deviceIds[index];
        try {
          const type = await inputDevice.getKeyboardType(deviceId);
          if (type === inputDevice.KeyboardType.ALPHABETIC_KEYBOARD) {
            alphabeticCount += 1;
          }
          details.push(`${deviceId}:${type}`);
        } catch (err) {
          details.push(`${deviceId}:ERROR`);
        }
      }
      LOGGER.info(
        `stage1 event=physicalKeyboardInventory deviceCount=${deviceIds.length} ` +
          `alphabeticCount=${alphabeticCount} devices=${details.join(',')}`
      );
    }).catch((err: Object): void => {
      LOGGER.warn(`stage1 event=physicalKeyboardInventory result=FAIL error=${JSON.stringify(err)}`);
    });
  }
}
