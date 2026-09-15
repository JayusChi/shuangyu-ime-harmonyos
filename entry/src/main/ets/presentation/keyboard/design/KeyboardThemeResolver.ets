import { EffectiveTheme } from '../../../domain/settings/ImeSettings';
import { KeyboardSkinDefinition } from '../../../domain/customization/KeyboardCustomization';
import { DARK_PALETTE, KeyboardColorPalette, LIGHT_PALETTE } from './KeyboardPalette';

export class KeyboardThemeResolver {
  resolveFloatingCandidates(theme: EffectiveTheme): KeyboardColorPalette {
    const dark = theme === EffectiveTheme.DARK;
    return this.resolve(theme, {
      schemaVersion: 1, id: 'builtin.floating-candidates', name: '浮动候选', images: {},
      colors: {
        candidateBackground: dark ? '#24282E' : '#FFFFFF',
        candidateText: dark ? '#F3F4F6' : '#191B20',
        candidateReading: dark ? '#A8B0BE' : '#959DAA',
        candidateDivider: dark ? '#414752' : '#E5E7EB',
        functionKeyBackground: dark ? '#343A44' : '#F5F6F7',
        functionKeyText: dark ? '#E5E7EB' : '#535B68'
      }
    });
  }

  resolve(
    theme: EffectiveTheme,
    skin?: KeyboardSkinDefinition,
    assetRoot: string = ''
  ): KeyboardColorPalette {
    const base = theme === EffectiveTheme.DARK ? DARK_PALETTE : LIGHT_PALETTE;
    if (!skin) {
      return base;
    }
    const colors = skin.colors;
    const images = skin.images;
    return {
      useDarkMedia: base.useDarkMedia,
      useDanranKeyImages: false,
      panelBackgroundImage: this.assetPath(assetRoot, images.panelBackground),
      letterKeyBackgroundImage: this.assetPath(assetRoot, images.letterKey),
      functionKeyBackgroundImage: this.assetPath(assetRoot, images.functionKey),
      spaceKeyBackgroundImage: this.assetPath(assetRoot, images.spaceKey),
      enterKeyBackgroundImage: this.assetPath(assetRoot, images.enterKey),
      panelBackground: this.color(colors.panelBackground, base.panelBackground),
      candidateBackground: this.color(colors.candidateBackground, base.candidateBackground),
      letterKeyBackground: this.color(colors.letterKeyBackground, base.letterKeyBackground),
      functionKeyBackground: this.color(colors.functionKeyBackground, base.functionKeyBackground),
      spaceKeyBackground: this.color(colors.spaceKeyBackground, base.spaceKeyBackground),
      primaryFunctionBackground: this.color(colors.primaryFunctionBackground, base.primaryFunctionBackground),
      modeKeyBackgroundEnglish: this.color(colors.modeKeyBackgroundEnglish, base.modeKeyBackgroundEnglish),
      modeKeyBackgroundChinese: this.color(colors.modeKeyBackgroundChinese, base.modeKeyBackgroundChinese),
      letterKeyPressedBackground: this.color(colors.letterKeyPressedBackground, base.letterKeyPressedBackground),
      functionKeyPressedBackground: this.color(colors.functionKeyPressedBackground, base.functionKeyPressedBackground),
      primaryFunctionPressedBackground: this.color(colors.primaryFunctionPressedBackground, base.primaryFunctionPressedBackground),
      letterKeyText: this.color(colors.letterKeyText, base.letterKeyText),
      functionKeyText: this.color(colors.functionKeyText, base.functionKeyText),
      primaryFunctionText: this.color(colors.primaryFunctionText, base.primaryFunctionText),
      modeKeyTextEnglish: this.color(colors.modeKeyTextEnglish, base.modeKeyTextEnglish),
      modeKeyTextChinese: this.color(colors.modeKeyTextChinese, base.modeKeyTextChinese),
      errorText: this.color(colors.errorText, base.errorText),
      previewBackground: this.color(colors.previewBackground, base.previewBackground),
      previewText: this.color(colors.previewText, base.previewText),
      previewShadow: this.color(colors.previewShadow, base.previewShadow),
      candidateText: this.color(colors.candidateText, base.candidateText),
      candidateReading: this.color(colors.candidateReading, base.candidateReading),
      candidateDivider: this.color(colors.candidateDivider, base.candidateDivider),
      keyBorder: this.color(colors.keyBorder, base.keyBorder)
    };
  }

  private color(value: string | undefined, fallback: string): string {
    if (value === undefined) {
      return fallback;
    }
    // Package colors follow CSS RGBA; ArkUI expects alpha before RGB.
    return value.length === 9 ? '#' + value.slice(7, 9) + value.slice(1, 7) : value;
  }

  private assetPath(assetRoot: string, relativePath: string | undefined): string {
    if (assetRoot.length === 0 || !relativePath) {
      return '';
    }
    // ArkUI image sources require a file URI for sandbox files. A bare path is
    // interpreted as a packaged resource and can silently leave the color only.
    const path = `${assetRoot}/${relativePath}`;
    return 'file://' + path.split('/').map((part: string): string => encodeURIComponent(part)).join('/');
  }
}
