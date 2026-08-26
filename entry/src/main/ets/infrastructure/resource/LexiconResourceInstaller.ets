import { InputMethodExtensionContext } from '@kit.IMEKit';
import fs from '@ohos.file.fs';
import hash from '@ohos.file.hash';
import { Logger } from '../../common/logging/Logger';

const TAG = 'LexiconResourceInstaller';
const LOGGER = new Logger(TAG);
const RAW_LEXICON_NAME = 'production.lex';
// Bump the installed name whenever the audited production lexicon identity
// changes. This prevents a valid file from the previous release from being
// reused after an app upgrade.
const INSTALLED_LEXICON_NAME = 'production-v118.lex';
const EXPECTED_PRODUCTION_LEXICON_BYTES = 3751923;
const EXPECTED_PRODUCTION_LEXICON_SHA256 =
  'e4dead906109136470691d0e463c2ada34c8e5bb9b3fc62bb2de552ed751d365';
const HASH_BUFFER_BYTES = 64 * 1024;
const VALIDATION_RECEIPT_SUFFIX = '.verified-v1';
const VALIDATION_RECEIPT_VERSION = 'production-lexicon-receipt/1';

export interface LexiconInstallResult {
  success: boolean;
  path: string;
  errorMessage: string;
}

export class LexiconResourceInstaller {
  installDefaultLexicon(context: InputMethodExtensionContext): LexiconInstallResult {
    const targetPath: string = `${context.filesDir}/${INSTALLED_LEXICON_NAME}`;
    const tempPath: string = `${targetPath}.tmp`;
    const receiptPath: string = `${targetPath}${VALIDATION_RECEIPT_SUFFIX}`;
    const receiptTempPath: string = `${receiptPath}.tmp`;
    try {
      if (this.isInstalled(targetPath, receiptPath)) {
        LOGGER.info('production lexicon already installed and valid');
        return this.success(targetPath);
      }

      const content: Uint8Array = context.resourceManager.getRawFileContentSync(RAW_LEXICON_NAME);
      if (content.byteLength !== EXPECTED_PRODUCTION_LEXICON_BYTES) {
        const message = `unexpected lexicon resource size: ${content.byteLength}`;
        LOGGER.error(message);
        return this.failure(message);
      }
      const sourceHash: string = this.hashBytes(content);
      if (sourceHash !== EXPECTED_PRODUCTION_LEXICON_SHA256) {
        const message = `unexpected lexicon resource SHA-256: ${sourceHash}`;
        LOGGER.error(message);
        return this.failure(message);
      }

      const file: fs.File = fs.openSync(
        tempPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
      );
      try {
        const buffer: ArrayBuffer = content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength);
        const bytesWritten: number = fs.writeSync(file.fd, buffer);
        if (bytesWritten !== content.byteLength) {
          throw new Error(`short lexicon write: expected ${content.byteLength}, got ${bytesWritten}`);
        }
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }

      if (!this.isExpectedFile(tempPath)) {
        this.removeIfPresent(tempPath);
        return this.failure('temporary lexicon verification failed');
      }

      this.removeIfPresent(receiptPath);
      this.removeIfPresent(targetPath);
      fs.renameSync(tempPath, targetPath);
      try {
        this.writeValidationReceipt(targetPath, receiptPath);
      } catch (err) {
        LOGGER.warn(`unable to write lexicon validation receipt: ${JSON.stringify(err)}`);
      }

      LOGGER.info('production lexicon installed after SHA-256 verification');
      return this.success(targetPath);
    } catch (err) {
      LOGGER.error(`install production lexicon failed: ${JSON.stringify(err)}`);
      this.removeIfPresent(tempPath);
      this.removeIfPresent(receiptTempPath);
      return this.failure('production lexicon resource install failed');
    }
  }

  private isInstalled(path: string, receiptPath: string): boolean {
    try {
      if (!fs.accessSync(path)) {
        return false;
      }
      const stat: fs.Stat = fs.statSync(path);
      if (stat.size !== EXPECTED_PRODUCTION_LEXICON_BYTES) {
        this.removeIfPresent(receiptPath);
        return false;
      }
      if (fs.accessSync(receiptPath)) {
        try {
          if (fs.readTextSync(receiptPath) === this.validationReceipt(stat)) {
            return true;
          }
        } catch (err) {
          LOGGER.warn(`unable to read lexicon validation receipt: ${JSON.stringify(err)}`);
          this.removeIfPresent(receiptPath);
        }
      }
      if (!this.isExpectedFile(path)) {
        this.removeIfPresent(receiptPath);
        return false;
      }
      try {
        this.writeValidationReceipt(path, receiptPath);
      } catch (err) {
        LOGGER.warn(`unable to refresh lexicon validation receipt: ${JSON.stringify(err)}`);
      }
      return true;
    } catch (err) {
      LOGGER.warn(`production lexicon validation failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  private isExpectedFile(path: string): boolean {
    if (!fs.accessSync(path)) {
      return false;
    }
    const stat: fs.Stat = fs.statSync(path);
    return stat.size === EXPECTED_PRODUCTION_LEXICON_BYTES &&
      this.hashFile(path) === EXPECTED_PRODUCTION_LEXICON_SHA256;
  }

  private hashBytes(content: Uint8Array): string {
    const hashStream: hash.HashStream = hash.createHash('sha256');
    const buffer: ArrayBuffer = content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength);
    hashStream.update(buffer);
    return hashStream.digest().toLowerCase();
  }

  private hashFile(path: string): string {
    const hashStream: hash.HashStream = hash.createHash('sha256');
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer: ArrayBuffer = new ArrayBuffer(HASH_BUFFER_BYTES);
      let bytesRead: number = fs.readSync(file.fd, buffer);
      while (bytesRead > 0) {
        hashStream.update(bytesRead === buffer.byteLength ? buffer : buffer.slice(0, bytesRead));
        bytesRead = fs.readSync(file.fd, buffer);
      }
    } finally {
      fs.closeSync(file);
    }
    return hashStream.digest().toLowerCase();
  }

  private validationReceipt(stat: fs.Stat): string {
    return `${VALIDATION_RECEIPT_VERSION}\n${EXPECTED_PRODUCTION_LEXICON_SHA256}\n${stat.ino.toString()}\n` +
      `${stat.size}\n${stat.mtime}\n${stat.ctime}\n`;
  }

  private writeValidationReceipt(lexiconPath: string, receiptPath: string): void {
    const receiptTempPath: string = `${receiptPath}.tmp`;
    const content: string = this.validationReceipt(fs.statSync(lexiconPath));
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
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (err) {
      LOGGER.warn(`failed to remove lexicon file: ${JSON.stringify(err)}`);
    }
  }

  private success(path: string): LexiconInstallResult {
    return {
      success: true,
      path,
      errorMessage: ''
    };
  }

  private failure(message: string): LexiconInstallResult {
    return {
      success: false,
      path: '',
      errorMessage: message
    };
  }
}
