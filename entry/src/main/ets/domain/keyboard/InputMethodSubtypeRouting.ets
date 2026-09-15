import { KeyboardMode } from './KeyboardAction';
import {
  QUANPIN_26_PROFILE_ID,
  XIAOHE_18_PROFILE_ID,
  XIAOHE_26_PROFILE_ID,
  XIAOHE_YINXING_26_PROFILE_ID
} from './KeyboardProfile';

export const QUANPIN_INPUT_METHOD_SUBTYPE_ID: string = 'shuangyu_quanpin_zh_cn';
/** Kept stable so an installed version can upgrade without losing its selected subtype. */
export const SHUANGPIN_INPUT_METHOD_SUBTYPE_ID: string = 'shuangyu_zh_cn';
export const XIAOHE_YINXING_INPUT_METHOD_SUBTYPE_ID: string = 'shuangyu_yinxing_zh_cn';
export const ENGLISH_INPUT_METHOD_SUBTYPE_ID: string = 'shuangyu_en_us';

export interface InputMethodSubtypeTarget {
  keyboardMode: KeyboardMode;
  keyboardProfileId?: string;
}

/** Maps platform-owned subtype identifiers to the existing product runtime. */
export function resolveInputMethodSubtypeTarget(
  subtypeId: string,
  currentProfileId?: string
): InputMethodSubtypeTarget | undefined {
  switch (subtypeId) {
    case QUANPIN_INPUT_METHOD_SUBTYPE_ID:
      return {
        keyboardMode: KeyboardMode.CHINESE,
        keyboardProfileId: QUANPIN_26_PROFILE_ID
      };
    case SHUANGPIN_INPUT_METHOD_SUBTYPE_ID:
      return {
        keyboardMode: KeyboardMode.CHINESE,
        // Both touch layouts share one platform subtype. Its echo must retain the selected layout.
        keyboardProfileId: currentProfileId === XIAOHE_18_PROFILE_ID ? XIAOHE_18_PROFILE_ID : XIAOHE_26_PROFILE_ID
      };
    case XIAOHE_YINXING_INPUT_METHOD_SUBTYPE_ID:
      return {
        keyboardMode: KeyboardMode.CHINESE,
        keyboardProfileId: XIAOHE_YINXING_26_PROFILE_ID
      };
    case ENGLISH_INPUT_METHOD_SUBTYPE_ID:
      return { keyboardMode: KeyboardMode.ENGLISH };
    default:
      return undefined;
  }
}
