import { describe, expect, it } from '@ohos/hypium';
import { clipboardReverseCharacter } from '../main/ets/domain/direct/ClipboardReverseLookup';
import { ClipboardReverseLookupService } from '../main/ets/application/ClipboardReverseLookupService';
import { ShapeLookupClipboardReader } from '../main/ets/infrastructure/clipboard/ShapeLookupClipboard';

class FakeReverseClipboard implements ShapeLookupClipboardReader {
  text?: string;
  constructor(text?: string) { this.text = text; }
  async readText(): Promise<string | undefined> { return this.text; }
}

export default function clipboardReverseLookupTest() {
  describe('ClipboardReverseLookup', () => {
    it('accepts one complete Han scalar with surrounding whitespace', 0, () => {
      expect(clipboardReverseCharacter(' 你\n')).assertEqual('你');
      expect(clipboardReverseCharacter('𠮷')).assertEqual('𠮷');
      for (const value of ['', '你好', 'a', '123', '😀', '\ud840', '你a']) {
        expect(clipboardReverseCharacter(value)).assertEqual('');
      }
    });
    it('queries only copied single characters and keeps all returned codes', 0, async () => {
      const clipboard = new FakeReverseClipboard('你');
      const service = new ClipboardReverseLookupService(clipboard);
      const queried: string[] = [];
      const lookup = (text: string): string[] => { queried.push(text); return ['nirx', 'ni']; };
      expect((await service.resolve(lookup)).text).assertEqual('nirx ni');
      for (const value of ['', '你好', 'ofi', '😀']) {
        clipboard.text = value;
        const result = await service.resolve(lookup);
        expect(result.text).assertEqual('');
        expect(result.available).assertTrue();
      }
      expect(queried.join(',')).assertEqual('你');
    });
    it('distinguishes denied clipboard access from no dictionary match', 0, async () => {
      const denied = await new ClipboardReverseLookupService(new FakeReverseClipboard()).resolve((): string[] => []);
      expect(denied.available).assertFalse();
      expect(denied.text).assertEqual('');
      const unknown = await new ClipboardReverseLookupService(new FakeReverseClipboard('龘')).resolve((): string[] => []);
      expect(unknown.available).assertTrue();
      expect(unknown.text).assertEqual('');
    });
  });
}
