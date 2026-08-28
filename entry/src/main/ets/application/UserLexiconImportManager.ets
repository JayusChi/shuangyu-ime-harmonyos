import fs from '@ohos.file.fs';
import { Logger } from '../common/logging/Logger';
import { NativeEngineGateway } from '../infrastructure/native/NativeEngineGateway';
import {
  NativeEngineGatewayContract,
  UserLexiconDocument,
  UserLexiconEntryRecord
} from '../infrastructure/native/NativeEngineTypes';
import { LexiconSourceConfig } from '../domain/settings/ImeSettings';


const LOGGER = new Logger('UserLexiconImportManager');

export interface ImportResult {
  success: boolean;
  message: string;
  importedCount: number;
  skippedCount: number;
}

export interface SourceImportPair {
  source: LexiconSourceConfig;
  result: ImportResult;
}

export interface MultiSourceImportResult {
  success: boolean;
  message: string;
  sources: SourceImportPair[];
  finalDocument: UserLexiconDocument;
}

export interface ValidationResult {
  valid: boolean;
  error: string;
}

export class UserLexiconImportManager {
  private readonly gateway: NativeEngineGatewayContract;

  constructor(gateway: NativeEngineGatewayContract = new NativeEngineGateway()) {
    this.gateway = gateway;
  }

  async importFromSources(
    sources: LexiconSourceConfig[],
    targetPath: string
  ): Promise<MultiSourceImportResult> {
    const enabledSources = sources
      .filter((src: LexiconSourceConfig) => src.enabled)
      .sort((a: LexiconSourceConfig, b: LexiconSourceConfig) => a.priority - b.priority);

    const baseDocument = this.gateway.loadUserLexicon(targetPath);
    if (!baseDocument.success || baseDocument.revision.length === 0) {
      return {
        success: false,
        message: baseDocument.message || '用户词库尚未初始化',
        sources: [],
        finalDocument: baseDocument
      };
    }

    if (enabledSources.length === 0) {
      return {
        success: true,
        message: '没有启用的词库源',
        sources: [],
        finalDocument: baseDocument
      };
    }

    const results: SourceImportPair[] = [];
    let mergedContent = this.serializeEntries(baseDocument.entries);

    for (const source of enabledSources) {
      const validation = this.validateSource(source);
      if (!validation.valid) {
        const failed = this.importFailure(validation.error);
        results.push({ source, result: failed });
        return {
          success: false,
          message: `${source.displayName}: ${validation.error}`,
          sources: results,
          finalDocument: baseDocument
        };
      }
      try {
        const sourceContent = fs.readTextSync(source.filePath);
        const importedCount = this.nonEmptyLineCount(sourceContent);
        if (source.mode === 'REPLACE') {
          mergedContent = sourceContent;
        } else if (source.mode === 'APPEND') {
          mergedContent = this.appendContent(mergedContent, sourceContent);
        } else {
          mergedContent = this.mergeContent(mergedContent, sourceContent);
        }
        results.push({
          source,
          result: {
            success: true,
            message: '导入成功',
            importedCount,
            skippedCount: 0
          }
        });
      } catch (err) {
        const message = `文件读取失败: ${JSON.stringify(err)}`;
        results.push({ source, result: this.importFailure(message) });
        return {
          success: false,
          message: `${source.displayName}: ${message}`,
          sources: results,
          finalDocument: baseDocument
        };
      }
    }

    const finalDocument = this.gateway.saveUserLexicon(
      targetPath,
      baseDocument.revision,
      mergedContent
    );
    if (!finalDocument.success) {
      return {
        success: false,
        message: finalDocument.errorLine > 0 ?
          `第 ${finalDocument.errorLine} 行格式无效` :
          (finalDocument.message || finalDocument.errorCode || '用户词库保存失败'),
        sources: results,
        finalDocument
      };
    }

    return {
      success: true,
      message: `成功导入 ${enabledSources.length} 个词库源`,
      sources: results,
      finalDocument
    };
  }

  private importFailure(message: string): ImportResult {
    return { success: false, message, importedCount: 0, skippedCount: 0 };
  }

  private appendContent(base: string, additional: string): string {
    const prefix = base.length === 0 || base.endsWith('\n') ? base : `${base}\n`;
    return `${prefix}${additional}`;
  }

  private nonEmptyLineCount(content: string): number {
    return content.split('\n').filter((line: string): boolean => line.trim().length > 0).length;
  }

  private mergeContent(base: string, additional: string): string {
    const baseLines = new Set(
      base.split('\n')
        .map((line: string) => line.trim())
        .filter((line: string) => line.length > 0)
    );

    const additionalLines = additional.split('\n')
      .map((line: string) => line.trim())
      .filter((line: string) => line.length > 0 && !baseLines.has(line));

    return this.appendContent(base, additionalLines.join('\n'));
  }

  private serializeEntries(entries: UserLexiconEntryRecord[]): string {
    return entries.slice()
      .sort((left: UserLexiconEntryRecord, right: UserLexiconEntryRecord): number =>
        left.sourceOrder - right.sourceOrder)
      .map((entry: UserLexiconEntryRecord): string => {
        let marker = '';
        if (entry.action === 'DIRECT') {
          marker = '#直';
        } else if (entry.action === 'DELETE') {
          marker = '#删';
        } else if (entry.action === 'FIXED') {
          marker = '#固';
        } else if (entry.action === 'POSITION') {
          marker = `#${entry.position}`;
        }
        const word = entry.action === 'DIRECT' && entry.displayText.length > 0 ?
          `${entry.text},${entry.displayText}` : entry.text;
        return `${word}\t${entry.code}${marker}\n`;
      }).join('');
  }

  async scanDirectory(dirPath: string): Promise<string[]> {
    const lexiconFiles: string[] = [];
    try {
      if (!fs.accessSync(dirPath)) {
        return lexiconFiles;
      }

      const dir = fs.listFileSync(dirPath);
      for (const filename of dir) {
        if (filename.endsWith('.txt') || filename.endsWith('.dict')) {
          lexiconFiles.push(`${dirPath}/${filename}`);
        }
      }
    } catch (err) {
      LOGGER.warn(`Failed to scan directory ${dirPath}: ${JSON.stringify(err)}`);
    }
    return lexiconFiles;
  }

  validateSource(source: LexiconSourceConfig): ValidationResult {
    if (!source.filePath || source.filePath.length === 0) {
      return { valid: false, error: '文件路径为空' };
    }

    try {
      if (!fs.accessSync(source.filePath)) {
        return { valid: false, error: '文件不存在' };
      }
    } catch (err) {
      return { valid: false, error: `文件访问失败: ${JSON.stringify(err)}` };
    }

    if (source.priority < 0) {
      return { valid: false, error: '优先级必须大于等于0' };
    }

    return { valid: true, error: '' };
  }
}
