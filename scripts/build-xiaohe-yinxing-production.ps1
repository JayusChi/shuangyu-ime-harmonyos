param(
    [string]$ProjectRoot = '',
    [string]$OutputDirectory = '',
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
$projectPath = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
} else {
    [IO.Path]::GetFullPath($ProjectRoot)
}
$auditRoot = Join-Path $projectPath 'dictionaries\audit\xiaohe-yinxing'
$contract = Join-Path $auditRoot 'conversion_contract.json'
$sourceManifest = Join-Path $auditRoot 'source_manifest.json'
$commandPolicy = Join-Path $auditRoot 'command_policy.json'
$sanitizedConfiguration = Join-Path $auditRoot 'sanitized_configuration.json'
$outputPath = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $projectPath 'dictionaries\generated\xiaohe-yinxing-production'
} else {
    [IO.Path]::GetFullPath($OutputDirectory)
}
$bundle = Join-Path $outputPath 'xiaohe-yinxing-production.hsyx'

function Assert-Sha256([string]$Path, [string]$Expected, [string]$Code) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Code`: missing required file"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected) {
        throw "$Code`: frozen SHA-256 mismatch"
    }
}

Assert-Sha256 $sourceManifest 'bb39015d3e4cd2998a4e14b904f277171951ea459d1b24b42d264cac4b0f2ffa' 'SOURCE_MANIFEST_IDENTITY'
Assert-Sha256 $contract '2db0ef42190d3058f2404e9848185f6e4d85734bba1c6e18acc6c85fdf3380b6' 'CONVERSION_CONTRACT_IDENTITY'
Assert-Sha256 $sanitizedConfiguration 'ebc2b5f0ded084e18379e006af19885a2b022fdf51701b0bb3b896dc1cf39b7e' 'SANITIZED_CONFIGURATION_IDENTITY'

Push-Location (Join-Path $projectPath 'engine-rust')
try {
    if (-not $VerifyOnly) {
        & cargo run --quiet -p yinxing-converter -- build `
            --contract $contract `
            --source-manifest $sourceManifest `
            --command-policy $commandPolicy `
            --sanitized-configuration $sanitizedConfiguration `
            --source-root $projectPath `
            --output $outputPath
        if ($LASTEXITCODE -ne 0) { throw "CONVERTER_BUILD_FAILED: exit=$LASTEXITCODE" }
    }
    & cargo run --quiet -p yinxing-converter -- verify --bundle $bundle
    if ($LASTEXITCODE -ne 0) { throw "CONVERTER_VERIFY_FAILED: exit=$LASTEXITCODE" }
} finally {
    Pop-Location
}

$bundleItem = Get-Item -LiteralPath $bundle
$bundleHash = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host 'XIAOHE_YINXING_PRODUCTION_RESULT=PASS'
Write-Host "BUNDLE=$($bundleItem.FullName)"
Write-Host "BUNDLE_BYTES=$($bundleItem.Length)"
Write-Host "BUNDLE_SHA256=$bundleHash"
