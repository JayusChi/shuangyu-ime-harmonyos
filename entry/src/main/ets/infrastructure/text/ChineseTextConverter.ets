import { i18n } from '@kit.LocalizationKit';

export interface ChineseTextConverter {
  toTraditional(text: string): string;
}

export class SystemChineseTextConverter implements ChineseTextConverter {
  private converter?: i18n.Transliterator;
  private resolved: boolean = false;

  toTraditional(text: string): string {
    if (text.length === 0) {
      return text;
    }
    const converter = this.getConverter();
    if (converter === undefined) {
      return text;
    }
    try {
      return converter.transform(text);
    } catch (_err) {
      return text;
    }
  }

  private getConverter(): i18n.Transliterator | undefined {
    if (this.resolved) {
      return this.converter;
    }
    this.resolved = true;
    try {
      const available = i18n.Transliterator.getAvailableIDs();
      const approvedIds: string[] = ['Simplified-Traditional', 'Hans-Hant'];
      const id = approvedIds.find((value: string): boolean => available.indexOf(value) >= 0);
      if (id !== undefined) {
        this.converter = i18n.Transliterator.getInstance(id);
      }
    } catch (_err) {
      this.converter = undefined;
    }
    return this.converter;
  }
}
