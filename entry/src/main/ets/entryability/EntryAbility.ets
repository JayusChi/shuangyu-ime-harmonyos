import picker from '@ohos.file.picker';
import { isExternalDirectTarget } from '../domain/direct/ExternalDirectTarget';
import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, Router, window } from '@kit.ArkUI';
import { getSharedSettingsController } from '../application/SettingsController';
import { HarmonySystemThemeBackend, SystemThemeMonitor } from '../application/SystemThemeMonitor';
import {
  HarmonySettingsWindowBackend,
  registerSharedSettingsWindowCoordinator,
  SettingsWindowCoordinator,
  unregisterSharedSettingsWindowCoordinator
} from '../application/SettingsWindowCoordinator';
import { getSharedDirectControlService } from '../application/DirectControlService';
import { getSharedKeyboardCustomizationRepository } from '../infrastructure/customization/KeyboardCustomizationRepository';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private systemThemeMonitor?: SystemThemeMonitor;
  private settingsInitialization?: Promise<Object>;
  private settingsWindowCoordinator?: SettingsWindowCoordinator;
  private entryRouter?: Router;
  private requestedEntryPage: string = 'pages/Index';
  private contentLoaded: boolean = false;
  private pendingDirectoryUri: string = '';
  private directoryPickerOpen: boolean = false;

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
    // Migrate packages imported by older versions before publishing the saved
    // selection. Only the main App writes to the input method's shared group.
    this.settingsInitialization = getSharedKeyboardCustomizationRepository().initialize(this.context, true)
      .then(() => settingsController.initialize(this.context));
    settingsController.startCrossRuntimeSync();
    this.handleDirectControlWant(want);
    const directory = want.parameters?.['openDirectoryUri'];
    this.pendingDirectoryUri = typeof directory === 'string' && isExternalDirectTarget('directory.open', directory)
      ? directory : '';
    this.openPendingDirectory();
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
    const directory = want.parameters?.['openDirectoryUri'];
    this.pendingDirectoryUri = typeof directory === 'string' && isExternalDirectTarget('directory.open', directory)
      ? directory : '';
    this.openPendingDirectory();
    this.requestedEntryPage = this.entryPageFromWant(want);
    if (this.contentLoaded && this.entryRouter) {
      try {
        this.entryRouter.replaceUrl({ url: this.requestedEntryPage }).catch((err: Object): void => {
          hilog.warn(DOMAIN, 'Settings', 'Entry page switch failed: %{public}s', JSON.stringify(err));
        });
      } catch (err) {
        hilog.warn(DOMAIN, 'Settings', 'Entry page switch failed: %{public}s', JSON.stringify(err));
      }
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
      this.entryRouter = mainWindow.getUIContext().getRouter();
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
      // Some phone windows are not ready before loadContent (1300002).
      // Recover the router here so a later clipboard Want can still switch pages.
      try {
        this.entryRouter = windowStage.getMainWindowSync().getUIContext().getRouter();
        if (entryPage !== this.requestedEntryPage) {
          this.entryRouter.replaceUrl({ url: this.requestedEntryPage }).catch((err: Object): void => {
            hilog.warn(DOMAIN, 'Settings', 'Pending entry page switch failed: %{public}s', JSON.stringify(err));
          });
        }
      } catch (err) {
        hilog.warn(DOMAIN, 'Settings', 'Loaded page router unavailable: %{public}s', JSON.stringify(err));
      }
      this.openPendingDirectory();
      onLoaded?.();
    });
  }

  private openPendingDirectory(): void {
    if (!this.contentLoaded || this.directoryPickerOpen || this.pendingDirectoryUri.length === 0) {
      return;
    }
    const uri = this.pendingDirectoryUri;
    this.pendingDirectoryUri = '';
    this.directoryPickerOpen = true;
    new picker.DocumentViewPicker(this.context).select({
      defaultFilePathUri: uri, maxSelectNumber: 1, selectMode: picker.DocumentSelectMode.FILE
    }).catch((): void => {
      try {
        promptAction.showToast({ message: '目录无法打开，请在用户词库中重新选择目录' });
        hilog.warn(DOMAIN, 'DirectControl', 'Cannot open saved directory');
      } catch (_) {}
    }).finally((): void => {
      this.directoryPickerOpen = false;
      this.openPendingDirectory();
    });
  }

  private entryPageFromWant(want: Want): string {
    if (want.parameters?.['shapeLookupFromClipboard'] === true) { return 'pages/ShapeLookup'; }
    const value = want.parameters?.['entryPage'];
    return typeof value === 'string' && value === 'pages/UserLexicon' ? value : 'pages/Index';
  }

  onWindowStageDestroy(): void {
    this.contentLoaded = false;
    this.entryRouter = undefined;
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
    this.openPendingDirectory();
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
