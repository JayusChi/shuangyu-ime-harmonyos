from device import Device, ROOT
import sys, json
d=Device(sys.argv[1]); results=[]
def typecode(code):
    if d.name=='phone':
        for c in code:d.tap(c.upper())
    else:d.keys(code)
def snap(name,expected=None,has=()):
    ns=d.nodes(name,True); value=next(a['text'] for a in ns if a.get('hint')=='ACCEPT_CHAT_SEND')
    texts=[a.get('text','') for a in ns]
    ok=(expected is None or value==expected) and all(any(t==h for t in texts) for h in has)
    r={'case':name,'text':value,'expected':expected,'required':has,'pass':ok}; results.append(r); print(json.dumps(r,ensure_ascii=False),flush=True)
    (d.out/'split-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    if not ok:raise RuntimeError(str(r))
if d.name=='phone':
    snap('split-menu','',('1 [传统]','2 [切分]'))
    d.tap('2 [切分]')
    typecode('hfkn');snap('split-ambiguous','',('1 很可能','2 困难'))
    d.tap('2 困难');snap('split-second','很困难')
prefix='很困难'
typecode('hfkn');typecode('n');snap('split-fifth',prefix+'很可能')
d.keys('!')
typecode('alyg');snap('split-unique',prefix+'很可能按理应该')
typecode('oit')
if d.name=='phone':d.tap('1 [传统]')
else:d.keys('1')
typecode('hfkn');snap('traditional-no-split',prefix+'很可能按理应该')
d.keys('!')
typecode('oit')
if d.name=='phone':d.tap('2 [切分]')
else:d.keys('2')
typecode('ni');snap('short-code-not-committed',prefix+'很可能按理应该')
if d.name=='phone':d.tap('空格')
else:d.keys(' ')
snap('normal-short-commit',prefix+'很可能按理应该你')
