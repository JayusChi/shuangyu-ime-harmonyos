from pathlib import Path
root=Path(__file__).resolve().parents[2]
path=root/'entry/src/main/ets/presentation/settings/SettingsPage.ets'
text=path.read_text(encoding='utf-8')

def replace_calls(text, name):
    marker='this.'+name+'('
    while marker in text:
        start=text.index(marker)
        i=start+len(marker)
        arg_start=i
        depth=0
        quote=''
        args=[]
        while i<len(text):
            c=text[i]
            if quote:
                if c=='\\': i+=2;continue
                if c==quote: quote=''
            elif c in "'\"`": quote=c
            elif c in '([{': depth+=1
            elif c in ')]}':
                if c==')' and depth==0:
                    args.append(text[arg_start:i].strip())
                    break
                depth-=1
            elif c==',' and depth==0:
                args.append(text[arg_start:i].strip());arg_start=i+1
            i+=1
        if name=='HomeItem':
            title,description,page,marker_value=args
            content=f'''SettingsNavigationRow({{ title: {title}, description: {description}, marker: {marker_value},
            theme: this.theme, selected: this.wideLayout && this.activeSection === {page},
            controlId: 'settings-section-' + {page}, onOpen: () => this.openSection({page}) }})'''
        else:
            title,value,page=args[:3]
            description=args[3] if len(args)>3 else "''"
            content=f'''SettingsNavigationRow({{ title: {title}, value: {value}, description: {description}, theme: this.theme,
        controlId: 'settings-open-' + {page}, onOpen: () => this.openDetail({page}) }})'''
        text=text[:start]+content+text[i+1:]
    return text

text=replace_calls(text,'Link')
text=replace_calls(text,'HomeItem')
start=text.index('  @Builder\n  private Link(')
end=text.index('  @Builder\n  private Home()',start)
text=text[:start]+text[end:]
path.with_suffix('.ets.ui-next').write_text(text,encoding='utf-8')
