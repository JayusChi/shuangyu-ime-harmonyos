import { KeyboardKeySpec, KeyboardKeyKind } from '../model/KeyboardLayoutSpec';
import { BaseKey } from './BaseKey';
import { KeyboardColorPalette } from '../design/KeyboardPalette';
import { OrientationMetrics } from '../design/KeyboardMetrics';
import { KeyboardMode } from '../../../domain/keyboard/KeyboardAction';
import { ShiftState } from '../../../domain/editor/EditorContext';

/**
 * 删除键组件。
 *
 * 重复删除控制器由键盘根组件持有，避免组合串或候选状态变化导致本组件
 * 重建时中断仍在进行的长按手势。
 */
@Component
export struct DeleteKey {
  @Prop spec: KeyboardKeySpec;
  @Prop palette: KeyboardColorPalette;
  @Prop metrics: OrientationMetrics;
  @Prop keyboardMode: KeyboardMode = KeyboardMode.ENGLISH;
  @Prop shiftState: ShiftState = ShiftState.LOWERCASE;

  onDeletePress?: () => void;
  onDeleteRelease?: () => void;
  onDeleteClick?: () => void;

  private handlePress(spec: KeyboardKeySpec): void {
    if (spec.kind === KeyboardKeyKind.DELETE && this.onDeletePress) {
      this.onDeletePress();
    }
  }

  private handleRelease(spec: KeyboardKeySpec): void {
    if (spec.kind === KeyboardKeyKind.DELETE && this.onDeleteRelease) {
      this.onDeleteRelease();
    }
  }

  private handleClick(spec: KeyboardKeySpec): void {
    if (spec.kind === KeyboardKeyKind.DELETE && this.onDeleteClick) {
      this.onDeleteClick();
    }
  }

  build() {
    BaseKey({
      spec: this.spec,
      palette: this.palette,
      metrics: this.metrics,
      keyboardMode: this.keyboardMode,
      shiftState: this.shiftState,
      onKeyPress: (spec: KeyboardKeySpec) => this.handlePress(spec),
      onKeyRelease: (spec: KeyboardKeySpec) => this.handleRelease(spec),
      onKeyClick: (spec: KeyboardKeySpec) => this.handleClick(spec)
    })
  }
}
