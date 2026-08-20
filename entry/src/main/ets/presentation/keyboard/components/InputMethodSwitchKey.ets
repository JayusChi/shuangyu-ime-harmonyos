import { ShortLongPressController } from '../../../application/ShortLongPressController';
import { KeyboardAction } from '../../../domain/keyboard/KeyboardAction';
import { KeyboardKeySpec } from '../model/KeyboardLayoutSpec';
import { KeyboardColorPalette } from '../design/KeyboardPalette';
import { OrientationMetrics } from '../design/KeyboardMetrics';

@Component
export struct InputMethodSwitchKey {
  @Prop spec: KeyboardKeySpec;
  @Prop palette: KeyboardColorPalette;
  @Prop metrics: OrientationMetrics;
  @Prop longPressEnabled: boolean = true;
  @State private isPressed: boolean = false;

  private pressController: ShortLongPressController | null = null;
  onAction?: (action: KeyboardAction) => void;

  aboutToAppear(): void {
    this.pressController = new ShortLongPressController(
      (): void => this.dispatch(this.spec.action),
      (): void => {
        if (this.longPressEnabled && this.spec.longPressAction) {
          this.dispatch(this.spec.longPressAction);
        }
      }
    );
  }

  aboutToDisappear(): void {
    this.pressController?.destroy();
    this.pressController = null;
  }

  private dispatch(action: KeyboardAction): void {
    if (this.onAction) {
      this.onAction(action);
    }
  }

  build() {
    Row() {
      Image($r('app.media.input_method_switcher'))
        .width(24)
        .height(24)
        .fillColor(this.palette.functionKeyText)
        .objectFit(ImageFit.Contain)
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.spec.weight)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.isPressed
      ? this.palette.functionKeyPressedBackground
      : this.palette.functionKeyBackground)
    .borderRadius(this.metrics.keyBorderRadius)
    .accessibilityText(this.longPressEnabled
      ? $r('app.string.switch_input_method_long_press')
      : $r('app.string.switch_input_method'))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true;
        this.pressController?.start();
      } else if (event.type === TouchType.Up) {
        this.isPressed = false;
        this.pressController?.release();
      } else if (event.type === TouchType.Cancel) {
        this.isPressed = false;
        this.pressController?.cancel();
      }
    })
    .onClick(() => {
      if (this.longPressEnabled) {
        this.pressController?.click();
      } else {
        this.pressController?.cancel();
        this.dispatch(this.spec.action);
      }
    })
  }
}
