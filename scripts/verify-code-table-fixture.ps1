param(
    [switch]$KeepArtifacts
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$manifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'
$tempBase = [IO.Path]::GetFullPath((Join-Path $repoRoot '.stage11_6_2a_verify_tmp'))
if (-not $tempBase.StartsWith($repoRoot.Path, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to manage fixture directory outside the repository: $tempBase"
}
if (Test-Path -LiteralPath $tempBase) {
    Remove-Item -LiteralPath $tempBase -Recurse -Force
}
$first = Join-Path $tempBase 'first'
$second = Join-Path $tempBase 'second'
New-Item -ItemType Directory -Path $first, $second -Force | Out-Null

function Invoke-Cargo([string[]]$Arguments) {
    & cargo @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "cargo failed with exit code ${LASTEXITCODE}: cargo $($Arguments -join ' ')"
    }
}

function Get-RelativeHashes([string]$Root) {
    $result = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
        $result[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $result
}

Push-Location $repoRoot
try {
    $firstWatch = [Diagnostics.Stopwatch]::StartNew()
    Invoke-Cargo @('run', '--quiet', '--manifest-path', $manifest, '-p', 'code-table-fixture-generator', '--', 'all', $first)
    $firstWatch.Stop()
    $secondWatch = [Diagnostics.Stopwatch]::StartNew()
    Invoke-Cargo @('run', '--quiet', '--manifest-path', $manifest, '-p', 'code-table-fixture-generator', '--', 'all', $second)
    $secondWatch.Stop()

    $firstHashes = Get-RelativeHashes $first
    $secondHashes = Get-RelativeHashes $second
    if ($firstHashes.Count -ne $secondHashes.Count) {
        throw "Independent generation produced different file counts: $($firstHashes.Count) vs $($secondHashes.Count)"
    }
    foreach ($relative in $firstHashes.Keys) {
        if (-not $secondHashes.Contains($relative) -or $firstHashes[$relative] -ne $secondHashes[$relative]) {
            throw "Independent generation differs at $relative"
        }
    }

    $firstBundle = Join-Path $first 'binary\code-table-fixture-synthetic.bundle'
    $secondBundle = Join-Path $second 'binary\code-table-fixture-synthetic.bundle'
    Invoke-Cargo @('run', '--quiet', '--manifest-path', $manifest, '-p', 'code-table-fixture-generator', '--', 'verify', $firstBundle)
    Invoke-Cargo @('test', '--manifest-path', $manifest, '-p', 'code-table-fixture-generator')
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-release-hap.ps1') -ResourceInputOnly
    if ($LASTEXITCODE -ne 0) { throw 'Release resource-input gate failed.' }

    $firstHash = (Get-FileHash -LiteralPath $firstBundle -Algorithm SHA256).Hash
    $secondHash = (Get-FileHash -LiteralPath $secondBundle -Algorithm SHA256).Hash
    if ($firstHash -ne $secondHash) { throw 'Independent fixture bundle SHA-256 values differ.' }
    $bundle = Get-Item -LiteralPath $firstBundle
    Write-Host 'CODE_TABLE_FIXTURE_VERIFY_RESULT=PASS'
    Write-Host "GENERATED_FILE_COUNT=$($firstHashes.Count)"
    Write-Host "FIRST_TOTAL_MILLIS=$($firstWatch.ElapsedMilliseconds)"
    Write-Host "SECOND_TOTAL_MILLIS=$($secondWatch.ElapsedMilliseconds)"
    Write-Host "BUNDLE_BYTES=$($bundle.Length)"
    Write-Host "FIRST_BUNDLE_SHA256=$firstHash"
    Write-Host "SECOND_BUNDLE_SHA256=$secondHash"
    Write-Host 'PEAK_MEMORY=UNAVAILABLE (no stable cross-platform measurement in current toolchain)'
} finally {
    Pop-Location
    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $tempBase)) {
        Remove-Item -LiteralPath $tempBase -Recurse -Force
    } elseif ($KeepArtifacts) {
        Write-Host "ARTIFACT_ROOT=$tempBase"
    }
}
