import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import {
  HIDE_KEYBOARD_ACTION,
  KeyboardAction,
  KeyboardMode,
  TOGGLE_LANGUAGE_ACTION,
  SHOW_INPUT_METHOD_PICKER_ACTION
} from '../../domain/keyboard/KeyboardAction';
import {
  shuangpinKeyboardLayoutDisplayName,
  ShuangpinKeyboardLayout
} from '../../domain/keyboard/ShuangpinKeyboardLayout';
import { KeyboardColorPalette, LIGHT_PALETTE } from '../keyboard/design/KeyboardPalette';
import {
  CompositionPreeditView,
  resolveCompositionPreeditView
} from '../../domain/candidate/CompositionPreeditView';
import { toContextualCandidateDisplayItem } from '../../domain/candidate/CandidateDisplayItem';
import {
  CandidateUiMode,
  resolveCandidateAccessibilityText,
  resolveCandidateEmptyFeedback,
  shouldShowCandidateExpansionAction
} from '../../domain/candidate/CandidateUiPolicy';

const CANDIDATE_BAR_HORIZONTAL_PADDING = 8;

export interface KeyboardStatusBarLayoutSpec {
  contentLayoutWeight: number;
  actionScrollable: boolean;
  actionId: string;
  actionAccessibilityText: string;
  actionIconSize: number;
  action: KeyboardAction;
}

export interface CandidateExpansionActionSpec {
  actionId: string;
  expandAccessibilityText: string;
  collapseAccessibilityText: string;
  minimumWidth: number;
}

/**
 * 可测试的顶部栏契约：候选只存在于弹性内容区，收起操作位于独立固定区。
 */
export const KEYBOARD_STATUS_BAR_LAYOUT: KeyboardStatusBarLayoutSpec = {
  contentLayoutWeight: 1,
  actionScrollable: false,
  actionId: 'status-bar-hide-keyboard',
  actionAccessibilityText: '收起键盘',
  // 固定尺寸矢量图标不依赖设备字体基线，由按键容器在所有设备上做几何居中。
  actionIconSize: 24,
  action: HIDE_KEYBOARD_ACTION
};

export const CANDIDATE_EXPANSION_ACTION: CandidateExpansionActionSpec = {
  actionId: 'status-bar-toggle-candidates',
  expandAccessibilityText: '展开候选',
  collapseAccessibilityText: '收起候选',
  minimumWidth: 56
};

/**
 * 候选栏状态
 */
export enum CandidateBarState {
  IDLE = 'idle',               // 空闲状态
  LOADING = 'loading',         // 加载中
  CANDIDATES = 'candidates',   // 显示候选
  ERROR = 'error'              // 错误状态
}

/**
 * 候选栏属性
 */
export interface CandidateBarProps {
  palette: KeyboardColorPalette;
  state: CandidateBarState;
  rawInput: string;
  preeditText: string;
  preferredPreeditText?: string;
  displaySegments?: string[];
  pendingCode?: string;
  segmentBoundaries?: number[];
  parserState?: string;
  candidates: Candidate[];
  highlightedIndex?: number;
  barHeight?: number;
  errorMessage?: string;
  candidateFontSize?: number;
  contentVisible?: boolean;
  actionWidth?: number;
  expanded?: boolean;
  pageLoading?: boolean;
  candidateUiMode?: CandidateUiMode;
  keyboardLayout?: ShuangpinKeyboardLayout;
  keyboardProfileName?: string;
  inputMethodPickerAvailable?: boolean;
  keyboardMode?: KeyboardMode;
  languageSwitchAvailable?: boolean;
  onCandidateClick?: (candidate: Candidate, index: number) => void;
  onToggleExpanded?: (expanded: boolean) => void;
  onAction?: (action: KeyboardAction) => void;
  onOpenKeyboardLayoutSelector?: () => void;
  onOpenSettings?: () => void;
}

@Component
export struct CandidateBar {
  @Prop palette: KeyboardColorPalette = LIGHT_PALETTE;
  @Prop state: CandidateBarState = CandidateBarState.IDLE;
  @Prop rawInput: string = '';
  @Prop preeditText: string = '';
  @Prop preferredPreeditText: string = '';
  @Prop displaySegments: string[] = [];
  @Prop pendingCode: string = '';
  @Prop segmentBoundaries: number[] = [];
  @Prop parserState: string = 'empty';
  @Prop @Watch('onCandidatesChange') candidates: Candidate[] = [];
  @Prop highlightedIndex: number = -1;
  @Prop barHeight: number = 52;
  @Prop errorMessage: string = '';
  @Prop candidateFontSize: number = 14;
  @Prop contentVisible: boolean = true;
  @Prop actionWidth: number = 48;
  @Prop expanded: boolean = false;
  @Prop pageLoading: boolean = false;
  @Prop candidateUiMode: CandidateUiMode = CandidateUiMode.BROWSABLE;
  @Prop keyboardLayout: ShuangpinKeyboardLayout = ShuangpinKeyboardLayout.TWENTY_SIX_KEY;
  @Prop keyboardProfileName: string = '';
  @Prop inputMethodPickerAvailable: boolean = false;
  @Prop keyboardMode: KeyboardMode = KeyboardMode.CHINESE;
  @Prop languageSwitchAvailable: boolean = true;
  @State private actionPressed: boolean = false;
  @State private languagePressed: boolean = false;
  @State private expansionPressed: boolean = false;

  private scroller: Scroller = new Scroller();

  private currentKeyboardName(): string {
    return this.keyboardProfileName.length > 0
      ? this.keyboardProfileName
      : shuangpinKeyboardLayoutDisplayName(this.keyboardLayout);
  }

  private languageLabel(): string {
    if (this.keyboardMode === KeyboardMode.CHINESE) {
      return '中';
    }
    if (this.keyboardMode === KeyboardMode.ENGLISH) {
      return '英';
    }
    return '中/英';
  }

  private languageAccessibilityText(): string {
    return this.keyboardMode === KeyboardMode.CHINESE
      ? '当前中文，切换到英文'
      : '当前英文，切换到中文';
  }

  onCandidateClick?: (candidate: Candidate, index: number) => void;
  onToggleExpanded?: (expanded: boolean) => void;
  onAction?: (action: KeyboardAction) => void;
  onOpenKeyboardLayoutSelector?: () => void;
  onOpenSettings?: () => void;

  @Builder
  private IdleToolbar() {
    Row({ space: 2 }) {
      Row({ space: 5 }) {
        Text('⌨')
          .fontSize(15)
          .fontColor(this.palette.modeKeyTextChinese)
        Text(this.currentKeyboardName())
          .fontSize(11)
          .fontColor(this.palette.modeKeyTextChinese)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
      }
      .height('100%')
      .padding({ left: 8, right: 8 })
      .layoutWeight(1.45)
      .justifyContent(FlexAlign.Center)
      .accessibilityText(`${this.currentKeyboardName()}，选择键盘方案`)
      .onClick((): void => this.onOpenKeyboardLayoutSelector?.())

      Row({ space: 4 }) {
        Image($r('app.media.input_method_switcher'))
          .width(17)
          .height(17)
          .fillColor(this.palette.functionKeyText)
          .objectFit(ImageFit.Contain)
        Text('输入法').fontSize(11).fontColor(this.palette.functionKeyText).maxLines(1)
      }
      .height('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .opacity(this.inputMethodPickerAvailable ? 1 : 0.45)
      .enabled(this.inputMethodPickerAvailable)
      .accessibilityText('输入法')
      .onClick((): void => this.onAction?.(SHOW_INPUT_METHOD_PICKER_ACTION))

      Row({ space: 4 }) {
        Text('⚙').fontSize(15).fontColor(this.palette.functionKeyText)
        Text('设置').fontSize(11).fontColor(this.palette.functionKeyText).maxLines(1)
      }
      .height('100%')
      .layoutWeight(0.85)
      .justifyContent(FlexAlign.Center)
      .accessibilityText('设置')
      .onClick((): void => this.onOpenSettings?.())

    }
    .width('100%')
    .height('100%')
    .padding({ left: 2, right: 2 })
  }

  private expansionAccessibilityText(): string {
    return this.expanded
      ? CANDIDATE_EXPANSION_ACTION.collapseAccessibilityText
      : CANDIDATE_EXPANSION_ACTION.expandAccessibilityText;
  }

  /**
   * 候选词列表变化时，将横向滚动位置重置到最左侧
   */
  private onCandidatesChange(): void {
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private preeditView(): CompositionPreeditView {
    return resolveCompositionPreeditView({
      rawInput: this.rawInput,
      preeditText: this.preeditText,
      preferredDisplayText: this.preferredPreeditText,
      displaySegments: this.displaySegments,
      pendingCode: this.pendingCode,
      segmentBoundaries: this.segmentBoundaries
    });
  }

  private emptyFeedbackText(): string {
    return resolveCandidateEmptyFeedback(this.candidateUiMode, this.rawInput).text;
  }

  private emptyFeedbackAccessibilityText(): string {
    return resolveCandidateEmptyFeedback(this.candidateUiMode, this.rawInput).accessibilityText;
  }

  private candidateAccessibilityText(candidate: Candidate, index: number): string {
    return resolveCandidateAccessibilityText(
      this.candidateUiMode,
      this.rawInput,
      index,
      candidate.text,
      candidate.reading
    );
  }

  /**
   * 阶段 4.1：未上屏组合编码统一使用下划线装饰。装饰只作用于 Text 组件
   * 的绘制，`rawInput`/`preeditText` 字符串保持原样，不会拼接下划线字符。
   */
  @Builder
  private PreeditChip() {
    // Read the reactive property in the builder itself. Passing a computed
    // object into @Builder can retain the previous render's value on device.
    Text(this.preeditView().displayText)
      .fontSize(14)
      .fontColor(this.palette.candidateText)
      .fontWeight(FontWeight.Medium)
      .decoration({
        type: TextDecorationType.Underline,
        color: this.palette.candidateText,
        style: TextDecorationStyle.SOLID
      })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private CompositionView() {
    Row({ space: 8 }) {
      this.PreeditChip()
      if (resolveCandidateEmptyFeedback(this.candidateUiMode, this.rawInput).visible) {
        Text(this.emptyFeedbackText())
          .fontSize(10)
          .fontColor(this.palette.candidateReading)
          .fontWeight(FontWeight.Regular)
          .accessibilityText(this.emptyFeedbackAccessibilityText())
      } else {
        Text(this.parserState)
          .fontSize(10)
          .fontColor(this.palette.candidateReading)
          .fontWeight(FontWeight.Regular)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: CANDIDATE_BAR_HORIZONTAL_PADDING, right: CANDIDATE_BAR_HORIZONTAL_PADDING })
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 构建候选词视图。候选词全量加载，通过横向滚动浏览，无翻页按钮。
   * 阶段 4.1：非空 rawInput 时在候选左侧固定展示带下划线的未上屏输入码，
   * 让用户明确区分组合中的编码与已上屏文本。
   */
  @Builder
  private CandidatesView() {
    if (this.candidates.length === 0) {
      if (this.preeditView().visible) {
        this.CompositionView()
      }
    } else {
      Scroll(this.scroller) {
        Row({ space: 6 }) {
          if (this.preeditView().visible) {
            // 未上屏输入码作为候选左侧不可点击的样式条，与候选一起横向滚动；
            // 只是展示，`decoration` 只在渲染层生效，`rawInput` 不受影响。
            this.PreeditChip()
          }
          ForEach(this.candidates, (candidate: Candidate, index: number) => {
            // 阶段 4.2：普通候选项仅渲染 candidate.text，宽度随文字自适应；
            // candidate.reading 仍保留在数据结构中供引擎、调试页与自动化测试使用。
            Text(toContextualCandidateDisplayItem(
              candidate,
              index,
              this.candidateUiMode,
              this.rawInput
            ).displayText)
              .fontSize(this.candidateFontSize)
              .fontColor(this.palette.candidateText)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(4)
              .backgroundColor(index === this.highlightedIndex
                ? this.palette.functionKeyBackground
                : this.palette.candidateBackground)
              .onClick(() => {
                if (this.onCandidateClick) {
                  this.onCandidateClick(candidate, index);
                }
              })
              .accessibilityText(this.candidateAccessibilityText(candidate, index))
          }, (candidate: Candidate) => candidate.id)
        }
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: CANDIDATE_BAR_HORIZONTAL_PADDING, right: CANDIDATE_BAR_HORIZONTAL_PADDING })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .width('100%')
      .height('100%')
    }
  }

  /**
   * 构建加载状态视图
   */
  @Builder
  private LoadingView() {
    Row() {
      Text('加载中...')
        .fontSize(11)
        .fontColor(this.palette.candidateReading)
        .fontWeight(FontWeight.Regular)
    }
    .width('100%')
    .height('100%')
    .padding({ left: CANDIDATE_BAR_HORIZONTAL_PADDING, right: CANDIDATE_BAR_HORIZONTAL_PADDING })
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 构建错误状态视图
   */
  @Builder
  private ErrorView() {
    Row() {
      Text(this.errorMessage || '引擎错误')
        .fontSize(11)
        .fontColor(this.palette.errorText)
        .fontWeight(FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .padding({ left: CANDIDATE_BAR_HORIZONTAL_PADDING, right: CANDIDATE_BAR_HORIZONTAL_PADDING })
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Row() {
      Column() {
        if (this.state === CandidateBarState.IDLE) {
          this.IdleToolbar()
        } else if (this.contentVisible) {
          if (this.state === CandidateBarState.LOADING) {
            this.LoadingView()
          } else if (this.state === CandidateBarState.ERROR) {
            this.ErrorView()
          } else if (this.state === CandidateBarState.CANDIDATES) {
            this.CandidatesView()
          } else if (this.preeditView().visible) {
            this.CompositionView()
          }
        }
      }
      .width(0)
      .height('100%')
      .layoutWeight(KEYBOARD_STATUS_BAR_LAYOUT.contentLayoutWeight)

      if (shouldShowCandidateExpansionAction(this.candidateUiMode, this.candidates.length)) {
        Row() {
          Text(this.expanded ? '收起' : '展开')
            .fontSize(11)
            .fontColor(this.palette.functionKeyText)
            .fontWeight(FontWeight.Medium)
        }
        .width(Math.max(CANDIDATE_EXPANSION_ACTION.minimumWidth, this.actionWidth))
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.expansionPressed
          ? this.palette.functionKeyPressedBackground
          : this.palette.candidateBackground)
        .border({ width: { left: 1 }, color: this.palette.candidateDivider })
        .opacity(this.pageLoading ? 0.55 : 1)
        .enabled(!this.pageLoading)
        .accessibilityText(this.expansionAccessibilityText())
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.expansionPressed = true;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.expansionPressed = false;
          }
        })
        .onClick(() => {
          this.onToggleExpanded?.(!this.expanded);
        })
      }

      Row() {
        Text(this.languageLabel())
          .fontSize(12)
          .fontColor(this.palette.functionKeyText)
          .fontWeight(FontWeight.Medium)
      }
      .width(this.actionWidth)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.languagePressed
        ? this.palette.functionKeyPressedBackground
        : this.palette.candidateBackground)
      .border({ width: { left: 1 }, color: this.palette.candidateDivider })
      .opacity(this.languageSwitchAvailable ? 1 : 0.45)
      .enabled(this.languageSwitchAvailable)
      .accessibilityText(this.languageAccessibilityText())
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.languagePressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.languagePressed = false;
        }
      })
      .onClick(() => this.onAction?.(TOGGLE_LANGUAGE_ACTION))

      Row() {
        Image($r('app.media.keyboard_hide_chevron'))
          .width(KEYBOARD_STATUS_BAR_LAYOUT.actionIconSize)
          .height(KEYBOARD_STATUS_BAR_LAYOUT.actionIconSize)
          .fillColor(this.palette.functionKeyText)
          .objectFit(ImageFit.Contain)
          .accessibilityText(KEYBOARD_STATUS_BAR_LAYOUT.actionAccessibilityText)
      }
      .width(this.actionWidth)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.actionPressed
        ? this.palette.functionKeyPressedBackground
        : this.palette.functionKeyBackground)
      .border({ width: { left: 1 }, color: this.palette.candidateDivider })
      .accessibilityText(KEYBOARD_STATUS_BAR_LAYOUT.actionAccessibilityText)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.actionPressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.actionPressed = false;
        }
      })
      .onClick(() => {
        if (this.onAction) {
          this.onAction(KEYBOARD_STATUS_BAR_LAYOUT.action);
        }
      })
    }
    .width('100%')
    .height(this.barHeight)
    .backgroundColor(this.palette.candidateBackground)
    .border({ width: { bottom: 1 }, color: this.palette.candidateDivider })
  }
}
