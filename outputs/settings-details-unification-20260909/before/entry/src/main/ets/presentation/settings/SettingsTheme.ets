export interface SettingsThemeTokens {
  pageBackground: string;
  cardBackground: string;
  primaryText: string;
  secondaryText: string;
  accent: string;
  chipBackground: string;
  selectedChipBackground: string;
  divider: string;
  danger: string;
}

export const LIGHT_SETTINGS_THEME: SettingsThemeTokens = {
  pageBackground: '#F5F7FA',
  cardBackground: '#FFFFFF',
  primaryText: '#18212F',
  secondaryText: '#657080',
  accent: '#0A59F7',
  chipBackground: '#EEF1F5',
  selectedChipBackground: '#DCEBFF',
  divider: '#E5E9F0',
  danger: '#C73434'
};

export const DARK_SETTINGS_THEME: SettingsThemeTokens = {
  pageBackground: '#111827',
  cardBackground: '#1F2937',
  primaryText: '#F9FAFB',
  secondaryText: '#AAB3C0',
  accent: '#78AFFF',
  chipBackground: '#374151',
  selectedChipBackground: '#1E4A80',
  divider: '#374151',
  danger: '#FF8B8B'
};

export function resolveSettingsTheme(isDark: boolean): SettingsThemeTokens {
  return isDark ? DARK_SETTINGS_THEME : LIGHT_SETTINGS_THEME;
}
