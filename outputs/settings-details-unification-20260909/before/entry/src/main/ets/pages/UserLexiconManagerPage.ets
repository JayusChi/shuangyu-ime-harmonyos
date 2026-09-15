/**
 * 用户词库管理页面
 *
 * 功能：
 * - 显示当前词库统计
 * - 词条列表展示
 * - 添加/编辑/删除词条
 * - 导入/导出词库文件
 * - 实时同步更新
 */

import { getSharedUserLexiconController, UserLexiconDocument, UserLexiconEntryRecord, UserLexiconActionType } from '../application/UserLexiconController';
import { getSharedSettingsController } from '../application/SettingsController';
import { LexiconSourceConfig } from '../domain/settings/ImeSettings';
import { Logger } from '../common/logging/Logger';
import promptAction from '@ohos.promptAction';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import util from '@ohos.util';

const LOGGER = new Logger('UserLexiconManagerPage');

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

@Entry
@Component
struct UserLexiconManagerPage {
  @State document: UserLexiconDocument = emptyDocument();
  @State loading: boolean = false;
  @State searchText: string = '';
  @State selectedIds: string[] = [];
  @State showAddDialog: boolean = false;
  @State showImportDialog: boolean = false;
  @State showSourcesDialog: boolean = false;
  @State lexiconSources: LexiconSourceConfig[] = [];

  // 添加词条对话框状态
  @State newEntryText: string = '';
  @State newEntryDisplayText: string = '';
  @State newEntryCode: string = '';
  @State newEntryAction: UserLexiconActionType = 'ADD';
  @State newEntryPosition: number = 1;

  aboutToAppear() {
    this.loadDocument();
    this.loadLexiconSources();

    // 订阅词库变更
    const controller = getSharedUserLexiconController();
    controller.subscribe((doc: UserLexiconDocument) => {
      this.document = doc;
    });
  }

  aboutToDisappear() {
    const controller = getSharedUserLexiconController();
    controller.unsubscribe((doc: UserLexiconDocument) => {
      this.document = doc;
    });
  }

  private loadDocument(): void {
    const controller = getSharedUserLexiconController();
    this.document = controller.getDocument();
  }

  private loadLexiconSources(): void {
    const settingsController = getSharedSettingsController();
    this.lexiconSources = settingsController.getLexiconSources();
  }

  private async reloadDocument(): Promise<void> {
    this.loading = true;
    try {
      const controller = getSharedUserLexiconController();
      const result = await controller.reload();
      if (!result.success) {
        this.showToast(result.message);
      }
    } catch (err) {
      LOGGER.error(`重新加载失败: ${JSON.stringify(err)}`);
      this.showToast('重新加载失败');
    } finally {
      this.loading = false;
    }
  }

  private getFilteredEntries(): UserLexiconEntryRecord[] {
    if (!this.searchText) {
      return this.document.entries;
    }
    const search = this.searchText.toLowerCase();
    return this.document.entries.filter((entry: UserLexiconEntryRecord) =>
      entry.text.toLowerCase().includes(search) ||
      entry.code.toLowerCase().includes(search)
    );
  }

  private getActionLabel(action: UserLexiconActionType, position: number): string {
    switch (action) {
      case 'ADD': return '普通';
      case 'DIRECT': return '直通';
      case 'DELETE': return '删除';
      case 'FIXED': return '固定';
      case 'POSITION': return `第${position}位`;
      default: return '未知';
    }
  }

  private getActionColor(action: UserLexiconActionType): string {
    switch (action) {
      case 'ADD': return '#666666';
      case 'DIRECT': return '#9C27B0';
      case 'DELETE': return '#FF6B6B';
      case 'FIXED': return '#4CAF50';
      case 'POSITION': return '#2196F3';
      default: return '#999999';
    }
  }

  private showToast(message: string): void {
    promptAction.showToast({ message, duration: 2000 });
  }

  private async addEntry(): Promise<void> {
    if (!this.newEntryText.trim() || !this.newEntryCode.trim()) {
      this.showToast('词条和编码不能为空');
      return;
    }

    this.loading = true;
    try {
      const controller = getSharedUserLexiconController();
      const result = await controller.upsert(
        this.newEntryText.trim(),
        this.newEntryCode.trim().toLowerCase(),
        this.newEntryAction,
        this.newEntryPosition,
        this.newEntryDisplayText.trim()
      );

      if (result.success) {
        this.showToast('添加成功');
        this.showAddDialog = false;
        this.resetAddDialogState();
      } else {
        this.showToast(result.message || '添加失败');
      }
    } catch (err) {
      LOGGER.error(`添加词条失败: ${JSON.stringify(err)}`);
      this.showToast('添加失败');
    } finally {
      this.loading = false;
    }
  }

  private async deleteEntries(): Promise<void> {
    if (this.selectedIds.length === 0) {
      this.showToast('请选择要删除的词条');
      return;
    }

    this.loading = true;
    try {
      const controller = getSharedUserLexiconController();
      const result = await controller.remove(this.selectedIds);

      if (result.success) {
        this.showToast(`已删除 ${this.selectedIds.length} 条`);
        this.selectedIds = [];
      } else {
        this.showToast(result.message || '删除失败');
      }
    } catch (err) {
      LOGGER.error(`删除词条失败: ${JSON.stringify(err)}`);
      this.showToast('删除失败');
    } finally {
      this.loading = false;
    }
  }

  private async importFromFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const result = await documentPicker.select({
        maxSelectNumber: 1
      });

      if (result && result.length > 0) {
        const uri = result[0];
        const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const content = await this.readFileContent(file);
        fs.closeSync(file);

        this.loading = true;
        const controller = getSharedUserLexiconController();
        const importResult = await controller.importText(content, false);

        if (importResult.success) {
          const stats = importResult.document.stats;
          this.showToast(`导入成功: ${stats.accepted}条已接受, ${stats.effective}条有效`);
        } else {
          if (importResult.document.errorLine > 0) {
            this.showToast(`第${importResult.document.errorLine}行格式错误`);
          } else {
            this.showToast(importResult.message || '导入失败');
          }
        }
      }
    } catch (err) {
      LOGGER.error(`导入文件失败: ${JSON.stringify(err)}`);
      this.showToast('导入失败');
    } finally {
      this.loading = false;
    }
  }

  private async readFileContent(file: fs.File): Promise<string> {
    const bufferSize = 4096;
    const buffer = new ArrayBuffer(bufferSize);
    let content = '';
    let readLen = 0;

    do {
      readLen = fs.readSync(file.fd, buffer);
      if (readLen > 0) {
        const uint8Array = new Uint8Array(buffer, 0, readLen);
        const decoder = new util.TextDecoder('utf-8');
        content += decoder.decode(uint8Array);
      }
    } while (readLen > 0);

    return content;
  }

  private async exportToFile(): Promise<void> {
    try {
      const controller = getSharedUserLexiconController();
      const content = controller.exportText();

      const documentPicker = new picker.DocumentViewPicker();
      const result = await documentPicker.save({
        newFileNames: ['user_lexicon_export.txt']
      });

      if (result) {
        const file = fs.openSync(result, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.writeSync(file.fd, content);
        fs.closeSync(file);
        this.showToast('导出成功');
      }
    } catch (err) {
      LOGGER.error(`导出文件失败: ${JSON.stringify(err)}`);
      this.showToast('导出失败');
    }
  }

  private async clearAllEntries(): Promise<void> {
    promptAction.showDialog({
      title: '确认清空',
      message: '确定要清空所有用户词条吗？此操作不可恢复。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '清空', color: '#FF6B6B' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        this.loading = true;
        try {
          const controller = getSharedUserLexiconController();
          const clearResult = await controller.clear();
          if (clearResult.success) {
            this.showToast('已清空');
          } else {
            this.showToast(clearResult.message || '清空失败');
          }
        } catch (err) {
          LOGGER.error(`清空词库失败: ${JSON.stringify(err)}`);
          this.showToast('清空失败');
        } finally {
          this.loading = false;
        }
      }
    });
  }

  private resetAddDialogState(): void {
    this.newEntryText = '';
    this.newEntryDisplayText = '';
    this.newEntryCode = '';
    this.newEntryAction = 'ADD';
    this.newEntryPosition = 1;
  }

  private toggleSelection(id: string): void {
    const index = this.selectedIds.indexOf(id);
    if (index >= 0) {
      this.selectedIds.splice(index, 1);
    } else {
      this.selectedIds.push(id);
    }
  }

  private async toggleSourceEnabled(sourceId: string): Promise<void> {
    const source = this.lexiconSources.find((s: LexiconSourceConfig) => s.id === sourceId);
    if (!source) return;

    this.loading = true;
    try {
      const settingsController = getSharedSettingsController();
      const result = await settingsController.updateLexiconSource(sourceId, { enabled: !source.enabled });
      if (result.success) {
        this.loadLexiconSources();
        this.showToast(source.enabled ? '已禁用词库源' : '已启用词库源');
      } else {
        this.showToast(result.message || '操作失败');
      }
    } catch (err) {
      LOGGER.error(`切换词库源状态失败: ${JSON.stringify(err)}`);
      this.showToast('操作失败');
    } finally {
      this.loading = false;
    }
  }

  private async addLexiconSourceFromFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const result = await documentPicker.select({
        maxSelectNumber: 1
      });

      if (result && result.length > 0) {
        const uri = result[0];
        const fileName = uri.split('/').pop() || 'unknown';
        const sourceId = `source_${Date.now()}`;

        const newSource: LexiconSourceConfig = {
          id: sourceId,
          displayName: fileName,
          filePath: uri,
          enabled: true,
          priority: this.lexiconSources.length,
          mode: 'APPEND'
        };

        this.loading = true;
        const settingsController = getSharedSettingsController();
        const addResult = await settingsController.addLexiconSource(newSource);

        if (addResult.success) {
          this.loadLexiconSources();
          this.showToast('词库源已添加');
        } else {
          this.showToast(addResult.message || '添加失败');
        }
      }
    } catch (err) {
      LOGGER.error(`添加词库源失败: ${JSON.stringify(err)}`);
      this.showToast('添加失败');
    } finally {
      this.loading = false;
    }
  }

  private async removeLexiconSource(sourceId: string): Promise<void> {
    this.loading = true;
    try {
      const settingsController = getSharedSettingsController();
      const result = await settingsController.removeLexiconSource(sourceId);
      if (result.success) {
        this.loadLexiconSources();
        this.showToast('已删除词库源');
      } else {
        this.showToast(result.message || '删除失败');
      }
    } catch (err) {
      LOGGER.error(`删除词库源失败: ${JSON.stringify(err)}`);
      this.showToast('删除失败');
    } finally {
      this.loading = false;
    }
  }

  build() {
    Column() {
      // 顶部工具栏
      Row() {
        Text('用户词库')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('刷新')
          .onClick(() => this.reloadDocument())
          .enabled(!this.loading)
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#F5F5F5')

      // 统计信息卡片
      Column() {
        Row() {
          StatItem({ label: '有效词条', value: this.document.stats.effective })
          StatItem({ label: '固定词条', value: this.document.stats.fixed })
          StatItem({ label: '删除规则', value: this.document.stats.deleted })
          StatItem({ label: '定位词条', value: this.document.stats.positioned })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround)
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .margin({ left: 16, right: 16, top: 8 })

      // 搜索栏
      Row() {
        Search({ placeholder: '搜索词条或编码', value: this.searchText })
          .onChange((value: string) => {
            this.searchText = value;
          })
          .width('100%')
      }
      .padding({ left: 16, right: 16, top: 8 })

      // 词条列表
      List() {
        ForEach(this.getFilteredEntries(), (entry: UserLexiconEntryRecord) => {
          ListItem() {
            EntryItem({
              entry: entry,
              selected: this.selectedIds.indexOf(entry.id) >= 0,
              onSelect: () => this.toggleSelection(entry.id),
              actionLabel: this.getActionLabel(entry.action, entry.position),
              actionColor: this.getActionColor(entry.action)
            })
          }
        }, (entry: UserLexiconEntryRecord) => entry.id)
      }
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 8 })
      .divider({ strokeWidth: 1, color: '#E0E0E0' })

      // 底部操作栏
      Row() {
        Button('添加')
          .onClick(() => {
            this.resetAddDialogState();
            this.showAddDialog = true;
          })
          .enabled(!this.loading)
          .layoutWeight(1)

        Button('删除')
          .onClick(() => this.deleteEntries())
          .enabled(!this.loading && this.selectedIds.length > 0)
          .backgroundColor('#FF6B6B')
          .layoutWeight(1)
          .margin({ left: 8 })

        Button('词库源')
          .onClick(() => {
            this.loadLexiconSources();
            this.showSourcesDialog = true;
          })
          .enabled(!this.loading)
          .layoutWeight(1)
          .margin({ left: 8 })

        Button('导入')
          .onClick(() => this.importFromFile())
          .enabled(!this.loading)
          .layoutWeight(1)
          .margin({ left: 8 })

        Button('导出')
          .onClick(() => this.exportToFile())
          .enabled(!this.loading)
          .layoutWeight(1)
          .margin({ left: 8 })

        Button('清空')
          .onClick(() => this.clearAllEntries())
          .enabled(!this.loading)
          .backgroundColor('#FF6B6B')
          .layoutWeight(1)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#F5F5F5')

      // 添加词条对话框
      if (this.showAddDialog) {
        CustomDialog({
          controller: this.dialogController,
          autoCancel: false,
          customStyle: true,
          builder: AddEntryDialogBuilder.bind(this)()
        })
      }

      // 词库源管理对话框
      if (this.showSourcesDialog) {
        CustomDialog({
          controller: this.sourcesDialogController,
          autoCancel: false,
          customStyle: true,
          builder: LexiconSourcesDialogBuilder.bind(this)()
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
  }

  @Builder
  AddEntryDialogBuilder() {
    Column() {
      Text('添加词条')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 })

      TextInput({ placeholder: '词条（如：鸿蒙系统）', text: this.newEntryText })
        .onChange((value: string) => {
          this.newEntryText = value;
        })
        .margin({ bottom: 12 })

      TextInput({ placeholder: '编码（如：hong meng xi tong）', text: this.newEntryCode })
        .onChange((value: string) => {
          this.newEntryCode = value;
        })
        .margin({ bottom: 12 })

      Row() {
        Text('操作类型:')
          .fontSize(14)
        Blank()
        Select([
          { value: '普通添加', action: 'ADD' },
          { value: '直通词条', action: 'DIRECT' },
          { value: '删除系统词', action: 'DELETE' },
          { value: '固定首位', action: 'FIXED' },
          { value: '插入位置', action: 'POSITION' }
        ])
          .selected(this.getActionIndex(this.newEntryAction))
          .onSelect((index: number) => {
            const actions: UserLexiconActionType[] = ['ADD', 'DIRECT', 'DELETE', 'FIXED', 'POSITION'];
            this.newEntryAction = actions[index];
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      if (this.newEntryAction === 'DIRECT') {
        TextInput({ placeholder: '候选提示（可选，留空则同上屏内容）', text: this.newEntryDisplayText })
          .onChange((value: string) => {
            this.newEntryDisplayText = value;
          })
          .margin({ bottom: 12 })
      }

      if (this.newEntryAction === 'POSITION') {
        Row() {
          Text('位置:')
            .fontSize(14)
          Blank()
          Counter() {
            Text(this.newEntryPosition.toString())
          }
          .onInc(() => {
            if (this.newEntryPosition < 999) {
              this.newEntryPosition++;
            }
          })
          .onDec(() => {
            if (this.newEntryPosition > 1) {
              this.newEntryPosition--;
            }
          })
        }
        .width('100%')
        .margin({ bottom: 12 })
      }

      Row() {
        Button('取消')
          .onClick(() => {
            this.showAddDialog = false;
          })
          .layoutWeight(1)
          .backgroundColor('#CCCCCC')

        Button('确定')
          .onClick(() => this.addEntry())
          .layoutWeight(1)
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(24)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }

  private getActionIndex(action: UserLexiconActionType): number {
    const actions: UserLexiconActionType[] = ['ADD', 'DIRECT', 'DELETE', 'FIXED', 'POSITION'];
    return actions.indexOf(action);
  }

  private dialogController: CustomDialogController = new CustomDialogController({
    builder: this.AddEntryDialogBuilder.bind(this),
    autoCancel: false
  })

  private sourcesDialogController: CustomDialogController = new CustomDialogController({
    builder: this.LexiconSourcesDialogBuilder.bind(this),
    autoCancel: false
  })

  @Builder
  LexiconSourcesDialogBuilder() {
    Column() {
      Row() {
        Text('词库源管理')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('添加')
          .onClick(() => this.addLexiconSourceFromFile())
          .enabled(!this.loading)
      }
      .width('100%')
      .margin({ bottom: 16 })

      if (this.lexiconSources.length === 0) {
        Text('暂无词库源')
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 20, bottom: 20 })
      } else {
        List() {
          ForEach(this.lexiconSources, (source: LexiconSourceConfig) => {
            ListItem() {
              LexiconSourceItem({
                source: source,
                onToggle: () => this.toggleSourceEnabled(source.id),
                onRemove: () => this.removeLexiconSource(source.id)
              })
            }
          }, (source: LexiconSourceConfig) => source.id)
        }
        .height(300)
        .divider({ strokeWidth: 1, color: '#E0E0E0' })
      }

      Button('关闭')
        .onClick(() => {
          this.showSourcesDialog = false;
        })
        .width('100%')
        .margin({ top: 16 })
    }
    .padding(24)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .width('90%')
  }
}

@Component
struct StatItem {
  @Prop label: string = '';
  @Prop value: number = 0;

  build() {
    Column() {
      Text(this.value.toString())
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
      Text(this.label)
        .fontSize(12)
        .fontColor('#999999')
        .margin({ top: 4 })
    }
  }
}

@Component
struct EntryItem {
  @Prop entry: UserLexiconEntryRecord = {
    id: '',
    text: '',
    displayText: '',
    code: '',
    action: 'ADD',
    position: 0,
    sourceOrder: 0
  };
  @Prop selected: boolean = false;
  @Prop actionLabel: string = '';
  @Prop actionColor: string = '#666666';
  onSelect: () => void = () => {};

  build() {
    Row() {
      Checkbox({ name: this.entry.id })
        .select(this.selected)
        .onChange(() => {
          this.onSelect();
        })
        .margin({ right: 12 })

      Column() {
        Row() {
          Text(this.entry.text)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
          Blank()
          Text(this.actionLabel)
            .fontSize(12)
            .fontColor(this.actionColor)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.actionColor + '20')
            .borderRadius(4)
        }
        .width('100%')

        Text(this.entry.code)
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.onSelect();
    })
  }
}

@Component
struct LexiconSourceItem {
  @Prop source: LexiconSourceConfig = {
    id: '',
    displayName: '',
    filePath: '',
    enabled: false,
    priority: 0,
    mode: 'APPEND'
  };
  onToggle: () => void = () => {};
  onRemove: () => void = () => {};

  build() {
    Row() {
      Column() {
        Text(this.source.displayName)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
        Text(`模式: ${this.source.mode} | 优先级: ${this.source.priority}`)
          .fontSize(12)
          .fontColor('#999999')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.source.enabled })
        .onChange(() => {
          this.onToggle();
        })
        .margin({ left: 8, right: 8 })

      Button('删除')
        .fontSize(12)
        .backgroundColor('#FF6B6B')
        .onClick(() => {
          this.onRemove();
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }
}
