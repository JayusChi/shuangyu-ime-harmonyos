import {
  isAvailableScheme,
  XIAOHE_YINXING_CATEGORY_IDS
} from '../settings/ImeSettings';

export interface DirectControlCommand {
  action: string;
  target: string;
}

export interface DirectControlParseResult {
  success: boolean;
  message: string;
  command?: DirectControlCommand;
}

const CATEGORY_ACTIONS: string[] = [
  'category.enable',
  'category.disable',
  'category.toggle'
];

export function parseDirectControlCommand(action: string, target: string): DirectControlParseResult {
  const normalizedAction = action.trim().toLowerCase();
  const normalizedTarget = target.trim().toLowerCase();
  if (normalizedAction === 'scheme.set') {
    if (!isAvailableScheme(normalizedTarget)) {
      return { success: false, message: '方案标识无效' };
    }
    return { success: true, message: '', command: { action: normalizedAction, target: normalizedTarget } };
  }
  if (CATEGORY_ACTIONS.indexOf(normalizedAction) >= 0) {
    if (XIAOHE_YINXING_CATEGORY_IDS.indexOf(normalizedTarget) < 0) {
      return { success: false, message: '分类标识无效' };
    }
    return { success: true, message: '', command: { action: normalizedAction, target: normalizedTarget } };
  }
  if (normalizedAction === 'category.set') {
    const ids = normalizedTarget.length === 0 ? [] : normalizedTarget.split(',')
      .map((id: string): string => id.trim())
      .filter((id: string): boolean => id.length > 0);
    if (ids.some((id: string): boolean => XIAOHE_YINXING_CATEGORY_IDS.indexOf(id) < 0)) {
      return { success: false, message: '分类列表包含无效标识' };
    }
    return { success: true, message: '', command: { action: normalizedAction, target: ids.join(',') } };
  }
  if (normalizedAction === 'category.preset') {
    if (normalizedTarget !== 'experienced' && normalizedTarget !== 'standard' &&
      normalizedTarget !== 'beginner') {
      return { success: false, message: '分类预设无效' };
    }
    return { success: true, message: '', command: { action: normalizedAction, target: normalizedTarget } };
  }
  if (normalizedAction === 'settings.smart-period') {
    if (normalizedTarget !== '0' && normalizedTarget !== '600') {
      return { success: false, message: '智能标点参数无效' };
    }
    return { success: true, message: '', command: { action: normalizedAction, target: normalizedTarget } };
  }
  if (normalizedAction === 'settings.punctuation' || normalizedAction === 'settings.fullwidth' ||
    normalizedAction === 'settings.traditional') {
    if (normalizedTarget !== 'toggle') {
      return { success: false, message: '设置切换参数无效' };
    }
    return { success: true, message: '', command: { action: normalizedAction, target: normalizedTarget } };
  }
  if (normalizedAction === 'settings.numeric-period') {
    if (normalizedTarget !== 'enabled' && normalizedTarget !== 'disabled') {
      return { success: false, message: '数字标点参数无效' };
    }
    return { success: true, message: '', command: { action: normalizedAction, target: normalizedTarget } };
  }
  if (normalizedAction === 'settings.empty-clear') {
    if (normalizedTarget !== '4' && normalizedTarget !== '12') {
      return { success: false, message: '清码阈值无效' };
    }
    return { success: true, message: '', command: { action: normalizedAction, target: normalizedTarget } };
  }
  if (normalizedAction === 'settings.commit-policy') {
    if (normalizedTarget !== 'top-screen' && normalizedTarget !== 'auto-commit') {
      return { success: false, message: '顶屏策略无效' };
    }
    return { success: true, message: '', command: { action: normalizedAction, target: normalizedTarget } };
  }
  if (normalizedAction === 'category.all' || normalizedAction === 'category.core' ||
    normalizedAction === 'status.get') {
    if (normalizedTarget.length > 0) {
      return { success: false, message: '该命令不接受目标参数' };
    }
    return { success: true, message: '', command: { action: normalizedAction, target: '' } };
  }
  return { success: false, message: '直通命令无效' };
}

export function resolveDirectControlHotkey(
  keyCode: number,
  ctrlKey: boolean,
  altKey: boolean,
  logoKey: boolean
): DirectControlCommand | undefined {
  if (!ctrlKey || !altKey || logoKey || keyCode < 2000 || keyCode > 2009) {
    return undefined;
  }
  const commands: DirectControlCommand[] = [
    { action: 'category.toggle', target: 'out-of-table-character' },
    { action: 'scheme.set', target: 'xiaohe' },
    { action: 'scheme.set', target: 'xiaohe-yinxing' },
    { action: 'category.core', target: '' },
    { action: 'category.all', target: '' },
    { action: 'category.toggle', target: 'category-secondary' },
    { action: 'category.toggle', target: 'one-key-secondary' },
    { action: 'category.toggle', target: 'two-key-secondary' },
    { action: 'category.toggle', target: 'rare-character' },
    { action: 'category.toggle', target: 'full-code-word' }
  ];
  return commands[keyCode - 2000];
}
