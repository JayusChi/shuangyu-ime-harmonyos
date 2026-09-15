import { isExternalDirectTarget } from '../domain/direct/ExternalDirectTarget';
import { SHAPE_LOOKUP_TARGET, shapeLookupUrl } from '../domain/direct/ShapeLookup';
import { Want } from '@kit.AbilityKit';
import { Logger } from '../common/logging/Logger';
import { directWebWant } from './DirectWebWant';

const LOGGER = new Logger('DirectSessionAction');

export interface DirectAbilityLauncher {
  startAbility(want: Want): Promise<void>;
}

/** UI controllers share the launcher owned by the live input method ability. */
export class DirectAbilityLauncherRegistry {
  private launcher?: DirectAbilityLauncher;

  bind(launcher: DirectAbilityLauncher): void { this.launcher = launcher; }
  get(): DirectAbilityLauncher | undefined { return this.launcher; }
  unbind(launcher: DirectAbilityLauncher): void {
    // A retiring ability must not clear a replacement ability's context.
    if (this.launcher === launcher) { this.launcher = undefined; }
  }
}

const SHARED_DIRECT_ABILITY_LAUNCHERS = new DirectAbilityLauncherRegistry();

export function getSharedDirectAbilityLaunchers(): DirectAbilityLauncherRegistry {
  return SHARED_DIRECT_ABILITY_LAUNCHERS;
}

export interface DirectSessionActionResult {
  handled: boolean;
  success: boolean;
}

const FIXED_HTTPS_URLS: Record<string, string> = {
  'flypy-home': 'https://flypy.cc',
  'flypy-help': 'https://flypy.cc/help',
  'flypy-help-mobile': 'https://flypy.cc/help/#/sj'
};

export class DirectSessionActionService {
  private readonly contextProvider: () => DirectAbilityLauncher | undefined;

  constructor(
    contextProvider: () => DirectAbilityLauncher | undefined
  ) {
    this.contextProvider = contextProvider;
  }

  async execute(action: string, target: string, lookupCharacter: string = ''): Promise<DirectSessionActionResult> {
    if (action !== 'url.open' && action !== 'app.open' && action !== 'directory.open') {
      return { handled: false, success: false };
    }
    const context = this.contextProvider();
    if (context === undefined) {
      LOGGER.warn(`ability launch unavailable: action=${action}`);
      return { handled: true, success: false };
    }
    try {
      if (action === 'directory.open') {
        if (!isExternalDirectTarget(action, target)) {
          return { handled: true, success: false };
        }
        await context.startAbility({
          bundleName: 'com.corrosion.shuangyuime', abilityName: 'EntryAbility',
          parameters: { entryPage: 'pages/UserLexicon', openDirectoryUri: target }
        });
        return { handled: true, success: true };
      }
      if (action === 'url.open' && target === SHAPE_LOOKUP_TARGET) {
        const url = shapeLookupUrl(lookupCharacter);
        await context.startAbility(url !== undefined ? directWebWant(url) : {
          bundleName: 'com.corrosion.shuangyuime', abilityName: 'EntryAbility',
          parameters: { shapeLookupFromClipboard: true }
        });
        return { handled: true, success: true };
      }
      if (action === 'url.open') {
        const url = FIXED_HTTPS_URLS[target] ?? (isExternalDirectTarget(action, target) ? target : undefined);
        if (url === undefined) {
          return { handled: true, success: false };
        }
        await context.startAbility(directWebWant(url));
        return { handled: true, success: true };
      }
      if (target !== 'settings' && target !== 'user-lexicon') {
        return { handled: true, success: false };
      }
      await context.startAbility({
        bundleName: 'com.corrosion.shuangyuime',
        abilityName: 'EntryAbility',
        parameters: {
          entryPage: target === 'user-lexicon' ? 'pages/UserLexicon' : 'pages/Index'
        }
      });
      return { handled: true, success: true };
    } catch (err) {
      LOGGER.warn(`ability launch failed: action=${action}, error=${JSON.stringify(err)}`);
      return { handled: true, success: false };
    }
  }
}
