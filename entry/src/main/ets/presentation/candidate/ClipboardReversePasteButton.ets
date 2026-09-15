import { CLIPBOARD_REVERSE_PASTE_WIDTH } from '../../domain/direct/ClipboardReverseLookup';

@Component
export struct ClipboardReversePasteButton {
  onPaste?: () => void;

  build() {
    PasteButton()
      .width(CLIPBOARD_REVERSE_PASTE_WIDTH)
      .height(36)
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
