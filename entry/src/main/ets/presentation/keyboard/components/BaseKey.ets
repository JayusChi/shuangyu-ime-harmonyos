import { KeyboardKeySpec, KeyboardKeyKind } from '../model/KeyboardLayoutSpec';
import { KeyboardColorPalette } from '../design/KeyboardPalette';
import { OrientationMetrics } from '../design/KeyboardMetrics';
import { KeyboardAction, KeyboardMode } from '../../../domain/keyboard/KeyboardAction';
import { ShiftState } from '../../../domain/editor/EditorContext';
import { AlternateKeyGestureController } from '../../../application/AlternateKeyGestureController';

/**
 * 按键状态
 */
export interface KeyState {
  isPressed: boolean;
}

/**
 * 基础按键组件属性
 */
export interface BaseKeyProps {
  spec: KeyboardKeySpec;
  palette: KeyboardColorPalette;
  metrics: OrientationMetrics;
  keyboardMode: KeyboardMode;
  shiftState?: ShiftState;
  longPressEnabled?: boolean;
  onKeyPress?: (spec: KeyboardKeySpec) => void;
  onKeyRelease?: (spec: KeyboardKeySpec) => void;
  onKeyClick?: (spec: KeyboardKeySpec) => void;
  onLongPressAction?: (action: KeyboardAction) => void;
}

/**
 * 基础按键组件
 * 提供统一的按键外观和交互
 */
@Component
export struct BaseKey {
  @Prop spec: KeyboardKeySpec;
  @Prop palette: KeyboardColorPalette;
  @Prop metrics: OrientationMetrics;
  @Prop keyboardMode: KeyboardMode = KeyboardMode.ENGLISH;
  @Prop shiftState: ShiftState = ShiftState.LOWERCASE;
  @Prop longPressEnabled: boolean = true;
  @State private isPressed: boolean = false;

  private gestureController: AlternateKeyGestureController | null = null;
  onKeyPress?: (spec: KeyboardKeySpec) => void;
  onKeyRelease?: (spec: KeyboardKeySpec) => void;
  onKeyClick?: (spec: KeyboardKeySpec) => void;
  onLongPressAction?: (action: KeyboardAction) => void;

  aboutToAppear(): void {
    this.gestureController = new AlternateKeyGestureController(
      (): void => this.dispatchShortPress(),
      (): void => this.dispatchLongPress(),
      (): void => this.dispatchSwipeUp(),
      undefined,
      (): void => this.dispatchSwipeDown()
    );
  }

  aboutToDisappear(): void {
    this.gestureController?.destroy();
    this.gestureController = null;
  }

  private supportsAlternateGesture(): boolean {
    return this.longPressEnabled &&
      (this.spec.longPressAction !== undefined || this.spec.swipeUpAction !== undefined ||
        this.spec.swipeDownAction !== undefined);
  }

  private dispatchShortPress(): void {
    if (this.onKeyClick) {
      this.onKeyClick(this.spec);
    }
  }

  private dispatchLongPress(): void {
    if (this.spec.longPressAction && this.onLongPressAction) {
      this.onLongPressAction(this.spec.longPressAction);
    }
  }

  private dispatchSwipeUp(): void {
    if (this.spec.swipeUpAction && this.onLongPressAction) {
      this.onLongPressAction(this.spec.swipeUpAction);
    }
  }

  private dispatchSwipeDown(): void {
    if (this.spec.swipeDownAction && this.onLongPressAction) {
      this.onLongPressAction(this.spec.swipeDownAction);
    }
  }

  /**
   * 获取按键背景色
   */
  private getBackgroundColor(): string {
    if (this.isPressed) {
      return this.getPressedBackgroundColor();
    }

    switch (this.spec.kind) {
      case KeyboardKeyKind.LETTER:
      case KeyboardKeyKind.T9_DIGIT:
        return this.palette.letterKeyBackground;
      case KeyboardKeyKind.SPACE:
        return this.palette.spaceKeyBackground;
      case KeyboardKeyKind.MODE_SWITCH:
        return this.keyboardMode === KeyboardMode.ENGLISH
          ? this.palette.modeKeyBackgroundEnglish
          : this.palette.modeKeyBackgroundChinese;
      case KeyboardKeyKind.SHIFT:
        return this.spec.active === true || this.shiftState === ShiftState.CAPS_LOCK
          ? this.palette.modeKeyBackgroundChinese
          : this.palette.functionKeyBackground;
      case KeyboardKeyKind.DELETE:
        return this.palette.functionKeyBackground;
      case KeyboardKeyKind.ENTER:
        return this.palette.primaryFunctionBackground;
      default:
        return this.palette.functionKeyBackground;
    }
  }

  /**
   * 获取按下状态背景色
   */
  private getPressedBackgroundColor(): string {
    switch (this.spec.kind) {
      case KeyboardKeyKind.LETTER:
      case KeyboardKeyKind.T9_DIGIT:
        return this.palette.letterKeyPressedBackground;
      case KeyboardKeyKind.DELETE:
      case KeyboardKeyKind.SPACE:
      case KeyboardKeyKind.MODE_SWITCH:
      case KeyboardKeyKind.SHIFT:
        return this.palette.functionKeyPressedBackground;
      case KeyboardKeyKind.ENTER:
        return this.palette.primaryFunctionPressedBackground;
      default:
        return this.palette.functionKeyPressedBackground;
    }
  }

  private getBackgroundImage(): string {
    if (this.isPressed) {
      return '';
    }
    switch (this.spec.kind) {
      case KeyboardKeyKind.LETTER:
      case KeyboardKeyKind.T9_DIGIT:
        return this.palette.letterKeyBackgroundImage;
      case KeyboardKeyKind.SPACE:
        return this.palette.spaceKeyBackgroundImage;
      case KeyboardKeyKind.ENTER:
        return this.palette.enterKeyBackgroundImage;
      default:
        return this.palette.functionKeyBackgroundImage;
    }
  }

  /**
   * 获取文字颜色
   */
  private getTextColor(): string {
    if (this.spec.kind === KeyboardKeyKind.MODE_SWITCH) {
      return this.keyboardMode === KeyboardMode.ENGLISH
        ? this.palette.modeKeyTextEnglish
        : this.palette.modeKeyTextChinese;
    }

    if (this.spec.kind === KeyboardKeyKind.ENTER) {
      return this.palette.primaryFunctionText;
    }

    return this.spec.kind === KeyboardKeyKind.LETTER || this.spec.kind === KeyboardKeyKind.T9_DIGIT
      ? this.palette.letterKeyText
      : this.palette.functionKeyText;
  }

  /**
   * 获取字体大小
   */
  private getFontSize(): number {
    return this.spec.kind === KeyboardKeyKind.LETTER || this.spec.kind === KeyboardKeyKind.T9_DIGIT
      ? this.metrics.letterFontSize
      : this.metrics.functionFontSize;
  }

  /**
   * 获取字体粗细
   */
  private getFontWeight(): FontWeight {
    return this.spec.kind === KeyboardKeyKind.LETTER || this.spec.kind === KeyboardKeyKind.T9_DIGIT
      ? FontWeight.Medium
      : FontWeight.Regular;
  }

  private isShiftLocked(): boolean {
    return this.spec.active === true || this.shiftState === ShiftState.CAPS_LOCK;
  }

  /**
   * 获取按键标签（模式切换键需要动态显示）
   */
  private getLabel(): string {
    if (this.spec.kind === KeyboardKeyKind.MODE_SWITCH &&
      (this.spec.id === 'mode-switch' || this.spec.id === 'language')) {
      return this.keyboardMode === KeyboardMode.ENGLISH ? '英' : '中';
    }
    return this.spec.label;
  }

  build() {
    Row() {
      if (this.spec.kind === KeyboardKeyKind.DELETE) {
        Image(this.palette.useDarkMedia
          ? $r('app.media.danran_delete_dark')
          : $r('app.media.danran_delete'))
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .accessibilityText(this.spec.accessibilityLabel)
      } else if (this.spec.kind === KeyboardKeyKind.SHIFT) {
        Image(this.palette.useDarkMedia
          ? (this.isShiftLocked()
            ? $r('app.media.danran_caps_lock_dark')
            : $r('app.media.danran_shift_dark'))
          : (this.isShiftLocked()
            ? $r('app.media.danran_caps_lock')
            : $r('app.media.danran_shift')))
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .accessibilityText(this.spec.accessibilityLabel)
      } else if (this.spec.upperLabel) {
        Column({ space: 1 }) {
          Text(this.spec.upperLabel)
            .fontSize(Math.max(8, this.metrics.functionFontSize - 1))
            .fontColor(this.palette.candidateReading)
            .fontWeight(FontWeight.Regular)
            .maxLines(1)
          Text(this.getLabel())
            .fontSize(this.getFontSize())
            .fontColor(this.getTextColor())
            .fontWeight(this.getFontWeight())
            .maxLines(1)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.spec.secondaryLabel) {
        Column({ space: 1 }) {
          Text(this.getLabel())
            .fontSize(this.getFontSize())
            .fontColor(this.getTextColor())
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
          Text(this.spec.secondaryLabel)
            .fontSize(Math.max(8, this.metrics.functionFontSize - 1))
            .fontColor(this.palette.candidateReading)
            .fontWeight(FontWeight.Regular)
            .maxLines(1)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Text(this.getLabel())
          .fontSize(this.getFontSize())
          .fontColor(this.getTextColor())
          .fontWeight(this.getFontWeight())
          .maxLines(1)
      }
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.spec.weight)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.getBackgroundColor())
    .backgroundImage(this.getBackgroundImage(), ImageRepeat.NoRepeat)
    .backgroundImageSize({ width: '100%', height: '100%' })
    .border({ width: 1, color: this.palette.keyBorder })
    .borderRadius(this.metrics.keyBorderRadius)
    .accessibilityText(this.spec.accessibilityLabel)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true;
        if (this.supportsAlternateGesture() && event.touches.length > 0) {
          this.gestureController?.start(event.touches[0].x, event.touches[0].y);
        }
        if (this.onKeyPress) {
          this.onKeyPress(this.spec);
        }
      } else if (event.type === TouchType.Move) {
        if (this.supportsAlternateGesture() && event.touches.length > 0) {
          this.gestureController?.move(event.touches[0].x, event.touches[0].y);
        }
      } else if (event.type === TouchType.Up) {
        this.isPressed = false;
        if (this.supportsAlternateGesture()) {
          this.gestureController?.release();
        }
        if (this.onKeyRelease) {
          this.onKeyRelease(this.spec);
        }
      } else if (event.type === TouchType.Cancel) {
        this.isPressed = false;
        this.gestureController?.cancel();
        if (this.onKeyRelease) {
          this.onKeyRelease(this.spec);
        }
      }
    })
    .onClick(() => {
      if (this.supportsAlternateGesture()) {
        this.gestureController?.click();
      } else {
        this.dispatchShortPress();
      }
    })
  }
}
