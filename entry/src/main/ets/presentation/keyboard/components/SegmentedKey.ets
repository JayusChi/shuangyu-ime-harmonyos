import { KeyboardAction, KeyboardMode } from '../../../domain/keyboard/KeyboardAction';
import { ShiftState } from '../../../domain/editor/EditorContext';
import {
  KeyboardKeyAlternativeSpec,
  KeyboardKeySpec
} from '../model/KeyboardLayoutSpec';
import {
  DanranKeyBackgroundKind,
  KeyboardColorPalette,
  resolveDanranKeyBackgroundSlice
} from '../design/KeyboardPalette';
import { OrientationMetrics } from '../design/KeyboardMetrics';

@Component
export struct SegmentedKey {
  @Prop spec: KeyboardKeySpec;
  @Prop palette: KeyboardColorPalette;
  @Prop metrics: OrientationMetrics;
  @Prop keyboardMode: KeyboardMode = KeyboardMode.CHINESE;
  @Prop shiftState: ShiftState = ShiftState.ONE_SHOT_UPPERCASE;
  @State private pressed: boolean = false;

  onAction?: (action: KeyboardAction) => void;

  private getBackgroundImage(): ResourceStr {
    if (!this.palette.useDanranKeyImages) {
      return this.pressed ? '' : this.palette.letterKeyBackgroundImage;
    }
    if (this.palette.useDarkMedia) {
      return this.pressed
        ? $r('app.media.danran_key_pressed_dark')
        : $r('app.media.danran_key_dark');
    }
    return this.pressed
      ? $r('app.media.danran_key_pressed')
      : $r('app.media.danran_key');
  }

  private getBackgroundResizableOptions(): ResizableOptions {
    if (!this.palette.useDanranKeyImages) {
      return {};
    }
    return {
      slice: resolveDanranKeyBackgroundSlice(
        DanranKeyBackgroundKind.LETTER,
        this.palette.useDarkMedia,
        this.pressed
      )
    };
  }

  build() {
    Row() {
      ForEach(this.spec.alternatives ?? [], (alternative: KeyboardKeyAlternativeSpec) => {
        Text(alternative.label)
          .fontSize(this.metrics.letterFontSize)
          .fontColor(this.palette.letterKeyText)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .height('100%')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .accessibilityText(alternative.accessibilityLabel)
          .onClick((): void => this.onAction?.(alternative.action))
      }, (alternative: KeyboardKeyAlternativeSpec) => `${this.spec.id}-${alternative.label}`)
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.spec.weight)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.palette.useDanranKeyImages
      ? '#00000000'
      : (this.pressed ? this.palette.letterKeyPressedBackground : this.palette.letterKeyBackground))
    .backgroundImage(this.getBackgroundImage(), ImageRepeat.NoRepeat)
    .backgroundImageSize({ width: '100%', height: '100%' })
    .backgroundImageResizable(this.getBackgroundResizableOptions())
    .border({ width: this.palette.useDanranKeyImages ? 0 : 1, color: this.palette.keyBorder })
    .borderRadius(this.palette.useDanranKeyImages ? 0 : this.metrics.keyBorderRadius)
    .accessibilityText(this.spec.accessibilityLabel)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
  }
}
