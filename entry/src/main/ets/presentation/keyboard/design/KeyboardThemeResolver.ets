import { EffectiveTheme } from '../../../domain/settings/ImeSettings';
import { KeyboardSkinDefinition } from '../../../domain/customization/KeyboardCustomization';
import { DARK_PALETTE, KeyboardColorPalette, LIGHT_PALETTE } from './KeyboardPalette';

export class KeyboardThemeResolver {
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
      panelBackground: colors.panelBackground ?? base.panelBackground,
      candidateBackground: colors.candidateBackground ?? base.candidateBackground,
      letterKeyBackground: colors.letterKeyBackground ?? base.letterKeyBackground,
      functionKeyBackground: colors.functionKeyBackground ?? base.functionKeyBackground,
      spaceKeyBackground: colors.spaceKeyBackground ?? base.spaceKeyBackground,
      primaryFunctionBackground: colors.primaryFunctionBackground ?? base.primaryFunctionBackground,
      modeKeyBackgroundEnglish: colors.modeKeyBackgroundEnglish ?? base.modeKeyBackgroundEnglish,
      modeKeyBackgroundChinese: colors.modeKeyBackgroundChinese ?? base.modeKeyBackgroundChinese,
      letterKeyPressedBackground: colors.letterKeyPressedBackground ?? base.letterKeyPressedBackground,
      functionKeyPressedBackground: colors.functionKeyPressedBackground ?? base.functionKeyPressedBackground,
      primaryFunctionPressedBackground: colors.primaryFunctionPressedBackground ??
        base.primaryFunctionPressedBackground,
      letterKeyText: colors.letterKeyText ?? base.letterKeyText,
      functionKeyText: colors.functionKeyText ?? base.functionKeyText,
      primaryFunctionText: colors.primaryFunctionText ?? base.primaryFunctionText,
      modeKeyTextEnglish: colors.modeKeyTextEnglish ?? base.modeKeyTextEnglish,
      modeKeyTextChinese: colors.modeKeyTextChinese ?? base.modeKeyTextChinese,
      errorText: colors.errorText ?? base.errorText,
      previewBackground: colors.previewBackground ?? base.previewBackground,
      previewText: colors.previewText ?? base.previewText,
      previewShadow: colors.previewShadow ?? base.previewShadow,
      candidateText: colors.candidateText ?? base.candidateText,
      candidateReading: colors.candidateReading ?? base.candidateReading,
      candidateDivider: colors.candidateDivider ?? base.candidateDivider,
      keyBorder: colors.keyBorder ?? base.keyBorder
    };
  }

  private assetPath(assetRoot: string, relativePath: string | undefined): string {
    return assetRoot.length > 0 && relativePath ? `${assetRoot}/${relativePath}` : '';
  }
}
