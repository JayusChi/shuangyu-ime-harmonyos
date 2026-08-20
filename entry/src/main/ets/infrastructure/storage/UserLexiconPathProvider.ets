import common from '@ohos.app.ability.common';

export const USER_LEXICON_FILE_NAME = 'user_lexicon.txt';

export interface UserLexiconPathResult {
  success: boolean;
  path: string;
  errorMessage: string;
}

/** Supplies the optional sandbox path; Rust treats a missing file as an empty overlay. */
export class UserLexiconPathProvider {
  getUserLexiconPath(context: common.Context): UserLexiconPathResult {
    if (context.filesDir.length <= 0) {
      return {
        success: false,
        path: '',
        errorMessage: 'filesDir is empty'
      };
    }
    return {
      success: true,
      path: `${context.filesDir}/${USER_LEXICON_FILE_NAME}`,
      errorMessage: ''
    };
  }
}
