import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import {
  candidateGridColumnsTemplate,
  CandidateExpansionLayout
} from '../../domain/candidate/CandidateExpansionPolicy';
import {
  CandidateDisplayItem,
  toContextualCandidateDisplayItem
} from '../../domain/candidate/CandidateDisplayItem';
import {
  CandidateUiMode,
  resolveCandidateAccessibilityText
} from '../../domain/candidate/CandidateUiPolicy';
import { KeyboardColorPalette, LIGHT_PALETTE } from '../keyboard/design/KeyboardPalette';
import {
  CompositionPreeditView,
  resolveCompositionPreeditView
} from '../../domain/candidate/CompositionPreeditView';

export interface CandidatePagerAccessibilitySpec {
  previous: string;
  next: string;
  back: string;
}

export const CANDIDATE_PAGER_ACCESSIBILITY: CandidatePagerAccessibilitySpec = {
  previous: '上一页候选',
  next: '下一页候选',
  back: '返回键盘'
};

@Component
export struct CandidateExpansionPanel {
  @Prop palette: KeyboardColorPalette = LIGHT_PALETTE;
  @Prop rawInput: string = '';
  @Prop preeditText: string = '';
  @Prop cursorPreeditVisible: boolean = false;
  @Prop displaySegments: string[] = [];
  @Prop pendingCode: string = '';
  @Prop segmentBoundaries: number[] = [];
  @Prop @Watch('resetGridPosition') candidates: Candidate[] = [];
  @Prop @Watch('resetGridPosition') candidatePage: number = 0;
  @Prop hasPreviousPage: boolean = false;
  @Prop hasNextPage: boolean = false;
  @Prop pageLoading: boolean = false;
  @Prop candidateFontSize: number = 14;
  @Prop candidateUiMode: CandidateUiMode = CandidateUiMode.BROWSABLE;
  @Prop highlightedIndex: number = -1;
  @Prop panelWidth: string = '100%';
  @Prop fillAvailableHeight: boolean = false;
  @Prop collapseActionVisible: boolean = false;
  @Prop collapseLabel: string = '返回键盘';
  @Prop layout: CandidateExpansionLayout = {
    columnCount: 5,
    visibleRowCount: 4,
    cellHeight: 44,
    panelHeight: 252
  };

  private readonly gridScroller: Scroller = new Scroller();
  onCandidateClick?: (candidate: Candidate, index: number) => void;
  onPreviousPage?: () => void;
  onNextPage?: () => void;
  onCollapse?: () => void;

  private resetGridPosition(): void {
    this.gridScroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private preeditView(): CompositionPreeditView {
    return resolveCompositionPreeditView({
      rawInput: this.rawInput,
      preeditText: this.preeditText,
      cursorPreeditVisible: this.cursorPreeditVisible,
      displaySegments: this.displaySegments,
      pendingCode: this.pendingCode,
      segmentBoundaries: this.segmentBoundaries
    });
  }

  private candidateDisplayItem(candidate: Candidate, index: number): CandidateDisplayItem {
    return toContextualCandidateDisplayItem(
      candidate,
      index,
      this.candidateUiMode,
      this.rawInput
    );
  }

  private candidateAccessibilityText(candidate: Candidate, index: number): string {
    return resolveCandidateAccessibilityText(
      this.candidateUiMode,
      this.rawInput,
      index,
      candidate.displayText && candidate.displayText.length > 0 ? candidate.displayText : candidate.text,
      candidate.reading
    );
  }

  @Builder
  private PreviousPageButton() {
    Button('上一页')
      .height(36)
      .layoutWeight(1)
      .fontSize(12)
      .fontColor(this.hasPreviousPage && !this.pageLoading
        ? this.palette.functionKeyText
        : this.palette.candidateReading)
      .backgroundColor(this.hasPreviousPage && !this.pageLoading
        ? this.palette.functionKeyBackground
        : this.palette.candidateBackground)
      .borderRadius(6)
      .enabled(this.hasPreviousPage && !this.pageLoading)
      .opacity(this.hasPreviousPage && !this.pageLoading ? 1 : 0.5)
      .accessibilityText(CANDIDATE_PAGER_ACCESSIBILITY.previous)
      .onClick(() => this.onPreviousPage?.())
  }

  @Builder
  private NextPageButton() {
    Button('下一页')
      .height(36)
      .layoutWeight(1)
      .fontSize(12)
      .fontColor(this.hasNextPage && !this.pageLoading
        ? this.palette.functionKeyText
        : this.palette.candidateReading)
      .backgroundColor(this.hasNextPage && !this.pageLoading
        ? this.palette.functionKeyBackground
        : this.palette.candidateBackground)
      .borderRadius(6)
      .enabled(this.hasNextPage && !this.pageLoading)
      .opacity(this.hasNextPage && !this.pageLoading ? 1 : 0.5)
      .accessibilityText(CANDIDATE_PAGER_ACCESSIBILITY.next)
      .onClick(() => this.onNextPage?.())
  }

  @Builder
  private BackToKeyboardButton() {
    Button(this.collapseLabel)
      .height(36)
      .layoutWeight(1)
      .fontSize(12)
      .fontColor(this.palette.functionKeyText)
      .backgroundColor(this.palette.functionKeyBackground)
      .borderRadius(6)
      .accessibilityText(this.collapseLabel)
      .onClick(() => this.onCollapse?.())
  }

  build() {
    Column({ space: 4 }) {
      if (this.preeditView().visible) {
        Text(this.preeditView().displayText)
          .width('100%')
          .fontSize(this.candidateFontSize)
          .fontColor(this.palette.candidateText)
          .fontWeight(FontWeight.Medium)
          .decoration({
            type: TextDecorationType.Underline,
            color: this.palette.candidateText,
            style: TextDecorationStyle.SOLID
          })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      }
      Grid(this.gridScroller) {
        ForEach(this.candidates, (candidate: Candidate, index: number) => {
          GridItem() {
            Text(this.candidateDisplayItem(candidate, index).displayText)
              .width('100%')
              .height(this.layout.cellHeight)
              .fontSize(this.candidateFontSize)
              .fontColor(this.palette.candidateText)
              .fontWeight(FontWeight.Medium)
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 6, right: 6, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(index === this.highlightedIndex
                ? this.palette.functionKeyBackground
                : this.palette.candidateBackground)
              .enabled(!this.pageLoading)
              .opacity(this.pageLoading ? 0.72 : 1)
              .accessibilityText(this.candidateAccessibilityText(candidate, index))
              .onClick(() => {
                if (!this.pageLoading) {
                  this.onCandidateClick?.(candidate, index);
                }
              })
          }
        }, (candidate: Candidate) => `${this.candidatePage}-${candidate.id}:${candidate.displayText ?? ''}`)
      }
      .columnsTemplate(candidateGridColumnsTemplate(this.layout.columnCount))
      .columnsGap(4)
      .rowsGap(4)
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      if (this.hasPreviousPage || this.hasNextPage || this.candidatePage > 0 || this.collapseActionVisible) {
        Row({ space: 8 }) {
          this.PreviousPageButton()
          Text(`第 ${this.candidatePage + 1} 页`)
            .fontSize(12)
            .fontColor(this.palette.candidateReading)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .accessibilityText(`候选第 ${this.candidatePage + 1} 页`)
          this.NextPageButton()
          if (this.collapseActionVisible) {
            this.BackToKeyboardButton()
          }
        }
        .width('100%')
        .height(44)
        .alignItems(VerticalAlign.Center)
      }
    }
    .width(this.panelWidth)
    .height(this.fillAvailableHeight ? '100%' : this.layout.panelHeight)
    .layoutWeight(this.fillAvailableHeight ? 1 : 0)
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.palette.candidateBackground)
    .border({ width: { bottom: 1 }, color: this.palette.candidateDivider })
  }
}
