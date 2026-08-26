import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, window } from '@kit.ArkUI';
import { getSharedSettingsController } from '../application/SettingsController';
import { HarmonySystemThemeBackend, SystemThemeMonitor } from '../application/SystemThemeMonitor';
import {
  HarmonySettingsWindowBackend,
  registerSharedSettingsWindowCoordinator,
  SettingsWindowCoordinator,
  unregisterSharedSettingsWindowCoordinator
} from '../application/SettingsWindowCoordinator';
import { getSharedDirectControlService } from '../application/DirectControlService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private systemThemeMonitor?: SystemThemeMonitor;
  private settingsInitialization?: Promise<Object>;
  private settingsWindowCoordinator?: SettingsWindowCoordinator;
  private requestedEntryPage: string = 'pages/Index';
  private contentLoaded: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.requestedEntryPage = this.entryPageFromWant(want);
    const settingsController = getSharedSettingsController();
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    this.systemThemeMonitor = new SystemThemeMonitor(
      new HarmonySystemThemeBackend(this.context),
      (isDark: boolean): void => settingsController.setSystemDarkMode(isDark)
    );
    this.systemThemeMonitor.start();
    this.settingsInitialization = settingsController.initialize(this.context);
    settingsController.startCrossRuntimeSync();
    this.handleDirectControlWant(want);
    this.settingsInitialization.catch((err: Object) => {
      hilog.warn(DOMAIN, 'Settings', 'Settings initialization failed: %{public}s', JSON.stringify(err));
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    this.systemThemeMonitor?.stop();
    this.systemThemeMonitor = undefined;
    getSharedSettingsController().stopCrossRuntimeSync();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleDirectControlWant(want);
    this.requestedEntryPage = this.entryPageFromWant(want);
    if (this.contentLoaded) {
      router.replaceUrl({ url: this.requestedEntryPage }).catch((err: Object): void => {
        hilog.warn(DOMAIN, 'Settings', 'Entry page switch failed: %{public}s', JSON.stringify(err));
      });
    }
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.systemThemeMonitor?.refresh();
    this.syncSettingsWindow('configuration update');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    this.prepareSettingsWindow(windowStage).catch((err: Object): void => {
      hilog.warn(DOMAIN, 'SettingsWindow', 'Main window preparation failed: %{public}s', JSON.stringify(err));
      this.loadSettingsPage(windowStage);
    });
  }

  private async prepareSettingsWindow(windowStage: window.WindowStage): Promise<void> {
    let mainWindow: window.Window;
    try {
      mainWindow = await windowStage.getMainWindow();
    } catch (err) {
      hilog.warn(DOMAIN, 'SettingsWindow', 'getMainWindow failed: %{public}s', JSON.stringify(err));
      this.loadSettingsPage(windowStage);
      return;
    }
    if (this.settingsWindowCoordinator !== undefined) {
      this.settingsWindowCoordinator.stop();
      unregisterSharedSettingsWindowCoordinator(this.settingsWindowCoordinator);
    }
    const coordinator = new SettingsWindowCoordinator(
      getSharedSettingsController(),
      new HarmonySettingsWindowBackend(mainWindow)
    );
    this.settingsWindowCoordinator = coordinator;
    registerSharedSettingsWindowCoordinator(coordinator);
    this.loadSettingsPage(windowStage, (): void => {
      this.finishSettingsWindowPreparation(coordinator).catch((err: Object): void => {
        hilog.warn(
          DOMAIN,
          'SettingsWindow',
          'Post-load window preparation failed: %{public}s',
          JSON.stringify(err)
        );
      });
    });
  }

  private async finishSettingsWindowPreparation(coordinator: SettingsWindowCoordinator): Promise<void> {
    if (this.settingsWindowCoordinator !== coordinator) {
      return;
    }
    // Window avoid-area and UIContext APIs return 1300002 until loadContent has completed.
    // Starting the coordinator here guarantees that its first inset query uses a valid window.
    await coordinator.start();
    try {
      await this.settingsInitialization;
    } catch (err) {
      // Initialization already logs the storage error. Continue with the safe in-memory defaults.
    }
    if (this.settingsWindowCoordinator !== coordinator) {
      return;
    }
    await coordinator.sync();
  }

  private loadSettingsPage(windowStage: window.WindowStage, onLoaded?: () => void): void {
    const entryPage = this.requestedEntryPage;
    windowStage.loadContent(entryPage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      this.contentLoaded = true;
      onLoaded?.();
    });
  }

  private entryPageFromWant(want: Want): string {
    const value = want.parameters?.['entryPage'];
    return typeof value === 'string' && value === 'pages/UserLexicon' ? value : 'pages/Index';
  }

  onWindowStageDestroy(): void {
    this.contentLoaded = false;
    if (this.settingsWindowCoordinator !== undefined) {
      this.settingsWindowCoordinator.stop();
      unregisterSharedSettingsWindowCoordinator(this.settingsWindowCoordinator);
    }
    this.settingsWindowCoordinator = undefined;
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    this.systemThemeMonitor?.refresh();
    this.syncSettingsWindow('foreground');
    getSharedSettingsController().reload(this.context).catch((err: Object) => {
      hilog.warn(DOMAIN, 'Settings', 'Settings reload failed: %{public}s', JSON.stringify(err));
    }).then((): void => {
      this.syncSettingsWindow('settings reload');
    });
  }

  private syncSettingsWindow(reason: string): void {
    this.settingsWindowCoordinator?.sync().catch((err: Object): void => {
      hilog.warn(
        DOMAIN,
        'SettingsWindow',
        'Window synchronization failed after %{public}s: %{public}s',
        reason,
        JSON.stringify(err)
      );
    });
  }

  private handleDirectControlWant(want: Want): void {
    const parameters = want.parameters;
    if (parameters === undefined) {
      return;
    }
    const actionValue = parameters['imeAction'];
    if (typeof actionValue !== 'string' || actionValue.length <= 0) {
      return;
    }
    const targetValue = parameters['imeTarget'];
    const target = typeof targetValue === 'string' ? targetValue : '';
    const initialization = this.settingsInitialization ??
      getSharedSettingsController().initialize(this.context);
    initialization.then((): Promise<Object> => {
      return getSharedDirectControlService().executeRaw(actionValue, target);
    }).then((result: Object): void => {
      hilog.info(DOMAIN, 'DirectControl', 'Direct command completed: %{public}s', JSON.stringify(result));
    }).catch((err: Object): void => {
      hilog.warn(DOMAIN, 'DirectControl', 'Direct command failed: %{public}s', JSON.stringify(err));
    });
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
