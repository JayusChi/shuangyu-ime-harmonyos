import { describe, it, expect } from '@ohos/hypium';
import {
  isAvailableScheme,
  DEFAULT_SCHEME_ID,
  QUANPIN_SCHEME_ID,
  PINYIN_9_SCHEME_ID,
  XIAOHE_YINXING_SCHEME_ID,
  AVAILABLE_SHUANGPIN_SCHEMES
} from '../main/ets/domain/settings/ImeSettings';

export default function schemeSwitchTest() {
  describe('Scheme availability', () => {
    it('should recognize xiaohe as available', 0, () => {
      expect(isAvailableScheme(DEFAULT_SCHEME_ID)).assertTrue();
    });

    it('should recognize xiaohe-yinxing as available', 0, () => {
      expect(isAvailableScheme(XIAOHE_YINXING_SCHEME_ID)).assertTrue();
    });

    it('should recognize quanpin as available', 0, () => {
      expect(isAvailableScheme(QUANPIN_SCHEME_ID)).assertTrue();
    });

    it('should recognize pinyin-9 as available', 0, () => {
      expect(isAvailableScheme(PINYIN_9_SCHEME_ID)).assertTrue();
    });

    it('should reject unknown scheme IDs', 0, () => {
      expect(isAvailableScheme('unknown')).assertFalse();
      expect(isAvailableScheme('')).assertFalse();
      expect(isAvailableScheme('xiaohe-fixture')).assertFalse();
    });

    it('should have exactly four available schemes', 0, () => {
      expect(AVAILABLE_SHUANGPIN_SCHEMES.length).assertEqual(4);
    });

    it('should list xiaohe first', 0, () => {
      expect(AVAILABLE_SHUANGPIN_SCHEMES[0].id).assertEqual(DEFAULT_SCHEME_ID);
      expect(AVAILABLE_SHUANGPIN_SCHEMES[0].displayName).assertEqual('小鹤双拼');
    });

    it('should list quanpin, pinyin-9, and xiaohe-yinxing in product order', 0, () => {
      expect(AVAILABLE_SHUANGPIN_SCHEMES[1].id).assertEqual(QUANPIN_SCHEME_ID);
      expect(AVAILABLE_SHUANGPIN_SCHEMES[1].displayName).assertEqual('26 键全拼');
      expect(AVAILABLE_SHUANGPIN_SCHEMES[2].id).assertEqual(PINYIN_9_SCHEME_ID);
      expect(AVAILABLE_SHUANGPIN_SCHEMES[2].displayName).assertEqual('9 键拼音');
      expect(AVAILABLE_SHUANGPIN_SCHEMES[3].id).assertEqual(XIAOHE_YINXING_SCHEME_ID);
      expect(AVAILABLE_SHUANGPIN_SCHEMES[3].displayName).assertEqual('小鹤音形');
    });
  });

  describe('Scheme constants', () => {
    it('should have stable xiaohe scheme ID', 0, () => {
      expect(DEFAULT_SCHEME_ID).assertEqual('xiaohe');
    });

    it('should have stable xiaohe-yinxing scheme ID', 0, () => {
      expect(XIAOHE_YINXING_SCHEME_ID).assertEqual('xiaohe-yinxing');
    });

    it('should have stable quanpin scheme ID', 0, () => {
      expect(QUANPIN_SCHEME_ID).assertEqual('quanpin');
    });

    it('should have stable pinyin-9 scheme ID', 0, () => {
      expect(PINYIN_9_SCHEME_ID).assertEqual('pinyin-9');
    });
  });
}
