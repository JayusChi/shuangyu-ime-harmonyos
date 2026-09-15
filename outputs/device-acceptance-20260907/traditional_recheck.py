from device import Device
import json
d=Device('computer')
def check(name,expected,required=()):
 ns=d.nodes(name,True);a=next(a for a in ns if a.get('hint')=='ACCEPT_STRESS_LONG_INPUT');ts=[a.get('text','') for a in ns]
 result={'case':name,'actual':a['text'],'expected':expected,'required':required,'pass':a['text']==expected and all(t in ts for t in required)}
 print(json.dumps(result,ensure_ascii=False),flush=True)
 assert result['pass'],result
d.keys('oit1')
d.keys('hfkn')
check('traditional-confirmed','',('hfkn',))
d.keys('\b\b\b\b')
d.keys('oit2')
d.keys('hfkn')
check('reenable-confirmed','',('1. 很可能','2. 困难'))
d.keys('2')
check('reenable-second','很困难')
d.keys('ni ')
check('normal-short-recheck','很困难你')
d.keys('oit1')
