[CmdletBinding()]
param(
    [string]$OutputPath = 'artifacts\quanpin-lexicon-v2\implementation-freeze-manifest.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$output = [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
if (-not $output.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'freeze output must stay inside repository' }
if (Test-Path -LiteralPath $output) { throw "refusing to overwrite implementation freeze: $output" }
$utf8 = [Text.UTF8Encoding]::new($false)

function Assert-FrozenDataset([string]$manifestRelative, [string]$datasetRelative) {
    $manifestPath = Join-Path $repoRoot $manifestRelative
    $datasetRoot = Join-Path $repoRoot $datasetRelative
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($file in $manifest.files) {
        $path = Join-Path $datasetRoot ([string]$file.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "frozen dataset file missing: $path" }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne [string]$file.sha256 -or (Get-Item $path).Length -ne [long]$file.bytes) { throw "frozen dataset changed: $path" }
    }
    return [ordered]@{ manifestPath=$manifestRelative.Replace('\','/'); manifestSha256=(Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant(); identitySha256=[string]$manifest.baselineIdentitySha256 }
}

$v1Dataset = Assert-FrozenDataset 'artifacts\quanpin-evaluation\freeze-manifest.json' 'artifacts\quanpin-evaluation\dataset'
$v2Dataset = Assert-FrozenDataset 'artifacts\quanpin-lexicon-v2\freeze-manifest.json' 'artifacts\quanpin-lexicon-v2\dataset'

$relevant = @(
    'engine-rust\Cargo.lock',
    'engine-rust\tools\candidate-baseline\src\lib.rs',
    'engine-rust\tools\candidate-baseline\src\quanpin_evaluation.rs',
    'engine-rust\tools\lexicon-builder\src\parser.rs',
    'engine-rust\crates\ime-engine\tests\quanpin_lexicon_v2.rs',
    'dictionaries\source\quanpin-v2\base.tsv',
    'dictionaries\source\quanpin-v2\domains.tsv',
    'dictionaries\source\quanpin-v2\hotwords-2026-08.tsv',
    'dictionaries\source\quanpin-v2\filter-policy.txt',
    'dictionaries\source\quanpin-v2\source-catalog.json',
    'artifacts\quanpin-lexicon-v2\source-manifest.json',
    'artifacts\quanpin-lexicon-v2\build-manifest.json',
    'artifacts\quanpin-lexicon-v2\freeze-manifest.json',
    'dictionaries\generated\quanpin-v2\default.lex',
    'dictionaries\generated\quanpin-v2\all_domains.lex',
    'dictionaries\generated\quanpin-v2\education.lex',
    'dictionaries\generated\quanpin-v2\finance.lex',
    'dictionaries\generated\quanpin-v2\legal.lex',
    'dictionaries\generated\quanpin-v2\medical.lex',
    'dictionaries\generated\quanpin-v2\software.lex',
    'dictionaries\generated\quanpin-v2\technology.lex',
    'entry\src\main\resources\rawfile\production.lex',
    'entry\src\main\ets\infrastructure\resource\LexiconResourceInstaller.ets',
    'entry\src\internalDebug\ets\infrastructure\resource\CodeTableFixtureInstaller.ets',
    'scripts\build-quanpin-lexicon-v2.ps1',
    'scripts\create-quanpin-v2-dataset.ps1',
    'scripts\create-quanpin-v2-dataset-utf8.ps1',
    'scripts\evaluate-quanpin-lexicon-v2.ps1',
    'scripts\verify-release-hap.ps1',
    'scripts\test-quanpin-lexicon-v2.ps1'
)
$files = [Collections.Generic.List[object]]::new()
foreach ($relative in $relevant) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "implementation file missing: $relative" }
    $files.Add([ordered]@{ path=$relative.Replace('\','/'); bytes=(Get-Item $path).Length; sha256=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant() })
}
$identityLines = @($files | ForEach-Object { "$($_.path)`t$($_.bytes)`t$($_.sha256)" }) -join "`n"
$sha = [Security.Cryptography.SHA256]::Create()
try { $identity = ([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($identityLines)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
$production = Join-Path $repoRoot 'entry\src\main\resources\rawfile\production.lex'
$manifest = [ordered]@{
    schemaVersion='quanpin-v2-implementation-freeze/1'; frozenAt=(Get-Date).ToUniversalTime().ToString('o'); gitIdentityUsed=$false
    implementationIdentitySha256=$identity; previousV1Dataset=$v1Dataset; v2Dataset=$v2Dataset
    productionLexiconSha256=(Get-FileHash $production -Algorithm SHA256).Hash.ToLowerInvariant(); productionLexiconBytes=(Get-Item $production).Length
    defaultDomainsEnabled=@(); blindCommandRuns=3; files=@($files)
    mutationPolicy='After this freeze, blind may run exactly once with three internal repetitions. Any source, rule, binary, evaluator, test, or dataset change invalidates the blind result and requires a new version.'
}
New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
[IO.File]::WriteAllText($output, ($manifest | ConvertTo-Json -Depth 10), $utf8)
Write-Host "QUANPIN_V2_FREEZE=PASS identity=$identity output=$output"
