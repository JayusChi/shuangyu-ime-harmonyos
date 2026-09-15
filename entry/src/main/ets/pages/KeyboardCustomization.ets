import { SettingsPage } from '../presentation/settings/SettingsPage';

@Entry
@Component
struct KeyboardCustomization {
  build() {
    Stack() {
      SettingsPage({ initialDestination: 'customization', initialSection: 'appearance' })
    }.width('100%').height('100%')
  }
}
