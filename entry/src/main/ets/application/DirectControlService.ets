import {
  DirectControlCommand,
  parseDirectControlCommand
} from '../domain/direct/DirectControlCommand';
import { XIAOHE_YINXING_CATEGORY_IDS } from '../domain/settings/ImeSettings';
import {
  getSharedSettingsController,
  SettingsController,
  SettingsOperationResult
} from './SettingsController';

export interface DirectControlResult {
  success: boolean;
  message: string;
}

export class DirectControlService {
  private readonly settings: SettingsController;

  constructor(settings: SettingsController = getSharedSettingsController()) {
    this.settings = settings;
  }

  executeRaw(action: string, target: string = ''): Promise<DirectControlResult> {
    const parsed = parseDirectControlCommand(action, target);
    if (!parsed.success || parsed.command === undefined) {
      const failure: DirectControlResult = { success: false, message: parsed.message };
      return Promise.resolve(failure);
    }
    return this.execute(parsed.command);
  }

  async execute(command: DirectControlCommand): Promise<DirectControlResult> {
    if (command.action === 'status.get') {
      const snapshot = this.settings.getSettings();
      return {
        success: true,
        message: `scheme=${snapshot.schemeId};categories=${snapshot.xiaoheYinxingEnabledCategoryIds.join(',')}`
      };
    }
    if (command.action === 'scheme.set') {
      return this.settings.changeScheme(command.target);
    }
    if (command.action === 'category.all') {
      return this.settings.setXiaoheYinxingEnabledCategoryIds(XIAOHE_YINXING_CATEGORY_IDS.slice());
    }
    if (command.action === 'category.core') {
      return this.settings.setXiaoheYinxingEnabledCategoryIds(['core']);
    }
    if (command.action === 'category.set') {
      const ids = command.target.length === 0 ? [] : command.target.split(',');
      return this.settings.setXiaoheYinxingEnabledCategoryIds(ids);
    }
    return this.applyCategoryCommand(command);
  }

  private applyCategoryCommand(command: DirectControlCommand): Promise<SettingsOperationResult> {
    const snapshot = this.settings.getSettings();
    const ids = snapshot.xiaoheYinxingEnabledCategoryIds.slice();
    const index = ids.indexOf(command.target);
    if (command.target === 'core' && command.action !== 'category.enable') {
      const failure: SettingsOperationResult = { success: false, message: '核心码表不能禁用' };
      return Promise.resolve(failure);
    }
    if (command.action === 'category.enable' && index < 0) {
      ids.push(command.target);
    } else if (command.action === 'category.disable' && index >= 0) {
      ids.splice(index, 1);
    } else if (command.action === 'category.toggle') {
      if (index >= 0) {
        ids.splice(index, 1);
      } else {
        ids.push(command.target);
      }
    }
    return this.settings.setXiaoheYinxingEnabledCategoryIds(ids);
  }
}

const SHARED_DIRECT_CONTROL_SERVICE = new DirectControlService();

export function getSharedDirectControlService(): DirectControlService {
  return SHARED_DIRECT_CONTROL_SERVICE;
}
