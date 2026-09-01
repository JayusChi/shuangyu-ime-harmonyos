import { KeyboardKeySpec, KeyboardKeyKind } from '../model/KeyboardLayoutSpec';
import { BaseKey } from './BaseKey';
import { KeyPreviewPopup } from './KeyPreviewPopup';
import { KeyboardColorPalette } from '../design/KeyboardPalette';
import { OrientationMetrics } from '../design/KeyboardMetrics';
import { KeyboardAction, KeyboardMode } from '../../../domain/keyboard/KeyboardAction';
import { ShiftState } from '../../../domain/editor/EditorContext';
import { DEFAULT_LONG_PRESS_DURATION_MS } from '../../../domain/settings/ImeSettings';

/**
 * 字母按键组件
 * 支持按下时显示预览弹出
 */
@Component
export struct LetterKey {
  @Prop spec: KeyboardKeySpec;
  @Prop palette: KeyboardColorPalette;
  @Prop metrics: OrientationMetrics;
  @Prop keyboardMode: KeyboardMode = KeyboardMode.ENGLISH;
  @Prop shiftState: ShiftState = ShiftState.LOWERCASE;
  @Prop longPressDurationMs: number = DEFAULT_LONG_PRESS_DURATION_MS;
  @State private showPreview: boolean = false;

  onKeyClick?: (spec: KeyboardKeySpec) => void;
  onAlternateAction?: (action: KeyboardAction) => void;

  private handlePress(spec: KeyboardKeySpec): void {
    if (spec.previewEnabled) {
      this.showPreview = true;
    }
  }

  private handleRelease(spec: KeyboardKeySpec): void {
    if (spec.previewEnabled) {
      this.showPreview = false;
    }
  }

  private handleClick(spec: KeyboardKeySpec): void {
    if (this.onKeyClick) {
      this.onKeyClick(spec);
    }
  }

  build() {
    Stack() {
      BaseKey({
        spec: this.spec,
        palette: this.palette,
        metrics: this.metrics,
        keyboardMode: this.keyboardMode,
        shiftState: this.shiftState,
        longPressDurationMs: this.longPressDurationMs,
        onKeyPress: (spec: KeyboardKeySpec) => this.handlePress(spec),
        onKeyRelease: (spec: KeyboardKeySpec) => this.handleRelease(spec),
        onKeyClick: (spec: KeyboardKeySpec) => this.handleClick(spec),
        onLongPressAction: (action: KeyboardAction) => this.onAlternateAction?.(action)
      })

      // 预览弹出
      if (this.spec.previewEnabled && this.showPreview) {
        KeyPreviewPopup({
          label: this.spec.previewLabel ?? this.spec.label,
          palette: this.palette,
          visible: this.showPreview,
          offsetX: 0,
          offsetY: -50
        })
      }
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.spec.weight)
  }
}
