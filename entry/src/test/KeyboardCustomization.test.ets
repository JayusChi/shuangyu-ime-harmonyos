import { describe, expect, it } from '@ohos/hypium';
import { createUnknownEditorContext, ShiftState } from '../main/ets/domain/editor/EditorContext';
import { KeyboardMode } from '../main/ets/domain/keyboard/KeyboardAction';
import {
  BUILTIN_KEYBOARD_SKIN_ID,
  BUILTIN_KEYBOARD_STRUCTURE_ID,
  KeyboardCustomizationShortcut,
  KeyboardStructureDefinition,
  parseKeyboardSkinJson,
  parseKeyboardStructureJson,
  resolveKeyboardCustomizationShortcut
} from '../main/ets/domain/customization/KeyboardCustomization';
import {
  bundledKeyboardSkinOptions,
  bundledKeyboardStructureOptions,
  loadBundledKeyboardSkin,
  loadBundledKeyboardStructure,
  SOFT_BLUE_SKIN_ID,
  WIDE_SPACE_STRUCTURE_ID
} from '../main/ets/domain/customization/BundledKeyboardCustomizations';
import { EffectiveTheme, SettingsRaw } from '../main/ets/domain/settings/ImeSettings';
import { SettingsValidator } from '../main/ets/infrastructure/storage/SettingsValidator';
import {
  applyKeyboardStructure
} from '../main/ets/presentation/keyboard/customization/KeyboardStructureResolver';
import { KeyboardThemeResolver } from '../main/ets/presentation/keyboard/design/KeyboardThemeResolver';
import { LIGHT_PALETTE } from '../main/ets/presentation/keyboard/design/KeyboardPalette';
import { createStage10KeyboardLayout } from '../main/ets/presentation/keyboard/layouts/Stage10KeyboardLayouts';

const VALID_STRUCTURE_JSON: string = `{
  "schemaVersion": 1,
  "id": "sample.reversed-top",
  "name": "测试结构",
  "rows": [
    { "kind": "top_letters", "keys": [
      { "id": "letter-p", "weight": 1.2 }, { "id": "letter-o" }, { "id": "letter-i" },
      { "id": "letter-u" }, { "id": "letter-y" }, { "id": "letter-t" },
      { "id": "letter-r" }, { "id": "letter-e" }, { "id": "letter-w" }, { "id": "letter-q" }
    ]},
    { "kind": "middle_letters", "keys": [
      { "id": "letter-a" }, { "id": "letter-s" }, { "id": "letter-d" },
      { "id": "letter-f" }, { "id": "letter-g" }, { "id": "letter-h" },
      { "id": "letter-j" }, { "id": "letter-k" }, { "id": "letter-l" }
    ]},
    { "kind": "bottom_letters", "keys": [
      { "id": "left-action" }, { "id": "letter-z" }, { "id": "letter-x" },
      { "id": "letter-c" }, { "id": "letter-v" }, { "id": "letter-b" },
      { "id": "letter-n" }, { "id": "letter-m" }, { "id": "delete" }
    ]},
    { "kind": "bottom_actions", "keys": [
      { "id": "number" }, { "id": "symbol" }, { "id": "space", "label": "空格" },
      { "id": "enter" }
    ]}
  ]
}`;

const VALID_SKIN_JSON: string = `{
  "schemaVersion": 1,
  "id": "sample.blue",
  "name": "柔蓝",
  "colors": {
    "panelBackground": "#E8F2FF",
    "letterKeyText": "#123456FF"
  },
  "images": {
    "letterKey": "assets/letter-key.png"
  }
}`;

export default function keyboardCustomizationTest() {
  describe('Keyboard customization packages', () => {
    it('parses a complete independent keyboard structure', 0, () => {
      const result = parseKeyboardStructureJson(VALID_STRUCTURE_JSON);
      expect(result.success).assertTrue();
      expect(result.value?.id).assertEqual('sample.reversed-top');
      expect(result.value?.rows.length).assertEqual(4);
      expect(result.value?.rows[0].keys[0].weight).assertEqual(1.2);
    });

    it('rejects structures missing required semantic keys', 0, () => {
      const invalid = VALID_STRUCTURE_JSON.replace(',\n      { "id": "enter" }', '');
      const result = parseKeyboardStructureJson(invalid);
      expect(result.success).assertFalse();
      expect(result.message.indexOf('enter') >= 0).assertTrue();
    });

    it('rejects out-of-range structure weights', 0, () => {
      const invalid = VALID_STRUCTURE_JSON.replace('"weight": 1.2', '"weight": 80');
      const result = parseKeyboardStructureJson(invalid);
      expect(result.success).assertFalse();
      expect(result.message.indexOf('weight') >= 0).assertTrue();
    });

    it('parses skin colors and sandbox-local image references', 0, () => {
      const result = parseKeyboardSkinJson(VALID_SKIN_JSON);
      expect(result.success).assertTrue();
      expect(result.value?.colors.panelBackground).assertEqual('#E8F2FF');
      expect(result.value?.images.letterKey).assertEqual('assets/letter-key.png');
    });

    it('rejects invalid colors and asset traversal', 0, () => {
      const badColor = parseKeyboardSkinJson(VALID_SKIN_JSON.replace('#E8F2FF', 'blue'));
      const badAsset = parseKeyboardSkinJson(
        VALID_SKIN_JSON.replace('assets/letter-key.png', '../letter-key.png'));
      expect(badColor.success).assertFalse();
      expect(badAsset.success).assertFalse();
    });

    it('rejects non-object manifests without throwing', 0, () => {
      expect(parseKeyboardStructureJson('null').success).assertFalse();
      expect(parseKeyboardSkinJson('[]').success).assertFalse();
    });

    it('resolves only the two documented touch-key chords', 0, () => {
      expect(resolveKeyboardCustomizationShortcut(['number', 'space']))
        .assertEqual(KeyboardCustomizationShortcut.CYCLE_SKIN);
      expect(resolveKeyboardCustomizationShortcut(['space', 'symbol']))
        .assertEqual(KeyboardCustomizationShortcut.CYCLE_STRUCTURE);
      expect(resolveKeyboardCustomizationShortcut(['space', 'punctuation-period']))
        .assertEqual(KeyboardCustomizationShortcut.CYCLE_STRUCTURE);
      expect(resolveKeyboardCustomizationShortcut(['number']))
        .assertEqual(KeyboardCustomizationShortcut.NONE);
    });

    it('reorders QWERTY while preserving built-in key actions', 0, () => {
      const parsed = parseKeyboardStructureJson(VALID_STRUCTURE_JSON);
      const structure = parsed.value as KeyboardStructureDefinition;
      const base = createStage10KeyboardLayout(
        KeyboardMode.ENGLISH, createUnknownEditorContext(), ShiftState.LOWERCASE);
      const customized = applyKeyboardStructure(base, structure);
      expect(customized.rows[0].keys[0].id).assertEqual('letter-p');
      expect(customized.rows[0].keys[0].weight).assertEqual(1.2);
      expect(customized.rows[0].keys[0].action.type).assertEqual(base.rows[0].keys[9].action.type);
      expect(customized.rows[3].keys.map((key) => key.id).join(','))
        .assertEqual('number,punctuation-comma,space,punctuation-period,enter');
    });

    it('keeps non-QWERTY layouts authoritative', 0, () => {
      const parsed = parseKeyboardStructureJson(VALID_STRUCTURE_JSON);
      const structure = parsed.value as KeyboardStructureDefinition;
      const numberLayout = createStage10KeyboardLayout(
        KeyboardMode.NUMBER, createUnknownEditorContext(), ShiftState.LOWERCASE);
      expect(applyKeyboardStructure(numberLayout, structure) === numberLayout).assertTrue();
    });

    it('merges a skin over the effective theme and resolves image paths', 0, () => {
      const skin = parseKeyboardSkinJson(VALID_SKIN_JSON).value;
      const palette = new KeyboardThemeResolver().resolve(EffectiveTheme.LIGHT, skin, '/data/skin');
      expect(palette.panelBackground).assertEqual('#E8F2FF');
      expect(palette.functionKeyBackground).assertEqual(LIGHT_PALETTE.functionKeyBackground);
      expect(palette.letterKeyBackgroundImage).assertEqual('/data/skin/assets/letter-key.png');
    });

    it('preserves valid selected IDs and falls back for invalid values', 0, () => {
      const validator = new SettingsValidator();
      const valid: SettingsRaw = {
        keyboardStructureId: 'sample.reversed-top',
        keyboardSkinId: 'sample.blue'
      };
      expect(validator.validate(valid).keyboardStructureId).assertEqual('sample.reversed-top');
      expect(validator.validate(valid).keyboardSkinId).assertEqual('sample.blue');
      const invalid: SettingsRaw = { keyboardStructureId: '../bad', keyboardSkinId: 'Bad ID' };
      expect(validator.validate(invalid).keyboardStructureId).assertEqual(BUILTIN_KEYBOARD_STRUCTURE_ID);
      expect(validator.validate(invalid).keyboardSkinId).assertEqual(BUILTIN_KEYBOARD_SKIN_ID);
    });

    it('ships multiple immediately switchable structures and skins', 0, () => {
      expect(bundledKeyboardStructureOptions().length).assertEqual(3);
      expect(bundledKeyboardSkinOptions().length).assertEqual(4);
      expect(loadBundledKeyboardStructure(WIDE_SPACE_STRUCTURE_ID)?.rows.length).assertEqual(4);
      expect(loadBundledKeyboardSkin(SOFT_BLUE_SKIN_ID)?.colors.panelBackground).assertEqual('#D8E4F4');
    });
  });
}
