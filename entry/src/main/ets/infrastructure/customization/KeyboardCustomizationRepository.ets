import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';
import { Logger } from '../../common/logging/Logger';
import {
  KeyboardCustomizationOption,
  KeyboardSkinDefinition,
  KeyboardStructureDefinition,
  parseKeyboardSkinJson,
  parseKeyboardStructureJson
} from '../../domain/customization/KeyboardCustomization';
import {
  bundledKeyboardSkinOptions,
  bundledKeyboardStructureOptions,
  loadBundledKeyboardSkin,
  loadBundledKeyboardStructure
} from '../../domain/customization/BundledKeyboardCustomizations';

const LOGGER = new Logger('KeyboardCustomizationRepository');
const ROOT_DIRECTORY_NAME = 'keyboard-customization';
const STRUCTURES_DIRECTORY_NAME = 'structures';
const SKINS_DIRECTORY_NAME = 'skins';
const STRUCTURE_MANIFEST_NAME = 'layout.json';
const SKIN_MANIFEST_NAME = 'skin.json';
const ASSETS_DIRECTORY_NAME = 'assets';
const MAX_ARCHIVE_BYTES: number = 12 * 1024 * 1024;
const MAX_EXTRACTED_BYTES: number = 24 * 1024 * 1024;
const MAX_PACKAGE_FILES: number = 32;

export interface KeyboardCustomizationImportResult {
  success: boolean;
  message: string;
  id?: string;
  name?: string;
}

export interface InstalledKeyboardSkin {
  definition: KeyboardSkinDefinition;
  assetRoot: string;
}

interface PackageTreeSummary {
  files: string[];
  totalBytes: number;
}

interface ExtractPackageResult {
  success: boolean;
  message: string;
  directory?: string;
  cleanupDirectory?: string;
}

export class KeyboardCustomizationRepository {
  private rootDirectory: string = '';
  private cacheDirectory: string = '';

  initialize(context: common.Context): void {
    this.rootDirectory = `${context.filesDir}/${ROOT_DIRECTORY_NAME}`;
    this.cacheDirectory = `${context.cacheDir}/${ROOT_DIRECTORY_NAME}`;
    this.ensureDirectory(this.rootDirectory);
    this.ensureDirectory(this.structuresDirectory());
    this.ensureDirectory(this.skinsDirectory());
    this.ensureDirectory(this.cacheDirectory);
  }

  listStructures(): KeyboardCustomizationOption[] {
    const options: KeyboardCustomizationOption[] = bundledKeyboardStructureOptions();
    this.installedDirectoryNames(this.structuresDirectory()).forEach((directoryName: string): void => {
      const definition = this.loadStructure(directoryName);
      if (definition) {
        options.push({ id: definition.id, name: definition.name, builtIn: false });
      }
    });
    return options;
  }

  listSkins(): KeyboardCustomizationOption[] {
    const options: KeyboardCustomizationOption[] = bundledKeyboardSkinOptions();
    this.installedDirectoryNames(this.skinsDirectory()).forEach((directoryName: string): void => {
      const installed = this.loadSkin(directoryName);
      if (installed) {
        options.push({ id: installed.definition.id, name: installed.definition.name, builtIn: false });
      }
    });
    return options;
  }

  loadStructure(id: string): KeyboardStructureDefinition | undefined {
    const bundled = loadBundledKeyboardStructure(id);
    if (bundled) {
      return bundled;
    }
    if (id.startsWith('builtin.') || !this.ready()) {
      return undefined;
    }
    const manifestPath = `${this.structuresDirectory()}/${id}/${STRUCTURE_MANIFEST_NAME}`;
    try {
      const parsed = parseKeyboardStructureJson(fs.readTextSync(manifestPath));
      return parsed.success && parsed.value?.id === id ? parsed.value : undefined;
    } catch (err) {
      LOGGER.warn(`custom structure load failed: ${JSON.stringify(err)}`);
      return undefined;
    }
  }

  loadSkin(id: string): InstalledKeyboardSkin | undefined {
    const bundled = loadBundledKeyboardSkin(id);
    if (bundled) {
      return { definition: bundled, assetRoot: '' };
    }
    if (id.startsWith('builtin.') || !this.ready()) {
      return undefined;
    }
    const packageDirectory = `${this.skinsDirectory()}/${id}`;
    try {
      const parsed = parseKeyboardSkinJson(fs.readTextSync(`${packageDirectory}/${SKIN_MANIFEST_NAME}`));
      if (!parsed.success || !parsed.value || parsed.value.id !== id ||
        !this.skinAssetsExist(packageDirectory, parsed.value)) {
        return undefined;
      }
      return { definition: parsed.value, assetRoot: packageDirectory };
    } catch (err) {
      LOGGER.warn(`custom skin load failed: ${JSON.stringify(err)}`);
      return undefined;
    }
  }

  async importStructurePackage(
    context: common.Context,
    sourceUri: string
  ): Promise<KeyboardCustomizationImportResult> {
    this.initialize(context);
    const extracted = await this.extractPackage(sourceUri, STRUCTURE_MANIFEST_NAME);
    if (!extracted.success || !extracted.directory) {
      if (extracted.cleanupDirectory) {
        this.removeTree(extracted.cleanupDirectory);
      }
      return { success: false, message: extracted.message };
    }
    try {
      const summary = this.summarizePackage(extracted.directory);
      if (summary.files.length !== 1 || summary.files[0] !== STRUCTURE_MANIFEST_NAME) {
        return { success: false, message: '结构包只能包含 layout.json' };
      }
      const parsed = parseKeyboardStructureJson(
        fs.readTextSync(`${extracted.directory}/${STRUCTURE_MANIFEST_NAME}`)
      );
      if (!parsed.success || !parsed.value) {
        return { success: false, message: parsed.message };
      }
      this.installDirectory(
        extracted.directory,
        `${this.structuresDirectory()}/${parsed.value.id}`,
        [STRUCTURE_MANIFEST_NAME]
      );
      return { success: true, message: '', id: parsed.value.id, name: parsed.value.name };
    } catch (err) {
      LOGGER.warn(`custom structure import failed: ${JSON.stringify(err)}`);
      return { success: false, message: `结构包导入失败：${JSON.stringify(err)}` };
    } finally {
      this.removeTree(extracted.cleanupDirectory ?? extracted.directory);
    }
  }

  async importSkinPackage(
    context: common.Context,
    sourceUri: string
  ): Promise<KeyboardCustomizationImportResult> {
    this.initialize(context);
    const extracted = await this.extractPackage(sourceUri, SKIN_MANIFEST_NAME);
    if (!extracted.success || !extracted.directory) {
      if (extracted.cleanupDirectory) {
        this.removeTree(extracted.cleanupDirectory);
      }
      return { success: false, message: extracted.message };
    }
    try {
      const summary = this.summarizePackage(extracted.directory);
      if (summary.files.indexOf(SKIN_MANIFEST_NAME) < 0 ||
        summary.files.some((path: string): boolean =>
          path !== SKIN_MANIFEST_NAME && !path.startsWith(`${ASSETS_DIRECTORY_NAME}/`))) {
        return { success: false, message: '皮肤包只能包含 skin.json 和 assets 目录' };
      }
      const parsed = parseKeyboardSkinJson(fs.readTextSync(`${extracted.directory}/${SKIN_MANIFEST_NAME}`));
      if (!parsed.success || !parsed.value) {
        return { success: false, message: parsed.message };
      }
      if (!this.skinAssetsExist(extracted.directory, parsed.value)) {
        return { success: false, message: 'skin.json 引用的图片不存在' };
      }
      this.installDirectory(
        extracted.directory,
        `${this.skinsDirectory()}/${parsed.value.id}`,
        summary.files
      );
      return { success: true, message: '', id: parsed.value.id, name: parsed.value.name };
    } catch (err) {
      LOGGER.warn(`custom skin import failed: ${JSON.stringify(err)}`);
      return { success: false, message: `皮肤包导入失败：${JSON.stringify(err)}` };
    } finally {
      this.removeTree(extracted.cleanupDirectory ?? extracted.directory);
    }
  }

  removeStructure(id: string): boolean {
    if (id.startsWith('builtin.') || !this.ready()) {
      return false;
    }
    return this.removeTree(`${this.structuresDirectory()}/${id}`);
  }

  removeSkin(id: string): boolean {
    if (id.startsWith('builtin.') || !this.ready()) {
      return false;
    }
    return this.removeTree(`${this.skinsDirectory()}/${id}`);
  }

  private ready(): boolean {
    return this.rootDirectory.length > 0;
  }

  private structuresDirectory(): string {
    return `${this.rootDirectory}/${STRUCTURES_DIRECTORY_NAME}`;
  }

  private skinsDirectory(): string {
    return `${this.rootDirectory}/${SKINS_DIRECTORY_NAME}`;
  }

  private installedDirectoryNames(directory: string): string[] {
    if (!this.ready()) {
      return [];
    }
    try {
      return fs.listFileSync(directory)
        .filter((name: string): boolean => !name.startsWith('.') &&
          fs.statSync(`${directory}/${name}`).isDirectory())
        .sort();
    } catch (err) {
      LOGGER.warn(`customization directory scan failed: ${JSON.stringify(err)}`);
      return [];
    }
  }

  private async extractPackage(sourceUri: string, manifestName: string): Promise<ExtractPackageResult> {
    const nonce = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    const workDirectory = `${this.cacheDirectory}/import-${nonce}`;
    const archivePath = `${workDirectory}/package.zip`;
    const extractedDirectory = `${workDirectory}/extracted`;
    try {
      this.ensureDirectory(workDirectory);
      const sourceFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      try {
        fs.copyFileSync(sourceFile.fd, archivePath);
      } finally {
        fs.closeSync(sourceFile);
      }
      const archiveBytes = fs.statSync(archivePath).size;
      if (archiveBytes <= 0 || archiveBytes > MAX_ARCHIVE_BYTES) {
        return { success: false, message: '压缩包大小必须在 1B～12MB 之间', cleanupDirectory: workDirectory };
      }
      const originalBytes = await zlib.getOriginalSize(archivePath);
      if (originalBytes <= 0 || originalBytes > MAX_EXTRACTED_BYTES) {
        return { success: false, message: '解压后大小必须在 1B～24MB 之间', cleanupDirectory: workDirectory };
      }
      this.ensureDirectory(extractedDirectory);
      const options: zlib.Options = {};
      await zlib.decompressFile(archivePath, extractedDirectory, options);
      const summary = this.summarizePackage(extractedDirectory);
      if (summary.files.length <= 0 || summary.files.length > MAX_PACKAGE_FILES ||
        summary.totalBytes > MAX_EXTRACTED_BYTES) {
        return { success: false, message: '压缩包文件数量或解压后大小超出限制', cleanupDirectory: workDirectory };
      }
      let packageDirectory = extractedDirectory;
      if (!this.exists(`${packageDirectory}/${manifestName}`)) {
        const entries = fs.listFileSync(extractedDirectory);
        if (entries.length !== 1 || !fs.statSync(`${extractedDirectory}/${entries[0]}`).isDirectory()) {
          return { success: false, message: `压缩包根目录缺少 ${manifestName}`, cleanupDirectory: workDirectory };
        }
        packageDirectory = `${extractedDirectory}/${entries[0]}`;
      }
      if (!this.exists(`${packageDirectory}/${manifestName}`)) {
        return { success: false, message: `压缩包内缺少 ${manifestName}`, cleanupDirectory: workDirectory };
      }
      return { success: true, message: '', directory: packageDirectory, cleanupDirectory: workDirectory };
    } catch (err) {
      this.removeTree(workDirectory);
      return { success: false, message: `无法解压模板包：${JSON.stringify(err)}` };
    }
  }

  private summarizePackage(directory: string): PackageTreeSummary {
    const files: string[] = [];
    let totalBytes = 0;
    const visit = (currentDirectory: string, prefix: string): void => {
      const entries = fs.listFileSync(currentDirectory);
      entries.forEach((name: string): void => {
        if (name === '.' || name === '..' || name.indexOf('\\') >= 0 || name.indexOf('/') >= 0) {
          throw new Error('压缩包包含非法路径');
        }
        const fullPath = `${currentDirectory}/${name}`;
        const relativePath = prefix.length > 0 ? `${prefix}/${name}` : name;
        const stat = fs.statSync(fullPath);
        if (stat.isDirectory()) {
          visit(fullPath, relativePath);
          return;
        }
        files.push(relativePath);
        totalBytes += stat.size;
        if (files.length > MAX_PACKAGE_FILES || totalBytes > MAX_EXTRACTED_BYTES) {
          throw new Error('模板包超过大小限制');
        }
      });
    };
    visit(directory, '');
    files.sort();
    return { files, totalBytes };
  }

  private skinAssetsExist(directory: string, definition: KeyboardSkinDefinition): boolean {
    const images = definition.images as Record<string, Object>;
    const keys: string[] = ['panelBackground', 'letterKey', 'functionKey', 'spaceKey', 'enterKey'];
    return keys.every((key: string): boolean => {
      const relativePath = images[key];
      return relativePath === undefined ||
        (typeof relativePath === 'string' && this.exists(`${directory}/${relativePath}`));
    });
  }

  private installDirectory(sourceDirectory: string, targetDirectory: string, relativeFiles: string[]): void {
    const nonce = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    const stagingDirectory = `${targetDirectory}.tmp-${nonce}`;
    const backupDirectory = `${targetDirectory}.bak-${nonce}`;
    this.ensureDirectory(stagingDirectory);
    try {
      relativeFiles.forEach((relativePath: string): void => {
        const separator = relativePath.lastIndexOf('/');
        if (separator >= 0) {
          this.ensureDirectory(`${stagingDirectory}/${relativePath.substring(0, separator)}`);
        }
        fs.copyFileSync(`${sourceDirectory}/${relativePath}`, `${stagingDirectory}/${relativePath}`);
      });
      if (this.exists(targetDirectory)) {
        fs.renameSync(targetDirectory, backupDirectory);
      }
      fs.renameSync(stagingDirectory, targetDirectory);
      this.removeTree(backupDirectory);
    } catch (err) {
      this.removeTree(stagingDirectory);
      if (!this.exists(targetDirectory) && this.exists(backupDirectory)) {
        try {
          fs.renameSync(backupDirectory, targetDirectory);
        } catch (restoreErr) {
          LOGGER.warn(`customization rollback failed: ${JSON.stringify(restoreErr)}`);
        }
      }
      throw new Error(JSON.stringify(err));
    }
  }

  private ensureDirectory(path: string): void {
    if (!this.exists(path)) {
      try {
        fs.mkdirSync(path, true);
      } catch (err) {
        throw new Error(`customization directory creation failed: ${JSON.stringify(err)}`);
      }
    }
  }

  private exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_err) {
      return false;
    }
  }

  private removeTree(path: string): boolean {
    try {
      if (!this.exists(path)) {
        return true;
      }
      const stat = fs.statSync(path);
      if (!stat.isDirectory()) {
        fs.unlinkSync(path);
        return true;
      }
      fs.listFileSync(path).forEach((name: string): void => {
        this.removeTree(`${path}/${name}`);
      });
      fs.rmdirSync(path);
      return true;
    } catch (err) {
      LOGGER.warn(`customization cleanup failed: ${JSON.stringify(err)}`);
      return false;
    }
  }
}

const SHARED_KEYBOARD_CUSTOMIZATION_REPOSITORY = new KeyboardCustomizationRepository();

export function getSharedKeyboardCustomizationRepository(): KeyboardCustomizationRepository {
  return SHARED_KEYBOARD_CUSTOMIZATION_REPOSITORY;
}
