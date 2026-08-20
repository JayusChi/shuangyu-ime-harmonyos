param(
    [switch]$ConfirmClean
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$targets = @(
    (Join-Path $repoRoot 'entry\build'),
    (Join-Path $repoRoot 'engine-rust\target'),
    (Join-Path $repoRoot '.hvigor')
)

if (-not $ConfirmClean) {
    Write-Host 'Dry run. Re-run with -ConfirmClean to remove generated build outputs.'
    $targets | ForEach-Object { Write-Host $_ }
    exit 0
}

foreach ($target in $targets) {
    if (Test-Path $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
        Write-Host "Removed: $target"
    }
}
