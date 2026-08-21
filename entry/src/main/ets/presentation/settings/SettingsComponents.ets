@Component
export struct ChoiceSettingRow {
  @Prop title: ResourceStr = '';
  @Prop description: ResourceStr = '';
  @Prop values: string[] = [];
  @Prop labels: string[] = [];
  @Prop disabledValues: string[] = [];
  @Prop currentValue: string = '';
  @Prop primaryTextColor: string = '#18212F';
  @Prop secondaryTextColor: string = '#657080';
  @Prop chipBackground: string = '#EEF1F5';
  @Prop selectedChipBackground: string = '#DCEBFF';
  @Prop accentColor: string = '#0A59F7';
  onValueChange?: (value: string) => void;

  private isDisabled(value: string): boolean {
    return this.disabledValues.indexOf(value) >= 0;
  }

  build() {
    Column({ space: 9 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor)
        .width('100%')
      if (this.description) {
        Text(this.description)
          .fontSize(12)
          .fontColor(this.secondaryTextColor)
          .width('100%')
      }
      Row({ space: 8 }) {
        ForEach(this.values, (value: string, index: number) => {
          Text(this.labels[index])
            .fontSize(13)
            .fontColor(value === this.currentValue ? this.accentColor : this.primaryTextColor)
            .fontWeight(value === this.currentValue ? FontWeight.Medium : FontWeight.Regular)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(38)
            .borderRadius(10)
            .enabled(!this.isDisabled(value))
            .opacity(this.isDisabled(value) ? 0.45 : 1)
            .backgroundColor(value === this.currentValue
              ? this.selectedChipBackground
              : this.chipBackground)
            .onClick(() => {
              if (this.isDisabled(value)) {
                return;
              }
              if (value !== this.currentValue && this.onValueChange) {
                this.onValueChange(value);
              }
            })
        }, (value: string) => value)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct SwitchSettingRow {
  @Prop title: ResourceStr = '';
  @Prop description: ResourceStr = '';
  @Prop checked: boolean = false;
  @Prop primaryTextColor: string = '#18212F';
  @Prop secondaryTextColor: string = '#657080';
  @Prop disabled: boolean = false;
  onCheckedChange?: (checked: boolean) => void;

  build() {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor)
        if (this.description) {
          Text(this.description)
            .fontSize(12)
            .fontColor(this.secondaryTextColor)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .enabled(!this.disabled)
        .opacity(this.disabled ? 0.55 : 1)
        .onChange((checked: boolean) => {
          if (!this.disabled && this.onCheckedChange) {
            this.onCheckedChange(checked);
          }
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct CodeTableCategorySettingRow {
  @Prop categoryId: string = '';
  @Prop displayName: string = '';
  @Prop kind: string = '';
  @Prop order: number = 0;
  @Prop checked: boolean = false;
  @Prop required: boolean = false;
  @Prop userToggleable: boolean = true;
  @Prop busy: boolean = false;
  onCheckedChange?: (checked: boolean) => void;

  build() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(`${this.order}. ${this.displayName}`)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#18212F')
        Text(`${this.categoryId} · ${this.kind}${this.required ? ' · required' : ''}`)
          .fontSize(11)
          .fontColor('#657080')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .enabled(this.userToggleable && !this.required && !this.busy)
        .opacity(this.userToggleable && !this.required ? 1 : 0.55)
        .onChange((checked: boolean) => {
          if (this.userToggleable && !this.required && !this.busy && this.onCheckedChange) {
            this.onCheckedChange(checked);
          }
        })
    }
    .width('100%')
    .padding({ top: 9, bottom: 9 })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct ActionSettingRow {
  @Prop title: ResourceStr = '';
  @Prop description: ResourceStr = '';
  @Prop primaryTextColor: string = '#18212F';
  @Prop secondaryTextColor: string = '#657080';
  @Prop actionColor: string = '#0A59F7';
  @Prop disabled: boolean = false;
  onAction?: () => void;

  build() {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.actionColor)
        Text(this.description)
          .fontSize(12)
          .fontColor(this.secondaryTextColor)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(24)
        .fontColor(this.secondaryTextColor)
    }
    .width('100%')
    .opacity(this.disabled ? 0.45 : 1)
    .onClick(() => {
      if (!this.disabled && this.onAction) {
        this.onAction();
      }
    })
  }
}
