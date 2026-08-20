import {
  Stage1167DeviceCommand,
  Stage1167DeviceCommandBus
} from '../infrastructure/Stage1167DeviceCommandBus';

@Entry
@Component
struct DebugStage1167Editor {
  @State private modeStatus: string = '音形 fixture · 默认分类';
  private readonly deviceCommandBus: Stage1167DeviceCommandBus = new Stage1167DeviceCommandBus();

  @Builder
  private AcceptanceInput(label: string, placeholder: string) {
    Column({ space: 5 }) {
      Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#101828')
      TextInput({ placeholder })
        .type(InputType.Normal)
        .width('100%')
        .height(46)
        .fontSize(16)
        .backgroundColor('#F2F4F7')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private async publish(command: Stage1167DeviceCommand, successText: string): Promise<void> {
    this.modeStatus = await this.deviceCommandBus.publish(command)
      ? successText
      : 'internalDebug 命令发送失败';
  }

  private async applyAllCategories(): Promise<void> {
    await this.publish('ALL_CATEGORIES', '音形 fixture · 全分类命令已发送');
  }

  private async applyCoreCategory(): Promise<void> {
    await this.publish('CORE_ONLY', '音形 fixture · 仅 core 命令已发送');
  }

  private async applyXiaohe(): Promise<void> {
    await this.publish('XIAOHE', 'xiaohe 命令已发送');
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text('阶段 11.6.7 · 独立 TextInput A–N')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#101828')
        Text('仅 internalDebug；每格均由真实输入法 Extension 写入。')
          .fontSize(13)
          .fontColor('#667085')
        Text(this.modeStatus).fontSize(13).fontColor('#175CD3')
        Row({ space: 8 }) {
          Button('音形全分类')
            .focusable(false)
            .onClick(async () => await this.applyAllCategories())
          Button('音形仅 core')
            .focusable(false)
            .onClick(async () => await this.applyCoreCategory())
        }
        .width('100%')
        Button('切回 xiaohe')
          .focusable(false)
          .onClick(async () => await this.applyXiaohe())

        this.AcceptanceInput('A 三码唯一不自动提交', '11.6.7-A')
        this.AcceptanceInput('B 四码唯一自动提交', '11.6.7-B')
        this.AcceptanceInput('C 四码多候选保留', '11.6.7-C')
        this.AcceptanceInput('D 唯一但有后续码不提交', '11.6.7-D')
        this.AcceptanceInput('E 第五码顶屏且新键一次', '11.6.7-E')
        this.AcceptanceInput('F 旧段无候选仍保留新键', '11.6.7-F')
        this.AcceptanceInput('G 用户删除改变唯一性', '11.6.7-G')
        this.AcceptanceInput('H 用户固顶改变首选', '11.6.7-H')
        this.AcceptanceInput('I 分类更新本身不提交', '11.6.7-I')
        this.AcceptanceInput('J 空码正向切分', '11.6.7-J')
        this.AcceptanceInput('K 空码反向切分', '11.6.7-K')
        this.AcceptanceInput('L 无合法切分安全清理', '11.6.7-L')
        this.AcceptanceInput('M Guide 状态隔离', '11.6.7-M')
        this.AcceptanceInput('N 切回 xiaohe 回归', '11.6.7-N')
      }
      .width('100%')
      // Keep the final TextInput scrollable above the IME panel so external
      // device automation can focus and inspect N on 2880px emulator screens.
      .padding({ left: 20, right: 20, top: 44, bottom: 420 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
