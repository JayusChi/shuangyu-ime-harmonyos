param(
    [int]$ProcessSamples = 5,
    [string]$EvidenceDir = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if ([string]::IsNullOrWhiteSpace($EvidenceDir)) {
    $EvidenceDir = Join-Path $repoRoot 'docs\evidence\2026-07-22-stage-11.6.3-formal'
}
New-Item -ItemType Directory -Force $EvidenceDir | Out-Null
$bundle = Join-Path $repoRoot 'dictionaries\generated\xiaohe-yinxing-production\xiaohe-yinxing-production.hsyx'
$manifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'

& cargo build --manifest-path $manifest --release -p code-table-runtime --example production_benchmark
if ($LASTEXITCODE -ne 0) { throw 'Release benchmark build failed' }
$binary = Join-Path $repoRoot 'engine-rust\target\release\examples\production_benchmark.exe'
$samples = @()
for ($index = 1; $index -le $ProcessSamples; $index++) {
    $line = & $binary $bundle
    if ($LASTEXITCODE -ne 0) { throw "Benchmark process $index failed" }
    $sample = $line | ConvertFrom-Json
    $sample | Add-Member -NotePropertyName processSample -NotePropertyValue $index
    $samples += $sample
}

$cargoVersion = (& cargo --version) -join ' '
$rustcVersion = (& rustc --version) -join ' '
$bundleHash = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
$environment = [ordered]@{
    capturedAt = (Get-Date).ToString('o')
    os = [Environment]::OSVersion.VersionString
    architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    processorCount = [Environment]::ProcessorCount
    dotnet = [Environment]::Version.ToString()
    cargo = $cargoVersion
    rustc = $rustcVersion
    profile = 'release'
    cachePolicy = 'fresh-process; operating-system file cache not controlled'
    independentProcessSamples = $ProcessSamples
    bundlePath = $bundle
    bundleBytes = (Get-Item -LiteralPath $bundle).Length
    bundleSha256 = $bundleHash
}
$sortedLoads = @($samples | ForEach-Object { [double]$_.loadNs } | Sort-Object)
$loadP50 = $sortedLoads[[math]::Floor(($sortedLoads.Count - 1) * 0.50)]
$loadP95 = $sortedLoads[[math]::Floor(($sortedLoads.Count - 1) * 0.95)]
$sortedSharedReloads = @($samples | ForEach-Object { [double]$_.sharedReloadNs } | Sort-Object)
$sharedReloadP50 = $sortedSharedReloads[[math]::Floor(($sortedSharedReloads.Count - 1) * 0.50)]
$sortedAfterLoad = @($samples | ForEach-Object { [double]$_.afterLoadBytes } | Sort-Object)
$afterLoadP50 = $sortedAfterLoad[[math]::Floor(($sortedAfterLoad.Count - 1) * 0.50)]
$sortedMemoryDelta = @($samples | ForEach-Object { [double]$_.memoryDeltaBytes } | Sort-Object)
$memoryDeltaP50 = $sortedMemoryDelta[[math]::Floor(($sortedMemoryDelta.Count - 1) * 0.50)]
$report = [ordered]@{
    environment = $environment
    aggregate = [ordered]@{
        loadP50Ns = $loadP50
        loadP95Ns = $loadP95
        loadP50Ms = $loadP50 / 1000000
        loadP95Ms = $loadP95 / 1000000
        sharedReloadP50Ns = $sharedReloadP50
        sharedReloadP50Ms = $sharedReloadP50 / 1000000
        afterLoadP50Bytes = $afterLoadP50
        loadMemoryDeltaP50Bytes = $memoryDeltaP50
        queryP50Ns = [math]::Round(($samples | Measure-Object -Property queryP50Ns -Average).Average)
        queryP95Ns = [math]::Round(($samples | Measure-Object -Property queryP95Ns -Average).Average)
        queryMaxNs = ($samples | Measure-Object -Property queryMaxNs -Maximum).Maximum
        peakMemoryBytes = ($samples | Measure-Object -Property peakMemoryBytes -Maximum).Maximum
        finalMemoryBytes = ($samples | Measure-Object -Property finalMemoryBytes -Maximum).Maximum
    }
    samples = $samples
}
$jsonPath = Join-Path $EvidenceDir 'performance-release.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8

$loadValues = @($samples | ForEach-Object { [double]$_.loadNs })
$queryP95Values = @($samples | ForEach-Object { [double]$_.queryP95Ns })
$stateP95Values = @($samples | ForEach-Object { [double]$_.stateP95Ns })
$memoryValues = @($samples | ForEach-Object { [double]$_.memoryDeltaBytes })
$summary = @(
    '# Xiaohe Yinxing production Release performance evidence'
    ''
    '- Profile: release'
    "- Independent process samples: $ProcessSamples"
    "- Bundle SHA-256: $bundleHash"
    "- Load ns min/avg/max: $([math]::Round(($loadValues | Measure-Object -Minimum).Minimum)) / $([math]::Round(($loadValues | Measure-Object -Average).Average)) / $([math]::Round(($loadValues | Measure-Object -Maximum).Maximum))"
    "- Shared immutable index reload p50 ns: $([math]::Round($sharedReloadP50))"
    "- Query p95 ns min/avg/max: $([math]::Round(($queryP95Values | Measure-Object -Minimum).Minimum)) / $([math]::Round(($queryP95Values | Measure-Object -Average).Average)) / $([math]::Round(($queryP95Values | Measure-Object -Maximum).Maximum))"
    "- State-cycle p95 ns min/avg/max: $([math]::Round(($stateP95Values | Measure-Object -Minimum).Minimum)) / $([math]::Round(($stateP95Values | Measure-Object -Average).Average)) / $([math]::Round(($stateP95Values | Measure-Object -Maximum).Maximum))"
    "- Load memory delta bytes min/avg/max: $([math]::Round(($memoryValues | Measure-Object -Minimum).Minimum)) / $([math]::Round(($memoryValues | Measure-Object -Average).Average)) / $([math]::Round(($memoryValues | Measure-Object -Maximum).Maximum))"
    ''
    'Every process validates fixed query results before timing and accumulates a checksum. Device RSS and latency require the separate ARM64 collector.'
)
$summary | Set-Content -LiteralPath (Join-Path $EvidenceDir 'performance-release.md') -Encoding utf8
Write-Host "STAGE11_6_3_PERFORMANCE_RESULT=PASS"
