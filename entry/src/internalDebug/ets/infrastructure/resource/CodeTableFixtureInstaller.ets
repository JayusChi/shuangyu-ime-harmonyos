import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import BuildProfile from 'BuildProfile';
import { Logger } from '../../common/logging/Logger';

const LOGGER = new Logger('CodeTableFixtureInstaller');
const FIXTURE_RAW_NAME = 'code-table-fixture-synthetic.bundle';
const FIXTURE_FILE_NAME = 'debug-code-table-fixture.bundle';
const FIXTURE_BYTES = 2024260;
const ACTION_FIXTURE_RAW_NAME = 'stage11_6_6_actions.json';
const ACTION_FIXTURE_FILE_NAME = 'debug-stage11-6-6-actions.json';
const ACTION_FIXTURE_BYTES = 2171;
const FORMAL_RAW_NAME = 'xiaohe-yinxing-production.hsyx';
const FORMAL_FILE_NAME = 'debug-xiaohe-yinxing-production.hsyx';
const CORRUPT_FORMAL_FILE_NAME = 'debug-xiaohe-yinxing-corrupt.hsyx';
const INCOMPATIBLE_FORMAL_FILE_NAME = 'debug-xiaohe-yinxing-incompatible.hsyx';
const FORMAL_BYTES = 25397952;
const PRODUCTION_RAW_NAME = 'production.lex';
const PRODUCTION_FILE_NAME = 'debug-stage1163-production.lex';
const PRODUCTION_BYTES = 3751923;
const USER_LEXICON_FILE_NAME = 'debug-stage1164-user-lexicon.txt';
const RESTART_USER_LEXICON_FILE_NAME = 'debug-stage1164-restart-user-lexicon.txt';

export interface DebugResourceInstallResult {
  success: boolean;
  path: string;
  errorMessage: string;
  reusedExisting: boolean;
}

export class CodeTableFixtureInstaller {
  installFixture(context: common.Context): DebugResourceInstallResult {
    if (!BuildProfile.DEBUG) {
      return this.failure('code-table fixture is unavailable outside Debug builds');
    }
    return this.install(context, FIXTURE_RAW_NAME, FIXTURE_FILE_NAME, FIXTURE_BYTES);
  }

  installActionFixture(context: common.Context): DebugResourceInstallResult {
    if (!BuildProfile.DEBUG) {
      return this.failure('action fixture is unavailable outside Debug builds');
    }
    return this.install(
      context,
      ACTION_FIXTURE_RAW_NAME,
      ACTION_FIXTURE_FILE_NAME,
      ACTION_FIXTURE_BYTES
    );
  }

  installProductionForRegression(context: common.Context): DebugResourceInstallResult {
    if (!BuildProfile.DEBUG) {
      return this.failure('debug regression installer is unavailable outside Debug builds');
    }
    return this.install(context, PRODUCTION_RAW_NAME, PRODUCTION_FILE_NAME, PRODUCTION_BYTES);
  }

  installFormalYinxing(context: common.Context): DebugResourceInstallResult {
    if (!BuildProfile.DEBUG) {
      return this.failure('formal yinxing bundle is unavailable outside Debug builds');
    }
    return this.install(context, FORMAL_RAW_NAME, FORMAL_FILE_NAME, FORMAL_BYTES);
  }

  installCorruptFormalYinxing(context: common.Context): DebugResourceInstallResult {
    if (!BuildProfile.DEBUG) {
      return this.failure('formal yinxing corruption probe is unavailable outside Debug builds');
    }
    const targetPath: string = `${context.filesDir}/${CORRUPT_FORMAL_FILE_NAME}`;
    try {
      const content: Uint8Array = context.resourceManager.getRawFileContentSync(FORMAL_RAW_NAME);
      if (content.byteLength !== FORMAL_BYTES) {
        return this.failure(`unexpected ${FORMAL_RAW_NAME} size: ${content.byteLength}`);
      }
      const damaged: Uint8Array = new Uint8Array(content.byteLength);
      damaged.set(content);
      damaged[0] = 0x58;
      const file: fs.File = fs.openSync(
        targetPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
      );
      try {
        fs.writeSync(file.fd, damaged.buffer);
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
      return { success: true, path: targetPath, errorMessage: '', reusedExisting: false };
    } catch (err) {
      LOGGER.error(`debug formal corruption probe failed: ${JSON.stringify(err)}`);
      return this.failure('unable to prepare corrupt formal yinxing bundle');
    }
  }

  installIncompatibleFormalYinxing(context: common.Context): DebugResourceInstallResult {
    if (!BuildProfile.DEBUG) {
      return this.failure('formal yinxing compatibility probe is unavailable outside Debug builds');
    }
    const targetPath: string = `${context.filesDir}/${INCOMPATIBLE_FORMAL_FILE_NAME}`;
    try {
      const content: Uint8Array = context.resourceManager.getRawFileContentSync(FORMAL_RAW_NAME);
      if (content.byteLength !== FORMAL_BYTES) {
        return this.failure(`unexpected ${FORMAL_RAW_NAME} size: ${content.byteLength}`);
      }
      const damaged: Uint8Array = new Uint8Array(content.byteLength);
      damaged.set(content);
      damaged[12] = 0x09;
      damaged[13] = 0x00;
      const file: fs.File = fs.openSync(
        targetPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
      );
      try {
        fs.writeSync(file.fd, damaged.buffer);
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
      return { success: true, path: targetPath, errorMessage: '', reusedExisting: false };
    } catch (err) {
      LOGGER.error(`debug formal compatibility probe failed: ${JSON.stringify(err)}`);
      return this.failure('unable to prepare incompatible formal yinxing bundle');
    }
  }

  installUserLexicon(
    context: common.Context,
    content: string,
    includeBackup: boolean = false
  ): DebugResourceInstallResult {
    if (!BuildProfile.DEBUG) {
      return this.failure('debug user lexicon is unavailable outside Debug builds');
    }
    const targetPath: string = `${context.filesDir}/${USER_LEXICON_FILE_NAME}`;
    try {
      this.writeText(targetPath, content);
      if (includeBackup) {
        this.writeText(`${targetPath}.bak`, content);
      }
      return { success: true, path: targetPath, errorMessage: '', reusedExisting: false };
    } catch (err) {
      LOGGER.error(`debug user lexicon prepare failed: ${JSON.stringify(err)}`);
      return this.failure('unable to prepare debug user lexicon');
    }
  }

  installPersistentRestartLexicon(
    context: common.UIAbilityContext,
    content: string
  ): DebugResourceInstallResult {
    if (!BuildProfile.DEBUG) {
      return this.failure('debug restart lexicon is unavailable outside Debug builds');
    }
    const targetPath: string = `${context.filesDir}/${RESTART_USER_LEXICON_FILE_NAME}`;
    const markerPath: string = `${targetPath}.ready`;
    try {
      if (fs.accessSync(targetPath) && fs.accessSync(markerPath)) {
        return { success: true, path: targetPath, errorMessage: '', reusedExisting: true };
      }
      this.writeText(targetPath, content);
      this.writeText(markerPath, 'ready');
      return { success: true, path: targetPath, errorMessage: '', reusedExisting: false };
    } catch (err) {
      LOGGER.error(`debug restart lexicon prepare failed: ${JSON.stringify(err)}`);
      return this.failure('unable to prepare debug restart lexicon');
    }
  }

  corruptUserLexiconPrimary(path: string): DebugResourceInstallResult {
    if (!BuildProfile.DEBUG || path.length <= 0) {
      return this.failure('debug user lexicon corruption is unavailable');
    }
    try {
      this.writeText(path, 'invalid');
      return { success: true, path, errorMessage: '', reusedExisting: false };
    } catch (err) {
      LOGGER.error(`debug user lexicon corruption failed: ${JSON.stringify(err)}`);
      return this.failure('unable to corrupt debug user lexicon primary');
    }
  }

  corruptUserLexiconBackup(path: string): DebugResourceInstallResult {
    if (!BuildProfile.DEBUG || path.length <= 0) {
      return this.failure('debug user lexicon backup corruption is unavailable');
    }
    const backupPath: string = `${path}.bak`;
    try {
      this.writeText(backupPath, 'invalid');
      return { success: true, path: backupPath, errorMessage: '', reusedExisting: false };
    } catch (err) {
      LOGGER.error(`debug user lexicon backup corruption failed: ${JSON.stringify(err)}`);
      return this.failure('unable to corrupt debug user lexicon backup');
    }
  }

  private install(
    context: common.Context,
    rawName: string,
    fileName: string,
    expectedBytes: number
  ): DebugResourceInstallResult {
    const targetPath: string = `${context.filesDir}/${fileName}`;
    try {
      const content: Uint8Array = context.resourceManager.getRawFileContentSync(rawName);
      if (content.byteLength !== expectedBytes) {
        return this.failure(`unexpected ${rawName} size: ${content.byteLength}`);
      }
      const file: fs.File = fs.openSync(
        targetPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
      );
      try {
        const buffer: ArrayBuffer = content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength);
        fs.writeSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      return { success: true, path: targetPath, errorMessage: '', reusedExisting: false };
    } catch (err) {
      LOGGER.error(`debug resource install failed: ${JSON.stringify(err)}`);
      return this.failure(`unable to install ${rawName}`);
    }
  }

  private writeText(path: string, content: string): void {
    const file: fs.File = fs.openSync(
      path,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
    );
    try {
      fs.writeSync(file.fd, content);
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
  }

  private failure(errorMessage: string): DebugResourceInstallResult {
    return { success: false, path: '', errorMessage, reusedExisting: false };
  }
}
