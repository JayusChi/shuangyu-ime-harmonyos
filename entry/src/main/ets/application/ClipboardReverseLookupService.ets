import { clipboardReverseCharacter, ClipboardReverseLookupResult } from '../domain/direct/ClipboardReverseLookup';
import { ShapeLookupClipboard, ShapeLookupClipboardReader } from '../infrastructure/clipboard/ShapeLookupClipboard';

export class ClipboardReverseLookupService {
  private readonly clipboard: ShapeLookupClipboardReader;

  constructor(clipboard: ShapeLookupClipboardReader = new ShapeLookupClipboard()) {
    this.clipboard = clipboard;
  }

  async resolve(lookup: (character: string) => string[]): Promise<ClipboardReverseLookupResult> {
    const copied = await this.clipboard.readText();
    const character = clipboardReverseCharacter(copied ?? '');
    const codes = character.length > 0 ? lookup(character) : [];
    return { available: copied !== undefined, character, text: codes.join(' ') };
  }
}
