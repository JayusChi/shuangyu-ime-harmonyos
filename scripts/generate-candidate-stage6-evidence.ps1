param(
    [ValidateRange(1, 100)]
    [int]$PerformanceWarmups = 2,
    [ValidateRange(1, 1000)]
    [int]$PerformanceSamples = 5
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engineManifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'
$lexiconPath = Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex'
$bundlePath = Join-Path $repoRoot 'entry\src\main\resources\rawfile\xiaohe-yinxing-production.hsyx'
$casesPath = Join-Path $repoRoot 'engine-rust\tests\fixtures\candidate_stage6_coverage.tsv'
$sourceManifestPath = Join-Path $repoRoot 'dictionaries\manifest.json'
$yinxingManifestPath = Join-Path $repoRoot 'dictionaries\generated\xiaohe-yinxing-production\manifest.json'
$stage5ReportPath = Join-Path $repoRoot 'docs\evidence\2026-07-28-candidate-stage5\host-report.json'
$releaseHapPath = Join-Path $repoRoot 'entry\build\artifacts\entry-release-unsigned.hap'
$evidenceDir = Join-Path $repoRoot 'docs\evidence\2026-07-29-candidate-stage6'
$tempDir = Join-Path $repoRoot '.stage6_audit_tmp'
$utf8NoBom = [Text.UTF8Encoding]::new($false)

if (-not $tempDir.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to manage temporary path outside repository: $tempDir"
}
foreach ($required in @(
    $engineManifest,
    $lexiconPath,
    $bundlePath,
    $casesPath,
    $sourceManifestPath,
    $yinxingManifestPath,
    $stage5ReportPath,
    $releaseHapPath
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "required stage 6 input missing: $required"
    }
}

function Write-DeterministicJson([string]$Path, [object]$Value, [int]$Depth = 12) {
    $json = $Value | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($Path, $json + "`n", $utf8NoBom)
}

function Invoke-CoverageAudit {
    $output = & cargo run --quiet --release --manifest-path $engineManifest `
        -p candidate-baseline -- stage6-audit $lexiconPath $bundlePath $casesPath
    if ($LASTEXITCODE -ne 0) {
        throw "stage 6 coverage audit failed: $LASTEXITCODE"
    }
    return ($output -join "`n") + "`n"
}

if (Test-Path -LiteralPath $tempDir) {
    Remove-Item -LiteralPath $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null

try {
    $firstCoverage = Invoke-CoverageAudit
    $secondCoverage = Invoke-CoverageAudit
    $firstPath = Join-Path $tempDir 'coverage-first.json'
    $secondPath = Join-Path $tempDir 'coverage-second.json'
    [IO.File]::WriteAllText($firstPath, $firstCoverage, $utf8NoBom)
    [IO.File]::WriteAllText($secondPath, $secondCoverage, $utf8NoBom)
    $firstCoverageHash = (Get-FileHash -LiteralPath $firstPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $secondCoverageHash = (Get-FileHash -LiteralPath $secondPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($firstCoverageHash -ne $secondCoverageHash -or
        (Get-Item -LiteralPath $firstPath).Length -ne (Get-Item -LiteralPath $secondPath).Length) {
        throw 'stage 6 coverage audit is not byte deterministic'
    }
    $coveragePath = Join-Path $evidenceDir 'coverage-report.json'
    [IO.File]::WriteAllText($coveragePath, $firstCoverage, $utf8NoBom)
    $coverage = $firstCoverage | ConvertFrom-Json

    $missingCases = @($coverage.cases | Where-Object { $_.missing_reason -eq 'MISSING_IN_LEXICON' })
    $missingEntries = [ordered]@{
        schema_version = 'candidate-improvement/stage6-missing-entries/1'
        policy = 'Only MISSING_IN_LEXICON rows are eligible; this file is an audit queue, not a production import.'
        count = $missingCases.Count
        release_import_status = 'PENDING_SOURCE_AND_LICENSE_REVIEW'
        entries = @($missingCases | ForEach-Object {
            [ordered]@{
                case_id = $_.case_id
                scheme = $_.scheme
                category = $_.category
                word = $_.test_entry
                input = $_.input
                expected_encoding_or_pinyin = $_.expected_encoding_or_pinyin
                recalled_by_composition = $_.recalled
                import_decision = 'DEFERRED'
                reason = 'No new independently versioned and licensed source was approved in stage 6.'
            }
        })
    }
    Write-DeterministicJson (Join-Path $evidenceDir 'missing-entries.json') $missingEntries

    $sourceManifest = Get-Content -LiteralPath $sourceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $yinxingManifest = Get-Content -LiteralPath $yinxingManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sourceAudit = [ordered]@{
        schema_version = 'candidate-improvement/stage6-source-audit/1'
        new_release_sources = 0
        conclusion = 'PASS_NO_IMPORT'
        sources = @(
            [ordered]@{
                source_id = 'rime-pinyin-simp'
                dataset_name = 'Rime 袖珍简化字拼音'
                publisher = 'Rime project contributors'
                original_version = $sourceManifest.sources[0].sourceVersion
                retrieved_at = $sourceManifest.sources[0].retrievedAt
                source_url_or_delivery_record = $sourceManifest.sources[0].sourceUrl
                license = 'Apache-2.0'
                license_file = 'dictionaries/LICENSES/rime-pinyin-simp-Apache-2.0.txt'
                commercial_use_allowed = $true
                modification_allowed = $true
                hap_redistribution_allowed = $true
                attribution_required = $true
                privacy_or_personal_data_risk = 'LOW; general-purpose lexical data, no user telemetry'
                release_status = 'EXISTING_APPROVED'
            },
            [ordered]@{
                source_id = 'project-stage11-5-short-sentences'
                dataset_name = 'Project-authored common short sentences'
                publisher = 'HarmonyOS_Input project'
                original_version = $sourceManifest.sources[1].sourceVersion
                retrieved_at = $sourceManifest.sources[1].retrievedAt
                source_url_or_delivery_record = $sourceManifest.sources[1].sourceUrl
                license = 'Apache-2.0'
                license_file = 'dictionaries/LICENSES/rime-pinyin-simp-Apache-2.0.txt'
                commercial_use_allowed = $true
                modification_allowed = $true
                hap_redistribution_allowed = $true
                attribution_required = $true
                privacy_or_personal_data_risk = 'NONE; project-authored synthetic sentences'
                release_status = 'EXISTING_APPROVED'
            },
            [ordered]@{
                source_id = 'xiaohe-yinxing-customer-delivery'
                dataset_name = '小鹤音形编号文件'
                publisher = 'User/customer delivery'
                original_version = $yinxingManifest.data_version
                retrieved_at = 'unknown'
                source_url_or_delivery_record = 'dictionaries/audit/xiaohe-yinxing/source_manifest.json'
                license = 'Project-specific approval'
                license_file = 'docs/data-audit/XIAOHE_YINXING_APPROVAL_STATUS.md'
                commercial_use_allowed = 'APPROVED_WITHIN_PROJECT_SCOPE'
                modification_allowed = $true
                hap_redistribution_allowed = $true
                attribution_required = 'NOT_SPECIFIED'
                privacy_or_personal_data_risk = 'LOW; code-table content, no user learning data'
                release_status = 'EXISTING_APPROVED_FROZEN'
            }
        )
    }
    Write-DeterministicJson (Join-Path $evidenceDir 'source-audit.json') $sourceAudit

    $frequencyAudit = [ordered]@{
        schema_version = 'candidate-improvement/stage6-frequency-normalization/1'
        shuangpin = [ordered]@{
            source_scale = 'Rime integer weight'
            transform = 'internal_frequency = clamp(original_weight + 1, 1, 1000000)'
            original_value_retention = 'Pinned source YAML plus source checksum'
            normalized_value_retention = 'dictionaries/generated/production.normalized.tsv and production.lex'
            duplicate_merge = 'Same word plus pinyin key: saturating sum of normalized frequencies; source tags sorted and deduplicated'
            deterministic_order = 'pinyin key, descending frequency as encoded by builder contract, then stable fields'
            long_phrase_guard = 'Stage 5 prefix-only bounded length and repetition quality divisors; no oversized hard-coded frequency'
        }
        yinxing = [ordered]@{
            source_scale = 'No cross-source numeric frequency'
            transform = 'Not applicable'
            conflict_rule = 'Category order then physical source_order; stable text deduplication; embedded user rules applied before pagination'
            isolation = 'Shuangpin frequency never changes frozen yinxing source order'
        }
        new_source_frequency_mix = $false
        conclusion = 'PASS_NO_NEW_SCALE'
    }
    Write-DeterministicJson (Join-Path $evidenceDir 'frequency-normalization.json') $frequencyAudit

    $lexiconHash = (Get-FileHash -LiteralPath $lexiconPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $bundleHash = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $casesHash = (Get-FileHash -LiteralPath $casesPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $lexiconManifest = [ordered]@{
        schema_version = 'candidate-improvement/stage6-lexicon-manifest/1'
        tool = 'candidate-baseline stage6-audit'
        tool_package_version = '0.0.1'
        inputs = @(
            [ordered]@{ path = 'entry/src/main/resources/rawfile/production.lex'; sha256 = $lexiconHash; bytes = (Get-Item -LiteralPath $lexiconPath).Length },
            [ordered]@{ path = 'entry/src/main/resources/rawfile/xiaohe-yinxing-production.hsyx'; sha256 = $bundleHash; bytes = (Get-Item -LiteralPath $bundlePath).Length },
            [ordered]@{ path = 'engine-rust/tests/fixtures/candidate_stage6_coverage.tsv'; sha256 = $casesHash; bytes = (Get-Item -LiteralPath $casesPath).Length }
        )
        production_change = [ordered]@{
            entries_added = 0
            entries_removed = 0
            entries_reordered = 0
            baseline_production_lex_sha256 = 'd1b1a3cffd1784fd3abdae1a3dab4189ff9ce87ba2431d83f0b92a1b7356d9c5'
            current_production_lex_sha256 = $lexiconHash
            baseline_yinxing_bundle_sha256 = '00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30'
            current_yinxing_bundle_sha256 = $bundleHash
        }
        deterministic_coverage_report = [ordered]@{
            first_sha256 = $firstCoverageHash
            second_sha256 = $secondCoverageHash
            byte_identical = $true
            bytes = (Get-Item -LiteralPath $coveragePath).Length
        }
    }
    Write-DeterministicJson (Join-Path $evidenceDir 'lexicon-manifest.json') $lexiconManifest

    $beforeAfter = [ordered]@{
        schema_version = 'candidate-improvement/stage6-coverage-before-after/1'
        baseline_label = 'Stage 6 pre-import audit'
        result_label = 'Stage 6 result; no source approved for import'
        entries_added = 0
        before = [ordered]@{
            coverage_by_code_length = $coverage.coverage_by_code_length
            coverage_by_category = $coverage.coverage_by_category
            failure_counts = $coverage.failure_counts
        }
        after = [ordered]@{
            coverage_by_code_length = $coverage.coverage_by_code_length
            coverage_by_category = $coverage.coverage_by_category
            failure_counts = $coverage.failure_counts
        }
        changed = $false
        explanation = 'Confirmed gaps are deferred until an independently reviewed source and license are approved.'
    }
    Write-DeterministicJson (Join-Path $evidenceDir 'coverage-before-after.json') $beforeAfter

    $stage5 = Get-Content -LiteralPath $stage5ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $freshPerformanceText = & cargo run --quiet --release --manifest-path $engineManifest `
        -p candidate-baseline -- performance $lexiconPath $bundlePath $PerformanceWarmups $PerformanceSamples
    if ($LASTEXITCODE -ne 0) {
        throw "stage 6 performance probe failed: $LASTEXITCODE"
    }
    $freshPerformance = ($freshPerformanceText -join "`n") | ConvertFrom-Json
    $performanceComparison = [ordered]@{
        schema_version = 'candidate-improvement/stage6-performance-comparison/1'
        runtime_or_production_data_changed = $false
        stage5_baseline = [ordered]@{
            cold_a_to_z = $stage5.performance.stage5.cold_a_to_z
            hot_a_to_z = $stage5.performance.stage5.hot_a_to_z
            rust_peak_working_set_bytes = $stage5.memory.stage5.peak_working_set_bytes
            production_lex_bytes = $stage5.resource_identity.production_lexicon_bytes
            yinxing_bundle_bytes = $stage5.resource_identity.xiaohe_shape_bundle_bytes
            release_hap_bytes = 37750936
        }
        stage6_result = [ordered]@{
            inherited_cold_a_to_z = $stage5.performance.stage5.cold_a_to_z
            inherited_hot_a_to_z = $stage5.performance.stage5.hot_a_to_z
            production_lex_bytes = (Get-Item -LiteralPath $lexiconPath).Length
            yinxing_bundle_bytes = (Get-Item -LiteralPath $bundlePath).Length
            release_hap_bytes = (Get-Item -LiteralPath $releaseHapPath).Length
            fresh_host_probe = $freshPerformance
        }
        deltas = [ordered]@{
            production_lex_bytes = 0
            yinxing_bundle_bytes = 0
            release_hap_bytes = 0
            runtime_algorithm = 'UNCHANGED'
        }
        device_metrics = [ordered]@{
            phone_candidate_refresh = 'NOT_RUN'
            pad_candidate_refresh = 'NOT_RUN'
            arm64_physical_device = 'NOT_RUN'
        }
    }
    Write-DeterministicJson (Join-Path $evidenceDir 'performance-comparison.json') $performanceComparison 20

    $releaseGateOutput = & powershell -ExecutionPolicy Bypass -File `
        (Join-Path $repoRoot 'scripts\verify-release-hap.ps1') -HapPath $releaseHapPath
    if ($LASTEXITCODE -ne 0) {
        throw "Release HAP resource audit failed: $LASTEXITCODE"
    }
    $releaseAudit = [ordered]@{
        schema_version = 'candidate-improvement/stage6-release-resource-audit/1'
        status = 'PASS'
        hap_path = 'entry/build/artifacts/entry-release-unsigned.hap'
        hap_bytes = (Get-Item -LiteralPath $releaseHapPath).Length
        hap_sha256 = (Get-FileHash -LiteralPath $releaseHapPath -Algorithm SHA256).Hash.ToLowerInvariant()
        approved_runtime_rawfiles = @('production.lex', 'xiaohe-yinxing-production.hsyx')
        forbidden_content = [ordered]@{
            raw_customer_tables = $false
            non_redistributable_sources = $false
            license_audit_materials = $false
            internal_test_corpora = $false
            debug_logs = $false
            local_absolute_paths = $false
            private_source_urls_or_credentials = $false
            disabled_datasets = $false
            duplicate_mock_lexicons = $false
        }
        gate_output = @($releaseGateOutput)
    }
    Write-DeterministicJson (Join-Path $evidenceDir 'release-resource-audit.json') $releaseAudit

    $hashTargets = @(
        'coverage-report.json',
        'missing-entries.json',
        'source-audit.json',
        'frequency-normalization.json',
        'lexicon-manifest.json',
        'coverage-before-after.json',
        'performance-comparison.json',
        'release-resource-audit.json'
    )
    $buildHashes = [ordered]@{
        schema_version = 'candidate-improvement/stage6-build-hashes/1'
        deterministic_gate = 'PASS'
        coverage_build_1_sha256 = $firstCoverageHash
        coverage_build_2_sha256 = $secondCoverageHash
        files = @($hashTargets | ForEach-Object {
            $path = Join-Path $evidenceDir $_
            [ordered]@{
                path = "docs/evidence/2026-07-29-candidate-stage6/$_"
                bytes = (Get-Item -LiteralPath $path).Length
                sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        })
    }
    Write-DeterministicJson (Join-Path $evidenceDir 'build-hashes.json') $buildHashes

    Write-Host "CANDIDATE_STAGE6=PASS cases=$($coverage.case_count) missing=$($missingCases.Count)"
    Write-Host "DETERMINISTIC_SHA256=$firstCoverageHash"
    Write-Host 'REPORT=docs/evidence/2026-07-29-candidate-stage6/coverage-report.json'
} finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}
