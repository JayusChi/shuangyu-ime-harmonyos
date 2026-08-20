import { hilog } from '@kit.PerformanceAnalysisKit';
import { Stage0DemoController } from './Stage0DemoController';

const DOMAIN = 0x0000;
const TAG = 'Stage0Keyboard';

@Entry
@Component
struct Stage0Keyboard {
  private readonly controller: Stage0DemoController = new Stage0DemoController();

  @State private engineVersion: string = '';
  @State private statusMessage: string = 'Stage 0 ready';

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Stage0 keyboard page appeared');
    this.engineVersion = this.controller.getEngineVersion();
  }

  private async deleteBackward(): Promise<void> {
    const deleted = await this.controller.deleteBackward();
    this.statusMessage = deleted ? 'Delete sent' : 'Delete failed';
  }

  @Builder
  private KeyButton(label: string, action: () => void) {
    Button(label)
      .height(28)
      .layoutWeight(1)
      .fontSize(11)
      .borderRadius(4)
      .onClick(action)
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        Text(`Rust ${this.engineVersion === '' ? 'not loaded' : this.engineVersion}`)
          .fontSize(10)
          .fontColor('#182431')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.statusMessage)
          .fontSize(10)
          .fontColor('#4E5969')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(18)
      .justifyContent(FlexAlign.SpaceBetween)

      Row({ space: 4 }) {
        this.KeyButton('A', () => {
          this.controller.insertLetter('a');
        })
        this.KeyButton('B', () => {
          this.controller.insertLetter('b');
        })
      }
      .width('100%')

      Row({ space: 4 }) {
        this.KeyButton('删除', () => {
          this.deleteBackward();
        })
        this.KeyButton('空格', () => {
          this.controller.insertSpace();
        })
        this.KeyButton('回车', () => {
          this.controller.sendEnter();
        })
        this.KeyButton('隐藏键盘', () => {
          this.controller.hideKeyboard();
        })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor('#F6F8FA')
  }
}
