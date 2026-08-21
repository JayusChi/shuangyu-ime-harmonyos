import { describe, expect, it } from '@ohos/hypium';
import common from '@ohos.app.ability.common';
import { EngineCoordinator } from '../main/ets/application/EngineCoordinator';
import { SettingsController } from '../main/ets/application/SettingsController';
import {
  CandidateFontSizeMode,
  copyImeSettings,
  CURRENT_SETTINGS_SCHEMA_VERSION,
  DEFAULT_SMART_PERIOD_TIMEOUT_MS,
  DEFAULT_IME_SETTINGS,
  EffectiveTheme,
  HapticLevel,
  imeSettingsEqual,
  ImeSettings,
  KeyboardHeightMode,
  resolveEffectiveTheme,
  settingsToRaw,
  ThemeMode,
  XIAOHE_YINXING_CATEGORY_IDS,
  XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS
} from '../main/ets/domain/settings/ImeSettings';
import { HapticBackend, HapticFeedbackService } from '../main/ets/infrastructure/haptic/HapticFeedbackService';
import { KeySoundBackend, KeySoundService } from '../main/ets/infrastructure/audio/KeySoundService';
import { SettingsMigration } from '../main/ets/infrastructure/storage/SettingsMigration';
import {
  SettingsRepositoryContract,
  SettingsRepositoryRecordCodec
} from '../main/ets/infrastructure/storage/SettingsRepository';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';
import { SettingsStore } from '../main/ets/state/SettingsStore';
import {
  calculateDynamicMetrics,
  getMetricsForOrientation,
  KEYBOARD_BOTTOM_PADDING,
  panelHeightForMode,
  PORTRAIT_METRICS
} from '../main/ets/presentation/keyboard/design/KeyboardMetrics';
import {
  createScreenMetrics,
  ScreenMetricsPx
} from '../main/ets/domain/display/ScreenMetrics';
import { createUnknownEditorContext } from '../main/ets/domain/editor/EditorContext';
import {
  CodeTableCategoryConfig,
  CompositionResult,
  FuzzyOptionId
} from '../main/ets/infrastructure/native/NativeEngineTypes';
import { ImeErrorCode } from '../main/ets/common/error/ImeError';
import { KeyboardThemeResolver } from '../main/ets/presentation/keyboard/design/KeyboardThemeResolver';
import { DARK_PALETTE, LIGHT_PALETTE } from '../main/ets/presentation/keyboard/design/KeyboardPalette';
import { UserModelStatus } from '../main/ets/infrastructure/native/NativeEngineTypes';
import {
  SystemThemeBackend,
  SystemThemeListener,
  SystemThemeMonitor
} from '../main/ets/application/SystemThemeMonitor';
import {
  AvoidAreaRectLike,
  resolveSettingsWindowStyle,
  resolveWindowSafeAreaInsets,
  SettingsSafeAreaListener,
  SettingsWindowBackend,
  SettingsWindowCoordinator,
  SettingsWindowStyle,
  WindowAvoidAreaLike
} from '../main/ets/application/SettingsWindowCoordinator';
import {
  DARK_SETTINGS_THEME,
  LIGHT_SETTINGS_THEME
} from '../main/ets/presentation/settings/SettingsTheme';
import {
  DEBUG_FIXED_LIGHT_WINDOW_STYLE,
  DEBUG_PAGE_BACKGROUND,
  DEBUG_PRIMARY_TEXT
} from '../main/ets/presentation/settings/DebugPageTheme';
import {
  PINYIN_9_PROFILE_ID,
  QUANPIN_26_PROFILE_ID,
  XIAOHE_18_PROFILE_ID,
  XIAOHE_26_PROFILE_ID
} from '../main/ets/domain/keyboard/KeyboardProfile';

class FakeSystemThemeBackend implements SystemThemeBackend {
  darkMode: boolean = false;
  subscribeCount: number = 0;
  unsubscribeCount: number = 0;
  listener?: SystemThemeListener;

  readDarkMode(): boolean {
    return this.darkMode;
  }

  subscribe(listener: SystemThemeListener): void {
    this.subscribeCount += 1;
    this.listener = listener;
  }

  unsubscribe(listener: SystemThemeListener): void {
    this.unsubscribeCount += 1;
    if (this.listener === listener) {
      this.listener = undefined;
    }
  }

  emit(isDark: boolean): void {
    this.darkMode = isDark;
    this.listener?.(isDark);
  }
}

class FakeSettingsWindowBackend implements SettingsWindowBackend {
  immersiveCount: number = 0;
  styles: SettingsWindowStyle[] = [];
  lifecycleEvents: string[] = [];

  async enableImmersiveLayout(): Promise<void> {
    this.immersiveCount += 1;
    this.lifecycleEvents.push('immersive');
  }

  async applyStyle(style: SettingsWindowStyle): Promise<void> {
    this.lifecycleEvents.push('style');
    this.styles.push(style);
  }

  startSafeAreaTracking(listener: SettingsSafeAreaListener): void {
    this.lifecycleEvents.push('safe-area');
    listener({ top: 44, bottom: 16, left: 0, right: 0 });
  }

  stopSafeAreaTracking(): void {
  }
}

class FakeSettingsRepository implements SettingsRepositoryContract {
  settings: ImeSettings = copyImeSettings(DEFAULT_IME_SETTINGS);
  saveSucceeds: boolean = true;
  saveCount: number = 0;
  loadCount: number = 0;
  saveResults: boolean[] = [];
  savedSettings: ImeSettings[] = [];

  async load(context: common.Context): Promise<ImeSettings> {
    this.loadCount += 1;
    return copyImeSettings(this.settings);
  }

  async save(settings: ImeSettings): Promise<boolean> {
    this.saveCount += 1;
    this.savedSettings.push(copyImeSettings(settings));
    const succeeds = this.saveResults.length > 0 ? this.saveResults.shift() ?? false : this.saveSucceeds;
    if (succeeds) {
      this.settings = copyImeSettings(settings);
    }
    return succeeds;
  }

  async reset(): Promise<boolean> {
    this.settings = copyImeSettings(DEFAULT_IME_SETTINGS);
    return this.saveSucceeds;
  }
}

class DeferredSettingsSave {
  private resolver?: () => void;
  readonly promise: Promise<void> = new Promise<void>((resolve: () => void) => {
    this.resolver = resolve;
  });

  resolve(): void {
    this.resolver?.();
  }
}

class DelayedSettingsWindowBackend implements SettingsWindowBackend {
  styles: SettingsWindowStyle[] = [];
  private applyCount: number = 0;
  readonly firstApplyStarted: DeferredSettingsSave = new DeferredSettingsSave();
  readonly releaseFirstApply: DeferredSettingsSave = new DeferredSettingsSave();

  async enableImmersiveLayout(): Promise<void> {
  }

  async applyStyle(style: SettingsWindowStyle): Promise<void> {
    this.styles.push(style);
    this.applyCount += 1;
    if (this.applyCount === 1) {
      this.firstApplyStarted.resolve();
      await this.releaseFirstApply.promise;
    }
  }

  startSafeAreaTracking(listener: SettingsSafeAreaListener): void {
  }

  stopSafeAreaTracking(): void {
  }
}

class FailingSettingsWindowBackend implements SettingsWindowBackend {
  async enableImmersiveLayout(): Promise<void> {
    throw new Error('simulated immersive failure');
  }

  async applyStyle(style: SettingsWindowStyle): Promise<void> {
    throw new Error('simulated style failure');
  }

  startSafeAreaTracking(listener: SettingsSafeAreaListener): void {
    throw new Error('simulated safe-area failure');
  }

  stopSafeAreaTracking(): void {
    throw new Error('simulated safe-area cleanup failure');
  }
}

function emptyAvoidRect(): AvoidAreaRectLike {
  return { left: 0, top: 0, width: 0, height: 0 };
}

function visibleAvoidArea(
  topRect: AvoidAreaRectLike,
  bottomRect: AvoidAreaRectLike,
  leftRect: AvoidAreaRectLike = emptyAvoidRect(),
  rightRect: AvoidAreaRectLike = emptyAvoidRect()
): WindowAvoidAreaLike {
  return { visible: true, leftRect, topRect, rightRect, bottomRect };
}

class DelayedSettingsRepository implements SettingsRepositoryContract {
  settings: ImeSettings = copyImeSettings(DEFAULT_IME_SETTINGS);
  saveCount: number = 0;
  concurrentWrites: number = 0;
  maxConcurrentWrites: number = 0;
  savedSettings: ImeSettings[] = [];
  readonly firstSaveStarted: DeferredSettingsSave = new DeferredSettingsSave();
  readonly releaseFirstSave: DeferredSettingsSave = new DeferredSettingsSave();

  async load(context: common.Context): Promise<ImeSettings> {
    return copyImeSettings(this.settings);
  }

  async save(settings: ImeSettings): Promise<boolean> {
    const saveIndex = this.saveCount;
    this.saveCount += 1;
    this.concurrentWrites += 1;
    this.maxConcurrentWrites = Math.max(this.maxConcurrentWrites, this.concurrentWrites);
    this.savedSettings.push(copyImeSettings(settings));
    try {
      if (saveIndex === 0) {
        this.firstSaveStarted.resolve();
        await this.releaseFirstSave.promise;
      }
      this.settings = copyImeSettings(settings);
      return true;
    } finally {
      this.concurrentWrites -= 1;
    }
  }

  async reset(): Promise<boolean> {
    return this.save(copyImeSettings(DEFAULT_IME_SETTINGS));
  }
}

class RejectingFirstSettingsRepository extends FakeSettingsRepository {
  async save(settings: ImeSettings): Promise<boolean> {
    if (this.saveCount === 0) {
      this.saveCount += 1;
      this.savedSettings.push(copyImeSettings(settings));
      throw new Error('simulated settings persistence rejection');
    }
    return super.save(settings);
  }
}

class FakeHapticBackend implements HapticBackend {
  durations: number[] = [];
  reject: boolean = false;
  async vibrate(durationMs: number): Promise<void> {
    this.durations.push(durationMs);
    if (this.reject) {
      throw new Error('fake haptic failure');
    }
  }
}

class FakeSoundBackend implements KeySoundBackend {
  playCount: number = 0;
  disposeCount: number = 0;
  reject: boolean = false;
  async play(): Promise<void> {
    this.playCount += 1;
    if (this.reject) {
      throw new Error('fake sound failure');
    }
  }
  async dispose(): Promise<void> {
    this.disposeCount += 1;
  }
}

function userModelStatus(enabled: boolean): UserModelStatus {
  return {
    loaded: true, enabled, sessionLearningAllowed: true, dirty: false, recordCount: 3,
    formatVersion: 1, dataVersion: 1, lastErrorCode: ''
  };
}

class FakeSettingsEngine extends EngineCoordinator {
  globalValues: boolean[] = [];
  sessionValues: boolean[] = [];
  isReady: boolean = true;
  categoryMode: boolean = false;
  rejectCategoryUpdate: boolean = false;
  categoryIds: string[] = XIAOHE_YINXING_CATEGORY_IDS.slice();
  categoryCalls: string[][] = [];
  simulatedSchemeId: string = 'xiaohe';
  schemeChanges: string[] = [];
  resetCount: number = 0;
  rejectSchemeId: string = '';
  rejectQuanpinConfig: boolean = false;
  quanpinConfigCalls: string[] = [];
  isInitialized(): boolean { return this.isReady; }
  getActiveSchemeId(): string { return this.categoryMode ? 'xiaohe-yinxing' : this.simulatedSchemeId; }
  reset(): CompositionResult {
    this.resetCount += 1;
    const result = candidateComposition();
    result.rawInput = '';
    result.preeditText = '';
    result.parsedSyllables = [];
    result.candidates = [];
    result.highlightedIndex = -1;
    result.parserState = 'empty';
    return result;
  }
  changeScheme(schemeId: string, _bundlePath?: string): CompositionResult {
    this.schemeChanges.push(schemeId);
    if (schemeId === this.rejectSchemeId) {
      const rejected = this.reset();
      rejected.success = false;
      rejected.errorCode = ImeErrorCode.INVALID_SCHEME;
      rejected.errorMessage = 'scheme rejected';
      return rejected;
    }
    this.simulatedSchemeId = schemeId;
    return this.reset();
  }
  setUserLearningEnabled(enabled: boolean): UserModelStatus {
    this.globalValues.push(enabled);
    return userModelStatus(enabled);
  }
  setSessionLearningAllowed(allowed: boolean): UserModelStatus {
    this.sessionValues.push(allowed);
    return userModelStatus(true);
  }
  reconfigureQuanpin(enabled: boolean, fuzzyOptions: FuzzyOptionId[]): CompositionResult {
    this.quanpinConfigCalls.push(`${enabled}:${fuzzyOptions.join('|')}`);
    const result = this.reset();
    if (this.rejectQuanpinConfig) {
      result.success = false;
      result.errorCode = ImeErrorCode.INVALID_CONFIG;
      result.errorMessage = 'quanpin config rejected';
    }
    return result;
  }
  getCodeTableCategoryConfig(): CodeTableCategoryConfig {
    return {
      schemaVersion: 1,
      categories: [],
      enabledCategoryIds: this.categoryIds.slice()
    };
  }
  setCodeTableCategories(enabledCategoryIds: string[]): CompositionResult {
    this.categoryCalls.push(enabledCategoryIds.slice());
    if (this.rejectCategoryUpdate) {
      const rejected = candidateComposition();
      rejected.success = false;
      rejected.errorCode = ImeErrorCode.INVALID_ARGUMENT;
      rejected.errorMessage = 'category update rejected';
      return rejected;
    }
    this.categoryIds = XIAOHE_YINXING_CATEGORY_IDS.filter((id: string) =>
      id === 'core' || enabledCategoryIds.indexOf(id) >= 0);
    return candidateComposition();
  }
}

function candidateComposition(): CompositionResult {
  return {
    success: true,
    errorCode: ImeErrorCode.SUCCESS,
    errorMessage: '',
    rawInput: 'ni',
    preeditText: 'ni',
    parsedSyllables: ['ni'],
    pendingCode: '',
    parserState: 'complete',
    candidates: [{ id: 'ni', text: '你', reading: 'ni', source: 'screen-metrics-test' }],
    highlightedIndex: 0,
    hasNextPage: false,
    hasPreviousPage: false,
    candidatePage: 0,
    commitText: '',
    action: null,
    compositionFinished: false
  };
}

export default function stage11Test() {
  describe('Stage 11 settings, theme and feedback', () => {
    it('locks default settings and Stage 10 visual defaults', 0, () => {
      expect(DEFAULT_IME_SETTINGS.schemaVersion).assertEqual(CURRENT_SETTINGS_SCHEMA_VERSION);
      expect(DEFAULT_IME_SETTINGS.schemeId).assertEqual('xiaohe');
      expect(DEFAULT_IME_SETTINGS.themeMode).assertEqual(ThemeMode.FOLLOW_SYSTEM);
      expect(DEFAULT_IME_SETTINGS.keyboardHeightMode).assertEqual(KeyboardHeightMode.STANDARD);
      expect(DEFAULT_IME_SETTINGS.candidateFontSizeMode).assertEqual(CandidateFontSizeMode.STANDARD);
      expect(DEFAULT_IME_SETTINGS.hapticLevel).assertEqual(HapticLevel.LIGHT);
      expect(DEFAULT_IME_SETTINGS.keySoundEnabled).assertFalse();
      expect(DEFAULT_IME_SETTINGS.userLearningEnabled).assertTrue();
      expect(DEFAULT_IME_SETTINGS.spellingCorrectionEnabled).assertFalse();
      expect(DEFAULT_IME_SETTINGS.fuzzyOptions.length).assertEqual(0);
      expect(DEFAULT_IME_SETTINGS.smartPeriodTimeoutMs).assertEqual(DEFAULT_SMART_PERIOD_TIMEOUT_MS);
      expect(panelHeightForMode(KeyboardHeightMode.STANDARD)).assertEqual(894);
      expect(PORTRAIT_METRICS.statusBarActionWidth).assertEqual(48);
    });

    it('uses exact injected tablet dimensions for portrait, landscape and height modes', 0, () => {
      const landscape = createScreenMetrics({ widthPx: 2880, heightPx: 1920, densityPixels: 2 }, true);
      const portrait = createScreenMetrics({ widthPx: 1920, heightPx: 2880, densityPixels: 2 }, false);
      expect(panelHeightForMode(KeyboardHeightMode.COMPACT, landscape)).assertEqual(932);
      expect(panelHeightForMode(KeyboardHeightMode.STANDARD, landscape)).assertEqual(1052);
      expect(panelHeightForMode(KeyboardHeightMode.TALL, landscape)).assertEqual(1182);
      expect(panelHeightForMode(KeyboardHeightMode.COMPACT, portrait)).assertEqual(968);
      expect(panelHeightForMode(KeyboardHeightMode.STANDARD, portrait)).assertEqual(1098);
      expect(panelHeightForMode(KeyboardHeightMode.TALL, portrait)).assertEqual(1226);
    });

    it('falls back for zero negative NaN and infinite screen dimensions', 0, () => {
      const invalid: ScreenMetricsPx[] = [
        { widthPx: 0, heightPx: 0, densityPixels: 3, isLandscape: false },
        { widthPx: -1080, heightPx: 2340, densityPixels: 3, isLandscape: false },
        { widthPx: Number.NaN, heightPx: 2340, densityPixels: 3, isLandscape: false },
        { widthPx: Number.POSITIVE_INFINITY, heightPx: 2340, densityPixels: 3, isLandscape: false }
      ];
      invalid.forEach((screen: ScreenMetricsPx): void => {
        const metrics = calculateDynamicMetrics(screen, KeyboardHeightMode.STANDARD);
        expect(Number.isFinite(metrics.letterKeyHeight)).assertTrue();
        expect(metrics.letterKeyHeight > 0).assertTrue();
        expect(Number.isFinite(metrics.candidateBarHeight)).assertTrue();
        const height = panelHeightForMode(KeyboardHeightMode.STANDARD, screen);
        expect(height).assertEqual(894);
      });
    });

    it('configuration direction normalizes stale dimensions and preserves composition state', 0, () => {
      const stalePortrait = createScreenMetrics({ widthPx: 1920, heightPx: 2880, densityPixels: 2 }, true);
      expect(stalePortrait.widthPx).assertEqual(2880);
      expect(stalePortrait.heightPx).assertEqual(1920);
      expect(stalePortrait.isLandscape).assertTrue();

      const store = new InputSessionStore();
      store.applyEditorContext(createUnknownEditorContext());
      store.updateComposition(candidateComposition());
      const before = store.getSnapshot();
      store.setScreenMetrics(stalePortrait);
      const after = store.getSnapshot();
      expect(after.rawInput).assertEqual(before.rawInput);
      expect(after.preeditText).assertEqual(before.preeditText);
      expect(after.candidates[0].text).assertEqual(before.candidates[0].text);
      expect(after.keyboardMode).assertEqual(before.keyboardMode);
    });

    it('copies and compares settings by value', 0, () => {
      const copy = copyImeSettings(DEFAULT_IME_SETTINGS);
      expect(imeSettingsEqual(copy, DEFAULT_IME_SETTINGS)).assertTrue();
      copy.themeMode = ThemeMode.DARK;
      expect(imeSettingsEqual(copy, DEFAULT_IME_SETTINGS)).assertFalse();
    });

    it('validates empty and corrupt fields independently', 0, () => {
      const validator = new SettingsValidator();
      const empty = validator.validate({});
      expect(imeSettingsEqual(empty, DEFAULT_IME_SETTINGS)).assertTrue();
      const partial = validator.validate({ themeMode: 'dark', keyboardHeightMode: 'broken', keySoundEnabled: 'true' });
      expect(partial.themeMode).assertEqual(ThemeMode.DARK);
      expect(partial.keyboardHeightMode).assertEqual(KeyboardHeightMode.STANDARD);
      expect(partial.keySoundEnabled).assertTrue();
      expect(partial.userLearningEnabled).assertTrue();
      expect(new SettingsValidator().validate({ smartPeriodTimeoutMs: '-1' }).smartPeriodTimeoutMs)
        .assertEqual(DEFAULT_SMART_PERIOD_TIMEOUT_MS);
      expect(new SettingsValidator().validate({ smartPeriodTimeoutMs: '800' }).smartPeriodTimeoutMs)
        .assertEqual(800);
    });

    it('falls back unknown enums, booleans, scheme and future version safely', 0, () => {
      const result = new SettingsValidator().validate(new SettingsMigration().migrate({
        schemaVersion: '999', schemeId: 'not-installed', themeMode: 'neon',
        candidateFontSizeMode: 'huge', hapticLevel: 'extreme', userLearningEnabled: 'maybe'
      }));
      expect(result.schemaVersion).assertEqual(CURRENT_SETTINGS_SCHEMA_VERSION);
      expect(result.schemeId).assertEqual('xiaohe');
      expect(result.themeMode).assertEqual(ThemeMode.FOLLOW_SYSTEM);
      expect(result.candidateFontSizeMode).assertEqual(CandidateFontSizeMode.STANDARD);
      expect(result.hapticLevel).assertEqual(HapticLevel.LIGHT);
      expect(result.userLearningEnabled).assertTrue();
    });

    it('migrates unversioned known legacy fields and is idempotent', 0, () => {
      const migration = new SettingsMigration();
      const first = migration.migrate({ darkMode: 'true', keyboardScale: '2', vibrationEnabled: 'false' });
      const second = migration.migrate(first);
      expect(first.schemaVersion).assertEqual(`${CURRENT_SETTINGS_SCHEMA_VERSION}`);
      expect(first.themeMode).assertEqual(ThemeMode.DARK);
      expect(first.keyboardHeightMode).assertEqual(KeyboardHeightMode.TALL);
      expect(first.hapticLevel).assertEqual(HapticLevel.OFF);
      expect(second.themeMode).assertEqual(first.themeMode);
      expect(second.keyboardHeightMode).assertEqual(first.keyboardHeightMode);
    });

    it('migrates and canonicalizes independent quanpin feature settings', 0, () => {
      const migration = new SettingsMigration();
      const validator = new SettingsValidator();
      const legacy = validator.validate(migration.migrate({ schemaVersion: '6' }));
      expect(legacy.spellingCorrectionEnabled).assertFalse();
      expect(legacy.fuzzyOptions.length).assertEqual(0);

      const configured = validator.validate(migration.migrate({
        schemaVersion: '7',
        spellingCorrectionEnabled: 'true',
        fuzzyOptions: '["ian_iang","unknown","n_l","n_l","z_zh"]'
      }));
      expect(configured.spellingCorrectionEnabled).assertTrue();
      expect(configured.fuzzyOptions.join('|')).assertEqual('n_l|z_zh|ian_iang');
      const restored = validator.validate(migration.migrate(settingsToRaw(configured)));
      expect(imeSettingsEqual(restored, configured)).assertTrue();
    });

    it('rolls back quanpin runtime configuration when persistence fails', 0, async () => {
      const repository = new FakeSettingsRepository();
      repository.saveSucceeds = false;
      const store = new SettingsStore();
      const initial = copyImeSettings(DEFAULT_IME_SETTINGS);
      initial.keyboardProfileId = QUANPIN_26_PROFILE_ID;
      initial.schemeId = 'quanpin';
      store.replace(initial);
      const engine = new FakeSettingsEngine();
      engine.simulatedSchemeId = 'quanpin';
      const controller = new SettingsController(repository, store, engine, new InputSessionStore());

      const failedSave = await controller.setSpellingCorrectionEnabled(true);
      expect(failedSave.success).assertFalse();
      expect(engine.quanpinConfigCalls.join(',')).assertEqual('true:,false:');
      expect(store.getSnapshot().spellingCorrectionEnabled).assertFalse();

      engine.rejectQuanpinConfig = true;
      const rejectedRuntime = await controller.setFuzzyOption('n_l', true);
      expect(rejectedRuntime.success).assertFalse();
      expect(repository.saveCount).assertEqual(1);
      expect(store.getSnapshot().fuzzyOptions.length).assertEqual(0);
    });

    it('migrates yinxing categories canonically and restores required core', 0, () => {
      const migration = new SettingsMigration();
      const validator = new SettingsValidator();
      const migrated = migration.migrate({
        schemaVersion: '1',
        xiaoheYinxingEnabledCategoryIds:
          '["rare-character","unknown","core","rare-character","category-secondary"]'
      });
      const settings = validator.validate(migrated);
      expect(settings.xiaoheYinxingEnabledCategoryIds.join('|'))
        .assertEqual('core|category-secondary|quick-symbol|symbol|symbol-group|rare-character');

      const empty = validator.validate(migration.migrate({
        schemaVersion: '1',
        xiaoheYinxingEnabledCategoryIds: '[]'
      }));
      expect(empty.xiaoheYinxingEnabledCategoryIds.join('|'))
        .assertEqual('core|quick-symbol|symbol|symbol-group');

      const first = JSON.stringify(settingsToRaw(settings));
      const second = JSON.stringify(settingsToRaw(
        validator.validate(migration.migrate(settingsToRaw(settings)))
      ));
      expect(second).assertEqual(first);
    });

    it('disables passthrough-dependent yinxing categories only for the legacy all-enabled default', 0, () => {
      const migration = new SettingsMigration();
      const validator = new SettingsValidator();
      const expected = 'core|category-secondary|quick-symbol|one-key-secondary|' +
        'out-of-table-character|symbol|symbol-group';

      expect(DEFAULT_IME_SETTINGS.xiaoheYinxingEnabledCategoryIds.join('|')).assertEqual(expected);
      expect(XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS.join('|')).assertEqual(expected);

      const legacyDefault = validator.validate(migration.migrate({
        schemaVersion: '7',
        xiaoheYinxingCategorySchemaVersion: '3',
        xiaoheYinxingEnabledCategoryIds: JSON.stringify(XIAOHE_YINXING_CATEGORY_IDS)
      }));
      expect(legacyDefault.xiaoheYinxingEnabledCategoryIds.join('|')).assertEqual(expected);

      const customized = validator.validate(migration.migrate({
        schemaVersion: '7',
        xiaoheYinxingCategorySchemaVersion: '3',
        xiaoheYinxingEnabledCategoryIds: '["core","two-key-secondary","rare-character"]'
      }));
      expect(customized.xiaoheYinxingEnabledCategoryIds.join('|'))
        .assertEqual('core|two-key-secondary|rare-character');
    });

    it('preserves and validates fixed lexicon sources across schema migration', 0, () => {
      const migration = new SettingsMigration();
      const validator = new SettingsValidator();
      const rawSources = JSON.stringify([
        {
          id: 'customer-main',
          displayName: '客户固定词库',
          filePath: 'file://docs/customer-main.txt',
          enabled: true,
          priority: 10,
          mode: 'MERGE'
        },
        {
          id: 'customer-main',
          displayName: '重复 ID',
          filePath: 'file://docs/duplicate.txt',
          enabled: true,
          priority: 20,
          mode: 'APPEND'
        },
        {
          id: 'invalid-mode',
          displayName: '无效模式',
          filePath: 'file://docs/invalid.txt',
          enabled: true,
          priority: 30,
          mode: 'UNKNOWN'
        }
      ]);
      const settings = validator.validate(migration.migrate({
        schemaVersion: '5',
        lexiconSources: rawSources
      }));

      expect(settings.schemaVersion).assertEqual(CURRENT_SETTINGS_SCHEMA_VERSION);
      expect(settings.lexiconSources.length).assertEqual(1);
      expect(settings.lexiconSources[0].id).assertEqual('customer-main');
      expect(settings.lexiconSources[0].mode).assertEqual('MERGE');

      const restored = validator.validate(migration.migrate(settingsToRaw(settings)));
      expect(imeSettingsEqual(restored, settings)).assertTrue();
    });

    it('applies native category snapshot before saving and rolls back on failure', 0, async () => {
      const repository = new FakeSettingsRepository();
      const store = new SettingsStore();
      const engine = new FakeSettingsEngine();
      engine.categoryMode = true;
      const session = new InputSessionStore();
      const controller = new SettingsController(repository, store, engine, session);

      const success = await controller.setXiaoheYinxingEnabledCategoryIds([
        'rare-character',
        'core',
        'rare-character'
      ]);
      expect(success.success).assertTrue();
      expect(repository.saveCount).assertEqual(1);
      expect(repository.settings.xiaoheYinxingEnabledCategoryIds.join('|'))
        .assertEqual('core|rare-character');
      expect(engine.categoryCalls.length).assertEqual(1);

      engine.rejectCategoryUpdate = true;
      const rejected = await controller.setXiaoheYinxingEnabledCategoryIds(['core']);
      expect(rejected.success).assertFalse();
      expect(repository.saveCount).assertEqual(1);

      engine.rejectCategoryUpdate = false;
      repository.saveSucceeds = false;
      const failedSave = await controller.setXiaoheYinxingEnabledCategoryIds([
        'core',
        'full-code-word'
      ]);
      expect(failedSave.success).assertFalse();
      expect(engine.categoryCalls.length).assertEqual(4);
      expect(engine.categoryIds.join('|')).assertEqual('core|rare-character');
    });

    it('persists canonical category direct controls while the engine process is offline', 0, async () => {
      const repository = new FakeSettingsRepository();
      const store = new SettingsStore();
      const engine = new FakeSettingsEngine();
      engine.isReady = false;
      const controller = new SettingsController(repository, store, engine, new InputSessionStore());

      const saved = await controller.setXiaoheYinxingEnabledCategoryIds([
        'rare-character',
        'core',
        'rare-character'
      ]);
      expect(saved.success).assertTrue();
      expect(repository.settings.xiaoheYinxingEnabledCategoryIds.join('|'))
        .assertEqual('core|rare-character');
      expect(engine.categoryCalls.length).assertEqual(0);

      const rejected = await controller.setXiaoheYinxingEnabledCategoryIds(['unknown']);
      expect(rejected.success).assertFalse();
      expect(repository.saveCount).assertEqual(1);
    });

    it('serializes and validates a settings round trip', 0, () => {
      const settings = copyImeSettings(DEFAULT_IME_SETTINGS);
      settings.themeMode = ThemeMode.DARK;
      settings.hapticLevel = HapticLevel.STRONG;
      settings.keySoundEnabled = true;
      settings.smartPeriodTimeoutMs = 1000;
      const roundTrip = new SettingsValidator().validate(settingsToRaw(settings));
      expect(imeSettingsEqual(settings, roundTrip)).assertTrue();
    });

    it('SettingsRepository record restores every persisted field', 0, () => {
      const persisted = copyImeSettings(DEFAULT_IME_SETTINGS);
      persisted.schemeId = 'xiaohe';
      persisted.themeMode = ThemeMode.DARK;
      persisted.keyboardHeightMode = KeyboardHeightMode.TALL;
      persisted.candidateFontSizeMode = CandidateFontSizeMode.LARGE;
      persisted.hapticLevel = HapticLevel.STRONG;
      persisted.keySoundEnabled = true;
      persisted.userLearningEnabled = false;
      const codec = new SettingsRepositoryRecordCodec();
      const restored = new SettingsValidator().validate(codec.decode(codec.encode(persisted)));
      expect(imeSettingsEqual(restored, persisted)).assertTrue();
    });

    it('SettingsStore notifies changes once and skips equal values', 0, () => {
      const store = new SettingsStore();
      let notifications = 0;
      const listener = (): void => { notifications += 1; };
      store.subscribe(listener);
      store.replace(copyImeSettings(DEFAULT_IME_SETTINGS));
      store.replace(copyImeSettings(DEFAULT_IME_SETTINGS));
      expect(notifications).assertEqual(1);
      const dark = store.getSnapshot();
      dark.themeMode = ThemeMode.DARK;
      store.replace(dark);
      expect(notifications).assertEqual(2);
      store.unsubscribe(listener);
    });

    it('SettingsStore follows system only in follow-system mode', 0, () => {
      const store = new SettingsStore();
      store.replace(copyImeSettings(DEFAULT_IME_SETTINGS));
      store.setSystemDarkMode(true);
      expect(store.isDarkMode()).assertTrue();
      const light = store.getSnapshot();
      light.themeMode = ThemeMode.LIGHT;
      store.replace(light);
      store.setSystemDarkMode(true);
      expect(store.isDarkMode()).assertFalse();
    });

    it('resolves follow-system with a light system theme', 0, () => {
      expect(resolveEffectiveTheme(ThemeMode.FOLLOW_SYSTEM, false)).assertEqual(EffectiveTheme.LIGHT);
    });

    it('resolves follow-system with a dark system theme', 0, () => {
      expect(resolveEffectiveTheme(ThemeMode.FOLLOW_SYSTEM, true)).assertEqual(EffectiveTheme.DARK);
    });

    it('keeps forced light when the system is dark', 0, () => {
      expect(resolveEffectiveTheme(ThemeMode.LIGHT, true)).assertEqual(EffectiveTheme.LIGHT);
    });

    it('keeps forced dark when the system is light', 0, () => {
      expect(resolveEffectiveTheme(ThemeMode.DARK, false)).assertEqual(EffectiveTheme.DARK);
    });

    it('uses follow-system behavior for invalid and missing theme values', 0, () => {
      expect(resolveEffectiveTheme('invalid', true)).assertEqual(EffectiveTheme.DARK);
      expect(resolveEffectiveTheme(undefined, false)).assertEqual(EffectiveTheme.LIGHT);
    });

    it('updates effective theme for both system and user setting changes', 0, () => {
      const store = new SettingsStore();
      store.replace(copyImeSettings(DEFAULT_IME_SETTINGS));
      expect(store.getEffectiveTheme()).assertEqual(EffectiveTheme.LIGHT);
      store.setSystemDarkMode(true);
      expect(store.getEffectiveTheme()).assertEqual(EffectiveTheme.DARK);
      const fixedLight = store.getSnapshot();
      fixedLight.themeMode = ThemeMode.LIGHT;
      store.replace(fixedLight);
      expect(store.getEffectiveTheme()).assertEqual(EffectiveTheme.LIGHT);
      store.setSystemDarkMode(false);
      expect(store.getEffectiveTheme()).assertEqual(EffectiveTheme.LIGHT);
    });

    it('deduplicates subscriptions and stops updates after unsubscribe', 0, () => {
      const store = new SettingsStore();
      let notifications = 0;
      const listener = (): void => { notifications += 1; };
      store.subscribe(listener);
      store.subscribe(listener);
      store.setSystemDarkMode(true);
      expect(notifications).assertEqual(1);
      store.unsubscribe(listener);
      store.unsubscribe(listener);
      store.setSystemDarkMode(false);
      expect(notifications).assertEqual(1);
    });

    it('system theme monitor subscribes, refreshes, and unsubscribes once', 0, () => {
      const backend = new FakeSystemThemeBackend();
      const values: boolean[] = [];
      const monitor = new SystemThemeMonitor(backend, (isDark: boolean): void => { values.push(isDark); });
      monitor.start();
      monitor.start();
      expect(backend.subscribeCount).assertEqual(1);
      expect(values.length).assertEqual(2);
      expect(values[0]).assertFalse();
      backend.emit(true);
      expect(values[2]).assertTrue();
      monitor.stop();
      monitor.stop();
      expect(backend.unsubscribeCount).assertEqual(1);
      backend.emit(false);
      expect(values.length).assertEqual(3);
    });

    it('system theme monitor refreshes the latest mode on keyboard lifecycle events', 0, () => {
      const backend = new FakeSystemThemeBackend();
      const values: boolean[] = [];
      const monitor = new SystemThemeMonitor(backend, (isDark: boolean): void => { values.push(isDark); });
      monitor.start();
      backend.darkMode = true;
      monitor.refresh();
      expect(values[values.length - 1]).assertTrue();
      backend.darkMode = false;
      monitor.refresh();
      expect(values[values.length - 1]).assertFalse();
    });

    it('theme resolver maps forced and followed modes to tokens', 0, () => {
      const store = new SettingsStore();
      const resolver = new KeyboardThemeResolver();
      store.replace(copyImeSettings(DEFAULT_IME_SETTINGS));
      store.setSystemDarkMode(false);
      expect(resolver.resolve(store.getEffectiveTheme()).panelBackground).assertEqual(LIGHT_PALETTE.panelBackground);
      store.setSystemDarkMode(true);
      expect(resolver.resolve(store.getEffectiveTheme()).panelBackground).assertEqual(DARK_PALETTE.panelBackground);
    });

    it('settings window style reuses page tokens and readable icon contrast', 0, () => {
      const light = resolveSettingsWindowStyle(false);
      const dark = resolveSettingsWindowStyle(true);
      expect(light.backgroundColor).assertEqual(LIGHT_SETTINGS_THEME.pageBackground);
      expect(light.contentColor).assertEqual(LIGHT_SETTINGS_THEME.primaryText);
      expect(light.lightIcons).assertFalse();
      expect(dark.backgroundColor).assertEqual(DARK_SETTINGS_THEME.pageBackground);
      expect(dark.contentColor).assertEqual(DARK_SETTINGS_THEME.primaryText);
      expect(dark.lightIcons).assertTrue();
    });

    it('Debug acceptance window style is fixed light with dark system-bar content', 0, () => {
      expect(DEBUG_FIXED_LIGHT_WINDOW_STYLE.backgroundColor).assertEqual(DEBUG_PAGE_BACKGROUND);
      expect(DEBUG_FIXED_LIGHT_WINDOW_STYLE.contentColor).assertEqual(DEBUG_PRIMARY_TEXT);
      expect(DEBUG_FIXED_LIGHT_WINDOW_STYLE.lightIcons).assertFalse();
    });

    it('window avoid areas resolve top cutout, bottom gesture, and landscape side insets', 0, () => {
      const system = visibleAvoidArea(
        { left: 0, top: 0, width: 1080, height: 96 },
        { left: 0, top: 2320, width: 1080, height: 80 }
      );
      const cutout = visibleAvoidArea(
        { left: 420, top: 0, width: 240, height: 132 },
        emptyAvoidRect(),
        { left: 0, top: 500, width: 72, height: 300 }
      );
      const gesture = visibleAvoidArea(
        emptyAvoidRect(),
        { left: 360, top: 2340, width: 360, height: 60 }
      );
      const insets = resolveWindowSafeAreaInsets(1080, 2400, [system, cutout, gesture]);
      expect(insets.top).assertEqual(132);
      expect(insets.bottom).assertEqual(80);
      expect(insets.left).assertEqual(72);
      expect(insets.right).assertEqual(0);
    });

    it('settings window follows system and applies a saved forced theme', 0, async () => {
      const repository = new FakeSettingsRepository();
      const store = new SettingsStore();
      const controller = new SettingsController(repository, store, new FakeSettingsEngine(), new InputSessionStore());
      const backend = new FakeSettingsWindowBackend();
      const coordinator = new SettingsWindowCoordinator(controller, backend);
      store.replace(copyImeSettings(DEFAULT_IME_SETTINGS));
      await coordinator.start();
      expect(backend.styles[backend.styles.length - 1].backgroundColor)
        .assertEqual(LIGHT_SETTINGS_THEME.pageBackground);
      controller.setSystemDarkMode(true);
      await coordinator.sync();
      expect(backend.styles[backend.styles.length - 1].backgroundColor)
        .assertEqual(DARK_SETTINGS_THEME.pageBackground);
      const result = await controller.setThemeMode(ThemeMode.LIGHT);
      expect(result.success).assertTrue();
      await coordinator.sync();
      expect(backend.styles[backend.styles.length - 1].backgroundColor)
        .assertEqual(LIGHT_SETTINGS_THEME.pageBackground);
      expect(backend.immersiveCount).assertEqual(1);
      coordinator.stop();
    });

    it('settings window reads its first safe area after immersive layout is enabled', 0, async () => {
      const controller = new SettingsController(
        new FakeSettingsRepository(), new SettingsStore(), new FakeSettingsEngine(), new InputSessionStore()
      );
      const backend = new FakeSettingsWindowBackend();
      const coordinator = new SettingsWindowCoordinator(controller, backend);
      let observedTop = 0;
      coordinator.subscribeSafeArea((insets): void => {
        observedTop = insets.top;
      });
      await coordinator.start();
      expect(backend.lifecycleEvents[0]).assertEqual('immersive');
      expect(backend.lifecycleEvents[1]).assertEqual('safe-area');
      expect(observedTop).assertEqual(44);
      coordinator.stop();
    });

    it('Debug page override wins system and forced themes until the matching page exits', 0, async () => {
      const store = new SettingsStore();
      const controller = new SettingsController(
        new FakeSettingsRepository(), store, new FakeSettingsEngine(), new InputSessionStore()
      );
      const backend = new FakeSettingsWindowBackend();
      const coordinator = new SettingsWindowCoordinator(controller, backend);
      store.replace(copyImeSettings(DEFAULT_IME_SETTINGS));
      controller.setSystemDarkMode(true);
      await coordinator.start();
      const token = coordinator.setPageStyleOverride(DEBUG_FIXED_LIGHT_WINDOW_STYLE);
      await coordinator.sync();
      expect(backend.styles[backend.styles.length - 1].backgroundColor).assertEqual(DEBUG_PAGE_BACKGROUND);
      controller.setSystemDarkMode(false);
      const result = await controller.setThemeMode(ThemeMode.DARK);
      expect(result.success).assertTrue();
      await coordinator.sync();
      expect(backend.styles[backend.styles.length - 1].backgroundColor).assertEqual(DEBUG_PAGE_BACKGROUND);
      coordinator.clearPageStyleOverride(token);
      await coordinator.sync();
      expect(backend.styles[backend.styles.length - 1].backgroundColor)
        .assertEqual(DARK_SETTINGS_THEME.pageBackground);
      coordinator.stop();
    });

    it('stale Debug page exit cannot clear a newer page override', 0, async () => {
      const controller = new SettingsController(
        new FakeSettingsRepository(), new SettingsStore(), new FakeSettingsEngine(), new InputSessionStore()
      );
      const backend = new FakeSettingsWindowBackend();
      const coordinator = new SettingsWindowCoordinator(controller, backend);
      await coordinator.start();
      const staleToken = coordinator.setPageStyleOverride(resolveSettingsWindowStyle(true));
      const currentToken = coordinator.setPageStyleOverride(DEBUG_FIXED_LIGHT_WINDOW_STYLE);
      coordinator.clearPageStyleOverride(staleToken);
      await coordinator.sync();
      expect(backend.styles[backend.styles.length - 1].backgroundColor).assertEqual(DEBUG_PAGE_BACKGROUND);
      coordinator.clearPageStyleOverride(currentToken);
      coordinator.stop();
    });

    it('window capability failures are logged and do not reject coordinator lifecycle', 0, async () => {
      const controller = new SettingsController(
        new FakeSettingsRepository(), new SettingsStore(), new FakeSettingsEngine(), new InputSessionStore()
      );
      const coordinator = new SettingsWindowCoordinator(controller, new FailingSettingsWindowBackend());
      await coordinator.start();
      await coordinator.sync();
      coordinator.stop();
      expect(true).assertTrue();
    });

    it('settings window serializes rapid theme changes so the newest style wins', 0, async () => {
      const store = new SettingsStore();
      const controller = new SettingsController(
        new FakeSettingsRepository(), store, new FakeSettingsEngine(), new InputSessionStore()
      );
      const backend = new DelayedSettingsWindowBackend();
      const coordinator = new SettingsWindowCoordinator(controller, backend);
      store.replace(copyImeSettings(DEFAULT_IME_SETTINGS));
      const initialSync = coordinator.start();
      await backend.firstApplyStarted.promise;
      const debugToken = coordinator.setPageStyleOverride(DEBUG_FIXED_LIGHT_WINDOW_STYLE);
      controller.setSystemDarkMode(true);
      coordinator.clearPageStyleOverride(debugToken);
      backend.releaseFirstApply.resolve();
      await initialSync;
      await coordinator.sync();
      expect(backend.styles[backend.styles.length - 1].backgroundColor)
        .assertEqual(DARK_SETTINGS_THEME.pageBackground);
      coordinator.stop();
    });

    it('keyboard height modes derive from standard and preserve bottom padding', 0, () => {
      const compact = getMetricsForOrientation(false, KeyboardHeightMode.COMPACT);
      const standard = getMetricsForOrientation(false, KeyboardHeightMode.STANDARD);
      const tall = getMetricsForOrientation(false, KeyboardHeightMode.TALL);
      expect(standard.letterKeyHeight).assertEqual(PORTRAIT_METRICS.letterKeyHeight);
      expect(compact.letterKeyHeight < standard.letterKeyHeight).assertTrue();
      expect(tall.letterKeyHeight > standard.letterKeyHeight).assertTrue();
      expect(compact.bottomPadding).assertEqual(KEYBOARD_BOTTOM_PADDING);
      expect(tall.bottomPadding).assertEqual(KEYBOARD_BOTTOM_PADDING);
    });

    it('controller keeps store unchanged when persistence fails', 0, async () => {
      const repo = new FakeSettingsRepository();
      repo.saveSucceeds = false;
      const store = new SettingsStore();
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());
      const result = await controller.setThemeMode(ThemeMode.DARK);
      expect(result.success).assertFalse();
      expect(store.getSnapshot().themeMode).assertEqual(ThemeMode.FOLLOW_SYSTEM);
    });

    it('controller persists and notifies a single setting', 0, async () => {
      const repo = new FakeSettingsRepository();
      const store = new SettingsStore();
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());
      const result = await controller.setKeyboardHeightMode(KeyboardHeightMode.TALL);
      expect(result.success).assertTrue();
      expect(repo.saveCount).assertEqual(1);
      expect(store.getSnapshot().keyboardHeightMode).assertEqual(KeyboardHeightMode.TALL);
    });

    it('controller persists the smart period timeout and rejects out-of-range values', 0, async () => {
      const repo = new FakeSettingsRepository();
      const store = new SettingsStore();
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());
      expect((await controller.setSmartPeriodTimeoutMs(800)).success).assertTrue();
      expect(store.getSnapshot().smartPeriodTimeoutMs).assertEqual(800);
      expect((await controller.setSmartPeriodTimeoutMs(2001)).success).assertFalse();
      expect(repo.saveCount).assertEqual(1);
    });

    it('serializes delayed saves and bases a rapid second field change on the first', 0, async () => {
      const repo = new DelayedSettingsRepository();
      const store = new SettingsStore();
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());

      const soundChange = controller.setKeySoundEnabled(true);
      await repo.firstSaveStarted.promise;
      const hapticChange = controller.setHapticLevel(HapticLevel.STRONG);
      expect(repo.saveCount).assertEqual(1);
      repo.releaseFirstSave.resolve();

      expect((await soundChange).success).assertTrue();
      expect((await hapticChange).success).assertTrue();
      expect(repo.maxConcurrentWrites).assertEqual(1);
      expect(repo.savedSettings[0].keySoundEnabled).assertTrue();
      expect(repo.savedSettings[0].hapticLevel).assertEqual(HapticLevel.LIGHT);
      expect(repo.savedSettings[1].keySoundEnabled).assertTrue();
      expect(repo.savedSettings[1].hapticLevel).assertEqual(HapticLevel.STRONG);
      expect(store.getSnapshot().keySoundEnabled).assertTrue();
      expect(store.getSnapshot().hapticLevel).assertEqual(HapticLevel.STRONG);
      expect(repo.settings.keySoundEnabled).assertTrue();
      expect(repo.settings.hapticLevel).assertEqual(HapticLevel.STRONG);
    });

    it('keeps the last rapid mutation of the same setting', 0, async () => {
      const repo = new FakeSettingsRepository();
      const store = new SettingsStore();
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());

      const enabled = controller.setKeySoundEnabled(true);
      const disabled = controller.setKeySoundEnabled(false);
      const enabledAgain = controller.setKeySoundEnabled(true);
      await enabled;
      await disabled;
      await enabledAgain;

      expect(repo.saveCount).assertEqual(3);
      expect(repo.savedSettings[0].keySoundEnabled).assertTrue();
      expect(repo.savedSettings[1].keySoundEnabled).assertFalse();
      expect(repo.savedSettings[2].keySoundEnabled).assertTrue();
      expect(store.getSnapshot().keySoundEnabled).assertTrue();
      expect(repo.settings.keySoundEnabled).assertTrue();
    });

    it('continues queued settings after a failed save without exposing unsaved state', 0, async () => {
      const repo = new FakeSettingsRepository();
      repo.saveResults = [false, true];
      const store = new SettingsStore();
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());

      const failed = controller.setThemeMode(ThemeMode.DARK);
      const continued = controller.setKeyboardHeightMode(KeyboardHeightMode.TALL);
      expect((await failed).success).assertFalse();
      expect((await continued).success).assertTrue();

      expect(repo.saveCount).assertEqual(2);
      expect(repo.savedSettings[1].themeMode).assertEqual(ThemeMode.FOLLOW_SYSTEM);
      expect(store.getSnapshot().themeMode).assertEqual(ThemeMode.FOLLOW_SYSTEM);
      expect(store.getSnapshot().keyboardHeightMode).assertEqual(KeyboardHeightMode.TALL);
      expect(imeSettingsEqual(store.getSnapshot(), repo.settings)).assertTrue();
    });

    it('recovers the settings queue after a repository promise rejects', 0, async () => {
      const repo = new RejectingFirstSettingsRepository();
      const store = new SettingsStore();
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());
      let firstRejected = false;

      const rejected = controller.setThemeMode(ThemeMode.DARK);
      const continued = controller.setHapticLevel(HapticLevel.MEDIUM);
      await rejected.catch((err: Object): void => {
        firstRejected = true;
      });
      const continuedResult = await continued;

      expect(firstRejected).assertTrue();
      expect(continuedResult.success).assertTrue();
      expect(store.getSnapshot().themeMode).assertEqual(ThemeMode.FOLLOW_SYSTEM);
      expect(store.getSnapshot().hapticLevel).assertEqual(HapticLevel.MEDIUM);
      expect(imeSettingsEqual(store.getSnapshot(), repo.settings)).assertTrue();
    });

    it('preserves rapid successful changes across three different fields', 0, async () => {
      const repo = new FakeSettingsRepository();
      const store = new SettingsStore();
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());

      const theme = controller.setThemeMode(ThemeMode.DARK);
      const height = controller.setKeyboardHeightMode(KeyboardHeightMode.TALL);
      const font = controller.setCandidateFontSizeMode(CandidateFontSizeMode.LARGE);
      await theme;
      await height;
      await font;

      const stored = store.getSnapshot();
      expect(stored.themeMode).assertEqual(ThemeMode.DARK);
      expect(stored.keyboardHeightMode).assertEqual(KeyboardHeightMode.TALL);
      expect(stored.candidateFontSizeMode).assertEqual(CandidateFontSizeMode.LARGE);
      expect(imeSettingsEqual(stored, repo.settings)).assertTrue();
    });

    it('queues restore defaults behind an in-flight settings save', 0, async () => {
      const repo = new DelayedSettingsRepository();
      const store = new SettingsStore();
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());

      const changed = controller.setThemeMode(ThemeMode.DARK);
      await repo.firstSaveStarted.promise;
      const reset = controller.resetToDefaults();
      expect(repo.saveCount).assertEqual(1);
      repo.releaseFirstSave.resolve();

      expect((await changed).success).assertTrue();
      expect((await reset).success).assertTrue();
      expect(repo.maxConcurrentWrites).assertEqual(1);
      expect(repo.saveCount).assertEqual(2);
      expect(imeSettingsEqual(store.getSnapshot(), DEFAULT_IME_SETTINGS)).assertTrue();
      expect(imeSettingsEqual(store.getSnapshot(), repo.settings)).assertTrue();
    });

    it('initialization still restores saved settings and marks the Store initialized', 0, async () => {
      const repo = new FakeSettingsRepository();
      repo.settings.themeMode = ThemeMode.DARK;
      repo.settings.keySoundEnabled = true;
      const store = new SettingsStore();
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());

      const loaded = await controller.initialize({} as common.Context);

      expect(loaded.themeMode).assertEqual(ThemeMode.DARK);
      expect(loaded.keySoundEnabled).assertTrue();
      expect(store.isInitialized()).assertTrue();
      expect(imeSettingsEqual(store.getSnapshot(), repo.settings)).assertTrue();
    });

    it('new input runtime restores the complete persisted snapshot including tall mode', 0, async () => {
      const repo = new FakeSettingsRepository();
      repo.settings.themeMode = ThemeMode.DARK;
      repo.settings.keyboardHeightMode = KeyboardHeightMode.TALL;
      repo.settings.candidateFontSizeMode = CandidateFontSizeMode.LARGE;
      repo.settings.hapticLevel = HapticLevel.MEDIUM;
      repo.settings.keySoundEnabled = true;
      repo.settings.userLearningEnabled = false;
      const store = new SettingsStore();
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());

      await controller.initialize({ processName: 'com.corrosion.shuangyuime:inputMethod' } as common.Context);

      expect(imeSettingsEqual(controller.getSettings(), repo.settings)).assertTrue();
      expect(controller.getSettings().keyboardHeightMode).assertEqual(KeyboardHeightMode.TALL);
    });

    it('repeated reload of an equal snapshot does not notify or resize consumers again', 0, async () => {
      const repo = new FakeSettingsRepository();
      repo.settings.keyboardHeightMode = KeyboardHeightMode.TALL;
      const store = new SettingsStore();
      let notifications = 0;
      store.subscribe((): void => { notifications += 1; });
      const controller = new SettingsController(repo, store, new FakeSettingsEngine(), new InputSessionStore());
      const context = { processName: 'com.corrosion.shuangyuime:inputMethod' } as common.Context;

      await controller.initialize(context);
      await controller.reload(context);
      await controller.reload(context);

      expect(repo.loadCount).assertEqual(3);
      expect(notifications).assertEqual(1);
    });

    it('global learning setting reaches engine and persists without deleting data', 0, async () => {
      const repo = new FakeSettingsRepository();
      const store = new SettingsStore();
      const engine = new FakeSettingsEngine();
      const controller = new SettingsController(repo, store, engine, new InputSessionStore());
      const result = await controller.setUserLearningEnabled(false);
      expect(result.success).assertTrue();
      expect(engine.globalValues[0]).assertFalse();
      expect(store.getSnapshot().userLearningEnabled).assertFalse();
    });

    it('rejects an uninstalled shuangpin scheme', 0, async () => {
      const controller = new SettingsController(
        new FakeSettingsRepository(), new SettingsStore(), new FakeSettingsEngine(), new InputSessionStore()
      );
      const result = await controller.changeScheme('microsoft');
      expect(result.success).assertFalse();
    });

    it('stage5SwitchesAllFourProfilesAndClearsSameSchemeLayoutState', 0, async () => {
      const repo = new FakeSettingsRepository();
      const settingsStore = new SettingsStore();
      const sessionStore = new InputSessionStore();
      const engine = new FakeSettingsEngine();
      const controller = new SettingsController(repo, settingsStore, engine, sessionStore);
      sessionStore.updateComposition(candidateComposition());

      const xiaohe18 = await controller.setKeyboardProfile(XIAOHE_18_PROFILE_ID);
      expect(xiaohe18.success).assertTrue();
      expect(engine.resetCount).assertEqual(1);
      expect(engine.schemeChanges.length).assertEqual(0);
      expect(sessionStore.getSnapshot().rawInput).assertEqual('');

      expect((await controller.setKeyboardProfile(XIAOHE_26_PROFILE_ID)).success).assertTrue();
      expect((await controller.setKeyboardProfile(QUANPIN_26_PROFILE_ID)).success).assertTrue();
      expect(controller.getSettings().schemeId).assertEqual('quanpin');
      expect((await controller.setKeyboardProfile(PINYIN_9_PROFILE_ID)).success).assertTrue();
      expect(controller.getSettings().keyboardProfileId).assertEqual(PINYIN_9_PROFILE_ID);
      expect(controller.getSettings().schemeId).assertEqual('pinyin-9');
      expect(engine.getActiveSchemeId()).assertEqual('pinyin-9');
      expect(repo.settings.keyboardProfileId).assertEqual(PINYIN_9_PROFILE_ID);
    });

    it('stage5NativeProfileFailureKeepsUiAndPersistenceOnThePreviousProfile', 0, async () => {
      const repo = new FakeSettingsRepository();
      const settingsStore = new SettingsStore();
      const engine = new FakeSettingsEngine();
      engine.rejectSchemeId = 'pinyin-9';
      const controller = new SettingsController(repo, settingsStore, engine, new InputSessionStore());

      const result = await controller.setKeyboardProfile(PINYIN_9_PROFILE_ID);

      expect(result.success).assertFalse();
      expect(controller.getSettings().keyboardProfileId).assertEqual(XIAOHE_26_PROFILE_ID);
      expect(controller.getSettings().schemeId).assertEqual('xiaohe');
      expect(repo.saveCount).assertEqual(0);
      expect(engine.getActiveSchemeId()).assertEqual('xiaohe');
      expect(engine.schemeChanges.join('|')).assertEqual('pinyin-9|xiaohe');
    });

    it('stage5PersistenceFailureRollsTheRustSchemeBackAndDoesNotPublishTheProfile', 0, async () => {
      const repo = new FakeSettingsRepository();
      repo.saveSucceeds = false;
      const settingsStore = new SettingsStore();
      const engine = new FakeSettingsEngine();
      const controller = new SettingsController(repo, settingsStore, engine, new InputSessionStore());

      const result = await controller.setKeyboardProfile(QUANPIN_26_PROFILE_ID);

      expect(result.success).assertFalse();
      expect(controller.getSettings().keyboardProfileId).assertEqual(XIAOHE_26_PROFILE_ID);
      expect(repo.settings.keyboardProfileId).assertEqual(XIAOHE_26_PROFILE_ID);
      expect(engine.getActiveSchemeId()).assertEqual('xiaohe');
      expect(engine.schemeChanges.join('|')).assertEqual('quanpin|xiaohe');
    });

    it('haptic off does not call backend and levels map increasingly', 0, () => {
      const store = new SettingsStore();
      const backend = new FakeHapticBackend();
      const service = new HapticFeedbackService(backend, store);
      const off = store.getSnapshot();
      off.hapticLevel = HapticLevel.OFF;
      store.replace(off);
      service.trigger();
      expect(backend.durations.length).assertEqual(0);
      const light = store.getSnapshot(); light.hapticLevel = HapticLevel.LIGHT; store.replace(light); service.trigger();
      const medium = store.getSnapshot(); medium.hapticLevel = HapticLevel.MEDIUM; store.replace(medium); service.trigger();
      const strong = store.getSnapshot(); strong.hapticLevel = HapticLevel.STRONG; store.replace(strong); service.trigger();
      expect(backend.durations[0] < backend.durations[1]).assertTrue();
      expect(backend.durations[1] < backend.durations[2]).assertTrue();
    });

    it('haptic repeated delete is throttled and backend exceptions are contained', 0, () => {
      const store = new SettingsStore();
      store.replace(copyImeSettings(DEFAULT_IME_SETTINGS));
      const backend = new FakeHapticBackend(); backend.reject = true;
      const service = new HapticFeedbackService(backend, store);
      service.trigger(true, 1000);
      service.trigger(true, 1050);
      service.trigger(true, 1130);
      expect(backend.durations.length).assertEqual(2);
    });

    it('key sound respects setting, throttles, contains errors and releases once', 0, () => {
      const store = new SettingsStore();
      const backend = new FakeSoundBackend(); backend.reject = true;
      const service = new KeySoundService(backend, store);
      service.trigger(1000);
      expect(backend.playCount).assertEqual(0);
      const enabled = store.getSnapshot(); enabled.keySoundEnabled = true; store.replace(enabled);
      service.trigger(1000); service.trigger(1010); service.trigger(1030);
      expect(backend.playCount).assertEqual(2);
      service.dispose(); service.dispose();
      expect(backend.disposeCount).assertEqual(1);
    });
  });
}
