// Generated from KeyboardCustomization.ets. Run build-editor.cjs to refresh.
globalThis.KeyboardFormat = (() => { const exports = {};
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveKeyboardCustomizationShortcut = exports.KeyboardCustomizationShortcut = exports.parseKeyboardSkinJson = exports.parseKeyboardStructureJson = exports.KEYBOARD_CUSTOMIZATION_SCHEMA_VERSION = exports.BUILTIN_KEYBOARD_SKIN_ID = exports.BUILTIN_KEYBOARD_STRUCTURE_ID = void 0;
exports.BUILTIN_KEYBOARD_STRUCTURE_ID = 'builtin.default';
exports.BUILTIN_KEYBOARD_SKIN_ID = 'builtin.follow-system';
exports.KEYBOARD_CUSTOMIZATION_SCHEMA_VERSION = 1;
const IDENTIFIER_PATTERN = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const COLOR_PATTERN = /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/;
const ASSET_PATTERN = /^assets\/[a-zA-Z0-9][a-zA-Z0-9._-]{0,95}\.(png|jpg|jpeg|webp)$/;
const LETTER_IDS = 'abcdefghijklmnopqrstuvwxyz'.split('').map((letter) => `letter-${letter}`);
const REQUIRED_STRUCTURE_KEYS = LETTER_IDS.concat(['left-action', 'delete', 'space', 'enter']);
const ALLOWED_STRUCTURE_KEYS = REQUIRED_STRUCTURE_KEYS.concat([
    'symbol', 'number', 'punctuation-comma-period', 'punctuation-comma', 'punctuation-period',
    'input-method-switch'
]);
function failure(message) {
    return { success: false, message };
}
function success(value) {
    return { success: true, message: '', value };
}
function validPackageIdentity(record) {
    const schemaVersion = record['schemaVersion'];
    const id = record['id'];
    const name = record['name'];
    if (schemaVersion !== exports.KEYBOARD_CUSTOMIZATION_SCHEMA_VERSION) {
        return '模板版本不受支持';
    }
    if (typeof id !== 'string' || !IDENTIFIER_PATTERN.test(id) || id.startsWith('builtin.')) {
        return '模板 ID 必须由小写字母、数字、点、横线或下划线组成';
    }
    if (typeof name !== 'string' || name.trim().length <= 0 || name.trim().length > 64) {
        return '模板名称长度必须为 1～64 个字符';
    }
    return '';
}
function parseRowKind(value) {
    if (value === undefined) {
        return undefined;
    }
    if (value === 'top_letters' || value === 'middle_letters' || value === 'bottom_letters' ||
        value === 'auxiliary' || value === 'bottom_actions') {
        return value;
    }
    return undefined;
}
function parseKeyboardStructureJson(content) {
    let record;
    try {
        record = JSON.parse(content);
    }
    catch (_err) {
        return failure('layout.json 不是有效的 JSON');
    }
    if (record === null || typeof record !== 'object' || Array.isArray(record)) {
        return failure('layout.json 根节点必须是对象');
    }
    const identityError = validPackageIdentity(record);
    if (identityError.length > 0) {
        return failure(identityError);
    }
    const rawRows = record['rows'];
    if (!Array.isArray(rawRows) || rawRows.length < 3 || rawRows.length > 6) {
        return failure('键盘结构必须包含 3～6 行');
    }
    const seenIds = [];
    const rows = [];
    for (const rawRow of rawRows) {
        if (rawRow === null || typeof rawRow !== 'object' || Array.isArray(rawRow)) {
            return failure('键盘行必须是对象');
        }
        const rowRecord = rawRow;
        const rawKeys = rowRecord['keys'];
        if (!Array.isArray(rawKeys) || rawKeys.length <= 0 || rawKeys.length > 12) {
            return failure('每行必须包含 1～12 个按键');
        }
        const kind = parseRowKind(rowRecord['kind']);
        if (rowRecord['kind'] !== undefined && kind === undefined) {
            return failure('存在不支持的行类型');
        }
        const keys = [];
        for (const rawKey of rawKeys) {
            if (rawKey === null || typeof rawKey !== 'object' || Array.isArray(rawKey)) {
                return failure('按键配置必须是对象');
            }
            const keyRecord = rawKey;
            const id = keyRecord['id'];
            if (typeof id !== 'string' || id.length <= 0 || id.length > 64 || seenIds.indexOf(id) >= 0) {
                return failure('按键 ID 为空、重复或过长');
            }
            if (ALLOWED_STRUCTURE_KEYS.indexOf(id) < 0) {
                return failure(`按键 ${id} 不受支持`);
            }
            const weightValue = keyRecord['weight'];
            if (weightValue !== undefined &&
                (typeof weightValue !== 'number' || !Number.isFinite(weightValue) || weightValue < 0.4 || weightValue > 8)) {
                return failure(`按键 ${id} 的 weight 必须在 0.4～8 之间`);
            }
            const labelValue = keyRecord['label'];
            if (labelValue !== undefined &&
                (typeof labelValue !== 'string' || labelValue.length <= 0 || labelValue.length > 8)) {
                return failure(`按键 ${id} 的 label 长度必须为 1～8 个字符`);
            }
            seenIds.push(id);
            const key = { id };
            if (typeof weightValue === 'number') {
                key.weight = weightValue;
            }
            if (typeof labelValue === 'string') {
                key.label = labelValue;
            }
            keys.push(key);
        }
        const row = { keys };
        if (kind !== undefined) {
            row.kind = kind;
        }
        rows.push(row);
    }
    const missing = REQUIRED_STRUCTURE_KEYS.filter((id) => seenIds.indexOf(id) < 0);
    if (missing.length > 0) {
        return failure(`键盘结构缺少必要按键：${missing.join(', ')}`);
    }
    const definition = {
        schemaVersion: exports.KEYBOARD_CUSTOMIZATION_SCHEMA_VERSION,
        id: record['id'],
        name: record['name'].trim(),
        rows
    };
    return success(definition);
}
exports.parseKeyboardStructureJson = parseKeyboardStructureJson;
function optionalColor(record, key) {
    const value = record[key];
    if (value === undefined) {
        return success(undefined);
    }
    if (typeof value !== 'string' || !COLOR_PATTERN.test(value)) {
        return failure(`${key} 必须是 #RRGGBB 或 #RRGGBBAA 颜色`);
    }
    return success(value);
}
function optionalAsset(record, key) {
    const value = record[key];
    if (value === undefined) {
        return success(undefined);
    }
    if (typeof value !== 'string' || !ASSET_PATTERN.test(value)) {
        return failure(`${key} 必须引用 assets 目录内的 PNG、JPG 或 WebP 图片`);
    }
    return success(value);
}
function assignColor(target, source, key) {
    const result = optionalColor(source, key);
    if (!result.success) {
        return failure(result.message);
    }
    const value = result.value;
    if (value !== undefined) {
        target[key] = value;
        return success(true);
    }
    return success(false);
}
function assignAsset(target, source, key) {
    const result = optionalAsset(source, key);
    if (!result.success) {
        return failure(result.message);
    }
    const value = result.value;
    if (value !== undefined) {
        target[key] = value;
        return success(true);
    }
    return success(false);
}
function parseKeyboardSkinJson(content) {
    let record;
    try {
        record = JSON.parse(content);
    }
    catch (_err) {
        return failure('skin.json 不是有效的 JSON');
    }
    if (record === null || typeof record !== 'object' || Array.isArray(record)) {
        return failure('skin.json 根节点必须是对象');
    }
    const identityError = validPackageIdentity(record);
    if (identityError.length > 0) {
        return failure(identityError);
    }
    const rawColors = record['colors'];
    const rawImages = record['images'];
    if (rawColors !== undefined &&
        (rawColors === null || typeof rawColors !== 'object' || Array.isArray(rawColors))) {
        return failure('colors 必须是对象');
    }
    if (rawImages !== undefined &&
        (rawImages === null || typeof rawImages !== 'object' || Array.isArray(rawImages))) {
        return failure('images 必须是对象');
    }
    const colorRecord = (rawColors ?? {});
    const imageRecord = (rawImages ?? {});
    const colors = {};
    const images = {};
    const colorKeys = [
        'panelBackground', 'candidateBackground', 'letterKeyBackground', 'functionKeyBackground',
        'spaceKeyBackground', 'primaryFunctionBackground', 'modeKeyBackgroundEnglish',
        'modeKeyBackgroundChinese', 'letterKeyPressedBackground', 'functionKeyPressedBackground',
        'primaryFunctionPressedBackground', 'letterKeyText', 'functionKeyText', 'primaryFunctionText',
        'modeKeyTextEnglish', 'modeKeyTextChinese', 'errorText', 'previewBackground', 'previewText',
        'previewShadow', 'candidateText', 'candidateReading', 'candidateDivider', 'keyBorder'
    ];
    const imageKeys = ['panelBackground', 'letterKey', 'functionKey', 'spaceKey', 'enterKey'];
    let customizationCount = 0;
    for (const key of colorKeys) {
        const result = assignColor(colors, colorRecord, key);
        if (!result.success) {
            return failure(result.message);
        }
        if (result.value === true) {
            customizationCount += 1;
        }
    }
    for (const key of imageKeys) {
        const result = assignAsset(images, imageRecord, key);
        if (!result.success) {
            return failure(result.message);
        }
        if (result.value === true) {
            customizationCount += 1;
        }
    }
    if (customizationCount <= 0) {
        return failure('皮肤至少需要配置一种颜色或图片');
    }
    const definition = {
        schemaVersion: exports.KEYBOARD_CUSTOMIZATION_SCHEMA_VERSION,
        id: record['id'],
        name: record['name'].trim(),
        colors,
        images
    };
    return success(definition);
}
exports.parseKeyboardSkinJson = parseKeyboardSkinJson;
var KeyboardCustomizationShortcut;
(function (KeyboardCustomizationShortcut) {
    KeyboardCustomizationShortcut["NONE"] = "none";
    KeyboardCustomizationShortcut["CYCLE_SKIN"] = "cycle-skin";
    KeyboardCustomizationShortcut["CYCLE_STRUCTURE"] = "cycle-structure";
})(KeyboardCustomizationShortcut = exports.KeyboardCustomizationShortcut || (exports.KeyboardCustomizationShortcut = {}));
/** Pure chord resolver used by the touch keyboard and unit tests. */
function resolveKeyboardCustomizationShortcut(pressedKeyIds) {
    const hasSpace = pressedKeyIds.indexOf('space') >= 0;
    if (hasSpace && pressedKeyIds.indexOf('number') >= 0) {
        return KeyboardCustomizationShortcut.CYCLE_SKIN;
    }
    if (hasSpace && (pressedKeyIds.indexOf('punctuation-period') >= 0 ||
        pressedKeyIds.indexOf('symbol') >= 0)) {
        return KeyboardCustomizationShortcut.CYCLE_STRUCTURE;
    }
    return KeyboardCustomizationShortcut.NONE;
}
exports.resolveKeyboardCustomizationShortcut = resolveKeyboardCustomizationShortcut;

return exports; })();
