import { describe, expect, it } from '@ohos/hypium';
import { UserLexiconDocumentEditor } from '../main/ets/application/UserLexiconController';
import {
  parseDirectControlCommand,
  resolveDirectControlHotkey
} from '../main/ets/domain/direct/DirectControlCommand';
import { UserLexiconEntryRecord } from '../main/ets/infrastructure/native/NativeEngineTypes';

function entry(id: string, text: string, code: string, order: number): UserLexiconEntryRecord {
  return { id, text, code, action: 'ADD', position: 0, sourceOrder: order };
}

export default function directControlUserLexiconTest() {
  describe('DirectControlUserLexicon', () => {
    it('parses only the closed direct command contract', 0, () => {
      expect(parseDirectControlCommand('scheme.set', 'xiaohe-yinxing').success).assertTrue();
      expect(parseDirectControlCommand('category.toggle', 'rare-character').success).assertTrue();
      expect(parseDirectControlCommand('category.toggle', 'unknown').success).assertFalse();
      expect(parseDirectControlCommand('category.all', 'unexpected').success).assertFalse();
      const categorySet = parseDirectControlCommand(
        'category.set',
        'core,one-key-secondary,rare-character'
      );
      expect(categorySet.success).assertTrue();
      expect(categorySet.command?.target).assertEqual('core,one-key-secondary,rare-character');
      expect(parseDirectControlCommand('category.set', 'core,unknown').success).assertFalse();
    });

    it('maps strict ctrl alt digit hotkeys and rejects loose modifiers', 0, () => {
      const command = resolveDirectControlHotkey(2002, true, true, false);
      expect(command?.action).assertEqual('scheme.set');
      expect(command?.target).assertEqual('xiaohe-yinxing');
      expect(resolveDirectControlHotkey(2002, true, false, false)).assertUndefined();
      expect(resolveDirectControlHotkey(2002, true, true, true)).assertUndefined();
    });

    it('serializes fixed and exact position actions without ambiguity', 0, () => {
      let entries: UserLexiconEntryRecord[] = [entry('a', '甲词', 'abcd', 0), entry('b', '乙词', 'efgh', 1)];
      entries = UserLexiconDocumentEditor.applyAction(entries, ['a'], 'FIXED', 0);
      entries = UserLexiconDocumentEditor.applyAction(entries, ['b'], 'POSITION', 3);
      expect(UserLexiconDocumentEditor.serialize(entries)).assertEqual('甲词\tabcd#固\n乙词\tefgh#3\n');
    });

    it('batch remove and upsert preserve deterministic source order', 0, () => {
      let entries: UserLexiconEntryRecord[] = [entry('a', '甲词', 'abcd', 0), entry('b', '乙词', 'efgh', 1)];
      entries = UserLexiconDocumentEditor.remove(entries, ['a']);
      entries = UserLexiconDocumentEditor.upsert(entries, '丙词', 'ijkl', 'DELETE', 0);
      expect(entries.length).assertEqual(2);
      expect(UserLexiconDocumentEditor.serialize(entries)).assertEqual('乙词\tefgh\n丙词\tijkl#删\n');
    });
  });
}
