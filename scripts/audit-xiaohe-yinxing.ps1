param(
    [switch]$AllowBlocked
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engineRoot = Join-Path $repoRoot 'engine-rust'
$outputRoot = Join-Path $repoRoot 'dictionaries\audit\xiaohe-yinxing'
$reportRoot = Join-Path $repoRoot 'docs\audits\data'
$tableRootName = -join (@(0x7801, 0x8868) | ForEach-Object { [char]$_ })
$yinxingRootName = -join (@(0x5C0F, 0x9E64, 0x97F3, 0x5F62) | ForEach-Object { [char]$_ })
$sourceRoots = @((Join-Path $repoRoot $tableRootName), (Join-Path $repoRoot $yinxingRootName))

function Get-SourceSnapshot {
    $items = foreach ($root in $sourceRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            throw "Missing formal source root: $root"
        }
        Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName | ForEach-Object {
            [pscustomobject]@{
                Path = $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/').Replace('\', '/')
                Size = $_.Length
                Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    }
    return @($items)
}

$before = @(Get-SourceSnapshot)
$arguments = @('run', '--quiet', '--manifest-path', (Join-Path $engineRoot 'Cargo.toml'), '-p', 'yinxing-source-auditor', '--', '--repo-root', $repoRoot, '--output', $outputRoot, '--reports', $reportRoot)
if ($AllowBlocked) { $arguments += '--allow-blocked' }

& cargo @arguments
$auditExit = $LASTEXITCODE
$after = @(Get-SourceSnapshot)
$beforeJson = $before | ConvertTo-Json -Compress
$afterJson = $after | ConvertTo-Json -Compress
if ($beforeJson -cne $afterJson) {
    throw 'SOURCE_IMMUTABILITY_CHECK=FAIL: formal source paths, sizes, or SHA-256 values changed'
}
Write-Host 'SOURCE_IMMUTABILITY_CHECK=PASS'
Write-Host "SOURCE_FILE_COUNT=$($after.Count)"
if ($auditExit -ne 0) { exit $auditExit }
