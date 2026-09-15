import { ClipboardReversePasteButton } from './ClipboardReversePasteButton';
import { CLIPBOARD_REVERSE_CODE, CLIPBOARD_REVERSE_LABEL } from '../../domain/direct/ClipboardReverseLookup';
import { CandidateExpansionPanel } from './CandidateExpansionPanel';
import { getSharedFloatingCandidateTextMeasurer } from '../../infrastructure/display/FloatingCandidateTextMeasurer';
import { KeyboardController } from '../../application/KeyboardController';
import { toContextualCandidateDisplayItem } from '../../domain/candidate/CandidateDisplayItem';
import {
  resolveCandidateAccessibilityText,
  resolveCandidateUiMode,
  resolveVisibleCandidates,
  resolveCollapsedCandidates,
  shouldShowCandidateExpansionAction,
  resolveCandidateSourceIndex,
  CandidateUiMode
} from '../../domain/candidate/CandidateUiPolicy';
import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import { DEFAULT_FLOATING_CANDIDATE_FONT_SIZE } from '../../domain/settings/ImeSettings';
import {
  CompositionPreeditDecoration,
  CompositionPreeditPlacement,
  CompositionPreeditView,
  resolveCompositionPreeditView
} from '../../domain/candidate/CompositionPreeditView';
import {
  FloatingCandidateViewSnapshot,
  getSharedFloatingCandidateViewStore,
  isFloatingCandidateViewCurrent
} from '../../state/FloatingCandidateViewStore';
import { getSharedInputSessionStore } from '../../state/InputSessionStore';
import { KeyboardColorPalette, LIGHT_PALETTE } from '../keyboard/design/KeyboardPalette';
import { KeyboardThemeResolver } from '../keyboard/design/KeyboardThemeResolver';
import { Logger } from '../../common/logging/Logger';
import {
  floatingCandidateRevealOffset,
  estimateFloatingCandidateWidthVp,
  resolveFloatingCandidateExpansionLayout,
  FLOATING_CANDIDATE_EXPAND_WIDTH_VP,
  FLOATING_CANDIDATE_SHADOW_INSET_VP,
  FLOATING_CANDIDATE_SHADOW_RADIUS_VP,
  FLOATING_CANDIDATE_SHADOW_OFFSET_Y_VP,
  FLOATING_CANDIDATE_CARD_RADIUS_VP,
  FLOATING_CANDIDATE_HORIZONTAL_PADDING_VP,
  FLOATING_CANDIDATE_ITEM_GAP_VP,
  FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP,
  FLOATING_CANDIDATE_ITEM_VERTICAL_PADDING_VP,
  FLOATING_CANDIDATE_SELECTED_BORDER_RADIUS_VP,
  FLOATING_CANDIDATE_SELECTED_HORIZONTAL_PADDING_VP,
  FLOATING_CANDIDATE_SELECTED_VERTICAL_PADDING_VP,
  FLOATING_CANDIDATE_PAGER_WIDTH_VP
} from '../../domain/candidate/FloatingCandidateLayout';

const LOGGER = new Logger('FloatingCandidateRoot');

export const FLOATING_CANDIDATE_PREVIOUS_PAGE_ACCESSIBILITY: string = '浮动候选上一页';
export const FLOATING_CANDIDATE_NEXT_PAGE_ACCESSIBILITY: string = '浮动候选下一页';

@Entry
@Component
struct FloatingCandidateRoot {
  private readonly controller: KeyboardController = new KeyboardController();
  private readonly viewStore = getSharedFloatingCandidateViewStore();
  private presentedSnapshot?: FloatingCandidateViewSnapshot;
  private readonly themeResolver: KeyboardThemeResolver = new KeyboardThemeResolver();
  private readonly scroller: Scroller = new Scroller();
  private viewportWidth: number = 0;

  @State private expanded: boolean = false;
  @State private hardwareCandidatePaging: boolean = false;
  @State private ready: boolean = false;
  @State private candidateDisplayCount: number = 5;
  @State private screenWidthVp: number = 360;
  @State private screenDensity: number = 1;
  @State private rawInput: string = '';
  @State private preeditText: string = '';
  @State private displaySegments: string[] = [];
  @State private pendingCode: string = '';
  @State private segmentBoundaries: number[] = [];
  @State private cursorPreeditVisible: boolean = false;
  @State private candidates: Candidate[] = [];
  @State private highlightedIndex: number = -1;
  @State private candidatePage: number = 0;
  @State private hasPreviousPage: boolean = false;
  @State private hasNextPage: boolean = false;
  @State private committing: boolean = false;
  @State private paging: boolean = false;
  @State private candidateFontSize: number = DEFAULT_FLOATING_CANDIDATE_FONT_SIZE;
  @State private candidateUiMode: CandidateUiMode = CandidateUiMode.BROWSABLE;
  @State private palette: KeyboardColorPalette = LIGHT_PALETTE;

  private readonly onPresentationChanged = (): void => this.refreshPresentation();

  aboutToAppear(): void {
    this.viewStore.subscribe(this.onPresentationChanged);
    this.refreshPresentation();
    getSharedFloatingCandidateTextMeasurer().bind(this.getUIContext());
  }

  aboutToDisappear(): void {
    getSharedFloatingCandidateTextMeasurer().unbind(this.getUIContext());
    this.viewStore.unsubscribe(this.onPresentationChanged);
    this.controller.dispose();
  }

  private refreshPresentation(): void {
    const view = this.viewStore.getSnapshot();
    this.presentedSnapshot = view;
    this.ready = view !== undefined;
    if (view === undefined) { return; }
    const state = view.session;
    const settings = view.settings;
    this.candidateUiMode = resolveCandidateUiMode(settings.schemeId);
    this.palette = this.themeResolver.resolveFloatingCandidates(view.theme);
    this.candidateFontSize = settings.floatingCandidateFontSize;
    this.candidateDisplayCount = settings.candidateDisplayCount;
    const highlightMoved = this.highlightedIndex !== state.highlightedIndex;
    if (this.rawInput !== state.rawInput || this.candidatePage !== state.candidatePage) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    }
    this.hardwareCandidatePaging = state.hardwareCandidatePaging === true;
    this.expanded = !this.hardwareCandidatePaging && state.floatingCandidateExpanded;
    this.screenDensity = Math.max(1, state.screenMetrics.densityPixels);
    this.screenWidthVp = state.screenMetrics.widthPx / this.screenDensity;
    this.rawInput = state.rawInput;
    this.preeditText = state.preeditText;
    this.displaySegments = state.displaySegments;
    this.pendingCode = state.pendingCode;
    this.segmentBoundaries = state.segmentBoundaries;
    this.cursorPreeditVisible = state.cursorPreeditVisible === true;
    this.candidates = state.candidates;
    this.highlightedIndex = state.highlightedIndex;
    this.candidatePage = state.candidatePage;
    this.hasPreviousPage = state.hasPreviousPage;
    this.hasNextPage = state.hasNextPage;
    if (!this.hardwareCandidatePaging && highlightMoved && !this.expanded &&
      this.visibleCandidates().findIndex((candidate: Candidate) => this.isHighlighted(candidate)) >= this.candidateDisplayCount) {
      this.controller.setFloatingCandidateExpanded(true);
    }
  }

  private presentationIsCurrent(): boolean {
    return this.presentedSnapshot !== undefined && isFloatingCandidateViewCurrent(
      this.presentedSnapshot, this.controller.getState(), getSharedInputSessionStore().getSessionGeneration());
  }

  private async commitCandidate(index: number): Promise<void> {
    if (this.committing || index < 0 || !this.presentationIsCurrent()) {
      if (index < 0) {
        LOGGER.warn('mouse candidate commit rejected: rendered candidate is no longer in the current snapshot');
      }
      return;
    }
    this.committing = true;
    try {
      const result = await this.controller.commitCandidate(index);
      LOGGER.info(`mouse candidate commit: index=${index}, success=${result.success}`);
    } finally {
      this.committing = false;
    }
  }

  private visibleCandidates(): Candidate[] {
    return resolveVisibleCandidates(
      this.candidateUiMode,
      this.rawInput,
      this.candidates
    );
  }

  private collapsedCandidates(): Candidate[] {
    return resolveCollapsedCandidates(this.visibleCandidates(), this.candidateDisplayCount);
  }

  private canExpand(): boolean {
    if (this.hardwareCandidatePaging) { return false; }
    const labels = this.collapsedCandidates().map((candidate: Candidate): string =>
      this.candidateText(candidate, this.sourceIndex(candidate)));
    if (this.preeditView().visible) { labels.unshift(this.preeditView().displayText); }
    const width = estimateFloatingCandidateWidthVp({
      clipboardReverseVisible: this.rawInput === CLIPBOARD_REVERSE_CODE && this.candidates.some((candidate: Candidate): boolean =>
        candidate.source === 'functional' && candidate.text === CLIPBOARD_REVERSE_LABEL),
      candidateLabels: labels, candidateFontSizeVp: this.candidateFontSize, pageStatus: this.pageStatus(),
      measuredTextWidthsVp: labels.map((label: string): number =>
        getSharedFloatingCandidateTextMeasurer().widthVp(label, this.candidateFontSize, this.screenDensity))
    });
    return shouldShowCandidateExpansionAction(this.candidateUiMode, this.visibleCandidates().length,
      this.rawInput, this.candidateDisplayCount, this.hasNextPage, width > this.screenWidthVp - 16);
  }

  private candidateText(candidate: Candidate, index: number): string {
    const item = toContextualCandidateDisplayItem(
      candidate,
      index,
      this.candidateUiMode,
      this.rawInput
    );
    return `${index + 1}. ${item.displayText}`;
  }

  private sourceIndex(candidate: Candidate): number {
    return resolveCandidateSourceIndex(this.candidates, candidate);
  }

  private candidateBody(candidate: Candidate): string {
    return toContextualCandidateDisplayItem(candidate, this.sourceIndex(candidate),
      this.candidateUiMode, this.rawInput).displayText;
  }

  private isHighlighted(candidate: Candidate): boolean {
    return this.sourceIndex(candidate) === this.highlightedIndex;
  }

  private pageStatus(): string {
    if (!this.hasPreviousPage && !this.hasNextPage && this.candidatePage === 0) {
      return '';
    }
    return `第 ${this.candidatePage + 1} 页`;
  }

  private preeditView(): CompositionPreeditView {
    return resolveCompositionPreeditView({
      rawInput: this.rawInput,
      preeditText: this.preeditText,
      cursorPreeditVisible: this.cursorPreeditVisible,
      placement: CompositionPreeditPlacement.FLOATING_WINDOW,
      displaySegments: this.displaySegments,
      pendingCode: this.pendingCode,
      segmentBoundaries: this.segmentBoundaries
    });
  }

  private async navigatePage(next: boolean): Promise<void> {
    if (this.paging || !this.presentationIsCurrent() || (next ? !this.hasNextPage : !this.hasPreviousPage)) {
      return;
    }
    this.paging = true;
    try {
      const result = next
        ? await this.controller.nextFloatingCandidatePage()
        : await this.controller.previousFloatingCandidatePage();
      if (result.success) {
        this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
      }
    } finally {
      this.paging = false;
    }
  }

  @Builder
  private CandidatePager() {
    Row({ space: 2 }) {
      Button('‹')
        .width(36)
        .height(38)
        .padding(0)
        .fontSize(20)
        .fontColor(this.hasPreviousPage && !this.paging
          ? this.palette.functionKeyText
          : this.palette.candidateReading)
        .backgroundColor(this.hasPreviousPage && !this.paging
          ? this.palette.functionKeyBackground
          : this.palette.candidateBackground)
        .borderRadius(8)
        .enabled(this.hasPreviousPage && !this.paging)
        .opacity(this.hasPreviousPage && !this.paging ? 1 : 0.45)
        .accessibilityText(FLOATING_CANDIDATE_PREVIOUS_PAGE_ACCESSIBILITY)
        .onClick(() => this.navigatePage(false))
      Text(`${this.candidatePage + 1}`)
        .width(32)
        .fontSize(11)
        .fontColor(this.palette.candidateReading)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .accessibilityText(`浮动候选第 ${this.candidatePage + 1} 页`)
      Button('›')
        .width(36)
        .height(38)
        .padding(0)
        .fontSize(20)
        .fontColor(this.hasNextPage && !this.paging
          ? this.palette.functionKeyText
          : this.palette.candidateReading)
        .backgroundColor(this.hasNextPage && !this.paging
          ? this.palette.functionKeyBackground
          : this.palette.candidateBackground)
        .borderRadius(8)
        .enabled(this.hasNextPage && !this.paging)
        .opacity(this.hasNextPage && !this.paging ? 1 : 0.45)
        .accessibilityText(FLOATING_CANDIDATE_NEXT_PAGE_ACCESSIBILITY)
        .onClick(() => this.navigatePage(true))
    }
    .width(FLOATING_CANDIDATE_PAGER_WIDTH_VP)
    .flexShrink(0)
    .height('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private CandidateCard() {
    Row({ space: FLOATING_CANDIDATE_ITEM_GAP_VP }) {
      Scroll(this.scroller) {
        Row({ space: FLOATING_CANDIDATE_ITEM_GAP_VP }) {
          if (this.preeditView().visible) {
            Text(this.preeditView().displayText)
              .fontSize(this.candidateFontSize)
              .lineHeight(Math.ceil(this.candidateFontSize * 1.4))
              .fontColor(this.palette.candidateReading)
              .fontWeight(FontWeight.Medium)
              .decoration({
                type: this.preeditView().decoration === CompositionPreeditDecoration.UNDERLINE
                  ? TextDecorationType.Underline
                  : TextDecorationType.None,
                color: this.palette.candidateText,
                style: TextDecorationStyle.SOLID
              })
              .maxLines(1)
              .textAlign(TextAlign.Start)
              .flexShrink(0)
              .padding({
                left: FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP,
                right: FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP,
                top: FLOATING_CANDIDATE_ITEM_VERTICAL_PADDING_VP,
                bottom: FLOATING_CANDIDATE_ITEM_VERTICAL_PADDING_VP
              })
          }
          ForEach(this.collapsedCandidates(), (candidate: Candidate, index: number) => {
            Text() {
              Span(`${this.sourceIndex(candidate) + 1} `)
                .fontSize(Math.max(10, this.candidateFontSize * 0.72))
                .fontColor(this.palette.candidateReading)
                .fontWeight(FontWeight.Regular)
              Span(this.candidateBody(candidate))
            }
              .fontSize(this.candidateFontSize)
              .lineHeight(Math.ceil(this.candidateFontSize * 1.4))
              .fontColor(this.palette.candidateText)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textAlign(TextAlign.Start)
              .flexShrink(0)
              .padding({
                left: this.isHighlighted(candidate)
                  ? FLOATING_CANDIDATE_SELECTED_HORIZONTAL_PADDING_VP
                  : FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP,
                right: this.isHighlighted(candidate)
                  ? FLOATING_CANDIDATE_SELECTED_HORIZONTAL_PADDING_VP
                  : FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP,
                top: this.isHighlighted(candidate)
                  ? FLOATING_CANDIDATE_SELECTED_VERTICAL_PADDING_VP
                  : FLOATING_CANDIDATE_ITEM_VERTICAL_PADDING_VP,
                bottom: this.isHighlighted(candidate)
                  ? FLOATING_CANDIDATE_SELECTED_VERTICAL_PADDING_VP
                  : FLOATING_CANDIDATE_ITEM_VERTICAL_PADDING_VP
              })
              .borderRadius(this.isHighlighted(candidate)
                ? FLOATING_CANDIDATE_SELECTED_BORDER_RADIUS_VP
                : 6)
              .backgroundColor(this.isHighlighted(candidate)
                ? this.palette.functionKeyBackground
                : this.palette.candidateBackground)
              .enabled(!this.committing)
              .accessibilityText(resolveCandidateAccessibilityText(
                this.candidateUiMode,
                this.rawInput,
                this.sourceIndex(candidate),
                candidate.displayText && candidate.displayText.length > 0 ? candidate.displayText : candidate.text,
                candidate.reading
              ))
              .onAreaChange((_old: Area, area: Area): void => {
                if (this.isHighlighted(candidate)) {
                  const offset = this.scroller.currentOffset().xOffset;
                  const next = floatingCandidateRevealOffset(this.viewportWidth, offset,
                    Number(area.position.x), Number(area.width));
                  if (next !== offset) { this.scroller.scrollTo({ xOffset: next, yOffset: 0 }); }
                }
              })
              .onClick(() => this.commitCandidate(this.sourceIndex(candidate)))
          }, (candidate: Candidate) => `${candidate.id}:${candidate.displayText ?? ''}`)
        }
        .height('100%')
        .flexShrink(0)
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .height('100%')
      .align(Alignment.Start)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .onAreaChange((_old: Area, area: Area): void => { this.viewportWidth = Number(area.width); })

      if (this.rawInput === CLIPBOARD_REVERSE_CODE && this.candidates.some((candidate: Candidate): boolean =>
        candidate.source === 'functional' && candidate.text === CLIPBOARD_REVERSE_LABEL)) {
        ClipboardReversePasteButton({
          onPaste: (): void => { this.controller.refreshClipboardReverseCandidate(); }
        })
      }
      if (this.pageStatus().length > 0) {
        this.CandidatePager()
      }
      if (this.canExpand()) {
        Button('展开').width(FLOATING_CANDIDATE_EXPAND_WIDTH_VP).height(38).padding(0)
          .fontSize(12).fontColor(this.palette.functionKeyText).backgroundColor(this.palette.functionKeyBackground)
          .borderRadius(8).flexShrink(0).accessibilityText('展开浮动候选')
          .onClick(() => {
            if (this.presentationIsCurrent()) { this.controller.setFloatingCandidateExpanded(true); }
          })
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      left: FLOATING_CANDIDATE_HORIZONTAL_PADDING_VP,
      right: FLOATING_CANDIDATE_HORIZONTAL_PADDING_VP
    })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.palette.candidateBackground)
    .border({ width: 1, color: this.palette.candidateDivider })
    .borderRadius(FLOATING_CANDIDATE_CARD_RADIUS_VP)
    .shadow({ radius: this.getUIContext().vp2px(FLOATING_CANDIDATE_SHADOW_RADIUS_VP),
      color: this.palette.useDarkMedia ? '#66000000' : '#200F172A',
      offsetX: 0, offsetY: this.getUIContext().vp2px(FLOATING_CANDIDATE_SHADOW_OFFSET_Y_VP) })
  }

  build() {
    Stack() {
      if (this.ready && this.expanded) {
        Column() {
          CandidateExpansionPanel({
            palette: this.palette, candidates: this.visibleCandidates(), rawInput: this.rawInput,
            preeditText: this.preeditText, cursorPreeditVisible: this.cursorPreeditVisible,
            displaySegments: this.displaySegments, pendingCode: this.pendingCode, segmentBoundaries: this.segmentBoundaries,
            candidatePage: this.candidatePage, hasPreviousPage: this.hasPreviousPage, hasNextPage: this.hasNextPage,
            pageLoading: this.paging || this.committing, candidateFontSize: this.candidateFontSize,
            candidateUiMode: this.candidateUiMode,
            highlightedIndex: this.visibleCandidates().findIndex((candidate: Candidate) => this.isHighlighted(candidate)),
            fillAvailableHeight: true, collapseActionVisible: true, collapseLabel: '收起',
            layout: resolveFloatingCandidateExpansionLayout(this.screenWidthVp, this.visibleCandidates().length, this.candidateFontSize),
            onCandidateClick: (candidate: Candidate) => this.commitCandidate(this.sourceIndex(candidate)),
            onPreviousPage: () => this.navigatePage(false), onNextPage: () => this.navigatePage(true),
            onCollapse: () => {
              if (this.presentationIsCurrent()) { this.controller.setFloatingCandidateExpanded(false); }
            }
          })
        }.width('100%').height('100%').borderRadius(FLOATING_CANDIDATE_CARD_RADIUS_VP).clip(true)
          .shadow({ radius: this.getUIContext().vp2px(FLOATING_CANDIDATE_SHADOW_RADIUS_VP),
            color: this.palette.useDarkMedia ? '#66000000' : '#200F172A',
            offsetX: 0, offsetY: this.getUIContext().vp2px(FLOATING_CANDIDATE_SHADOW_OFFSET_Y_VP) })
      } else if (this.ready) { this.CandidateCard() }
    }
      .width('100%')
      .height('100%')
      .padding(FLOATING_CANDIDATE_SHADOW_INSET_VP)
      .backgroundColor(Color.Transparent)
  }
}
