import { getComputerCandidateProbeBus } from '../../infrastructure/ime/ComputerCandidateProbeBus';

@Entry
@Component
struct ComputerCandidateProbeRoot {
  @State private panelKind: string = 'CANDIDATE';

  aboutToAppear(): void {
    this.panelKind = getComputerCandidateProbeBus().getActivePanel();
  }

  private recordClick(index: number): void {
    getComputerCandidateProbeBus().recordMouseClick(index);
  }

  build() {
    Row({ space: 8 }) {
      Text(`2in1 Stage 1 · ${this.panelKind}`)
        .fontSize(13)
        .fontColor('#52606D')
        .maxLines(1)

      ForEach(['你', '好', '双羽'], (candidate: string, index: number) => {
        Text(`${index + 1} ${candidate}`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#172B4D')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor('#E9F2FF')
          .focusable(false)
          .onClick((): void => this.recordClick(index))
      }, (candidate: string) => candidate)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#7A9CC6' })
    .borderRadius(10)
  }
}
