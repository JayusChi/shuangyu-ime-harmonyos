param(
    [int]$PerformanceWarmups = 10,
    [int]$PerformanceSamples = 100,
    [switch]$SkipPerformance
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$engineManifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'
$lexiconPath = Join-Path $repoRoot 'dictionaries\generated\production.lex'
$bundlePath = Join-Path $repoRoot 'dictionaries\generated\xiaohe-yinxing-production\xiaohe-yinxing-production.hsyx'
$outputDir = Join-Path $repoRoot 'artifacts\candidate-baseline'
$docsPath = Join-Path $repoRoot 'docs\candidate-baseline.md'
$runRoot = Join-Path $outputDir ('.work-' + [Guid]::NewGuid().ToString('N'))
$runOne = Join-Path $runRoot 'one'
$runTwo = Join-Path $runRoot 'two'
$stableNames = @(
    'environment.json',
    'flypy-shape-h.json',
    'flypy-double-pinyin-h.json',
    'single-key-baseline.json',
    'double-key-baseline.json',
    'sentence-baseline.json',
    'interaction-baseline.json'
)

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Value
    )
    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function ConvertTo-StableJson {
    param([Parameter(Mandatory = $true)]$Value)
    return ($Value | ConvertTo-Json -Depth 20) + "`n"
}

function Get-RelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $rootText = ([IO.Path]::GetFullPath([string]$repoRoot)).TrimEnd('\', '/')
    $pathText = [IO.Path]::GetFullPath($Path)
    if (-not $pathText.StartsWith($rootText + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        $pathText -cne $rootText) {
        throw "Path is outside repository root: $Path"
    }
    return $pathText.Substring($rootText.Length).TrimStart('\', '/').Replace('\', '/')
}

function Write-EnvironmentSnapshot {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $nativeFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $repoRoot 'entry\build') -Recurse -File -Filter 'libime_bridge.so' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '[\\/]intermediates[\\/]stripped_native_libs[\\/]' } |
            Sort-Object FullName
    )
    $nativeHashes = @($nativeFiles | ForEach-Object {
        [ordered]@{
            path = Get-RelativePath $_.FullName
            byte_size = [long]$_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    $environment = [ordered]@{
        schema_version = 'candidate-baseline/environment/1'
        host = [ordered]@{
            os = [Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
            logical_processor_count = [Environment]::ProcessorCount
            cargo = (& cargo --version) -join ' '
            rustc = (& rustc --version) -join ' '
        }
        application = [ordered]@{
            bundle_name = 'com.corrosion.shuangyuime'
            version_code = 1000000
            version_name = '0.1.0'
            engine_version = '0.0.1-pinyin-stage1'
        }
        resources = @(
            [ordered]@{
                id = 'archived-v115-double-pinyin-lexicon'
                path = 'dictionaries/generated/production.lex'
                byte_size = (Get-Item -LiteralPath $lexiconPath).Length
                sha256 = (Get-FileHash -LiteralPath $lexiconPath -Algorithm SHA256).Hash.ToLowerInvariant()
            },
            [ordered]@{
                id = 'production-flypy-shape-bundle'
                path = 'dictionaries/generated/xiaohe-yinxing-production/xiaohe-yinxing-production.hsyx'
                byte_size = (Get-Item -LiteralPath $bundlePath).Length
                sha256 = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        )
        page_size_contract = [ordered]@{
            arkts_requested_page_size = 50
            rust_default_page_size = 5
            rust_max_page_size = 9
            production_effective_page_size = 9
            normalization = 'min(caller_request, rust_max_page_size)'
        }
        environment_page_sizes = @(
            [ordered]@{
                environment = 'Phone'
                source_level_effective_page_size = 9
                actual_device_measurement = 'NOT_RUN'
                reason = 'No Phone simulator or physical device was attached during this host baseline run.'
            },
            [ordered]@{
                environment = 'Pad'
                source_level_effective_page_size = 9
                actual_device_measurement = 'NOT_RUN'
                reason = 'No Pad simulator or physical device was attached during this host baseline run.'
            },
            [ordered]@{
                environment = 'Debug'
                source_level_effective_page_size = 9
                actual_installed_build_measurement = 'NOT_RUN'
                reason = 'Debug and Release share EngineCoordinator and Rust QueryConfig; an installed Debug package was not instrumented.'
            },
            [ordered]@{
                environment = 'Release'
                source_level_effective_page_size = 9
                actual_installed_build_measurement = 'NOT_RUN'
                reason = 'Debug and Release share EngineCoordinator and Rust QueryConfig; an installed Release package was not instrumented.'
            }
        )
        native_libraries = $nativeHashes
        native_library_status = if ($nativeHashes.Count -gt 0) { 'HASHED_EXISTING_BUILD_ARTIFACTS' } else { 'NOT_AVAILABLE' }
        deterministic_fields_exclude = @('timestamp', 'temporary_directory', 'absolute_path')
    }
    Write-Utf8NoBom -Path (Join-Path $Directory 'environment.json') -Value (ConvertTo-StableJson $environment)
}

if (-not (Test-Path -LiteralPath $lexiconPath -PathType Leaf)) {
    throw "Archived V115 double-pinyin lexicon is missing: $lexiconPath"
}
if (-not (Test-Path -LiteralPath $bundlePath -PathType Leaf)) {
    throw "Production flypy-shape bundle is missing: $bundlePath"
}
if ($PerformanceWarmups -lt 0 -or $PerformanceSamples -le 0) {
    throw 'PerformanceWarmups must be non-negative and PerformanceSamples must be positive.'
}

New-Item -ItemType Directory -Force -Path $runOne, $runTwo | Out-Null

try {
    foreach ($run in @($runOne, $runTwo)) {
        & cargo run --quiet --release --manifest-path $engineManifest -p candidate-baseline -- `
            stable $lexiconPath $bundlePath $run
        if ($LASTEXITCODE -ne 0) {
            throw "Stable candidate baseline generation failed for $run"
        }
        Write-EnvironmentSnapshot -Directory $run
    }

    $determinism = @()
    foreach ($name in $stableNames) {
        $firstPath = Join-Path $runOne $name
        $secondPath = Join-Path $runTwo $name
        if (-not (Test-Path -LiteralPath $firstPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $secondPath -PathType Leaf)) {
            throw "Missing stable output: $name"
        }
        $firstHash = (Get-FileHash -LiteralPath $firstPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $secondHash = (Get-FileHash -LiteralPath $secondPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($firstHash -cne $secondHash) {
            throw "Byte determinism check failed: $name"
        }
        $determinism += [ordered]@{
            file = $name
            sha256 = $firstHash
            byte_identical_across_two_runs = $true
        }
    }

    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    foreach ($name in $stableNames) {
        Copy-Item -LiteralPath (Join-Path $runOne $name) -Destination (Join-Path $outputDir $name) -Force
    }
    $determinismReport = [ordered]@{
        schema_version = 'candidate-baseline/determinism/1'
        result = 'PASS'
        compared_run_count = 2
        files = $determinism
    }
    Write-Utf8NoBom -Path (Join-Path $outputDir 'determinism.json') -Value (ConvertTo-StableJson $determinismReport)

    if (-not $SkipPerformance) {
        $performanceText = (& cargo run --quiet --release --manifest-path $engineManifest `
            -p candidate-baseline -- performance $lexiconPath $bundlePath `
            $PerformanceWarmups $PerformanceSamples) -join "`n"
        if ($LASTEXITCODE -ne 0) {
            throw 'Candidate performance baseline generation failed.'
        }
        $null = $performanceText | ConvertFrom-Json
        Write-Utf8NoBom -Path (Join-Path $outputDir 'performance-baseline.json') -Value ($performanceText + "`n")
    }

    $shape = Get-Content -LiteralPath (Join-Path $outputDir 'flypy-shape-h.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $doublePinyin = Get-Content -LiteralPath (Join-Path $outputDir 'flypy-double-pinyin-h.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $performance = if (Test-Path -LiteralPath (Join-Path $outputDir 'performance-baseline.json')) {
        Get-Content -LiteralPath (Join-Path $outputDir 'performance-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $null
    }
    $performanceLines = if ($null -eq $performance) {
        @('- Host performance: `NOT_RUN` (`-SkipPerformance`).')
    } else {
        @($performance.metrics | ForEach-Object {
            "- $($_.id): P50 $($_.p50) ns, P95 $($_.p95) ns, max $($_.max) ns"
        })
    }
    $report = @(
        '# Candidate improvement stage 0 baseline'
        ''
        'Status: host-runnable scope completed. Phone, Pad, installed Debug/Release, and ARM64 device measurements were not run.'
        ''
        '## Generation command'
        ''
        '```powershell'
        'powershell -ExecutionPolicy Bypass -File scripts\generate-candidate-baseline.ps1'
        '```'
        ''
        'Deterministic candidate snapshots are generated twice and compared file-by-file with SHA-256. Performance data is excluded from the byte gate because latency and process memory naturally vary.'
        ''
        '## Key results'
        ''
        "- Flypy shape `h`: $($shape.total_candidate_count) complete candidates, $($shape.exact_one_key_count) exact one-key candidates, page size $($shape.page_size), `hasNextPage=$($shape.has_next_page)`."
        "- Flypy shape first 9: $($shape.first_9.text -join ', ')."
        "- Xiaohe double-pinyin production `h*`: $($doublePinyin.production_h_record_count) records and $($doublePinyin.production_h_unique_text_count) unique texts."
        "- Double-pinyin pre-ranking recall: $($doublePinyin.pre_rank_recall_count), scanned from $($doublePinyin.scanned_pinyin_range.first) through $($doublePinyin.scanned_pinyin_range.last)."
        "- `ha/hai`: $($doublePinyin.ha_hai_count)/$($doublePinyin.pre_rank_recall_count), or $($doublePinyin.ha_hai_ratio_percent)%."
        "- Double-pinyin ranked first 9: $($doublePinyin.ranked_first_9.text -join ', ')."
        '- ArkTS requests 50; Rust defaults to 5 and caps at 9; the current production effective page size is 9.'
        ''
        '## Performance summary'
        ''
    ) + $performanceLines + @(
        ''
        '## Environment limitations'
        ''
        '- Actual Phone and Pad package page size, UI-visible latency, and memory: `NOT_RUN`; corresponding simulators or devices are required.'
        '- Installed Debug and Release package page size: `NOT_RUN`; the shared-source contract implies 9.'
        '- ARM64 physical-device performance: `NOT_RUN`.'
        '- Git metadata was unavailable in this execution environment, so a separate stage 0 commit was not created or verified.'
        ''
        '## Stage 1 regression focus'
        ''
        '- Raising the page cap must not alter the global order of the 512-item shape snapshot.'
        '- Requests for both 50 and 9 must remain testable; concatenated pages must not repeat or lose candidates.'
        '- Stage 1 must not also fix double-pinyin recall; the current 100% `ha/hai` bias in the 64-item pool is the stage 3 control.'
        '- Unique four-code auto-commit, multiple four-code candidates, double-pinyin sentences, and partial commit must match these snapshots.'
        ''
        'This stage adds only diagnostics, scripts, tests, and evidence. It does not change production dictionaries, ranking, paging parameters, recall logic, or UI.'
    )
    Write-Utf8NoBom -Path $docsPath -Value (($report -join "`n") + "`n")
} finally {
    $resolvedRunRoot = [IO.Path]::GetFullPath($runRoot)
    $resolvedOutput = [IO.Path]::GetFullPath($outputDir)
    if ($resolvedRunRoot.StartsWith($resolvedOutput + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedRunRoot).StartsWith('.work-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedRunRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'CANDIDATE_BASELINE_STAGE0=PASS'
Write-Host "OUTPUT_DIR=$(Get-RelativePath $outputDir)"
Write-Host "REPORT=$(Get-RelativePath $docsPath)"
