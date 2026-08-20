@Entry
@Component
struct Index {
  @State private chatText: string = '';
  @State private browserText: string = '';
  @State private searchText: string = '';
  @State private multilineText: string = '';
  @State private stressText: string = '';
  @State private passwordText: string = '';

  @Builder
  private FieldTitle(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor('#182431')
      .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('双羽输入法 0.2.0 独立验收')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .width('100%')

        Text('本应用与输入法使用不同包名，用于验收真实跨应用编辑器连接。')
          .fontSize(14)
          .fontColor('#5C6B7A')
          .width('100%')

        this.FieldTitle('聊天发送')
        TextInput({ text: this.chatText, placeholder: 'ACCEPT_CHAT_SEND' })
          .type(InputType.Normal)
          .enterKeyType(EnterKeyType.Send)
          .height(52)
          .onChange((value: string): void => {
            this.chatText = value;
          })

        this.FieldTitle('浏览器地址')
        TextInput({ text: this.browserText, placeholder: 'ACCEPT_BROWSER_URL' })
          .type(InputType.URL)
          .enterKeyType(EnterKeyType.Go)
          .height(52)
          .onChange((value: string): void => {
            this.browserText = value;
          })

        this.FieldTitle('搜索')
        TextInput({ text: this.searchText, placeholder: 'ACCEPT_SEARCH' })
          .type(InputType.Normal)
          .enterKeyType(EnterKeyType.Search)
          .height(52)
          .onChange((value: string): void => {
            this.searchText = value;
          })

        this.FieldTitle('多行消息')
        TextArea({ text: this.multilineText, placeholder: 'ACCEPT_MULTILINE' })
          .enterKeyType(EnterKeyType.NEW_LINE)
          .height(140)
          .onChange((value: string): void => {
            this.multilineText = value;
          })

        this.FieldTitle('快速连击与长期输入')
        TextArea({ text: this.stressText, placeholder: 'ACCEPT_STRESS_LONG_INPUT' })
          .enterKeyType(EnterKeyType.NEW_LINE)
          .height(180)
          .onChange((value: string): void => {
            this.stressText = value;
          })

        Text(`当前字符数：${this.stressText.length}`)
          .fontSize(14)
          .fontColor('#5C6B7A')
          .width('100%')

        this.FieldTitle('密码输入保护')
        TextInput({ text: this.passwordText, placeholder: 'ACCEPT_PASSWORD' })
          .type(InputType.Password)
          .height(52)
          .onChange((value: string): void => {
            this.passwordText = value;
          })

        Text(`PASSWORD_LENGTH=${this.passwordText.length}`)
          .fontSize(14)
          .fontColor('#5C6B7A')
          .width('100%')
      }
      .padding(20)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F8FA')
  }
}
