import common from '@ohos.app.ability.common';
import { ConfigurationConstant, systemConfiguration } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { Logger } from '../common/logging/Logger';

const LOGGER = new Logger('SystemThemeMonitor');

export type SystemThemeListener = (isDark: boolean) => void;

export interface SystemThemeBackend {
  readDarkMode(): boolean;
  subscribe(listener: SystemThemeListener): void;
  unsubscribe(listener: SystemThemeListener): void;
}

/**
 * Owns one system-theme subscription and makes initialization/disposal idempotent.
 */
export class SystemThemeMonitor {
  private started: boolean = false;
  private readonly backend: SystemThemeBackend;
  private readonly listener: SystemThemeListener;

  constructor(
    backend: SystemThemeBackend,
    listener: SystemThemeListener
  ) {
    this.backend = backend;
    this.listener = listener;
  }

  start(): void {
    if (this.started) {
      this.refresh();
      return;
    }
    this.started = true;
    this.backend.subscribe(this.listener);
    this.refresh();
  }

  refresh(): void {
    if (!this.started) {
      return;
    }
    this.listener(this.backend.readDarkMode());
  }

  stop(): void {
    if (!this.started) {
      return;
    }
    this.started = false;
    this.backend.unsubscribe(this.listener);
  }
}

/**
 * Reads the effective resource color mode. context.config may be NOT_SET while following the system,
 * so it must not be interpreted as light mode.
 */
export class HarmonySystemThemeBackend implements SystemThemeBackend {
  private callback?: systemConfiguration.UpdatedCallback;
  private readonly context: common.Context;
  private lastKnownDarkMode: boolean = false;

  constructor(context: common.Context) {
    this.context = context;
  }

  readDarkMode(): boolean {
    try {
      this.lastKnownDarkMode =
        this.context.resourceManager.getConfigurationSync().colorMode === resourceManager.ColorMode.DARK;
      return this.lastKnownDarkMode;
    } catch (err) {
      LOGGER.warn(`effective resource color mode read failed: ${JSON.stringify(err)}`);
      return this.lastKnownDarkMode;
    }
  }

  subscribe(listener: SystemThemeListener): void {
    if (this.callback) {
      return;
    }
    const callback: systemConfiguration.UpdatedCallback = {
      onColorModeUpdated: (colorMode: ConfigurationConstant.ColorMode): void => {
        if (colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
          this.lastKnownDarkMode = true;
          listener(true);
        } else if (colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
          this.lastKnownDarkMode = false;
          listener(false);
        } else {
          // NOT_SET means the application follows the system; read the actual resource mode.
          listener(this.readDarkMode());
        }
      }
    };
    this.context.getApplicationContext().onSystemConfigurationUpdated(callback);
    this.callback = callback;
  }

  unsubscribe(listener: SystemThemeListener): void {
    const callback = this.callback;
    this.callback = undefined;
    if (!callback) {
      return;
    }
    try {
      this.context.getApplicationContext().offSystemConfigurationUpdated(callback);
    } catch (err) {
      LOGGER.warn(`system theme listener removal failed: ${JSON.stringify(err)}`);
    }
  }
}
