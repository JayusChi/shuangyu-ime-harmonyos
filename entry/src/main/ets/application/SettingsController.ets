import common from '@ohos.app.ability.common';
import { Logger } from '../common/logging/Logger';
import {
  CandidateFontSizeMode,
  CandidatePresentationMode,
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  HapticLevel,
  ImeSettings,
  isAvailableScheme,
  KeyboardHeightMode,
  LexiconSourceConfig,
  normalizeXiaoheYinxingCategoryIds,
  QUANPIN_FUZZY_OPTIONS,
  QUANPIN_SCHEME_ID,
  QuanpinFuzzyOption,
  ThemeMode,
  XIAOHE_YINXING_CATEGORY_IDS,
  XIAOHE_YINXING_SCHEME_ID
} from '../domain/settings/ImeSettings';
import { SettingsRepository, SettingsRepositoryContract } from '../infrastructure/storage/SettingsRepository';
import { UserModelCommandRepository } from '../infrastructure/storage/UserModelCommandRepository';
import { UserModelCommandBus } from '../infrastructure/storage/UserModelCommandBus';
import { SettingsSyncBus } from '../infrastructure/storage/SettingsSyncBus';
import { SettingsValidator } from '../infrastructure/storage/SettingsValidator';
import { getSharedInputSessionStore, InputSessionStore } from '../state/InputSessionStore';
import { getSharedSettingsStore, SettingsStateListener, SettingsStore } from '../state/SettingsStore';
import { EngineCoordinator, getSharedEngineCoordinator } from './EngineCoordinator';
import { SerialActionExecutor } from './SerialActionExecutor';
import { YinxingBundleInstaller } from '../infrastructure/resource/YinxingBundleInstaller';
import { InputPresentationPreference } from '../domain/display/InputPresentationMode';
import {
  findKeyboardProfile,
  isEnabledKeyboardProfile,
  keyboardProfileForEngineScheme,
  keyboardProfileLayoutKind,
  KeyboardLayoutKind,
  XIAOHE_26_PROFILE_ID
} from '../domain/keyboard/KeyboardProfile';
import { CodeTableCategoryDefinition } from '../infrastructure/native/NativeEngineTypes';

const LOGGER = new Logger('SettingsController');
const MAIN_PROCESS_NAME = 'com.corrosion.shuangyuime';

export interface SettingsOperationResult {
  success: boolean;
  message: string;
}

type SettingsMutation = (settings: ImeSettings) => void;
type SettingsMutationTask = (settings: ImeSettings) => Promise<SettingsOperationResult>;

export class SettingsController {
  private readonly repository: SettingsRepositoryContract;
  private readonly store: SettingsStore;
  private readonly engine: EngineCoordinator;
  private readonly sessionStore: InputSessionStore;
  private readonly settingsMutationQueue: SerialActionExecutor = new SerialActionExecutor();
  private initializationTask?: Promise<ImeSettings>;
  private context?: common.Context;
  private readonly userModelCommands: UserModelCommandRepository = new UserModelCommandRepository();
  private readonly userModelCommandBus: UserModelCommandBus = new UserModelCommandBus();
  private readonly settingsSyncBus: SettingsSyncBus = new SettingsSyncBus();
  private readonly validator: SettingsValidator = new SettingsValidator();

  constructor(
    repository: SettingsRepositoryContract = new SettingsRepository(),
    store: SettingsStore = getSharedSettingsStore(),
    engine: EngineCoordinator = getSharedEngineCoordinator(),
    sessionStore: InputSessionStore = getSharedInputSessionStore()
  ) {
    this.repository = repository;
    this.store = store;
    this.engine = engine;
    this.sessionStore = sessionStore;
  }

  initialize(context: common.Context): Promise<ImeSettings> {
    this.context = context;
    if (this.initializationTask) {
      return this.initializationTask;
    }
    this.initializationTask = this.settingsMutationQueue.enqueue(async (): Promise<ImeSettings> => {
      return this.load(context);
    });
    return this.initializationTask;
  }

  async reload(context: common.Context): Promise<ImeSettings> {
    this.context = context;
    this.initializationTask = this.settingsMutationQueue.enqueue(async (): Promise<ImeSettings> => {
      return this.load(context);
    });
    return this.initializationTask;
  }

  getSettings(): ImeSettings {
    return this.store.getSnapshot();
  }

  isDarkMode(): boolean {
    return this.store.isDarkMode();
  }

  subscribe(listener: SettingsStateListener): void {
    this.store.subscribe(listener);
  }

  unsubscribe(listener: SettingsStateListener): void {
    this.store.unsubscribe(listener);
  }

  setSystemDarkMode(isDark: boolean): void {
    this.store.setSystemDarkMode(isDark);
  }

  startCrossRuntimeSync(): void {
    this.settingsSyncBus.subscribe((raw): void => {
      this.settingsMutationQueue.enqueue(async (): Promise<void> => {
        const previous = this.store.getSnapshot();
        const next = this.validator.validate(raw);
        LOGGER.info(
          `cross-runtime settings received: old={${this.describe(previous)}}, new={${this.describe(next)}}`
        );
        const runtimeProfileChanged = previous.keyboardProfileId !== next.keyboardProfileId ||
          previous.schemeId !== next.schemeId;
        if (this.engine.isInitialized() && runtimeProfileChanged) {
          let bundlePath: string | undefined = undefined;
          if (previous.schemeId !== next.schemeId && next.schemeId === XIAOHE_YINXING_SCHEME_ID) {
            if (!this.context) {
              LOGGER.warn('synchronized xiaohe-yinxing scheme has no input method context');
              return;
            }
            const installResult = await new YinxingBundleInstaller().installYinxingBundle(this.context);
            if (!installResult.success) {
              LOGGER.warn(`synchronized xiaohe-yinxing bundle unavailable: ${installResult.errorCode}`);
              return;
            }
            bundlePath = installResult.path;
          }
          const resetResult = this.engine.reset();
          if (!resetResult.success) {
            LOGGER.warn('synchronized profile composition could not be cleared');
            return;
          }
          this.sessionStore.clearComposition();
          if (previous.schemeId !== next.schemeId) {
            const schemeResult = this.engine.changeScheme(next.schemeId, bundlePath);
            if (!schemeResult.success) {
              this.engine.changeScheme(previous.schemeId);
              LOGGER.warn('synchronized scheme could not be applied');
              return;
            }
          }
        }
        const quanpinFeaturesChanged = previous.spellingCorrectionEnabled !==
          next.spellingCorrectionEnabled || previous.fuzzyOptions.join('|') !== next.fuzzyOptions.join('|');
        if (this.engine.isInitialized() && (quanpinFeaturesChanged ||
          (runtimeProfileChanged && next.schemeId === QUANPIN_SCHEME_ID))) {
          const activeQuanpin = this.engine.getActiveSchemeId() === QUANPIN_SCHEME_ID;
          const featureResult = this.engine.reconfigureQuanpin(
            next.spellingCorrectionEnabled,
            next.fuzzyOptions
          );
          if (!featureResult.success) {
            LOGGER.warn('synchronized quanpin feature configuration could not be applied');
            return;
          }
          if (activeQuanpin) {
            this.sessionStore.clearComposition();
          }
        }
        let categoryHandled: boolean = false;
        if (this.engine.isInitialized() && this.engine.getActiveSchemeId() === XIAOHE_YINXING_SCHEME_ID) {
          categoryHandled = true;
          if (previous.xiaoheYinxingEnabledCategoryIds.join('|') !==
            next.xiaoheYinxingEnabledCategoryIds.join('|')) {
            const categoryResult = this.engine.setCodeTableCategories(
              next.xiaoheYinxingEnabledCategoryIds
            );
            if (!categoryResult.success || categoryResult.commitText.length > 0) {
              LOGGER.warn('synchronized category selection could not be applied');
              return;
            }
            this.sessionStore.updateComposition(categoryResult);
          }
        }
        this.store.replace(next);
        this.applyCurrentSettingsToEngine(!categoryHandled);
        LOGGER.info('cross-runtime settings applied');
      }).catch((err: Object): void => {
        LOGGER.warn(`cross-runtime settings apply failed: ${JSON.stringify(err)}`);
      });
    }).catch((err: Object) => {
      LOGGER.warn(`settings synchronization failed: ${JSON.stringify(err)}`);
    });
  }

  stopCrossRuntimeSync(): void {
    this.settingsSyncBus.unsubscribe();
  }

  async setThemeMode(value: ThemeMode): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.themeMode = value;
    });
  }

  async setKeyboardHeightMode(value: KeyboardHeightMode): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.keyboardHeightMode = value;
    });
  }

  async setCandidateFontSizeMode(value: CandidateFontSizeMode): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.candidateFontSizeMode = value;
    });
  }

  async setHapticLevel(value: HapticLevel): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.hapticLevel = value;
    });
  }

  async setKeySoundEnabled(enabled: boolean): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.keySoundEnabled = enabled;
    });
  }

  async setSmartPeriodTimeoutMs(timeoutMs: number): Promise<SettingsOperationResult> {
    if (!Number.isInteger(timeoutMs) || timeoutMs < 0 || timeoutMs > 2000) {
      return { success: false, message: '智能句号时间参数无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.smartPeriodTimeoutMs = timeoutMs;
    });
  }

  async setCandidatePresentationMode(value: CandidatePresentationMode): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.candidatePresentationMode = value;
    });
  }

  async setInputPresentationPreference(value: InputPresentationPreference): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.inputPresentationPreference = value;
    });
  }

  async setUserLearningEnabled(enabled: boolean): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutationTask(async (settings: ImeSettings): Promise<SettingsOperationResult> => {
      if (this.engine.isInitialized()) {
        const status = this.engine.setUserLearningEnabled(enabled);
        if (status.lastErrorCode.length > 0) {
          return { success: false, message: '用户学习设置应用失败' };
        }
        const session = this.sessionStore.getSnapshot();
        const effectiveAllowed = enabled && session.editorContext.learningAllowed;
        this.engine.setSessionLearningAllowed(effectiveAllowed);
        this.sessionStore.updateLearningAllowed(effectiveAllowed);
      }
      settings.userLearningEnabled = enabled;
      return this.persist(settings);
    });
  }

  async setAiEnabled(enabled: boolean): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.aiEnabled = enabled;
      if (!enabled) {
        settings.cloudAiEnabled = false;
      }
    });
  }

  async setLocalAssociationEnabled(enabled: boolean): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.localAssociationEnabled = enabled;
    });
  }

  async setVoiceInputEnabled(enabled: boolean): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.voiceInputEnabled = enabled;
    });
  }

  async setSpellingCorrectionEnabled(enabled: boolean): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutationTask(async (previous: ImeSettings): Promise<SettingsOperationResult> => {
      return this.applyQuanpinFeatures(previous, enabled, previous.fuzzyOptions);
    });
  }

  async setFuzzyOption(option: QuanpinFuzzyOption, enabled: boolean): Promise<SettingsOperationResult> {
    if (QUANPIN_FUZZY_OPTIONS.indexOf(option) < 0) {
      return { success: false, message: '模糊音选项无效' };
    }
    return this.enqueueSettingsMutationTask(async (previous: ImeSettings): Promise<SettingsOperationResult> => {
      const requested = previous.fuzzyOptions.filter(
        (item: QuanpinFuzzyOption): boolean => item !== option
      );
      if (enabled) {
        requested.push(option);
      }
      const canonical = QUANPIN_FUZZY_OPTIONS.filter(
        (item: QuanpinFuzzyOption): boolean => requested.indexOf(item) >= 0
      );
      return this.applyQuanpinFeatures(
        previous,
        previous.spellingCorrectionEnabled,
        canonical
      );
    });
  }

  private async applyQuanpinFeatures(
    previous: ImeSettings,
    spellingCorrectionEnabled: boolean,
    fuzzyOptions: QuanpinFuzzyOption[]
  ): Promise<SettingsOperationResult> {
    let appliedToEngine = false;
    if (this.engine.isInitialized()) {
      const activeQuanpin = this.engine.getActiveSchemeId() === QUANPIN_SCHEME_ID;
      const result = this.engine.reconfigureQuanpin(spellingCorrectionEnabled, fuzzyOptions);
      if (!result.success) {
        return { success: false, message: '全拼纠错设置应用失败' };
      }
      appliedToEngine = true;
      if (activeQuanpin) {
        this.sessionStore.clearComposition();
      }
    }
    const next = copyImeSettings(previous);
    next.spellingCorrectionEnabled = spellingCorrectionEnabled;
    next.fuzzyOptions = fuzzyOptions.slice();
    try {
      const saved = await this.persist(next);
      if (saved.success) {
        return saved;
      }
    } catch (_err) {
    }
    if (appliedToEngine) {
      this.engine.reconfigureQuanpin(previous.spellingCorrectionEnabled, previous.fuzzyOptions);
    }
    return { success: false, message: '全拼纠错设置保存失败' };
  }

  async setXiaoheYinxingEnabledCategoryIds(
    enabledCategoryIds: string[]
  ): Promise<SettingsOperationResult> {
    if (enabledCategoryIds.some((id: string) => XIAOHE_YINXING_CATEGORY_IDS.indexOf(id) < 0)) {
      return { success: false, message: '分类标识无效' };
    }
    return this.enqueueSettingsMutationTask(async (previous: ImeSettings): Promise<SettingsOperationResult> => {
      let canonicalIds = normalizeXiaoheYinxingCategoryIds(enabledCategoryIds);
      let appliedToEngine: boolean = false;
      if (this.engine.isInitialized() && this.engine.getActiveSchemeId() === XIAOHE_YINXING_SCHEME_ID) {
        const result = this.engine.setCodeTableCategories(canonicalIds);
        if (!result.success || result.commitText.length > 0) {
          return { success: false, message: '分类设置应用失败' };
        }
        appliedToEngine = true;
        try {
          canonicalIds = this.engine.getCodeTableCategoryConfig().enabledCategoryIds;
        } catch (_err) {
          this.engine.setCodeTableCategories(previous.xiaoheYinxingEnabledCategoryIds);
          return { success: false, message: '分类设置应用失败' };
        }
        this.sessionStore.updateComposition(result);
      }
      const next = copyImeSettings(previous);
      next.xiaoheYinxingEnabledCategoryIds = canonicalIds.slice();
      try {
        const saved = await this.persist(next);
        if (saved.success) {
          return saved;
        }
      } catch (_err) {
      }
      if (appliedToEngine) {
        const rollback = this.engine.setCodeTableCategories(previous.xiaoheYinxingEnabledCategoryIds);
        if (rollback.success && rollback.commitText.length === 0) {
          this.sessionStore.updateComposition(rollback);
        }
      }
      return { success: false, message: '分类设置保存失败' };
    });
  }

  getCodeTableCategories(): CodeTableCategoryDefinition[] {
    if (!this.engine.isInitialized() || this.engine.getActiveSchemeId() !== XIAOHE_YINXING_SCHEME_ID) {
      return [];
    }
    try {
      const config = this.engine.getCodeTableCategoryConfig();
      return config.categories;
    } catch (err) {
      LOGGER.warn(`Failed to get code table categories: ${JSON.stringify(err)}`);
      return [];
    }
  }

  getEnabledCategoryIds(): string[] {
    const settings = this.getSettings();
    return settings.xiaoheYinxingEnabledCategoryIds.slice();
  }

  async toggleCategory(categoryId: string, enabled: boolean): Promise<SettingsOperationResult> {
    const current = this.getEnabledCategoryIds();
    const index = current.indexOf(categoryId);

    if (enabled && index < 0) {
      current.push(categoryId);
    } else if (!enabled && index >= 0) {
      current.splice(index, 1);
    } else {
      return { success: true, message: '' };
    }

    return this.setXiaoheYinxingEnabledCategoryIds(current);
  }

  async changeScheme(schemeId: string): Promise<SettingsOperationResult> {
    if (!isAvailableScheme(schemeId)) {
      return { success: false, message: '输入方案不可用' };
    }
    const current = this.getSettings();
    const profileId = keyboardProfileForEngineScheme(
      schemeId,
      keyboardProfileLayoutKind(current.keyboardProfileId)
    ) ?? keyboardProfileForEngineScheme(schemeId, KeyboardLayoutKind.T9_9_KEY) ??
      keyboardProfileForEngineScheme(schemeId, KeyboardLayoutKind.QWERTY_26_KEY);
    if (!profileId) {
      return { success: false, message: '键盘档案不可用' };
    }
    return this.setKeyboardProfile(profileId);
  }

  async setKeyboardProfile(profileId: string): Promise<SettingsOperationResult> {
    if (!isEnabledKeyboardProfile(profileId)) {
      return { success: false, message: '键盘档案不可用' };
    }
    const target = findKeyboardProfile(profileId);
    if (!target) {
      return { success: false, message: '键盘档案不可用' };
    }
    return this.enqueueSettingsMutationTask(async (previous: ImeSettings): Promise<SettingsOperationResult> => {
      if (previous.keyboardProfileId === profileId) {
        return { success: true, message: '' };
      }

      const schemeId = target.engineSchemeId;
      const schemeChanged = previous.schemeId !== schemeId;

      let bundlePath: string | undefined = undefined;
      if (schemeChanged && schemeId === XIAOHE_YINXING_SCHEME_ID) {
        if (!this.context) {
          return { success: false, message: '输入法上下文未初始化' };
        }
        const installer = new YinxingBundleInstaller();
        const installResult = await installer.installYinxingBundle(this.context);
        if (!installResult.success) {
          LOGGER.error(`xiaohe-yinxing bundle install failed: ${installResult.errorCode} - ${installResult.errorMessage}`);
          return { success: false, message: '音形资源安装失败' };
        }
        bundlePath = installResult.path;
        LOGGER.info('xiaohe-yinxing bundle is ready');
      }

      if (this.engine.isInitialized()) {
        // A profile switch is also a composition boundary when both profiles
        // share the same Rust scheme (for example xiaohe-17 -> xiaohe-26).
        // Reset Native first so a failed reset cannot leave a cleared ArkTS UI
        // pointing at a live old composition.
        const reset = this.engine.reset();
        if (!reset.success) {
          return { success: false, message: '键盘组合清理失败' };
        }
        this.sessionStore.clearComposition();
        if (schemeChanged) {
          const result = this.engine.changeScheme(schemeId, bundlePath);
          if (!result.success) {
            this.engine.changeScheme(previous.schemeId);
            return { success: false, message: '键盘方案切换失败' };
          }
          if (schemeId === QUANPIN_SCHEME_ID) {
            const featureResult = this.engine.reconfigureQuanpin(
              previous.spellingCorrectionEnabled,
              previous.fuzzyOptions
            );
            if (!featureResult.success) {
              this.engine.changeScheme(previous.schemeId);
              return { success: false, message: '全拼纠错设置恢复失败' };
            }
          }
        }
      } else if (schemeChanged && schemeId === XIAOHE_YINXING_SCHEME_ID && bundlePath) {
        // The settings UI runs in the main process, separate from the live IME.
        // Validate the production bundle through ArkTS -> C++ -> Rust before
        // persisting and broadcasting the choice.
        const validation = this.engine.initialize(
          XIAOHE_YINXING_SCHEME_ID,
          undefined,
          undefined,
          500,
          bundlePath
        );
        this.engine.dispose();
        if (!validation.success) {
          return { success: false, message: '音形资源校验失败' };
        }
      }
      const next = copyImeSettings(previous);
      next.keyboardProfileId = profileId;
      next.schemeId = schemeId;
      const saved = await this.persist(next);
      if (!saved.success && schemeChanged && this.engine.isInitialized()) {
        this.engine.changeScheme(previous.schemeId);
      }
      return saved;
    });
  }

  async clearUserModel(): Promise<SettingsOperationResult> {
    const context = this.context;
    if (!context) {
      return { success: false, message: '输入引擎尚未初始化' };
    }
    const requested = await this.userModelCommands.requestClear(context);
    const published = await this.userModelCommandBus.publishClear();
    if (!requested && !published) {
      return { success: false, message: '清空请求保存失败' };
    }
    if (!this.engine.isInitialized()) {
      return { success: true, message: '' };
    }
    const status = this.engine.clearUserModel();
    if (status.lastErrorCode.length > 0) {
      return { success: false, message: '清空用户词频失败' };
    }
    this.sessionStore.clearComposition();
    return { success: true, message: '' };
  }

  async resetToDefaults(): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutationTask(async (previous: ImeSettings): Promise<SettingsOperationResult> => {
      let quanpinApplied = false;
      if (this.engine.isInitialized()) {
        const activeQuanpin = this.engine.getActiveSchemeId() === QUANPIN_SCHEME_ID;
        const featureResult = this.engine.reconfigureQuanpin(
          DEFAULT_IME_SETTINGS.spellingCorrectionEnabled,
          DEFAULT_IME_SETTINGS.fuzzyOptions
        );
        if (!featureResult.success) {
          return { success: false, message: '恢复默认全拼设置失败' };
        }
        quanpinApplied = true;
        if (activeQuanpin) {
          this.sessionStore.clearComposition();
        }
      }
      const reset = await this.repository.reset();
      if (!reset) {
        if (quanpinApplied) {
          this.engine.reconfigureQuanpin(previous.spellingCorrectionEnabled, previous.fuzzyOptions);
        }
        return { success: false, message: '恢复默认设置失败' };
      }
      const defaults = copyImeSettings(DEFAULT_IME_SETTINGS);
      this.store.replace(defaults);
      this.applyCurrentSettingsToEngine();
      this.publishSettings(defaults);
      return { success: true, message: '' };
    });
  }

  applyCurrentSettingsToEngine(applyCategories: boolean = true): void {
    if (!this.engine.isInitialized()) {
      return;
    }
    const settings = this.getSettings();
    const currentSession = this.sessionStore.getSnapshot();
    this.engine.setUserLearningEnabled(settings.userLearningEnabled);
    this.engine.setSessionLearningAllowed(
      settings.userLearningEnabled && currentSession.editorContext.learningAllowed
    );
    this.sessionStore.updateLearningAllowed(
      settings.userLearningEnabled && currentSession.editorContext.learningAllowed
    );
    if (applyCategories && this.engine.getActiveSchemeId() === XIAOHE_YINXING_SCHEME_ID) {
      const categoryResult = this.engine.setCodeTableCategories(
        settings.xiaoheYinxingEnabledCategoryIds
      );
      if (categoryResult.success && categoryResult.commitText.length === 0) {
        this.sessionStore.updateComposition(categoryResult);
      }
    }
  }

  private async load(context: common.Context): Promise<ImeSettings> {
    let settings = await this.repository.load(context);

    if (settings.schemeId === XIAOHE_YINXING_SCHEME_ID) {
      const installer = new YinxingBundleInstaller();
      const installResult = await installer.installYinxingBundle(context);
      if (!installResult.success) {
        LOGGER.warn(`xiaohe-yinxing bundle unavailable on startup: ${installResult.errorCode} - ${installResult.errorMessage}, falling back to xiaohe`);
        settings = copyImeSettings(settings);
        settings.keyboardProfileId = keyboardProfileForEngineScheme(
          'xiaohe',
          keyboardProfileLayoutKind(settings.keyboardProfileId)
        ) ?? XIAOHE_26_PROFILE_ID;
        settings.schemeId = 'xiaohe';
        try {
          await this.repository.save(settings);
        } catch (err) {
          LOGGER.warn(`failed to persist fallback scheme: ${JSON.stringify(err)}`);
        }
      } else {
        LOGGER.info('xiaohe-yinxing bundle is ready');
      }
    }

    this.store.replace(settings);
    this.applyCurrentSettingsToEngine();
    if (context.processName === MAIN_PROCESS_NAME) {
      this.publishSettings(settings);
    }
    LOGGER.info(`settings loaded: process=${context.processName}, ${this.describe(settings)}`);
    return settings;
  }

  private enqueueSettingsMutation(mutation: SettingsMutation): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutationTask(async (settings: ImeSettings): Promise<SettingsOperationResult> => {
      mutation(settings);
      return this.persist(settings);
    });
  }

  private enqueueSettingsMutationTask(task: SettingsMutationTask): Promise<SettingsOperationResult> {
    return this.settingsMutationQueue.enqueue(async (): Promise<SettingsOperationResult> => {
      // Read only after earlier mutations have persisted and replaced the Store.
      const latest = this.getSettings();
      return task(latest);
    });
  }

  private async persist(settings: ImeSettings): Promise<SettingsOperationResult> {
    let saved: boolean;
    try {
      saved = await this.repository.save(settings);
    } catch (err) {
      const detail = JSON.stringify(err);
      LOGGER.warn(`settings save rejected: ${detail}`);
      throw new Error(`settings save rejected: ${detail}`);
    }
    if (!saved) {
      return { success: false, message: '设置保存失败' };
    }
    this.store.replace(settings);
    this.publishSettings(settings);
    return { success: true, message: '' };
  }

  private publishSettings(settings: ImeSettings): void {
    this.settingsSyncBus.publish(settings).then((published: boolean) => {
      if (!published) {
        LOGGER.warn('settings cross-runtime publish failed');
      }
    }).catch((err: Object) => {
      LOGGER.warn(`settings cross-runtime publish failed: ${JSON.stringify(err)}`);
    });
  }

  private describe(settings: ImeSettings): string {
    return `keyboardProfileId=${settings.keyboardProfileId}, schemeId=${settings.schemeId}, ` +
      `keyboardHeightMode=${settings.keyboardHeightMode}, ` +
      `candidateFontSizeMode=${settings.candidateFontSizeMode}, hapticLevel=${settings.hapticLevel}, ` +
      `keySoundEnabled=${settings.keySoundEnabled}, userLearningEnabled=${settings.userLearningEnabled}, ` +
      `spellingCorrectionEnabled=${settings.spellingCorrectionEnabled}, ` +
      `smartPeriodTimeoutMs=${settings.smartPeriodTimeoutMs}, ` +
      `fuzzyOptions=${settings.fuzzyOptions.join('|')}, ` +
      `inputPresentationPreference=${settings.inputPresentationPreference}, ` +
      `xiaoheYinxingEnabledCategoryCount=${settings.xiaoheYinxingEnabledCategoryIds.length}`;
  }

  getLexiconSources(): LexiconSourceConfig[] {
    return this.getSettings().lexiconSources.slice();
  }

  async addLexiconSource(source: LexiconSourceConfig): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutationTask(async (previous: ImeSettings): Promise<SettingsOperationResult> => {
      if (!this.isValidLexiconSource(source)) {
        return { success: false, message: '词库来源配置无效' };
      }
      const sources = previous.lexiconSources.slice();
      const existingIndex = sources.findIndex((s: LexiconSourceConfig) => s.id === source.id);
      if (existingIndex >= 0) {
        return { success: false, message: '词库源ID已存在' };
      }
      sources.push(source);
      const next = copyImeSettings(previous);
      next.lexiconSources = sources;
      return this.persist(next);
    });
  }

  async updateLexiconSource(sourceId: string, updates: Partial<LexiconSourceConfig>): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutationTask(async (previous: ImeSettings): Promise<SettingsOperationResult> => {
      const sources = previous.lexiconSources.slice();
      const index = sources.findIndex((s: LexiconSourceConfig) => s.id === sourceId);
      if (index < 0) {
        return { success: false, message: '词库源不存在' };
      }
      const current = sources[index];
      sources[index] = {
        id: current.id,
        displayName: updates.displayName !== undefined ? updates.displayName : current.displayName,
        filePath: updates.filePath !== undefined ? updates.filePath : current.filePath,
        enabled: updates.enabled !== undefined ? updates.enabled : current.enabled,
        priority: updates.priority !== undefined ? updates.priority : current.priority,
        mode: updates.mode !== undefined ? updates.mode : current.mode
      };
      if (!this.isValidLexiconSource(sources[index])) {
        return { success: false, message: '词库来源配置无效' };
      }
      const next = copyImeSettings(previous);
      next.lexiconSources = sources;
      return this.persist(next);
    });
  }

  async removeLexiconSource(sourceId: string): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutationTask(async (previous: ImeSettings): Promise<SettingsOperationResult> => {
      const sources = previous.lexiconSources.filter((s: LexiconSourceConfig) => s.id !== sourceId);
      if (sources.length === previous.lexiconSources.length) {
        return { success: false, message: '词库源不存在' };
      }
      const next = copyImeSettings(previous);
      next.lexiconSources = sources;
      return this.persist(next);
    });
  }

  async updateXiaoheYinxingEnabledCategories(categoryIds: string[]): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutationTask(async (previous: ImeSettings): Promise<SettingsOperationResult> => {
      const normalized = normalizeXiaoheYinxingCategoryIds(categoryIds);
      const next = copyImeSettings(previous);
      next.xiaoheYinxingEnabledCategoryIds = normalized;
      return this.persist(next);
    });
  }

  private isValidLexiconSource(source: LexiconSourceConfig): boolean {
    return source.id.length > 0 && source.id.length <= 128 &&
      source.displayName.length > 0 && source.displayName.length <= 256 &&
      source.filePath.length > 0 && source.filePath.length <= 4096 &&
      Number.isInteger(source.priority) && source.priority >= 0 &&
      (source.mode === 'REPLACE' || source.mode === 'APPEND' || source.mode === 'MERGE');
  }
}

const SHARED_SETTINGS_CONTROLLER = new SettingsController();

export function getSharedSettingsController(): SettingsController {
  return SHARED_SETTINGS_CONTROLLER;
}
