import { KeyboardController } from '../../application/KeyboardController';
import { toContextualCandidateDisplayItem } from '../../domain/candidate/CandidateDisplayItem';
import {
  resolveCandidateAccessibilityText,
  resolveCandidateUiMode,
  resolveVisibleCandidates,
  resolveCandidateSourceIndex,
  CandidateUiMode
} from '../../domain/candidate/CandidateUiPolicy';
import { CandidateFontSizeMode } from '../../domain/settings/ImeSettings';
import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import {
  CompositionPreeditDecoration,
  CompositionPreeditPlacement,
  CompositionPreeditView,
  resolveCompositionPreeditView
} from '../../domain/candidate/CompositionPreeditView';
import { getSharedSettingsStore, SettingsStore } from '../../state/SettingsStore';
import { KeyboardColorPalette, LIGHT_PALETTE } from '../keyboard/design/KeyboardPalette';
import { KeyboardThemeResolver } from '../keyboard/design/KeyboardThemeResolver';
import { Logger } from '../../common/logging/Logger';
import {
  FLOATING_CANDIDATE_HORIZONTAL_PADDING_VP,
  FLOATING_CANDIDATE_ITEM_GAP_VP,
  FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP
} from '../../domain/candidate/FloatingCandidateLayout';

const LOGGER = new Logger('FloatingCandidateRoot');

@Entry
@Component
struct FloatingCandidateRoot {
  private readonly controller: KeyboardController = new KeyboardController();
  private readonly settingsStore: SettingsStore = getSharedSettingsStore();
  private readonly themeResolver: KeyboardThemeResolver = new KeyboardThemeResolver();
  private readonly scroller: Scroller = new Scroller();

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
  @State private candidateFontSize: number = 14;
  @State private candidateUiMode: CandidateUiMode = CandidateUiMode.BROWSABLE;
  @State private palette: KeyboardColorPalette = LIGHT_PALETTE;

  private readonly onSessionChanged = (): void => this.refreshSession();
  private readonly onSettingsChanged = (): void => this.refreshSettings();

  aboutToAppear(): void {
    this.controller.subscribe(this.onSessionChanged);
    this.settingsStore.subscribe(this.onSettingsChanged);
    this.refreshSession();
    this.refreshSettings();
  }

  aboutToDisappear(): void {
    this.controller.unsubscribe(this.onSessionChanged);
    this.settingsStore.unsubscribe(this.onSettingsChanged);
    this.controller.dispose();
  }

  private refreshSession(): void {
    const state = this.controller.getState();
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
  }

  private refreshSettings(): void {
    const settings = this.settingsStore.getSnapshot();
    this.candidateUiMode = resolveCandidateUiMode(settings.schemeId);
    this.palette = this.themeResolver.resolve(this.settingsStore.getEffectiveTheme());
    if (settings.candidateFontSizeMode === CandidateFontSizeMode.SMALL) {
      this.candidateFontSize = 12;
    } else if (settings.candidateFontSizeMode === CandidateFontSizeMode.LARGE) {
      this.candidateFontSize = 17;
    } else {
      this.candidateFontSize = 14;
    }
  }

  private async commitCandidate(index: number): Promise<void> {
    if (this.committing || index < 0) {
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

  build() {
    Row({ space: FLOATING_CANDIDATE_ITEM_GAP_VP }) {
      Scroll(this.scroller) {
        Row({ space: FLOATING_CANDIDATE_ITEM_GAP_VP }) {
          if (this.preeditView().visible) {
            Text(this.preeditView().displayText)
              .fontSize(this.candidateFontSize)
              .fontColor(this.palette.candidateText)
              .fontWeight(FontWeight.Medium)
              .decoration({
                type: this.preeditView().decoration === CompositionPreeditDecoration.UNDERLINE
                  ? TextDecorationType.Underline
                  : TextDecorationType.None,
                color: this.palette.candidateText,
                style: TextDecorationStyle.SOLID
              })
              .maxLines(1)
              .padding({
                left: FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP,
                right: FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP,
                top: 5,
                bottom: 5
              })
          }
          ForEach(this.visibleCandidates(), (candidate: Candidate, index: number) => {
            Text(this.candidateText(candidate, this.sourceIndex(candidate)))
              .fontSize(this.candidateFontSize)
              .fontColor(this.palette.candidateText)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .padding({
                left: FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP,
                right: FLOATING_CANDIDATE_ITEM_HORIZONTAL_PADDING_VP,
                top: 5,
                bottom: 5
              })
              .borderRadius(6)
              .backgroundColor(this.sourceIndex(candidate) === this.highlightedIndex
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
              .onClick(() => this.commitCandidate(this.sourceIndex(candidate)))
          }, (candidate: Candidate) => candidate.id)
        }
        .height('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .height('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

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
    .borderRadius(10)
  }
}
