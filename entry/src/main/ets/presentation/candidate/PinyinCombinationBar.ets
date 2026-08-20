import { KeyboardColorPalette, LIGHT_PALETTE } from '../keyboard/design/KeyboardPalette';

export interface PinyinCombinationOption {
  text: string;
  combinationIndex: number;
  selected: boolean;
}

/** Preserves Rust publication order exactly; ArkTS does not sort or infer. */
export function buildPinyinCombinationOptions(
  currentPinyin: string,
  pinyinCombinations: string[]
): PinyinCombinationOption[] {
  const options: PinyinCombinationOption[] = [];
  if (currentPinyin.length > 0) {
    options.push({ text: currentPinyin, combinationIndex: 0, selected: true });
  }
  pinyinCombinations.forEach((text: string, index: number): void => {
    options.push({ text, combinationIndex: index + 1, selected: false });
  });
  return options;
}

@Component
export struct PinyinCombinationBar {
  @Prop palette: KeyboardColorPalette = LIGHT_PALETTE;
  @Prop currentPinyin: string = '';
  @Prop pinyinCombinations: string[] = [];
  @Prop barHeight: number = 34;

  onCombinationClick?: (combinationIndex: number) => void;
  private scroller: Scroller = new Scroller();

  build() {
    Row({ space: 6 }) {
      Text('拼音')
        .fontSize(10)
        .fontColor(this.palette.candidateReading)
        .fontWeight(FontWeight.Medium)
        .padding({ left: 8 })
        .accessibilityText('拼音组合')

      Scroll(this.scroller) {
        Row({ space: 6 }) {
          ForEach(
            buildPinyinCombinationOptions(this.currentPinyin, this.pinyinCombinations),
            (option: PinyinCombinationOption) => {
              Text(option.text)
                .fontSize(12)
                .fontColor(option.selected ? this.palette.modeKeyTextEnglish : this.palette.candidateText)
                .fontWeight(option.selected ? FontWeight.Bold : FontWeight.Medium)
                .maxLines(1)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .borderRadius(4)
                .backgroundColor(option.selected
                  ? this.palette.modeKeyBackgroundEnglish
                  : this.palette.candidateBackground)
                .accessibilityText(`拼音 ${option.text}${option.selected ? '，已选择' : ''}`)
                .onClick((): void => this.onCombinationClick?.(option.combinationIndex))
            },
            (option: PinyinCombinationOption) => `${option.combinationIndex}-${option.text}`
          )
        }
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ right: 8 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height(this.barHeight)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.palette.candidateBackground)
    .border({ width: { bottom: 1 }, color: this.palette.candidateDivider })
    .accessibilityText(`当前拼音 ${this.currentPinyin}`)
  }
}
