import { shapeLookupCharacter, shapeLookupCursorCharacter, shapeLookupUrl } from '../domain/direct/ShapeLookup';
import { ShapeLookupClipboard, ShapeLookupClipboardReader } from '../infrastructure/clipboard/ShapeLookupClipboard';
import { DirectAbilityLauncher } from './DirectSessionActionService';
import { directWebWant } from './DirectWebWant';

export class ShapeLookupService {
  private readonly clipboard: ShapeLookupClipboardReader;
  constructor(clipboard: ShapeLookupClipboardReader = new ShapeLookupClipboard()) { this.clipboard = clipboard; }

  async resolve(before: string, preview: string, previewActive: boolean): Promise<string> {
    const character = shapeLookupCursorCharacter(before, preview, previewActive);
    if (character.length > 0) { return character; }
    return shapeLookupCharacter((await this.clipboard.readText()) ?? '', false);
  }

  /** Read immediately after a successful system PasteButton click; no restricted permission request. */
  async openClipboard(launcher: DirectAbilityLauncher, pasteAuthorized: boolean): Promise<boolean> {
    if (!pasteAuthorized) { return false; }
    const text = await this.clipboard.readText();
    const url = shapeLookupUrl(shapeLookupCharacter(text ?? '', false));
    if (url === undefined) { return false; }
    await launcher.startAbility(directWebWant(url));
    return true;
  }
}
