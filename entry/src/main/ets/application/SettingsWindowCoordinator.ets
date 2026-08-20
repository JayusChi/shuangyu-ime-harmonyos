import { window } from '@kit.ArkUI';
import { Logger } from '../common/logging/Logger';
import { SettingsStateListener } from '../state/SettingsStore';
import { SettingsThemeTokens, resolveSettingsTheme } from '../presentation/settings/SettingsTheme';
import { SettingsController } from './SettingsController';

const LOGGER = new Logger('SettingsWindow');

export interface SettingsWindowStyle {
  backgroundColor: string;
  contentColor: string;
  lightIcons: boolean;
}

export interface SettingsSafeAreaInsets {
  top: number;
  bottom: number;
  left: number;
  right: number;
}

export interface AvoidAreaRectLike {
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface WindowAvoidAreaLike {
  visible: boolean;
  leftRect: AvoidAreaRectLike;
  topRect: AvoidAreaRectLike;
  rightRect: AvoidAreaRectLike;
  bottomRect: AvoidAreaRectLike;
}

export type SettingsSafeAreaListener = (insets: SettingsSafeAreaInsets) => void;

interface PageStyleOverride {
  token: number;
  style: SettingsWindowStyle;
}

export interface SettingsWindowBackend {
  enableImmersiveLayout(): Promise<void>;
  applyStyle(style: SettingsWindowStyle): Promise<void>;
  startSafeAreaTracking(listener: SettingsSafeAreaListener): void;
  stopSafeAreaTracking(): void;
}

export const EMPTY_SETTINGS_SAFE_AREA: SettingsSafeAreaInsets = {
  top: 0,
  bottom: 0,
  left: 0,
  right: 0
};

function occupied(rect: AvoidAreaRectLike): boolean {
  return rect.width > 0 && rect.height > 0;
}

/** Resolves edge insets in the same unit as the supplied window and avoid-area rectangles. */
export function resolveWindowSafeAreaInsets(
  windowWidth: number,
  windowHeight: number,
  areas: WindowAvoidAreaLike[]
): SettingsSafeAreaInsets {
  let top = 0;
  let bottom = 0;
  let left = 0;
  let right = 0;
  areas.forEach((area: WindowAvoidAreaLike): void => {
    if (!area.visible) {
      return;
    }
    if (occupied(area.topRect)) {
      top = Math.max(top, area.topRect.top + area.topRect.height);
    }
    if (occupied(area.bottomRect)) {
      bottom = Math.max(bottom, windowHeight - area.bottomRect.top);
    }
    if (occupied(area.leftRect)) {
      left = Math.max(left, area.leftRect.left + area.leftRect.width);
    }
    if (occupied(area.rightRect)) {
      right = Math.max(right, windowWidth - area.rightRect.left);
    }
  });
  return {
    top: Math.max(0, Math.min(windowHeight, top)),
    bottom: Math.max(0, Math.min(windowHeight, bottom)),
    left: Math.max(0, Math.min(windowWidth, left)),
    right: Math.max(0, Math.min(windowWidth, right))
  };
}

export function resolveSettingsWindowStyle(isDark: boolean): SettingsWindowStyle {
  const theme: SettingsThemeTokens = resolveSettingsTheme(isDark);
  return {
    backgroundColor: theme.pageBackground,
    contentColor: theme.primaryText,
    lightIcons: isDark
  };
}

/**
 * Applies settings-page theme changes to the main window in order. Serializing the work guarantees
 * that an older asynchronous system-bar request can never finish after the newest requested style.
 */
export class SettingsWindowCoordinator {
  private readonly controller: SettingsController;
  private readonly backend: SettingsWindowBackend;
  private readonly onSettingsChanged: SettingsStateListener = (): void => {
    this.sync().catch((err: Object): void => {
      LOGGER.warn(`automatic window theme synchronization failed: ${JSON.stringify(err)}`);
    });
  };
  private started: boolean = false;
  private immersiveAttempted: boolean = false;
  private safeAreaTrackingStarted: boolean = false;
  private requestVersion: number = 0;
  private nextOverrideToken: number = 0;
  private pageStyleOverride?: PageStyleOverride;
  private safeAreaInsets: SettingsSafeAreaInsets = EMPTY_SETTINGS_SAFE_AREA;
  private readonly safeAreaListeners: Set<SettingsSafeAreaListener> = new Set<SettingsSafeAreaListener>();
  private applyQueue: Promise<void> = Promise.resolve();
  private readonly onSafeAreaChanged: SettingsSafeAreaListener = (insets: SettingsSafeAreaInsets): void => {
    this.safeAreaInsets = {
      top: insets.top,
      bottom: insets.bottom,
      left: insets.left,
      right: insets.right
    };
    this.safeAreaListeners.forEach((listener: SettingsSafeAreaListener): void => {
      listener(this.safeAreaInsets);
    });
  };

  constructor(controller: SettingsController, backend: SettingsWindowBackend) {
    this.controller = controller;
    this.backend = backend;
  }

  start(): Promise<void> {
    if (!this.started) {
      this.started = true;
      this.controller.subscribe(this.onSettingsChanged);
    }
    return this.sync();
  }

  subscribeSafeArea(listener: SettingsSafeAreaListener): void {
    this.safeAreaListeners.add(listener);
    listener(this.safeAreaInsets);
  }

  unsubscribeSafeArea(listener: SettingsSafeAreaListener): void {
    this.safeAreaListeners.delete(listener);
  }

  setPageStyleOverride(style: SettingsWindowStyle): number {
    const token = ++this.nextOverrideToken;
    this.pageStyleOverride = {
      token,
      style: {
        backgroundColor: style.backgroundColor,
        contentColor: style.contentColor,
        lightIcons: style.lightIcons
      }
    };
    this.sync().catch((err: Object): void => {
      LOGGER.warn(`page window style override failed: ${JSON.stringify(err)}`);
    });
    return token;
  }

  clearPageStyleOverride(token: number): void {
    if (this.pageStyleOverride?.token !== token) {
      return;
    }
    this.pageStyleOverride = undefined;
    this.sync().catch((err: Object): void => {
      LOGGER.warn(`restoring settings window style failed: ${JSON.stringify(err)}`);
    });
  }

  sync(): Promise<void> {
    if (!this.started) {
      return Promise.resolve();
    }
    const version = ++this.requestVersion;
    const style = this.pageStyleOverride?.style ?? resolveSettingsWindowStyle(this.controller.isDarkMode());
    this.applyQueue = this.applyQueue.then(async (): Promise<void> => {
      if (!this.immersiveAttempted) {
        this.immersiveAttempted = true;
        try {
          await this.backend.enableImmersiveLayout();
        } catch (err) {
          LOGGER.warn(`immersive window layout is unavailable: ${JSON.stringify(err)}`);
        }
      }
      if (!this.started) {
        return;
      }
      // Avoid-area values depend on the final window layout mode. Querying them before immersive
      // layout is enabled can cache an empty top inset, and some devices do not emit a second
      // avoidAreaChange event. Start tracking only after the layout mode has settled so the first
      // page frame already has the status-bar/cutout inset.
      if (!this.safeAreaTrackingStarted) {
        this.safeAreaTrackingStarted = true;
        try {
          this.backend.startSafeAreaTracking(this.onSafeAreaChanged);
        } catch (err) {
          LOGGER.warn(`safe-area tracking is unavailable: ${JSON.stringify(err)}`);
        }
      }
      if (version !== this.requestVersion) {
        return;
      }
      try {
        await this.backend.applyStyle(style);
      } catch (err) {
        LOGGER.warn(`window system bar style update failed: ${JSON.stringify(err)}`);
      }
    });
    return this.applyQueue;
  }

  stop(): void {
    if (!this.started) {
      return;
    }
    this.started = false;
    this.requestVersion += 1;
    this.controller.unsubscribe(this.onSettingsChanged);
    try {
      this.backend.stopSafeAreaTracking();
    } catch (err) {
      LOGGER.warn(`safe-area tracking cleanup failed: ${JSON.stringify(err)}`);
    }
    this.safeAreaTrackingStarted = false;
    this.safeAreaListeners.clear();
    this.pageStyleOverride = undefined;
  }
}

let sharedSettingsWindowCoordinator: SettingsWindowCoordinator | undefined;

export function registerSharedSettingsWindowCoordinator(coordinator: SettingsWindowCoordinator): void {
  sharedSettingsWindowCoordinator = coordinator;
}

export function unregisterSharedSettingsWindowCoordinator(coordinator: SettingsWindowCoordinator): void {
  if (sharedSettingsWindowCoordinator === coordinator) {
    sharedSettingsWindowCoordinator = undefined;
  }
}

export function getSharedSettingsWindowCoordinator(): SettingsWindowCoordinator | undefined {
  return sharedSettingsWindowCoordinator;
}

export class HarmonySettingsWindowBackend implements SettingsWindowBackend {
  private readonly mainWindow: window.Window;
  private systemAvoidArea?: window.AvoidArea;
  private cutoutAvoidArea?: window.AvoidArea;
  private navigationAvoidArea?: window.AvoidArea;
  private safeAreaListener?: SettingsSafeAreaListener;
  private trackingSafeArea: boolean = false;
  private readonly avoidAreaChangeListener = (options: window.AvoidAreaOptions): void => {
    this.updateAvoidArea(options.type, options.area);
    this.emitSafeArea();
  };

  constructor(mainWindow: window.Window) {
    this.mainWindow = mainWindow;
  }

  async enableImmersiveLayout(): Promise<void> {
    try {
      await this.mainWindow.setWindowLayoutFullScreen(true);
    } catch (err) {
      LOGGER.warn(`setWindowLayoutFullScreen failed: ${JSON.stringify(err)}`);
    }
  }

  async applyStyle(style: SettingsWindowStyle): Promise<void> {
    try {
      this.mainWindow.setWindowBackgroundColor(style.backgroundColor);
    } catch (err) {
      LOGGER.warn(`window background color update failed: ${JSON.stringify(err)}`);
    }
    try {
      await this.mainWindow.setWindowSystemBarProperties({
        statusBarColor: style.backgroundColor,
        navigationBarColor: style.backgroundColor,
        isStatusBarLightIcon: style.lightIcons,
        isNavigationBarLightIcon: style.lightIcons,
        statusBarContentColor: style.contentColor,
        navigationBarContentColor: style.contentColor
      });
    } catch (err) {
      LOGGER.warn(`setWindowSystemBarProperties failed: ${JSON.stringify(err)}`);
    }
  }

  startSafeAreaTracking(listener: SettingsSafeAreaListener): void {
    this.safeAreaListener = listener;
    if (!this.trackingSafeArea) {
      try {
        this.mainWindow.on('avoidAreaChange', this.avoidAreaChangeListener);
        this.trackingSafeArea = true;
      } catch (err) {
        LOGGER.warn(`avoidAreaChange registration failed: ${JSON.stringify(err)}`);
      }
    }
    this.refreshAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    this.refreshAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
    this.refreshAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.emitSafeArea();
  }

  stopSafeAreaTracking(): void {
    if (this.trackingSafeArea) {
      try {
        this.mainWindow.off('avoidAreaChange', this.avoidAreaChangeListener);
      } catch (err) {
        LOGGER.warn(`avoidAreaChange cleanup failed: ${JSON.stringify(err)}`);
      }
    }
    this.trackingSafeArea = false;
    this.safeAreaListener = undefined;
  }

  private refreshAvoidArea(type: window.AvoidAreaType): void {
    try {
      this.updateAvoidArea(type, this.mainWindow.getWindowAvoidArea(type));
    } catch (err) {
      LOGGER.warn(`getWindowAvoidArea(${type}) failed: ${JSON.stringify(err)}`);
    }
  }

  private updateAvoidArea(type: window.AvoidAreaType, area: window.AvoidArea): void {
    if (type === window.AvoidAreaType.TYPE_SYSTEM) {
      this.systemAvoidArea = area;
    } else if (type === window.AvoidAreaType.TYPE_CUTOUT) {
      this.cutoutAvoidArea = area;
    } else if (type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      this.navigationAvoidArea = area;
    }
  }

  private emitSafeArea(): void {
    if (this.safeAreaListener === undefined) {
      return;
    }
    try {
      const rect = this.mainWindow.getWindowProperties().windowRect;
      const areas: WindowAvoidAreaLike[] = [];
      if (this.systemAvoidArea !== undefined) {
        areas.push(this.copyAvoidArea(this.systemAvoidArea));
      }
      if (this.cutoutAvoidArea !== undefined) {
        areas.push(this.copyAvoidArea(this.cutoutAvoidArea));
      }
      if (this.navigationAvoidArea !== undefined) {
        areas.push(this.copyAvoidArea(this.navigationAvoidArea));
      }
      const pxInsets = resolveWindowSafeAreaInsets(rect.width, rect.height, areas);
      const uiContext = this.mainWindow.getUIContext();
      this.safeAreaListener({
        top: uiContext.px2vp(pxInsets.top),
        bottom: uiContext.px2vp(pxInsets.bottom),
        left: uiContext.px2vp(pxInsets.left),
        right: uiContext.px2vp(pxInsets.right)
      });
    } catch (err) {
      LOGGER.warn(`safe-area calculation failed: ${JSON.stringify(err)}`);
    }
  }

  private copyRect(rect: window.Rect): AvoidAreaRectLike {
    return { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
  }

  private copyAvoidArea(area: window.AvoidArea): WindowAvoidAreaLike {
    return {
      visible: area.visible,
      leftRect: this.copyRect(area.leftRect),
      topRect: this.copyRect(area.topRect),
      rightRect: this.copyRect(area.rightRect),
      bottomRect: this.copyRect(area.bottomRect)
    };
  }
}
