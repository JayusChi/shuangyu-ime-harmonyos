@Component
export struct ClipboardReversePasteButton {
  onPaste?: () => void;

  build() {
    PasteButton()
      .fontSize(14)
      .onClick((_event: ClickEvent, result: PasteButtonOnClickResult): void => {
        if (result === PasteButtonOnClickResult.SUCCESS) {
          this.onPaste?.();
        } else {
          this.getUIContext().getPromptAction().showToast({ message: '粘贴未获授权，请重新点击粘贴' });
        }
      })
  }
}
