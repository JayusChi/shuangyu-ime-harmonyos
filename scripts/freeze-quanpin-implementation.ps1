[CmdletBinding()]
param(
    [string]$OutputPath = 'artifacts\quanpin-evaluation\implementation-freeze-manifest.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$datasetManifestPath = Join-Path $repoRoot 'artifacts\quanpin-evaluation\freeze-manifest.json'
$productionLexiconPath = Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex'
$expectedDatasetIdentity = 'f68c3006ee1c714eb9f1c543439785fd1164e61b6ef21a4d8da851d2b1e2ba22'
$expectedLexiconHash = '6a5f0567ca52c3e0ae539c9753109652c3c98218a0bfba1ad492d4ec494d6ff4'

$datasetManifest = Get-Content -Raw -Encoding UTF8 $datasetManifestPath | ConvertFrom-Json
if ($datasetManifest.baselineIdentitySha256 -ne $expectedDatasetIdentity) {
    throw "Frozen dataset identity changed: $($datasetManifest.baselineIdentitySha256)"
}
$lexiconHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $productionLexiconPath).Hash.ToLowerInvariant()
if ($lexiconHash -ne $expectedLexiconHash) {
    throw "Production lexicon changed: $lexiconHash"
}

$relevantFiles = @(
    'engine-rust\Cargo.lock',
    'engine-rust\crates\engine-protocol\src\composition.rs',
    'engine-rust\crates\ime-engine\Cargo.toml',
    'engine-rust\crates\ime-engine\src\lib.rs',
    'engine-rust\crates\ime-engine\src\formal.rs',
    'engine-rust\crates\ime-engine\src\candidate_session.rs',
    'engine-rust\crates\ime-engine\src\quanpin_features.rs',
    'engine-rust\crates\ime-engine\examples\precise_match_stage0_baseline.rs',
    'engine-rust\crates\ime-engine\examples\quanpin_feature_inspect.rs',
    'engine-rust\crates\ime-engine\examples\quanpin_feature_runtime.rs',
    'engine-rust\crates\ime-engine\examples\stage0_shuangpin_baseline.rs',
    'engine-rust\crates\ime-engine\examples\stage11_5_benchmark.rs',
    'engine-rust\crates\ime-engine\examples\t9_stage3_benchmark.rs',
    'engine-rust\crates\ime-engine\tests\code_table_backend.rs',
    'engine-rust\crates\ime-engine\tests\precise_match_stage0_baseline.rs',
    'engine-rust\crates\ime-engine\tests\quanpin_features.rs',
    'engine-rust\crates\ime-engine\tests\quanpin_quality.rs',
    'engine-rust\crates\ime-engine\tests\quanpin_stage2.rs',
    'engine-rust\crates\ime-engine\tests\stage11_5_production_corpus.rs',
    'engine-rust\crates\ime-engine\tests\stage7_cases.rs',
    'engine-rust\crates\ime-engine\tests\stage8_cases.rs',
    'engine-rust\crates\ime-engine\tests\stage9_cases.rs',
    'engine-rust\crates\ime-engine\tests\t9_stage3.rs',
    'engine-rust\crates\ime-engine\tests\user_lexicon_cases.rs',
    'engine-rust\crates\ime-engine\tests\xiaohe_yinxing_production.rs',
    'engine-rust\crates\ime-ffi\src\lib.rs',
    'engine-rust\tools\candidate-baseline\src\lib.rs',
    'engine-rust\tools\candidate-baseline\src\main.rs',
    'engine-rust\tools\candidate-baseline\src\quanpin_evaluation.rs',
    'entry\src\main\cpp\bridge\rust_engine_bridge.h',
    'entry\src\main\cpp\napi\engine_napi.cpp',
    'entry\src\main\ets\infrastructure\native\NativeEngineTypes.ets',
    'entry\src\main\ets\infrastructure\native\NativeEngineGateway.ets',
    'entry\src\main\types\libime_bridge\index.d.ts',
    'entry\src\main\ets\application\EngineCoordinator.ets',
    'entry\src\main\ets\application\InputSessionController.ets',
    'entry\src\main\ets\application\SettingsController.ets',
    'entry\src\main\ets\domain\settings\ImeSettings.ets',
    'entry\src\main\ets\infrastructure\storage\SettingsMigration.ets',
    'entry\src\main\ets\infrastructure\storage\SettingsValidator.ets',
    'entry\src\main\ets\infrastructure\storage\SettingsRepository.ets',
    'entry\src\main\ets\presentation\settings\SettingsPage.ets',
    'entry\src\test\Stage2Controller.test.ets',
    'entry\src\test\Stage11.test.ets',
    'docs\API_CONTRACT.md',
    'docs\ACTION_PROTOCOL.md',
    'docs\DIRECT_ENCODING_SIX_REQUIREMENTS.md',
    'scripts\evaluate-quanpin-quality.ps1',
    'scripts\freeze-quanpin-implementation.ps1'
)

$files = foreach ($relativePath in $relevantFiles) {
    $absolutePath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        throw "Relevant implementation file is missing: $relativePath"
    }
    $file = Get-Item -LiteralPath $absolutePath
    [ordered]@{
        path = $relativePath.Replace('\', '/')
        bytes = $file.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath).Hash.ToLowerInvariant()
    }
}

$manifest = [ordered]@{
    schemaVersion = 'quanpin-implementation-freeze/1'
    frozenAt = (Get-Date).ToUniversalTime().ToString('o')
    gitIdentityUsed = $false
    datasetBaselineIdentitySha256 = $expectedDatasetIdentity
    datasetManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $datasetManifestPath).Hash.ToLowerInvariant()
    productionLexiconSha256 = $lexiconHash
    productionLexiconBytes = (Get-Item -LiteralPath $productionLexiconPath).Length
    engineVersion = '0.0.1-quanpin-features'
    interfaceVersion = 9
    abiVersion = 9
    settingsSchemaVersion = 7
    defaults = [ordered]@{
        configVersion = 1
        spellingCorrectionEnabled = $false
        maximumEditDistance = 1
        fuzzyOptions = @()
    }
    hardLimits = [ordered]@{
        maximumCorrectableRawLength = 32
        maximumSpellingVariants = 512
        maximumSpellingSearchNodes = 1024
        maximumCorrectionQueryPaths = 32
        maximumCandidatesPerExpansionPath = 3
        maximumFuzzyQueryPaths = 32
        maximumFuzzyChangesPerPath = 2
        maximumCombinedQueryPaths = 8
        maximumSentenceDecodePathsPerSpellingKind = 4
        maximumFuzzySentenceDecodePaths = 8
        maximumCombinedSentenceDecodePaths = 4
        maximumMergedCandidates = 256
        featureCacheCapacity = 0
    }
    files = @($files)
    mutationPolicy = 'Run blind exactly once (three repetitions) against this source/config identity. Any subsequent algorithm, parameter, source, config, production lexicon, or frozen dataset change requires a new implementation version and a new freeze manifest.'
}

$resolvedOutput = [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
if (-not $resolvedOutput.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output path must stay inside the repository.'
}
$parent = Split-Path -Parent $resolvedOutput
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$json = $manifest | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($resolvedOutput, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Host "Implementation frozen: $resolvedOutput"
