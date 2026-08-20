import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';

const BUNDLE_NAME = 'com.corrosion.shuangyuime';
const COMMAND_EVENT = `${BUNDLE_NAME}.event.DEBUG_STAGE1167_COMMAND`;

export type Stage1167DeviceCommand = 'ALL_CATEGORIES' | 'CORE_ONLY' | 'XIAOHE';

export class Stage1167DeviceCommandBus {
  private subscriber?: commonEventManager.CommonEventSubscriber;

  async publish(command: Stage1167DeviceCommand): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      commonEventManager.publish(
        COMMAND_EVENT,
        { bundleName: BUNDLE_NAME, data: command },
        (err: BusinessError): void => resolve(!err)
      );
    });
  }

  async subscribe(listener: (command: Stage1167DeviceCommand) => void): Promise<boolean> {
    try {
      if (this.subscriber) {
        return true;
      }
      const subscriber = await commonEventManager.createSubscriber({
        events: [COMMAND_EVENT]
      });
      commonEventManager.subscribe(
        subscriber,
        (err: BusinessError, data: commonEventManager.CommonEventData): void => {
          if (err || data.event !== COMMAND_EVENT) {
            return;
          }
          const command = data.data as Stage1167DeviceCommand;
          if (command === 'ALL_CATEGORIES' || command === 'CORE_ONLY' || command === 'XIAOHE') {
            listener(command);
          }
        }
      );
      this.subscriber = subscriber;
      return true;
    } catch (err) {
      return false;
    }
  }

  unsubscribe(): void {
    const subscriber = this.subscriber;
    this.subscriber = undefined;
    if (subscriber) {
      commonEventManager.unsubscribe(subscriber);
    }
  }
}
