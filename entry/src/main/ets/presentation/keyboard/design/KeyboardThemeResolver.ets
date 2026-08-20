import { EffectiveTheme } from '../../../domain/settings/ImeSettings';
import { DARK_PALETTE, KeyboardColorPalette, LIGHT_PALETTE } from './KeyboardPalette';

export class KeyboardThemeResolver {
  resolve(theme: EffectiveTheme): KeyboardColorPalette {
    return theme === EffectiveTheme.DARK ? DARK_PALETTE : LIGHT_PALETTE;
  }
}
