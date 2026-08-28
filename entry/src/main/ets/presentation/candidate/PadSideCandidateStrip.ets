import { toContextualCandidateDisplayItem } from '../../domain/candidate/CandidateDisplayItem';
import {
  CandidateUiMode,
  resolveCandidateAccessibilityText
} from '../../domain/candidate/CandidateUiPolicy';
import { resolveCompositionPreeditView } from '../../domain/candidate/CompositionPreeditView';
import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import { KeyboardColorPalette, LIGHT_PALETTE } from '../keyboard/design/KeyboardPalette';

@Component
export struct PadSideCandidateStrip {
  @Prop palette: KeyboardColorPalette = LIGHT_PALETTE;
  @Prop rawInput: string = '';
  @Prop preeditText: string = '';
  @Prop cursorPreeditVisible: boolean = false;
  @Prop displaySegments: string[] = [];
  @Prop pendingCode: string = '';
  @Prop segmentBoundaries: number[] = [];
  @Prop candidates: Candidate[] = [];
  @Prop candidateUiMode: CandidateUiMode = CandidateUiMode.BROWSABLE;
  @Prop candidateFontSize: number = 14;
  @Prop highlightedIndex: number = -1;
  onCandidateClick?: (candidate: Candidate, index: number) => void;

  private preeditDisplayText(): string {
    return resolveCompositionPreeditView({
      rawInput: this.rawInput,
      preeditText: this.preeditText,
      cursorPreeditVisible: this.cursorPreeditVisible,
      displaySegments: this.displaySegments,
      pendingCode: this.pendingCode,
      segmentBoundaries: this.segmentBoundaries
    }).displayText;
  }

  build() {
    Column({ space: 6 }) {
      if (this.rawInput.length > 0 && !this.cursorPreeditVisible) {
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
            Text(toContextualCandidateDisplayItem(
              candidate,
              index,
              this.candidateUiMode,
              this.rawInput
            ).displayText)
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
              .accessibilityText(resolveCandidateAccessibilityText(
                this.candidateUiMode,
                this.rawInput,
                index,
                candidate.displayText && candidate.displayText.length > 0 ? candidate.displayText : candidate.text,
                candidate.reading
              ))
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
