import {
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  EffectiveTheme,
  imeSettingsEqual,
  ImeSettings,
  resolveEffectiveTheme,
  ThemeMode
} from '../domain/settings/ImeSettings';

export type SettingsStateListener = () => void;

export class SettingsStore {
  private settings: ImeSettings = copyImeSettings(DEFAULT_IME_SETTINGS);
  private initialized: boolean = false;
  private systemDarkMode: boolean = false;
  private listeners: SettingsStateListener[] = [];

  getSnapshot(): ImeSettings {
    return copyImeSettings(this.settings);
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  isDarkMode(): boolean {
    return this.getEffectiveTheme() === EffectiveTheme.DARK;
  }

  getEffectiveTheme(): EffectiveTheme {
    return resolveEffectiveTheme(this.settings.themeMode, this.systemDarkMode);
  }

  replace(settings: ImeSettings, initialized: boolean = true): void {
    const changed = !imeSettingsEqual(this.settings, settings) || this.initialized !== initialized;
    this.settings = copyImeSettings(settings);
    this.initialized = initialized;
    if (changed) {
      this.notify();
    }
  }

  setSystemDarkMode(isDark: boolean): void {
    if (this.systemDarkMode === isDark) {
      return;
    }
    this.systemDarkMode = isDark;
    if (this.settings.themeMode === ThemeMode.FOLLOW_SYSTEM) {
      this.notify();
    }
  }

  reset(): void {
    this.replace(DEFAULT_IME_SETTINGS, true);
  }

  subscribe(listener: SettingsStateListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: SettingsStateListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  private notify(): void {
    this.listeners.slice().forEach((listener: SettingsStateListener) => listener());
  }
}

const SHARED_SETTINGS_STORE = new SettingsStore();

export function getSharedSettingsStore(): SettingsStore {
  return SHARED_SETTINGS_STORE;
}
