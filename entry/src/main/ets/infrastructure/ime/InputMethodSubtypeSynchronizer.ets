import { inputMethod } from '@kit.IMEKit';
import InputMethodSubtype from '@ohos.InputMethodSubtype';
import { Logger } from '../../common/logging/Logger';
import {
  QUANPIN_INPUT_METHOD_SUBTYPE_ID,
  SHUANGPIN_INPUT_METHOD_SUBTYPE_ID,
  XIAOHE_YINXING_INPUT_METHOD_SUBTYPE_ID
} from '../../domain/keyboard/InputMethodSubtypeRouting';
import {
  QUANPIN_26_PROFILE_ID,
  XIAOHE_18_PROFILE_ID,
  XIAOHE_26_PROFILE_ID,
  XIAOHE_YINXING_26_PROFILE_ID
} from '../../domain/keyboard/KeyboardProfile';

const LOGGER = new Logger('InputMethodSubtypeSync');
const SHUANGYU_BUNDLE_NAME: string = 'com.corrosion.shuangyuime';

export interface InputMethodSubtypeDescriptor {
  name: string;
  id: string;
  locale: string;
  language: string;
}

export interface InputMethodSubtypeBackend {
  getCurrentInputMethodName(): string;
  getCurrentSubtypeId(): string;
  listCurrentSubtypes(): Promise<InputMethodSubtypeDescriptor[]>;
  switchCurrentSubtype(target: InputMethodSubtypeDescriptor): Promise<boolean>;
}

export function inputMethodSubtypeIdForKeyboardProfile(profileId: string): string | undefined {
  switch (profileId) {
    case QUANPIN_26_PROFILE_ID:
      return QUANPIN_INPUT_METHOD_SUBTYPE_ID;
    case XIAOHE_18_PROFILE_ID:
    case XIAOHE_26_PROFILE_ID:
      return SHUANGPIN_INPUT_METHOD_SUBTYPE_ID;
    case XIAOHE_YINXING_26_PROFILE_ID:
      return XIAOHE_YINXING_INPUT_METHOD_SUBTYPE_ID;
    default:
      // The platform exposes no dedicated subtype for the 9-key profile.
      return undefined;
  }
}

export class HarmonyInputMethodSubtypeBackend implements InputMethodSubtypeBackend {
  private readonly nativeSubtypes: Map<string, InputMethodSubtype> =
    new Map<string, InputMethodSubtype>();

  getCurrentInputMethodName(): string {
    return inputMethod.getCurrentInputMethod().name;
  }

  getCurrentSubtypeId(): string {
    return inputMethod.getCurrentInputMethodSubtype().id;
  }

  async listCurrentSubtypes(): Promise<InputMethodSubtypeDescriptor[]> {
    try {
      const setting = inputMethod.getSetting();
      const subtypes = await setting.listCurrentInputMethodSubtype();
      this.nativeSubtypes.clear();
      return subtypes.map((subtype: InputMethodSubtype): InputMethodSubtypeDescriptor => {
        this.nativeSubtypes.set(subtype.id, subtype);
        return {
          name: subtype.name,
          id: subtype.id,
          locale: subtype.locale,
          language: subtype.language
        };
      });
    } catch (err) {
      this.nativeSubtypes.clear();
      LOGGER.warn(`failed to list input method subtypes: error=${JSON.stringify(err)}`);
      return [];
    }
  }

  async switchCurrentSubtype(target: InputMethodSubtypeDescriptor): Promise<boolean> {
    const nativeTarget: InputMethodSubtype | undefined = this.nativeSubtypes.get(target.id);
    if (!nativeTarget) {
      return false;
    }
    try {
      return await inputMethod.switchCurrentInputMethodSubtype(nativeTarget);
    } catch (err) {
      LOGGER.warn(`failed to switch input method subtype: id=${target.id}, error=${JSON.stringify(err)}`);
      return false;
    }
  }
}

export class InputMethodSubtypeSynchronizer {
  private readonly backend: InputMethodSubtypeBackend;

  constructor(backend: InputMethodSubtypeBackend = new HarmonyInputMethodSubtypeBackend()) {
    this.backend = backend;
  }

  async syncForKeyboardProfile(profileId: string): Promise<boolean> {
    const targetId = inputMethodSubtypeIdForKeyboardProfile(profileId);
    if (!targetId) {
      return true;
    }
    try {
      if (this.backend.getCurrentInputMethodName() !== SHUANGYU_BUNDLE_NAME) {
        return false;
      }
      if (this.backend.getCurrentSubtypeId() === targetId) {
        return true;
      }
      const subtypes = await this.backend.listCurrentSubtypes();
      const target = subtypes.find((subtype: InputMethodSubtypeDescriptor): boolean =>
        subtype.name === SHUANGYU_BUNDLE_NAME && subtype.id === targetId);
      if (!target) {
        LOGGER.warn(`target input method subtype unavailable: id=${targetId}`);
        return false;
      }
      const switched = await this.backend.switchCurrentSubtype(target);
      if (!switched) {
        LOGGER.warn(`platform rejected input method subtype synchronization: id=${targetId}`);
      }
      return switched;
    } catch (err) {
      LOGGER.warn(`input method subtype synchronization failed: id=${targetId}, error=${JSON.stringify(err)}`);
      return false;
    }
  }
}
