import { SettingsPage } from '../presentation/settings/SettingsPage';

@Entry
@Component
struct XiaoheYinxingCategoryManagerPage {
  build() {
    Stack() {
      SettingsPage({ initialDestination: 'categories', initialSection: 'lexicon' })
    }.width('100%').height('100%')
  }
}
