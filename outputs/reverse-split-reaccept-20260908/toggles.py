exec(open('outputs/reverse-split-reaccept-20260908/inspect.py', encoding='utf-8-sig').read().split("d.show(")[0])
for a in d.nodes('toggle-state'):
    if a.get('type')=='Toggle': print(a)
