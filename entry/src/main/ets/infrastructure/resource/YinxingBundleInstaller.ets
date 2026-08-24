import common from '@ohos.app.ability.common';
import { contextConstant } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import hash from '@ohos.file.hash';
import { Logger } from '../../common/logging/Logger';

const TAG = 'YinxingBundleInstaller';
const LOGGER = new Logger(TAG);

const RAW_BUNDLE_NAME = 'xiaohe-yinxing-production.hsyx';
const INSTALLED_BUNDLE_NAME = 'xiaohe-yinxing-production-v3.hsyx';
const VALIDATION_RECEIPT_SUFFIX = '.verified-v3';
const VALIDATION_RECEIPT_VERSION = 'yinxing-bundle-receipt/3';
const EXPECTED_BUNDLE_SIZE = 56144463;
const EXPECTED_BUNDLE_SHA256 = 'e9eb4b3bb1968e29738d257c0d9904eaa5fbf7ce1b69b0905128edc80e365aad';

export interface YinxingBundleInstallResult {
  success: boolean;
  path: string;
  errorCode: string;
  errorMessage: string;
}

export class YinxingBundleInstaller {
  private lastValidationMode: string = 'none';

  async installYinxingBundle(context: common.Context): Promise<YinxingBundleInstallResult> {
    const preparationStartedAt = Date.now();
    const storageContext = context.createAreaModeContext(contextConstant.AreaMode.EL2);
    const targetPath = `${storageContext.filesDir}/${INSTALLED_BUNDLE_NAME}`;
    const tempPath = `${storageContext.filesDir}/${INSTALLED_BUNDLE_NAME}.tmp`;
    const receiptPath = `${targetPath}${VALIDATION_RECEIPT_SUFFIX}`;

    try {
      await this.cleanupTempFiles(storageContext.filesDir);

      if (await this.isValidInstalled(targetPath, receiptPath)) {
        LOGGER.info(
          `xiaohe-yinxing bundle already installed and valid: ` +
            `validationMode=${this.lastValidationMode}, preparationMs=${Date.now() - preparationStartedAt}`
        );
        return this.success(targetPath);
      }

      LOGGER.info('installing xiaohe-yinxing bundle from HAP');
      const content: Uint8Array = context.resourceManager.getRawFileContentSync(RAW_BUNDLE_NAME);

      if (content.byteLength !== EXPECTED_BUNDLE_SIZE) {
        return this.failure(
          'BUNDLE_SIZE_MISMATCH',
          `bundle size mismatch: expected ${EXPECTED_BUNDLE_SIZE}, got ${content.byteLength}`
        );
      }

      const file = fs.openSync(tempPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const buffer = content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength);
        fs.writeSync(file.fd, buffer);
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }

      const computedHash = await hash.hash(tempPath, 'sha256');
      if (computedHash.toLowerCase() !== EXPECTED_BUNDLE_SHA256.toLowerCase()) {
        fs.unlinkSync(tempPath);
        return this.failure(
          'BUNDLE_HASH_MISMATCH',
          `bundle hash mismatch: expected ${EXPECTED_BUNDLE_SHA256}, got ${computedHash}`
        );
      }

      if (fs.accessSync(targetPath)) {
        fs.unlinkSync(targetPath);
      }
      if (fs.accessSync(receiptPath)) {
        fs.unlinkSync(receiptPath);
      }
      fs.renameSync(tempPath, targetPath);
      try {
        this.writeValidationReceipt(targetPath, receiptPath);
      } catch (err) {
        // The receipt is only a cold-start optimization. The installed bundle
        // has already passed the full SHA-256 check and remains usable.
        LOGGER.warn(`unable to persist bundle validation receipt: ${JSON.stringify(err)}`);
      }

      LOGGER.info(
        `xiaohe-yinxing bundle installed successfully: ` +
          `validationMode=install-hash, preparationMs=${Date.now() - preparationStartedAt}`
      );
      return this.success(targetPath);
    } catch (err) {
      LOGGER.error(`install xiaohe-yinxing bundle failed: ${JSON.stringify(err)}`);
      try {
        if (fs.accessSync(tempPath)) {
          fs.unlinkSync(tempPath);
        }
      } catch (_) {}
      return this.failure('BUNDLE_INSTALL_FAILED', 'bundle installation failed');
    }
  }

  private async isValidInstalled(path: string, receiptPath: string): Promise<boolean> {
    try {
      if (!fs.accessSync(path)) {
        return false;
      }
      const stat: fs.Stat = fs.statSync(path);
      if (stat.size !== EXPECTED_BUNDLE_SIZE) {
        this.removeIfPresent(receiptPath);
        return false;
      }
      if (fs.accessSync(receiptPath) &&
        fs.readTextSync(receiptPath) === this.validationReceipt(stat)) {
        this.lastValidationMode = 'receipt';
        return true;
      }
      const computedHash = await hash.hash(path, 'sha256');
      if (computedHash.toLowerCase() !== EXPECTED_BUNDLE_SHA256.toLowerCase()) {
        this.removeIfPresent(receiptPath);
        return false;
      }
      try {
        this.writeValidationReceipt(path, receiptPath);
      } catch (err) {
        LOGGER.warn(`unable to refresh bundle validation receipt: ${JSON.stringify(err)}`);
      }
      this.lastValidationMode = 'hash';
      return true;
    } catch (err) {
      LOGGER.warn(`validation failed for installed bundle: ${JSON.stringify(err)}`);
      return false;
    }
  }

  private async cleanupTempFiles(filesDir: string): Promise<void> {
    try {
      const files = fs.listFileSync(filesDir);
      for (const file of files) {
        if (file === `${INSTALLED_BUNDLE_NAME}.tmp` ||
          file === `${INSTALLED_BUNDLE_NAME}${VALIDATION_RECEIPT_SUFFIX}.tmp`) {
          const fullPath = `${filesDir}/${file}`;
          try {
            fs.unlinkSync(fullPath);
            LOGGER.info(`cleaned up temp file: ${file}`);
          } catch (err) {
            LOGGER.warn(`failed to clean temp file ${file}: ${JSON.stringify(err)}`);
          }
        }
      }
    } catch (err) {
      LOGGER.warn(`temp file cleanup failed: ${JSON.stringify(err)}`);
    }
  }

  private validationReceipt(stat: fs.Stat): string {
    return `${VALIDATION_RECEIPT_VERSION}\n${EXPECTED_BUNDLE_SHA256}\n${stat.ino.toString()}\n` +
      `${stat.size}\n${stat.mtime}\n${stat.ctime}\n`;
  }

  private writeValidationReceipt(bundlePath: string, receiptPath: string): void {
    const receiptTempPath = `${receiptPath}.tmp`;
    const content = this.validationReceipt(fs.statSync(bundlePath));
    const file: fs.File = fs.openSync(
      receiptTempPath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
    );
    try {
      fs.writeSync(file.fd, content);
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
    this.removeIfPresent(receiptPath);
    fs.renameSync(receiptTempPath, receiptPath);
  }

  private removeIfPresent(path: string): void {
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  }

  private success(path: string): YinxingBundleInstallResult {
    return {
      success: true,
      path,
      errorCode: '',
      errorMessage: ''
    };
  }

  private failure(code: string, message: string): YinxingBundleInstallResult {
    return {
      success: false,
      path: '',
      errorCode: code,
      errorMessage: message
    };
  }
}
