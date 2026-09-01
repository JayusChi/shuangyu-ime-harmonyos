import { InputMethodExtensionContext } from '@kit.IMEKit';
import fs from '@ohos.file.fs';
import hash from '@ohos.file.hash';
import { Logger } from '../../common/logging/Logger';

const TAG = 'QuanpinContextModelInstaller';
const LOGGER = new Logger(TAG);
const RAW_MODEL_NAME = 'quanpin-context-v2.qng';
const INSTALLED_MODEL_NAME = 'quanpin-context-v3-15b55101.qng';
const EXPECTED_MODEL_BYTES = 64300;
export const QUANPIN_CONTEXT_MODEL_SHA256 =
  '15b55101d77a87a64d2d414f96147291f7e260a138c98ecbea1d38af2f17b05f';
const HASH_BUFFER_BYTES = 64 * 1024;

export interface QuanpinContextModelInstallResult {
  success: boolean;
  path: string;
  errorMessage: string;
}

export class QuanpinContextModelResourceInstaller {
  install(context: InputMethodExtensionContext): QuanpinContextModelInstallResult {
    const targetPath: string = `${context.filesDir}/${INSTALLED_MODEL_NAME}`;
    const tempPath: string = `${targetPath}.tmp`;
    try {
      if (this.isInstalled(targetPath)) {
        return this.success(targetPath);
      }

      const content: Uint8Array = context.resourceManager.getRawFileContentSync(RAW_MODEL_NAME);
      if (content.byteLength !== EXPECTED_MODEL_BYTES) {
        return this.failure(`unexpected context model size: ${content.byteLength}`);
      }
      const sourceHash: string = this.hashBytes(content);
      if (sourceHash !== QUANPIN_CONTEXT_MODEL_SHA256) {
        return this.failure(`unexpected context model SHA-256: ${sourceHash}`);
      }

      const file: fs.File = fs.openSync(
        tempPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
      );
      try {
        const buffer: ArrayBuffer = content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength);
        const bytesWritten: number = fs.writeSync(file.fd, buffer);
        if (bytesWritten !== content.byteLength) {
          throw new Error(`short context model write: expected ${content.byteLength}, got ${bytesWritten}`);
        }
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }

      if (!this.isInstalled(tempPath)) {
        this.removeIfPresent(tempPath);
        return this.failure('temporary context model verification failed');
      }
      this.removeIfPresent(targetPath);
      fs.renameSync(tempPath, targetPath);
      LOGGER.info('quanpin context model installed after SHA-256 verification');
      return this.success(targetPath);
    } catch (err) {
      LOGGER.warn(`quanpin context model install failed; base ranking retained: ${JSON.stringify(err)}`);
      this.removeIfPresent(tempPath);
      return this.failure('quanpin context model resource install failed');
    }
  }

  private isInstalled(path: string): boolean {
    try {
      return fs.accessSync(path) &&
        fs.statSync(path).size === EXPECTED_MODEL_BYTES &&
        this.hashFile(path) === QUANPIN_CONTEXT_MODEL_SHA256;
    } catch (err) {
      LOGGER.warn(`quanpin context model validation failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  private hashBytes(content: Uint8Array): string {
    try {
      const hashStream: hash.HashStream = hash.createHash('sha256');
      const buffer: ArrayBuffer = content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength);
      hashStream.update(buffer);
      return hashStream.digest().toLowerCase();
    } catch (err) {
      throw new Error(`quanpin context model byte hashing failed: ${JSON.stringify(err)}`);
    }
  }

  private hashFile(path: string): string {
    try {
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
    } catch (err) {
      throw new Error(`quanpin context model file hashing failed: ${JSON.stringify(err)}`);
    }
  }

  private removeIfPresent(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (err) {
      LOGGER.warn(`failed to remove context model file: ${JSON.stringify(err)}`);
    }
  }

  private success(path: string): QuanpinContextModelInstallResult {
    return { success: true, path, errorMessage: '' };
  }

  private failure(message: string): QuanpinContextModelInstallResult {
    LOGGER.warn(`${message}; base ranking retained`);
    return { success: false, path: '', errorMessage: message };
  }
}
