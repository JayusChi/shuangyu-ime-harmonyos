import { DEFAULT_CANDIDATE_DISPLAY_COUNT } from '../../domain/settings/ImeSettings';
import { Candidate } from '../../infrastructure/native/NativeEngineTypes';
import {
  HIDE_KEYBOARD_ACTION,
  KeyboardAction,
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
  resolveCollapsedCandidates,
  shouldShowCandidateExpansionAction
} from '../../domain/candidate/CandidateUiPolicy';
import {
  AiAction,
  AI_ACTIONS,
  AiPresentationState,
  AiProviderKind,
  AiRequestState,
  AiSuggestion,
  aiActionLabel,
  createIdleAiPresentationState
} from '../../domain/ai/AiContracts';
import {
  createIdleVoicePresentationState,
  VoicePresentationState,
  VoiceSessionState
} from '../../domain/voice/VoiceContracts';
import { LocalAssociationSuggestion } from '../../domain/ai/LocalAssociationContracts';

const CANDIDATE_BAR_HORIZONTAL_PADDING = 8;
export const COLLAPSED_CANDIDATE_LIMIT = DEFAULT_CANDIDATE_DISPLAY_COUNT;

export interface KeyboardStatusBarLayoutSpec {
  contentLayoutWeight: number;
  actionScrollable: boolean;
  languageSwitchVisible: boolean;
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
  // 中英文切换统一由架高层或空格手势承担，候选栏不再重复显示入口。
  languageSwitchVisible: false,
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
  cursorPreeditVisible?: boolean;
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
  candidateDisplayCount?: number;
  hasNextPage?: boolean;
  contentVisible?: boolean;
  actionWidth?: number;
  expanded?: boolean;
  pageLoading?: boolean;
  candidateUiMode?: CandidateUiMode;
  keyboardLayout?: ShuangpinKeyboardLayout;
  keyboardProfileName?: string;
  inputMethodPickerAvailable?: boolean;
  bottomLiftLayerVisible?: boolean;
  aiEntryVisible?: boolean;
  aiEntryEnabled?: boolean;
  aiUnavailableReason?: string;
  voiceEntryVisible?: boolean;
  voiceEntryEnabled?: boolean;
  voiceUnavailableReason?: string;
  aiPresentation?: AiPresentationState;
  voicePresentation?: VoicePresentationState;
  localAssociations?: LocalAssociationSuggestion[];
  onCandidateClick?: (candidate: Candidate, index: number) => void;
  onToggleExpanded?: (expanded: boolean) => void;
  onAction?: (action: KeyboardAction) => void;
  onOpenKeyboardLayoutSelector?: () => void;
  onOpenSettings?: () => void;
  onAiEntry?: () => void;
  onAiAction?: (action: AiAction) => void;
  onAiSuggestionClick?: (suggestionId: string) => void;
  onAiCancel?: () => void;
  onLocalAssociationClick?: (associationId: string) => void;
  onVoiceEntry?: () => void;
  onVoiceStop?: () => void;
  onVoiceConfirm?: () => void;
  onVoiceRetry?: () => void;
  onVoiceCancel?: () => void;
}

@Component
export struct CandidateBar {
  @Prop palette: KeyboardColorPalette = LIGHT_PALETTE;
  @Prop state: CandidateBarState = CandidateBarState.IDLE;
  @Prop rawInput: string = '';
  @Prop preeditText: string = '';
  @Prop cursorPreeditVisible: boolean = false;
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
  @Prop candidateDisplayCount: number = DEFAULT_CANDIDATE_DISPLAY_COUNT;
  @Prop hasNextPage: boolean = false;
  @State private candidateContentWidth: number = 0;
  @State private candidateViewportWidth: number = 0;
  @Prop contentVisible: boolean = true;
  @Prop actionWidth: number = 48;
  @Prop expanded: boolean = false;
  @Prop pageLoading: boolean = false;
  @Prop candidateUiMode: CandidateUiMode = CandidateUiMode.BROWSABLE;
  @Prop keyboardLayout: ShuangpinKeyboardLayout = ShuangpinKeyboardLayout.TWENTY_SIX_KEY;
  @Prop keyboardProfileName: string = '';
  @Prop inputMethodPickerAvailable: boolean = false;
  @Prop bottomLiftLayerVisible: boolean = false;
  @Prop aiEntryVisible: boolean = false;
  @Prop aiEntryEnabled: boolean = false;
  @Prop aiUnavailableReason: string = '';
  @Prop voiceEntryVisible: boolean = false;
  @Prop voiceEntryEnabled: boolean = false;
  @Prop voiceUnavailableReason: string = '';
  @Prop aiPresentation: AiPresentationState = createIdleAiPresentationState();
  @Prop voicePresentation: VoicePresentationState = createIdleVoicePresentationState();
  @Prop localAssociations: LocalAssociationSuggestion[] = [];
  @State private actionPressed: boolean = false;
  @State private expansionPressed: boolean = false;
  @State private aiPressed: boolean = false;
  @State private voicePressed: boolean = false;

  private scroller: Scroller = new Scroller();

  private currentKeyboardName(): string {
    return this.keyboardProfileName.length > 0
      ? this.keyboardProfileName
      : shuangpinKeyboardLayoutDisplayName(this.keyboardLayout);
  }

  onCandidateClick?: (candidate: Candidate, index: number) => void;
  onToggleExpanded?: (expanded: boolean) => void;
  onAction?: (action: KeyboardAction) => void;
  onOpenKeyboardLayoutSelector?: () => void;
  onOpenSettings?: () => void;
  onAiEntry?: () => void;
  onAiAction?: (action: AiAction) => void;
  onAiSuggestionClick?: (suggestionId: string) => void;
  onAiCancel?: () => void;
  onLocalAssociationClick?: (associationId: string) => void;
  onVoiceEntry?: () => void;
  onVoiceStop?: () => void;
  onVoiceConfirm?: () => void;
  onVoiceRetry?: () => void;
  onVoiceCancel?: () => void;

  @Builder
  private IdleToolbar() {
    Row({ space: 2 }) {
      Row() {
        Image($r('app.media.candidate_settings_menu'))
          .width(KEYBOARD_STATUS_BAR_LAYOUT.actionIconSize)
          .height(KEYBOARD_STATUS_BAR_LAYOUT.actionIconSize)
          .fillColor(this.palette.functionKeyText)
          .objectFit(ImageFit.Contain)
      }
      .width(this.actionWidth)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .id('status-bar-settings')
      .accessibilityText('设置菜单')
      .onClick((): void => this.onOpenSettings?.())

      if (!this.bottomLiftLayerVisible) {
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
      }

      if (!this.bottomLiftLayerVisible) {
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
      }

      if (this.aiEntryVisible) {
        Row() {
          Text(this.aiEntryEnabled ? 'AI' : 'AI不可用')
            .fontSize(11)
            .fontColor(this.palette.functionKeyText)
            .maxLines(1)
        }
        .height('100%')
        .layoutWeight(0.8)
        .justifyContent(FlexAlign.Center)
        .opacity(this.aiEntryEnabled ? 1 : 0.45)
        .enabled(this.aiEntryEnabled)
        .backgroundColor(this.aiPressed
          ? this.palette.functionKeyPressedBackground
          : this.palette.candidateBackground)
        .accessibilityText(this.aiEntryEnabled ? 'AI 辅助' : this.aiUnavailableReason)
        .onTouch((event: TouchEvent): void => {
          this.aiPressed = event.type === TouchType.Down;
        })
        .onClick((): void => this.onAiEntry?.())
      }

      if (this.voiceEntryVisible) {
        Row() {
          Text(this.voiceEntryEnabled ? '语音' : '语音不可用')
            .fontSize(11)
            .fontColor(this.palette.functionKeyText)
            .maxLines(1)
        }
        .height('100%')
        .layoutWeight(0.9)
        .justifyContent(FlexAlign.Center)
        .opacity(this.voiceEntryEnabled ? 1 : 0.45)
        .enabled(this.voiceEntryEnabled)
        .backgroundColor(this.voicePressed
          ? this.palette.functionKeyPressedBackground
          : this.palette.candidateBackground)
        .accessibilityText(this.voiceEntryEnabled ? '语音输入' : this.voiceUnavailableReason)
        .onTouch((event: TouchEvent): void => {
          this.voicePressed = event.type === TouchType.Down;
        })
        .onClick((): void => this.onVoiceEntry?.())
      }

    }
    .width('100%')
    .height('100%')
    .padding({ left: 2, right: 2 })
  }

  @Builder
  private AiAssistView() {
    if (this.aiPresentation.state === AiRequestState.ACTIONS) {
      Scroll() {
        Row({ space: 7 }) {
          Text('AI·云端')
            .fontSize(11)
            .fontColor(this.palette.candidateReading)
          ForEach(AI_ACTIONS, (action: AiAction) => {
            Text(aiActionLabel(action))
              .fontSize(12)
              .fontColor(this.palette.candidateText)
              .padding({ left: 9, right: 9, top: 4, bottom: 4 })
              .borderRadius(4)
              .backgroundColor(this.palette.functionKeyBackground)
              .accessibilityText(`AI 动作，${aiActionLabel(action)}，云端处理`)
              .onClick((): void => this.onAiAction?.(action))
          }, (action: AiAction): string => action)
          Text('取消')
            .fontSize(11)
            .fontColor(this.palette.functionKeyText)
            .onClick((): void => this.onAiCancel?.())
        }
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: CANDIDATE_BAR_HORIZONTAL_PADDING, right: CANDIDATE_BAR_HORIZONTAL_PADDING })
        .onAreaChange((_old: Area, area: Area) => { this.candidateContentWidth = Number(area.width); })
      }
      .onAreaChange((_old: Area, area: Area) => { this.candidateViewportWidth = Number(area.width); })
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    } else if (this.aiPresentation.state === AiRequestState.READY) {
      Scroll() {
        Row({ space: 6 }) {
          Text(this.aiPresentation.providerKind === AiProviderKind.CLOUD ? 'AI·云端' : 'AI')
            .fontSize(11)
            .fontColor(this.palette.candidateReading)
          ForEach(this.aiPresentation.suggestions, (suggestion: AiSuggestion) => {
            Text(suggestion.text)
              .fontSize(this.candidateFontSize)
              .flexShrink(0)
              .fontColor(this.palette.candidateText)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(4)
              .backgroundColor(this.palette.functionKeyBackground)
              .accessibilityText(`AI 候选，${suggestion.label}`)
              .onClick((): void => this.onAiSuggestionClick?.(suggestion.suggestionId))
          }, (suggestion: AiSuggestion): string => suggestion.suggestionId)
          Text('取消')
            .fontSize(11)
            .fontColor(this.palette.functionKeyText)
            .onClick((): void => this.onAiCancel?.())
        }
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: CANDIDATE_BAR_HORIZONTAL_PADDING, right: CANDIDATE_BAR_HORIZONTAL_PADDING })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    } else {
      Row({ space: 8 }) {
        Text('AI')
          .fontSize(11)
          .fontColor(this.palette.candidateReading)
        Text(this.aiPresentation.statusMessage)
          .fontSize(11)
          .fontColor(this.aiPresentation.state === AiRequestState.ERROR
            ? this.palette.errorText
            : this.palette.candidateText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.aiPresentation.state === AiRequestState.LOADING ||
          this.aiPresentation.state === AiRequestState.APPLYING) {
          Text('取消')
            .fontSize(11)
            .fontColor(this.palette.functionKeyText)
            .onClick((): void => this.onAiCancel?.())
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: CANDIDATE_BAR_HORIZONTAL_PADDING, right: CANDIDATE_BAR_HORIZONTAL_PADDING })
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private VoiceAssistView() {
    Row({ space: 8 }) {
      Text('语音')
        .fontSize(11)
        .fontColor(this.palette.candidateReading)
      Text(this.voicePresentation.finalText.length > 0
        ? this.voicePresentation.finalText
        : (this.voicePresentation.interimText.length > 0
          ? this.voicePresentation.interimText
          : this.voicePresentation.statusMessage))
        .fontSize(11)
        .fontColor(this.voicePresentation.state === VoiceSessionState.ERROR
          ? this.palette.errorText
          : this.palette.candidateText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.voicePresentation.state === VoiceSessionState.RESULT_READY) {
        Text('上屏').fontSize(11).fontColor(this.palette.functionKeyText)
          .onClick((): void => this.onVoiceConfirm?.())
        Text('重说').fontSize(11).fontColor(this.palette.functionKeyText)
          .onClick((): void => this.onVoiceRetry?.())
        Text('取消').fontSize(11).fontColor(this.palette.functionKeyText)
          .onClick((): void => this.onVoiceCancel?.())
      } else if (this.voicePresentation.state === VoiceSessionState.LISTENING) {
        Text('停止').fontSize(11).fontColor(this.palette.functionKeyText)
          .onClick((): void => this.onVoiceStop?.())
        Text('取消').fontSize(11).fontColor(this.palette.functionKeyText)
          .onClick((): void => this.onVoiceCancel?.())
      } else if (this.voicePresentation.state === VoiceSessionState.ERROR) {
        Text('重试').fontSize(11).fontColor(this.palette.functionKeyText)
          .onClick((): void => this.onVoiceRetry?.())
        Text('取消').fontSize(11).fontColor(this.palette.functionKeyText)
          .onClick((): void => this.onVoiceCancel?.())
      } else if (this.voicePresentation.state === VoiceSessionState.FINALIZING ||
        this.voicePresentation.state === VoiceSessionState.COMMITTING) {
        Text('取消').fontSize(11).fontColor(this.palette.functionKeyText)
          .onClick((): void => this.onVoiceCancel?.())
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: CANDIDATE_BAR_HORIZONTAL_PADDING, right: CANDIDATE_BAR_HORIZONTAL_PADDING })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private LocalAssociationView() {
    Scroll() {
      Row({ space: 7 }) {
        Text('关联·本地')
          .fontSize(11)
          .fontColor(this.palette.candidateReading)
        ForEach(this.localAssociations, (suggestion: LocalAssociationSuggestion) => {
          Text(suggestion.text)
            .fontSize(this.candidateFontSize)
            .fontColor(this.palette.candidateText)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .borderRadius(4)
            .backgroundColor(this.palette.functionKeyBackground)
            .accessibilityText(`本地关联词，${suggestion.text}`)
            .onClick((): void => this.onLocalAssociationClick?.(suggestion.associationId))
        }, (suggestion: LocalAssociationSuggestion): string => suggestion.associationId)
      }
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: CANDIDATE_BAR_HORIZONTAL_PADDING, right: CANDIDATE_BAR_HORIZONTAL_PADDING })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
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
      cursorPreeditVisible: this.cursorPreeditVisible,
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
      candidate.displayText && candidate.displayText.length > 0 ? candidate.displayText : candidate.text,
      candidate.reading
    );
  }

  /**
   * 收起态只展示一整组候选，避免下一项被固定的“展开”按钮裁掉。
   * 其余候选统一进入全键盘展开页浏览。
   */
  private collapsedCandidates(): Candidate[] {
    return resolveCollapsedCandidates(this.candidates, this.candidateDisplayCount);
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
   * 收起态显示用户设定数量（默认五项），其余候选通过展开页浏览。
   * 光标处没有系统预编辑时，在候选左侧展示带下划线的未上屏输入码；光标处
   * 已显示输入码时这里保持隐藏，确保同一输入码只有一个展示位置。
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
          ForEach(this.collapsedCandidates(), (candidate: Candidate, index: number) => {
            // Number the visible candidates without modifying their commit text.
            Text() {
              Span(`${index + 1} `)
                .fontSize(Math.max(10, this.candidateFontSize - 3))
                .fontColor(this.palette.candidateReading)
                .fontWeight(FontWeight.Regular)
              Span(toContextualCandidateDisplayItem(
                candidate,
                index,
                this.candidateUiMode,
                this.rawInput
              ).displayText)
            }
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
          }, (candidate: Candidate) => `${candidate.id}:${candidate.displayText ?? ''}`)
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
        if (this.voicePresentation.state !== VoiceSessionState.IDLE) {
          this.VoiceAssistView()
        } else if (this.aiPresentation.state !== AiRequestState.IDLE) {
          this.AiAssistView()
        } else if (this.localAssociations.length > 0) {
          this.LocalAssociationView()
        } else if (this.state === CandidateBarState.IDLE) {
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

      if (this.expanded || shouldShowCandidateExpansionAction(
        this.candidateUiMode,
        this.candidates.length,
        this.rawInput,
        this.candidateDisplayCount,
        this.hasNextPage,
        this.candidateViewportWidth > 0 && this.candidateContentWidth > this.candidateViewportWidth + 1
      )) {
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

      // Keep the hide action at the right edge even when the bottom lift layer is visible.
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
      .id(KEYBOARD_STATUS_BAR_LAYOUT.actionId)
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
