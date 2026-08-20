import common from '@ohos.app.ability.common';
import { Logger } from '../common/logging/Logger';
import {
  NativeEngineGatewayContract,
  UserLexiconActionType,
  UserLexiconDocument,
  UserLexiconEntryRecord
} from '../infrastructure/native/NativeEngineTypes';
import { NativeEngineGateway } from '../infrastructure/native/NativeEngineGateway';
import { UserLexiconPathProvider } from '../infrastructure/storage/UserLexiconPathProvider';
import { UserLexiconSyncBus } from '../infrastructure/storage/UserLexiconSyncBus';
import { getSharedInputSessionStore, InputSessionStore } from '../state/InputSessionStore';
import { EngineCoordinator, getSharedEngineCoordinator } from './EngineCoordinator';
import { SerialActionExecutor } from './SerialActionExecutor';
import { LexiconSourceConfig } from '../domain/settings/ImeSettings';
import { UserLexiconImportManager } from './UserLexiconImportManager';

const LOGGER = new Logger('UserLexiconController');

export interface UserLexiconOperationResult {
  success: boolean;
  message: string;
  document: UserLexiconDocument;
}

export type UserLexiconListener = (document: UserLexiconDocument) => void;

function emptyDocument(): UserLexiconDocument {
  return {
    success: true,
    errorCode: '',
    errorLine: 0,
    errorField: '',
    message: '',
    warningCode: '',
    revision: '',
    entries: [],
    stats: { accepted: 0, effective: 0, added: 0, deleted: 0, fixed: 0, positioned: 0 }
  };
}

export class UserLexiconDocumentEditor {
  static serialize(entries: UserLexiconEntryRecord[]): string {
    const ordered = entries.slice().sort((left: UserLexiconEntryRecord, right: UserLexiconEntryRecord) =>
      left.sourceOrder - right.sourceOrder);
    return ordered.map((entry: UserLexiconEntryRecord) => {
      let marker = '';
      if (entry.action === 'DELETE') {
        marker = '#删';
      } else if (entry.action === 'FIXED') {
        marker = '#固';
      } else if (entry.action === 'POSITION') {
        marker = `#${entry.position}`;
      }
      return `${entry.text}\t${entry.code}${marker}\n`;
    }).join('');
  }

  static upsert(
    entries: UserLexiconEntryRecord[],
    text: string,
    code: string,
    action: UserLexiconActionType,
    position: number
  ): UserLexiconEntryRecord[] {
    const next = entries.filter((entry: UserLexiconEntryRecord) =>
      !(entry.text === text && entry.code === code));
    next.push({
      id: '',
      text,
      code,
      action,
      position: action === 'POSITION' ? position : 0,
      sourceOrder: next.length
    });
    return next;
  }

  static remove(entries: UserLexiconEntryRecord[], ids: string[]): UserLexiconEntryRecord[] {
    return entries.filter((entry: UserLexiconEntryRecord) => ids.indexOf(entry.id) < 0)
      .map((entry: UserLexiconEntryRecord, index: number): UserLexiconEntryRecord => ({
        id: entry.id,
        text: entry.text,
        code: entry.code,
        action: entry.action,
        position: entry.position,
        sourceOrder: index
      }));
  }

  static applyAction(
    entries: UserLexiconEntryRecord[],
    ids: string[],
    action: UserLexiconActionType,
    position: number
  ): UserLexiconEntryRecord[] {
    return entries.map((entry: UserLexiconEntryRecord): UserLexiconEntryRecord => ({
      id: entry.id,
      text: entry.text,
      code: entry.code,
      action: ids.indexOf(entry.id) >= 0 ? action : entry.action,
      position: ids.indexOf(entry.id) >= 0 && action === 'POSITION' ? position :
        (ids.indexOf(entry.id) >= 0 ? 0 : entry.position),
      sourceOrder: entry.sourceOrder
    }));
  }
}

export class UserLexiconController {
  private readonly gateway: NativeEngineGatewayContract;
  private readonly pathProvider: UserLexiconPathProvider;
  private readonly syncBus: UserLexiconSyncBus;
  private readonly engine: EngineCoordinator;
  private readonly sessionStore: InputSessionStore;
  private readonly queue: SerialActionExecutor = new SerialActionExecutor();
  private readonly listeners: UserLexiconListener[] = [];
  private readonly sourceImporter: UserLexiconImportManager;
  private path: string = '';
  private document: UserLexiconDocument = emptyDocument();

  constructor(
    gateway: NativeEngineGatewayContract = new NativeEngineGateway(),
    pathProvider: UserLexiconPathProvider = new UserLexiconPathProvider(),
    syncBus: UserLexiconSyncBus = new UserLexiconSyncBus(),
    engine: EngineCoordinator = getSharedEngineCoordinator(),
    sessionStore: InputSessionStore = getSharedInputSessionStore(),
    sourceImporter: UserLexiconImportManager = new UserLexiconImportManager(gateway)
  ) {
    this.gateway = gateway;
    this.pathProvider = pathProvider;
    this.syncBus = syncBus;
    this.engine = engine;
    this.sessionStore = sessionStore;
    this.sourceImporter = sourceImporter;
  }

  initialize(context: common.Context): Promise<UserLexiconDocument> {
    return this.queue.enqueue(async (): Promise<UserLexiconDocument> => {
      const path = this.pathProvider.getUserLexiconPath(context);
      if (!path.success) {
        this.document = this.failure('invalid_path', path.errorMessage);
        this.notify();
        return this.getDocument();
      }
      this.path = path.path;
      this.document = this.gateway.loadUserLexicon(this.path);
      this.notify();
      return this.getDocument();
    });
  }

  reload(): Promise<UserLexiconDocument> {
    return this.queue.enqueue(async (): Promise<UserLexiconDocument> => {
      if (this.path.length <= 0) {
        return this.getDocument();
      }
      this.document = this.gateway.loadUserLexicon(this.path);
      this.notify();
      return this.getDocument();
    });
  }

  getDocument(): UserLexiconDocument {
    return {
      success: this.document.success,
      errorCode: this.document.errorCode,
      errorLine: this.document.errorLine,
      errorField: this.document.errorField,
      message: this.document.message,
      warningCode: this.document.warningCode,
      revision: this.document.revision,
      entries: this.document.entries.map((entry: UserLexiconEntryRecord): UserLexiconEntryRecord => ({
        id: entry.id,
        text: entry.text,
        code: entry.code,
        action: entry.action,
        position: entry.position,
        sourceOrder: entry.sourceOrder
      })),
      stats: {
        accepted: this.document.stats.accepted,
        effective: this.document.stats.effective,
        added: this.document.stats.added,
        deleted: this.document.stats.deleted,
        fixed: this.document.stats.fixed,
        positioned: this.document.stats.positioned
      }
    };
  }

  subscribe(listener: UserLexiconListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: UserLexiconListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  upsert(
    text: string,
    code: string,
    action: UserLexiconActionType,
    position: number = 0
  ): Promise<UserLexiconOperationResult> {
    return this.mutate(UserLexiconDocumentEditor.serialize(
      UserLexiconDocumentEditor.upsert(this.document.entries, text, code, action, position)
    ));
  }

  remove(ids: string[]): Promise<UserLexiconOperationResult> {
    return this.mutate(UserLexiconDocumentEditor.serialize(
      UserLexiconDocumentEditor.remove(this.document.entries, ids)
    ));
  }

  applyAction(
    ids: string[],
    action: UserLexiconActionType,
    position: number = 0
  ): Promise<UserLexiconOperationResult> {
    return this.mutate(UserLexiconDocumentEditor.serialize(
      UserLexiconDocumentEditor.applyAction(this.document.entries, ids, action, position)
    ));
  }

  importText(content: string, replace: boolean): Promise<UserLexiconOperationResult> {
    const merged = replace ? content : `${UserLexiconDocumentEditor.serialize(this.document.entries)}${content}`;
    return this.mutate(merged);
  }

  importSources(sources: LexiconSourceConfig[]): Promise<UserLexiconOperationResult> {
    return this.queue.enqueue(async (): Promise<UserLexiconOperationResult> => {
      if (this.path.length <= 0 || this.document.revision.length <= 0) {
        return { success: false, message: '用户词库尚未初始化', document: this.getDocument() };
      }
      const imported = await this.sourceImporter.importFromSources(sources, this.path);
      this.document = imported.finalDocument;
      if (!imported.success) {
        this.notify();
        return { success: false, message: imported.message, document: this.getDocument() };
      }
      if (this.engine.isInitialized()) {
        const composition = this.engine.reloadUserLexicon();
        if (composition.success) {
          this.sessionStore.updateComposition(composition);
        } else {
          LOGGER.warn('local user lexicon reload failed after source import');
        }
      }
      const content = UserLexiconDocumentEditor.serialize(this.document.entries);
      if (!(await this.syncBus.publish(content))) {
        LOGGER.warn('user lexicon source import event was not published');
      }
      this.notify();
      return { success: true, message: imported.message, document: this.getDocument() };
    });
  }

  clear(): Promise<UserLexiconOperationResult> {
    return this.mutate('');
  }

  exportText(): string {
    return UserLexiconDocumentEditor.serialize(this.document.entries);
  }

  private mutate(content: string): Promise<UserLexiconOperationResult> {
    return this.queue.enqueue(async (): Promise<UserLexiconOperationResult> => {
      if (this.path.length <= 0 || this.document.revision.length <= 0) {
        return { success: false, message: '用户词库尚未初始化', document: this.getDocument() };
      }
      const saved = this.gateway.saveUserLexicon(this.path, this.document.revision, content);
      if (!saved.success) {
        if (saved.errorCode === 'revision_conflict') {
          this.document = this.gateway.loadUserLexicon(this.path);
          this.notify();
        }
        return {
          success: false,
          message: this.errorMessage(saved),
          document: this.getDocument()
        };
      }
      this.document = saved;
      if (this.engine.isInitialized()) {
        const composition = this.engine.reloadUserLexicon();
        if (composition.success) {
          this.sessionStore.updateComposition(composition);
        } else {
          LOGGER.warn('local user lexicon reload failed after a verified save');
        }
      }
      const published = await this.syncBus.publish(content);
      if (!published) {
        LOGGER.warn('user lexicon change event was not published');
      }
      this.notify();
      return { success: true, message: '', document: this.getDocument() };
    });
  }

  private errorMessage(document: UserLexiconDocument): string {
    if (document.errorCode === 'revision_conflict') {
      return '用户词库已在其他窗口更新，请重试';
    }
    if (document.errorLine > 0) {
      return `第 ${document.errorLine} 行格式无效`;
    }
    return document.message.length > 0 ? document.message : '用户词库操作失败';
  }

  private failure(errorCode: string, message: string): UserLexiconDocument {
    const value = emptyDocument();
    value.success = false;
    value.errorCode = errorCode;
    value.message = message;
    return value;
  }

  private notify(): void {
    const snapshot = this.getDocument();
    this.listeners.slice().forEach((listener: UserLexiconListener) => listener(snapshot));
  }
}

const SHARED_USER_LEXICON_CONTROLLER = new UserLexiconController();

export function getSharedUserLexiconController(): UserLexiconController {
  return SHARED_USER_LEXICON_CONTROLLER;
}
