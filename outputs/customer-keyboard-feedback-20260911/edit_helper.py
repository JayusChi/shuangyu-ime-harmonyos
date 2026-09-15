from pathlib import Path
import os

def edit(name,pairs):
 p=Path(name); data=p.read_text(encoding='utf-8'); target=Path('outputs/customer-keyboard-feedback-20260911/before')/name
 if not target.exists():
  target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(p.read_bytes())
 for old,new in pairs:
  assert old in data,(name,old); data=data.replace(old,new,1)
 temp=p.with_name(p.name+'.feedback-tmp')
 with temp.open('xb') as output: output.write(data.replace('\n','\r\n').encode('utf-8'))
 os.replace(temp,p)
