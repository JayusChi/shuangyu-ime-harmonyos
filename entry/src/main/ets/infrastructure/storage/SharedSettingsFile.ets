import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import { KEYBOARD_CUSTOMIZATION_DATA_GROUP_ID } from '../customization/KeyboardCustomizationStorageConfig';

const MAX_SETTINGS_BYTES: number = 64 * 1024;

/** Main-app snapshot; BASIC extensions only read their shared mount. */
export class SharedSettingsFile {
  private path: string = '';

  async initialize(context: common.Context): Promise<void> {
    if (!KEYBOARD_CUSTOMIZATION_DATA_GROUP_ID || this.path) {
      return;
    }
    const directory = await context.getGroupDir(KEYBOARD_CUSTOMIZATION_DATA_GROUP_ID);
    if (!directory || !directory.startsWith('/') || directory === context.filesDir || directory === context.cacheDir) {
      throw new Error('invalid shared settings directory');
    }
    this.path = `${directory}/ime-settings.json`;
  }

  read(): string | undefined {
    if (!this.path || !fs.accessSync(this.path)) {
      return undefined;
    }
    const size = fs.statSync(this.path).size;
    if (size <= 0 || size > MAX_SETTINGS_BYTES) {
      throw new Error('invalid shared settings size');
    }
    return fs.readTextSync(this.path);
  }

  write(record: string): void {
    if (!this.path) {
      // Unprovisioned installations still retain working DataProxy settings.
      // initialize() reports the missing mount to the caller.
      return;
    }
    const temporary = `${this.path}.pending`;
    try {
      const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, record);
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
      // Rename on the same mount exposes only complete settings to readers.
      fs.renameSync(temporary, this.path);
    } finally {
      if (fs.accessSync(temporary)) {
        fs.unlinkSync(temporary);
      }
    }
  }
}
