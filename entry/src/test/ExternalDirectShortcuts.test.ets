import { describe, expect, it } from '@ohos/hypium';
import { Want } from '@kit.AbilityKit';
import { DirectAbilityLauncher, DirectAbilityLauncherRegistry, DirectSessionActionService } from '../main/ets/application/DirectSessionActionService';
import { UserLexiconDocumentEditor } from '../main/ets/application/UserLexiconController';
import { ShapeLookupService } from '../main/ets/application/ShapeLookupService';
import { ShapeLookupClipboardReader } from '../main/ets/infrastructure/clipboard/ShapeLookupClipboard';
import { shapeLookupUrl } from '../main/ets/domain/direct/ShapeLookup';
import { isExternalDirectTarget } from '../main/ets/domain/direct/ExternalDirectTarget';
import { isFlypyWebTarget } from '../main/ets/domain/direct/FlypyWebTarget';
import { directWebWant } from '../main/ets/application/DirectWebWant';

class LookupClipboard implements ShapeLookupClipboardReader {
  text: string | undefined = '鹤';
  reads: number = 0;
  async readText(): Promise<string | undefined> { this.reads += 1; return this.text; }
}

class ShortcutLauncher implements DirectAbilityLauncher {
  wants: Want[] = [];
  fail: boolean = false;
  async startAbility(want: Want): Promise<void> {
    if (this.fail) { throw new Error('launch rejected'); }
    this.wants.push(want);
  }
}

export default function externalDirectShortcutsTest() {
  describe('ExternalDirectShortcuts', () => {
    it('loads only the exact official HTTPS origin in the private web ability', 0, () => {
      for (const url of ['https://flypy.cc', 'https://flypy.cc/help/#/sj', 'https://flypy.cc/ix/?q=%F0%A0%AE%B7']) {
        expect(isFlypyWebTarget(url)).assertTrue();
        expect(directWebWant(url).abilityName).assertEqual('FlypyWebAbility');
        expect(directWebWant(url).uri).assertEqual(url);
      }
      for (const url of ['http://flypy.cc', 'https://flypy.cc.evil.test/', 'https://flypy.cc@evil.test/',
        'https://evil.test/?flypy.cc', 'file:///data/private', 'javascript:alert(1)', 'https://flypy.cc/\n']) {
        expect(isFlypyWebTarget(url)).assertFalse();
        expect(directWebWant(url).abilityName).assertUndefined();
      }
    });
    it('releases the retired launcher without clearing a replacement ability', 0, async () => {
      const registry = new DirectAbilityLauncherRegistry();
      const first = new ShortcutLauncher();
      const replacement = new ShortcutLauncher();
      const service = new DirectSessionActionService(() => registry.get());
      expect((await service.execute('url.open', 'flypy-home')).success).assertFalse();
      registry.bind(first);
      expect((await service.execute('url.open', 'flypy-home')).success).assertTrue();
      registry.bind(replacement);
      registry.unbind(first);
      expect((await service.execute('url.open', 'flypy-shape', '你')).success).assertTrue();
      expect(first.wants.length).assertEqual(1);
      expect(replacement.wants.length).assertEqual(1);
      registry.unbind(replacement);
      expect((await service.execute('url.open', 'flypy-home')).success).assertFalse();
      expect(replacement.wants.length).assertEqual(1);
    });
    it('oix prefers the committed cursor character and falls back to a copied complete Unicode character', 0, async () => {
      const clipboard = new LookupClipboard();
      const lookup = new ShapeLookupService(clipboard);
      expect(await lookup.resolve('输入你oix', 'oix', true)).assertEqual('你');
      expect(clipboard.reads).assertEqual(0);
      expect(await lookup.resolve('oix', 'oix', true)).assertEqual('鹤');
      expect(await lookup.resolve('', 'oix', false)).assertEqual('鹤');
      clipboard.text = '𠮷';
      expect(await lookup.resolve('', '', false)).assertEqual('𠮷');
      expect(shapeLookupUrl('𠮷')).assertEqual('https://flypy.cc/ix/?q=%F0%A0%AE%B7');
      expect(shapeLookupUrl('你好')).assertUndefined();
      expect(shapeLookupUrl('oix')).assertUndefined();
    });

    it('oix clipboard lookup reads only after a successful system paste click', 0, async () => {
      const clipboard = new LookupClipboard();
      clipboard.text = undefined;
      const lookup = new ShapeLookupService(clipboard);
      const launcher = new ShortcutLauncher();
      expect(await lookup.openClipboard(launcher, false)).assertFalse();
      expect(clipboard.reads).assertEqual(0);
      expect(launcher.wants.length).assertEqual(0);
      expect(await lookup.openClipboard(launcher, true)).assertFalse();
      expect(clipboard.reads).assertEqual(1);
      expect(launcher.wants.length).assertEqual(0);
      clipboard.text = '鹤';
      expect(await lookup.openClipboard(launcher, true)).assertTrue();
      expect(launcher.wants[0].uri).assertEqual('https://flypy.cc/ix/?q=%E9%B9%A4');
      expect(launcher.wants[0].abilityName).assertEqual('FlypyWebAbility');
      clipboard.text = '';
      expect(await lookup.openClipboard(launcher, true)).assertFalse();
      expect(launcher.wants.length).assertEqual(1);
    });

    it('oix launches the captured character or the foreground clipboard flow without leaking its label', 0, async () => {
      const launcher = new ShortcutLauncher();
      const service = new DirectSessionActionService((): DirectAbilityLauncher => launcher);
      expect((await service.execute('url.open', 'flypy-shape', '你')).success).assertTrue();
      expect(launcher.wants[0].uri).assertEqual('https://flypy.cc/ix/?q=%E4%BD%A0');
      expect(launcher.wants[0].abilityName).assertEqual('FlypyWebAbility');
      expect((await service.execute('url.open', 'flypy-shape')).success).assertTrue();
      expect(launcher.wants[1].parameters?.['shapeLookupFromClipboard']).assertTrue();
      expect(launcher.wants[1].abilityName).assertEqual('EntryAbility');
    });

    it('preserves URL paths queries commas and fragments through export and launch', 0, async () => {
      const url = 'https://example.com/Help?q=a,b#Part';
      const entries = UserLexiconDocumentEditor.upsert([], url, 'zzweb', 'OPEN_URL', 0, '帮助');
      expect(UserLexiconDocumentEditor.serialize(entries)).assertEqual(url + '\tzzweb#网页\t帮助\n');
      const launcher = new ShortcutLauncher();
      const service = new DirectSessionActionService((): DirectAbilityLauncher => launcher);
      expect((await service.execute('url.open', url)).success).assertTrue();
      expect(launcher.wants.length).assertEqual(1);
      expect(launcher.wants[0].uri).assertEqual(url);
      expect(launcher.wants[0].action).assertEqual('ohos.want.action.viewData');
    });
    it('routes saved directories to the foreground ability with the exact document URI', 0, async () => {
      const uri = 'file://docs/storage/Users/currentUser/文档,资料';
      const entries = UserLexiconDocumentEditor.upsert([], uri, 'zzdir', 'OPEN_DIRECTORY', 0, '文档');
      expect(UserLexiconDocumentEditor.serialize(entries)).assertEqual(uri + '\tzzdir#目录\t文档\n');
      const launcher = new ShortcutLauncher();
      const service = new DirectSessionActionService((): DirectAbilityLauncher => launcher);
      expect((await service.execute('directory.open', uri)).success).assertTrue();
      expect(launcher.wants[0].abilityName).assertEqual('EntryAbility');
      expect(launcher.wants[0].parameters?.['openDirectoryUri']).assertEqual(uri);
    });
    it('rejects invalid targets without launching and reports launcher failures', 0, async () => {
      const launcher = new ShortcutLauncher();
      const service = new DirectSessionActionService((): DirectAbilityLauncher => launcher);
      for (const target of ['javascript:alert(1)', 'https://', 'https://u:p@example.com', 'https://example.com/a b']) {
        expect((await service.execute('url.open', target)).success).assertFalse();
      }
      expect((await service.execute('directory.open', 'file://other.app/private')).success).assertFalse();
      expect(launcher.wants.length).assertEqual(0);
      launcher.fail = true;
      expect((await service.execute('url.open', 'https://example.com')).success).assertFalse();
      expect((await new DirectSessionActionService(() => undefined).execute('url.open', 'https://example.com')).success)
        .assertFalse();
      expect(isExternalDirectTarget('directory.open', 'file://docs/')).assertFalse();
      expect(isExternalDirectTarget('url.open', 'https://example.com/\n')).assertFalse();
    });
    it('keeps existing fixed URLs and text direct entries working', 0, async () => {
      const launcher = new ShortcutLauncher();
      const service = new DirectSessionActionService((): DirectAbilityLauncher => launcher);
      expect((await service.execute('url.open', 'flypy-home')).success).assertTrue();
      expect(launcher.wants[0].uri).assertEqual('https://flypy.cc');
      const entries = UserLexiconDocumentEditor.upsert([], '给予', 'gwyu', 'DIRECT', 0, '提示');
      expect(UserLexiconDocumentEditor.serialize(entries)).assertEqual('给予,提示\tgwyu#直\n');
    });
  });
}
