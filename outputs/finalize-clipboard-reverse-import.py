from pathlib import Path
exec((Path(__file__).parent / 'implement-clipboard-reverse.py').read_text(encoding='utf-8').split("replace('engine-rust/crates/code-table-runtime/src/state.rs'")[0])
replace('scripts/import-shuangyu-customer-lexicon.ps1', '    [IO.File]::WriteAllText($Path, $text, $utf8NoBom)', '''    # Avoid truncating files currently mapped by the editor or build tools.
    # Identical output keeps its timestamp; changed output replaces one file atomically.
    $targetPath = [IO.Path]::GetFullPath($Path)
    if ([IO.File]::Exists($targetPath) -and
        ([IO.FileInfo]$targetPath).Length -eq $utf8NoBom.GetByteCount($text) -and
        [IO.File]::ReadAllText($targetPath, $strictUtf8) -ceq $text) {
        return
    }
    $temporaryPath = $targetPath + '.import-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    if ([IO.Path]::GetDirectoryName($temporaryPath) -cne [IO.Path]::GetDirectoryName($targetPath)) {
        throw 'Temporary import output must stay in the target directory'
    }
    try {
        [IO.File]::WriteAllText($temporaryPath, $text, $utf8NoBom)
        if ([IO.File]::Exists($targetPath)) {
            [IO.File]::Replace($temporaryPath, $targetPath, $null)
        } else {
            [IO.File]::Move($temporaryPath, $targetPath)
        }
    } finally {
        if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
    }''')
