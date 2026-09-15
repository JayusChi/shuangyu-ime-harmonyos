from pathlib import Path
import subprocess
exec((Path(__file__).parent / 'implement-clipboard-reverse.py').read_text(encoding='utf-8').split("replace('engine-rust/crates/code-table-runtime/src/state.rs'")[0])
source = (Path(__file__).parent / 'polish-clipboard-reverse.py').read_text(encoding='utf-8').split('# Format only')[1]
source = source[source.index('def format_region'):]
source = source.replace('    edit(name, formatted)', "    try:\n        edit(name, formatted)\n    except RuntimeError as error:\n        if not str(error).startswith('No change:'): raise")
exec(source)
