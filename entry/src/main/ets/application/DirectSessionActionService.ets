import { InputMethodExtensionContext } from '@kit.IMEKit';
import { ImeInputService } from './ImeInputService';

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
  private readonly contextProvider: () => InputMethodExtensionContext | undefined;
  private readonly imeService: ImeInputService;

  constructor(
    contextProvider: () => InputMethodExtensionContext | undefined,
    imeService: ImeInputService
  ) {
    this.contextProvider = contextProvider;
    this.imeService = imeService;
  }

  async execute(action: string, target: string): Promise<DirectSessionActionResult> {
    if (action === 'editor.delete-line') {
      if (target.length > 0 || this.imeService.deleteCurrentLine === undefined) {
        return { handled: true, success: false };
      }
      return { handled: true, success: await this.imeService.deleteCurrentLine() };
    }
    if (action !== 'url.open' && action !== 'app.open') {
      return { handled: false, success: false };
    }
    const context = this.contextProvider();
    if (context === undefined) {
      return { handled: true, success: false };
    }
    try {
      if (action === 'url.open') {
        const url = FIXED_HTTPS_URLS[target];
        if (url === undefined) {
          return { handled: true, success: false };
        }
        await context.startAbility({
          action: 'ohos.want.action.viewData',
          uri: url
        });
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
    } catch (_err) {
      return { handled: true, success: false };
    }
  }
}
