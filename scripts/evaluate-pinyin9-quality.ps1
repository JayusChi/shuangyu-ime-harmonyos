[CmdletBinding()]
param(
    [ValidateSet('CreateDataset', 'Validate', 'FreezeDataset', 'FreezeImplementation', 'PublicRegression', 'Dev', 'Blind')]
    [string]$Action = 'Dev',
    [ValidateRange(3, 20)]
    [int]$Runs = 3,
    [string]$BaselineId = 'pinyin9-quality-v1-20260817',
    [string]$FrozenAt = '2026-08-17T00:00:00+08:00'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rustRoot = Join-Path $repoRoot 'engine-rust'
$sourceDataset = Join-Path $repoRoot 'artifacts\quanpin-evaluation\dataset'
$artifactRoot = Join-Path $repoRoot 'artifacts\pinyin9-evaluation'
$dataset = Join-Path $artifactRoot 'dataset'
$manifest = Join-Path $artifactRoot 'freeze-manifest.json'
$implementationManifest = Join-Path $artifactRoot 'implementation-freeze-manifest.json'
$lexicon = Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex'
$receipt = Join-Path $artifactRoot 'blind-run-receipt.json'
$cargoManifest = Join-Path $rustRoot 'Cargo.toml'

function Invoke-CandidateBaseline {
    param([string[]]$Arguments)
    & cargo run --release -p candidate-baseline --manifest-path $cargoManifest -- @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "candidate-baseline failed with exit code $LASTEXITCODE."
    }
}

switch ($Action) {
    'CreateDataset' {
        Invoke-CandidateBaseline @('pinyin9-create-dataset', $sourceDataset, $dataset)
        break
    }
    'Validate' {
        Invoke-CandidateBaseline @('pinyin9-validate', $dataset)
        break
    }
    'FreezeDataset' {
        Invoke-CandidateBaseline @('pinyin9-freeze', $dataset, $manifest, $BaselineId, $FrozenAt)
        break
    }
    'FreezeImplementation' {
        Invoke-CandidateBaseline @(
            'pinyin9-implementation-freeze',
            $repoRoot,
            $manifest,
            $lexicon,
            $implementationManifest,
            $FrozenAt
        )
        break
    }
    default {
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
            throw "Frozen dataset manifest is missing: $manifest"
        }
        if (-not (Test-Path -LiteralPath $implementationManifest -PathType Leaf)) {
            throw "Frozen implementation manifest is missing: $implementationManifest"
        }
        if (-not (Test-Path -LiteralPath $lexicon -PathType Leaf)) {
            throw "Installed formal production lexicon is missing: $lexicon"
        }
        Invoke-CandidateBaseline @('pinyin9-validate', $dataset)

        $split = switch ($Action) {
            'PublicRegression' { 'public-regression' }
            'Dev' { 'dev' }
            'Blind' { 'blind' }
        }
        $stem = switch ($Action) {
            'PublicRegression' { 'baseline-public-regression' }
            'Dev' { 'baseline-dev' }
            'Blind' { 'baseline-blind' }
        }
        $results = Join-Path $artifactRoot ($stem + '-results.json')
        $failures = Join-Path $artifactRoot ($stem + '-failures.jsonl')
        $arguments = @(
            'pinyin9-evaluate',
            $dataset,
            $manifest,
            $lexicon,
            $results,
            $failures,
            $Runs.ToString(),
            '--split',
            $split,
            '--implementation-manifest',
            $implementationManifest,
            '--repo-root',
            $repoRoot
        )
        if ($Action -eq 'Blind') {
            if ($Runs -ne 3) {
                throw 'Blind evaluation is fixed to exactly three internal runs.'
            }
            $arguments += @('--receipt', $receipt)
        }
        Invoke-CandidateBaseline $arguments
        $summary = Get-Content -Raw -Encoding UTF8 $results | ConvertFrom-Json
        $metrics = $summary.metrics
        Write-Host ("Samples={0} Top1={1:P3} Top3={2:P3} Top5={3:P3} MRR={4:N6} Unrecalled={5:P3}" -f `
            $summary.sampleCount, $metrics.top1Rate, $metrics.top3Rate, $metrics.top5Rate, $metrics.mrr, $metrics.targetUnrecalledRate)
        Write-Host "Results: $results"
        Write-Host "Failures: $failures"
        if ($Action -eq 'Blind') { Write-Host "Single-use blind receipt: $receipt" }
    }
}
