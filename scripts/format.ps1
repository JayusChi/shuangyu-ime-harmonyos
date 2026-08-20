$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'ohos-abi.ps1')
Add-CargoBinToPathIfNeeded

Push-Location (Join-Path $PSScriptRoot '..\engine-rust')
try {
    cargo fmt
    if ($LASTEXITCODE -ne 0) {
        throw "cargo fmt failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$clangFormatPath = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native\llvm\bin\clang-format.exe'
$clangFormat = Get-Command clang-format -ErrorAction SilentlyContinue
if (-not $clangFormat -and (Test-Path $clangFormatPath)) {
    $clangFormat = Get-Item -LiteralPath $clangFormatPath
}

if ($clangFormat) {
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'entry\src\main\cpp') -Recurse -File |
        Where-Object { $_.Extension -in @('.cpp', '.h') } |
        ForEach-Object { & $clangFormat.FullName -i $_.FullName }
} else {
    Write-Host 'SKIPPED clang-format: command not detected.'
}
