import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { isFlypyWebTarget } from '../domain/direct/FlypyWebTarget';
import { isExternalDirectTarget } from '../domain/direct/ExternalDirectTarget';

@Entry({ useSharedStorage: true })
@Component
struct FlypyWeb {
  @LocalStorageLink('flypyWebUrl') private url: string = '';
  @LocalStorageLink('flypyWebRequest') @Watch('reloadRequest') private request: number = 0;
  @State private progress: number = 0;
  @State private failed: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private attached: boolean = false;

  private close(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.terminateSelf().catch((): void => {});
  }

  private back(): void {
    try {
      if (this.attached && this.controller.accessBackward()) { this.controller.backward(); return; }
    } catch (_) {}
    this.close();
  }

  onBackPress(): boolean { this.back(); return true; }

  private reloadRequest(): void {
    if (!this.attached || !isFlypyWebTarget(this.url)) { return; }
    this.failed = false;
    this.progress = 0;
    try { this.controller.loadUrl(this.url); }
    catch (_) { this.failed = true; }
  }

  private intercept(request: WebResourceRequest): boolean {
    const url = request.getRequestUrl();
    if (isFlypyWebTarget(url)) { return false; }
    // Dictionary links open only after a user gesture, with ordinary OS URL routing.
    if (request.isMainFrame() && request.isRequestGesture() && isExternalDirectTarget('url.open', url)) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.startAbility({ action: 'ohos.want.action.viewData', uri: url }).catch((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '链接暂时无法打开' });
      });
    }
    return true;
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('返回').onClick((): void => { this.back(); })
        Column({ space: 2 }) {
          Text(this.url.includes('/ix/') ? '小鹤查形' : '小鹤官网')
            .fontSize(18).fontWeight(FontWeight.Medium).maxLines(1)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
          Text('flypy.cc').fontSize(12).fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }.layoutWeight(1)
        Button('刷新').onClick((): void => { this.reloadRequest(); })
        Button('关闭').onClick((): void => { this.close(); })
      }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
      if (this.progress < 100 && !this.failed) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear }).width('100%').height(2)
      }
      Stack() {
        Web({ src: this.url, controller: this.controller })
          .width('100%').height('100%')
          .javaScriptAccess(true).domStorageAccess(true).fileAccess(false)
          .onControllerAttached((): void => { this.attached = true; })
          .onLoadIntercept((event): boolean => { return this.intercept(event.data); })
          .onPageBegin((): void => { this.progress = 0; this.failed = false; })
          .onProgressChange((event): void => { this.progress = event.newProgress; })
          .onPageEnd((): void => { this.progress = 100; })
          .onErrorReceive((event): void => {
            if (event.request.isMainFrame()) { this.failed = true; }
          })
          .onHttpErrorReceive((event): void => {
            if (event.request.isMainFrame() && event.response.getResponseCode() >= 400) { this.failed = true; }
          })
          .onRenderExited((): void => { this.failed = true; })
        if (this.failed) {
          Column({ space: 16 }) {
            Text('查形网页暂时无法载入').fontSize(18)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
            Text('请检查网络连接后重试').fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            Button('重新载入').onClick((): void => { this.reloadRequest(); })
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
            .backgroundColor($r('sys.color.ohos_id_color_background'))
        }
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').backgroundColor($r('sys.color.ohos_id_color_background'))
  }
}
