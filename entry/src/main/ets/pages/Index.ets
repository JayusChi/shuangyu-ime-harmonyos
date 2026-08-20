import { SettingsPage } from '../presentation/settings/SettingsPage';

@Entry
@Component
struct Index {
  build() {
    Stack() {
      SettingsPage()
    }.width('100%').height('100%')
  }
}
