import { router } from '@kit.ArkUI';

@Entry
@Component
struct DebugIndex {
  build() {
    Column({ space: 18 }) {
      Text('内部 Debug 工具')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .width('100%')
      Button('设置')
        .width('100%')
        .onClick(() => router.pushUrl({ url: 'pages/Index' }))
      Button('调试与验收')
        .width('100%')
        .onClick(() => router.pushUrl({ url: 'pages/DebugStage10' }))
      Text('执行输入框、布局、Shift 与回车动作验收。')
        .fontSize(13)
        .fontColor('#6B7280')
        .width('100%')
      Button('码表运行时验收')
        .width('100%')
        .onClick(() => router.pushUrl({ url: 'pages/DebugCodeTable' }))
      Button('11.6.7 编辑器 A-N')
        .width('100%')
        .onClick(() => router.pushUrl({ url: 'pages/DebugStage1167Editor' }))
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 56 })
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }
}
