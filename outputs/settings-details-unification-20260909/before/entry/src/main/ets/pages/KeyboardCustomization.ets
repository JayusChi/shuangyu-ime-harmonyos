import { KeyboardCustomizationPage } from '../presentation/settings/KeyboardCustomizationPage';

@Entry
@Component
struct KeyboardCustomization {
  build() {
    Stack() {
      KeyboardCustomizationPage()
    }.width('100%').height('100%')
  }
}
