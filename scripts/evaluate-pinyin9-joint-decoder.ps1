[CmdletBinding()]
param(
    [ValidateSet('FreezeImplementation', 'PublicRegression', 'Dev', 'All')]
    [string]$Action = 'All',
    [ValidateRange(3, 20)]
    [int]$Runs = 3,
    [string]$FrozenAt = '2026-08-18T00:00:00+08:00',
    [ValidatePattern('^pinyin9-joint-decoder-evaluation(?:-v[0-9]+)?$')]
    [string]$ArtifactName = 'pinyin9-joint-decoder-evaluation-v3'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rustRoot = Join-Path $repoRoot 'engine-rust'
$cargoManifest = Join-Path $rustRoot 'Cargo.toml'
$baselineRoot = Join-Path $repoRoot 'artifacts\pinyin9-evaluation'
$artifactRoot = Join-Path (Join-Path $repoRoot 'artifacts') $ArtifactName
$dataset = Join-Path $baselineRoot 'dataset'
$datasetManifest = Join-Path $baselineRoot 'freeze-manifest.json'
$lexicon = Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex'
$implementationManifest = Join-Path $artifactRoot 'implementation-manifest.json'

New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

function Invoke-CandidateBaseline {
    param([string[]]$Arguments)
    & cargo run --release -p candidate-baseline --manifest-path $cargoManifest -- @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "candidate-baseline failed with exit code $LASTEXITCODE."
    }
}

function Freeze-Implementation {
    if (Test-Path -LiteralPath $implementationManifest -PathType Leaf) {
        return
    }
    Invoke-CandidateBaseline @(
        'pinyin9-implementation-freeze',
        $repoRoot,
        $datasetManifest,
        $lexicon,
        $implementationManifest,
        $FrozenAt
    )
}

function Invoke-Split {
    param(
        [string]$Split,
        [string]$Stem
    )
    Invoke-CandidateBaseline @(
        'pinyin9-evaluate',
        $dataset,
        $datasetManifest,
        $lexicon,
        (Join-Path $artifactRoot ($Stem + '-results.json')),
        (Join-Path $artifactRoot ($Stem + '-failures.jsonl')),
        $Runs.ToString(),
        '--split',
        $Split,
        '--implementation-manifest',
        $implementationManifest,
        '--repo-root',
        $repoRoot
    )
}

function Select-Metrics {
    param($Result)
    $metrics = $Result.metrics
    [ordered]@{
        top1Rate = $metrics.top1Rate
        top3Rate = $metrics.top3Rate
        top5Rate = $metrics.top5Rate
        mrr = $metrics.mrr
        targetUnrecalledRate = $metrics.targetUnrecalledRate
        canonicalPinyinEnteredInternalSearchRate = $metrics.canonicalPinyinEnteredInternalSearchRate
        canonicalPinyinJointBeamPrunedRate = $metrics.canonicalPinyinJointBeamPrunedRate
        canonicalPinyinEnteredPublic32Rate = $metrics.canonicalPinyinEnteredPublic32Rate
        canonicalPinyinNotIn32PathsRate = $metrics.canonicalPinyinNotIn32PathsRate
        canonicalPathPresentButTargetUnrecalledRate = $metrics.canonicalPathPresentButTargetUnrecalledRate
        candidateRecalledButWrongTop1Rate = $metrics.candidateRecalledButWrongTop1Rate
        keyLatencyMicros = $metrics.keyLatencyMicros
        sampleTotalLatencyMicros = $metrics.sampleTotalLatencyMicros
        safety = $metrics.safety
        jointDecoder = $metrics.jointDecoder
        failureAttribution = $metrics.failureAttribution
    }
}

function Write-ComparisonArtifacts {
    $publicPath = Join-Path $artifactRoot 'public-regression-results.json'
    $devPath = Join-Path $artifactRoot 'dev-results.json'
    if (-not (Test-Path -LiteralPath $publicPath) -or -not (Test-Path -LiteralPath $devPath)) {
        return
    }
    $public = Get-Content -Raw -Encoding UTF8 -LiteralPath $publicPath | ConvertFrom-Json
    $dev = Get-Content -Raw -Encoding UTF8 -LiteralPath $devPath | ConvertFrom-Json
    $baselinePublic = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $baselineRoot 'baseline-public-regression-results.json') | ConvertFrom-Json
    $baselineDev = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $baselineRoot 'baseline-dev-results.json') | ConvertFrom-Json

    $comparison = [ordered]@{
        schemaVersion = 'pinyin9-joint-decoder-comparison/1'
        measurementKind = 'frozen-public-and-dev-before-after'
        blindReused = $false
        publicRegression = [ordered]@{
            baseline = Select-Metrics $baselinePublic
            jointDecoder = Select-Metrics $public
        }
        dev = [ordered]@{
            baseline = Select-Metrics $baselineDev
            jointDecoder = Select-Metrics $dev
        }
    }
    $comparison | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $artifactRoot 'baseline-comparison.json')

    $determinism = [ordered]@{
        schemaVersion = 'pinyin9-joint-decoder-determinism/1'
        runCount = $Runs
        publicRegression = [ordered]@{
            deterministic = $public.deterministicCandidateOutputs
            candidateOutputSha256ByRun = $public.candidateOutputSha256ByRun
            resultFileSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $publicPath).Hash.ToLowerInvariant()
        }
        dev = [ordered]@{
            deterministic = $dev.deterministicCandidateOutputs
            candidateOutputSha256ByRun = $dev.candidateOutputSha256ByRun
            resultFileSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $devPath).Hash.ToLowerInvariant()
        }
    }
    $determinism | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $artifactRoot 'determinism-receipt.json')

    $performance = [ordered]@{
        schemaVersion = 'pinyin9-joint-decoder-performance/1'
        platform = 'Windows x86_64 host release; not HarmonyOS device data'
        publicRegression = [ordered]@{
            baselineKeyLatencyMicros = $baselinePublic.metrics.keyLatencyMicros
            jointDecoderKeyLatencyMicros = $public.metrics.keyLatencyMicros
            baselineEngineLoadLatencyMicros = $baselinePublic.engineLoadLatencyMicros
            jointDecoderEngineLoadLatencyMicros = $public.engineLoadLatencyMicros
            jointDecoderSearch = $public.metrics.jointDecoder
        }
        dev = [ordered]@{
            baselineKeyLatencyMicros = $baselineDev.metrics.keyLatencyMicros
            jointDecoderKeyLatencyMicros = $dev.metrics.keyLatencyMicros
            baselineEngineLoadLatencyMicros = $baselineDev.engineLoadLatencyMicros
            jointDecoderEngineLoadLatencyMicros = $dev.engineLoadLatencyMicros
            jointDecoderSearch = $dev.metrics.jointDecoder
        }
    }
    $performance | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $artifactRoot 'performance-comparison.json')
}

Invoke-CandidateBaseline @('pinyin9-validate', $dataset)
Freeze-Implementation

switch ($Action) {
    'FreezeImplementation' { break }
    'PublicRegression' { Invoke-Split 'public-regression' 'public-regression' }
    'Dev' { Invoke-Split 'dev' 'dev' }
    'All' {
        Invoke-Split 'public-regression' 'public-regression'
        Invoke-Split 'dev' 'dev'
    }
}

Write-ComparisonArtifacts
