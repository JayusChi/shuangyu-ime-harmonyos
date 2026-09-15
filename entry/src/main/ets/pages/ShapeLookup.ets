import { common, Want } from '@kit.AbilityKit';
import { DirectAbilityLauncher } from '../application/DirectSessionActionService';
import { ShapeLookupService } from '../application/ShapeLookupService';

class ShapeLookupAbilityLauncher implements DirectAbilityLauncher {
  private readonly context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async startAbility(want: Want): Promise<void> {
    await this.context.startAbility(want);
  }
}

@Entry
@Component
struct ShapeLookup {
  @State private opening: boolean = false;

  private pasteAndLookup(result: PasteButtonOnClickResult): void {
    if (this.opening) { return; }
    if (result !== PasteButtonOnClickResult.SUCCESS) {
      this.getUIContext().getPromptAction().showToast({ message: '粘贴未获授权，请重新点击粘贴' });
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.opening = true;
    // The native security component grants temporary access for this explicit click.
    new ShapeLookupService().openClipboard(new ShapeLookupAbilityLauncher(context), true)
      .then((opened: boolean): void => {
        if (!opened) {
          this.getUIContext().getPromptAction().showToast({ message: '请先复制一个汉字，再点击粘贴' });
        }
      }).catch((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '查形网页暂时无法打开，请稍后重试' });
      }).finally((): void => { this.opening = false; });
  }

  build() {
    Column({ space: 24 }) {
      Text('粘贴查形')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Text('点击粘贴，将复制内容开头的一个汉字带到小鹤查形网页。')
        .fontSize(16)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 360 })
      PasteButton()
        .onClick((_event: ClickEvent, result: PasteButtonOnClickResult): void => {
          this.pasteAndLookup(result);
        })
      Button('返回设置')
        .onClick((): void => {
          this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' }).catch((): void => {});
        })
    }
    .width('100%')
    .height('100%')
    .padding(32)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.ohos_id_color_background'))
  }
}
