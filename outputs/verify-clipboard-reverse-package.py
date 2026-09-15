from pathlib import Path
import zipfile, json, hashlib
ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'outputs/record-clipboard-reverse.py').read_text(encoding='utf-8')
exec(source[source.index('hap = ROOT'):])
