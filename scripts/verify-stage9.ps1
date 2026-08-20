param(
    [switch]$SkipHap,
    [string]$DevEcoRoot = $(if ($env:DEVECO_STUDIO_ROOT) { $env:DEVECO_STUDIO_ROOT } else { 'C:\Program Files\Huawei\DevEco Studio' })
)

$ErrorActionPreference = 'Stop'
$script:Results = @()

function Add-Result {
    param([string]$Name, [string]$Result, [string]$Detail)
    $script:Results += [PSCustomObject]@{
        Step = $Name
        Result = $Result
        Detail = $Detail
    }
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host ''
    Write-Host "== $Name =="
    & $Action
    Add-Result -Name $Name -Result 'PASS' -Detail 'completed'
}

function Assert-FileExists {
    param([string]$Path, [string]$Message)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

function Assert-FileContains {
    param([string]$Path, [string]$Pattern, [string]$Message)
    $content = Get-Content -Encoding UTF8 -LiteralPath $Path -Raw
    if ($content -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-TreeNotContains {
    param(
        [string]$Root,
        [string]$Pattern,
        [string]$Message,
        [string[]]$Extensions = @('*')
    )
    $files = Get-ChildItem -LiteralPath $Root -Recurse -File |
        Where-Object {
            if ($Extensions -contains '*') {
                return $true
            }
            $Extensions -contains $_.Extension
        }
    foreach ($file in $files) {
        $content = Get-Content -Encoding UTF8 -LiteralPath $file.FullName -Raw
        if ($content -match $Pattern) {
            throw "$Message Match: $($file.FullName)"
        }
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$engineRoot = Join-Path $repoRoot 'engine-rust'
$stage9Fixture = Join-Path $engineRoot 'tests\fixtures\stage9_user_learning_cases.tsv'

Invoke-Step 'Environment check' {
    & (Join-Path $PSScriptRoot 'check-environment.ps1')
}

Invoke-Step 'Stage 9 required files' {
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\user-model\Cargo.toml') -Message 'user-model crate must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\user-model\src\model.rs') -Message 'user-model model module must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\user-model\src\persistence.rs') -Message 'user-model persistence module must exist'
    Assert-FileExists -Path (Join-Path $engineRoot 'crates\user-model\src\recovery.rs') -Message 'user-model recovery module must exist'
    Assert-FileExists -Path $stage9Fixture -Message 'stage9 fixture must exist'
    Assert-FileExists -Path (Join-Path $repoRoot 'docs\adr\0009-stage9-user-learning-model.md') -Message 'stage9 ADR must exist'
    Assert-FileContains -Path (Join-Path $engineRoot 'Cargo.toml') -Pattern 'crates/user-model' -Message 'workspace must contain user-model'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\ime-engine\Cargo.toml') -Pattern 'user-model' -Message 'ime-engine must depend on user-model'
    Assert-FileContains -Path (Join-Path $engineRoot 'crates\candidate-ranking\src\ranking_policy.rs') -Pattern 'rank_candidates_with_user_scores' -Message 'candidate-ranking must expose user-score ranking'
}

Invoke-Step 'Rust format' {
    Push-Location $engineRoot
    try {
        cargo fmt --check
        if ($LASTEXITCODE -ne 0) { throw "cargo fmt failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Rust clippy' {
    Push-Location $engineRoot
    try {
        cargo clippy --workspace --all-targets -- -D warnings
        if ($LASTEXITCODE -ne 0) { throw "cargo clippy failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'user-model tests' {
    Push-Location $engineRoot
    try {
        cargo test -p user-model
        if ($LASTEXITCODE -ne 0) { throw "user-model tests failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'candidate-ranking tests' {
    Push-Location $engineRoot
    try {
        cargo test -p candidate-ranking
        if ($LASTEXITCODE -ne 0) { throw "candidate-ranking tests failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'sentence-decoder tests' {
    Push-Location $engineRoot
    try {
        cargo test -p sentence-decoder
        if ($LASTEXITCODE -ne 0) { throw "sentence-decoder tests failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'ime-engine tests' {
    Push-Location $engineRoot
    try {
        cargo test -p ime-engine
        if ($LASTEXITCODE -ne 0) { throw "ime-engine tests failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'ime-ffi tests' {
    Push-Location $engineRoot
    try {
        cargo test -p ime-ffi
        if ($LASTEXITCODE -ne 0) { throw "ime-ffi tests failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Rust workspace tests' {
    Push-Location $engineRoot
    try {
        cargo test --workspace
        if ($LASTEXITCODE -ne 0) { throw "cargo test failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

Invoke-Step 'Rust x86_64 and arm64-v8a artifacts' {
    & (Join-Path $PSScriptRoot 'build-native.ps1') -Abi all
}

Invoke-Step 'ArkTS unit tests' {
    $hvigor = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.bat'
    if (-not (Test-Path -LiteralPath $hvigor)) {
        throw "hvigorw not found: $hvigor"
    }
    $env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
    Push-Location $repoRoot
    try {
        & $hvigor --no-daemon --mode module -p module=entry@default test
        if ($LASTEXITCODE -ne 0) { throw "ArkTS unit tests failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

if ($SkipHap) {
    Write-Host ''
    Write-Host '== C++/ArkTS/HAP build =='
    Write-Host 'SKIPPED HAP build by -SkipHap.'
    Add-Result -Name 'C++/ArkTS/HAP build' -Result 'SKIP' -Detail 'skipped by -SkipHap'
} else {
    Invoke-Step 'C++/ArkTS/HAP build' {
        & (Join-Path $PSScriptRoot 'build-hap.ps1') -SkipRust
    }
}

Invoke-Step 'Stage 9 architecture boundary checks' {
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\ets') -Pattern 'MAX_USER_WEIGHT|score_record|selection_count|last_selected_seq|candidate_hash|HUM9' -Message 'ArkTS must not contain user ranking or model persistence algorithms' -Extensions @('.ets', '.ts')
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main\cpp') -Pattern 'MAX_USER_WEIGHT|score_record|selection_count|last_selected_seq|candidate_hash|HUM9|checksum32|write_snapshot|read_snapshot' -Message 'C++ must not contain user model business algorithms or file parsing' -Extensions @('.cpp', '.h')
    Assert-TreeNotContains -Root (Join-Path $engineRoot 'crates\user-model\src') -Pattern '@kit|ohos|openharmony|IMEKit|inputMethodEngine' -Message 'user-model must not depend on HarmonyOS APIs' -Extensions @('.rs')
    Assert-TreeNotContains -Root (Join-Path $engineRoot 'crates\candidate-query\src') -Pattern 'user_model|user_model\.dat|write_snapshot|read_snapshot|File::create|fs::write' -Message 'candidate-query must not directly operate user model files' -Extensions @('.rs')
    Assert-TreeNotContains -Root (Join-Path $engineRoot 'crates\sentence-decoder\src') -Pattern 'user_model\.dat|write_snapshot|read_snapshot|File::create|fs::write' -Message 'sentence-decoder must not directly operate user model files' -Extensions @('.rs')
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main') -Pattern 'ohos.permission.INTERNET' -Message 'stage9 must not add network permission' -Extensions @('.json5', '.json', '.ets')
    Assert-TreeNotContains -Root (Join-Path $repoRoot 'entry\src\main') -Pattern 'rawInput_SENTINEL|password content|raw input content' -Message 'logs and app sources must not contain user input logging sentinels' -Extensions @('.ets', '.cpp', '.h', '.json5')
}

Invoke-Step 'Artifact summary' {
    $stage9FixtureItem = Get-Item -LiteralPath $stage9Fixture
    Write-Host "Stage 9 fixture: $($stage9FixtureItem.FullName)"
    Write-Host "Stage 9 fixture size: $($stage9FixtureItem.Length) bytes"

    $rustRoot = Join-Path $engineRoot 'target\ohos'
    if (Test-Path -LiteralPath $rustRoot) {
        Get-ChildItem -LiteralPath $rustRoot -Recurse -Filter *.a |
            Select-Object FullName, Length, LastWriteTime |
            Format-Table -AutoSize
    }

    if (-not $SkipHap) {
        $hap = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'entry\build') -Recurse -Filter *.hap |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $hap) {
            throw 'HAP artifact not found under entry\build.'
        }
        Write-Host "HAP: $($hap.FullName)"
        Write-Host "HAP size: $($hap.Length) bytes"
    }
}

Write-Host ''
Write-Host '== Stage 9 verification summary =='
$script:Results | Format-Table -AutoSize
Write-Host ''
Write-Host 'Stage 9 local verification completed. Device install and real input validation are not performed by this script.'
