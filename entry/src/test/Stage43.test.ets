import { describe, it, expect } from '@ohos/hypium';
import {
  CompositionPreeditDecoration,
  formatTwoCodePreedit,
  resolveCompositionPreeditView
} from '../main/ets/domain/candidate/CompositionPreeditView';

export default function stage43Test() {
  describe('stage 4.3 two-code preedit display', () => {
    it('formats the customer example as six two-code segments', 0, () => {
      expect(formatTwoCodePreedit(
        'vegewtyijkjj',
        ['ve', 'ge', 'wt', 'yi', 'jk', 'jj']
      )).assertEqual("ve'ge'wt'yi'jk'jj");
    });

    it('keeps one complete two-code segment unchanged', 0, () => {
      expect(formatTwoCodePreedit('ve', ['ve'])).assertEqual('ve');
    });

    it('keeps an odd trailing key as the pending segment', 0, () => {
      expect(formatTwoCodePreedit('vegew', ['ve', 'ge', 'w'])).assertEqual("ve'ge'w");
    });

    it('uses engine boundaries without duplicating an existing separator', 0, () => {
      expect(formatTwoCodePreedit("ve'gewt", ['ve', 'ge', 'wt'])).assertEqual("ve'ge'wt");
    });

    it('uses engine segments when rawInput has no separator', 0, () => {
      expect(formatTwoCodePreedit('veg', ['ve', 'g'])).assertEqual("ve'g");
    });

    it('preserves a trailing explicit segment boundary', 0, () => {
      expect(formatTwoCodePreedit("ve'", ['ve'])).assertEqual("ve'");
    });

    it('preserves guide characters and groups the following letter run', 0, () => {
      expect(formatTwoCodePreedit(';rqab', [';rq', 'ab'])).assertEqual(";rq'ab");
    });

    it('does not guess segments when an old engine omits displaySegments', 0, () => {
      expect(formatTwoCodePreedit('vege')).assertEqual('vege');
    });

    it('empty input remains hidden', 0, () => {
      const view = resolveCompositionPreeditView({
        rawInput: '',
        preeditText: '',
        pendingCode: '',
        segmentBoundaries: []
      });
      expect(view.visible).assertFalse();
      expect(view.displayText).assertEqual('');
      expect(view.decoration).assertEqual(CompositionPreeditDecoration.NONE);
    });

    it('display segmentation does not use expanded full-pinyin preedit text', 0, () => {
      const view = resolveCompositionPreeditView({
        rawInput: 'nihc',
        preeditText: "ni'hao",
        displaySegments: ['ni', 'hc'],
        pendingCode: '',
        segmentBoundaries: []
      });
      expect(view.visible).assertTrue();
      expect(view.displayText).assertEqual("ni'hc");
      expect(view.displayText.indexOf('hao')).assertEqual(-1);
      expect(view.decoration).assertEqual(CompositionPreeditDecoration.UNDERLINE);
    });
  });
}
