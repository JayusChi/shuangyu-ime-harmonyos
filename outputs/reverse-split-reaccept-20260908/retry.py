exec(open('outputs/reverse-split-reaccept-20260908/inspect.py', encoding='utf-8-sig').read().split("d.show(")[0])
d.tap('ACCEPT_CHAT_SEND')
d.keys('oit')
import time
time.sleep(1)
d.show('retry-oit',True)
