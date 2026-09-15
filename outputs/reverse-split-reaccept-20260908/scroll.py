exec(open('outputs/reverse-split-reaccept-20260908/inspect.py', encoding='utf-8-sig').read().split("d.show(")[0])
import time
for i in range(8):
    ns=d.nodes('settings-scroll')
    if any(a.get('text')=='切分模式' and a.get('visible')!='false' for a in ns):break
    d.shell('uitest','uiInput','swipe',2400,1550,2400,800,1500)
    time.sleep(.3)
d.show('settings-split-off',True)
