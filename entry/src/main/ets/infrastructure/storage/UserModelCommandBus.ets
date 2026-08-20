import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { Logger } from '../../common/logging/Logger';

const LOGGER = new Logger('UserModelCommandBus');
const BUNDLE_NAME = 'com.corrosion.shuangyuime';
const CLEAR_EVENT = `${BUNDLE_NAME}.event.CLEAR_USER_MODEL`;

export class UserModelCommandBus {
  private subscriber?: commonEventManager.CommonEventSubscriber;

  async publishClear(): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      commonEventManager.publish(CLEAR_EVENT, { bundleName: BUNDLE_NAME }, (err: BusinessError): void => {
        if (err) {
          LOGGER.warn(`clear event publish failed: ${err.code}`);
          resolve(false);
          return;
        }
        LOGGER.info('clear event published');
        resolve(true);
      });
    });
  }

  async subscribeClear(listener: () => void): Promise<boolean> {
    try {
      if (this.subscriber) {
        return true;
      }
      const subscriber = await commonEventManager.createSubscriber({
        events: [CLEAR_EVENT],
        publisherBundleName: BUNDLE_NAME
      });
      commonEventManager.subscribe(
        subscriber,
        (err: BusinessError, data: commonEventManager.CommonEventData): void => {
          if (err) {
            LOGGER.warn(`clear event receive failed: ${err.code}`);
            return;
          }
          if (data.event === CLEAR_EVENT) {
            listener();
          }
        }
      );
      this.subscriber = subscriber;
      LOGGER.info('clear event subscribed');
      return true;
    } catch (err) {
      LOGGER.warn(`clear event subscribe failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  unsubscribeClear(): void {
    const subscriber = this.subscriber;
    this.subscriber = undefined;
    if (!subscriber) {
      return;
    }
    try {
      commonEventManager.unsubscribe(subscriber, (err?: BusinessError): void => {
        if (err) {
          LOGGER.warn(`clear event unsubscribe failed: ${err.code}`);
        }
      });
    } catch (err) {
      LOGGER.warn(`clear event unsubscribe failed: ${JSON.stringify(err)}`);
    }
  }
}
