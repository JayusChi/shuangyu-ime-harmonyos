exec(open('outputs/reverse-split-reaccept-20260908/inspect.py', encoding='utf-8-sig').read().split("d.show(")[0])
import time, json
results=[]
expected_text=''
def check(name, expected, required=()):
    for attempt in range(12):
        ns=d.nodes(name)
        value=next(a['text'] for a in ns if a.get('hint')=='ACCEPT_CHAT_SEND')
        texts=[a.get('text','') for a in ns if a.get('visible')!='false']
        ok=value==expected and all(t in texts for t in required)
        if ok: break
        time.sleep(.35)
    d.nodes(name,True)
    r=dict(case=name,actual=value,expected=expected,required=required,passed=ok)
    results.append(r)
    (d.out/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(r,ensure_ascii=False),flush=True)
    assert ok, r
check('01-oit-menu','',('1. [传统]','2. [切分]'))
d.keys('1')
d.keys('hfkn')
check('02-traditional-no-split','')
d.keys('oit')
check('03-oit-reopen','',('1. [传统]','2. [切分]'))
d.keys('2')
d.keys('hfkn')
check('04-split-candidates','',("hf'kn",'1. 很可能','2. 困难'))
d.keys('2')
expected_text='很困难'
check('05-second-commits-full',expected_text)
d.keys('hfknn')
expected_text+='很可能'
check('06-fifth-keeps-next-code',expected_text,('n',))
d.keys('\b')
d.keys('hfkn')
check('07-before-backspace',expected_text,("hf'kn",))
d.keys('\b')
check('08-backspace',expected_text,('hfk',))
d.keys('n')
check('09-retype',expected_text,('1. 很可能','2. 困难'))
d.keys('\b\b\b\b')
for i,(code,wanted) in enumerate([('alyghfry','按理应该很容易'),('gmycxnta','干嘛要笑她'),('xtupjdma','学双拼简单吗'),('nivtsmne','你折腾什么呢')]):
    d.keys(code)
    # Last ambiguous group is explicitly confirmed as in normal four-code input.
    time.sleep(.5)
    ns=d.nodes('sentence-state')
    value=next(a['text'] for a in ns if a.get('hint')=='ACCEPT_CHAT_SEND')
    if value!=expected_text+wanted:
        d.keys(' ')
    expected_text+=wanted
    check(f'10-sentence-{i+1}',expected_text)
d.keys('oit1')
d.keys('hfkn')
check('11-return-traditional',expected_text)
# No Escape on empty composition: the host may hide/detach the IME.

