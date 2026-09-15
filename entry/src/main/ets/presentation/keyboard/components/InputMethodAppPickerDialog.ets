import { InputMethodAppOption, InputMethodAppPicker } from '../../../application/InputMethodAppPicker';

@CustomDialog
export struct InputMethodAppPickerDialog {
  controller: CustomDialogController;
  private readonly picker: InputMethodAppPicker = new InputMethodAppPicker();
  @State private options: InputMethodAppOption[] = [];
  @State private loading: boolean = true;
  @State private switching: boolean = false;
  @State private errorMessage: string = '';

  aboutToAppear(): void {
    this.loadApplications();
  }

  aboutToDisappear(): void {
    this.picker.close();
  }

  private async loadApplications(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      const options = await this.picker.load();
      if (this.picker.isActive()) {
        this.options = options;
        if (options.length === 0) {
          this.errorMessage = '暂无已启用的输入法';
        }
      }
    } catch (_) {
      if (this.picker.isActive()) {
        this.errorMessage = '无法读取输入法列表，请重试';
      }
    } finally {
      if (this.picker.isActive()) {
        this.loading = false;
      }
    }
  }

  private async selectApplication(option: InputMethodAppOption): Promise<void> {
    if (this.switching) {
      return;
    }
    this.switching = true;
    this.errorMessage = '';
    const success = await this.picker.select(option.name);
    if (!this.picker.isActive()) {
      return;
    }
    this.switching = false;
    if (success) {
      this.dismiss();
    } else {
      this.errorMessage = '无法切换输入法，请重试';
    }
  }

  private dismiss(): void {
    this.picker.close();
    this.controller.close();
  }

  build() {
    Column({ space: 8 }) {
      Text('选择输入法')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 8 })
      if (this.loading) {
        LoadingProgress().width(32).height(32).margin(16)
      } else {
        List() {
          ForEach(this.options, (option: InputMethodAppOption) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(option.label)
                  .fontSize(18)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  .layoutWeight(1)
                if (option.current) {
                  Text('当前')
                    .fontSize(14)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                }
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .enabled(!this.switching)
              .accessibilityText(option.current ? `${option.label}，当前输入法` : option.label)
              .id(`system-input-method-app:${option.name}`)
              .onClick((): void => { this.selectApplication(option); })
            }
          }, (option: InputMethodAppOption): string => option.name)
        }
        .width('100%')
        .constraintSize({ maxHeight: 280 })
        .edgeEffect(EdgeEffect.Spring)
      }
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .padding({ left: 16, right: 16 })
        Button('重试').onClick((): void => { this.loadApplications(); })
      }
      Button('取消')
        .width('100%')
        .margin({ top: 8 })
        .onClick((): void => this.dismiss())
    }
    .padding(12)
    .width('100%')
    .id('system-input-method-app-picker')
  }
}
