param(
    [int]$PerformanceWarmups = 5,
    [int]$PerformanceSamples = 30
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$engineManifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'
$lexiconPath = Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex'
$baselinePath = Join-Path $repoRoot 'artifacts\candidate-baseline\double-key-baseline.json'
$sentenceBaselinePath = Join-Path $repoRoot 'artifacts\candidate-baseline\sentence-baseline.json'
$evidenceDir = Join-Path $repoRoot 'docs\evidence\2026-07-28-candidate-stage3'
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

function ConvertTo-CanonicalJson {
    param([Parameter(Mandatory = $true)]$Value)
    return $Value | ConvertTo-Json -Depth 30 -Compress
}

function Get-PropertyCount {
    param($Value)
    if ($null -eq $Value) {
        return 0
    }
    return @($Value.PSObject.Properties).Count
}

function Assert-ResultEquivalent {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$Label
    )
    foreach ($field in @(
        'success',
        'raw_input',
        'preedit_text',
        'parsed_syllables',
        'pending_code',
        'parser_state',
        'candidate_count',
        'candidates',
        'candidate_page',
        'has_previous_page',
        'has_next_page',
        'commit_text',
        'composition_finished'
    )) {
        $expectedJson = ConvertTo-CanonicalJson $Expected.$field
        $actualJson = ConvertTo-CanonicalJson $Actual.$field
        if ($expectedJson -cne $actualJson) {
            throw "$Label differs at $field"
        }
    }
}

if ($PerformanceWarmups -lt 0 -or $PerformanceSamples -le 0) {
    throw 'PerformanceWarmups must be non-negative and PerformanceSamples must be positive.'
}
foreach ($path in @($lexiconPath, $baselinePath, $sentenceBaselinePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required input is missing: $path"
    }
}

New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$reportText = (& cargo run --quiet --release --manifest-path $engineManifest `
    -p candidate-baseline -- stage3 $lexiconPath $PerformanceWarmups $PerformanceSamples) -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw 'Stage 3 host report generation failed.'
}
$report = $reportText | ConvertFrom-Json

Assert-True ($report.configuration.page_size -eq 50) 'Production page size changed.'
Assert-True ($report.configuration.prefix_recall_pool_limit -eq 256) 'Recall pool limit is not 256.'
Assert-True ($report.configuration.prefix_snapshot_limit -eq 128) 'Prefix snapshot limit is not 128.'
Assert-True ($report.h_comparison.legacy_recall_pool_size -eq 64) 'Legacy h pool is not frozen at 64.'
Assert-True ($report.h_comparison.current_recall_pool_size -eq 256) 'Current h recall pool is not 256.'
Assert-True ($report.h_comparison.current_snapshot_size -eq 128) 'Current h snapshot is not 128.'
Assert-True $report.h_comparison.cache_consistent 'h cold/cache results differ.'

$requiredBranches = @(
    'ha', 'hai', 'han', 'hang', 'hao',
    'he', 'hei', 'hen', 'heng',
    'hong', 'hou',
    'hu', 'hua', 'huai', 'huan', 'huang', 'hui', 'hun', 'huo'
)
$hBranches = @($report.h_comparison.current_recall_pool_branch_counts.PSObject.Properties.Name)
foreach ($branch in $requiredBranches) {
    Assert-True ($hBranches -contains $branch) "h recall pool does not cover branch $branch"
}
$hTop20Branches = @(
    $report.h_comparison.current_first_20 |
        ForEach-Object { ($_.reading -split ' ')[0] } |
        Sort-Object -Unique
)
Assert-True ($hTop20Branches.Count -gt 2) 'h top 20 is still dominated by one lexical branch.'
$hTop20Text = @($report.h_comparison.current_first_20.text)
$expectedCommonCodePoints = @(0x548C, 0x597D, 0x8FD8, 0x4F1A, 0x5F88, 0x540E, 0x6216)
foreach ($codePoint in $expectedCommonCodePoints) {
    $text = [char]$codePoint
    Assert-True ($hTop20Text -contains $text) "Expected common candidate is missing from h top 20: $text"
}

Assert-True ($report.single_key_a_to_z.Count -eq 26) 'a-z report does not contain 26 keys.'
foreach ($case in $report.single_key_a_to_z) {
    Assert-True $case.cache_consistent "Cache mismatch for $($case.input)."
    $topBranches = @($case.top_20_first_syllable_branch_counts.PSObject.Properties.Name)
    $topBranchCount = Get-PropertyCount $case.top_20_first_syllable_branch_counts
    if ($case.matched_first_syllable_branch_count -gt 1 -and $case.candidate_snapshot_size -ge 20) {
        $isExactPriority = $topBranchCount -eq 1 -and $topBranches[0] -ceq $case.input
        Assert-True ($topBranchCount -gt 1 -or $isExactPriority) "Top 20 lexical branch monopoly remains for $($case.input)."
    }
}

Assert-True $report.pagination.concatenated_order_identical 'Page-size concatenation differs.'
Assert-True $report.pagination.second_page_commit.commit_matches_selected 'Second-page commit mismatch.'
foreach ($size in @(9, 20, 30, 50)) {
    $row = $report.pagination.snapshot_sizes | Where-Object { $_.page_size -eq $size }
    Assert-True ($null -ne $row -and $row.candidate_count -eq 128) "Page size $size did not expose the 128-item snapshot."
}

$doubleKeyBaseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($actualCase in $report.regressions.exact_double_key) {
    $expectedCase = $doubleKeyBaseline.cases |
        Where-Object { $_.scheme_id -eq 'xiaohe' -and $_.input -eq $actualCase.input } |
        Select-Object -First 1
    Assert-True ($null -ne $expectedCase) "Missing exact baseline for $($actualCase.input)."
    Assert-ResultEquivalent $expectedCase.result $actualCase.result "Exact $($actualCase.input)"
}

$sentenceBaseline = Get-Content -LiteralPath $sentenceBaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($actualCase in $report.regressions.sentence_and_partial_inputs) {
    $expectedCase = $sentenceBaseline.sentence_cases |
        Where-Object { $_.input -eq $actualCase.input } |
        Select-Object -First 1
    Assert-True ($null -ne $expectedCase) "Missing sentence baseline for $($actualCase.input)."
    Assert-ResultEquivalent $expectedCase.result $actualCase.result "Sentence $($actualCase.input)"
}
$expectedPartial = $sentenceBaseline.partial_commit
$actualPartial = $report.regressions.partial_commit
Assert-True ($expectedPartial.selected_page_index -eq $actualPartial.selected_page_index) 'Partial commit index changed.'
Assert-True ($expectedPartial.selected_text -ceq $actualPartial.selected_text) 'Partial commit text changed.'
Assert-ResultEquivalent $expectedPartial.before $actualPartial.before 'Partial commit before'
Assert-ResultEquivalent $expectedPartial.after $actualPartial.after 'Partial commit after'

Assert-True ($report.performance.cold_a_to_z.p95 -lt 20000000) 'Host cold-query P95 exceeded 20 ms.'

[IO.File]::WriteAllText($reportPath, $reportText + "`n", [Text.UTF8Encoding]::new($false))
$legacyTop20 = $report.h_comparison.legacy_first_20.text -join ', '
$currentTop20 = $report.h_comparison.current_first_20.text -join ', '
$branchTable = @($report.single_key_a_to_z | ForEach-Object {
    $topBranchCount = Get-PropertyCount $_.top_20_first_syllable_branch_counts
    "| $($_.input) | $($_.matched_first_syllable_branch_count) | $($_.recall_pool_size) | $($_.candidate_snapshot_size) | $topBranchCount | $($_.cold_query.p50) | $($_.cold_query.p95) | $($_.hot_query.p50) |"
})
$summary = @(
    '# Candidate improvement stage 3 generated summary'
    ''
    "- Legacy h recall pool: $($report.h_comparison.legacy_recall_pool_size); branches: $($report.h_comparison.legacy_branch_counts.PSObject.Properties.Name -join '/')."
    "- Current h recall pool/snapshot: $($report.h_comparison.current_recall_pool_size)/$($report.h_comparison.current_snapshot_size); snapshot branches: $(@($report.h_comparison.current_snapshot_branch_counts.PSObject.Properties.Name).Count)."
    "- Legacy top 20: $legacyTop20"
    "- Current top 20: $currentTop20"
    "- a-z cold P50/P95: $($report.performance.cold_a_to_z.p50)/$($report.performance.cold_a_to_z.p95) ns."
    "- a-z hot P50/P95: $($report.performance.hot_a_to_z.p50)/$($report.performance.hot_a_to_z.p95) ns."
    "- Page-size 9/20/30/50 concatenation identical: $($report.pagination.concatenated_order_identical)."
    "- Exact double-pinyin, sentence and partial-commit baselines: PASS."
    ''
    '| Key | Matched branches | Recall pool | Snapshot | Top-20 branches | Cold P50(ns) | Cold P95(ns) | Hot P50(ns) |'
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |'
) + $branchTable
[IO.File]::WriteAllText($summaryPath, ($summary -join "`n") + "`n", [Text.UTF8Encoding]::new($false))

Write-Host 'CANDIDATE_STAGE3_EVIDENCE=PASS'
Write-Host "REPORT=docs/evidence/2026-07-28-candidate-stage3/host-report.json"
Write-Host "SUMMARY=docs/evidence/2026-07-28-candidate-stage3/generated-summary.md"
