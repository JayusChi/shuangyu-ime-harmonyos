import { describe, expect, it } from '@ohos/hypium';
import { transformDirectText } from '../main/ets/domain/keyboard/DirectTextTransformer';
import { PunctuationMode } from '../main/ets/domain/settings/ImeSettings';

export default function directTextTransformerTest() {
  describe('DirectTextTransformer', () => {
    it('switches only the approved punctuation set to English', 0, () => {
      expect(transformDirectText('。', PunctuationMode.ENGLISH, false)).assertEqual('.');
      expect(transformDirectText('，', PunctuationMode.ENGLISH, false)).assertEqual(',');
      expect(transformDirectText('、', PunctuationMode.ENGLISH, false)).assertEqual('、');
    });

    it('converts only digits letters and space to full width', 0, () => {
      expect(transformDirectText('A', PunctuationMode.CHINESE, true)).assertEqual('Ａ');
      expect(transformDirectText('z', PunctuationMode.CHINESE, true)).assertEqual('ｚ');
      expect(transformDirectText('0', PunctuationMode.CHINESE, true)).assertEqual('０');
      expect(transformDirectText(' ', PunctuationMode.CHINESE, true)).assertEqual('　');
      expect(transformDirectText('.', PunctuationMode.CHINESE, true)).assertEqual('.');
    });
  });
}
