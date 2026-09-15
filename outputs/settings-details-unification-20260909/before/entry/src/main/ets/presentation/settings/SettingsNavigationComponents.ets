import { resolveSettingsTheme, SettingsThemeTokens } from './SettingsTheme';

/** Presentation-only rows; mutations remain in the existing settings controller. */
@Component
export struct SettingsNavigationRow {
  @Prop title: string = '';
  @Prop description: string = '';
  @Prop value: string = '';
  @Prop marker: string = '';
  @Prop selected: boolean = false;
  @Prop disabled: boolean = false;
  @Prop controlId: string = '';
  @Prop theme: SettingsThemeTokens = resolveSettingsTheme(false);
  onOpen: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        if (this.marker.length > 0) {
          Text(this.marker).fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor(this.theme.accent).textAlign(TextAlign.Center)
            .width(34).height(34).borderRadius(11)
            .backgroundColor(this.theme.selectedChipBackground)
        }
        Column({ space: 5 }) {
          Text(this.title).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(this.theme.primaryText).width('100%')
          if (this.description.length > 0) {
            Text(this.description).fontSize(12).fontColor(this.theme.secondaryText).width('100%')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.value.length > 0) {
          Text(this.value).fontSize(13).fontColor(this.theme.secondaryText)
            .constraintSize({ maxWidth: '40%' }).textAlign(TextAlign.End)
        }
        Text('›').fontSize(24).fontColor(this.theme.secondaryText)
      }.width('100%').padding({ left: 16, right: 16, top: 17, bottom: 17 })
    }
    .id(this.controlId)
    .width('100%')
    .constraintSize({ minHeight: 66 })
    .backgroundColor(this.selected ? this.theme.selectedChipBackground : this.theme.cardBackground)
    .borderRadius(0).enabled(!this.disabled).onClick(this.onOpen)
  }
}

@Component
export struct SettingsOptionList {
  @Prop values: string[] = [];
  @Prop labels: string[] = [];
  @Prop descriptions: string[] = [];
  @Prop currentValue: string = '';
  @Prop theme: SettingsThemeTokens = resolveSettingsTheme(false);
  @Prop disabled: boolean = false;
  onValueChange: (value: string) => void = () => {};

  build() {
    Column() {
      ForEach(this.values, (value: string, index: number) => {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 14 }) {
            Column({ space: 5 }) {
              Text(this.labels[index]).fontSize(16).fontColor(this.theme.primaryText).width('100%')
              if (this.descriptions[index]) {
                Text(this.descriptions[index]).fontSize(12).fontColor(this.theme.secondaryText).width('100%')
              }
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text(value === this.currentValue ? '●' : '○').fontSize(22)
              .fontColor(value === this.currentValue ? this.theme.accent : this.theme.secondaryText)
          }.width('100%').padding(17)
        }
        .id(`settings-option-${value}`)
        .accessibilityText(`${this.labels[index]}${value === this.currentValue ? '，已选择' : ''}`)
        .width('100%').constraintSize({ minHeight: 58 }).borderRadius(0)
        .backgroundColor(this.theme.cardBackground).enabled(!this.disabled)
        .onClick(() => {
          if (value !== this.currentValue) this.onValueChange(value);
        })
        if (index < this.values.length - 1) {
          Divider().color(this.theme.divider).margin({ left: 17, right: 17 })
        }
      }, (value: string) => value)
    }.width('100%').borderRadius(18).clip(true).backgroundColor(this.theme.cardBackground)
  }
}

@Component
export struct SettingsAdjustmentRow {
  @Prop title: ResourceStr = '';
  @Prop description: string = '';
  @Prop @Watch('syncPreview') value: number = 0;
  @Prop min: number = 0;
  @Prop max: number = 100;
  @Prop step: number = 1;
  @Prop decimals: number = 0;
  @Prop suffix: string = '';
  @Prop theme: SettingsThemeTokens = resolveSettingsTheme(false);
  @State private preview: number = 0;
  onValueChange: (value: number) => void = () => {};
  onPreview: (value: number) => void = () => {};

  aboutToAppear(): void { this.syncPreview(); }
  private syncPreview(): void { this.preview = this.value; }
  private adjust(direction: number): void {
    const next = Number(Math.max(this.min, Math.min(this.max, this.value + direction * this.step))
      .toFixed(this.decimals));
    if (next !== this.value) {
      this.preview = next;
      this.onPreview(next);
      this.onValueChange(next);
    }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text(this.title).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(this.theme.primaryText).layoutWeight(1)
        Text(`${this.preview.toFixed(this.decimals)}${this.suffix}`)
          .fontSize(14).fontColor(this.theme.accent)
      }.width('100%')
      Row({ space: 8 }) {
        Button('−', { type: ButtonType.Normal }).width(40).height(40).padding(0).borderRadius(11)
          .fontSize(22).fontColor(this.theme.accent).backgroundColor(this.theme.chipBackground)
          .enabled(this.value > this.min).accessibilityText('减小')
          .onClick(() => this.adjust(-1))
        Slider({ value: this.preview, min: this.min, max: this.max, step: this.step })
          .selectedColor(this.theme.accent).layoutWeight(1)
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.preview = Number(value.toFixed(this.decimals));
            this.onPreview(this.preview);
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.onValueChange(this.preview);
            }
          })
        Button('＋', { type: ButtonType.Normal }).width(40).height(40).padding(0).borderRadius(11)
          .fontSize(20).fontColor(this.theme.accent).backgroundColor(this.theme.chipBackground)
          .enabled(this.value < this.max).accessibilityText('增大')
          .onClick(() => this.adjust(1))
      }.width('100%')
      if (this.description.length > 0) {
        Text(this.description).fontSize(12).fontColor(this.theme.secondaryText).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct SettingsCandidatePreview {
  @Prop floating: boolean = false;
  @Prop fontSize: number = 15;
  @Prop theme: SettingsThemeTokens = resolveSettingsTheme(false);

  @Builder
  private CandidateWords() {
    Row({ space: 18 }) {
      Text('看看').fontSize(this.fontSize).fontColor(this.theme.accent)
      Text('看见').fontSize(this.fontSize).fontColor(this.theme.primaryText)
      Text('看书').fontSize(this.fontSize).fontColor(this.theme.primaryText)
    }.padding(12).constraintSize({ maxWidth: '100%' })
  }

  @Builder
  private KeyRow(letters: string[]) {
    Row({ space: 4 }) {
      ForEach(letters, (letter: string) => {
        Text(letter).fontSize(12).fontColor(this.theme.primaryText).textAlign(TextAlign.Center)
          .height(30).layoutWeight(1).borderRadius(5).backgroundColor(this.theme.cardBackground)
      }, (letter: string) => letter)
    }.width('100%')
  }

  build() {
    Column({ space: 10 }) {
      Text('效果预览').fontSize(12).fontColor(this.theme.secondaryText).width('100%')
      Text('今天想去看│').fontSize(15).fontColor(this.theme.primaryText).width('100%')
        .padding(12).backgroundColor(this.theme.pageBackground).borderRadius(10)
      if (this.floating) {
        Column() { this.CandidateWords() }
          .border({ width: 1, color: this.theme.divider }).borderRadius(10)
      }
      Column({ space: 5 }) {
        if (!this.floating) { this.CandidateWords() }
        this.KeyRow(['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'])
        this.KeyRow(['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'])
        this.KeyRow(['⇧', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '⌫'])
      }.width('100%').padding(8).borderRadius(12).backgroundColor(this.theme.chipBackground)
    }.width('100%').padding(16).borderRadius(18).backgroundColor(this.theme.cardBackground)
      .alignItems(HorizontalAlign.Start).accessibilityText('候选位置和字号示意，非输入区域')
  }
}
