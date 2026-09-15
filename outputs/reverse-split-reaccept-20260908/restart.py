exec(open('outputs/reverse-split-reaccept-20260908/inspect.py', encoding='utf-8-sig').read().split("d.show(")[0])
import time
assert '2. 困难' in [a.get('text') for a in d.nodes('before-restart')]
d.keys('\b\b\b\b')
print('PASS settings page enabled split in independent editor',flush=True)
print(d.shell('aa','force-stop','com.corrosion.shuangyuime'),flush=True)
d.tap('ACCEPT_CHAT_SEND')
time.sleep(.5)
d.keys('hfkn')
for i in range(12):
 ns=d.nodes('restart-persisted')
 if '2. 困难' in [a.get('text') for a in ns]:break
 time.sleep(.5)
assert '2. 困难' in [a.get('text') for a in ns]
d.nodes('restart-persisted',True)
print('PASS split persists after IME process restart',flush=True)
d.keys('\b\b\b\boit1')
time.sleep(.5)
d.start('com.corrosion.shuangyuime')
time.sleep(.5)
