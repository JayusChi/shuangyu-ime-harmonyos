import { SettingsLeaveGuard } from './SettingsDetailComponents';
/**
 * 小鹤音形码表分类管理页面
 * Feature 5: 码表分类管理UI
 */

import { getSharedSettingsController, SettingsController } from '../../application/SettingsController';
import {
  EMPTY_SETTINGS_SAFE_AREA,
  getSharedSettingsWindowCoordinator,
  SettingsSafeAreaInsets,
  SettingsSafeAreaListener,
  SettingsWindowCoordinator
} from '../../application/SettingsWindowCoordinator';
import {
  XIAOHE_YINXING_CATEGORY_UI_IDS,
  XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS
} from '../../domain/settings/ImeSettings';
import { Logger } from '../../common/logging/Logger';
import { SettingsStateListener } from '../../state/SettingsStore';
import { resolveSettingsTheme, SettingsThemeTokens } from './SettingsTheme';

const LOGGER = new Logger('XiaoheYinxingCategoryManagerPage');

interface CategoryInfo {
  id: string;
  displayName: string;
  description: string;
}

const CATEGORY_INFO_MAP: Record<string, CategoryInfo> = {
  'core': {
    id: 'core',
    displayName: '首选',
    description: '基础必选词库，始终启用'
  },
  'category-secondary': {
    id: 'category-secondary',
    displayName: '分类',
    description: '包含次选、表外和随心词条'
  },
  'quick-symbol': {
    id: 'quick-symbol',
    displayName: '快符',
    description: '分号引导的常用符号与快捷操作'
  },
  'one-key-secondary': {
    id: 'one-key-secondary',
    displayName: '一简次选',
    description: '一键编码的次选词条'
  },
  'two-key-secondary': {
    id: 'two-key-secondary',
    displayName: '二简次选',
    description: '二键编码的次选词条，默认关闭'
  },
  'out-of-table-character': {
    id: 'out-of-table-character',
    displayName: '表外字',
    description: '不在常用字表中的汉字'
  },
  'full-code-word': {
    id: 'full-code-word',
    displayName: '全码词',
    description: '支持 #固置顶和 #直精确输入，默认关闭'
  },
  'symbol': {
    id: 'symbol',
    displayName: '符号',
    description: '合并符号和符号组，使用 o 编码输入'
  },
  'rare-character': {
    id: 'rare-character',
    displayName: '生僻字',
    description: '罕见汉字，默认关闭'
  },
  'full-code-character': {
    id: 'full-code-character',
    displayName: '全码字',
    description: '需要完整编码的单字，默认关闭'
  },
  'ok-spelling': {
    id: 'ok-spelling',
    displayName: 'ok拼字',
    description: '以 ok 开头的六码或八码拼字词条'
  }
};

@Component
export struct YinxingCategorySettings {
  onRegisterLeave: (guard?: SettingsLeaveGuard) => void = () => {};
  onNavigateBack: () => void = () => {};
  private pendingNavigation?: () => void;
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
    this.onRegisterLeave((proceed: () => void): void => {
      this.pendingNavigation = proceed;
      this.goBack();
    });
    this.settingsController.subscribe(this.onSettingsChanged);
    this.windowCoordinator = getSharedSettingsWindowCoordinator();
    this.windowCoordinator?.subscribeSafeArea(this.onSafeAreaChanged);
    this.loadEnabledCategories();
    this.theme = resolveSettingsTheme(this.settingsController.isDarkMode());
  }

  aboutToDisappear(): void {
    this.onRegisterLeave(undefined);
    this.settingsController.unsubscribe(this.onSettingsChanged);
    this.windowCoordinator?.unsubscribeSafeArea(this.onSafeAreaChanged);
    this.windowCoordinator = undefined;
  }

  private loadEnabledCategories(): void {
    const settings = this.settingsController.getSettings();
    this.enabledCategoryIds = settings.xiaoheYinxingEnabledCategoryIds.slice();
  }

  private isCategoryEnabled(categoryId: string): boolean {
    return this.targetCategoryIds(categoryId).every(
      (id: string): boolean => this.enabledCategoryIds.includes(id)
    );
  }

  private targetCategoryIds(categoryId: string): string[] {
    if (categoryId === 'category-secondary') {
      return ['category-secondary', 'out-of-table-character'];
    }
    if (categoryId === 'symbol') {
      return ['symbol', 'symbol-group'];
    }
    return [categoryId];
  }

  private enabledUiCategoryCount(): number {
    return XIAOHE_YINXING_CATEGORY_UI_IDS.filter((id: string) => this.isCategoryEnabled(id)).length;
  }

  private async toggleCategory(categoryId: string): Promise<void> {
    // 首选词库不可禁用
    if (categoryId === 'core') {
      this.showToast('首选不可禁用');
      return;
    }

    const isCurrentlyEnabled = this.isCategoryEnabled(categoryId);
    const targetIds: string[] = this.targetCategoryIds(categoryId);
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
    this.enabledCategoryIds = XIAOHE_YINXING_DEFAULT_ENABLED_CATEGORY_IDS.slice();
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
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 2000 });
    } catch (_) {}
  }

  private back(): void {
    try {
      const proceed = this.pendingNavigation;
      this.pendingNavigation = undefined;
      if (proceed) proceed();
      else this.onNavigateBack();
    } catch (err) {
      LOGGER.warn(`返回分类设置失败: ${JSON.stringify(err)}`);
    }
  }

  private goBack(): void {
    if (this.hasChanges) {
      try {
        this.getUIContext().getPromptAction().showDialog({
          title: '提示',
          message: '有未保存的更改，确定要退出吗？',
          buttons: [{ text: '取消', color: '#666666' }, { text: '退出', color: '#FF6B6B' }]
        }).then((result) => {
          if (result.index === 1) {
            this.back();
          }
        });
      } catch (err) {
        LOGGER.warn(`退出确认框打开失败: ${JSON.stringify(err)}`);
      }
    } else {
      this.back();
    }
  }

  build() {
    Column() {
        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Text('小鹤音形')
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

              Text('首选始终启用；二简次选、全码词、生僻字和全码字默认关闭。')
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
          .width('100%').constraintSize({ maxWidth: 720 })
          .padding({ left: 20, right: 20, top: 8, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%').align(Alignment.Top).scrollBar(BarState.Auto)
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
        .width('100%').constraintSize({ maxWidth: 720 })
        .padding({ left: 20, right: 20, top: 12, bottom: 12 })
        .backgroundColor(this.theme.pageBackground)
    }.width('100%').height('100%').backgroundColor(this.theme.pageBackground)
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
