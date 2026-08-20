param(
    [switch]$SkipNative,
    [switch]$SkipArkTS,
    [switch]$SkipHap,
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' })
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$manifest = Join-Path $repoRoot 'engine-rust\Cargo.toml'
$evidenceDir = Join-Path $repoRoot 'docs\evidence\lexicon-rules-phase2'
$tempDir = Join-Path $repoRoot '.phase2_tmp'
$production = Join-Path $repoRoot 'dictionaries\generated\production.lex'
$fixture = Join-Path $repoRoot 'engine-rust\tests\fixtures\user-lexicon\valid.txt'
New-Item -ItemType Directory -Force $evidenceDir | Out-Null
if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
New-Item -ItemType Directory -Force $tempDir | Out-Null
Start-Transcript -Path (Join-Path $evidenceDir 'verify-phase2.log') -Force | Out-Null

function Assert-LastExit([string]$message) {
    if ($LASTEXITCODE -ne 0) { throw $message }
}

try {
    Push-Location $repoRoot
    try {
        $before = Get-Item -LiteralPath $production
        $beforeSize = $before.Length
        $beforeHash = (Get-FileHash -LiteralPath $production -Algorithm SHA256).Hash

        & cargo fmt --manifest-path $manifest --all -- --check
        Assert-LastExit 'cargo fmt failed'
        & cargo clippy --manifest-path $manifest --workspace --all-targets -- -D warnings
        Assert-LastExit 'cargo clippy failed'
        & cargo test --manifest-path $manifest --workspace
        Assert-LastExit 'workspace tests failed'
        & cargo test --manifest-path $manifest -p user-lexicon
        Assert-LastExit 'user-lexicon tests failed'
        & cargo test --manifest-path $manifest -p ime-engine --test user_lexicon_cases
        Assert-LastExit 'ime-engine user lexicon tests failed'
        & cargo test --manifest-path $manifest -p ime-ffi
        Assert-LastExit 'ime-ffi tests failed'

        $imported = Join-Path $tempDir 'imported.txt'
        & cargo run --quiet --manifest-path $manifest -p user-lexicon-tool -- validate $fixture
        Assert-LastExit 'user lexicon validation failed'
        & cargo run --quiet --manifest-path $manifest -p user-lexicon-tool -- import $fixture $imported
        Assert-LastExit 'user lexicon import failed'
        & cargo run --quiet --manifest-path $manifest -p user-lexicon-tool -- validate $imported
        Assert-LastExit 'normalized user lexicon validation failed'

        & (Join-Path $PSScriptRoot 'verify-lexicon-order.ps1')
        Assert-LastExit 'phase 1 deterministic regression failed'
        & (Join-Path $PSScriptRoot 'build-lexicon.ps1')
        Assert-LastExit 'production lexicon rebuild failed'

        $after = Get-Item -LiteralPath $production
        $afterHash = (Get-FileHash -LiteralPath $production -Algorithm SHA256).Hash
        if ($beforeSize -ne $after.Length -or $beforeHash -ne $afterHash) {
            throw 'production lexicon size or SHA-256 changed'
        }

        & (Join-Path $PSScriptRoot 'test-rust.ps1')
        Assert-LastExit 'test-rust.ps1 failed'

        if (-not $SkipNative) {
            & (Join-Path $PSScriptRoot 'build-native.ps1') -Abi all
            Assert-LastExit 'Native dual ABI build failed'
        }
        if (-not $SkipArkTS) {
            $hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'
            $env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
            & $hvigor --no-daemon --mode module -p module=entry@default test
            Assert-LastExit 'ArkTS tests failed'
        }
        if (-not $SkipHap) {
            & (Join-Path $PSScriptRoot 'build-hap.ps1') -SkipRust -BuildMode release -DevEcoRoot $DevEcoRoot
            Assert-LastExit 'Release HAP build failed'
            & (Join-Path $PSScriptRoot 'verify-release-hap.ps1')
            Assert-LastExit 'Release HAP verification failed'

            $hap = Get-Item (Join-Path $repoRoot 'entry\build\artifacts\entry-release-unsigned.hap')
            $archive = Join-Path $tempDir 'entry.zip'
            $expanded = Join-Path $tempDir 'hap-expanded'
            Copy-Item -LiteralPath $hap.FullName -Destination $archive -Force
            Expand-Archive -LiteralPath $archive -DestinationPath $expanded
            $forbidden = Get-ChildItem -LiteralPath $expanded -Recurse | Where-Object {
                $_.Name -like '*user-lexicon*' -or $_.Name -eq 'valid.txt' -or $_.Name -eq 'invalid-marker.txt'
            }
            if ($forbidden.Count -gt 0) { throw 'Release HAP contains user lexicon test fixtures' }
        }

        Write-Host "PRODUCTION_SIZE=$($after.Length)"
        Write-Host "PRODUCTION_SHA256=$afterHash"
        Write-Host 'USER_LEXICON_FIXTURES_IN_HAP=0'
        Write-Host 'LEXICON_RULES_PHASE2_VERIFY_RESULT=PASS'
    } finally {
        Pop-Location
    }
    Stop-Transcript | Out-Null
    exit 0
} catch {
    Write-Error $_
    Write-Host 'LEXICON_RULES_PHASE2_VERIFY_RESULT=FAIL'
    Stop-Transcript | Out-Null
    exit 1
}
