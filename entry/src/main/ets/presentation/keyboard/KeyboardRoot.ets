import { KeyboardController } from '../../application/KeyboardController';
import { InputOperationResult } from '../../application/InputOperationResult';
import { KeyboardAction, KeyboardMode } from '../../domain/keyboard/KeyboardAction';
import { KeyboardKeyRole, KeyboardKeySpec, QWERTY_KEY_ROWS } from './KeyboardLayout';

@Entry
@Component
struct KeyboardRoot {
  private readonly controller: KeyboardController = new KeyboardController();

  @State private sessionActive: boolean = false;
  @State private keyboardVisible: boolean = false;
  @State private keyboardMode: KeyboardMode = KeyboardMode.ENGLISH;
  @State private editorConnected: boolean = false;
  @State private lastErrorMessage: string = 'success';
  @State private statusMessage: string = 'Stage 2 ready';
  @State private engineVersion: string = '';

  aboutToAppear(): void {
    this.engineVersion = this.controller.getEngineVersion();
    this.refreshState();
  }

  private refreshState(): void {
    const state = this.controller.getState();
    this.sessionActive = state.sessionActive;
    this.keyboardVisible = state.keyboardVisible;
    this.keyboardMode = state.keyboardMode;
    this.editorConnected = state.editorConnected;
    this.lastErrorMessage = state.lastErrorMessage;
  }

  private async dispatchAction(action: KeyboardAction): Promise<void> {
    const result = await this.controller.handleAction(action);
    this.refreshState();
    this.statusMessage = this.statusForResult(result);
  }

  private statusForResult(result: InputOperationResult): string {
    if (result.success) {
      return 'OK';
    }

    return `错误 ${result.errorCode}`;
  }

  private modeLabel(): string {
    return this.keyboardMode === KeyboardMode.ENGLISH ? '英' : '中';
  }

  private modeHint(): string {
    return this.keyboardMode === KeyboardMode.ENGLISH ? 'English' : '中文占位';
  }

  private keyLabel(spec: KeyboardKeySpec): string {
    if (spec.role === KeyboardKeyRole.MODE) {
      return this.modeLabel();
    }

    return spec.label;
  }

  private keyBackground(spec: KeyboardKeySpec): string {
    switch (spec.role) {
      case KeyboardKeyRole.LETTER:
        return '#FFFFFF';
      case KeyboardKeyRole.SPACE:
        return '#F1F5F9';
      case KeyboardKeyRole.MODE:
        return this.keyboardMode === KeyboardMode.ENGLISH ? '#E8F3FF' : '#FFF4E5';
      default:
        return '#E5E7EB';
    }
  }

  private keyTextColor(spec: KeyboardKeySpec): string {
    if (spec.role === KeyboardKeyRole.MODE) {
      return this.keyboardMode === KeyboardMode.ENGLISH ? '#0A59F7' : '#B45309';
    }

    return '#111827';
  }

  private keyFontSize(spec: KeyboardKeySpec): number {
    if (spec.role === KeyboardKeyRole.LETTER) {
      return 18;
    }

    return 12;
  }

  @Builder
  private KeyButton(spec: KeyboardKeySpec) {
    Row() {
      Text(this.keyLabel(spec))
        .fontSize(this.keyFontSize(spec))
        .fontColor(this.keyTextColor(spec))
        .fontWeight(spec.role === KeyboardKeyRole.LETTER ? FontWeight.Medium : FontWeight.Regular)
        .maxLines(1)
    }
      .height(42)
      .layoutWeight(spec.weight)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.keyBackground(spec))
      .borderRadius(6)
      .onClick(() => {
        this.dispatchAction(spec.action);
      })
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(this.modeHint())
          .fontSize(12)
          .fontColor('#111827')
          .fontWeight(FontWeight.Medium)
        Text(this.sessionActive && this.editorConnected ? '会话 active' : '等待输入框')
          .fontSize(11)
          .fontColor(this.sessionActive && this.editorConnected ? '#047857' : '#6B7280')
        Text(this.keyboardVisible ? 'visible' : 'hidden')
          .fontSize(11)
          .fontColor('#6B7280')
        Text(this.statusMessage)
          .fontSize(11)
          .fontColor('#4B5563')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
      }
      .width('100%')
      .height(28)

      Row({ space: 6 }) {
        Text(`Rust ${this.engineVersion === '' ? 'not loaded' : this.engineVersion}`)
          .fontSize(10)
          .fontColor('#6B7280')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.lastErrorMessage)
          .fontSize(10)
          .fontColor(this.lastErrorMessage === 'success' ? '#6B7280' : '#B91C1C')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(18)

      ForEach(QWERTY_KEY_ROWS, (row: KeyboardKeySpec[]) => {
        Row({ space: 5 }) {
          ForEach(row, (spec: KeyboardKeySpec) => {
            this.KeyButton(spec)
          }, (spec: KeyboardKeySpec) => spec.id)
        }
        .width('100%')
        .height(44)
      }, (row: KeyboardKeySpec[]) => row.map((spec: KeyboardKeySpec) => spec.id).join('-'))
    }
    .width('100%')
    .height('100%')
    .padding({ left: 10, right: 10, top: 6, bottom: 8 })
    .backgroundColor('#F8FAFC')
  }
}
