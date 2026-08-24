import { inputMethodEngine } from '@kit.IMEKit';
import { Logger } from '../../common/logging/Logger';
import {
  InputMethodCapabilityState,
  InputMethodSecurityMode,
  MicrophonePermissionState
} from '../../domain/security/InputMethodCapabilityState';

const LOGGER = new Logger('ImeSecurityMode');

export class InputMethodSecurityModeProvider {
  probe(
    source: inputMethodEngine.InputMethodAbility,
    cloudAiProviderAvailable: boolean,
    speechProviderAvailable: boolean
  ): InputMethodCapabilityState {
    let securityMode = InputMethodSecurityMode.UNKNOWN;
    try {
      const platformMode = source.getSecurityMode();
      securityMode = platformMode === inputMethodEngine.SecurityMode.FULL
        ? InputMethodSecurityMode.FULL
        : InputMethodSecurityMode.BASIC;
      LOGGER.info(`input method security mode detected: mode=${securityMode}`);
    } catch (_err) {
      LOGGER.warn('input method security mode detection failed');
    }
    return {
      securityMode,
      microphonePermission: MicrophonePermissionState.NOT_REQUESTED,
      localAiProviderAvailable: false,
      cloudAiProviderAvailable,
      speechProviderAvailable,
      detectedAtMs: Date.now()
    };
  }
}
