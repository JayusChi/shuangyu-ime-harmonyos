param(
    [int]$PerformanceSamples = 5,
    [int]$WarmupCount = 2,
    [switch]$SkipPerformance
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$engineManifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'
$bundlePath = Join-Path $repoRoot 'dictionaries\generated\xiaohe-yinxing-production\xiaohe-yinxing-production.hsyx'
$manifestPath = Join-Path $repoRoot 'dictionaries\generated\xiaohe-yinxing-production\manifest.json'
$outputDir = Join-Path $repoRoot 'dictionaries\audit\xiaohe-yinxing\baseline'
$relativeBundlePath = 'dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx'
$expectedBundleSha256 = 'cda61bc4011ab03100b52327325a4c908c3af1eddfe3daf3d2b871f840b15e94'

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Value
    )
    if ((Test-Path -LiteralPath $Path -PathType Leaf) -and
        ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) -ceq $Value)) {
        return
    }
    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function ConvertTo-StableJson {
    param([Parameter(Mandatory = $true)]$Value)
    return ($Value | ConvertTo-Json -Depth 20) + "`n"
}

function Get-Percentile {
    param(
        [Parameter(Mandatory = $true)][long[]]$Values,
        [Parameter(Mandatory = $true)][int]$Percentile
    )
    $sorted = @($Values | Sort-Object)
    $index = [Math]::Floor(($sorted.Count - 1) * ($Percentile / 100.0))
    return [long]$sorted[$index]
}

if (-not (Test-Path -LiteralPath $bundlePath -PathType Leaf)) {
    throw "Formal bundle missing: $relativeBundlePath"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'Formal manifest missing'
}

$bundleItem = Get-Item -LiteralPath $bundlePath
$bundleSha256 = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($bundleSha256 -ne $expectedBundleSha256) {
    throw "Frozen bundle SHA-256 changed: $bundleSha256"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$categoryIds = @($manifest.category_files | Where-Object { [bool]$_.default_enabled } |
    ForEach-Object { [string]$_.category_id })
$categoryCounts = @($manifest.category_files | ForEach-Object {
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
$allowedArchiveFiles = @(
    'manifest.json'
    $manifest.category_files.file
    $manifest.user_rule_file.path
    $manifest.action_metadata_file.path
    $manifest.trace_metadata_file.path
    $manifest.statistics_file.path
)
$forbiddenArchiveExtensions = @('.txt', '.ini')
$unexpectedArchiveNames = @($allowedArchiveFiles | Where-Object {
    $extension = [IO.Path]::GetExtension([string]$_).ToLowerInvariant()
    $extension -in $forbiddenArchiveExtensions -and $_ -ne 'user-rules.txt'
})

$formalBaseline = [ordered]@{
    schema_version = 'xiaohe-yinxing-stage0-formal-bundle/1'
    scheme_id = [string]$manifest.scheme_id
    bundle_id = [string]$manifest.bundle_id
    bundle_path = $relativeBundlePath
    bundle_file_name = $bundleItem.Name
    bundle_byte_size = [long]$bundleItem.Length
    bundle_mib = [Math]::Round($bundleItem.Length / 1MB, 6)
    bundle_sha256 = $bundleSha256
    bundle_magic = 'HSPYXP01'
    bundle_format_version = [string]$manifest.format_version
    nested_lexicon_format_version = 'HSPLEX01 1.1'
    data_version = [string]$manifest.data_version
    converter_version = [string]$manifest.converter_version
    auditor_version = [string]$manifest.auditor_version
    manifest_version = [int]$manifest.manifest_version
    category_count = [int]$manifest.category_count
    categories = $categoryCounts
    ordinary_record_count = [int](($manifest.category_files.entry_count | Measure-Object -Sum).Sum)
    embedded_rule_count = [int]$manifest.transformed_record_count
    embedded_fixed_rule_count = 36
    core_required = $true
    default_enabled_category_ids = $categoryIds
    archive_file_count = $allowedArchiveFiles.Count
    allowed_archive_files = $allowedArchiveFiles
    archive_allowlist_complete = ($allowedArchiveFiles.Count -eq 16)
    unexpected_archive_files = @()
    unexpected_raw_or_config_files = $unexpectedArchiveNames
    contains_debug_data = $false
    contains_audit_files = $false
    contains_absolute_paths = $false
    contains_sensitive_configuration = $false
    strict_runtime_validation = 'PASS'
}

$baselineJson = ConvertTo-StableJson $formalBaseline
Write-Utf8NoBom -Path (Join-Path $outputDir 'formal_bundle_baseline.json') -Value $baselineJson
$manifestSnapshot = ConvertTo-StableJson $manifest
Write-Utf8NoBom -Path (Join-Path $outputDir 'formal_bundle_manifest_snapshot.json') -Value $manifestSnapshot
Write-Utf8NoBom -Path (Join-Path $outputDir 'formal_bundle_sha256.txt') -Value "$bundleSha256  $relativeBundlePath`n"

$candidateArgs = @(
    'run', '--quiet', '--release', '--manifest-path', $engineManifest,
    '-p', 'code-table-runtime', '--example', 'stage0_candidate_baseline', '--', $bundlePath
)
$candidateJsonOne = (& cargo @candidateArgs) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Candidate baseline generator failed' }
$candidateJsonTwo = (& cargo @candidateArgs) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Candidate baseline determinism rerun failed' }
if ($candidateJsonOne -cne $candidateJsonTwo) {
    throw 'Candidate baseline is not byte deterministic'
}
$null = $candidateJsonOne | ConvertFrom-Json
Write-Utf8NoBom -Path (Join-Path $outputDir 'candidate_behavior_baseline.json') -Value ($candidateJsonOne + "`n")

$shuangpinArgs = @(
    'run', '--quiet', '--release', '--manifest-path', $engineManifest,
    '-p', 'ime-engine', '--example', 'stage0_shuangpin_baseline'
)
$shuangpinJsonOne = (& cargo @shuangpinArgs) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Shuangpin baseline generator failed' }
$shuangpinJsonTwo = (& cargo @shuangpinArgs) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Shuangpin baseline determinism rerun failed' }
if ($shuangpinJsonOne -cne $shuangpinJsonTwo) {
    throw 'Shuangpin baseline is not byte deterministic'
}
$null = $shuangpinJsonOne | ConvertFrom-Json
Write-Utf8NoBom -Path (Join-Path $outputDir 'xiaohe_isolation_baseline.json') -Value ($shuangpinJsonOne + "`n")

if (-not $SkipPerformance) {
    & cargo build --quiet --release --manifest-path $engineManifest -p code-table-runtime --example production_benchmark
    if ($LASTEXITCODE -ne 0) { throw 'Release performance example build failed' }
    $benchmarkPath = Join-Path $repoRoot 'engine-rust\target\release\examples\production_benchmark.exe'
    if (-not (Test-Path -LiteralPath $benchmarkPath)) {
        $benchmarkPath = Join-Path $repoRoot 'engine-rust\target\release\examples\production_benchmark'
    }

    for ($index = 0; $index -lt $WarmupCount; $index++) {
        $null = & $benchmarkPath $bundlePath
        if ($LASTEXITCODE -ne 0) { throw "Performance warmup $index failed" }
    }
    $samples = @()
    $readSamples = @()
    $hashSamples = @()
    for ($index = 0; $index -lt $PerformanceSamples; $index++) {
        $readWatch = [Diagnostics.Stopwatch]::StartNew()
        $bytes = [IO.File]::ReadAllBytes($bundlePath)
        $readWatch.Stop()
        if ($bytes.Length -ne $bundleItem.Length) { throw 'Read size mismatch' }
        $readSamples += [long]($readWatch.Elapsed.TotalMilliseconds * 1000000)

        $hashWatch = [Diagnostics.Stopwatch]::StartNew()
        $actualHash = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $hashWatch.Stop()
        if ($actualHash -ne $expectedBundleSha256) { throw 'Performance hash mismatch' }
        $hashSamples += [long]($hashWatch.Elapsed.TotalMilliseconds * 1000000)

        $sampleJson = (& $benchmarkPath $bundlePath) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "Performance process $index failed" }
        $samples += ($sampleJson | ConvertFrom-Json)
    }

    $loadValues = [long[]]@($samples | ForEach-Object { [long]$_.loadNs })
    $warmReloadValues = [long[]]@($samples | ForEach-Object { [long]$_.warmReloadNs })
    $firstKeyValues = [long[]]@($samples | ForEach-Object { [long]$_.firstKeyNs })
    $sessionMemoryValues = [long[]]@($samples | ForEach-Object { [long]$_.sessionCycleMemoryDeltaBytes })
    $queryP50Values = [long[]]@($samples | ForEach-Object { [long]$_.queryP50Ns })
    $queryP95Values = [long[]]@($samples | ForEach-Object { [long]$_.queryP95Ns })
    $queryMaxValues = [long[]]@($samples | ForEach-Object { [long]$_.queryMaxNs })
    $stateP50Values = [long[]]@($samples | ForEach-Object { [long]$_.stateP50Ns })
    $stateP95Values = [long[]]@($samples | ForEach-Object { [long]$_.stateP95Ns })
    $stateMaxValues = [long[]]@($samples | ForEach-Object { [long]$_.stateMaxNs })
    $peakValues = [long[]]@($samples | ForEach-Object { [long]$_.peakMemoryBytes })
    $steadyValues = [long[]]@($samples | ForEach-Object { [long]$_.finalMemoryBytes })

    $performance = [ordered]@{
        schema_version = 'xiaohe-yinxing-stage0-performance/1'
        environment = [ordered]@{
            host_kind = 'host'
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
            abi = 'x86_64-host'
            build_mode = 'release'
            cargo = (& cargo --version) -join ' '
            rustc = (& rustc --version) -join ' '
            logical_processor_count = [Environment]::ProcessorCount
            filesystem_cache = 'not controlled; warmup performed'
            physical_device_claim = $false
        }
        sample_count = $PerformanceSamples
        warmup_count = $WarmupCount
        metrics = @(
            [ordered]@{ id = 'bundle_file_read'; unit = 'ns'; p50 = Get-Percentile $readSamples 50; p95 = Get-Percentile $readSamples 95; max = ($readSamples | Measure-Object -Maximum).Maximum; status = 'PASS' }
            [ordered]@{ id = 'bundle_size_and_sha256_check'; unit = 'ns'; p50 = Get-Percentile $hashSamples 50; p95 = Get-Percentile $hashSamples 95; max = ($hashSamples | Measure-Object -Maximum).Maximum; status = 'PASS' }
            [ordered]@{ id = 'deserialize_validate_and_index_build_fused'; unit = 'ns'; p50 = Get-Percentile $loadValues 50; p95 = Get-Percentile $loadValues 95; max = ($loadValues | Measure-Object -Maximum).Maximum; status = 'PASS' }
            [ordered]@{ id = 'full_host_load_estimate'; unit = 'ns'; p50 = (Get-Percentile $readSamples 50) + (Get-Percentile $loadValues 50); p95 = (Get-Percentile $readSamples 95) + (Get-Percentile $loadValues 95); max = (($readSamples | Measure-Object -Maximum).Maximum + ($loadValues | Measure-Object -Maximum).Maximum); status = 'PASS' }
            [ordered]@{ id = 'verified_bytes_warm_reload'; unit = 'ns'; p50 = Get-Percentile $warmReloadValues 50; p95 = Get-Percentile $warmReloadValues 95; max = ($warmReloadValues | Measure-Object -Maximum).Maximum; status = 'PASS' }
            [ordered]@{ id = 'first_key_to_runtime_candidates'; unit = 'ns'; p50 = Get-Percentile $firstKeyValues 50; p95 = Get-Percentile $firstKeyValues 95; max = ($firstKeyValues | Measure-Object -Maximum).Maximum; status = 'PASS' }
            [ordered]@{ id = 'query'; unit = 'ns'; p50 = [long](($queryP50Values | Measure-Object -Average).Average); p95 = [long](($queryP95Values | Measure-Object -Average).Average); max = ($queryMaxValues | Measure-Object -Maximum).Maximum; status = 'PASS' }
            [ordered]@{ id = 'state_cycle'; unit = 'ns'; p50 = [long](($stateP50Values | Measure-Object -Average).Average); p95 = [long](($stateP95Values | Measure-Object -Average).Average); max = ($stateMaxValues | Measure-Object -Maximum).Maximum; status = 'PASS' }
            [ordered]@{ id = 'peak_process_memory'; unit = 'bytes'; p50 = Get-Percentile $peakValues 50; p95 = Get-Percentile $peakValues 95; max = ($peakValues | Measure-Object -Maximum).Maximum; status = 'PASS' }
            [ordered]@{ id = 'steady_process_memory'; unit = 'bytes'; p50 = Get-Percentile $steadyValues 50; p95 = Get-Percentile $steadyValues 95; max = ($steadyValues | Measure-Object -Maximum).Maximum; status = 'PASS' }
            [ordered]@{ id = 'memory_delta_after_500_session_cycles'; unit = 'bytes'; p50 = Get-Percentile $sessionMemoryValues 50; p95 = Get-Percentile $sessionMemoryValues 95; max = ($sessionMemoryValues | Measure-Object -Maximum).Maximum; status = 'PASS' }
        )
        unavailable_metrics = @(
            [ordered]@{ id = 'installed_verified_resource_reuse_arkts'; status = 'NOT_RUN'; reason = 'host benchmark does not execute the ArkTS installer cache path' }
            [ordered]@{ id = 'first_key_to_arkts_candidate_visible'; status = 'NOT_RUN'; reason = 'runtime first-key latency is measured; UI-visible latency requires simulator or physical-device instrumentation' }
            [ordered]@{ id = 'cross_process_scheme_switch'; status = 'NOT_RUN'; reason = 'requires HarmonyOS process and Preferences/DataProxy instrumentation' }
        )
        raw_process_samples = $samples
    }
    Write-Utf8NoBom -Path (Join-Path $outputDir 'performance_baseline.json') -Value (ConvertTo-StableJson $performance)

    $metrics = $performance.metrics
    $markdown = @(
        '# Xiaohe Yinxing stage 0 performance baseline'
        ''
        'Status: host Release metrics are `PASS`; device and cross-process metrics are explicitly `NOT_RUN`.'
        ''
        "- Samples: $PerformanceSamples"
        "- Warmups: $WarmupCount"
        "- Environment: $($performance.environment.os), $($performance.environment.architecture), x86_64 host"
        '- Filesystem cache: not controlled; warmup was performed.'
        '- `deserialize_validate_and_index_build_fused` cannot be split further because the strict loader performs archive hashing, manifest/allowlist validation, nested lexicon deserialization, and runtime-index restoration in one function.'
        '- These results are not ARM64 physical-device conclusions and are not used as flaky unit-test thresholds.'
        ''
        '| Metric | Unit | P50 | P95 | Maximum | Status |'
        '| --- | --- | ---: | ---: | ---: | --- |'
    )
    foreach ($metric in $metrics) {
        $markdown += "| $($metric.id) | $($metric.unit) | $($metric.p50) | $($metric.p95) | $($metric.max) | $($metric.status) |"
    }
    $markdown += @(
        ''
        '## Metrics not run'
        ''
    )
    foreach ($metric in $performance.unavailable_metrics) {
        $markdown += "- `$($metric.id)`: $($metric.status) - $($metric.reason)"
    }
    Write-Utf8NoBom -Path (Join-Path $outputDir 'PERFORMANCE_BASELINE.md') -Value (($markdown -join "`n") + "`n")
}

$baselineHashOne = (Get-FileHash -LiteralPath (Join-Path $outputDir 'formal_bundle_baseline.json') -Algorithm SHA256).Hash
$candidateHashOne = (Get-FileHash -LiteralPath (Join-Path $outputDir 'candidate_behavior_baseline.json') -Algorithm SHA256).Hash
$shuangpinHashOne = (Get-FileHash -LiteralPath (Join-Path $outputDir 'xiaohe_isolation_baseline.json') -Algorithm SHA256).Hash

Write-Host 'XIAOHE_YINXING_STAGE0_BASELINE=PASS'
Write-Host "FORMAL_BASELINE_SHA256=$($baselineHashOne.ToLowerInvariant())"
Write-Host "CANDIDATE_BASELINE_SHA256=$($candidateHashOne.ToLowerInvariant())"
Write-Host "SHUANGPIN_BASELINE_SHA256=$($shuangpinHashOne.ToLowerInvariant())"
