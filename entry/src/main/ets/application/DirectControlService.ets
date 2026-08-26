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

export function resolveCategoryPresetIds(current: string[], target: string): string[] {
  const mutableIds: string[] = ['full-code-word', 'full-code-character', 'rare-character'];
  const enabled = current.filter((id: string): boolean => mutableIds.indexOf(id) < 0);
  if (target === 'standard' || target === 'beginner') {
    enabled.push('full-code-word');
  }
  if (target === 'beginner') {
    enabled.push('full-code-character');
    enabled.push('rare-character');
  }
  return enabled;
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
    if (command.action === 'category.preset') {
      return this.applyCategoryPreset(command.target);
    }
    if (command.action === 'settings.smart-period') {
      return this.settings.setSmartPeriodTimeoutMs(Number(command.target));
    }
    if (command.action === 'settings.punctuation') {
      return this.settings.togglePunctuationMode();
    }
    if (command.action === 'settings.fullwidth') {
      return this.settings.toggleFullWidthEnabled();
    }
    if (command.action === 'settings.traditional') {
      return this.settings.toggleTraditionalOutputEnabled();
    }
    if (command.action === 'settings.numeric-period') {
      return this.settings.setNumericPeriodEnabled(command.target === 'enabled');
    }
    if (command.action === 'settings.empty-clear') {
      const current = this.settings.getSettings();
      return this.settings.setCodeTableCommitPolicy(
        current.codeTableAutoCommitEnabled,
        Number(command.target)
      );
    }
    if (command.action === 'settings.commit-policy') {
      const current = this.settings.getSettings();
      return this.settings.setCodeTableCommitPolicy(
        command.target === 'auto-commit',
        current.codeTableEmptyClearLength
      );
    }
    return this.applyCategoryCommand(command);
  }

  private applyCategoryPreset(target: string): Promise<SettingsOperationResult> {
    const enabled = resolveCategoryPresetIds(
      this.settings.getSettings().xiaoheYinxingEnabledCategoryIds,
      target
    );
    return this.settings.setXiaoheYinxingEnabledCategoryIds(enabled);
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
