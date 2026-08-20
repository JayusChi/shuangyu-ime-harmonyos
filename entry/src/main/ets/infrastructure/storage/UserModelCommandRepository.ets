import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { Logger } from '../../common/logging/Logger';

const LOGGER = new Logger('UserModelCommand');
const COMMAND_PREFERENCES_NAME = 'ime_settings_commands';
const CLEAR_REQUESTED_KEY = 'user_model_clear_requested';

export class UserModelCommandRepository {
  async requestClear(context: common.Context): Promise<boolean> {
    try {
      const storage = await preferences.getPreferences(context, { name: COMMAND_PREFERENCES_NAME });
      await storage.put(CLEAR_REQUESTED_KEY, true);
      await storage.flush();
      LOGGER.info('clear request persisted');
      return true;
    } catch (err) {
      LOGGER.warn(`clear request persist failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  async consumeClearRequest(context: common.Context): Promise<boolean> {
    try {
      preferences.removePreferencesFromCacheSync(context, { name: COMMAND_PREFERENCES_NAME });
      const storage = await preferences.getPreferences(context, { name: COMMAND_PREFERENCES_NAME });
      const requested = await storage.get(CLEAR_REQUESTED_KEY, false);
      if (requested !== true) {
        return false;
      }
      await storage.put(CLEAR_REQUESTED_KEY, false);
      await storage.flush();
      LOGGER.info('clear request consumed');
      return true;
    } catch (err) {
      LOGGER.warn(`clear request consume failed: ${JSON.stringify(err)}`);
      return false;
    }
  }
}
