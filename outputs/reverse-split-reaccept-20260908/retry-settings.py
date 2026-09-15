exec(open('outputs/reverse-split-reaccept-20260908/inspect.py', encoding='utf-8-sig').read().split("d.show(")[0])
import time
d.start('com.example.shuangyuime.acceptance')
time.sleep(.5)
d.tap('ACCEPT_SEARCH')
d.keys('hfkn')
for i in range(10):
 ns=d.nodes('settings-toggle-effective-retry')
 if '2. 困难' in [a.get('text') for a in ns]:break
 time.sleep(.5)
d.show('settings-toggle-effective-retry',True)
