import common from '@ohos.app.ability.common';
import { describe, expect, it } from '@ohos/hypium';
import {
  USER_LEXICON_FILE_NAME,
  UserLexiconPathProvider
} from '../main/ets/infrastructure/storage/UserLexiconPathProvider';

export default function userLexiconPathProviderTest() {
  describe('userLexiconPathProvider', () => {
    it('usesOptionalSandboxFileWithoutCreatingIt', 0, () => {
      const provider = new UserLexiconPathProvider();
      const result = provider.getUserLexiconPath({ filesDir: '/data/storage/el2/base/files' } as common.Context);
      expect(result.success).assertTrue();
      expect(result.path).assertEqual(`/data/storage/el2/base/files/${USER_LEXICON_FILE_NAME}`);
    });

    it('rejectsEmptyFilesDirectory', 0, () => {
      const provider = new UserLexiconPathProvider();
      const result = provider.getUserLexiconPath({ filesDir: '' } as common.Context);
      expect(result.success).assertFalse();
      expect(result.path).assertEqual('');
    });
  });
}
