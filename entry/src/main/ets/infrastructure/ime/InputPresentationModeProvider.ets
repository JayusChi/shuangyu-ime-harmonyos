import deviceInfo from '@ohos.deviceInfo';
import {
  InputPresentationMode,
  InputPresentationPreference,
  resolveInputPresentationMode
} from '../../domain/display/InputPresentationMode';

export interface InputPresentationModeProvider {
  resolve(
    preference?: InputPresentationPreference,
    physicalKeyboardPresent?: boolean
  ): InputPresentationMode;
}

/** Product AUTO rule: 2in1, or Tablet with an alphabetic keyboard, uses hardware presentation. */
export class HarmonyInputPresentationModeProvider implements InputPresentationModeProvider {
  resolve(
    preference: InputPresentationPreference = InputPresentationPreference.AUTO,
    physicalKeyboardPresent: boolean = false
  ): InputPresentationMode {
    return resolveInputPresentationMode(preference, deviceInfo.deviceType, physicalKeyboardPresent);
  }
}
