import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { dataShare } from '@kit.ArkData';
import { Logger } from '../../common/logging/Logger';

const LOGGER = new Logger('UserLexiconSyncBus');
const BUNDLE_NAME = 'com.corrosion.shuangyuime';
const USER_LEXICON_CHANGED_EVENT = `${BUNDLE_NAME}.event.USER_LEXICON_CHANGED`;
const USER_LEXICON_MANIFEST_URI = `datashareproxy://${BUNDLE_NAME}/user_lexicon/manifest`;
const SHARED_CONFIG: dataShare.DataProxyConfig = { type: dataShare.DataProxyType.SHARED_CONFIG };
const CHUNK_CHARACTERS = 900;
const MAX_CHUNKS = 512;
const BATCH_SIZE = 32;

interface UserLexiconManifest {
  version: string;
  chunkCount: number;
}

export class UserLexiconSyncBus {
  private subscriber?: commonEventManager.CommonEventSubscriber;
  private publishSequence: number = 0;

  async publish(content: string): Promise<boolean> {
    const stored = await this.publishSnapshot(content);
    if (!stored) {
      return false;
    }
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      commonEventManager.publish(
        USER_LEXICON_CHANGED_EVENT,
        { bundleName: BUNDLE_NAME },
        (err: BusinessError): void => resolve(!err)
      );
    });
  }

  async readSnapshot(): Promise<string | undefined> {
    try {
      const handle = await dataShare.createDataProxyHandle();
      const manifest = await this.readManifest(handle);
      if (!manifest) {
        return undefined;
      }
      const chunks: string[] = [];
      for (let offset = 0; offset < manifest.chunkCount; offset += BATCH_SIZE) {
        const limit = Math.min(offset + BATCH_SIZE, manifest.chunkCount);
        const uris: string[] = [];
        for (let index = offset; index < limit; index += 1) {
          uris.push(this.chunkUri(manifest.version, index));
        }
        const results = await handle.get(uris, SHARED_CONFIG);
        if (results.length !== uris.length) {
          return undefined;
        }
        for (let index = 0; index < results.length; index += 1) {
          if (results[index].result !== dataShare.DataProxyErrorCode.SUCCESS ||
            typeof results[index].value !== 'string') {
            return undefined;
          }
          chunks.push(results[index].value as string);
        }
      }
      return chunks.join('');
    } catch (err) {
      LOGGER.warn(`user lexicon shared snapshot read failed: ${JSON.stringify(err)}`);
      return undefined;
    }
  }

  async subscribe(listener: () => void): Promise<boolean> {
    try {
      if (this.subscriber) {
        return true;
      }
      const subscriber = await commonEventManager.createSubscriber({
        events: [USER_LEXICON_CHANGED_EVENT],
        publisherBundleName: BUNDLE_NAME
      });
      commonEventManager.subscribe(
        subscriber,
        (err: BusinessError, data: commonEventManager.CommonEventData): void => {
          if (!err && data.event === USER_LEXICON_CHANGED_EVENT) {
            listener();
          }
        }
      );
      this.subscriber = subscriber;
      return true;
    } catch (err) {
      LOGGER.warn(`user lexicon subscribe failed: ${JSON.stringify(err)}`);
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
      commonEventManager.unsubscribe(subscriber);
    } catch (err) {
      LOGGER.warn(`user lexicon unsubscribe failed: ${JSON.stringify(err)}`);
    }
  }

  private async publishSnapshot(content: string): Promise<boolean> {
    try {
      const chunks = this.splitContent(content);
      if (chunks.length > MAX_CHUNKS) {
        LOGGER.warn(`user lexicon shared snapshot is too large: chunks=${chunks.length}`);
        return false;
      }
      const handle = await dataShare.createDataProxyHandle();
      const previous = await this.readManifest(handle);
      this.publishSequence += 1;
      const version = `${Date.now()}-${this.publishSequence}`;
      for (let offset = 0; offset < chunks.length; offset += BATCH_SIZE) {
        const limit = Math.min(offset + BATCH_SIZE, chunks.length);
        const batch: dataShare.ProxyData[] = [];
        for (let index = offset; index < limit; index += 1) {
          batch.push({
            uri: this.chunkUri(version, index),
            value: chunks[index],
            allowList: []
          });
        }
        const results = await handle.publish(batch, SHARED_CONFIG);
        if (results.length !== batch.length ||
          results.some((result: dataShare.DataProxyResult): boolean =>
            result.result !== dataShare.DataProxyErrorCode.SUCCESS)) {
          LOGGER.warn('user lexicon shared chunk publish was rejected');
          return false;
        }
      }
      const manifest: UserLexiconManifest = { version, chunkCount: chunks.length };
      const manifestResults = await handle.publish([{
        uri: USER_LEXICON_MANIFEST_URI,
        value: JSON.stringify(manifest),
        allowList: []
      }], SHARED_CONFIG);
      if (manifestResults.length !== 1 ||
        manifestResults[0].result !== dataShare.DataProxyErrorCode.SUCCESS) {
        LOGGER.warn('user lexicon shared manifest publish was rejected');
        return false;
      }
      if (previous && previous.version !== version) {
        await this.deleteChunks(handle, previous);
      }
      return true;
    } catch (err) {
      LOGGER.warn(`user lexicon shared snapshot publish failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  private splitContent(content: string): string[] {
    const chunks: string[] = [];
    let start = 0;
    while (start < content.length) {
      let end = Math.min(start + CHUNK_CHARACTERS, content.length);
      if (end < content.length) {
        const tail = content.charCodeAt(end - 1);
        if (tail >= 0xD800 && tail <= 0xDBFF) {
          end -= 1;
        }
      }
      chunks.push(content.substring(start, end));
      start = end;
    }
    return chunks;
  }

  private async readManifest(
    handle: dataShare.DataProxyHandle
  ): Promise<UserLexiconManifest | undefined> {
    try {
      const results = await handle.get([USER_LEXICON_MANIFEST_URI], SHARED_CONFIG);
      if (results.length !== 1 || results[0].result !== dataShare.DataProxyErrorCode.SUCCESS ||
        typeof results[0].value !== 'string') {
        return undefined;
      }
      const manifest = JSON.parse(results[0].value) as UserLexiconManifest;
      if (typeof manifest.version !== 'string' || manifest.version.length <= 0 ||
        !Number.isInteger(manifest.chunkCount) || manifest.chunkCount < 0 ||
        manifest.chunkCount > MAX_CHUNKS) {
        LOGGER.warn('user lexicon shared manifest is invalid');
        return undefined;
      }
      return manifest;
    } catch (err) {
      LOGGER.warn(`user lexicon shared manifest read failed: ${JSON.stringify(err)}`);
      return undefined;
    }
  }

  private async deleteChunks(
    handle: dataShare.DataProxyHandle,
    manifest: UserLexiconManifest
  ): Promise<void> {
    for (let offset = 0; offset < manifest.chunkCount; offset += BATCH_SIZE) {
      const limit = Math.min(offset + BATCH_SIZE, manifest.chunkCount);
      const uris: string[] = [];
      for (let index = offset; index < limit; index += 1) {
        uris.push(this.chunkUri(manifest.version, index));
      }
      try {
        const results = await handle.delete(uris, SHARED_CONFIG);
        if (results.length !== uris.length ||
          results.some((result: dataShare.DataProxyResult): boolean =>
            result.result !== dataShare.DataProxyErrorCode.SUCCESS)) {
          LOGGER.warn('stale user lexicon shared chunks were not fully deleted');
        }
      } catch (err) {
        LOGGER.warn(`stale user lexicon shared chunk cleanup failed: ${JSON.stringify(err)}`);
      }
    }
  }

  private chunkUri(version: string, index: number): string {
    return `datashareproxy://${BUNDLE_NAME}/user_lexicon/${version}/${index}`;
  }
}
