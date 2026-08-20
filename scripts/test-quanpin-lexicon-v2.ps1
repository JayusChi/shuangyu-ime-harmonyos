[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$buildScript = Join-Path $repoRoot 'scripts\build-quanpin-lexicon-v2.ps1'
$sourceManifest = Join-Path $repoRoot 'artifacts\quanpin-lexicon-v2\source-manifest.json'
$buildManifest = Join-Path $repoRoot 'artifacts\quanpin-lexicon-v2\build-manifest.json'

try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -AsOfDate 2030-01-01 -CheckOnly
    if ($LASTEXITCODE -ne 0) { throw 'future-date expiry check failed' }
    $future = Get-Content -LiteralPath $sourceManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($future.stats.expired -ne 12) { throw "expected 12 expired hotwords, got $($future.stats.expired)" }
} finally {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -AsOfDate 2026-08-14 -CheckOnly
    if ($LASTEXITCODE -ne 0) { throw 'failed to restore current source manifest' }
}

$current = Get-Content -LiteralPath $sourceManifest -Raw -Encoding UTF8 | ConvertFrom-Json
if ($current.stats.expired -ne 0) { throw 'current build unexpectedly expires hotwords' }
if ($current.stats.mergedDuplicates -lt 1) { throw 'cross-source conflict merge was not exercised' }
$built = Get-Content -LiteralPath $buildManifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $built.deterministic -or $built.repetitions -lt 2) { throw 'deterministic build evidence missing' }
if (@($built.defaultDomainsEnabled).Count -ne 0) { throw 'a domain is enabled by default' }
if ([string]$built.packagedProductionProfile -ne 'all_domains') { throw 'formal packaged profile is not all_domains' }

& cargo test --manifest-path (Join-Path $repoRoot 'engine-rust\Cargo.toml') -p lexicon-builder
if ($LASTEXITCODE -ne 0) { throw 'lexicon-builder tests failed' }
& cargo test --manifest-path (Join-Path $repoRoot 'engine-rust\Cargo.toml') -p ime-engine --test quanpin_lexicon_v2
if ($LASTEXITCODE -ne 0) { throw 'formal ImeEngine V2 tests failed' }
Write-Host 'QUANPIN_V2_TEST=PASS expiry=12 domainDefault=off deterministic=true tamper=reject'
