import { SettingsWindowStyle } from '../../application/SettingsWindowCoordinator';

// Stage 10 is an acceptance surface, so its palette deliberately does not resolve app or system themes.
export const DEBUG_PAGE_BACKGROUND = '#FFFFFF';
export const DEBUG_INPUT_BACKGROUND = '#F6F8FA';
export const DEBUG_PRIMARY_TEXT = '#1F2937';
export const DEBUG_SECONDARY_TEXT = '#4E5969';
export const DEBUG_PLACEHOLDER_TEXT = '#6B7280';
export const DEBUG_STATUS_TEXT = '#007D5A';
export const DEBUG_CARET = '#0A59F7';

export const DEBUG_FIXED_LIGHT_WINDOW_STYLE: SettingsWindowStyle = {
  backgroundColor: DEBUG_PAGE_BACKGROUND,
  contentColor: DEBUG_PRIMARY_TEXT,
  lightIcons: false
};
