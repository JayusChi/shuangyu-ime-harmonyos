import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { ImeSettings, SettingsRaw, settingsToRaw } from '../../domain/settings/ImeSettings';
import { Logger } from '../../common/logging/Logger';

const LOGGER = new Logger('SettingsSyncBus');
const BUNDLE_NAME = 'com.corrosion.shuangyuime';
const SETTINGS_CHANGED_EVENT = `${BUNDLE_NAME}.event.SETTINGS_CHANGED`;

export class SettingsSyncBus {
  private subscriber?: commonEventManager.CommonEventSubscriber;

  async publish(settings: ImeSettings): Promise<boolean> {
    const data = JSON.stringify(settingsToRaw(settings));
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      commonEventManager.publish(
        SETTINGS_CHANGED_EVENT,
        { bundleName: BUNDLE_NAME, data: data },
        (err: BusinessError): void => {
          if (err) {
            LOGGER.warn(`settings event publish failed: ${err.code}`);
            resolve(false);
            return;
          }
          LOGGER.info('settings event published');
          resolve(true);
        }
      );
    });
  }

  async subscribe(listener: (raw: SettingsRaw) => void): Promise<boolean> {
    try {
      if (this.subscriber) {
        return true;
      }
      const subscriber = await commonEventManager.createSubscriber({
        events: [SETTINGS_CHANGED_EVENT],
        publisherBundleName: BUNDLE_NAME
      });
      commonEventManager.subscribe(
        subscriber,
        (err: BusinessError, eventData: commonEventManager.CommonEventData): void => {
          if (err) {
            LOGGER.warn(`settings event receive failed: ${err.code}`);
            return;
          }
          if (eventData.event !== SETTINGS_CHANGED_EVENT || !eventData.data) {
            return;
          }
          try {
            listener(JSON.parse(eventData.data) as SettingsRaw);
          } catch (parseError) {
            LOGGER.warn(`settings event parse failed: ${JSON.stringify(parseError)}`);
          }
        }
      );
      this.subscriber = subscriber;
      LOGGER.info('settings event subscribed');
      return true;
    } catch (err) {
      LOGGER.warn(`settings event subscribe failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  unsubscribe(): void {
    const subscriber = this.subscriber;
    this.subscriber = undefined;
    if (!subscriber) {
      return;
    }
    try {
      commonEventManager.unsubscribe(subscriber, (err?: BusinessError): void => {
        if (err) {
          LOGGER.warn(`settings event unsubscribe failed: ${err.code}`);
        }
      });
    } catch (err) {
      LOGGER.warn(`settings event unsubscribe failed: ${JSON.stringify(err)}`);
    }
  }
}
