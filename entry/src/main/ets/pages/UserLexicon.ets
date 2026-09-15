import { SettingsPage } from '../presentation/settings/SettingsPage';

interface UserLexiconRouteParams { initialAction?: string; }

@Entry
@Component
struct UserLexicon {
  @State private destination: string = 'user-lexicon';

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as UserLexiconRouteParams;
    this.destination = params?.initialAction === 'DIRECT' ? 'user-shortcuts' : 'user-lexicon';
  }

  build() {
    Stack() {
      SettingsPage({ initialDestination: this.destination, initialSection: 'lexicon' })
    }.width('100%').height('100%')
  }
}
