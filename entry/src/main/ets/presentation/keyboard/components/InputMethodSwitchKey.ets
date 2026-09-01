import { ShortLongPressController } from '../../../application/ShortLongPressController';
import { KeyboardAction } from '../../../domain/keyboard/KeyboardAction';
import { KeyboardKeySpec } from '../model/KeyboardLayoutSpec';
import {
  DanranKeyBackgroundKind,
  KeyboardColorPalette,
  resolveDanranKeyBackgroundSlice
} from '../design/KeyboardPalette';
import { OrientationMetrics } from '../design/KeyboardMetrics';
import { DEFAULT_LONG_PRESS_DURATION_MS } from '../../../domain/settings/ImeSettings';

@Component
export struct InputMethodSwitchKey {
  @Prop spec: KeyboardKeySpec;
  @Prop palette: KeyboardColorPalette;
  @Prop metrics: OrientationMetrics;
  @Prop longPressEnabled: boolean = true;
  @Prop @Watch('resetPressController') longPressDurationMs: number = DEFAULT_LONG_PRESS_DURATION_MS;
  @State private isPressed: boolean = false;

  private pressController: ShortLongPressController | null = null;
  onAction?: (action: KeyboardAction) => void;

  aboutToAppear(): void {
    this.resetPressController();
  }

  private resetPressController(): void {
    this.pressController?.destroy();
    this.pressController = new ShortLongPressController(
      (): void => this.dispatch(this.spec.action),
      (): void => {
        if (this.longPressEnabled && this.spec.longPressAction) {
          this.dispatch(this.spec.longPressAction);
        }
      },
      this.longPressDurationMs
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

  private getBackgroundImage(): ResourceStr {
    if (!this.palette.useDanranKeyImages) {
      return this.isPressed ? '' : this.palette.functionKeyBackgroundImage;
    }
    if (this.palette.useDarkMedia) {
      return this.isPressed
        ? $r('app.media.danran_function_pressed_dark')
        : $r('app.media.danran_function_dark');
    }
    return this.isPressed
      ? $r('app.media.danran_function_pressed')
      : $r('app.media.danran_function');
  }

  private getBackgroundResizableOptions(): ResizableOptions {
    if (!this.palette.useDanranKeyImages) {
      return {};
    }
    return {
      slice: resolveDanranKeyBackgroundSlice(
        DanranKeyBackgroundKind.FUNCTION,
        this.palette.useDarkMedia,
        this.isPressed
      )
    };
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
    .backgroundColor(this.palette.useDanranKeyImages
      ? '#00000000'
      : (this.isPressed ? this.palette.functionKeyPressedBackground : this.palette.functionKeyBackground))
    .backgroundImage(this.getBackgroundImage(), ImageRepeat.NoRepeat)
    .backgroundImageSize({ width: '100%', height: '100%' })
    .backgroundImageResizable(this.getBackgroundResizableOptions())
    .border({ width: this.palette.useDanranKeyImages ? 0 : 1, color: this.palette.keyBorder })
    .borderRadius(this.palette.useDanranKeyImages ? 0 : this.metrics.keyBorderRadius)
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
