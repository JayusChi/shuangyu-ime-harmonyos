from pathlib import Path
import hashlib
import json
import re

root = Path.cwd()
out = root / 'outputs/settings-details-unification-20260909'
baseline = json.loads((out / 'source-baseline.json').read_text(encoding='utf-8'))
allowed = {
    'entry/src/main/ets/presentation/settings/SettingsPage.ets',
    'entry/src/main/ets/presentation/settings/KeyboardCustomizationPage.ets',
    'entry/src/main/ets/presentation/settings/UserLexiconPage.ets',
    'entry/src/main/ets/pages/KeyboardCustomization.ets',
    'entry/src/main/ets/pages/UserLexicon.ets',
    'entry/src/main/ets/pages/XiaoheYinxingCategoryManagerPage.ets',
}
changed = [p for p, digest in baseline.items()
           if hashlib.sha256((root / p).read_bytes()).hexdigest() != digest]
assert set(changed) <= allowed, changed

def methods(text):
    return {m.group(1): m.group(0) for m in re.finditer(
        r'^  (?:private )?(?:async )?(\w+)\([^\n]*\)[^\n]*\{\n.*?^  \}',
        text, re.MULTILINE | re.DOTALL)
        if m.group(1)[0].islower() and m.group(1) not in {
            'build', 'aboutToAppear', 'aboutToDisappear', 'back', 'goBack'}}

compared = {}
for old, new in [
    ('presentation/settings/KeyboardCustomizationPage.ets', 'presentation/settings/KeyboardCustomizationPage.ets'),
    ('presentation/settings/UserLexiconPage.ets', 'presentation/settings/UserLexiconPage.ets'),
    ('pages/XiaoheYinxingCategoryManagerPage.ets', 'presentation/settings/YinxingCategorySettings.ets'),
]:
    old_text = (out / 'before/entry/src/main/ets' / old).read_text(encoding='utf-8')
    new_text = (root / 'entry/src/main/ets' / new).read_text(encoding='utf-8')
    before, after = methods(old_text), methods(new_text)
    assert before, old
    for name, body in before.items():
        assert after.get(name) == body, f'Business method changed: {old}:{name}'
    compared[old] = list(before)

# Category exit confirmation is reused exactly; only back() dispatches to Navigation.
old_cat = (out / 'before/entry/src/main/ets/pages/XiaoheYinxingCategoryManagerPage.ets').read_text(encoding='utf-8')
new_cat = (root / 'entry/src/main/ets/presentation/settings/YinxingCategorySettings.ets').read_text(encoding='utf-8')
pattern = r'  private goBack\(\): void \{.*?^  \}'
assert re.search(pattern, old_cat, re.S | re.M).group() == re.search(pattern, new_cat, re.S | re.M).group()
result = {
    'result': 'PASS', 'baselineFiles': len(baseline),
    'unchangedExistingFiles': len(baseline)-len(changed), 'changedUiFiles': changed,
    'controllersStorageModelsNativeRustAndRouteManifestUnchanged': True,
    'businessMethodsPreserved': compared, 'categoryExitConfirmationUnchanged': True,
}
(out / 'preservation-result.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps({'result': 'PASS', 'unchangedFiles': result['unchangedExistingFiles'],
                  'businessMethodCounts': {k: len(v) for k, v in compared.items()}}, ensure_ascii=False))
