import { resolveSettingsTheme, SettingsThemeTokens } from './SettingsTheme';

// A navigation-only guard lets a detail keep its existing unsaved-changes dialog.
export type SettingsLeaveGuard = (proceed: () => void) => void;

@Component
export struct SettingsDetailHeader {
  @Prop title: string = '';
  @Prop theme: SettingsThemeTokens = resolveSettingsTheme(false);
  onBack: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Button('‹', { type: ButtonType.Normal }).fontSize(32).fontColor(this.theme.accent)
        .width(44).height(44).padding(0).borderRadius(14).backgroundColor(this.theme.pageBackground)
        .id('settings-back').accessibilityText('返回').onClick(this.onBack)
      Text(this.title).fontSize(21).fontWeight(FontWeight.Bold)
        .fontColor(this.theme.primaryText).layoutWeight(1)
    }.width('100%').padding({ left: 12, right: 20, top: 8, bottom: 8 })
  }
}

@Component
export struct SettingsChoiceChips {
  @Prop title: string = '';
  @Prop values: string[] = [];
  @Prop labels: string[] = [];
  @Prop currentValue: string = '';
  @Prop primaryTextColor: string = '#18212F';
  @Prop secondaryTextColor: string = '#657080';
  @Prop chipBackground: string = '#EEF1F5';
  @Prop selectedChipBackground: string = '#DCEBFF';
  @Prop accentColor: string = '#0A59F7';
  onValueChange: (value: string) => void = () => {};

  build() {
    Column({ space: 10 }) {
      Text(this.title).fontSize(14).fontColor(this.secondaryTextColor)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.values, (value: string, index: number) => {
          Button(this.labels[index], { type: ButtonType.Normal }).height(40)
            .padding({ left: 14, right: 14 }).margin({ right: 8, bottom: 8 }).borderRadius(12)
            .fontSize(14).fontColor(value === this.currentValue ? this.accentColor : this.primaryTextColor)
            .backgroundColor(value === this.currentValue ? this.selectedChipBackground : this.chipBackground)
            .id('settings-choice-' + value)
            .onClick((): void => { if (value !== this.currentValue) this.onValueChange(value); })
        }, (value: string): string => value)
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
