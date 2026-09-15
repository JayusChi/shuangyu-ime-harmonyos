from pathlib import Path
import difflib
import json

root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent
before = out / 'before'
paths = {p.relative_to(before).as_posix() for p in before.rglob('*') if p.is_file()}
paths.update([
    'engine-rust/crates/ime-engine/examples/xiaohe_sentence_inspect.rs',
    'engine-rust/crates/ime-engine/tests/xiaohe_fixed_words.rs',
    'docs/evidence/2026-09-14-shuangpin-fixed-words/README.md',
])
diffs = []
changed = []
for rel in sorted(paths):
    current = root / rel
    if not current.exists():
        continue
    old = (before / rel).read_text(encoding='utf-8-sig') if (before / rel).exists() else ''
    new = current.read_text(encoding='utf-8-sig')
    if old == new:
        continue
    delta = list(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                    fromfile='before/' + rel, tofile='after/' + rel))
    diffs.extend(delta)
    changed.append({'file': rel, 'added': sum(s.startswith('+') and not s.startswith('+++') for s in delta),
                    'removed': sum(s.startswith('-') and not s.startswith('---') for s in delta)})
(out / 'changes.diff').write_text(''.join(diffs), encoding='utf-8')
(out / 'changed-files.json').write_text(json.dumps(changed, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(changed, ensure_ascii=False, indent=2))
