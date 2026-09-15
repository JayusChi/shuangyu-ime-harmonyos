import common from '@ohos.app.ability.common';
import { Logger } from '../common/logging/Logger';
import {
  CandidateFontSizeMode,
  DEFAULT_CANDIDATE_FONT_SIZE,
  DEFAULT_KEYBOARD_FONT_SIZE,
  MIN_KEYBOARD_FONT_SIZE,
  MAX_KEYBOARD_FONT_SIZE,
  MIN_UPPER_LABEL_RIGHT_MARGIN,
  MAX_UPPER_LABEL_RIGHT_MARGIN,
  DEFAULT_FLOATING_CANDIDATE_FONT_SIZE,
  MIN_CANDIDATE_DISPLAY_COUNT, MAX_CANDIDATE_DISPLAY_COUNT,
  KEYBOARD_HEIGHT_MODE_OPTIONS,
  legacyCandidateFontSize,
  MAX_CANDIDATE_FONT_SIZE,
  MIN_CANDIDATE_FONT_SIZE,
  CandidatePresentationMode,
  copyImeSettings,
  DEFAULT_IME_SETTINGS,
  HapticLevel,
  ImeSettings,
  isAvailableScheme,
  KeyboardHeightMode,
  MAX_LONG_PRESS_DURATION_MS,
  MIN_LONG_PRESS_DURATION_MS,
  PunctuationMode,
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
import { normalizeSmartPunctuationSymbols } from '../domain/keyboard/SmartPunctuation';
import { normalizeLetterSwipeSymbols } from '../domain/keyboard/LetterSwipeSymbols';
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

  startCrossRuntimeSync(readOnlySharedFile: boolean = false): void {
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
              this.applyCurrentSettingsToEngine();
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
          if (runtimeProfileChanged || previous.xiaoheYinxingEnabledCategoryIds.join('|') !==
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
          if (runtimeProfileChanged || previous.codeTableAutoCommitEnabled !== next.codeTableAutoCommitEnabled ||
            previous.codeTableEmptyClearLength !== next.codeTableEmptyClearLength ||
            previous.codeTableReverseSplitEnabled !== next.codeTableReverseSplitEnabled) {
            const policyResult = this.engine.setCodeTableCommitPolicy(
              next.codeTableAutoCommitEnabled,
              next.codeTableEmptyClearLength,
              next.codeTableReverseSplitEnabled
            );
            if (!policyResult.success || policyResult.commitText.length > 0) {
              LOGGER.warn('synchronized code table commit policy could not be applied');
              return;
            }
            this.sessionStore.updateComposition(policyResult);
          }
        }
        this.store.replace(next);
        this.applyCurrentSettingsToEngine(!categoryHandled);
        LOGGER.info('cross-runtime settings applied');
      }).catch((err: Object): void => {
        LOGGER.warn(`cross-runtime settings apply failed: ${JSON.stringify(err)}`);
      });
    }, readOnlySharedFile ? this.context : undefined).catch((err: Object) => {
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

  async setKeyboardStructureId(value: string): Promise<SettingsOperationResult> {
    if (!this.isValidCustomizationId(value)) {
      return { success: false, message: '键盘结构标识无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.keyboardStructureId = value;
    });
  }

  async setKeyboardSkinId(value: string): Promise<SettingsOperationResult> {
    if (!this.isValidCustomizationId(value)) {
      return { success: false, message: '键盘皮肤标识无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.keyboardSkinId = value;
    });
  }

  async setKeyboardHeightMode(value: KeyboardHeightMode): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.keyboardHeightMode = value;
    });
  }

  async setKeyboardLiftLayerEnabled(enabled: boolean): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.keyboardLiftLayerEnabled = enabled;
    });
  }

  async setCandidateFontSizeMode(value: CandidateFontSizeMode): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.candidateFontSizeMode = value;
      settings.candidateFontSize = legacyCandidateFontSize(value, false);
      settings.floatingCandidateFontSize = legacyCandidateFontSize(value, true);
    });
  }

  async adjustKeyboardHeight(target: string): Promise<SettingsOperationResult> {
    if (target !== 'default' && target !== 'increase' && target !== 'decrease') {
      return { success: false, message: '键盘高度操作无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      const index = KEYBOARD_HEIGHT_MODE_OPTIONS.indexOf(settings.keyboardHeightMode);
      const next = target === 'default' ? 4 : index + (target === 'increase' ? 1 : -1);
      settings.keyboardHeightMode = KEYBOARD_HEIGHT_MODE_OPTIONS[
        Math.max(0, Math.min(KEYBOARD_HEIGHT_MODE_OPTIONS.length - 1, next))];
    });
  }

  async setKeyboardHeightScale(value: number): Promise<SettingsOperationResult> {
    const index = Math.round((value * 100 - 80) / 5);
    if (!Number.isFinite(value) || value < 0.8 || value > 1.2 ||
      index < 0 || index >= KEYBOARD_HEIGHT_MODE_OPTIONS.length) {
      return { success: false, message: '键盘高度无效' };
    }
    return this.setKeyboardHeightMode(KEYBOARD_HEIGHT_MODE_OPTIONS[index]);
  }

  async adjustKeyboardFontSize(target: string): Promise<SettingsOperationResult> {
    if (target !== 'default' && target !== 'increase' && target !== 'decrease') {
      return { success: false, message: '键盘字号操作无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      const next = target === 'default' ? DEFAULT_KEYBOARD_FONT_SIZE :
        settings.keyboardFontSize + (target === 'increase' ? 2 : -1);
      settings.keyboardFontSize = Math.max(MIN_KEYBOARD_FONT_SIZE, Math.min(MAX_KEYBOARD_FONT_SIZE, next));
    });
  }

  async setKeyboardFontSizeOffset(value: number): Promise<SettingsOperationResult> {
    const size = DEFAULT_KEYBOARD_FONT_SIZE + value;
    if (!Number.isInteger(value) || size < MIN_KEYBOARD_FONT_SIZE || size > MAX_KEYBOARD_FONT_SIZE) {
      return { success: false, message: '键盘字号增减量无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.keyboardFontSize = size;
    });
  }

  async setUpperLabelRightMargin(value: number): Promise<SettingsOperationResult> {
    if (!Number.isInteger(value) || value < MIN_UPPER_LABEL_RIGHT_MARGIN ||
      value > MAX_UPPER_LABEL_RIGHT_MARGIN) {
      return { success: false, message: '上档符号右边距无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.upperLabelRightMargin = value;
    });
  }

  async adjustCandidateFontSize(floating: boolean, target: string): Promise<SettingsOperationResult> {
    if (target !== 'default' && target !== 'increase' && target !== 'decrease') {
      return { success: false, message: '候选字号操作无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      const current = floating ? settings.floatingCandidateFontSize : settings.candidateFontSize;
      const next = target === 'default' ?
        (floating ? DEFAULT_FLOATING_CANDIDATE_FONT_SIZE : DEFAULT_CANDIDATE_FONT_SIZE) :
        current + (target === 'increase' ? 2 : -1);
      const size = Math.max(MIN_CANDIDATE_FONT_SIZE, Math.min(MAX_CANDIDATE_FONT_SIZE, next));
      if (floating) { settings.floatingCandidateFontSize = size; } else { settings.candidateFontSize = size; }
    });
  }

  async setCandidateFontSize(value: number, floating: boolean = false): Promise<SettingsOperationResult> {
    if (!Number.isInteger(value) || value < MIN_CANDIDATE_FONT_SIZE || value > MAX_CANDIDATE_FONT_SIZE) {
      return { success: false, message: '候选字号无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      if (floating) { settings.floatingCandidateFontSize = value; } else { settings.candidateFontSize = value; }
    });
  }

  async setHapticEnabled(enabled: boolean): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.hapticLevel = enabled ?
        (settings.hapticLevel === HapticLevel.OFF ? HapticLevel.LIGHT : settings.hapticLevel) : HapticLevel.OFF;
    });
  }

  async setCandidateDisplayCount(value: number): Promise<SettingsOperationResult> {
    if (!Number.isInteger(value) || value < MIN_CANDIDATE_DISPLAY_COUNT || value > MAX_CANDIDATE_DISPLAY_COUNT) {
      return { success: false, message: '候选显示数量无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => { settings.candidateDisplayCount = value; });
  }

  async setKeySoundVolume(value: number): Promise<SettingsOperationResult> {
    if (!Number.isInteger(value) || value < 0 || value > 100) {
      return { success: false, message: '按键音量无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => { settings.keySoundVolume = value; });
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
      return { success: false, message: '智能标点时间参数无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.smartPeriodTimeoutMs = timeoutMs;
    });
  }

  async setLongPressDurationMs(durationMs: number): Promise<SettingsOperationResult> {
    if (!Number.isInteger(durationMs) || durationMs < MIN_LONG_PRESS_DURATION_MS ||
      durationMs > MAX_LONG_PRESS_DURATION_MS) {
      return { success: false, message: '长按时间参数无效' };
    }
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.longPressDurationMs = durationMs;
    });
  }

  async setSmartPunctuationSymbols(symbols: string): Promise<SettingsOperationResult> {
    const normalized = normalizeSmartPunctuationSymbols(symbols);
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.smartPunctuationSymbols = normalized;
    });
  }

  async setLetterSwipeSymbols(
    chineseSymbols: string,
    englishSymbols: string
  ): Promise<SettingsOperationResult> {
    const normalizedChinese = normalizeLetterSwipeSymbols(chineseSymbols);
    const normalizedEnglish = normalizeLetterSwipeSymbols(englishSymbols);
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.chineseLetterSwipeSymbols = normalizedChinese;
      settings.englishLetterSwipeSymbols = normalizedEnglish;
    });
  }

  async togglePunctuationMode(): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.punctuationMode = settings.punctuationMode === PunctuationMode.CHINESE ?
        PunctuationMode.ENGLISH : PunctuationMode.CHINESE;
    });
  }

  async toggleFullWidthEnabled(): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.fullWidthEnabled = !settings.fullWidthEnabled;
    });
  }

  async setNumericPeriodEnabled(enabled: boolean): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.numericPeriodEnabled = enabled;
    });
  }

  async toggleTraditionalOutputEnabled(): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.traditionalOutputEnabled = !settings.traditionalOutputEnabled;
    });
  }

  async setCodeTableCommitPolicy(
    autoCommitEnabled?: boolean,
    emptyClearLength?: number,
    reverseSplitEnabled?: boolean
  ): Promise<SettingsOperationResult> {
    if (emptyClearLength !== undefined && emptyClearLength !== 4 && emptyClearLength !== 12) {
      return { success: false, message: '音形清码阈值无效' };
    }
    return this.enqueueSettingsMutationTask(async (previous: ImeSettings): Promise<SettingsOperationResult> => {
      const splitEnabled = reverseSplitEnabled ?? previous.codeTableReverseSplitEnabled;
      const nextAutoCommitEnabled = autoCommitEnabled ?? previous.codeTableAutoCommitEnabled;
      const nextEmptyClearLength = emptyClearLength ?? previous.codeTableEmptyClearLength;
      let applied = false;
      if (this.engine.isInitialized() && this.engine.getActiveSchemeId() === XIAOHE_YINXING_SCHEME_ID) {
        const result = this.engine.setCodeTableCommitPolicy(nextAutoCommitEnabled, nextEmptyClearLength, splitEnabled);
        if (!result.success || result.commitText.length > 0) {
          return { success: false, message: '音形顶屏策略应用失败' };
        }
        applied = true;
        this.sessionStore.updateComposition(result);
      }
      const next = copyImeSettings(previous);
      next.codeTableAutoCommitEnabled = nextAutoCommitEnabled;
      next.codeTableEmptyClearLength = nextEmptyClearLength;
      next.codeTableReverseSplitEnabled = splitEnabled;
      let saved: SettingsOperationResult;
      try {
        saved = await this.persist(next);
      } catch (_err) {
        saved = { success: false, message: '音形输入设置保存失败' };
      }
      if (saved.success) {
        return saved;
      }
      if (applied) {
        this.engine.setCodeTableCommitPolicy(
          previous.codeTableAutoCommitEnabled,
          previous.codeTableEmptyClearLength,
          previous.codeTableReverseSplitEnabled
        );
      }
      return saved;
    });
  }

  async setCodeTableReverseSplitEnabled(enabled: boolean): Promise<SettingsOperationResult> {
    return this.setCodeTableCommitPolicy(undefined, undefined, enabled);
  }

  async setCandidatePresentationMode(value: CandidatePresentationMode): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => {
      settings.candidatePresentationMode = value;
    });
  }

  async setInlinePreeditEnabled(value: boolean): Promise<SettingsOperationResult> {
    return this.enqueueSettingsMutation((settings: ImeSettings): void => { settings.inlinePreeditEnabled = value; });
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
            this.applyCurrentSettingsToEngine();
            return { success: false, message: '键盘方案切换失败' };
          }
          if (schemeId === QUANPIN_SCHEME_ID) {
            const featureResult = this.engine.reconfigureQuanpin(
              previous.spellingCorrectionEnabled,
              previous.fuzzyOptions
            );
            if (!featureResult.success) {
              this.engine.changeScheme(previous.schemeId);
              this.applyCurrentSettingsToEngine();
              return { success: false, message: '全拼纠错设置恢复失败' };
            }
          }
          if (schemeId === XIAOHE_YINXING_SCHEME_ID) {
            const categoryResult = this.engine.setCodeTableCategories(previous.xiaoheYinxingEnabledCategoryIds);
            const policyResult = this.engine.setCodeTableCommitPolicy(
              previous.codeTableAutoCommitEnabled,
              previous.codeTableEmptyClearLength,
              previous.codeTableReverseSplitEnabled
            );
            if (!categoryResult.success || !policyResult.success) {
              this.engine.changeScheme(previous.schemeId);
              this.applyCurrentSettingsToEngine();
              return { success: false, message: '音形输入设置恢复失败' };
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
      let saved: SettingsOperationResult;
      try {
        saved = await this.persist(next);
      } catch (_err) {
        saved = { success: false, message: '键盘方案保存失败' };
      }
      if (!saved.success && schemeChanged && this.engine.isInitialized()) {
        this.engine.changeScheme(previous.schemeId);
        this.applyCurrentSettingsToEngine();
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
    const settings = this.getSettings();
    this.engine.setTraditionalOutputEnabled(settings.traditionalOutputEnabled);
    if (!this.engine.isInitialized()) {
      return;
    }
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
      const policyResult = this.engine.setCodeTableCommitPolicy(
        settings.codeTableAutoCommitEnabled,
        settings.codeTableEmptyClearLength,
        settings.codeTableReverseSplitEnabled
      );
      if (!policyResult.success) {
        LOGGER.warn('persisted code table commit policy could not be applied');
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
    this.engine.setTraditionalOutputEnabled(settings.traditionalOutputEnabled);
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
      `keyboardStructureId=${settings.keyboardStructureId}, keyboardSkinId=${settings.keyboardSkinId}, ` +
      `keyboardHeightMode=${settings.keyboardHeightMode}, ` +
      `candidateFontSizeMode=${settings.candidateFontSizeMode}, hapticLevel=${settings.hapticLevel}, ` +
      `keySoundEnabled=${settings.keySoundEnabled}, userLearningEnabled=${settings.userLearningEnabled}, ` +
      `spellingCorrectionEnabled=${settings.spellingCorrectionEnabled}, ` +
      `smartPeriodTimeoutMs=${settings.smartPeriodTimeoutMs}, ` +
      `longPressDurationMs=${settings.longPressDurationMs}, ` +
      `smartPunctuationSymbols=${JSON.stringify(settings.smartPunctuationSymbols)}, ` +
      `fuzzyOptions=${settings.fuzzyOptions.join('|')}, ` +
      `inputPresentationPreference=${settings.inputPresentationPreference}, ` +
      `xiaoheYinxingEnabledCategoryCount=${settings.xiaoheYinxingEnabledCategoryIds.length}`;
  }

  private isValidCustomizationId(value: string): boolean {
    return /^[a-z0-9][a-z0-9._-]{0,63}$/.test(value);
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
