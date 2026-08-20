param(
    [int]$PerformanceWarmups = 5,
    [int]$PerformanceSamples = 30
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$engineManifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'
$lexiconPath = Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex'
$normalizedPath = Join-Path $repoRoot 'dictionaries\generated\production.normalized.tsv'
$shapePath = Join-Path $repoRoot 'entry\src\main\resources\rawfile\xiaohe-yinxing-production.hsyx'
$stage3ReportPath = Join-Path $repoRoot 'docs\evidence\2026-07-28-candidate-stage3\host-report.json'
$evidenceDir = Join-Path $repoRoot 'docs\evidence\2026-07-28-candidate-stage5'
$reportPath = Join-Path $evidenceDir 'host-report.json'
$summaryPath = Join-Path $evidenceDir 'generated-summary.md'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Get-LengthSummary {
    param([Parameter(Mandatory = $true)]$Candidates)
    $items = @($Candidates)
    return [ordered]@{
        single_character = @($items | Where-Object { $_.text.Length -eq 1 }).Count
        two_to_four_characters = @($items | Where-Object {
            $_.text.Length -ge 2 -and $_.text.Length -le 4
        }).Count
        over_four_characters = @($items | Where-Object { $_.text.Length -gt 4 }).Count
        repeated_single_character = @($items | Where-Object {
            $_.text.Length -ge 2 -and (@($_.text.ToCharArray() | Select-Object -Unique).Count -eq 1)
        }).Count
    }
}

function Get-OneBasedRank {
    param(
        [Parameter(Mandatory = $true)]$Candidates,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $items = @($Candidates)
    for ($index = 0; $index -lt $items.Count; $index++) {
        if ($items[$index].text -ceq $Text) {
            return $index + 1
        }
    }
    return $null
}

function ConvertTo-CanonicalJson {
    param([Parameter(Mandatory = $true)]$Value)
    return $Value | ConvertTo-Json -Depth 50 -Compress
}

if ($PerformanceWarmups -lt 0 -or $PerformanceSamples -le 0) {
    throw 'PerformanceWarmups must be non-negative and PerformanceSamples must be positive.'
}
foreach ($path in @($lexiconPath, $normalizedPath, $shapePath, $stage3ReportPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required input is missing: $path"
    }
}

$stage3 = Get-Content -LiteralPath $stage3ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$currentText = (& cargo run --quiet --release --manifest-path $engineManifest `
    -p candidate-baseline -- stage3 $lexiconPath $PerformanceWarmups $PerformanceSamples) -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw 'Stage 5 candidate report generation failed.'
}
$current = $currentText | ConvertFrom-Json

$learningText = (& cargo run --quiet --release --manifest-path $engineManifest `
    -p candidate-baseline -- stage5-learning $lexiconPath) -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw 'Stage 5 learning report generation failed.'
}
$learning = $learningText | ConvertFrom-Json

$rows = @(Import-Csv -LiteralPath $normalizedPath -Delimiter "`t" `
    -Header word,reading,frequency,source)
$allFrequencies = @($rows | ForEach-Object { [int64]$_.frequency })
$sources = @($rows | Group-Object source | Sort-Object Name | ForEach-Object {
    [ordered]@{ source = $_.Name; entry_count = $_.Count }
})
$lengths = @($rows | Group-Object { $_.word.Length } | Sort-Object {
    [int]$_.Name
} | ForEach-Object {
    $frequencies = @($_.Group | ForEach-Object { [int64]$_.frequency })
    [ordered]@{
        character_count = [int]$_.Name
        entry_count = $_.Count
        min_frequency = ($frequencies | Measure-Object -Minimum).Minimum
        max_frequency = ($frequencies | Measure-Object -Maximum).Maximum
        average_frequency = [math]::Round(($frequencies | Measure-Object -Average).Average, 3)
    }
})
$highFrequencyLong = @($rows |
    Where-Object { $_.word.Length -ge 4 } |
    Sort-Object @{Expression = {[int64]$_.frequency}; Descending = $true}, word |
    Select-Object -First 20 word,reading,@{n='frequency';e={[int64]$_.frequency}},source)
$highFrequencyRepeated = @($rows |
    Where-Object {
        $_.word.Length -ge 2 -and
        (@($_.word.ToCharArray() | Select-Object -Unique).Count -eq 1)
    } |
    Sort-Object @{Expression = {[int64]$_.frequency}; Descending = $true}, word |
    Select-Object -First 20 word,reading,@{n='frequency';e={[int64]$_.frequency}},source)

$selectedKeys = @('a', 'h', 'n', 's', 'z')
$keyReports = @($current.single_key_a_to_z |
    Where-Object { $_.input -in $selectedKeys } |
    ForEach-Object {
        [ordered]@{
            input = $_.input
            recall_pool_size = $_.recall_pool_size
            snapshot_size = $_.candidate_snapshot_size
            top_20_branch_count = @($_.top_20_first_syllable_branch_counts.PSObject.Properties).Count
            top_20_length_summary = Get-LengthSummary $_.top_20
            top_20 = @($_.top_20)
        }
    })

$beforeH20 = @($stage3.h_comparison.current_first_20)
$beforeH50 = @($stage3.h_comparison.current_first_50)
$afterH20 = @($current.h_comparison.current_first_20)
$afterH50 = @($current.h_comparison.current_first_50)
$replyDate = -join @([char]0x56DE, [char]0x590D, [char]0x65E5, [char]0x671F)
$hehe = -join @([char]0x5475, [char]0x5475)
$haha = -join @([char]0x54C8, [char]0x54C8)
$anomalyRanks = @(($replyDate, $hehe, $haha) | ForEach-Object {
    [ordered]@{
        text = $_
        before_rank_one_based = Get-OneBasedRank $beforeH50 $_
        after_rank_one_based = Get-OneBasedRank $afterH50 $_
    }
})

Assert-True ($current.configuration.prefix_recall_pool_limit -eq 256) 'Recall pool changed.'
Assert-True ($current.configuration.prefix_snapshot_limit -eq 128) 'Snapshot limit changed.'
Assert-True ($current.configuration.page_size -eq 50) 'Page size changed.'
Assert-True ($current.h_comparison.current_recall_pool_size -eq 256) 'h recall pool is not 256.'
Assert-True ($current.h_comparison.current_snapshot_size -eq 128) 'h snapshot is not 128.'
Assert-True ((ConvertTo-CanonicalJson $current.h_comparison.current_recall_pool_branch_counts) -ceq `
    (ConvertTo-CanonicalJson $stage3.h_comparison.current_recall_pool_branch_counts)) `
    'Stage 3 h recall branch coverage changed.'
Assert-True $current.h_comparison.cache_consistent 'h cache hit differs from cold query.'
Assert-True $current.pagination.concatenated_order_identical 'Page sizes produce different order.'
Assert-True ((Get-LengthSummary $afterH20).over_four_characters -eq 0) `
    'h top 20 still contains an over-four-character candidate.'
Assert-True ((Get-LengthSummary $afterH20).repeated_single_character -eq 0) `
    'h top 20 still contains a repeated single-character candidate.'
Assert-True (@($current.h_comparison.current_snapshot_branch_counts.PSObject.Properties).Count -ge 10) `
    'h branch coverage regressed.'
foreach ($keyReport in $keyReports) {
    Assert-True ($keyReport.top_20_length_summary.over_four_characters -eq 0) `
        "$($keyReport.input) top 20 contains an over-four-character candidate."
}
Assert-True ($learning.rank_after_learning_one_based -lt $learning.rank_base_one_based) `
    'Learned candidate did not rise.'
Assert-True $learning.persisted 'Learning did not survive reload.'
Assert-True $learning.clear_restored_baseline 'Clear did not restore baseline.'
Assert-True $learning.disabled_session_unchanged 'Disabled session changed persistent rank.'
Assert-True $learning.model_file_removed_after_clear 'Clear left the model file behind.'
Assert-True ((ConvertTo-CanonicalJson $current.regressions.exact_double_key) -ceq `
    (ConvertTo-CanonicalJson $stage3.regressions.exact_double_key)) `
    'Exact double-pinyin regression changed.'
Assert-True ((ConvertTo-CanonicalJson $current.regressions.sentence_and_partial_inputs) -ceq `
    (ConvertTo-CanonicalJson $stage3.regressions.sentence_and_partial_inputs)) `
    'Sentence regression changed.'
Assert-True ((ConvertTo-CanonicalJson $current.regressions.partial_commit) -ceq `
    (ConvertTo-CanonicalJson $stage3.regressions.partial_commit)) `
    'Partial commit regression changed.'

$lexiconHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $lexiconPath).Hash.ToLowerInvariant()
$shapeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $shapePath).Hash.ToLowerInvariant()
Assert-True ($lexiconHash -ceq 'd1b1a3cffd1784fd3abdae1a3dab4189ff9ce87ba2431d83f0b92a1b7356d9c5') `
    'production.lex changed.'
Assert-True ($shapeHash -ceq '00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30') `
    'Xiaohe shape bundle changed.'

$report = [ordered]@{
    schema_version = 'candidate-improvement/stage5-host-report/1'
    profile = 'release'
    configuration = $current.configuration
    resource_identity = [ordered]@{
        production_lexicon_bytes = (Get-Item -LiteralPath $lexiconPath).Length
        production_lexicon_sha256 = $lexiconHash
        xiaohe_shape_bundle_bytes = (Get-Item -LiteralPath $shapePath).Length
        xiaohe_shape_bundle_sha256 = $shapeHash
    }
    lexicon_audit = [ordered]@{
        normalized_entry_count = $rows.Count
        sources = $sources
        frequency_min = ($allFrequencies | Measure-Object -Minimum).Minimum
        frequency_max = ($allFrequencies | Measure-Object -Maximum).Maximum
        character_length_distribution = $lengths
        high_frequency_long_candidates = $highFrequencyLong
        high_frequency_repeated_candidates = $highFrequencyRepeated
        duplicate_merge_contract = 'same text + same normalized reading; max frequency; sorted merged sources'
        same_text_multiple_readings_contract = 'prefix Top-K occupies one visible-text slot and keeps the best full stable ranking key'
    }
    ranking_contract = [ordered]@{
        applies_to = 'QueryMode::Prefix + ExistingRanking + GlobalTopK only'
        exact_query = 'unchanged: match type, raw frequency DESC, stable text/reading/source/id'
        sentence_query = 'unchanged sentence decoder scoring and bounded user score'
        prefix_priority = @(
            'match type (exact before prefix)',
            'prefix quality score + bounded user score DESC',
            'raw frequency DESC',
            'text ASC',
            'reading ASC',
            'source ASC',
            'stable id ASC'
        )
        prefix_quality = [ordered]@{
            one_or_two_char_divisor = 1
            three_char_divisor = 2
            four_or_more_char_divisor = 8
            repeated_single_character_extra_divisor = 8
            penalties_are_capped = $true
            candidates_are_filtered = $false
        }
        learning_position = 'full scan -> visible-text Top-K 256 -> dedupe/system sort -> user rerank -> snapshot 128 -> paging'
    }
    h_before_after = [ordered]@{
        before_stage = 3
        before_first_20 = $beforeH20
        after_first_20 = $afterH20
        before_first_50 = $beforeH50
        after_first_50 = $afterH50
        before_top_20_length_summary = Get-LengthSummary $beforeH20
        after_top_20_length_summary = Get-LengthSummary $afterH20
        anomaly_rank_changes = $anomalyRanks
        recall_pool_size = $current.h_comparison.current_recall_pool_size
        snapshot_size = $current.h_comparison.current_snapshot_size
        snapshot_branch_count = @($current.h_comparison.current_snapshot_branch_counts.PSObject.Properties).Count
    }
    selected_single_key_regressions = $keyReports
    learning = $learning
    stability = [ordered]@{
        cache_consistent = $current.h_comparison.cache_consistent
        page_size_9_20_30_50_identical = $current.pagination.concatenated_order_identical
        page_sizes = $current.pagination.snapshot_sizes
    }
    regressions = $current.regressions
    performance = [ordered]@{
        stage3 = $stage3.performance
        stage5 = $current.performance
        ranking_subphases = $learning.performance
    }
    memory = [ordered]@{
        stage3 = $stage3.memory
        stage5 = $current.memory
        structural_bounds = 'prefix Top-K O(256), final prefix snapshot 128, no additional unbounded collection'
    }
}

New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
[IO.File]::WriteAllText(
    $reportPath,
    ($report | ConvertTo-Json -Depth 50) + "`n",
    [Text.UTF8Encoding]::new($false)
)

$summary = @(
    '# Candidate improvement stage 5 generated summary'
    ''
    "- h before top 20: $($beforeH20.text -join ', ')"
    "- h after top 20: $($afterH20.text -join ', ')"
    "- h after top 50: $($afterH50.text -join ', ')"
    "- h top-20 single/2-4/>4/repeated: $((Get-LengthSummary $afterH20).single_character)/$((Get-LengthSummary $afterH20).two_to_four_characters)/$((Get-LengthSummary $afterH20).over_four_characters)/$((Get-LengthSummary $afterH20).repeated_single_character)."
    "- Learned candidate $($learning.target_text) rank: $($learning.rank_trajectory_one_based -join ' -> '); reload $($learning.rank_after_reload_one_based), clear $($learning.rank_after_clear_one_based), disabled session $($learning.rank_after_disabled_session_one_based)."
    "- a-z cold P50/P95: $($current.performance.cold_a_to_z.p50)/$($current.performance.cold_a_to_z.p95) ns."
    "- a-z hot P50/P95: $($current.performance.hot_a_to_z.p50)/$($current.performance.hot_a_to_z.p95) ns."
    "- Dedup/system sort/user rerank P50: $($learning.performance.deduplicate.p50)/$($learning.performance.system_prefix_sort.p50)/$($learning.performance.user_rerank.p50) ns."
    "- Exact double-pinyin, sentence, partial commit, cache and page-size stability: PASS."
    ''
    '| Key | Top 20 | Single | 2-4 chars | >4 chars | Branches |'
    '| --- | --- | ---: | ---: | ---: | ---: |'
) + @($keyReports | ForEach-Object {
    "| $($_.input) | $($_.top_20.text -join ', ') | $($_.top_20_length_summary.single_character) | $($_.top_20_length_summary.two_to_four_characters) | $($_.top_20_length_summary.over_four_characters) | $($_.top_20_branch_count) |"
})
[IO.File]::WriteAllText(
    $summaryPath,
    ($summary -join "`n") + "`n",
    [Text.UTF8Encoding]::new($false)
)

Write-Host 'CANDIDATE_STAGE5_EVIDENCE=PASS'
Write-Host 'REPORT=docs/evidence/2026-07-28-candidate-stage5/host-report.json'
Write-Host 'SUMMARY=docs/evidence/2026-07-28-candidate-stage5/generated-summary.md'
