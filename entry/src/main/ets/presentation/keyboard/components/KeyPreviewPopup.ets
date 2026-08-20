import { KeyboardColorPalette } from '../design/KeyboardPalette';
import { KEY_PREVIEW_CONFIG } from '../design/KeyboardMetrics';

/**
 * 按键预览弹出组件
 */
@Component
export struct KeyPreviewPopup {
  @Prop label: string = '';
  @Prop palette: KeyboardColorPalette;
  @Prop visible: boolean = false;
  @Prop offsetX: number = 0;
  @Prop offsetY: number = KEY_PREVIEW_CONFIG.OFFSET_Y;

  build() {
    if (this.visible) {
      Column() {
        Text(this.label)
          .fontSize(24)
          .fontColor(this.palette.previewText)
          .fontWeight(FontWeight.Medium)
      }
      .width(KEY_PREVIEW_CONFIG.WIDTH)
      .height(KEY_PREVIEW_CONFIG.HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.palette.previewBackground)
      .borderRadius(KEY_PREVIEW_CONFIG.BORDER_RADIUS)
      .shadow({
        radius: 8,
        color: this.palette.previewShadow,
        offsetX: 0,
        offsetY: 2
      })
      .position({ x: this.offsetX, y: this.offsetY })
      .zIndex(100)
    }
  }
}
