import { UserLexiconPage } from '../presentation/settings/UserLexiconPage';

@Entry
@Component
struct UserLexicon {
  build() {
    Stack() {
      UserLexiconPage()
    }.width('100%').height('100%')
  }
}
