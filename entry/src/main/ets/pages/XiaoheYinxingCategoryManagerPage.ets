/**
 * 小鹤音形码表分类管理页面
 * Feature 5: 码表分类管理UI
 */

import { getSharedSettingsController, SettingsController } from '../application/SettingsController';
import {
  EMPTY_SETTINGS_SAFE_AREA,
  getSharedSettingsWindowCoordinator,
  SettingsSafeAreaInsets,
  SettingsSafeAreaListener,
  SettingsWindowCoordinator
} from '../application/SettingsWindowCoordinator';
import {
  XIAOHE_YINXING_CATEGORY_IDS,
  XIAOHE_YINXING_CATEGORY_UI_IDS
} from '../domain/settings/ImeSettings';
import { Logger } from '../common/logging/Logger';
import { SettingsStateListener } from '../state/SettingsStore';
import { resolveSettingsTheme, SettingsThemeTokens } from '../presentation/settings/SettingsTheme';
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';

const LOGGER = new Logger('XiaoheYinxingCategoryManagerPage');

interface CategoryInfo {
  id: string;
  displayName: string;
  description: string;
}

const CATEGORY_INFO_MAP: Record<string, CategoryInfo> = {
  'core': {
    id: 'core',
    displayName: '核心词库',
    description: '基础必选词库，包含常用汉字和词组'
  },
  'category-secondary': {
    id: 'category-secondary',
    displayName: '分类简码',
    description: '按分类的简码词条'
  },
  'quick-symbol': {
    id: 'quick-symbol',
    displayName: '快符',
    description: '分号引导的常用符号与快捷操作'
  },
  'one-key-secondary': {
    id: 'one-key-secondary',
    displayName: '一键简码',
    description: '单键输入的常用字简码'
  },
  'two-key-secondary': {
    id: 'two-key-secondary',
    displayName: '二键简码',
    description: '两键输入的常用字简码'
  },
  'out-of-table-character': {
    id: 'out-of-table-character',
    displayName: '表外字',
    description: '不在常用字表中的汉字'
  },
  'full-code-word': {
    id: 'full-code-word',
    displayName: '全码词组',
    description: '需要完整编码的词组'
  },
  'symbol': {
    id: 'symbol',
    displayName: '符号',
    description: 'o 编码引导的符号、特殊字符与表情'
  },
  'rare-character': {
    id: 'rare-character',
    displayName: '生僻字',
    description: '罕见的汉字'
  },
  'full-code-character': {
    id: 'full-code-character',
    displayName: '全码单字',
    description: '需要完整编码的单字'
  }
};

@Entry
@Component
struct XiaoheYinxingCategoryManagerPage {
  private readonly settingsController: SettingsController = getSharedSettingsController();
  @State private enabledCategoryIds: string[] = [];
  @State private loading: boolean = false;
  @State private hasChanges: boolean = false;
  @State private theme: SettingsThemeTokens = resolveSettingsTheme(false);
  @State private safeArea: SettingsSafeAreaInsets = EMPTY_SETTINGS_SAFE_AREA;
  private windowCoordinator?: SettingsWindowCoordinator;
  private readonly onSettingsChanged: SettingsStateListener = (): void => {
    this.loadEnabledCategories();
    this.theme = resolveSettingsTheme(this.settingsController.isDarkMode());
  };
  private readonly onSafeAreaChanged: SettingsSafeAreaListener = (insets: SettingsSafeAreaInsets): void => {
    this.safeArea = insets;
  };

  aboutToAppear(): void {
    this.settingsController.subscribe(this.onSettingsChanged);
    this.windowCoordinator = getSharedSettingsWindowCoordinator();
    this.windowCoordinator?.subscribeSafeArea(this.onSafeAreaChanged);
    this.loadEnabledCategories();
    this.theme = resolveSettingsTheme(this.settingsController.isDarkMode());
  }

  aboutToDisappear(): void {
    this.settingsController.unsubscribe(this.onSettingsChanged);
    this.windowCoordinator?.unsubscribeSafeArea(this.onSafeAreaChanged);
    this.windowCoordinator = undefined;
  }

  private loadEnabledCategories(): void {
    const settings = this.settingsController.getSettings();
    this.enabledCategoryIds = settings.xiaoheYinxingEnabledCategoryIds.slice();
  }

  private isCategoryEnabled(categoryId: string): boolean {
    if (categoryId === 'symbol') {
      return this.enabledCategoryIds.includes('symbol') && this.enabledCategoryIds.includes('symbol-group');
    }
    return this.enabledCategoryIds.includes(categoryId);
  }

  private enabledUiCategoryCount(): number {
    return XIAOHE_YINXING_CATEGORY_UI_IDS.filter((id: string) => this.isCategoryEnabled(id)).length;
  }

  private async toggleCategory(categoryId: string): Promise<void> {
    // 核心词库不可禁用
    if (categoryId === 'core') {
      this.showToast('核心词库不可禁用');
      return;
    }

    const isCurrentlyEnabled = this.isCategoryEnabled(categoryId);
    const targetIds: string[] = categoryId === 'symbol' ? ['symbol', 'symbol-group'] : [categoryId];
    if (isCurrentlyEnabled) {
      this.enabledCategoryIds = this.enabledCategoryIds.filter((id: string) => !targetIds.includes(id));
    } else {
      this.enabledCategoryIds = [...this.enabledCategoryIds, ...targetIds];
    }

    this.hasChanges = true;
  }

  private async saveChanges(): Promise<void> {
    this.loading = true;
    try {
      const result = await this.settingsController.setXiaoheYinxingEnabledCategoryIds(
        this.enabledCategoryIds
      );

      if (result.success) {
        this.showToast('保存成功');
        this.hasChanges = false;
      } else {
        this.showToast(result.message || '保存失败');
      }
    } catch (err) {
      LOGGER.error(`保存分类设置失败: ${JSON.stringify(err)}`);
      this.showToast('保存失败');
    } finally {
      this.loading = false;
    }
  }

  private async resetToDefault(): Promise<void> {
    this.enabledCategoryIds = XIAOHE_YINXING_CATEGORY_IDS.slice();
    this.hasChanges = true;
    this.showToast('已重置为默认设置');
  }

  private getCategoryInfo(categoryId: string): CategoryInfo {
    return CATEGORY_INFO_MAP[categoryId] || {
      id: categoryId,
      displayName: categoryId,
      description: ''
    };
  }

  private showToast(message: string): void {
    promptAction.showToast({ message, duration: 2000 });
  }

  private goBack(): void {
    if (this.hasChanges) {
      promptAction.showDialog({
        title: '提示',
        message: '有未保存的更改，确定要退出吗？',
        buttons: [{ text: '取消', color: '#666666' }, { text: '退出', color: '#FF6B6B' }]
      }).then((result) => {
        if (result.index === 1) {
          router.back();
        }
      });
    } else {
      router.back();
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme.pageBackground)
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
        )

      Column() {
        Row({ space: 12 }) {
          Text('‹')
            .fontSize(34)
            .fontColor(this.theme.accent)
            .fontWeight(FontWeight.Lighter)
            .textAlign(TextAlign.Center)
            .width(44)
            .height(44)
            .borderRadius(14)
            .backgroundColor(this.theme.cardBackground)
            .onClick(() => this.goBack())

          Text('码表分类')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.primaryText)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Text(`${XIAOHE_YINXING_CATEGORY_UI_IDS.length} 类`)
            .fontSize(12)
            .fontColor(this.theme.secondaryText)
            .textAlign(TextAlign.Center)
            .width(44)
        }
        .width('100%')
        .height(58)
        .padding({ left: 20, right: 20, top: 7, bottom: 7 })

        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Text('小鹤音形分类词库')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.primaryText)
                  .layoutWeight(1)

                Text(`已启用 ${this.enabledUiCategoryCount()}`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.theme.accent)
                  .backgroundColor(this.theme.selectedChipBackground)
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .borderRadius(12)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              Text('核心词库始终启用，其余分类可按需开关。')
                .fontSize(13)
                .fontColor(this.theme.secondaryText)
                .width('100%')

              Text('快符使用分号引导；符号使用 o 编码输入。')
                .fontSize(12)
                .fontColor(this.theme.accent)
                .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.theme.cardBackground)
            .borderRadius(18)

            Column({ space: 0 }) {
              ForEach(XIAOHE_YINXING_CATEGORY_UI_IDS, (categoryId: string, index: number) => {
                CategoryItem({
                  category: this.getCategoryInfo(categoryId),
                  checked: this.isCategoryEnabled(categoryId),
                  isCore: categoryId === 'core',
                  primaryTextColor: this.theme.primaryText,
                  secondaryTextColor: this.theme.secondaryText,
                  dividerColor: this.theme.divider,
                  accentColor: this.theme.accent,
                  disabledBackground: this.theme.chipBackground,
                  onToggle: () => this.toggleCategory(categoryId)
                })

                if (index < XIAOHE_YINXING_CATEGORY_UI_IDS.length - 1) {
                  Divider()
                    .color(this.theme.divider)
                    .strokeWidth(0.5)
                    .margin({ left: 16, right: 16 })
                }
              }, (categoryId: string) => categoryId)
            }
            .width('100%')
            .backgroundColor(this.theme.cardBackground)
            .borderRadius(18)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 4, bottom: 14 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)

        Column({ space: 10 }) {
          Row({ space: 12 }) {
            Button('重置默认')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.primaryText)
              .backgroundColor(this.theme.chipBackground)
              .borderRadius(14)
              .height(48)
              .layoutWeight(1)
              .enabled(!this.loading)
              .onClick(() => this.resetToDefault())

            Button(this.loading ? '保存中…' : '保存更改')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor(this.hasChanges && !this.loading ? this.theme.accent : '#B9C0CA')
              .borderRadius(14)
              .height(48)
              .layoutWeight(1)
              .enabled(this.hasChanges && !this.loading)
              .onClick(() => this.saveChanges())
          }
          .width('100%')

          Text(`当前 ${this.enabledUiCategoryCount()} / ${XIAOHE_YINXING_CATEGORY_UI_IDS.length} 类启用`)
            .fontSize(12)
            .fontColor(this.theme.secondaryText)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 12 })
        .backgroundColor(this.theme.cardBackground)
        .border({ width: { top: 0.5 }, color: this.theme.divider })
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.safeArea.top,
        bottom: this.safeArea.bottom,
        left: this.safeArea.left,
        right: this.safeArea.right
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
  }
}

@Component
struct CategoryItem {
  @Prop category: CategoryInfo = { id: '', displayName: '', description: '' };
  @Prop checked: boolean = false;
  @Prop isCore: boolean = false;
  @Prop primaryTextColor: string = '#18212F';
  @Prop secondaryTextColor: string = '#657080';
  @Prop dividerColor: string = '#E5E9F0';
  @Prop accentColor: string = '#0A59F7';
  @Prop disabledBackground: string = '#EEF1F5';
  onToggle: () => void = () => {};

  build() {
    Row() {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.category.displayName)
            .fontSize(15)
            .fontColor(this.primaryTextColor)
            .fontWeight(FontWeight.Medium)

          if (this.isCore) {
            Text('必选')
              .fontSize(11)
              .fontColor('#C76800')
              .backgroundColor('#FFF1DD')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
          }
        }

        if (this.category.description) {
          Text(this.category.description)
            .fontSize(12)
            .fontColor(this.secondaryTextColor)
            .lineHeight(17)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .selectedColor(this.isCore ? this.disabledBackground : this.accentColor)
        .enabled(!this.isCore)
        .onChange((isOn: boolean) => {
          if (!this.isCore) {
            this.onToggle();
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }
}
