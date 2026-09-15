import { pasteboard } from '@kit.BasicServicesKit';

export interface ShapeLookupClipboardReader {
  /** undefined means unavailable/permission denied; empty string means an empty non-text clipboard. */
  readText(): Promise<string | undefined>;
}

export class ShapeLookupClipboard implements ShapeLookupClipboardReader {
  async readText(): Promise<string | undefined> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      return data.getPrimaryText() ?? '';
    } catch (_) { return undefined; }
  }
}
