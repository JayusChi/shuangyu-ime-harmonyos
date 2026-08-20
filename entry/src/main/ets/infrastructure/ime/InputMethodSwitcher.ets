import { inputMethod } from '@kit.IMEKit';
import { Logger } from '../../common/logging/Logger';

const TAG = 'InputMethodSwitcher';
const LOGGER = new Logger(TAG);
const DUPLICATE_REQUEST_GUARD_MS: number = 700;

export interface InputMethodSwitchCapabilities {
  canSwitchToNext: boolean;
  canShowSystemPicker: boolean;
  canListInputMethods: boolean;
  canSwitchToSpecified: boolean;
  minimumListApi: number;
  minimumCurrentImeSwitchApi: number;
  minimumPickerApi: number;
}

export interface InputMethodDescriptor {
  name: string;
  id: string;
}

export enum InputMethodSwitchResultType {
  SWITCHED_TO_NEXT = 'switched_to_next',
  SYSTEM_PICKER_OPENED = 'system_picker_opened',
  FALLBACK_PICKER_OPENED = 'fallback_picker_opened',
  REQUEST_ALREADY_IN_PROGRESS = 'request_already_in_progress',
  UNAVAILABLE = 'unavailable',
  SESSION_INVALID = 'session_invalid',
  SYSTEM_CALL_FAILED = 'system_call_failed'
}

export interface InputMethodSwitchResult {
  type: InputMethodSwitchResultType;
  success: boolean;
  errorMessage: string;
}

export interface InputMethodSystemBackend {
  getCapabilities(): InputMethodSwitchCapabilities;
  listEnabledInputMethods(): Promise<InputMethodDescriptor[]>;
  getCurrentInputMethod(): InputMethodDescriptor;
  switchToInputMethod(target: InputMethodDescriptor): Promise<boolean>;
  showSystemPicker(): Promise<boolean>;
}

const API_24_CAPABILITIES: InputMethodSwitchCapabilities = {
  // HarmonyOS does not expose a dedicated "next" call. At API 11+, the current IME can
  // enumerate enabled methods and switch to a selected target, so the adapter composes both.
  canSwitchToNext: true,
  canShowSystemPicker: true,
  canListInputMethods: true,
  canSwitchToSpecified: true,
  minimumListApi: 9,
  minimumCurrentImeSwitchApi: 11,
  minimumPickerApi: 9
};

function descriptorKey(descriptor: InputMethodDescriptor): string {
  return `${descriptor.name}\n${descriptor.id}`;
}

export class HarmonyInputMethodSystemBackend implements InputMethodSystemBackend {
  private readonly nativeProperties: Map<string, inputMethod.InputMethodProperty> =
    new Map<string, inputMethod.InputMethodProperty>();

  getCapabilities(): InputMethodSwitchCapabilities {
    return API_24_CAPABILITIES;
  }

  async listEnabledInputMethods(): Promise<InputMethodDescriptor[]> {
    const properties = await inputMethod.getSetting().getInputMethods(true);
    this.nativeProperties.clear();
    return properties.map((property: inputMethod.InputMethodProperty): InputMethodDescriptor => {
      const descriptor: InputMethodDescriptor = { name: property.name, id: property.id };
      this.nativeProperties.set(descriptorKey(descriptor), property);
      return descriptor;
    });
  }

  getCurrentInputMethod(): InputMethodDescriptor {
    const current = inputMethod.getCurrentInputMethod();
    return { name: current.name, id: current.id };
  }

  async switchToInputMethod(target: InputMethodDescriptor): Promise<boolean> {
    let nativeTarget = this.nativeProperties.get(descriptorKey(target));
    if (!nativeTarget) {
      await this.listEnabledInputMethods();
      nativeTarget = this.nativeProperties.get(descriptorKey(target));
    }
    if (!nativeTarget) {
      return false;
    }
    return inputMethod.switchInputMethod(nativeTarget);
  }

  async showSystemPicker(): Promise<boolean> {
    // API 24 keeps this official service call for non-UI integration, although API 18 marks it
    // deprecated in favor of the ArkUI InputMethodListDialog component.
    return inputMethod.getSetting().showOptionalInputMethods();
  }
}

export class InputMethodSwitcher {
  private readonly backend: InputMethodSystemBackend;
  private sessionActive: boolean = false;
  private sessionGeneration: number = 0;
  private requestInProgress: boolean = false;
  private lastRequestCompletedAt: number = 0;
  private readonly duplicateRequestGuardMs: number;

  constructor(
    backend: InputMethodSystemBackend = new HarmonyInputMethodSystemBackend(),
    duplicateRequestGuardMs: number = DUPLICATE_REQUEST_GUARD_MS
  ) {
    this.backend = backend;
    this.duplicateRequestGuardMs = duplicateRequestGuardMs;
  }

  getCapabilities(): InputMethodSwitchCapabilities {
    return this.backend.getCapabilities();
  }

  setSessionActive(active: boolean): void {
    if (this.sessionActive !== active || !active) {
      this.sessionGeneration += 1;
    }
    this.sessionActive = active;
    if (!active) {
      this.requestInProgress = false;
      this.lastRequestCompletedAt = 0;
    }
  }

  async requestSwitchToNext(): Promise<InputMethodSwitchResult> {
    const capabilities = this.getCapabilities();
    if (!capabilities.canSwitchToNext || !capabilities.canListInputMethods ||
      !capabilities.canSwitchToSpecified) {
      return this.requestPickerFallback('direct next switching unavailable');
    }
    return this.runGuarded('switch_next', async (generation: number): Promise<InputMethodSwitchResult> => {
      try {
        const enabled = await this.backend.listEnabledInputMethods();
        if (!this.isGenerationCurrent(generation)) {
          return this.sessionInvalid();
        }
        if (enabled.length < 2) {
          return this.openPickerWithinGuard(generation, true);
        }
        const current = this.backend.getCurrentInputMethod();
        const currentIndex = enabled.findIndex((item: InputMethodDescriptor): boolean =>
          item.name === current.name && item.id === current.id);
        if (currentIndex < 0) {
          return this.openPickerWithinGuard(generation, true);
        }
        const target = enabled[(currentIndex + 1) % enabled.length];
        const switched = await this.backend.switchToInputMethod(target);
        if (!this.isGenerationCurrent(generation)) {
          return this.sessionInvalid();
        }
        if (switched) {
          return { type: InputMethodSwitchResultType.SWITCHED_TO_NEXT, success: true, errorMessage: '' };
        }
        return this.openPickerWithinGuard(generation, true);
      } catch (err) {
        LOGGER.warn(`system switch failed; attempting picker fallback: action=switch_next, error=${JSON.stringify(err)}`);
        return this.openPickerWithinGuard(generation, true);
      }
    });
  }

  async requestShowSystemPicker(): Promise<InputMethodSwitchResult> {
    if (!this.getCapabilities().canShowSystemPicker) {
      return this.unavailable('system input method picker unavailable');
    }
    return this.runGuarded('show_picker', async (generation: number): Promise<InputMethodSwitchResult> => {
      return this.openPickerWithinGuard(generation, false);
    });
  }

  private async requestPickerFallback(reason: string): Promise<InputMethodSwitchResult> {
    if (!this.getCapabilities().canShowSystemPicker) {
      return this.unavailable(reason);
    }
    return this.runGuarded('fallback_picker', async (generation: number): Promise<InputMethodSwitchResult> => {
      return this.openPickerWithinGuard(generation, true);
    });
  }

  private async openPickerWithinGuard(
    generation: number,
    fallback: boolean
  ): Promise<InputMethodSwitchResult> {
    if (!this.getCapabilities().canShowSystemPicker) {
      return this.unavailable('system input method picker unavailable');
    }
    try {
      const opened = await this.backend.showSystemPicker();
      if (!this.isGenerationCurrent(generation)) {
        return this.sessionInvalid();
      }
      if (!opened) {
        return this.failed('system input method picker returned false');
      }
      return {
        type: fallback
          ? InputMethodSwitchResultType.FALLBACK_PICKER_OPENED
          : InputMethodSwitchResultType.SYSTEM_PICKER_OPENED,
        success: true,
        errorMessage: ''
      };
    } catch (err) {
      LOGGER.error(`system picker call failed: error=${JSON.stringify(err)}`);
      return this.failed('system input method picker call failed');
    }
  }

  private async runGuarded(
    action: string,
    task: (generation: number) => Promise<InputMethodSwitchResult>
  ): Promise<InputMethodSwitchResult> {
    if (!this.sessionActive) {
      return this.sessionInvalid();
    }
    const now = Date.now();
    if (this.requestInProgress || now - this.lastRequestCompletedAt < this.duplicateRequestGuardMs) {
      LOGGER.info(`duplicate system input method request suppressed: action=${action}`);
      return {
        type: InputMethodSwitchResultType.REQUEST_ALREADY_IN_PROGRESS,
        success: true,
        errorMessage: ''
      };
    }

    this.requestInProgress = true;
    const generation = this.sessionGeneration;
    try {
      return await task(generation);
    } finally {
      if (generation === this.sessionGeneration) {
        this.requestInProgress = false;
        this.lastRequestCompletedAt = Date.now();
      }
    }
  }

  private isGenerationCurrent(generation: number): boolean {
    return this.sessionActive && generation === this.sessionGeneration;
  }

  private unavailable(message: string): InputMethodSwitchResult {
    return { type: InputMethodSwitchResultType.UNAVAILABLE, success: false, errorMessage: message };
  }

  private sessionInvalid(): InputMethodSwitchResult {
    return {
      type: InputMethodSwitchResultType.SESSION_INVALID,
      success: false,
      errorMessage: 'input method session is no longer active'
    };
  }

  private failed(message: string): InputMethodSwitchResult {
    return { type: InputMethodSwitchResultType.SYSTEM_CALL_FAILED, success: false, errorMessage: message };
  }
}

let sharedInputMethodSwitcher: InputMethodSwitcher | undefined;

export function getSharedInputMethodSwitcher(): InputMethodSwitcher {
  if (!sharedInputMethodSwitcher) {
    sharedInputMethodSwitcher = new InputMethodSwitcher();
  }
  return sharedInputMethodSwitcher;
}
