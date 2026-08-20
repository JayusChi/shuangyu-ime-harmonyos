import { Logger } from '../../common/logging/Logger';

const LOGGER = new Logger('ComputerStage1Probe');

export type ComputerProbePanelKind = 'CANDIDATE' | 'STATUS_BAR';

class ComputerCandidateProbeBus {
  private activePanel: ComputerProbePanelKind = 'CANDIDATE';
  private clickCount: number = 0;

  setActivePanel(kind: ComputerProbePanelKind): void {
    this.activePanel = kind;
  }

  getActivePanel(): ComputerProbePanelKind {
    return this.activePanel;
  }

  getClickCount(): number {
    return this.clickCount;
  }

  recordMouseClick(candidateIndex: number): void {
    this.clickCount += 1;
    LOGGER.info(
      `stage1 event=mouseClick panel=${this.activePanel} candidateIndex=${candidateIndex} clickCount=${this.clickCount}`
    );
  }
}

const SHARED_BUS = new ComputerCandidateProbeBus();

export function getComputerCandidateProbeBus(): ComputerCandidateProbeBus {
  return SHARED_BUS;
}
