from pathlib import Path
import hashlib
import json
import zipfile

root = Path.cwd()
paths = {
    'release': root / 'outputs/release-0.10.0/entry-default.hap',
    'device': root / 'entry/build/default/outputs/default/entry-default-signed.hap',
}
hashes = {}
for label, path in paths.items():
    with zipfile.ZipFile(path) as archive:
        hashes[label] = {
            name: hashlib.sha256(archive.read(name)).hexdigest()
            for name in archive.namelist()
            if not name.endswith('/') and name not in {'.pages.info', 'module.json', 'pack.info'}
        }
different = [
    name for name in hashes['release'].keys() | hashes['device'].keys()
    if hashes['release'].get(name) != hashes['device'].get(name)
]
result = {
    'result': 'IDENTICAL' if not different else 'DIFFERENT_BUILD_PRODUCTS',
    'comparedFiles': len(hashes['release']),
    'comparison': 'Same application source, independently compiled release/default products; byte identity is not assumed',
    'differentFiles': sorted(different),
    'identicalFiles': sum(hashes['release'].get(name) == hashes['device'].get(name) for name in hashes['release']),
    'excludedMetadata': ['.pages.info', 'module.json', 'pack.info'],
    'files': hashes,
}
(root / 'outputs/release-0.10.0/device-payload-comparison.json').write_text(
    json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8'
)
print(json.dumps({key: value for key, value in result.items() if key != 'files'}, ensure_ascii=False))
