import { toCandidateDisplayItem } from '../../domain/candidate/CandidateDisplayItem';
import { resolveCompositionPreeditView } from '../../domain/candidate/CompositionPreeditView';
import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import { KeyboardColorPalette, LIGHT_PALETTE } from '../keyboard/design/KeyboardPalette';

@Component
export struct PadSideCandidateStrip {
  @Prop palette: KeyboardColorPalette = LIGHT_PALETTE;
  @Prop rawInput: string = '';
  @Prop preeditText: string = '';
  @Prop displaySegments: string[] = [];
  @Prop pendingCode: string = '';
  @Prop segmentBoundaries: number[] = [];
  @Prop candidates: Candidate[] = [];
  @Prop candidateFontSize: number = 14;
  @Prop highlightedIndex: number = -1;
  onCandidateClick?: (candidate: Candidate, index: number) => void;

  private preeditDisplayText(): string {
    return resolveCompositionPreeditView({
      rawInput: this.rawInput,
      preeditText: this.preeditText,
      displaySegments: this.displaySegments,
      pendingCode: this.pendingCode,
      segmentBoundaries: this.segmentBoundaries
    }).displayText;
  }

  build() {
    Column({ space: 6 }) {
      if (this.rawInput.length > 0) {
        Text(this.preeditDisplayText())
          .width('100%')
          .fontSize(15)
          .fontColor(this.palette.candidateText)
          .fontWeight(FontWeight.Medium)
          .decoration({
            type: TextDecorationType.Underline,
            color: this.palette.candidateText,
            style: TextDecorationStyle.SOLID
          })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      }
      Scroll() {
        Column({ space: 6 }) {
          ForEach(this.candidates, (candidate: Candidate, index: number) => {
            Text(toCandidateDisplayItem(candidate, index).displayText)
              .width('100%')
              .fontSize(this.candidateFontSize)
              .fontColor(this.palette.candidateText)
              .fontWeight(FontWeight.Medium)
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 8, right: 8, top: 9, bottom: 9 })
              .borderRadius(6)
              .backgroundColor(index === this.highlightedIndex
                ? this.palette.functionKeyBackground
                : this.palette.candidateBackground)
              .accessibilityText(toCandidateDisplayItem(candidate, index).accessibilityText)
              .onClick(() => this.onCandidateClick?.(candidate, index))
          }, (candidate: Candidate) => candidate.id)
        }
        .width('100%')
        .padding({ left: 6, right: 6, bottom: 6 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
    }
    .width(156)
    .height('100%')
    .backgroundColor(this.palette.candidateBackground)
    .border({ width: { left: 1 }, color: this.palette.candidateDivider })
  }
}
