export enum InputPresentationMode {
  TOUCH = 'TOUCH',
  HARDWARE = 'HARDWARE'
}

/**
 * The persisted preference is deliberately separate from the effective mode.
 * The persisted preference is resolved again whenever settings or the
 * alphabetic physical-keyboard state changes.
 */
export enum InputPresentationPreference {
  AUTO = 'AUTO',
  TOUCH = 'TOUCH',
  HARDWARE = 'HARDWARE'
}

export enum InputPresentationState {
  INACTIVE = 'INACTIVE',
  TOUCH_READY = 'TOUCH_READY',
  HARDWARE_READY = 'HARDWARE_READY'
}

export function resolveInputPresentationMode(
  preference: InputPresentationPreference,
  deviceType: string,
  physicalKeyboardPresent: boolean = false
): InputPresentationMode {
  if (preference === InputPresentationPreference.TOUCH) {
    return InputPresentationMode.TOUCH;
  }
  if (preference === InputPresentationPreference.HARDWARE) {
    return InputPresentationMode.HARDWARE;
  }
  const normalizedDeviceType = deviceType.trim().toLowerCase();
  return normalizedDeviceType === '2in1' ||
    (normalizedDeviceType === 'tablet' && physicalKeyboardPresent)
    ? InputPresentationMode.HARDWARE
    : InputPresentationMode.TOUCH;
}

export function readyStateForMode(mode: InputPresentationMode): InputPresentationState {
  return mode === InputPresentationMode.HARDWARE
    ? InputPresentationState.HARDWARE_READY
    : InputPresentationState.TOUCH_READY;
}
