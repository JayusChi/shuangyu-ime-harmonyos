import {
  EDITOR_KIND_EXTRA_CONFIG_KEY,
  EDITOR_KIND_NUMBER_DECIMAL
} from '../domain/editor/EditorContext';
import {
  EMPTY_SETTINGS_SAFE_AREA,
  getSharedSettingsWindowCoordinator,
  SettingsSafeAreaInsets,
  SettingsSafeAreaListener,
  SettingsWindowCoordinator
} from '../application/SettingsWindowCoordinator';
import {
  DEBUG_CARET,
  DEBUG_FIXED_LIGHT_WINDOW_STYLE,
  DEBUG_INPUT_BACKGROUND,
  DEBUG_PAGE_BACKGROUND,
  DEBUG_PLACEHOLDER_TEXT,
  DEBUG_PRIMARY_TEXT,
  DEBUG_SECONDARY_TEXT,
  DEBUG_STATUS_TEXT
} from '../presentation/settings/DebugPageTheme';

@Entry
@Component
struct DebugStage10 {
  @State private safeArea: SettingsSafeAreaInsets = EMPTY_SETTINGS_SAFE_AREA;
  @State private lastActionStatus: string = '最近编辑动作：尚未执行';
  private windowCoordinator?: SettingsWindowCoordinator;
  private windowStyleOverrideToken?: number;
  private readonly onSafeAreaChanged: SettingsSafeAreaListener = (insets: SettingsSafeAreaInsets): void => {
    this.safeArea = insets;
  };

  aboutToAppear(): void {
    this.windowCoordinator = getSharedSettingsWindowCoordinator();
    this.windowCoordinator?.subscribeSafeArea(this.onSafeAreaChanged);
    this.windowStyleOverrideToken = this.windowCoordinator?.setPageStyleOverride(DEBUG_FIXED_LIGHT_WINDOW_STYLE);
  }

  aboutToDisappear(): void {
    this.windowCoordinator?.unsubscribeSafeArea(this.onSafeAreaChanged);
    if (this.windowStyleOverrideToken !== undefined) {
      this.windowCoordinator?.clearPageStyleOverride(this.windowStyleOverrideToken);
    }
    this.windowStyleOverrideToken = undefined;
    this.windowCoordinator = undefined;
  }
  @Builder
  private FieldLabel(label: string) {
    Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(DEBUG_PRIMARY_TEXT)
  }

  @Builder
  private Stage10TextInput(label: string, placeholder: string, type: InputType, enterKey: EnterKeyType) {
    Column({ space: 6 }) {
      this.FieldLabel(label)
      TextInput({ placeholder })
        .type(type)
        .enterKeyType(enterKey)
        .onWillAttachIME((client: IMEClient) => {
          if (type === InputType.NUMBER_DECIMAL) {
            const customSettings: Record<string, string> = {};
            customSettings[EDITOR_KIND_EXTRA_CONFIG_KEY] = EDITOR_KIND_NUMBER_DECIMAL;
            client.setExtraConfig({ customSettings });
          }
        })
        .width('100%').height(48).fontSize(16)
        .fontColor(DEBUG_PRIMARY_TEXT)
        .placeholderColor(DEBUG_PLACEHOLDER_TEXT)
        .caretColor(DEBUG_CARET)
        .backgroundColor(DEBUG_INPUT_BACKGROUND)
        .onSubmit(() => { this.lastActionStatus = `最近编辑动作：${label}`; })
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(DEBUG_PAGE_BACKGROUND)
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
        )

      Column() {
        Scroll() {
          Column({ space: 16 }) {
        Text('阶段 10 · 输入框类型验收').fontSize(24).fontWeight(FontWeight.Bold)
          .fontColor(DEBUG_PRIMARY_TEXT)
        Text('仅 Debug 构建用于输入框、布局、Shift 与回车动作验收。')
          .fontSize(14).fontColor(DEBUG_SECONDARY_TEXT)
        Text(this.lastActionStatus).fontSize(13).fontColor(DEBUG_STATUS_TEXT)
        this.Stage10TextInput('普通文本', '普通文本：默认中文', InputType.Normal, EnterKeyType.Done)
        this.Stage10TextInput('密码', '密码：安全英文键盘', InputType.Password, EnterKeyType.Done)
        this.Stage10TextInput('数字密码', '数字密码', InputType.NUMBER_PASSWORD, EnterKeyType.Done)
        this.Stage10TextInput('数字', '数字：0～9', InputType.Number, EnterKeyType.Done)
        this.Stage10TextInput('小数', '小数：包含小数点', InputType.NUMBER_DECIMAL, EnterKeyType.Done)
        this.Stage10TextInput('电话', '电话：包含 * # +', InputType.PhoneNumber, EnterKeyType.Done)
        this.Stage10TextInput('邮箱', 'name@example.com', InputType.Email, EnterKeyType.Next)
        this.Stage10TextInput('URL', 'https://example.com', InputType.URL, EnterKeyType.Go)
        this.Stage10TextInput('搜索', '搜索：回车执行搜索', InputType.Normal, EnterKeyType.Search)
        Column({ space: 6 }) {
          this.FieldLabel('多行文本')
          TextArea({ placeholder: '多行文本：回车插入换行' })
            .enterKeyType(EnterKeyType.NEW_LINE).width('100%').height(120).fontSize(16)
            .fontColor(DEBUG_PRIMARY_TEXT)
            .placeholderColor(DEBUG_PLACEHOLDER_TEXT)
            .caretColor(DEBUG_CARET)
            .backgroundColor(DEBUG_INPUT_BACKGROUND)
        }.width('100%').alignItems(HorizontalAlign.Start)
          }
          .width('100%').padding(24).alignItems(HorizontalAlign.Start).backgroundColor(DEBUG_PAGE_BACKGROUND)
        }.width('100%').height('100%').backgroundColor(DEBUG_PAGE_BACKGROUND)
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.safeArea.top,
        bottom: this.safeArea.bottom,
        left: this.safeArea.left,
        right: this.safeArea.right
      })
    }.width('100%').height('100%').backgroundColor(DEBUG_PAGE_BACKGROUND)
  }
}
