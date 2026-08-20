import common from '@ohos.app.ability.common';

export const USER_MODEL_FILE_NAME = 'user_model.dat';

export interface UserModelPathResult {
  success: boolean;
  path: string;
  errorMessage: string;
}

export class UserModelPathProvider {
  getUserModelPath(context: common.Context): UserModelPathResult {
    if (context.filesDir.length <= 0) {
      return {
        success: false,
        path: '',
        errorMessage: 'filesDir is empty'
      };
    }
    return {
      success: true,
      path: `${context.filesDir}/${USER_MODEL_FILE_NAME}`,
      errorMessage: ''
    };
  }
}
