import {
  CURRENT_SETTINGS_SCHEMA_VERSION,
  SettingsRaw,
  XIAOHE_YINXING_CATEGORY_IDS,
  XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION
} from '../../domain/settings/ImeSettings';
import { keyboardProfileForLegacy } from '../../domain/keyboard/KeyboardProfile';

export class SettingsMigration {
  migrate(raw: SettingsRaw): SettingsRaw {
    const migrated: SettingsRaw = this.copyRaw(raw);
    const parsedVersion = Number.parseInt(raw.schemaVersion ?? '0');

    if (!migrated.keyboardProfileId) {
      migrated.keyboardProfileId = keyboardProfileForLegacy(raw.schemeId, raw.legacyKeyboardLayout);
    }

    if (!Number.isFinite(parsedVersion) || parsedVersion <= 0) {
      if (!migrated.themeMode && raw.darkMode) {
        migrated.themeMode = raw.darkMode === 'true' ? 'dark' : 'light';
      }
      if (!migrated.keyboardHeightMode && raw.keyboardScale) {
        migrated.keyboardHeightMode = this.migrateHeight(raw.keyboardScale);
      }
      if (!migrated.candidateFontSizeMode && raw.candidateFontScale) {
        migrated.candidateFontSizeMode = this.migrateCandidateFont(raw.candidateFontScale);
      }
      if (!migrated.hapticLevel && raw.vibrationEnabled) {
        migrated.hapticLevel = raw.vibrationEnabled === 'false' ? 'off' : 'light';
      }
    }

    if (!migrated.xiaoheYinxingEnabledCategoryIds) {
      migrated.xiaoheYinxingEnabledCategoryIds = JSON.stringify(XIAOHE_YINXING_CATEGORY_IDS);
    } else {
      const categoryVersion = Number.parseInt(raw.xiaoheYinxingCategorySchemaVersion ?? '0');
      if (!Number.isFinite(categoryVersion) || categoryVersion < 3) {
        migrated.xiaoheYinxingEnabledCategoryIds = this.enableNewYinxingCategories(
          migrated.xiaoheYinxingEnabledCategoryIds
        );
      }
    }
    if (!migrated.spellingCorrectionEnabled) {
      migrated.spellingCorrectionEnabled = 'false';
    }
    if (!migrated.fuzzyOptions) {
      migrated.fuzzyOptions = '[]';
    }
    migrated.xiaoheYinxingCategorySchemaVersion = `${XIAOHE_YINXING_CATEGORY_SCHEMA_VERSION}`;
    migrated.schemaVersion = `${CURRENT_SETTINGS_SCHEMA_VERSION}`;
    return migrated;
  }

  private enableNewYinxingCategories(value: string): string {
    try {
      const parsed: Object[] = JSON.parse(value) as Object[];
      if (!Array.isArray(parsed)) {
        return JSON.stringify(XIAOHE_YINXING_CATEGORY_IDS);
      }
      const ids: string[] = [];
      parsed.forEach((item: Object) => {
        if (typeof item === 'string') {
          ids.push(item as string);
        }
      });
      if (ids.indexOf('quick-symbol') < 0) {
        ids.push('quick-symbol');
      }
      if (ids.indexOf('symbol') < 0) {
        ids.push('symbol');
      }
      if (ids.indexOf('symbol-group') < 0) {
        ids.push('symbol-group');
      }
      return JSON.stringify(ids);
    } catch (_err) {
      return JSON.stringify(XIAOHE_YINXING_CATEGORY_IDS);
    }
  }

  private migrateHeight(value: string): string {
    if (value === '0' || value === 'compact') {
      return 'compact';
    }
    if (value === '2' || value === 'tall') {
      return 'tall';
    }
    return 'standard';
  }

  private migrateCandidateFont(value: string): string {
    if (value === '0' || value === 'small') {
      return 'small';
    }
    if (value === '2' || value === 'large') {
      return 'large';
    }
    return 'standard';
  }

  private copyRaw(raw: SettingsRaw): SettingsRaw {
    return {
      schemaVersion: raw.schemaVersion,
      keyboardProfileId: raw.keyboardProfileId,
      schemeId: raw.schemeId,
      legacyKeyboardLayout: raw.legacyKeyboardLayout,
      themeMode: raw.themeMode,
      keyboardHeightMode: raw.keyboardHeightMode,
      candidateFontSizeMode: raw.candidateFontSizeMode,
      hapticLevel: raw.hapticLevel,
      keySoundEnabled: raw.keySoundEnabled,
      userLearningEnabled: raw.userLearningEnabled,
      spellingCorrectionEnabled: raw.spellingCorrectionEnabled,
      fuzzyOptions: raw.fuzzyOptions,
      inputPresentationPreference: raw.inputPresentationPreference,
      candidatePresentationMode: raw.candidatePresentationMode,
      xiaoheYinxingHintCandidateCount: raw.xiaoheYinxingHintCandidateCount,
      xiaoheYinxingCategorySchemaVersion: raw.xiaoheYinxingCategorySchemaVersion,
      xiaoheYinxingEnabledCategoryIds: raw.xiaoheYinxingEnabledCategoryIds,
      lexiconSources: raw.lexiconSources,
      darkMode: raw.darkMode,
      keyboardScale: raw.keyboardScale,
      candidateFontScale: raw.candidateFontScale,
      vibrationEnabled: raw.vibrationEnabled
    };
  }
}
