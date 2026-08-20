import common from '@ohos.app.ability.common';
import { Logger } from '../common/logging/Logger';
import {
  DEFAULT_SHUANGPIN_KEYBOARD_LAYOUT,
  ShuangpinKeyboardLayout
} from '../domain/keyboard/ShuangpinKeyboardLayout';
import {
  keyboardProfileForEngineScheme,
  keyboardProfileLayoutKind,
  KeyboardLayoutKind
} from '../domain/keyboard/KeyboardProfile';
import { getSharedSettingsController, SettingsController } from './SettingsController';

const LOGGER = new Logger('KeyboardLayoutPreference');

export type KeyboardLayoutPreferenceListener = (layout: ShuangpinKeyboardLayout) => void;

/**
 * Compatibility adapter for the existing keyboard UI. Persistence now belongs
 * to the validated `ImeSettings.keyboardProfileId` flow; this class no longer
 * owns an independent preferences file.
 */
export class KeyboardLayoutPreferenceController {
  private layout: ShuangpinKeyboardLayout = DEFAULT_SHUANGPIN_KEYBOARD_LAYOUT;
  private listeners: KeyboardLayoutPreferenceListener[] = [];
  private initializationTask?: Promise<ShuangpinKeyboardLayout>;
  private subscribed: boolean = false;
  private readonly onSettingsChanged = (): void => this.refreshFromSettings();
  private readonly settings: SettingsController;

  constructor(settings: SettingsController = getSharedSettingsController()) {
    this.settings = settings;
  }

  initialize(context: common.Context): Promise<ShuangpinKeyboardLayout> {
    if (this.initializationTask) {
      return this.initializationTask;
    }
    if (!this.subscribed) {
      this.settings.subscribe(this.onSettingsChanged);
      this.subscribed = true;
    }
    this.initializationTask = this.load(context);
    return this.initializationTask;
  }

  getLayout(): ShuangpinKeyboardLayout {
    return this.layout;
  }

  subscribe(listener: KeyboardLayoutPreferenceListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: KeyboardLayoutPreferenceListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  async select(layout: ShuangpinKeyboardLayout): Promise<boolean> {
    const current = this.settings.getSettings();
    const targetLayout = layout === ShuangpinKeyboardLayout.SEVENTEEN_KEY
      ? KeyboardLayoutKind.SEVENTEEN_KEY
      : KeyboardLayoutKind.QWERTY_26_KEY;
    const profileId = keyboardProfileForEngineScheme(current.schemeId, targetLayout);
    if (!profileId) {
      LOGGER.warn(`no legal keyboard profile for scheme=${current.schemeId}, layout=${targetLayout}`);
      return false;
    }
    const result = await this.settings.setKeyboardProfile(profileId);
    this.refreshFromSettings();
    if (!result.success) {
      LOGGER.warn(`keyboard profile save failed: ${result.message}`);
    }
    return result.success;
  }

  private async load(context: common.Context): Promise<ShuangpinKeyboardLayout> {
    try {
      await this.settings.initialize(context);
      this.refreshFromSettings();
      LOGGER.info(`keyboard profile layout loaded: ${this.layout}`);
    } catch (err) {
      this.replace(DEFAULT_SHUANGPIN_KEYBOARD_LAYOUT);
      LOGGER.warn(`keyboard profile load failed; using default: ${JSON.stringify(err)}`);
    }
    return this.layout;
  }

  private refreshFromSettings(): void {
    const layoutKind = keyboardProfileLayoutKind(this.settings.getSettings().keyboardProfileId);
    this.replace(layoutKind === KeyboardLayoutKind.SEVENTEEN_KEY
      ? ShuangpinKeyboardLayout.SEVENTEEN_KEY
      : ShuangpinKeyboardLayout.TWENTY_SIX_KEY);
  }

  private replace(layout: ShuangpinKeyboardLayout): void {
    if (this.layout === layout) {
      return;
    }
    this.layout = layout;
    this.listeners.slice().forEach((listener: KeyboardLayoutPreferenceListener): void => listener(layout));
  }
}

const SHARED_KEYBOARD_LAYOUT_PREFERENCE = new KeyboardLayoutPreferenceController();

export function getSharedKeyboardLayoutPreferenceController(): KeyboardLayoutPreferenceController {
  return SHARED_KEYBOARD_LAYOUT_PREFERENCE;
}
