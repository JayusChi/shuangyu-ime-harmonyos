import sys
from pathlib import Path
sys.path.insert(0, str(Path('outputs/device-acceptance-20260907').resolve()))
from device import Device
d=Device('computer')
d.target='127.0.0.1:5555'
d.out=Path('outputs/reverse-split-reaccept-20260908').resolve()
d.show('acceptance-open', True)
