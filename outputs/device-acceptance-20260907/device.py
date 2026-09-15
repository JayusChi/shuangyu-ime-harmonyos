import json, subprocess, sys, time, re
from pathlib import Path
sys.stdout.reconfigure(encoding='utf-8')
ROOT=Path(__file__).resolve().parent
HDC=r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
class Device:
    def __init__(self, name):
        self.name=name; self.target='127.0.0.1:'+('5555' if name=='phone' else '5557'); self.out=ROOT/name
    def run(self,*args):
        p=subprocess.run([HDC,'-t',self.target,*map(str,args)],capture_output=True,encoding='utf-8',errors='replace',timeout=30)
        if p.returncode: raise RuntimeError(p.stdout+p.stderr)
        return p.stdout
    def shell(self,*args): return self.run('shell',*args)
    def nodes(self,name='state',screen=False):
        remote='/data/local/tmp/accept0907.json'
        self.shell('uitest','dumpLayout','-p',remote)
        self.run('file','recv',remote,str(self.out/(name+'.json')))
        def walk(n):
            yield n.get('attributes',{})
            for c in n.get('children',[]): yield from walk(c)
        ns=list(walk(json.loads((self.out/(name+'.json')).read_text(encoding='utf-8'))))
        if screen:
            self.shell('uitest','screenCap','-p','/data/local/tmp/accept0907.png')
            self.run('file','recv','/data/local/tmp/accept0907.png',str(self.out/(name+'.png')))
        return ns
    def show(self,name='state',screen=False):
        for a in self.nodes(name,screen):
            if (a.get('text') or a.get('hint') or a.get('type') in ['TextInput','TextArea']) and a.get('visible')!='false':
                print({k:a[k] for k in ['type','text','hint','id','bounds','selected','checked'] if k in a})
    def tap(self,text):
        matches=[]
        for attempt in range(4):
            ns=self.nodes()
            matches=[a for a in ns if (a.get('text')==text or a.get('hint')==text or a.get('id')==text) and a.get('visible')!='false']
            if matches:break
            time.sleep(1)
        if len(matches)!=1: raise RuntimeError(f'{text}: {len(matches)} matches')
        a=matches[0]; x1,y1,x2,y2=map(int,re.findall(r'\d+',a['bounds']))
        self.shell('uitest','uiInput','click',(x1+x2)//2,(y1+y2)//2)
    def keys(self,text):
        for c in text:
            code=2017+ord(c)-97 if c.isascii() and c.islower() else (2000+int(c) if c.isdigit() else {' ':2050,'\n':2054,'\b':2055,'!':2070}[c])
            self.shell('uitest','uiInput','keyEvent',code)
    def start(self,bundle='com.example.shuangyuime.acceptance',fresh=False):
        if fresh:self.shell('aa','force-stop',bundle)
        print(self.shell('aa','start','-b',bundle,'-a','EntryAbility'))
if __name__=='__main__':
    d=Device(sys.argv[1]); action=sys.argv[2]; args=sys.argv[3:]
    if action=='show':d.show(args[0] if args else 'state',True)
    elif action=='tap':d.tap(args[0])
    elif action=='keys':d.keys(args[0])
    elif action=='start':d.start(*args)
    elif action=='shell':print(d.shell(*args))
