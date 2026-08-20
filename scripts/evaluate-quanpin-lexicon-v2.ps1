[CmdletBinding()]
param(
    [ValidateSet('dev','blind')][string]$Split = 'dev',
    [ValidateSet('default','all_domains')][string]$Profile = 'all_domains',
    [ValidateRange(3,3)][int]$Runs = 3
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rustManifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'
$artifactRoot = Join-Path $repoRoot 'artifacts\quanpin-lexicon-v2'
$dataset = Join-Path $artifactRoot 'dataset'
$datasetManifest = Join-Path $artifactRoot 'freeze-manifest.json'
$implementationManifestPath = Join-Path $artifactRoot 'implementation-freeze-manifest.json'
$lexicon = Join-Path $repoRoot "dictionaries\generated\quanpin-v2\$Profile.lex"
$utf8 = [Text.UTF8Encoding]::new($false)

function Assert-ImplementationFreeze {
    if (-not (Test-Path -LiteralPath $implementationManifestPath -PathType Leaf)) { throw 'implementation freeze is required before blind' }
    $manifest = Get-Content -LiteralPath $implementationManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($file in $manifest.files) {
        $path = Join-Path $repoRoot ([string]$file.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "frozen implementation file missing: $path" }
        $hash = (Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne [string]$file.sha256 -or (Get-Item $path).Length -ne [long]$file.bytes) { throw "frozen implementation changed: $($file.path)" }
    }
    return $manifest
}

if ($Split -eq 'blind') {
    if ($Profile -ne 'all_domains' -or $Runs -ne 3) { throw 'blind requires all_domains and exactly three internal repetitions' }
    $implementation = Assert-ImplementationFreeze
    $results = Join-Path $artifactRoot 'post-change-blind-results.json'
    $failures = Join-Path $artifactRoot 'post-change-blind-failures.jsonl'
    $receipt = Join-Path $artifactRoot 'blind-run-receipt.json'
    foreach ($path in @($results,$failures,$receipt)) { if (Test-Path -LiteralPath $path) { throw "one-shot blind already attempted or output exists: $path" } }
} else {
    $devStem = if ($Profile -eq 'all_domains') { 'post-change-dev' } else { 'post-change-default-dev' }
    $results = Join-Path $artifactRoot "$devStem-results.json"
    $failures = Join-Path $artifactRoot "$devStem-failures.jsonl"
}

& cargo run --release -p candidate-baseline --manifest-path $rustManifest -- quanpin-evaluate $dataset $datasetManifest $lexicon $results $failures $Runs --split $Split --spelling-correction false --fuzzy-options false
if ($LASTEXITCODE -ne 0) { throw "V2 $Split evaluation failed: $LASTEXITCODE" }

if ($Split -eq 'blind') {
    $receiptData = [ordered]@{
        schemaVersion='quanpin-v2-blind-receipt/1'; executedAt=(Get-Date).ToUniversalTime().ToString('o'); runs=$Runs; profile=$Profile
        implementationIdentitySha256=[string]$implementation.implementationIdentitySha256
        datasetIdentitySha256=[string]$implementation.v2Dataset.identitySha256
        resultsSha256=(Get-FileHash $results -Algorithm SHA256).Hash.ToLowerInvariant(); failuresSha256=(Get-FileHash $failures -Algorithm SHA256).Hash.ToLowerInvariant()
        mutationPolicy='Result is final for this implementation identity; no post-blind tuning is permitted.'
    }
    [IO.File]::WriteAllText($receipt, ($receiptData | ConvertTo-Json -Depth 6), $utf8)
}
$summary = Get-Content -LiteralPath $results -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host ("QUANPIN_V2_EVAL=PASS split={0} samples={1} top1={2:P3} top3={3:P3} top5={4:P3} mrr={5:N6}" -f $Split,$summary.sampleCount,$summary.metrics.top1Rate,$summary.metrics.top3Rate,$summary.metrics.top5Rate,$summary.metrics.mrr)
