param(
    [switch]$SkipNative,
    [switch]$SkipHap,
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' })
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$evidenceDir = Join-Path $repoRoot 'docs\evidence\stage11_5'
New-Item -ItemType Directory -Force $evidenceDir | Out-Null
Start-Transcript -Path (Join-Path $evidenceDir 'verify-stage11_5.log') -Force | Out-Null
try {
    Push-Location $repoRoot
    try {
        & (Join-Path $PSScriptRoot 'build-lexicon.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'production lexicon build failed' }
        & cargo fmt --manifest-path engine-rust\Cargo.toml --all -- --check
        if ($LASTEXITCODE -ne 0) { throw 'cargo fmt failed' }
        & cargo clippy --manifest-path engine-rust\Cargo.toml --workspace --all-targets -- -D warnings
        if ($LASTEXITCODE -ne 0) { throw 'cargo clippy failed' }
        & cargo test --manifest-path engine-rust\Cargo.toml --workspace
        if ($LASTEXITCODE -ne 0) { throw 'cargo test failed' }
        if (-not $SkipNative) {
            & (Join-Path $PSScriptRoot 'build-native.ps1') -Abi all
            if ($LASTEXITCODE -ne 0) { throw 'Native dual ABI build failed' }
        }
        $hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'
        $env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
        & $hvigor --no-daemon --mode module -p module=entry@default test
        if ($LASTEXITCODE -ne 0) { throw 'ArkTS tests failed' }
        if (-not $SkipHap) {
            & (Join-Path $PSScriptRoot 'build-hap.ps1') -SkipRust -BuildMode release -DevEcoRoot $DevEcoRoot
            if ($LASTEXITCODE -ne 0) { throw 'HAP build failed' }
            & (Join-Path $PSScriptRoot 'verify-release-hap.ps1')
            if ($LASTEXITCODE -ne 0) { throw 'Release HAP verification failed' }
            $hap = Get-Item (Join-Path $repoRoot 'entry\build\artifacts\entry-release-unsigned.hap')
            $archive = Join-Path $repoRoot '.stage11_5_tmp\entry.zip'
            $expanded = Join-Path $repoRoot '.stage11_5_tmp\hap-expanded'
            Copy-Item $hap.FullName $archive -Force
            if (Test-Path $expanded) { Remove-Item $expanded -Recurse -Force }
            Expand-Archive -LiteralPath $archive -DestinationPath $expanded
            $packed = Get-ChildItem $expanded -Recurse -Filter production.lex | Select-Object -First 1
            if ($null -eq $packed -or $packed.Length -ne 3741328) { throw 'production lexicon missing or truncated in HAP' }
        }
    } finally { Pop-Location }
    Write-Host 'STAGE11_5_VERIFY_RESULT=PASS'
    Stop-Transcript | Out-Null
    exit 0
} catch {
    Write-Error $_
    Write-Host 'STAGE11_5_VERIFY_RESULT=FAIL'
    Stop-Transcript | Out-Null
    exit 1
}
