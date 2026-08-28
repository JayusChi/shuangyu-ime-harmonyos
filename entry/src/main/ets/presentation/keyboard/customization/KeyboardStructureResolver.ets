import {
  KeyboardStructureDefinition,
  KeyboardStructureKeyDefinition,
  KeyboardStructureRowDefinition
} from '../../../domain/customization/KeyboardCustomization';
import {
  KeyboardKeySpec,
  KeyboardLayoutSpec,
  KeyboardRowKind,
  KeyboardRowSpec
} from '../model/KeyboardLayoutSpec';

const LETTER_IDS: string[] = 'abcdefghijklmnopqrstuvwxyz'.split('').map((letter: string): string =>
  `letter-${letter}`);

function rowKind(value: string | undefined): KeyboardRowKind | undefined {
  if (value === KeyboardRowKind.TOP_LETTERS || value === KeyboardRowKind.MIDDLE_LETTERS ||
    value === KeyboardRowKind.BOTTOM_LETTERS || value === KeyboardRowKind.AUXILIARY ||
    value === KeyboardRowKind.BOTTOM_ACTIONS) {
    return value as KeyboardRowKind;
  }
  return undefined;
}

function resolveKeyId(id: string, available: KeyboardKeySpec[]): string {
  if (id !== 'left-action') {
    return id;
  }
  return available.some((key: KeyboardKeySpec): boolean => key.id === 'escape') ? 'escape' : 'shift';
}

function copyKey(
  original: KeyboardKeySpec,
  definition?: KeyboardStructureKeyDefinition
): KeyboardKeySpec {
  const copy: KeyboardKeySpec = {
    id: original.id,
    label: original.label,
    kind: original.kind,
    weight: definition?.weight ?? original.weight,
    action: original.action,
    previewEnabled: original.previewEnabled,
    accessibilityLabel: definition?.label ?? original.accessibilityLabel,
    active: original.active
  };
  copy.upperLabel = original.upperLabel;
  copy.secondaryLabel = original.secondaryLabel;
  copy.previewLabel = original.previewLabel;
  copy.longPressAction = original.longPressAction;
  copy.swipeUpAction = original.swipeUpAction;
  copy.swipeDownAction = original.swipeDownAction;
  copy.alternatives = original.alternatives?.slice();
  if (definition?.label !== undefined) {
    copy.label = definition.label;
  }
  return copy;
}

function enforceSplitPunctuationAroundSpace(
  keys: KeyboardKeySpec[],
  available: KeyboardKeySpec[]
): void {
  let spaceIndex = keys.findIndex((key: KeyboardKeySpec): boolean => key.id === 'space');
  if (spaceIndex < 0) {
    return;
  }
  if (!keys.some((key: KeyboardKeySpec): boolean => key.id === 'punctuation-comma')) {
    const comma = available.find((key: KeyboardKeySpec): boolean => key.id === 'punctuation-comma');
    if (comma) {
      keys.splice(spaceIndex, 0, copyKey(comma));
      spaceIndex += 1;
    }
  }
  if (!keys.some((key: KeyboardKeySpec): boolean => key.id === 'punctuation-period')) {
    const period = available.find((key: KeyboardKeySpec): boolean => key.id === 'punctuation-period');
    if (period) {
      keys.splice(spaceIndex + 1, 0, copyKey(period));
    }
  }
}

/**
 * A structure package can only rearrange keys that the active input mode already
 * owns. Number, symbol, T9 and 18-key layouts therefore keep their authoritative
 * built-in layout and input semantics.
 */
export function applyKeyboardStructure(
  base: KeyboardLayoutSpec,
  structure: KeyboardStructureDefinition | undefined
): KeyboardLayoutSpec {
  if (!structure) {
    return base;
  }
  const available: KeyboardKeySpec[] = [];
  base.rows.forEach((row: KeyboardRowSpec): void => {
    row.keys.forEach((key: KeyboardKeySpec): void => {
      available.push(key);
    });
  });
  const qwerty = LETTER_IDS.every((id: string): boolean =>
    available.some((key: KeyboardKeySpec): boolean => key.id === id));
  if (!qwerty) {
    return base;
  }

  const rows: KeyboardRowSpec[] = [];
  structure.rows.forEach((definition: KeyboardStructureRowDefinition): void => {
    const keys: KeyboardKeySpec[] = [];
    definition.keys.forEach((keyDefinition: KeyboardStructureKeyDefinition): void => {
      const id = resolveKeyId(keyDefinition.id, available);
      const original = available.find((key: KeyboardKeySpec): boolean => key.id === id);
      if (!original) {
        return;
      }
      keys.push(copyKey(original, keyDefinition));
    });
    enforceSplitPunctuationAroundSpace(keys, available);
    if (keys.length > 0) {
      const row: KeyboardRowSpec = { keys };
      const kind = rowKind(definition.kind);
      if (kind !== undefined) {
        row.kind = kind;
      }
      rows.push(row);
    }
  });
  return rows.length >= 3 ? { rows } : base;
}
