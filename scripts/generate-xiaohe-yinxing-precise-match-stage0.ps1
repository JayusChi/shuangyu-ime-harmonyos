param(
    [int]$PerformanceSamples = 10,
    [int]$WarmupCount = 3,
    [switch]$SkipPerformance
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$engineManifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'
$lexiconPath = Join-Path $repoRoot 'dictionaries\generated\production.lex'
$bundlePath = Join-Path $repoRoot 'dictionaries\generated\xiaohe-yinxing-production\xiaohe-yinxing-production.hsyx'
$manifestPath = Join-Path $repoRoot 'dictionaries\generated\xiaohe-yinxing-production\manifest.json'
$modulePath = Join-Path $repoRoot 'entry\src\main\module.json5'
$legacyBehaviorPath = Join-Path $repoRoot 'dictionaries\audit\xiaohe-yinxing\baseline\candidate_behavior_baseline.json'
$outputDir = Join-Path $repoRoot 'dictionaries\audit\xiaohe-yinxing\precise-match-stage0'
$expectedBundleBytes = 25397952
$expectedBundleSha256 = '00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30'

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Value
    )
    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function ConvertTo-StableJson {
    param([Parameter(Mandatory = $true)]$Value)
    return ($Value | ConvertTo-Json -Depth 30) + "`n"
}

function Get-RelativeHashRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )
    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        path = $RelativePath
        bytes = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

foreach ($required in @($engineManifest, $lexiconPath, $bundlePath, $manifestPath, $modulePath, $legacyBehaviorPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required stage 0 input is missing: $required"
    }
}

$bundleItem = Get-Item -LiteralPath $bundlePath
$bundleSha256 = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($bundleItem.Length -ne $expectedBundleBytes) {
    throw "Frozen bundle size changed: $($bundleItem.Length)"
}
if ($bundleSha256 -ne $expectedBundleSha256) {
    throw "Frozen bundle SHA-256 changed: $bundleSha256"
}

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$moduleText = Get-Content -LiteralPath $modulePath -Raw -Encoding UTF8
$permissions = @([regex]::Matches($moduleText, 'ohos\.permission\.[A-Z_]+') | ForEach-Object Value | Sort-Object -Unique)
$categories = @($manifest.category_files | ForEach-Object {
    [ordered]@{
        category_id = [string]$_.category_id
        display_name = [string]$_.display_name
        order = [int]$_.order
        entry_count = [int]$_.entry_count
        default_enabled = [bool]$_.default_enabled
        required = ([string]$_.category_id -eq 'core')
        file = [string]$_.file
        sha256 = [string]$_.sha256
    }
})
$formal = [ordered]@{
    schema_version = 'xiaohe-yinxing-precise-match-stage0-formal/1'
    scheme_id = [string]$manifest.scheme_id
    bundle_id = [string]$manifest.bundle_id
    bundle_path = 'dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx'
    bundle_byte_size = [long]$bundleItem.Length
    bundle_sha256 = $bundleSha256
    manifest_sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    bundle_magic = 'HSPYXP01'
    bundle_format_version = [string]$manifest.format_version
    data_version = [string]$manifest.data_version
    category_count = [int]$manifest.category_count
    ordinary_record_count = [int](($manifest.category_files.entry_count | Measure-Object -Sum).Sum)
    embedded_rule_count = [int]$manifest.transformed_record_count
    categories = $categories
    requested_permissions = $permissions
    network_permission_present = [bool]($permissions -contains 'ohos.permission.INTERNET')
}
$formalPath = Join-Path $outputDir 'formal_bundle_baseline.json'
Write-Utf8NoBom -Path $formalPath -Value (ConvertTo-StableJson $formal)

$manifestSnapshotPath = Join-Path $outputDir 'formal_bundle_manifest_snapshot.json'
Write-Utf8NoBom -Path $manifestSnapshotPath -Value (ConvertTo-StableJson $manifest)

$behaviorArgs = @(
    'run', '--quiet', '--release', '--manifest-path', $engineManifest,
    '-p', 'ime-engine', '--example', 'precise_match_stage0_baseline', '--', $bundlePath
)
$behaviorOne = (& cargo @behaviorArgs) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Progressive behavior baseline generation failed' }
$behaviorTwo = (& cargo @behaviorArgs) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Progressive behavior determinism rerun failed' }
if ($behaviorOne -cne $behaviorTwo) {
    throw 'Progressive behavior baseline is not byte deterministic'
}
$null = $behaviorOne | ConvertFrom-Json
$behaviorPath = Join-Path $outputDir 'progressive_behavior_baseline.json'
Write-Utf8NoBom -Path $behaviorPath -Value ($behaviorOne + "`n")

$shuangpinArgs = @(
    'run', '--quiet', '--release', '--manifest-path', $engineManifest,
    '-p', 'ime-engine', '--example', 'stage0_shuangpin_baseline'
)
$shuangpinOne = (& cargo @shuangpinArgs) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Xiaohe isolation baseline generation failed' }
$shuangpinTwo = (& cargo @shuangpinArgs) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Xiaohe isolation determinism rerun failed' }
if ($shuangpinOne -cne $shuangpinTwo) {
    throw 'Xiaohe isolation baseline is not byte deterministic'
}
$null = $shuangpinOne | ConvertFrom-Json
$shuangpinPath = Join-Path $outputDir 'xiaohe_isolation_baseline.json'
Write-Utf8NoBom -Path $shuangpinPath -Value ($shuangpinOne + "`n")

$compatibility = [ordered]@{
    schema_version = 'xiaohe-yinxing-precise-match-stage0-compatibility/1'
    four_code_query_semantics = 'ProgressiveXiaoheYinxing delegates four-code queries to ExactOnly; the referenced committed exact-path baseline remains applicable.'
    referenced_baseline = Get-RelativeHashRecord -Path $legacyBehaviorPath -RelativePath 'dictionaries/audit/xiaohe-yinxing/baseline/candidate_behavior_baseline.json'
    covered_behavior = @(
        'four-code unique auto-commit'
        'four-code multiple candidates'
        'empty/no-result handling'
        'embedded and external #delete/#fixed/#N user rules'
        'category filtering before uniqueness and paging'
    )
    regression_test = 'cargo test --manifest-path engine-rust/Cargo.toml -p code-table-runtime --test stage0_baseline'
}
$compatibilityPath = Join-Path $outputDir 'four_code_user_rule_compatibility.json'
Write-Utf8NoBom -Path $compatibilityPath -Value (ConvertTo-StableJson $compatibility)

$performancePath = Join-Path $outputDir 'performance_baseline.json'
if (-not $SkipPerformance) {
    $performanceArgs = @(
        'run', '--quiet', '--release', '--manifest-path', $engineManifest,
        '-p', 'candidate-baseline', '--', 'performance-page-size',
        $lexiconPath, $bundlePath, '50', $WarmupCount, $PerformanceSamples
    )
    $performanceJson = (& cargo @performanceArgs) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Progressive performance baseline generation failed' }
    $null = $performanceJson | ConvertFrom-Json
    Write-Utf8NoBom -Path $performancePath -Value ($performanceJson + "`n")
}

$deterministicFiles = @(
    Get-RelativeHashRecord -Path $formalPath -RelativePath 'dictionaries/audit/xiaohe-yinxing/precise-match-stage0/formal_bundle_baseline.json'
    Get-RelativeHashRecord -Path $manifestSnapshotPath -RelativePath 'dictionaries/audit/xiaohe-yinxing/precise-match-stage0/formal_bundle_manifest_snapshot.json'
    Get-RelativeHashRecord -Path $behaviorPath -RelativePath 'dictionaries/audit/xiaohe-yinxing/precise-match-stage0/progressive_behavior_baseline.json'
    Get-RelativeHashRecord -Path $shuangpinPath -RelativePath 'dictionaries/audit/xiaohe-yinxing/precise-match-stage0/xiaohe_isolation_baseline.json'
    Get-RelativeHashRecord -Path $compatibilityPath -RelativePath 'dictionaries/audit/xiaohe-yinxing/precise-match-stage0/four_code_user_rule_compatibility.json'
)
$index = [ordered]@{
    schema_version = 'xiaohe-yinxing-precise-match-stage0-index/1'
    deterministic_generation = 'PASS'
    formal_data_modified = $false
    deterministic_files = $deterministicFiles
    performance_file = if (Test-Path -LiteralPath $performancePath -PathType Leaf) {
        Get-RelativeHashRecord -Path $performancePath -RelativePath 'dictionaries/audit/xiaohe-yinxing/precise-match-stage0/performance_baseline.json'
    } else {
        $null
    }
    performance_is_determinism_gated = $false
}
$indexPath = Join-Path $outputDir 'baseline_index.json'
Write-Utf8NoBom -Path $indexPath -Value (ConvertTo-StableJson $index)

Write-Host 'XIAOHE_YINXING_PRECISE_MATCH_STAGE0=PASS'
Write-Host "BUNDLE_SHA256=$bundleSha256"
Write-Host "PROGRESSIVE_BEHAVIOR_SHA256=$((Get-FileHash -LiteralPath $behaviorPath -Algorithm SHA256).Hash.ToLowerInvariant())"
Write-Host "XIAOHE_ISOLATION_SHA256=$((Get-FileHash -LiteralPath $shuangpinPath -Algorithm SHA256).Hash.ToLowerInvariant())"
if (Test-Path -LiteralPath $performancePath -PathType Leaf) {
    Write-Host "PERFORMANCE_BASELINE=$performancePath"
}
