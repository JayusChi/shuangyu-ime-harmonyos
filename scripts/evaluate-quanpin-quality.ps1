[CmdletBinding()]
param(
    [ValidateRange(3, 20)]
    [int]$Runs = 3,
    [ValidateSet('dev', 'blind', 'all')]
    [string]$Split = 'dev',
    [switch]$SpellingCorrectionEnabled,
    [switch]$DisableFuzzyOptions,
    [string]$ResultsPath = '',
    [string]$FailuresPath = '',
    [string]$AnonymousDistributionPath = '',
    [ValidateRange(0, 5)]
    [int]$LearningRepetitions = 3,
    [switch]$CreateNewBaseline,
    [string]$BaselineId,
    [string]$FrozenAt,
    [string]$NewManifestPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rustRoot = Join-Path $repoRoot 'engine-rust'
$dataset = Join-Path $repoRoot 'artifacts\quanpin-evaluation\dataset'
$manifest = Join-Path $repoRoot 'artifacts\quanpin-evaluation\freeze-manifest.json'
$lexicon = Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex'
if ([string]::IsNullOrWhiteSpace($ResultsPath)) {
    $ResultsPath = Join-Path $repoRoot ("artifacts\quanpin-evaluation\pre-change-{0}-results.json" -f $Split)
}
if ([string]::IsNullOrWhiteSpace($FailuresPath)) {
    $FailuresPath = Join-Path $repoRoot ("artifacts\quanpin-evaluation\pre-change-{0}-failures.jsonl" -f $Split)
}
$results = [System.IO.Path]::GetFullPath($ResultsPath)
$failures = [System.IO.Path]::GetFullPath($FailuresPath)
$protectedResults = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\quanpin-evaluation\baseline-results.json'))
$protectedFailures = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\quanpin-evaluation\failure-cases.jsonl'))
if ($results -eq $protectedResults -or $failures -eq $protectedFailures) {
    throw 'Refusing to overwrite the frozen pre-improvement baseline artifacts.'
}

if ($CreateNewBaseline) {
    if ([string]::IsNullOrWhiteSpace($BaselineId) -or
        [string]::IsNullOrWhiteSpace($FrozenAt) -or
        [string]::IsNullOrWhiteSpace($NewManifestPath)) {
        throw '-CreateNewBaseline requires -BaselineId, -FrozenAt, and -NewManifestPath.'
    }
    $resolvedNewManifest = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $NewManifestPath))
    if (-not $resolvedNewManifest.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'New manifest path must stay inside the repository.'
    }
    & cargo run --release -p candidate-baseline --manifest-path (Join-Path $rustRoot 'Cargo.toml') -- `
        quanpin-freeze $dataset $resolvedNewManifest $BaselineId $FrozenAt
    if ($LASTEXITCODE -ne 0) { throw "Dataset freeze failed with exit code $LASTEXITCODE." }
    Write-Host "Created new frozen manifest at $resolvedNewManifest. Review it before using it for evaluation."
    exit 0
}

if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "Frozen manifest is missing: $manifest"
}
if (-not (Test-Path -LiteralPath $lexicon -PathType Leaf)) {
    throw "Formal production lexicon is missing: $lexicon"
}

& cargo run --release -p candidate-baseline --manifest-path (Join-Path $rustRoot 'Cargo.toml') -- `
    quanpin-validate $dataset
if ($LASTEXITCODE -ne 0) { throw "Dataset validation failed with exit code $LASTEXITCODE." }

$spellingCorrectionFlag = ([bool]$SpellingCorrectionEnabled).ToString().ToLowerInvariant()
$fuzzyOptionsFlag = (-not [bool]$DisableFuzzyOptions).ToString().ToLowerInvariant()
$evaluationArgs = @(
    'quanpin-evaluate', $dataset, $manifest, $lexicon, $results, $failures, $Runs,
    '--split', $Split,
    '--spelling-correction', $spellingCorrectionFlag,
    '--fuzzy-options', $fuzzyOptionsFlag,
    '--learning-repetitions', $LearningRepetitions
)
if (-not [string]::IsNullOrWhiteSpace($AnonymousDistributionPath)) {
    $distribution = [System.IO.Path]::GetFullPath($AnonymousDistributionPath)
    if (-not (Test-Path -LiteralPath $distribution -PathType Leaf)) {
        throw "Anonymous aggregate distribution is missing: $distribution"
    }
    & cargo run --release -p candidate-baseline --manifest-path (Join-Path $rustRoot 'Cargo.toml') -- `
        quanpin-distribution-validate $distribution
    if ($LASTEXITCODE -ne 0) { throw "Anonymous aggregate validation failed with exit code $LASTEXITCODE." }
    $evaluationArgs += @('--anonymous-distribution', $distribution)
}
& cargo run --release -p candidate-baseline --manifest-path (Join-Path $rustRoot 'Cargo.toml') -- @evaluationArgs
if ($LASTEXITCODE -ne 0) { throw "Quanpin evaluation failed with exit code $LASTEXITCODE." }

$summary = Get-Content -Raw -Encoding UTF8 $results | ConvertFrom-Json
$metrics = $summary.metrics
Write-Host ("Samples={0} Top1={1:P3} Top3={2:P3} Top5={3:P3} MRR={4:N6}" -f `
    $summary.sampleCount, $metrics.top1Rate, $metrics.top3Rate, $metrics.top5Rate, $metrics.mrr)
$breakdown = $metrics.failureBreakdown
Write-Host ("Failures: unrecalled={0:P3}, recalled-outside-Top5={1:P3}, ranking-error={2:P3}" -f `
    $breakdown.targetUnrecalledRate, $breakdown.recalledOutsideTop5Rate, $breakdown.rankingErrorRate)
if ($summary.anonymousDistribution.provided) {
    $weighted = $summary.anonymousDistribution.weightedMetricsOverCoveredEvents
    Write-Host ("Anonymous-weighted: coverage={0:P3}, Top1={1:P3}, Top5={2:P3}" -f `
        $summary.anonymousDistribution.coveredEventRate, $weighted.top1Rate, $weighted.top5Rate)
}
if ($summary.userLearningProbe.enabled) {
    Write-Host ("User-learning probe: eligible={0}, improved={1}, became-Top1={2}, worsened={3}, rank={4:N3}->{5:N3}" -f `
        $summary.userLearningProbe.eligibleTargetCount, $summary.userLearningProbe.improvedRankCount, `
        $summary.userLearningProbe.becameTop1Count, $summary.userLearningProbe.worsenedRankCount, `
        $summary.userLearningProbe.averageRankBefore, $summary.userLearningProbe.averageRankAfter)
}
Write-Host "Results: $results"
Write-Host "Failures: $failures"
